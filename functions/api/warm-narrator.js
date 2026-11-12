export async function onRequest({ request }) {
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  const upstream = await fetch("https://gtsdrmfvtialuxhfxtvz.supabase.co/functions/v1/cache-haunted-narrator", { method: "GET" });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff"
    }
  });
}
