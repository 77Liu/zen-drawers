/* Shared disk storage supplied by the native app. Ordinary file HTML still works locally. */
(()=>{
 if(location.protocol!=='http:'||location.hostname!=='127.0.0.1')return;
 const original=window.localStorage;
 function request(path,body,method='POST',retry=true){
  const xhr=new XMLHttpRequest();xhr.open(method,path,false);
  if(body!==undefined){xhr.setRequestHeader('Content-Type','application/json');if(token)xhr.setRequestHeader('X-Zen-Token',token)}
  xhr.send(body===undefined?null:JSON.stringify(body));
  if(xhr.status===403&&body!==undefined&&retry){const latest=request('/api/state',undefined,'GET',false);if(latest.token&&latest.token!==token){token=latest.token;return request(path,body,method,false)}}
  if(xhr.status<200||xhr.status>=300)throw Error('本机数据未能保存（'+xhr.status+'）');
  return xhr.responseText?JSON.parse(xhr.responseText):{};
 }
 let token='',initial;
 try{initial=request('/api/state',undefined,'GET')}catch(e){return}
 if(initial.kind!=='zen-disk-store')return;
 token=initial.token;let revision=initial.revision,cache=initial.storage||{},pending=0;
 const source={};for(let i=0;i<original.length;i++){const key=original.key(i);if(key.startsWith('zen-'))source[key]=original.getItem(key)}
 const needsMigration=!Object.keys(cache).length&&Object.keys(source).some(k=>['zen-drawers-v1','zen-qa-v1'].includes(k));
 if(needsMigration){const result=request('/api/bootstrap',{storage:source});cache=result.storage;revision=result.revision}
 const storage={get length(){return Object.keys(cache).length},key(i){return Object.keys(cache)[i]??null},getItem(k){return Object.hasOwn(cache,String(k))?cache[String(k)]:null},setItem(k,v){k=String(k);v=String(v);const result=request('/api/item',{key:k,value:v});cache[k]=v;revision=result.revision},removeItem(k){k=String(k);const result=request('/api/item',{key:k,value:null});delete cache[k];revision=result.revision},clear(){const result=request('/api/clear',{});cache={};revision=result.revision}};
 Object.defineProperty(window,'localStorage',{value:storage,configurable:true});
 async function writeFiles(entries){for(const [id,blob] of entries){const response=await fetch('/api/files/'+encodeURIComponent(id),{method:'PUT',headers:{'X-Zen-Token':token,'Content-Type':blob.type||'application/octet-stream'},body:blob});if(!response.ok)throw Error('附件未能保存：'+response.status)}}
 window.ZenFiles={async importImage(url){const response=await fetch("/api/import-image",{method:"POST",headers:{"Content-Type":"application/json","X-Zen-Token":token},body:JSON.stringify({url})});if(!response.ok)throw Error("网络图片下载失败，请检查链接");return response.blob()},store:writeFiles,async read(id){const response=await fetch('/api/files/'+encodeURIComponent(id));if(!response.ok)throw Error('附件不存在，请从完整备份恢复');return response.blob()}};
 const ready=(async()=>{
  if(!needsMigration&&!(initial.migrationPending&&Object.keys(source).some(k=>['zen-drawers-v1','zen-qa-v1'].includes(k))))return;
  const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('zen-drawers-files',1);r.onupgradeneeded=()=>r.result.createObjectStore('files');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
  const entries=await new Promise((resolve,reject)=>{const tx=db.transaction('files'),items=[],r=tx.objectStore('files').openCursor();r.onsuccess=()=>{const c=r.result;if(c){items.push([c.key,c.value]);c.continue()}};tx.oncomplete=()=>resolve(items);tx.onerror=()=>reject(tx.error)});
  await writeFiles(entries);db.close();request('/api/migration-complete',{});
 })();
 window.ZenStore={ready};
 async function sync(){if(pending)return;pending++;const requestedRevision=revision;try{const response=await fetch('/api/state');if(!response.ok)return;const next=await response.json();if(next.token)token=next.token;if(revision!==requestedRevision)return;if(next.revision!==revision){const previous=cache;cache=next.storage;revision=next.revision;for(const key of new Set([...Object.keys(previous),...Object.keys(cache)])){const oldValue=previous[key]??null,newValue=cache[key]??null;if(oldValue!==newValue)window.dispatchEvent(new StorageEvent('storage',{key,oldValue,newValue,url:location.href}))}}}catch(e){}finally{pending--}}
 setInterval(sync,1200);window.addEventListener('focus',sync);document.addEventListener('visibilitychange',()=>{if(!document.hidden)sync()});
})();
