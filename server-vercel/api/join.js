// POST /api/join {g, code} -> {ok, epoch}: join a room. A room only counts as full once a match is live,
// so a guest can retry after a failed attempt; every join starts a fresh handshake ("epoch").
import { redis, reply, cors, TTL } from "./_store.js";
export const config = { runtime: "edge" };

export default async function handler(req) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const body = await req.json().catch(() => ({}));
  const g = String(body.g || "").slice(0, 12);
  const code = String(body.code || "").toUpperCase().trim().slice(0, 8);
  if (!(await redis("EXISTS", `room:${g}:${code}`))) return reply({ error: "Room not found" }, 404);
  if (await redis("EXISTS", `live:${g}:${code}`)) return reply({ error: "Room is full" }, 409);
  const epoch = await redis("INCR", `epoch:${g}:${code}`);
  await redis("EXPIRE", `epoch:${g}:${code}`, TTL);
  return reply({ ok: true, epoch });
}
