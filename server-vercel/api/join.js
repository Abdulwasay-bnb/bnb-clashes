// POST /api/join {g, code} -> {ok}: claim the guest seat of a room.
import { redis, reply, cors, TTL } from "./_store.js";
export const config = { runtime: "edge" };

export default async function handler(req) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const body = await req.json().catch(() => ({}));
  const g = String(body.g || "").slice(0, 12);
  const code = String(body.code || "").toUpperCase().trim().slice(0, 8);
  if (!(await redis("EXISTS", `room:${g}:${code}`))) return reply({ error: "Room not found" }, 404);
  const ok = await redis("SET", `guest:${g}:${code}`, "1", "EX", TTL, "NX");
  if (ok !== "OK") return reply({ error: "Room is full" }, 409);
  return reply({ ok: true });
}
