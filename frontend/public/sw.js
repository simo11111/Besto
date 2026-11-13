const CACHE='night-camp-shell-v44';
const SHELL=['/','/manifest.webmanifest','/night-camp-icon.svg?v=20261113c','/night-camp-icon.svg','/night-camp-icon-192.png'];
const AUDIO_RE=/\.(?:mp3|ogg|wav)$/i;
const STATIC_RE=/\.(?:js|css|woff2?|png|svg|webp|avif)$/i;

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>event.waitUntil(
  caches.keys().then(keys=>Promise.all(keys.filter(key=>
    (key.startsWith('mimox-shell-')||key.startsWith('night-camp-shell-'))&&key!==CACHE
  ).map(key=>caches.delete(key)))).then(()=>self.clients.claim())
));

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;

  if(request.mode==='navigate'){
    event.respondWith(fetch(request).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}
      return response;
    }).catch(async()=> (await caches.match(request))||(await caches.match('/'))));
    return;
  }

  if(AUDIO_RE.test(url.pathname)&&request.headers.has('range')){
    event.respondWith((async()=>{
      const cache=await caches.open(CACHE);
      const key=new Request(url.href,{method:'GET',credentials:request.credentials});
      let full=await cache.match(key);
      if(!full){
        try{
          full=await fetch(key);
          if(full.ok)await cache.put(key,full.clone());
        }catch{
          return new Response('Audio unavailable offline',{status:503});
        }
      }
      const bytes=await full.arrayBuffer();
      const match=/bytes=(\d+)-(\d*)/i.exec(request.headers.get('range')||'');
      if(!match)return full;
      const start=Number(match[1]);
      const end=match[2]?Math.min(Number(match[2]),bytes.byteLength-1):bytes.byteLength-1;
      if(start>=bytes.byteLength)return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+bytes.byteLength}});
      return new Response(bytes.slice(start,end+1),{
        status:206,
        headers:{
          'Content-Type':full.headers.get('Content-Type')||'audio/mpeg',
          'Content-Range':'bytes '+start+'-'+end+'/'+bytes.byteLength,
          'Accept-Ranges':'bytes',
          'Content-Length':String(end-start+1)
        }
      });
    })());
    return;
  }

  event.respondWith(caches.match(request).then(cached=>{
    if(cached)return cached;
    return fetch(request).then(response=>{
      if(response.ok&&(STATIC_RE.test(url.pathname)||AUDIO_RE.test(url.pathname))){
        const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));
      }
      return response;
    });
  }));
});
