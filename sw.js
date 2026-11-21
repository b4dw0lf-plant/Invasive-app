const APP='invasive-survey-v4',TILES='invasive-tiles-v1';
const SHELL=['./','index.html','manifest.webmanifest','icon.svg','https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js','https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(APP).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(n=>n!==APP&&n!==TILES).map(n=>caches.delete(n)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const u=new URL(e.request.url);
  if(e.request.method!=='GET')return;
  const isTile=/arcgisonline\.com|tile\.openstreetmap\.org/.test(u.host);
  const cname=isTile?TILES:APP;
  e.respondWith(caches.open(cname).then(async c=>{
    const hit=await c.match(e.request,{ignoreSearch:false});
    const net=fetch(e.request).then(r=>{if(r&&(r.ok||r.type==='opaque'))c.put(e.request,r.clone());return r}).catch(()=>hit);
    return isTile?(hit||net):(hit?(net,hit):net);
  }));
});
