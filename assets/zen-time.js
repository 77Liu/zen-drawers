/* Local calendar labels. Chinese names follow Unicode CLDR; ranges follow Zen's UI policy. */
(()=>{
'use strict';
const pad=n=>String(n).padStart(2,'0');
function normalize(value){if(typeof value!=='string'||!value.trim())return null;const d=new Date(value);return Number.isFinite(+d)?d.toISOString():null}
const calendarDay=d=>Date.UTC(d.getFullYear(),d.getMonth(),d.getDate())/86400000;
function format(value,now=new Date()){
 const valid=normalize(value);if(!valid)return'';const d=new Date(valid),day=calendarDay(d),today=calendarDay(now),diff=day-today;
 const monday=today-(now.getDay()+6)%7,weekday='日一二三四五六'[d.getDay()];
 let label;if(diff===-1)label='昨天';else if(diff===0)label='今天';else if(diff===1)label='明天';else if(day>=monday&&day<monday+7)label='周'+weekday;else if(day>=monday+7&&day<monday+14)label='下周'+weekday;
 else return(d.getFullYear()!==now.getFullYear()?d.getFullYear()+'-':'')+pad(d.getMonth()+1)+'-'+pad(d.getDate())+' '+pad(d.getHours())+':'+pad(d.getMinutes());
 return label+' '+d.getHours()+'点'+(d.getMinutes()?pad(d.getMinutes())+'分':'');
}
function localInput(value){const d=new Date(value);return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate())+'T'+pad(d.getHours())+':'+pad(d.getMinutes())}
function refreshBadge(el){const time=normalize(el.dataset.time);el.textContent=time?format(time):'';el.hidden=!time;el.title=time?new Date(time).toLocaleString('zh-CN',{hour12:false})+' · 点击修改':'设置加急时间';el.classList.toggle('has-time',!!time)}
function badge(record,action){const b=document.createElement('button');b.type='button';b.className='urgent-time';b.dataset.time=normalize(record.urgentAt)||'';b.setAttribute('aria-label','设置加急时间：'+(record.text||record.title||''));b.addEventListener('pointerdown',e=>e.stopPropagation());b.addEventListener('dblclick',e=>e.stopPropagation());b.onclick=e=>{e.stopPropagation();action()};refreshBadge(b);queueMicrotask(()=>{const alarm=b.parentElement?.querySelector('.task-urgent');if(alarm){alarm.title='点击切换加急 · 右键设置时间';alarm.oncontextmenu=e=>{e.preventDefault();e.stopPropagation();action()}}});return b}
let dlg,handler;
function ensureDialog(){if(dlg)return;dlg=document.createElement('dialog');dlg.id='urgent-time-dialog';dlg.setAttribute('aria-labelledby','urgent-time-title');dlg.innerHTML='<form id="urgent-time-form"><div class="dialog-head"><h2 id="urgent-time-title">加急时间</h2><button type="button" class="close" data-time-close aria-label="关闭">×</button></div><div class="dialog-body"><p id="urgent-time-subject" class="muted"></p><label class="field"><span>日期与时间（可选）</span><input type="datetime-local" id="urgent-time-input" step="60"></label><p id="urgent-time-preview" class="tiny muted"></p><p id="urgent-time-error" class="error" role="alert"></p></div><div class="dialog-foot"><button type="button" id="urgent-time-clear">仅加急，不设时间</button><span class="spacer"></span><button type="button" data-time-close>取消</button><button type="submit" class="primary">保存</button></div></form>';document.body.append(dlg);dlg.querySelectorAll('[data-time-close]').forEach(b=>b.onclick=()=>dlg.close());const input=dlg.querySelector('#urgent-time-input');input.oninput=()=>{dlg.querySelector('#urgent-time-preview').textContent=input.value?format(new Date(input.value).toISOString()):'仅标记加急';dlg.querySelector('#urgent-time-error').textContent=''};function save(value){try{handler(value);dlg.close()}catch(e){dlg.querySelector('#urgent-time-error').textContent=e.message}}
 dlg.querySelector('#urgent-time-clear').onclick=()=>save(null);dlg.querySelector('form').onsubmit=e=>{e.preventDefault();if(!input.checkValidity()){input.reportValidity();return}const value=input.value?normalize(new Date(input.value).toISOString()):null;save(value)};
}
function open({title,value,onSave}){ensureDialog();handler=onSave;dlg.querySelector('#urgent-time-subject').textContent=title;const normalized=normalize(value);dlg.querySelector('#urgent-time-input').value=normalized?localInput(normalized):'';dlg.querySelector('#urgent-time-preview').textContent=normalized?format(normalized):'仅标记加急';dlg.querySelector('#urgent-time-error').textContent='';dlg.showModal();dlg.querySelector('#urgent-time-input').focus()}
function refresh(){document.querySelectorAll('.urgent-time').forEach(refreshBadge)}
window.ZenTime={normalize,format,badge,open};
setInterval(refresh,60000);window.addEventListener('focus',refresh);document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
})();
