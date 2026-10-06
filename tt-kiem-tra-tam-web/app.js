const API='https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-model-api';
const $=s=>document.querySelector(s);
const state={panels:[],model:null,shareId:'',requestedBoard:''};
function requestedBoardUid314(){return String(new URLSearchParams(location.search).get('board')||'').trim()}

function urlShareId(){return String(new URLSearchParams(location.search).get('id')||'').trim()}
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function dim(p){if(Array.isArray(p.cut)&&p.cut.length)return p.cut.join(' × ')+' mm';const d=p.kt_cat||p.cut_size||p.dimensions||p.size||'';if(typeof d==='string'&&d.trim())return d;const a=[p.length||p.dai,p.width||p.rong,p.thickness||p.do_day].filter(v=>v!==undefined&&v!==null&&v!=='');return a.length?a.join(' × ')+' mm':'—'}
function edgeMap(p){const src=p.dan_canh||p.edge_banding||p.banding||p.edges||{};const get=(...keys)=>{for(const k of keys){const v=src?.[k]??p?.[k];if(v!==undefined&&v!==null&&v!==false&&v!==0&&v!=='0'&&v!=='')return v}return null};return {top:get('tren','top'),right:get('phai','right'),bottom:get('duoi','bottom'),left:get('trai','left')}}
function edgeCount(p){return Object.values(edgeMap(p)).filter(Boolean).length}
function thickness(p){const v=p.do_day??p.thickness??p.t??(Array.isArray(p.cut)?p.cut[2]:'')??'';if(v!==''&&v!=null)return String(v);const s=dim(p);const m=s.match(/(?:x|×)\s*([\d.]+)\s*mm?\s*$/i);return m?m[1]:''}
function panelCode(p){return p.ma_tam||p.code||p.uid||p.panel_uid||p.id||'—'}
function panelName(p){return p.ten||p.name||p.panel_name||'Tấm chưa đặt tên'}
function panelPath(p){return p.path||p.vi_tri||p.location||p.parent_path||'Chưa có vị trí'}

function setStatus(text,type=''){const e=$('#status');e.textContent=text;e.className='status '+type}
function setLoginMessage(text,type=''){const e=$('#loginMessage');e.textContent=text;e.className='loginMessage '+type}
function showApp(){
  $('#loginCard').classList.add('hidden');$('#logoutBtn').classList.remove('hidden');
  $('#modelCard').classList.remove('hidden');$('#controls').classList.remove('hidden');$('#summary').classList.remove('hidden');
}
function hideApp(){
  $('#loginCard').classList.remove('hidden');$('#logoutBtn').classList.add('hidden');
  ['#modelCard','#controls','#summary'].forEach(s=>$(s).classList.add('hidden'));$('#list').innerHTML='';
}
function loadModel(model){
  state.model=model;state.requestedBoard=requestedBoardUid314();const p=model.payload||{};
  state.panels=Array.isArray(p.panels)?p.panels:(Array.isArray(p.boards)?p.boards:(Array.isArray(p.tam)?p.tam:[]));
  $('#modelName').textContent=model.model_name||p.model_name||'SketchUp Model';
  $('#modelId').textContent='Mã: '+(model.share_id||state.shareId||'—');
  $('#updatedAt').textContent='Cập nhật: '+new Date(model.updated_at).toLocaleString('vi-VN');
  $('#panelCount').textContent=state.panels.length;
  $('#edgeCount').textContent=state.panels.reduce((a,x)=>a+edgeCount(x),0);
  const th=[...new Set(state.panels.map(thickness).filter(Boolean))].sort((a,b)=>num(a)-num(b));
  $('#thicknessCount').textContent=th.length;
  $('#thicknessFilter').innerHTML='<option value="">Tất cả độ dày</option>'+th.map(v=>`<option value="${esc(v)}">${esc(v)} mm</option>`).join('');
  showApp();setStatus('ĐÃ ĐĂNG NHẬP','ok');render();if(state.requestedBoard){const hit=state.panels.find(x=>String(x.uid||x.panel_uid||x.code||x.ma_tam||'')===state.requestedBoard);if(hit)setTimeout(()=>openDetail(hit),120);}
}
async function login(){
  const projectLogin=$('#projectLogin').value.trim();
  const password=$('#projectPassword').value;
  if(!projectLogin||!password){setLoginMessage('Nhập đủ Tên dự án và Mật khẩu.');return}
  $('#loginBtn').disabled=true;setLoginMessage('Đang xác thực…');setStatus('ĐANG ĐĂNG NHẬP');
  try{
    const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'login',share_id:state.shareId,project_login:projectLogin,password})});
    const j=await res.json().catch(()=>({}));
    if(!res.ok||!j.ok){
      const map={invalid_credentials:'Tên dự án hoặc mật khẩu không đúng.',missing_credentials:'Thiếu thông tin đăng nhập.',not_found:'Không tìm thấy dự án.',database_error:'Máy chủ dữ liệu đang lỗi.'};
      throw new Error(map[j.error]||j.detail||j.error||'Đăng nhập thất bại');
    }
    $('#projectPassword').value='';setLoginMessage('Đăng nhập thành công.','ok');loadModel(j.model);
  }catch(e){setStatus('ĐĂNG NHẬP LỖI','bad');setLoginMessage(e.message||String(e))}
  finally{$('#loginBtn').disabled=false}
}
function logout(){
  state.model=null;state.panels=[];$('#projectPassword').value='';setLoginMessage('');hideApp();setStatus('Sẵn sàng');$('#projectLogin').focus();
}
function render(){
  const q=$('#search').value.trim().toLowerCase();const tf=$('#thicknessFilter').value;const ef=$('#edgeFilter').value;
  const rows=state.panels.filter(p=>{const text=[panelName(p),panelCode(p),panelPath(p),dim(p)].join(' ').toLowerCase();const passQ=!q||text.includes(q);const passT=!tf||thickness(p)===tf;const ec=edgeCount(p);const passE=!ef||(ef==='has'?ec>0:ec===0);return passQ&&passT&&passE});
  $('#summary').textContent=`Đang hiển thị ${rows.length}/${state.panels.length} tấm.`;
  $('#list').innerHTML=rows.map(p=>{const e=edgeMap(p);return `<article class="card" data-idx="${state.panels.indexOf(p)}">
    <div class="cardTop"><div><div class="name">${esc(panelName(p))}</div><div class="code">${esc(panelCode(p))}</div></div><span class="badge thk">${esc(thickness(p)||'?')} mm</span></div>
    <div class="dim">${esc(dim(p))}</div><div class="path">${esc(panelPath(p))}</div>
    <div class="badges">${edgeCount(p)?`<span class="badge edge">${edgeCount(p)} cạnh dán</span>`:''}</div>
    <div class="edgebox"><div class="edgeTitle">DÁN CẠNH</div><div class="edgeRow">
      <div class="edge ${e.left?'on':''}">TRÁI${e.left?' '+esc(e.left):''}</div><div class="edge ${e.top?'on':''}">TRÊN${e.top?' '+esc(e.top):''}</div>
      <div class="edge ${e.right?'on':''}">PHẢI${e.right?' '+esc(e.right):''}</div><div class="edge ${e.bottom?'on':''}">DƯỚI${e.bottom?' '+esc(e.bottom):''}</div>
    </div></div></article>`}).join('');
  document.querySelectorAll('.card').forEach(el=>el.addEventListener('click',()=>openDetail(state.panels[Number(el.dataset.idx)])));
}
function openDetail(p){
  $('#dName').textContent=panelName(p);const e=edgeMap(p);
  const items=[['Mã tấm',panelCode(p)],['Kích thước cắt',dim(p)],['Độ dày',thickness(p)?thickness(p)+' mm':'—'],['Vị trí trong Model',panelPath(p)],['Tag / Layer',p.tag||p.layer||'—'],['Vật liệu',p.vat_lieu||p.material||'—'],['Cạnh TRÁI',e.left||'Không dán'],['Cạnh TRÊN',e.top||'Không dán'],['Cạnh PHẢI',e.right||'Không dán'],['Cạnh DƯỚI',e.bottom||'Không dán'],['UID',p.uid||p.panel_uid||'—']];
  $('#detailBody').innerHTML='<div class="detailGrid">'+items.map((x,i)=>`<div class="detailItem ${i===3?'detailWide':''}"><span>${esc(x[0])}</span><b>${esc(x[1])}</b></div>`).join('')+'</div>';$('#detailDialog').showModal();
}
async function downloadPackage315(){
  const title=document.querySelector('#loginTitle');
  const hint=document.querySelector('#loginHint');
  const btn=document.querySelector('#loginBtn');
  const user=document.querySelector('#projectLogin');
  const pass=document.querySelector('#projectPassword');
  const toggle=document.querySelector('#togglePassword');
  document.querySelectorAll('.fieldLabel').forEach(x=>x.classList.add('hidden'));
  if(user) user.classList.add('hidden');
  if(pass) pass.classList.add('hidden');
  if(toggle) toggle.classList.add('hidden');
  if(title) title.textContent='TẢI TRẦN TUẤN NESTING PRO v3.1.5';
  if(hint) hint.textContent='Bấm nút bên dưới để tải trực tiếp file cài RBZ. Không dùng bộ tải tệp của ChatGPT.';
  if(btn){
    btn.disabled=true;
    btn.textContent='ĐANG CHUẨN BỊ FILE...';
  }
  try{
    const url='https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/TT_kiem_tra_tam_pro/releases/TT_NESTING_315.rbz.b64?ts='+Date.now();
    const res=await fetch(url,{cache:'no-store'});
    if(!res.ok) throw new Error('Không tải được dữ liệu RBZ từ GitHub.');
    const b64=(await res.text()).replace(/\s+/g,'');
    const bin=atob(b64);
    const bytes=new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++) bytes[i]=bin.charCodeAt(i);
    const blob=new Blob([bytes],{type:'application/zip'});
    const href=URL.createObjectURL(blob);
    const a=document.createElement('a');
    a.href=href;
    a.download='TT_NESTING_315.rbz';
    document.body.appendChild(a);
    if(btn){
      btn.disabled=false;
      btn.textContent='TẢI TT_NESTING_315.RBZ';
      btn.onclick=()=>a.click();
    }
    a.click();
    setLoginMessage('Đã tạo file cài RBZ. Nếu trình duyệt chưa tải, bấm nút TẢI bên trên.','ok');
    setStatus('FILE SẴN SÀNG','ok');
    setTimeout(()=>URL.revokeObjectURL(href),600000);
  }catch(e){
    if(btn){
      btn.disabled=false;
      btn.textContent='THỬ TẢI LẠI';
      btn.onclick=downloadPackage315;
    }
    setLoginMessage(e.message||String(e));
    setStatus('TẢI FILE LỖI','bad');
  }
}

function boot(){
  const params=new URLSearchParams(location.search);
  if(params.get('download')==='315'){downloadPackage315();return}
  state.shareId=urlShareId();
  if(state.shareId){$('#qrModeHint').classList.remove('hidden');$('#loginHint').textContent='QR CHÍNH đã xác định Model. Nhập Tên dự án và Mật khẩu để xem dữ liệu.'}
  else{$('#loginHint').textContent='Bạn có thể đăng nhập trực tiếp bằng Tên dự án + Mật khẩu, không cần quét QR.'}
  setStatus('CHỜ ĐĂNG NHẬP');setTimeout(()=>$('#projectLogin').focus(),120);
}
$('#loginBtn').addEventListener('click',login);$('#projectPassword').addEventListener('keydown',e=>{if(e.key==='Enter')login()});$('#projectLogin').addEventListener('keydown',e=>{if(e.key==='Enter')$('#projectPassword').focus()});
$('#togglePassword').addEventListener('click',()=>{const p=$('#projectPassword');const show=p.type==='password';p.type=show?'text':'password';$('#togglePassword').textContent=show?'ẨN':'HIỆN'});
$('#logoutBtn').addEventListener('click',logout);$('#closeDialog').addEventListener('click',()=>$('#detailDialog').close());
['search','thicknessFilter','edgeFilter'].forEach(id=>$('#'+id).addEventListener(id==='search'?'input':'change',render));
boot();