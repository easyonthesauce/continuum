# Continuum

A photograph, then the next 8 seconds. Grab a webcam frame, a director model
writes what happens *immediately after* the shutter, and MiniMax H3
image-to-video renders it. Runs as a static page plus two Edge functions.

## Layout

```
public/index.html            the whole app
public/manifest.webmanifest  PWA manifest
api/venice/[...path].js       Edge proxy → api.venice.ai (injects the key)
api/health.js                 boot probe; flips the client into proxy mode
```

## Deploy (Vercel)

No build step. Vercel serves `public/` statically and the `api/` folder as Edge
functions.

### The one thing you must set

Add an environment variable so the key stays server-side:

- **Key:** `VENICE_API_KEY`
- **Value:** your Venice API key (`sk-...`)
- **Environments:** Production (and Preview if you use it)

Then redeploy. Once it's set, `/api/health` returns `proxy: true`, the browser
routes every Venice call through `/api/venice`, and the key never reaches the
client.

Without the env var the app still loads — it falls back to asking for a key in
**Settings**, used directly from the browser (works, but exposes the key and
can hit CORS). Setting the env var is the intended path.

## Local dev

`npx vercel dev` from this folder, with `VENICE_API_KEY` in a `.env` file.

## Saving clips

Vercel's filesystem is ephemeral, so clips are saved on the client: a real
folder on desktop Chrome/Edge, the share sheet → Photos on iOS, device storage
(OPFS) otherwise, falling back to a normal download.
