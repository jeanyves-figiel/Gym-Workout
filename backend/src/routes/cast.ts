import { createReadStream, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';

/**
 * Chromecast receiver (#1008): the TV draws the workout itself, like any cast app (Netflix, YouTube). The iPhone only
 * sends small live-state messages over the Cast channel (`urn:x-cast:cloud.monkeygrade.workout`); the TV plays the
 * exercise's movement clip from this server. Nothing to install: the Chromecast loads this page when the member casts.
 *
 * `GET /cast/receiver`: the receiver page (registered as the Custom Receiver URL in the Google Cast console).
 * `GET /cast/motion/:file`: the light 60 fps movement clip of a catalog exercise (`motion-<id>.mp4`, the same files
 * the app bundles), copied into the image at build time (`CAST_MOTION_DIR`, default `content/motion`; locally the
 * app's resources).
 */
export const CAST_NAMESPACE = 'urn:x-cast:cloud.monkeygrade.workout';

const clipName = /^motion-[a-z0-9-]{1,80}\.mp4$/;

export const castRoutes = (app: FastifyInstance, motionDirs: string[]) => {
  app.get('/cast/receiver', async (_req, reply) =>
    reply
      .type('text/html; charset=utf-8')
      // The TV fetches it on every cast: a short cache keeps a fix rolling out within minutes.
      .header('cache-control', 'public, max-age=300')
      .send(RECEIVER_HTML),
  );

  app.get<{ Params: { file: string } }>('/cast/motion/:file', async (req, reply) => {
    const { file } = req.params;
    if (!clipName.test(file)) return reply.status(404).send({ error: 'not_found', message: 'No such clip.' });
    const path = motionDirs.map((d) => join(d, file)).find((p) => existsSync(p));
    if (!path) return reply.status(404).send({ error: 'not_found', message: 'No such clip.' });
    const size = statSync(path).size;
    reply.header('cache-control', 'public, max-age=86400').header('accept-ranges', 'bytes').header('access-control-allow-origin', '*');
    // The TV's video element asks for byte ranges.
    const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
    if (range && (range[1] || range[2])) {
      const start = range[1] ? Number(range[1]) : Math.max(0, size - Number(range[2]));
      const end = range[1] && range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
      if (start > end || start >= size) return reply.status(416).header('content-range', `bytes */${size}`).send();
      return reply
        .status(206)
        .type('video/mp4')
        .header('content-range', `bytes ${start}-${end}/${size}`)
        .header('content-length', end - start + 1)
        .send(createReadStream(path, { start, end }));
    }
    return reply.type('video/mp4').header('content-length', size).send(createReadStream(path));
  });
};

/**
 * The TV layout of the iPhone's TVPlayerView (design mix B + A, #724): movement full height on the category gradient,
 * big rest / work timer, SET / KG / REPS tiles, heart rate · time · %, one Up next bar. Everything sits in fixed places.
 * Sizes in vh (1vh = the iPhone layout's `u`). Timers count locally from the last message: no traffic per second.
 * The clip is stacked (colour on top, alpha as grey below) and masked in a WebGL shader.
 */
const RECEIVER_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>MonkeyWorkout</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@800;900&display=block" rel="stylesheet">
<script src="https://www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js"></script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100vw;height:100vh;overflow:hidden;background:#090a0e;color:#fff;font-family:Nunito,system-ui,sans-serif;font-weight:900}
#bg{position:absolute;inset:0;transition:background .6s}
#idle{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2vh;background:linear-gradient(135deg,#2F6BFF,#8A4DFF)}
#idle h1{font-size:9vh}#idle p{font-size:3.5vh;font-weight:800;opacity:.85}
#live{position:absolute;inset:0;display:none}
#motion{position:absolute;left:0;top:20vh;bottom:16vh;width:64%}
#motion canvas{width:100%;height:100%;display:block}
#glyph{position:absolute;inset:0;display:none;align-items:center;justify-content:center;font-size:30vh;opacity:.35}
#head{position:absolute;left:5vh;top:5vh;max-width:106vh}
#label{font-size:2.6vh;letter-spacing:.2em;opacity:.85;text-transform:uppercase}
#name{font-size:7vh;line-height:1.1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1.2vh}
#pos{font-size:2.8vh;opacity:.8;margin-top:1.2vh;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#side{position:absolute;right:5vh;top:5vh;width:calc(36% - 5vh);display:flex;flex-direction:column;gap:2.4vh}
#timer{background:rgba(0,0,0,.22);border-radius:3vh;padding:2.4vh 0;text-align:center}
#tval{font-size:15vh;line-height:1;font-variant-numeric:tabular-nums}
#tcap{font-size:2.8vh;letter-spacing:.2em;opacity:.85;margin-top:.4vh}
#tiles{display:flex;gap:1.6vh}
.tile{flex:1;border-radius:2.4vh;padding:1.8vh;color:#fff;border:.3vh solid rgba(255,255,255,.35);min-width:0}
.tile b{display:block;font-size:2.4vh;opacity:.85}
.tile span{font-size:8vh;line-height:1.05;white-space:nowrap}
.tile small{font-size:3.6vh;opacity:.75}
#stats{display:flex;justify-content:space-between;font-size:3.4vh;font-variant-numeric:tabular-nums}
#next{position:absolute;left:5vh;right:5vh;bottom:4vh;background:rgba(0,0,0,.35);border-radius:2.4vh;overflow:hidden;color:#fff}
#nrow{height:8vh;display:flex;align-items:center;gap:2vh;padding:0 2.4vh}
#nrow b{font-size:3vh;letter-spacing:.15em}
#ntext{font-size:3.4vh;font-weight:800;opacity:.85;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#bar{height:.6vh;background:rgba(255,255,255,.2)}#fill{height:100%;background:#fff;width:0;transition:width .6s}
</style></head><body>
<div id="idle"><h1>MonkeyWorkout</h1><p>Start a workout on your iPhone: it shows here.</p></div>
<div id="live">
  <div id="bg"></div>
  <div id="motion"><canvas id="cv"></canvas><div id="glyph">●</div></div>
  <div id="head"><div id="label"></div><div id="name"></div><div id="pos"></div></div>
  <div id="side">
    <div id="timer"><div id="tval">GO</div><div id="tcap"></div></div>
    <div id="tiles">
      <div class="tile" style="background:linear-gradient(135deg,#FF2D55,#FF6FB5)"><b>SET</b><span id="set"></span><small id="sets"></small></div>
      <div class="tile" style="background:linear-gradient(135deg,#A64DFF,#FF4DD8)"><b>KG</b><span id="kg"></span></div>
      <div class="tile" style="background:linear-gradient(135deg,#00C9A7,#2EC5FF)"><b>REPS</b><span id="reps"></span></div>
    </div>
    <div id="stats"><span id="hr"></span><span id="clock"></span><span id="pct"></span></div>
  </div>
  <div id="next"><div id="nrow"><b>UP NEXT</b><span id="ntext"></span></div><div id="bar"><div id="fill"></div></div></div>
</div>
<video id="clip" muted playsinline preload="auto" crossorigin="anonymous" style="display:none"></video>
<script>
const NS = '${CAST_NAMESPACE}';
const COLORS = {warmup:['#FF8A00','#FFC93D'],power:['#FF2D55','#FF6FB5'],strength:['#2F6BFF','#8A4DFF'],
  mobility:['#A64DFF','#FF4DD8'],cardio:['#00C9A7','#2EC5FF'],stretch:['#1ED98A','#B6FF6B']};
const $ = (id) => document.getElementById(id);
let live = null, at = 0;
const clockText = (t) => { const s = Math.ceil(Math.max(0, t)); const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60;
  return h ? h + ':' + String(m).padStart(2, '0') + ':' + String(x).padStart(2, '0') : m + ':' + String(x).padStart(2, '0'); };
const since = () => (performance.now() - at) / 1000;

function show(m) {
  live = m; at = performance.now();
  $('idle').style.display = m ? 'none' : 'flex';
  $('live').style.display = m ? 'block' : 'none';
  if (!m) return stopMotion();
  const c = COLORS[m.category] || COLORS.strength;
  $('bg').style.background = 'linear-gradient(135deg,' + c[0] + ',' + c[1] + ')';
  $('live').style.color = (m.category === 'warmup' || m.category === 'stretch') ? '#0A0D0F' : '#fff';
  $('label').textContent = m.label; $('name').textContent = m.name;
  $('pos').textContent = m.position + ' of ' + m.count + ' · ' + m.title;
  $('set').textContent = m.set; $('sets').textContent = '/' + m.sets;
  $('kg').textContent = m.kg || '–'; $('reps').textContent = m.reps;
  $('hr').textContent = '♥ ' + (m.heartRate || '–');
  $('pct').textContent = Math.round(m.progress * 100) + ' %';
  $('ntext').textContent = m.next; $('fill').style.width = Math.min(100, Math.max(0, m.progress * 100)) + '%';
  tick();
}

function tick() {
  if (!live) return;
  const t = since();
  let v = 'GO', cap = 'SET ' + live.set + ' OF ' + live.sets;
  if (live.restLeft != null) { v = clockText(live.restLeft - t); cap = 'REST'; }
  else if (live.workLeft != null) { v = clockText(live.workLeft - t); cap = 'WORK'; }
  $('tval').textContent = v; $('tcap').textContent = cap;
  $('clock').textContent = clockText(live.elapsed + t);
}
setInterval(tick, 250);

// Movement: the clip's pieces (start frame, frames, seconds) played one after another at the phone's tempo.
const video = $('clip'), canvas = $('cv');
const gl = canvas.getContext('webgl', {premultipliedAlpha: false, alpha: true});
let clipId = null, pieces = null, playAt = 0, playOffset = 0, ready = false;
const FPS = 60;
function setupGL() {
  if (!gl) return;
  const vs = 'attribute vec2 p;varying vec2 uv;void main(){uv=vec2((p.x+1.)/2.,(1.-p.y)/2.);gl_Position=vec4(p,0,1);}';
  const fs = 'precision mediump float;varying vec2 uv;uniform sampler2D t;void main(){vec3 c=texture2D(t,vec2(uv.x,uv.y*.5)).rgb;float a=texture2D(t,vec2(uv.x,.5+uv.y*.5)).r;gl_FragColor=vec4(c,a);}';
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; };
  const pr = gl.createProgram(); gl.attachShader(pr, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(pr); gl.useProgram(pr);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1,1,-1,-1,1,1,1]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(pr, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
  for (const k of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, k, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
}
setupGL();

function stopMotion() { pieces = null; video.pause(); }

function play(m) {
  if (!m.exerciseId) { clipId = null; ready = false; video.removeAttribute('src'); $('glyph').style.display = 'flex'; clear(); return; }
  $('glyph').style.display = 'none';
  if (clipId !== m.exerciseId) {
    clipId = m.exerciseId; ready = false;
    video.src = '/cast/motion/motion-' + m.exerciseId + '.mp4';
    video.load();
  }
  pieces = m.pieces; playOffset = m.offset || 0; playAt = performance.now();
}
video.addEventListener('loadeddata', () => { ready = true; draw(); });

function want() {
  if (!pieces) return null;
  let t = (performance.now() - playAt) / 1000 + playOffset;
  for (const [start, length, duration] of pieces) {
    if (t < duration) return {frame: start + (length > 1 ? length * t / duration : 0), rate: length > 1 ? (length / FPS) / duration : 0};
    t -= duration;
  }
  pieces = null;
  return null;
}

function clear() { if (gl) { gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); } }

function draw() {
  if (!gl || !ready || !video.videoWidth) return;
  const w = canvas.clientWidth * devicePixelRatio, h = canvas.clientHeight * devicePixelRatio;
  if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
  // Fit: the picture (half the clip's height) centred in the area.
  const pw = video.videoWidth, ph = video.videoHeight / 2, s = Math.min(w / pw, h / ph);
  const dw = pw * s, dh = ph * s;
  clear();
  gl.viewport((w - dw) / 2, (h - dh) / 2, dw, dh);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);
  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
}

function frame() {
  const p = want();
  if (ready && p) {
    const target = p.frame / FPS;
    if (p.rate === 0) {
      if (!video.paused) video.pause();
      if (Math.abs(video.currentTime - target) > 0.01) video.currentTime = target;
    } else {
      if (Math.abs(video.playbackRate - p.rate) > 0.01) video.playbackRate = p.rate;
      // Drifted (or just started): jump to the right picture, then the decoder plays on its own.
      if (video.paused || Math.abs(video.currentTime - target) > 0.12) video.currentTime = target;
      if (video.paused) video.play().catch(() => {});
    }
  } else if (ready && !video.paused) {
    video.pause();
  }
  if (live) draw();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

const context = cast.framework.CastReceiverContext.getInstance();
context.addCustomMessageListener(NS, (e) => {
  const m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
  if (m.type === 'state') show(m.live || null);
  if (m.type === 'play' && live) play(m);
  if (m.type === 'idle') show(null);
});
const options = new cast.framework.CastReceiverOptions();
options.disableIdleTimeout = true;
options.skipPlayersLoad = true;
options.customNamespaces = { [NS]: cast.framework.system.MessageType.JSON };
context.start(options);
</script></body></html>`;
