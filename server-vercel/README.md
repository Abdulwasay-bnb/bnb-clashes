# BNB Clashes online server (Vercel)

Room codes and the WebRTC handshake. Matches run peer-to-peer, so this only sees a few small
messages per match. Needs an Upstash Redis store on the Vercel project (Vercel → Storage → Upstash, free).

Deploy: `vercel deploy --prod` from this folder.
