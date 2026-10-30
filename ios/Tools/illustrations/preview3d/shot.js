// node shot.js out.png W H name:yaw[:zoom] ...   -> grid of renders
const { chromium } = require('playwright'); const http=require('http'),fs=require('fs'),path=require('path');
(async()=>{
 const [outp,W,H,...specs]=process.argv.slice(2);
 const srv=http.createServer((q,r)=>{const f=path.join(__dirname,decodeURIComponent(q.url.split('?')[0]));fs.readFile(f,(e,d)=>{if(e){r.writeHead(404);r.end();return;}
  r.writeHead(200,{'Content-Type':f.endsWith('.js')?'text/javascript':f.endsWith('.html')?'text/html':'application/octet-stream'});r.end(d);});}).listen(0);
 const port=srv.address().port;
 const b=await chromium.launch({args:['--use-gl=swiftshader','--enable-webgl','--ignore-gpu-blocklist']});
 const cols=Math.min(specs.length,+process.env.COLS||4), rows=Math.ceil(specs.length/cols);
 const pg=await b.newPage({viewport:{width:+W*cols,height:+H*rows}});
 const shots=[];
 for(const s of specs){const [name,yaw,zoom,at]=s.split(':');
   await pg.goto(`http://localhost:${port}/view.html?w=${W}&h=${H}`); await pg.waitForFunction('window.ready');
   await pg.evaluate(([n,y,z,a])=>window.render(n,y,{zoom:z,at:a,joints:false}),[name,+yaw,+(zoom||1),at]);
   shots.push(await pg.locator('canvas').screenshot());}
 // compose via page
 await pg.setContent(`<body style="margin:0;display:grid;grid-template-columns:repeat(${cols},${W}px);background:#5a5df0">${shots.map((s,i)=>`<div style="position:relative"><img src="data:image/png;base64,${s.toString('base64')}"><span style="position:absolute;left:4px;top:2px;color:#fff;font:bold 12px sans-serif">${specs[i]}</span></div>`).join('')}</body>`);
 await pg.screenshot({path:outp,fullPage:true}); await b.close(); srv.close();
})();
