// Keep one Chrome storage origin for the installed app and browser.
window.ZenDesktopReady=(async()=>{
 if(window.ZenStore){await ZenStore.ready;return;}
 const HOME='http://127.0.0.1:19763', migrated='zen-desktop-origin-v1';
 if(location.protocol==='file:'){
  if(new URLSearchParams(location.search).has('standalone'))return;
  try{
   const health=await fetch(HOME+'/health',{signal:AbortSignal.timeout(1500)}).then(r=>r.json());
   if(health.app!=='zen-drawers')return;
   const previous=localStorage.getItem(migrated);if(previous){location.replace(HOME+'/?migration='+encodeURIComponent(previous)+location.hash);return new Promise(()=>{})}
   const storage={};for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(k.startsWith('zen-'))storage[k]=localStorage.getItem(k)}
   if(!storage['zen-drawers-v1']&&!storage['zen-qa-v1']){location.replace(HOME+'/'+location.hash);return new Promise(()=>{})}
   document.documentElement.style.visibility='hidden';
   const config=await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=HOME+'/desktop-config.js';s.onload=()=>resolve(window.ZenDesktopConfig);s.onerror=reject;document.head.append(s)});
   const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('zen-drawers-files',1);r.onupgradeneeded=()=>r.result.createObjectStore('files');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
   const pairs=await new Promise((resolve,reject)=>{const tx=db.transaction('files'),items=[];const r=tx.objectStore('files').openCursor();r.onsuccess=()=>{const c=r.result;if(c){items.push([c.key,c.value]);c.continue()}};tx.oncomplete=()=>resolve(items);tx.onerror=()=>reject(tx.error)});
   const files=await Promise.all(pairs.map(async([id,blob])=>({id,data:await new Promise((resolve,reject)=>{const f=new FileReader();f.onload=()=>resolve(f.result);f.onerror=()=>reject(f.error);f.readAsDataURL(blob)})})));db.close();
   const response=await fetch(HOME+'/migration',{method:'POST',headers:{'Content-Type':'text/plain'},body:JSON.stringify({token:config.token,snapshot:{storage,files,createdAt:new Date().toISOString()}})});
   if(!response.ok)throw Error('迁移备份未能保存');
   const {id}=await response.json();localStorage.setItem(migrated,id);
   // The original file storage is retained intact as an additional backup.
   location.replace(HOME+'/?migration='+id+location.hash);return new Promise(()=>{});
  }catch(error){document.documentElement.style.visibility='';console.warn('Zen keeps the original file storage:',error);return}
 }
 if(location.origin!==HOME)return;
 const id=new URLSearchParams(location.search).get('migration');
 if(id){
  document.documentElement.style.visibility='hidden';
  try{
   const mark='zen-imported-'+id;
   if(!localStorage.getItem(mark)){
    const response=await fetch('/migration/'+encodeURIComponent(id));if(!response.ok)throw Error('找不到迁移备份');const snapshot=await response.json();
    // Import only into an empty origin; never replace existing records silently.
    if(!localStorage.getItem('zen-drawers-v1')&&!localStorage.getItem('zen-qa-v1')){
     const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('zen-drawers-files',1);r.onupgradeneeded=()=>r.result.createObjectStore('files');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
     const blobs=await Promise.all(snapshot.files.map(async f=>[f.id,await fetch(f.data).then(r=>r.blob())]));
     if(blobs.length)await new Promise((resolve,reject)=>{const tx=db.transaction('files','readwrite');blobs.forEach(([k,v])=>tx.objectStore('files').put(v,k));tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error)});db.close();
     Object.entries(snapshot.storage).forEach(([k,v])=>{if(k.startsWith('zen-')&&typeof v==='string')localStorage.setItem(k,v)});
    }
    localStorage.setItem(mark,'1');
   }
   localStorage.setItem(migrated,'1');
   history.replaceState(null,'','/'+location.hash);
  }catch(error){document.documentElement.style.visibility='';document.body.textContent='记录迁移未完成：'+error.message+'。原 HTML 中的记录与本机备份仍保留，请重新打开原 HTML。';throw error}
  document.documentElement.style.visibility='';
 }
 if('serviceWorker'in navigator)navigator.serviceWorker.register('/zen-sw.js').catch(console.warn);
})();
if(location.origin==='http://127.0.0.1:19763'&&!window.ZenStore){
 let installPrompt;
 window.addEventListener('beforeinstallprompt',async event=>{
  event.preventDefault();installPrompt=event;
  if(document.readyState==='loading')await new Promise(resolve=>document.addEventListener('DOMContentLoaded',resolve,{once:true}));
  const button=document.createElement('button');button.id='install-zen';button.textContent='安装应用';button.onclick=async()=>{await installPrompt.prompt();const result=await installPrompt.userChoice;if(result.outcome==='accepted')button.remove()};document.querySelector('.toolbar')?.append(button);
 });
 window.addEventListener('appinstalled',()=>document.querySelector('#install-zen')?.remove());
}
