/* Shared Markdown image ingestion. Image bytes belong to the local file store. */
window.ZenMarkdown=(()=>{
 const imageType=/^image\/(png|jpeg|gif|webp|avif)$/i;
 async function remote(url){
  let response;
  if(!url.startsWith('data:')&&window.ZenFiles?.importImage)return ZenFiles.importImage(url);
  response=await fetch(url);if(!response.ok)throw Error('网络图片下载失败');
  const blob=await response.blob();if(!imageType.test(blob.type))throw Error('链接不是支持的图片');return blob;
 }
 async function localize(text,upload){
  // HTML copied from websites is converted to stable Markdown image references too.
  text=text.replace(/<img\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi,(_,src)=>'![图片]('+src+')');
  const matches=[...text.matchAll(/!\[([^\]]*)\]\(\s*(https?:\/\/[^\s]+?|data:image\/[^\s]+?)\s*(?:\s+"[^"]*")?\)/gi)];
  const urls=new Map();for(const m of matches){if(!urls.has(m[2]))urls.set(m[2],await upload(await remote(m[2])));text=text.replace(m[0],'!['+m[1]+']('+urls.get(m[2])+')')}
  return text;
 }
 function bind(target,upload,notice,cm=null){
  const host=cm?cm.getWrapperElement():target;
  host.addEventListener('paste',async e=>{
   const clip=e.clipboardData,files=[...(clip?.files||[])].filter(f=>imageType.test(f.type));
   const doc=new DOMParser().parseFromString(clip?.getData('text/html')||'','text/html');
   const images=[...doc.images].map(i=>i.getAttribute('src')).filter(s=>/^(https?:|data:image\/)/i.test(s||''));
   const plain=clip?.getData('text/plain')||'';
   if(!files.length&&!images.length&&!/!\[[^\]]*\]\(https?:/i.test(plain))return;
   e.preventDefault();e.stopImmediatePropagation();host.dataset.imageBusy='true';
   const cursor=cm?{from:cm.getCursor('from'),to:cm.getCursor('to')}:{from:target.selectionStart,to:target.selectionEnd};
   try{let content='';if(files.length){for(const f of files)content+='\n\n![图片]('+await upload(f)+')\n\n'}else if(images.length){content=plain;for(const url of images)content+='\n\n![图片]('+await upload(await remote(url))+')\n\n'}else content=await localize(plain,upload);
    if(cm)cm.replaceRange(content,cursor.from,cursor.to);else{target.setRangeText(content,cursor.from,cursor.to,'end');target.dispatchEvent(new Event('input',{bubbles:true}))}
   }catch(err){notice('图片未能保存：'+err.message)}finally{delete host.dataset.imageBusy}
  },true);
 }
 return{localize,bind,remote};
})();
