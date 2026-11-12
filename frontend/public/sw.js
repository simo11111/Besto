const CACHE='mimox-shell-v30';
const SOUND_ASSETS=[
  '/sounds/camp-theme.mp3','/sounds/night-ambience.mp3','/sounds/morning-birds.mp3','/sounds/death-sting.mp3',
  '/sounds/save-chime.mp3','/sounds/vote-click.mp3','/sounds/eject-whoosh.mp3',
  '/sounds/win-fanfare.mp3','/sounds/lose-drone.mp3','/sounds/role-reveal.mp3'
];
const SHELL=['/','/manifest.webmanifest','/night-camp-icon.svg?v=20261112a','/night-camp-icon.svg','/night-camp-hero.svg','/games/haunted_camp.svg'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('mimox-shell-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('message',event=>{
  if(event.data?.type==='PRECACHE_HAUNTED_SOUNDS'){
    event.waitUntil(caches.open(CACHE).then(cache=>Promise.all(SOUND_ASSETS.map(async asset=>{
      try{const response=await fetch(asset);if(response.ok)await cache.put(asset,response.clone());}catch{/* optional until sound pack is shipped */}
    }))));
  }
});
self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;
  if(request.mode==='navigate'){
    event.respondWith(fetch(request).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put('/',copy));}
      return response;
    }).catch(()=>caches.match('/')));
    return;
  }
  event.respondWith(caches.match(request).then(cached=>{
    const network=fetch(request).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}
      return response;
    }).catch(error=>{if(cached)return cached;throw error;});
    return cached||network;
  }));
});
