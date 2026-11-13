const CACHE='mimox-shell-v42';
const SHELL=['/','/manifest.webmanifest','/night-camp-icon.svg?v=20261113a','/night-camp-icon.svg','/mimox-icon-192.png'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('mimox-shell-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
 const request=event.request;if(request.method!=='GET')return;
 const url=new URL(request.url);if(url.origin!==self.location.origin)return;
 if(request.mode==='navigate'){
  event.respondWith(fetch(request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}return response;}).catch(async()=> (await caches.match(request))||(await caches.match('/'))));
  return;
 }
 event.respondWith(caches.match(request).then(cached=>{
  if(cached)return cached;
  return fetch(request).then(response=>{if(response.ok&&/.(?:js|css|woff2?|png|svg|webp|avif)$/.test(url.pathname)){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}return response;});
 }));
});
