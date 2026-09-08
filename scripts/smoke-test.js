"use strict";

const BASE = process.env.BASE_URL || "http://127.0.0.1:3000";
const TOKEN = process.env.ACCESS_TOKEN || "change-me";

async function main() {
  const health = await fetch(BASE + "/health");
  if (!health.ok) throw new Error("/health failed: " + health.status);
  console.log("health", await health.json());

  const unauth = await fetch(BASE + "/api/session");
  if (unauth.status !== 401) throw new Error("expected 401 without token, got " + unauth.status);
  console.log("unauth session -> 401 ok");

  const unauthStream = await fetch(BASE + "/stream.mjpg");
  if (unauthStream.status !== 401) throw new Error("expected 401 on stream, got " + unauthStream.status);
  try { await unauthStream.arrayBuffer(); } catch (_) {}
  console.log("unauth stream -> 401 ok");

  const session = await fetch(BASE + "/api/session", { headers: { Authorization: "Bearer " + TOKEN } });
  if (!session.ok) throw new Error("/api/session failed: " + session.status);
  console.log("session", await session.json());

  const ptz = await fetch(BASE + "/api/ptz/stop", { method: "POST", headers: { Authorization: "Bearer " + TOKEN } });
  if (!ptz.ok) throw new Error("ptz failed: " + ptz.status);
  console.log("ptz", await ptz.json());

  const snap = await fetch(BASE + "/api/snapshot", { headers: { Authorization: "Bearer " + TOKEN } });
  if (!snap.ok) throw new Error("snapshot failed: " + snap.status);
  const buf = Buffer.from(await snap.arrayBuffer());
  if (buf.length < 100 || buf[0] !== 0xff || buf[1] !== 0xd8) throw new Error("snapshot is not a JPEG");
  console.log("snapshot jpeg bytes", buf.length);

  const ac = new AbortController();
  const stream = await fetch(BASE + "/stream.mjpg?token=" + encodeURIComponent(TOKEN), { signal: ac.signal });
  if (!stream.ok) throw new Error("stream failed: " + stream.status);
  const reader = stream.body.getReader();
  const { value } = await reader.read();
  if (!value || value.length < 10) throw new Error("empty stream chunk");
  ac.abort();
  console.log("stream first chunk bytes", value.length);
  console.log("SMOKE OK");
}

main().catch((err) => { console.error(err); process.exit(1); });
