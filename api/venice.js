// Edge proxy for the Venice API.
// The browser calls /api/venice/<whatever> (rewritten here by vercel.json,
// since [...path] catch-alls only work in Next.js) and this forwards it to
// https://api.venice.ai/api/v1/<whatever>, injecting the server-side key so
// VENICE_API_KEY never ships to the client. Streams responses (incl. video).

export const config = { runtime: "edge" };

const VENICE = "https://api.venice.ai/api/v1";

export default async function handler(req) {
  const key = process.env.VENICE_API_KEY;
  const url = new URL(req.url);
  const rewritten = url.searchParams.get("__path");
  url.searchParams.delete("__path");
  const path = rewritten !== null ? "/" + rewritten : url.pathname.replace(/^\/api\/venice/, "");
  const tail = path + url.search;

  const headers = new Headers();
  headers.set("Content-Type", req.headers.get("content-type") || "application/json");
  // Prefer the server-side key; fall back to a client-supplied key if present.
  if (key) headers.set("Authorization", "Bearer " + key);
  else if (req.headers.get("authorization")) headers.set("Authorization", req.headers.get("authorization"));

  if (!key && !req.headers.get("authorization")) {
    return Response.json(
      { error: "No Venice API key. Set VENICE_API_KEY in Vercel env, or enter a key in Settings." },
      { status: 401 }
    );
  }

  const init = { method: req.method, headers };
  if (req.method !== "GET" && req.method !== "HEAD") init.body = await req.arrayBuffer();

  let upstream;
  try {
    upstream = await fetch(VENICE + tail, init);
  } catch (e) {
    return Response.json({ error: "Upstream fetch failed: " + (e?.message || e) }, { status: 502 });
  }

  const respHeaders = new Headers();
  const ct = upstream.headers.get("content-type");
  if (ct) respHeaders.set("content-type", ct);
  const cd = upstream.headers.get("content-disposition");
  if (cd) respHeaders.set("content-disposition", cd);

  return new Response(upstream.body, { status: upstream.status, headers: respHeaders });
}
