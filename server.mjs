#!/usr/bin/env node
import http from "node:http";
import https from "node:https";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(ROOT, "captures");
const PORT = Number(process.argv[2] || process.env.PORT || 8787);
const UPSTREAM = "https://api.venice.ai/api/v1";
const MIME = {".html":"text/html; charset=utf-8",".js":"text/javascript",".css":"text/css",
  ".mp4":"video/mp4",".jpg":"image/jpeg",".png":"image/png",".webp":"image/webp",
  ".json":"application/json",".webmanifest":"application/manifest+json",".svg":"image/svg+xml",".pem":"application/x-pem-file"};

const readBody = (req) => new Promise((res, rej) => {
  const chunks = []; req.on("data", c => chunks.push(c));
  req.on("end", () => res(Buffer.concat(chunks))); req.on("error", rej);
});
const safeJoin = (base, rel) => {
  const p = path.resolve(base, rel);
  const r = path.relative(base, p);
  if (r.startsWith("..") || path.isAbsolute(r)) throw new Error("path escape: " + rel);
  return p;
};
const json = (res, code, obj) => {
  res.writeHead(code, {"Content-Type":"application/json","Access-Control-Allow-Origin":"*"});
  res.end(JSON.stringify(obj));
};
function lanUrls(port, tls) {
  const out = [];
  for (const list of Object.values(os.networkInterfaces()))
    for (const i of list || [])
      if (i.family === "IPv4" && !i.internal) out.push(`${tls ? "https" : "http"}://${i.address}:${port}`);
  return out;
}

const handler = async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (req.method === "OPTIONS") {
      return res.writeHead(204, {"Access-Control-Allow-Origin":"*",
        "Access-Control-Allow-Headers":"*","Access-Control-Allow-Methods":"GET,POST,PUT,DELETE,OPTIONS"}).end();
    }

    if (url.pathname === "/api/health")
      return json(res, 200, {ok:true, runtime:"node", proxy:true, save:true, captures:OUT});

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
      if (body.manifest)
        await fs.appendFile(safeJoin(OUT, path.join(path.dirname(body.path), "manifest.jsonl")), body.manifest);
      console.log("saved", body.path);
      return json(res, 200, {ok:true, path:body.path});
    }

    if (url.pathname.startsWith("/venice/")) {
      const target = UPSTREAM + url.pathname.slice("/venice".length) + url.search;
      const headers = {...req.headers};
      for (const k of ["host","origin","referer","content-length","accept-encoding","connection"]) delete headers[k];
      if (!headers.authorization && process.env.VENICE_API_KEY)
        headers.authorization = "Bearer " + process.env.VENICE_API_KEY;
      const body = ["GET","HEAD"].includes(req.method) ? undefined : await readBody(req);
      const up = await fetch(target, {method:req.method, headers, body});
      res.writeHead(up.status, {
        "Content-Type": up.headers.get("content-type") || "application/octet-stream",
        "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"
      });
      return res.end(Buffer.from(await up.arrayBuffer()));
    }

    const file = url.pathname === "/" ? "/index.html" : url.pathname;
    const full = safeJoin(ROOT, decodeURIComponent(file.replace(/^\//, "")));
    const data = await fs.readFile(full);
    res.writeHead(200, {"Content-Type": MIME[path.extname(full).toLowerCase()] || "application/octet-stream"});
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
  for (const u of lanUrls(PORT, !!tls)) console.log(`  on a phone ->  ${u}`);
  console.log(`  clips land ->  ${OUT}`);
  console.log(process.env.VENICE_API_KEY ? "  using VENICE_API_KEY from the environment\n" : "  add your API key in the app's Settings panel\n");
});