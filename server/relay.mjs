// BNB Clashes room relay: pairs two players by a short room code and forwards their messages.
//
//   client -> {"t":"create","v":1}            server -> {"t":"room","code":"K7QP2"}
//   client -> {"t":"join","code":"K7QP2","v":1} server -> {"t":"paired"} to both players
//   after pairing every message is forwarded to the other player untouched;
//   server -> {"t":"peer_left"} when the other player disconnects, {"t":"error","msg":...} on failures.
//
// Run: npm install && node relay.mjs   (PORT env var, default 8787). Any host with WebSockets works.
import http from "node:http";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.PORT || 8787);
const VERSION = 1;
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";   // no 0/O, 1/I/L
const ROOM_TTL_MS = 30 * 60 * 1000;                   // unjoined rooms expire
const MAX_MSG = 64 * 1024;
const MAX_ROOMS = 2000;

const rooms = new Map();   // game + code -> {host, guest, created}  (one server can host several games)

function newCode() {
  for (;;) {
    let c = "";
    for (let i = 0; i < 5; i++) c += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    if (!rooms.has(c)) return c;
  }
}

const send = (ws, obj) => ws.readyState === ws.OPEN && ws.send(JSON.stringify(obj));

const server = http.createServer((req, res) => {
  // health check for hosting platforms
  res.writeHead(200, { "content-type": "text/plain" });
  res.end(`bnb-clashes relay ok, ${rooms.size} rooms\n`);
});
const wss = new WebSocketServer({ server, maxPayload: MAX_MSG });

wss.on("connection", (ws) => {
  ws.room = null;
  ws.isAlive = true;
  ws.on("pong", () => (ws.isAlive = true));
  ws.on("message", (data, isBinary) => {
    const r = ws.room;
    if (r && r.host && r.guest) {
      const other = r.host === ws ? r.guest : r.host;
      if (other.readyState === other.OPEN) other.send(data, { binary: isBinary });
      return;
    }
    let m;
    try { m = JSON.parse(data.toString()); } catch { return; }
    if (m.v !== VERSION) return send(ws, { t: "error", msg: "Version mismatch: update the game" });
    if (m.t === "create" && !ws.room) {
      if (rooms.size >= MAX_ROOMS) return send(ws, { t: "error", msg: "Server full, try again later" });
      const g = String(m.g || "");
      let code;
      do { code = newCode(); } while (rooms.has(g + code));
      ws.room = { key: g + code, code, host: ws, guest: null, created: Date.now() };
      rooms.set(ws.room.key, ws.room);
      send(ws, { t: "room", code });
    } else if (m.t === "join" && !ws.room) {
      const code = String(m.code || "").toUpperCase().trim();
      const room = rooms.get(String(m.g || "") + code);
      if (!room) return send(ws, { t: "error", msg: "Room not found" });
      if (room.guest) return send(ws, { t: "error", msg: "Room is full" });
      room.guest = ws;
      ws.room = room;
      send(room.host, { t: "paired" });
      send(ws, { t: "paired" });
    }
  });
  ws.on("close", () => {
    const r = ws.room;
    if (!r) return;
    const other = r.host === ws ? r.guest : r.host;
    if (other) { send(other, { t: "peer_left" }); other.room = null; other.close(); }
    rooms.delete(r.key);
  });
});

// drop dead connections and stale rooms
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
  const now = Date.now();
  for (const [code, r] of rooms) {
    if (!r.guest && now - r.created > ROOM_TTL_MS) { r.host.close(); rooms.delete(code); }   // code here is the map key
  }
}, 15000);

server.listen(PORT, () => console.log(`relay listening on :${PORT}`));
