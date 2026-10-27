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