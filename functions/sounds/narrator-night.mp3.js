const SOURCE_URL = "https://elevenlabsusercontent.com/database/workspace/f3f06a9ba5254bbc92d7d9f57821a322/content_generation/WaOOEWCuXqpxXMSVFvyt/ZQfdaiBEqzugzikNiZex/content.mp3?Expires=1794513600&KeyName=assets-cdn-key-1&Signature=_iVlQKrXe4HDDKzFU1vUKd42X5w=";

export async function onRequest({ request, ctx }) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const cacheUrl = new URL(request.url); cacheUrl.searchParams.set('asset-version','2');
  const cacheKey = new Request(cacheUrl.toString(), { method: "GET" });
  const cache = caches.default;
  let response = await cache.match(cacheKey);
  if (!response) {
    const upstream = await fetch(SOURCE_URL, { headers: { Accept: "audio/mpeg" } });
    if (!upstream.ok) {
      return new Response("Narrator audio is temporarily unavailable.", {
        status: 502,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" }
      });
    }
    response = new Response(upstream.body, {
      headers: {
        "Content-Type": "audio/mpeg",
        "Cache-Control": "public, max-age=31536000, s-maxage=31536000, immutable",
        "Access-Control-Allow-Origin": "*",
        "Cross-Origin-Resource-Policy": "cross-origin",
        "X-Content-Type-Options": "nosniff"
      }
    });
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
  }
  if (request.method === "HEAD") return new Response(null, { status: response.status, headers: response.headers });
  return response;
}
