#!/usr/bin/env bash
set -euo pipefail

DIR="${1:-continuum}"
mkdir -p "$DIR/api/venice" "$DIR/public"
cd "$DIR"

cat > vercel.json <<'__VERCEL__'
{
  "rewrites": [
    { "source": "/venice/:path*", "destination": "/api/venice/:path*" }
  ],
  "functions": {
    "api/**/*.js": { "maxDuration": 60 }
  },
  "regions": ["iad1"],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "Permissions-Policy", "value": "camera=(self)" },
        { "key": "Referrer-Policy", "value": "no-referrer" },
        { "key": "Cache-Control", "value": "no-store" }
      ]
    }
  ]
}
__VERCEL__

cat > api/health.js <<'__HEALTH__'
export default function handler(req, res) {
  res.setHeader("cache-control", "no-store");
  res.status(200).json({
    ok: true,
    runtime: "vercel",
    proxy: true,
    save: !!process.env.BLOB_READ_WRITE_TOKEN,
    maxSaveBytes: 3_200_000
  });
}
__HEALTH__

cat > 'api/venice/[...path].js' <<'__PROXY__'
import { Readable } from "node:stream";

export const config = { runtime: "nodejs", maxDuration: 60 };

const UPSTREAM = "https://api.venice.ai/api/v1";
const SKIP = new Set(["host","origin","referer","connection","content-length",
                      "accept-encoding","transfer-encoding","keep-alive"]);

export default async function handler(req, res) {
  if (req.method === "OPTIONS") {
    return res.status(204)
      .setHeader("access-control-allow-origin", "*")
      .setHeader("access-control-allow-headers", "*")
      .setHeader("access-control-allow-methods", "GET,POST,PUT,DELETE,OPTIONS")
      .end();
  }

  const segs = req.query.path;
  const path = "/" + (Array.isArray(segs) ? segs.join("/") : segs || "");
  const qs = req.url.includes("?") ? req.url.slice(req.url.indexOf("?")) : "";

  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) if (!SKIP.has(k)) headers[k] = v;
  if (!headers.authorization && process.env.VENICE_API_KEY) {
    headers.authorization = "Bearer " + process.env.VENICE_API_KEY;
  }

  let body;
  if (!["GET", "HEAD"].includes(req.method)) {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    if (chunks.length) body = Buffer.concat(chunks);
  }

  const up = await fetch(UPSTREAM + path + qs, { method: req.method, headers, body });

  res.statusCode = up.status;
  res.setHeader("content-type", up.headers.get("content-type") || "application/octet-stream");
  res.setHeader("cache-control", "no-store");
  res.setHeader("access-control-allow-origin", "*");

  if (!up.body) return res.end();
  Readable.fromWeb(up.body).pipe(res);
}
__PROXY__

cat > manifest.webmanifest <<'__MANIFEST__'
{
  "name": "Continuum",
  "short_name": "Continuum",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0a0b0f",
  "theme_color": "#0a0b0f",
  "icons": [{ "src": "/icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any" }]
}
__MANIFEST__

cat > icon.svg <<'__ICON__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 180">
  <rect width="180" height="180" rx="40" fill="#0a0b0f"/>
  <circle cx="90" cy="90" r="46" fill="none" stroke="#5eead4" stroke-width="7"/>
  <circle cx="90" cy="90" r="17" fill="#5eead4"/>
  <path d="M90 30v16M90 134v16M30 90h16M134 90h16" stroke="#a78bfa" stroke-width="7" stroke-linecap="round"/>
</svg>
__ICON__

cat > server.mjs <<'__SERVER__'
#!/usr/bin/env node
/**
 * CONTINUUM local server — zero dependencies (Node 20+).
 *   node server.mjs [port]
 * Serves index.html, proxies /venice/* -> https://api.venice.ai/api/v1/*,
 * and writes finished clips into ./captures/YYYY-MM-DD/.
 *
 * Optional HTTPS (required for the camera on a phone over the LAN):
 *   openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 825 \
 *     -subj "/CN=continuum.local" -addext "subjectAltName=DNS:localhost,IP:$(ipconfig getifaddr en0)"
 *   TLS_KEY=key.pem TLS_CERT=cert.pem VENICE_API_KEY=sk-... node server.mjs
 */
import http from "node:http";
import https from "node:https";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(ROOT, "captures");
const PORT = Number(process.argv[2] || process.env.PORT || 8787);
const UPSTREAM = "https://api.venice.ai/api/v1";
const MIME = {".html":"text/html; charset=utf-8",".js":"text/javascript",".css":"text/css",
  ".mp4":"video/mp4",".jpg":"image/jpeg",".png":"image/png",".webp":"image/webp",
  ".json":"application/json",".webmanifest":"application/manifest+json",".svg":"image/svg+xml"};

const readBody = (req) => new Promise((res, rej) => {
  const chunks = []; req.on("data", c => chunks.push(c));
  req.on("end", () => res(Buffer.concat(chunks))); req.on("error", rej);
});
const safeJoin = (base, rel) => {
  const p = path.normalize(path.join(base, rel));
  if (!p.startsWith(base)) throw new Error("path escape: " + rel);
  return p;
};
const json = (res, code, obj) => {
  res.writeHead(code, {"Content-Type":"application/json","Access-Control-Allow-Origin":"*"});
  res.end(JSON.stringify(obj));
};

const handler = async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (req.method === "OPTIONS") {
      return res.writeHead(204, {"Access-Control-Allow-Origin":"*",
        "Access-Control-Allow-Headers":"*","Access-Control-Allow-Methods":"GET,POST,PUT,DELETE,OPTIONS"}).end();
    }

    if (url.pathname === "/api/health") return json(res, 200, {ok:true, runtime:"node", proxy:true, save:true, captures:OUT});

    if (url.pathname === "/api/save" && req.method === "POST") {
      const body = JSON.parse((await readBody(req)).toString("utf8"));
      const target = safeJoin(OUT, body.path);
      await fs.mkdir(path.dirname(target), {recursive:true});
      await fs.writeFile(target, Buffer.from(body.data, "base64"));
      if (body.still && body.stillPath) {
        const sp = safeJoin(OUT, body.stillPath);
        await fs.mkdir(path.dirname(sp), {recursive:true});
        await fs.writeFile(sp, Buffer.from(body.still, "base64"));
      }
      if (body.manifest) {
        await fs.appendFile(safeJoin(OUT, path.join(path.dirname(body.path), "manifest.jsonl")), body.manifest);
      }
      console.log("saved", body.path);
      return json(res, 200, {ok:true, path:body.path});
    }

    if (url.pathname.startsWith("/venice/")) {
      const target = UPSTREAM + url.pathname.slice("/venice".length) + url.search;
      const headers = {...req.headers};
      for (const k of ["host","origin","referer","content-length","accept-encoding","connection"]) delete headers[k];
      if (!headers.authorization && process.env.VENICE_API_KEY) headers.authorization = "Bearer " + process.env.VENICE_API_KEY;
      const body = ["GET","HEAD"].includes(req.method) ? undefined : await readBody(req);
      const up = await fetch(target, {method:req.method, headers, body});
      res.writeHead(up.status, {
        "Content-Type": up.headers.get("content-type") || "application/octet-stream",
        "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"
      });
      return res.end(Buffer.from(await up.arrayBuffer()));
    }

    let file = url.pathname === "/" ? "/index.html" : url.pathname;
    const full = safeJoin(ROOT, file.replace(/^\//, ""));
    const data = await fs.readFile(full);
    res.writeHead(200, {"Content-Type": MIME[path.extname(full)] || "application/octet-stream"});
    res.end(data);
  } catch (e) {
    if (e.code === "ENOENT") return json(res, 404, {error:"not found"});
    console.error(e);
    json(res, 500, {error:e.message});
  }
};

const tls = process.env.TLS_KEY && process.env.TLS_CERT;
const server = tls
  ? https.createServer({key: await fs.readFile(process.env.TLS_KEY), cert: await fs.readFile(process.env.TLS_CERT)}, handler)
  : http.createServer(handler);

server.listen(PORT, "0.0.0.0", () => {
  console.log(`\n  CONTINUUM  ->  ${tls ? "https" : "http"}://localhost:${PORT}`);
  console.log(`  clips land ->  ${OUT}`);
  console.log(process.env.VENICE_API_KEY ? "  using VENICE_API_KEY from the environment\n" : "  add your API key in the app's Settings panel\n");
});
__SERVER__

cat > README.md <<'__README__'
# CONTINUUM

A webcam frame becomes the next few seconds of video, via MiniMax H3 image-to-video on the Venice API.

Pick a mode (Boring / Luck / Murphy's Law / Funny / Serious / Custom), optionally arm the 18+ layer,
shoot. Each shot is queued first-come-first-served, directed by a vision model, rendered, and saved with
a name that describes the scene.

## Run locally

    VENICE_API_KEY=sk-... node server.mjs
    # open http://localhost:8787

Clips are written to ./captures/YYYY-MM-DD/NNN-scene-slug.mp4 with a manifest.jsonl.

For the camera on a phone over the LAN you need HTTPS:

    openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 825 \
      -subj "/CN=continuum.local" -addext "subjectAltName=DNS:localhost,IP:$(ipconfig getifaddr en0)"
    TLS_KEY=key.pem TLS_CERT=cert.pem VENICE_API_KEY=sk-... node server.mjs

Then open https://<your-lan-ip>:8787 on the phone and trust the cert once.

## Deploy to Vercel

    npm i -g vercel
    vercel link
    vercel env add VENICE_API_KEY production
    vercel --prod

The key stays server-side in the /venice proxy. On iOS, clips are saved to Photos via the share sheet
(and kept in device storage); desktop Chrome/Edge can still write to a real folder.

## Save ladder

First available wins: desktop folder -> server disk (./captures) -> device storage (OPFS) ->
share sheet -> Downloads. The header badge shows which is live.

## Optional

Add `@vercel/blob` and a BLOB_READ_WRITE_TOKEN to persist clips on the server. Note the 4.5 MB
function body limit versus base64's 33% inflation: clips over ~3.2 MB fall back to the share sheet.
__README__

printf '\n  Created:\n'
find . -type f -not -path './captures/*' | sort | sed 's|^\./|    |'
printf '\n  Next:\n'
printf '    cd %s\n' "$DIR"
printf '    VENICE_API_KEY=sk-... node server.mjs\n\n'
