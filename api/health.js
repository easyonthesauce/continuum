// Health probe the client hits on boot. `proxy: true` tells the client to
// route Venice calls through /api/venice (so no client key is needed).
// `save: false` because Vercel's filesystem is ephemeral — clips are saved
// client-side (share sheet / device storage / download).

export const config = { runtime: "edge" };

export default function handler() {
  return Response.json({
    save: false,
    maxSaveBytes: 0,
    proxy: Boolean(process.env.VENICE_API_KEY)
  });
}
