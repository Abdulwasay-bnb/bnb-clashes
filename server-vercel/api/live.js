// POST /api/live {g, code}: the host reports the match is connected, so later joins are refused.
import { redis, reply, cors, TTL } from "./_store.js";
export const config = { runtime: "edge" };

export default async function handler(req) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const b = await req.json().catch(() => ({}));
  const g = String(b.g || "").slice(0, 12), code = String(b.code || "").toUpperCase().slice(0, 8);
  await redis("SET", `live:${g}:${code}`, "1", "EX", TTL);
  return reply({ ok: true });
}
