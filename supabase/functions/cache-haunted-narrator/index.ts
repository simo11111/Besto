import { createClient } from "jsr:@supabase/supabase-js@2";
const SOURCE_URL = "https://elevenlabsusercontent.com/database/workspace/f3f06a9ba5254bbc92d7d9f57821a322/content_generation/WaOOEWCuXqpxXMSVFvyt/ZQfdaiBEqzugzikNiZex/content.mp3?Expires=1794513600&KeyName=assets-cdn-key-1&Signature=_iVlQKrXe4HDDKzFU1vUKd42X5w=";
const BUCKET = "game-assets";
const OBJECT_PATH = "audio/narrator-night-v2.mp3";
Deno.serve(async (request: Request) => {
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  const supabaseUrl = Deno.env.get("SUPABASE_URL"), serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return Response.json({ error: "Storage service is not configured." }, { status: 500 });
  const client = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const publicUrl = client.storage.from(BUCKET).getPublicUrl(OBJECT_PATH).data.publicUrl;
  const existing = await client.storage.from(BUCKET).list("game-audio", { search: "narrator-night.mp3" });
  if (existing.data?.some(file => file.name === "narrator-night.mp3")) return Response.json({ ready: true, url: publicUrl, cached: true }, { headers: { "Cache-Control": "public, max-age=3600" } });
  const upstream = await fetch(SOURCE_URL, { headers: { Accept: "audio/mpeg" } });
  if (!upstream.ok) return Response.json({ error: "Narrator source is temporarily unavailable." }, { status: 502 });
  const audio = new Uint8Array(await upstream.arrayBuffer());
  const uploaded = await client.storage.from(BUCKET).upload(OBJECT_PATH, audio, { contentType: "audio/mpeg", cacheControl: "31536000", upsert: true });
  if (uploaded.error) return Response.json({ error: uploaded.error.message }, { status: 500 });
  return Response.json({ ready: true, url: publicUrl, cached: false, bytes: audio.byteLength }, { headers: { "Cache-Control": "public, max-age=3600" } });
});
