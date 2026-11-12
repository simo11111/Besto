import { createClient } from "jsr:@supabase/supabase-js@2";
const SOURCE_URL = "https://elevenlabsusercontent.com/database/workspace/f3f06a9ba5254bbc92d7d9f57821a322/content_generation/h5vf8L7tfZqGxUbeHlHx/a5GgSsKGrTPpuEa9qNjc/content.png?Expires=1794513600&KeyName=assets-cdn-key-1&Signature=opcJWngPJED_OvRDIJVcivH34us=";
const BUCKET = "avatars";
const OBJECT_PATH = "game-assets/haunted-anime-sprites-v1.png";
Deno.serve(async (request: Request) => {
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  const supabaseUrl = Deno.env.get("SUPABASE_URL"), serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return Response.json({ error: "Storage service is not configured." }, { status: 500 });
  const client = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const publicUrl = client.storage.from(BUCKET).getPublicUrl(OBJECT_PATH).data.publicUrl;
  const existing = await client.storage.from(BUCKET).list("game-assets", { search: "haunted-anime-sprites-v1.png" });
  if (existing.data?.some(file => file.name === "haunted-anime-sprites-v1.png")) return Response.json({ ready: true, url: publicUrl, cached: true }, { headers: { "Cache-Control": "public, max-age=3600" } });
  const upstream = await fetch(SOURCE_URL, { headers: { Accept: "image/png" } });
  if (!upstream.ok) return Response.json({ error: "Anime character source is temporarily unavailable." }, { status: 502 });
  const image = new Uint8Array(await upstream.arrayBuffer());
  const uploaded = await client.storage.from(BUCKET).upload(OBJECT_PATH, image, { contentType: "image/png", cacheControl: "31536000", upsert: true });
  if (uploaded.error) return Response.json({ error: uploaded.error.message }, { status: 500 });
  return Response.json({ ready: true, url: publicUrl, cached: false, bytes: image.byteLength }, { headers: { "Cache-Control": "public, max-age=3600" } });
});
