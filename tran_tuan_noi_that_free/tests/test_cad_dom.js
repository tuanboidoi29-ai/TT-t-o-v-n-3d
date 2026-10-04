const {JSDOM}=require('jsdom');const fs=require('fs');
const html=fs.readFileSync(require('path').join(__dirname,'../files/tran_tuan_noi_that/ui/cad_walls.html'),'utf8');
const calls=[];const dom=new JSDOM(html,{runScripts:'dangerously',beforeParse(w){w.sketchup={};['ready','import_cad','scan_selected','recognize','toggle_wall','preview','create','cancel_job'].forEach(n=>w.sketchup[n]=(...a)=>calls.push([n,...a]));}});
const w=dom.window,d=w.document;function check(ok,msg){if(!ok)throw Error(msg);}
const data={layers:[{name:'A-WALL',count:8,kind:'Tường',use:true},{name:'DIM',count:30,kind:'Bỏ qua',use:false}],walls:[{id:0,a:[0,55],b:[4000,55],width:110,length:4000,selected:true,layer:'A-WALL'}],symbols:[{name:'A-DOOR',kind:'Cung 90° — kiểm tra',count:1}]};
w.dispatchEvent(new w.Event('DOMContentLoaded'));w.receive(data);w.setStatus('Kiểm tra');
check(d.querySelectorAll('#plan polygon').length===1,'Plan polygon');
check(d.getElementById('status').textContent==='Kiểm tra','Status bridge');
d.getElementById('previewBtn').click();d.getElementById('createBtn').click();
d.querySelector('#walls input').click();
d.getElementById('height').value='3200';d.getElementById('height').dispatchEvent(new w.Event('input'));
check(d.getElementById('createBtn').disabled,'Stale create disabled');
w.receive(data);check(d.getElementById('createBtn').disabled,'Toggle response must not enable stale options');
w.recognize();const payload=JSON.parse(calls.find(c=>c[0]==='recognize')[1]);
check(payload.height==='3200'&&payload.layers.join()==='A-WALL','Payload');
for(const name of ['ready','preview','create','toggle_wall','recognize'])check(calls.some(c=>c[0]===name),'Callback '+name);
data.layers[0].name='<img src=x onerror="window.pwned=1">';w.receive(data);check(!w.pwned&&!d.querySelector('#layers img'),'Safe names');
check(d.querySelectorAll('#layers input').length===2,'Layer controls');
console.log('DOM tests passed: plan, status, callbacks, settings, stale preview guard, safe names');dom.window.close();
