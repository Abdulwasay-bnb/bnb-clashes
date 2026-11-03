// Tiny Redis helper over Upstash's REST API (added to the Vercel project through the Upstash integration).
const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;

export async function redis(...cmd) {
  if (!URL_ || !TOKEN) throw new Error("Redis store not configured");
  const r = await fetch(URL_, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify(cmd),
  });
  const j = await r.json();
  if (j.error) throw new Error(j.error);
  return j.result;
}

export const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "content-type",
  "content-type": "application/json",
};

export const reply = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: cors });

export const TTL = 900;   // rooms and their signalling messages expire after 15 minutes
