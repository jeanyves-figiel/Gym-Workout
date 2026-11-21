import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { FastifyInstance, FastifyRequest } from 'fastify';

/**
 * Rich share previews (#1113). The App Store's own link card only shows the icon, so the app shares our link instead:
 * - `GET /app`: landing page for "Share MonkeyWorkout". iMessage, WhatsApp, Slack and Instagram DMs show the big
 *   preview image (design A); the page has the Smart App Banner and an App Store button.
 * - `GET /og/:file`: the share art from `content/share` (rendered by `scripts/share-art/render.mjs`): `link.jpg`
 *   1200×630 link preview, `story.jpg` 1080×1920 Instagram story, `post.jpg` 1080×1080 feed post, `event.jpg`
 *   1920×1080 App Store In-App Event art (design C).
 * Invite (`/i/:code`) and public post (`/share/:id`) pages reuse `shareMeta` for the same preview image.
 */

export const SHARE_ART = ['link.jpg', 'story.jpg', 'post.jpg', 'event.jpg'] as const;

const art = new Map<string, Buffer>();
const dir = join(import.meta.dirname, '..', '..', 'content', 'share');
for (const f of SHARE_ART) if (existsSync(join(dir, f))) art.set(f, readFileSync(join(dir, f)));

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** This server's public origin as the caller reached it (Fly terminates TLS; trustProxy keeps https). */
export const publicOrigin = (req: FastifyRequest) => `${req.protocol}://${req.host}`;

/** Open Graph + Twitter tags with the link preview image; previews need an absolute image URL. */
export const shareMeta = (req: FastifyRequest, title: string, description: string) => {
  const img = `${publicOrigin(req)}/og/link.jpg`;
  return `<meta property="og:type" content="website"><meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}"><meta property="og:image" content="${img}">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:image:alt" content="MonkeyWorkout: your gym week, built around your machines">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="${img}">`;
};

export const appShareRoutes = (app: FastifyInstance, appName: string, appStoreId: string) => {
  const storeUrl = `https://apps.apple.com/app/id${appStoreId}`;

  app.get<{ Params: { file: string } }>('/og/:file', async (req, reply) => {
    const body = art.get(req.params.file);
    if (!body) return reply.status(404).send({ error: 'not_found', message: 'No such image.' });
    return reply.type('image/jpeg').header('cache-control', 'public, max-age=86400').send(body);
  });

  app.get('/app', async (req, reply) => {
    const title = `${appName}: gym plans, AI Coach, Apple Watch`;
    const desc = 'Your gym week, built around your machines. Free on the App Store.';
    reply.header('Content-Type', 'text/html; charset=utf-8').header('cache-control', 'public, max-age=300')
      .header('Content-Security-Policy', "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'");
    return reply.send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="description" content="${esc(desc)}"><meta name="apple-itunes-app" content="app-id=${esc(appStoreId)}">
<meta property="og:url" content="${publicOrigin(req)}/app">${shareMeta(req, title, desc)}
<style>body{margin:0;min-height:100vh;background:linear-gradient(120deg,#FF2D87,#FF6A3C 55%,#FFB03C);color:#fff;font-family:-apple-system,system-ui,sans-serif;display:flex;justify-content:center;align-items:center;padding:24px;box-sizing:border-box}
.c{max-width:520px;width:100%}h1{font-size:44px;font-weight:900;line-height:1;letter-spacing:-1px;margin:18px 0 14px}.k{font-weight:900;font-size:22px}
p{font-size:17px;opacity:.95}a{display:inline-block;margin-top:18px;background:#C8FF3C;color:#111;font-weight:900;font-size:18px;border-radius:16px;padding:14px 26px;text-decoration:none}
img{width:100%;border-radius:22px;margin-top:22px;box-shadow:0 20px 50px #0004}</style></head>
<body><div class="c"><div class="k">${esc(appName)}</div><h1>Your gym week, built around your machines.</h1>
<p>Plans for your gym's machines, an AI Coach that adapts, and Apple Watch tracking with zero typing.</p>
<a href="${storeUrl}">Free on the App Store</a><img src="/og/post.jpg" alt=""></div></body></html>`);
  });
};
