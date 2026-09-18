const fs=require('fs'),vm=require('vm');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.value='';this.checked=false;this.disabled=false;this.hidden=false;this.events={};this.classList={toggle:(k,v)=>this[k]=v};}
 appendChild(c){this.children.push(c)}
 removeAttribute(k){delete this[k]}
 addEventListener(k,f){this.events[k]=f}
 reportValidity(){return true}
 set textContent(t){this.text=t;this.children=[]}get textContent(){return this.text}
}
const ids={};for(const k of ['views','project','scale','cut_scale','cut_mm','render','quality','stats','form','status','preview-list','preview-image','preview-label','preview-note','preview-screen','cancel-preview'])ids[k]=new Element();
const fixed=new Element('select');fixed.disabled=true;
const fields=['project','scale','cut_scale','cut_mm','render','quality','stats'].map(k=>ids[k]);
const views=()=>ids.views.children.flatMap(l=>l.children).filter(c=>c.dataset&&c.dataset.view);
const doc={createElement:t=>new Element(t),createTextNode:t=>({text:t}),getElementById:k=>ids[k],querySelectorAll:s=>s==='[data-view]'?views():s==='[data-view]:checked'?views().filter(c=>c.checked):s==='[data-fixed]'?[fixed]:[...fields,...views(),fixed]};
let calls=[];const bridge={ready:()=>calls.push(['ready']),preview_page:id=>calls.push(['page',id]),run:(a,p)=>calls.push(['run',a,JSON.parse(p)])};
const c=vm.createContext({document:doc,sketchup:bridge});vm.runInContext(fs.readFileSync('output/layout185_ui.js','utf8'),c);
let n=0;const assert=(v,m)=>{if(!v)throw Error(m);n++};
vm.runInContext('receive({project:"Bếp",scale:20,cut_scale:10,cut_mm:20,render:"Vector",quality:90,stats:true,views:["front"]})',c);
assert(views().length===8 && views().filter(v=>v.checked).length===1,'view choices');
vm.runInContext('resetPreview();previewRunning(true);addPreviewPage({id:0,label:"Mặt đứng"});addPreviewPage({id:1,label:"Mặt cắt"});showPreviewImage({id:0,label:"Mặt đứng",src:"data:image/png;base64,abc"})',c);
assert(ids['preview-list'].children.length===2,'page dropdown');
assert(ids['preview-image'].hidden===false && ids['preview-image'].src.startsWith('data:'),'image visible');
vm.runInContext('movePage(1)',c);assert(JSON.stringify(calls.at(-1))==='["page",1]','next page bridge');
vm.runInContext('movePage(1)',c);assert(calls.at(-1)[1]===1,'last page boundary');
vm.runInContext('zoomPreview(true)',c);assert(ids['preview-screen'].zoom,'zoom');
vm.runInContext('setBusy(true)',c);assert(ids.scale.disabled && !ids['preview-list'].disabled,'preview controls remain available');
vm.runInContext('setBusy(false)',c);assert(!ids.scale.disabled && fixed.disabled,'form reenabled but fixed resolution stays fixed');
ids.form.events.change();assert(ids['preview-note'].textContent.includes('Thông số đã đổi'),'stale preview notice');
vm.runInContext('run("preview")',c);assert(calls.at(-1)[1]==='preview' && calls.at(-1)[2].project==='Bếp','preview callback payload');
vm.runInContext('resetPreview()',c);assert(ids['preview-image'].hidden && !ids['preview-image'].src,'clear old image');
console.log('PASS '+n+' UI logic checks; browser rendering not tested.');
