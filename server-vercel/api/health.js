import { reply } from "./_store.js";
export const config = { runtime: "edge" };
export default async function handler() {
  const store = Boolean(process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL);
  return reply({ ok: true, game: "bnb-clashes", store });
}
