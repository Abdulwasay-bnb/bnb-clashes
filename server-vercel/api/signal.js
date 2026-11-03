// WebRTC handshake mailbox. The match itself then runs directly between the two players.
//   POST /api/signal {g, code, to: "host"|"guest", msg}     -> {ok}
//   GET  /api/signal?g=&code=&for=host|guest&from=N         -> {msgs: [...], next: N}
import { redis, reply, cors, TTL } from "./_store.js";
export const config = { runtime: "edge" };

export default async function handler(req) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method === "POST") {
    const b = await req.json().catch(() => ({}));
    const g = String(b.g || "").slice(0, 12), code = String(b.code || "").toUpperCase().slice(0, 8);
    const to = b.to === "host" ? "host" : "guest";
    const msg = JSON.stringify(b.msg || {});
    if (msg.length > 16000) return reply({ error: "too big" }, 413);
    if (!(await redis("EXISTS", `room:${g}:${code}`))) return reply({ error: "Room not found" }, 404);
    const key = `sig:${g}:${code}:${to}`;
    await redis("RPUSH", key, msg);
    await redis("EXPIRE", key, TTL);
    return reply({ ok: true });
  }
  const u = new URL(req.url);
  const g = (u.searchParams.get("g") || "").slice(0, 12), code = (u.searchParams.get("code") || "").toUpperCase().slice(0, 8);
  const who = u.searchParams.get("for") === "host" ? "host" : "guest";
  const from = Math.max(0, parseInt(u.searchParams.get("from") || "0", 10) || 0);
  const list = (await redis("LRANGE", `sig:${g}:${code}:${who}`, from, -1)) || [];
  return reply({ msgs: list.map((s) => JSON.parse(s)), next: from + list.length });
}
