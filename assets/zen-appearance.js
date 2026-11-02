/* Local system fonts: no downloads; selection follows the shared Chrome origin. */
(()=>{
 const KEY='zen-appearance-v1',defaults={size:'medium',font:'default'};
 const fonts={default:'-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif',songti:'"Songti SC","STSong",serif',kaiti:'"Kaiti SC","STKaiti",serif',bold:'"Heiti SC","PingFang SC",sans-serif'};
 fonts.emphasis=fonts.default;
 const scales={small:12/13,medium:1,large:15/13};
 const defaultWeight=font=>['emphasis','bold'].includes(font)?500:400;
 const clean=p=>({weight:Number.isFinite(Number(p?.weight))&&p?.weight!=null?Math.max(400,Math.min(650,Math.round(Number(p.weight)/25)*25)):defaultWeight(p?.font),size:Object.hasOwn(scales,p?.size)?p.size:'medium',font:Object.hasOwn(fonts,p?.font)?p.font:'default'});
 let saved=defaults;try{saved=clean(JSON.parse(localStorage.getItem(KEY)))}catch(e){}
 function apply(p){const root=document.documentElement;root.style.setProperty('--font-scale',scales[p.size]);root.style.setProperty('--ui-font',fonts[p.font]);root.style.setProperty('--serif',['default','emphasis'].includes(p.font)?'"Songti SC","STSong","Noto Serif CJK SC",serif':fonts[p.font]);root.style.setProperty('--focus-weight',p.weight);root.dataset.font=p.font;root.dataset.fontSize=p.size;requestAnimationFrame(()=>window.ZenCards?.layout())}
 apply(saved);
 const form=document.querySelector('#settings-form'),block=document.createElement('section');block.className='appearance-settings';
 block.innerHTML='<h3>阅读外观</h3><div class="appearance-fields"><label class="field"><span>字体大小</span><select id="appearance-size" aria-label="字体大小"><option value="small">小</option><option value="medium">中 · 默认</option><option value="large">大</option></select></label><label class="field"><span>字体</span><select id="appearance-font" aria-label="字体"><option value="default">系统字体 · 当前默认</option><option value="emphasis">系统字体 · 清晰强调</option><option value="songti">宋体 · 书卷</option><option value="kaiti">楷体 · 手写</option><option value="bold">黑体 · 粗体</option></select></label></div><label class="appearance-weight field"><span>重点字重 <output id="appearance-weight-value">500</output></span><input type="range" id="appearance-weight" aria-label="重点文字字重" min="400" max="650" step="25" list="appearance-weight-ticks"><datalist id="appearance-weight-ticks"><option value="400"></option><option value="450"></option><option value="500"></option><option value="550"></option><option value="600"></option><option value="650"></option></datalist><span class="weight-tick-labels" aria-hidden="true"><span>400 常规</span><span>450</span><span>500</span><span>550</span><span>600</span><span>650 粗</span></span></label><p class="tiny muted">只调整标题与重点文字，说明文字保持轻盈。</p><p class="appearance-preview">轻重有序，安放此刻。<span>Zen · 先安放，再从容安排。</span></p><p class="tiny muted">抽屉与 Zen QA 共用，本机记住选择。</p></section>';
 form.querySelector('.dialog-body').prepend(block);form.querySelector('h2').textContent='设置';document.querySelector('#settings').textContent='设置';
 const size=document.querySelector('#appearance-size'),font=document.querySelector('#appearance-font'),weight=document.querySelector('#appearance-weight'),weightValue=document.querySelector('#appearance-weight-value');
 function preview(){weightValue.textContent=weight.value;apply(clean({size:size.value,font:font.value,weight:Number(weight.value)}))}size.onchange=preview;weight.oninput=preview;font.onchange=()=>{weight.value=defaultWeight(font.value);preview()};
 let committed=false;
 document.querySelector('#settings').addEventListener('click',()=>{committed=false;size.value=saved.size;font.value=saved.font;weight.value=saved.weight;weightValue.textContent=saved.weight});
 window.ZenAppearance={commit(){const next=clean({size:size.value,font:font.value,weight:Number(weight.value)});localStorage.setItem(KEY,JSON.stringify(next));saved=next;committed=true}};
 document.querySelector('#settings-dialog').addEventListener('close',()=>{if(!committed)apply(saved)});
 window.addEventListener('storage',e=>{if(e.key===KEY){try{saved=clean(JSON.parse(e.newValue));apply(saved)}catch(error){}}});
})();
