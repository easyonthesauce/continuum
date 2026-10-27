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