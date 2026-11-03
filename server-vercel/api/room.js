// POST /api/room {g} -> {code}: create a room. The host then waits for a guest's handshake.
import { redis, reply, cors, TTL } from "./_store.js";
export const config = { runtime: "edge" };
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export default async function handler(req) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return reply({ error: "POST only" }, 405);
  const body = await req.json().catch(() => ({}));
  const g = String(body.g || "").slice(0, 12);
  for (let tries = 0; tries < 8; tries++) {
    let code = "";
    for (let i = 0; i < 5; i++) code += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    const ok = await redis("SET", `room:${g}:${code}`, "1", "EX", TTL, "NX");
    if (ok === "OK") return reply({ code });
  }
  return reply({ error: "Server busy, try again" }, 503);
}
