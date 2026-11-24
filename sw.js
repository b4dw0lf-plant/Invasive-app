const APP='invasive-survey-v8',TILES='invasive-tiles-v1';
const SHELL=['./','index.html','manifest.webmanifest','icon.svg','pdf-lib.min.js','species.csv','treatments.csv','config.js','https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js','https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(APP).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(n=>n!==APP&&n!==TILES).map(n=>caches.delete(n)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const u=new URL(e.request.url);
  if(e.request.method!=='GET')return;
  /* map tiles: saved copy first, then network (prefer a CORS request so the stored copy is not an opaque response) */
  if(/arcgisonline\.com|tile\.openstreetmap\.org/.test(u.host)){
    e.respondWith(caches.open(TILES).then(async c=>{
      const hit=await c.match(e.request,{ignoreVary:true});if(hit)return hit;
      try{const r=await fetch(e.request.url,{mode:'cors',credentials:'omit'});if(r.ok){c.put(e.request.url,r.clone());return r}}catch(_){}
      try{const r2=await fetch(e.request);if(r2&&(r2.ok||r2.type==='opaque'))c.put(e.request,r2.clone());return r2}catch(_){return Response.error()}
    }));return}
  /* data files and settings: newest copy when online, saved copy when offline */
  if(u.origin===location.origin&&/\.(csv)$|config\.js$/.test(u.pathname)){
    e.respondWith(fetch(e.request).then(r=>{if(r.ok){const c=r.clone();caches.open(APP).then(x=>x.put(e.request,c))}return r}).catch(()=>caches.match(e.request)));return}
  /* cloud calls are never cached */
  if(u.origin!==location.origin&&!/cdnjs\.cloudflare\.com/.test(u.host))return;
  /* app files: saved copy first, refreshed in the background */
  e.respondWith(caches.open(APP).then(async c=>{
    const hit=await c.match(e.request);
    const net=fetch(e.request).then(r=>{if(r&&(r.ok||r.type==='opaque'))c.put(e.request,r.clone());return r}).catch(()=>hit);
    return hit||net;
  }));
});
