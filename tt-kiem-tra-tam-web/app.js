const API='https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-model-api';
const $=s=>document.querySelector(s);
const state={shareId:'',pendingBoard:'',model:null,panels:[],labels:[],model3d:[],view:{yaw:-.65,pitch:-.45,zoom:1,drag:false,x:0,y:0},stream:null,scanLoop:0,detector:null};

function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function shareIdFromUrl(){return String(new URLSearchParams(location.search).get('id')||'').trim()}
function boardFromUrl(){return String(new URLSearchParams(location.search).get('board')||'').trim()}
function setStatus(t,cls=''){const e=$('#status');e.textContent=t;e.className='status '+cls}
function setMsg(t,cls=''){const e=$('#loginMessage');e.textContent=t;e.className='loginMessage '+cls}
function codeOf(p){return p.code||p.ma_tam||p.uid||p.panel_uid||p.id||'—'}
function nameOf(p){return p.name||p.ten||p.panel_name||'Tấm chưa đặt tên'}
function pathOf(p){return p.path||p.vi_tri||p.location||'—'}
function labelInfo(p){return p.label||{assigned:!!p.label_assigned,code:p.label_code||codeOf(p),name:p.label_name||nameOf(p)}}
function thickness(p){const v=p.thickness??p.do_day??(Array.isArray(p.cut)?p.cut[2]:'');return v==null?'':String(v)}
function dim(p){if(Array.isArray(p.cut)&&p.cut.length>=2)return p.cut.map(x=>Number(x).toFixed(x%1?1:0)).join(' × ')+' mm';return p.dimensions||p.size||'—'}
function bandsOf(p){return p.banding||p.bands||p.dan_canh||{}}
function bandCount(p){return Object.values(bandsOf(p)).filter(v=>v!==null&&v!==false&&v!==0&&v!=='').length}

function showApp(){ $('#loginCard').classList.add('hidden'); ['#projectCard','#modelPanel','#controls','#summary'].forEach(s=>$(s).classList.remove('hidden')); $('#logoutBtn').classList.remove('hidden'); }
function hideApp(){ $('#loginCard').classList.remove('hidden'); ['#projectCard','#modelPanel','#controls','#summary'].forEach(s=>$(s).classList.add('hidden')); $('#logoutBtn').classList.add('hidden'); $('#list').innerHTML=''; }

async function login(){
  const login=$('#projectLogin').value.trim();
  const password=$('#projectPassword').value;
  if(!login||!password){setMsg('Nhập đủ Tên dự án và Mật khẩu.');return}
  $('#loginBtn').disabled=true;setMsg('Đang xác thực…');setStatus('ĐANG ĐĂNG NHẬP');
  try{
    const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'login',share_id:state.shareId,project_login:login,password})});
    const j=await res.json().catch(()=>({}));
    if(!res.ok||!j.ok){
      const map={invalid_credentials:'Tên dự án hoặc mật khẩu không đúng.',missing_credentials:'Thiếu thông tin đăng nhập.',project_login_too_short:'Tên dự án quá ngắn.',password_too_short:'Mật khẩu quá ngắn.',password_required:'Dự án chưa có mật khẩu.'};
      throw new Error(map[j.error]||j.detail||j.error||'Đăng nhập thất bại');
    }
    localStorage.setItem('tt_project_login',login);
    $('#projectPassword').value='';
    loadModel(j.model);
    setMsg('Đăng nhập thành công.','ok');
  }catch(e){setStatus('ĐĂNG NHẬP LỖI','bad');setMsg(e.message||String(e))}
  finally{$('#loginBtn').disabled=false}
}

function loadModel(model){
  state.model=model||{};const p=state.model.payload||{};
  state.shareId=state.model.share_id||state.shareId;
  state.panels=Array.isArray(p.panels)?p.panels:(Array.isArray(p.boards)?p.boards:[]);
  state.labels=Array.isArray(p.labels)?p.labels:state.panels.filter(x=>labelInfo(x).assigned);
  state.model3d=Array.isArray(p.model3d)?p.model3d:[];
  $('#modelName').textContent=state.model.model_name||p.model_name||'SketchUp Model';
  $('#modelId').textContent='Mã: '+state.shareId;
  $('#savedAt').textContent='Lưu: '+new Date(state.model.last_saved_at||state.model.updated_at||Date.now()).toLocaleString('vi-VN');
  $('#revision').textContent='Revision: '+String(state.model.revision||1);
  $('#panelCount').textContent=state.panels.length;
  $('#labelCount').textContent=state.labels.length;
  $('#bandCount').textContent=state.panels.reduce((a,p)=>a+bandCount(p),0);
  const th=[...new Set(state.panels.map(thickness).filter(Boolean))].sort((a,b)=>num(a)-num(b));
  $('#thicknessFilter').innerHTML='<option value="">Tất cả độ dày</option>'+th.map(v=>'<option value="'+esc(v)+'">'+esc(v)+' mm</option>').join('');
  showApp();render();drawModel();setStatus('DỮ LIỆU ĐÃ LƯU','ok');
  if(state.pendingBoard){const hit=findBoard(state.pendingBoard);if(hit)setTimeout(()=>openDetail(hit),100);}
}

function findBoard(token){const t=String(token||'').trim();return state.panels.find(p=>[p.uid,p.panel_uid,p.code,p.ma_tam,p.id].map(String).includes(t))||null}
function render(){
  const q=$('#search').value.trim().toLowerCase(),tf=$('#thicknessFilter').value,lf=$('#labelFilter').value;
  const rows=state.panels.filter(p=>{const li=labelInfo(p);const txt=[nameOf(p),codeOf(p),li.code,li.name,p.tag,p.material,pathOf(p),dim(p)].join(' ').toLowerCase();return(!q||txt.includes(q))&&(!tf||thickness(p)===tf)&&(!lf||(lf==='yes'?li.assigned:!li.assigned))});
  $('#summary').textContent='Đang hiển thị '+rows.length+'/'+state.panels.length+' tấm • '+state.labels.length+' tem đã lưu.';
  $('#list').innerHTML=rows.map(p=>{const li=labelInfo(p),b=bandsOf(p);return '<article class="card" data-code="'+esc(codeOf(p))+'"><div class="cardTop"><div><div class="name">'+esc(li.assigned?li.name:nameOf(p))+'</div><div class="code">'+esc(li.code||codeOf(p))+'</div></div><span class="badge thk">'+esc(thickness(p)||'?')+' mm</span></div><div class="dim">'+esc(dim(p))+'</div><div class="path">'+esc(pathOf(p))+'</div><div class="badges">'+(li.assigned?'<span class="badge label">ĐÃ GÁN TEM</span>':'')+(bandCount(p)?'<span class="badge band">'+bandCount(p)+' CẠNH DÁN</span>':'')+'</div><div class="edgeRow">'+['U-','V+','U+','V-'].map((k,i)=>'<div class="edge '+(b[k]?'on':'')+'">'+['TRÁI','TRÊN','PHẢI','DƯỚI'][i]+(b[k]?' '+esc(b[k]):'')+'</div>').join('')+'</div></article>'}).join('');
  document.querySelectorAll('.card').forEach(el=>el.onclick=()=>{const hit=state.panels.find(p=>codeOf(p)===el.dataset.code);if(hit)openDetail(hit)});
}
function openDetail(p){
  const li=labelInfo(p),b=bandsOf(p);$('#dName').textContent=li.assigned?li.name:nameOf(p);
  const items=[['Mã tem',li.code||codeOf(p)],['Tên tấm',nameOf(p)],['Kích thước',dim(p)],['Độ dày',thickness(p)+' mm'],['Tag / Layer',p.tag||'—'],['Vật liệu',p.material||'—'],['Vị trí trong Model',pathOf(p)],['Cạnh trái',b['U-']||'Không dán'],['Cạnh trên',b['V+']||'Không dán'],['Cạnh phải',b['U+']||'Không dán'],['Cạnh dưới',b['V-']||'Không dán'],['UID',p.uid||p.panel_uid||'—']];
  $('#detailBody').innerHTML='<div class="detailGrid">'+items.map((x,i)=>'<div class="detailItem '+(i===6?'wide':'')+'"><span>'+esc(x[0])+'</span><b>'+esc(x[1])+'</b></div>').join('')+'</div>';
  $('#detailDialog').showModal();
}

function project3d(pt,c,v,scale,W,H){let x=pt[0]-c[0],y=pt[1]-c[1],z=pt[2]-c[2];let cy=Math.cos(v.yaw),sy=Math.sin(v.yaw),cp=Math.cos(v.pitch),sp=Math.sin(v.pitch);let x1=x*cy-y*sy,y1=x*sy+y*cy,z1=z;let y2=y1*cp-z1*sp,z2=y1*sp+z1*cp;return[W/2+x1*scale*v.zoom,H/2-z2*scale*v.zoom]}
function drawModel(){
  const cv=$('#modelCanvas'),boxes=state.model3d;if(!cv)return;const dpr=window.devicePixelRatio||1,W=cv.clientWidth||800,H=cv.clientHeight||360;cv.width=W*dpr;cv.height=H*dpr;const ctx=cv.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,W,H);
  if(!boxes.length){ctx.fillStyle='#7f96b3';ctx.font='14px Arial';ctx.fillText('Model chưa có dữ liệu 3D. Hãy Đồng bộ Web lại từ SketchUp.',20,40);return}
  const pts=[];boxes.forEach(b=>(b.corners||[]).forEach(p=>pts.push(p)));const c=[0,0,0];pts.forEach(p=>{c[0]+=p[0];c[1]+=p[1];c[2]+=p[2]});c[0]/=pts.length;c[1]/=pts.length;c[2]/=pts.length;let span=100;pts.forEach(p=>{span=Math.max(span,Math.abs(p[0]-c[0])*2,Math.abs(p[1]-c[1])*2,Math.abs(p[2]-c[2])*2)});const scale=Math.min(W,H)*.72/span,edges=[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];boxes.forEach(b=>{ctx.strokeStyle=b.label&&b.label.assigned?'#60a5fa':'#475569';ctx.lineWidth=b.label&&b.label.assigned?1.8:1;ctx.beginPath();edges.forEach(e=>{const a=project3d(b.corners[e[0]],c,state.view,scale,W,H),q=project3d(b.corners[e[1]],c,state.view,scale,W,H);ctx.moveTo(a[0],a[1]);ctx.lineTo(q[0],q[1])});ctx.stroke()});
}

function bindModel(){const cv=$('#modelCanvas');cv.onmousedown=e=>{state.view.drag=true;state.view.x=e.clientX;state.view.y=e.clientY};window.addEventListener('mouseup',()=>state.view.drag=false);window.addEventListener('mousemove',e=>{if(!state.view.drag)return;state.view.yaw+=(e.clientX-state.view.x)*.008;state.view.pitch+=(e.clientY-state.view.y)*.008;state.view.pitch=Math.max(-1.45,Math.min(1.45,state.view.pitch));state.view.x=e.clientX;state.view.y=e.clientY;drawModel()});cv.onwheel=e=>{e.preventDefault();state.view.zoom*=e.deltaY<0?1.12:.89;state.view.zoom=Math.max(.2,Math.min(7,state.view.zoom));drawModel()};cv.ondblclick=()=>{state.view={yaw:-.65,pitch:-.45,zoom:1,drag:false,x:0,y:0};drawModel()}}
function logout(){stopScanner();state.model=null;state.panels=[];state.labels=[];state.model3d=[];hideApp();setStatus('Sẵn sàng');setMsg('');}

function parseQr(raw){
  const s=String(raw||'').trim();if(!s)return false;
  try{const u=new URL(s);const id=u.searchParams.get('id')||'';const board=u.searchParams.get('board')||'';if(id)state.shareId=id;if(board)state.pendingBoard=board;handleQrResult();return true}catch(e){}
  const hit=findBoard(s);if(hit){stopScanner();$('#scanDialog').close();openDetail(hit);return true}
  if(/^TTB[-_]/i.test(s)){state.pendingBoard=s;handleQrResult();return true}
  return false;
}
function handleQrResult(){
  stopScanner();if($('#scanDialog').open)$('#scanDialog').close();
  if(state.model&&state.shareId===state.model.share_id){const hit=findBoard(state.pendingBoard);if(hit){openDetail(hit);return}}
  $('#qrModeHint').classList.remove('hidden');$('#qrModeHint').textContent='Đã đọc QR. Mã dự án: '+(state.shareId||'—')+(state.pendingBoard?' • Tấm: '+state.pendingBoard:'')+'. Hãy đăng nhập để xem dữ liệu.';hideApp();$('#projectLogin').focus();
}

async function startScanner(){
  const st=$('#scanStatus');st.textContent='Đang mở camera…';
  try{
    state.stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});
    const v=$('#qrVideo');v.srcObject=state.stream;await v.play();
    if('BarcodeDetector' in window){try{state.detector=new BarcodeDetector({formats:['qr_code']})}catch(e){state.detector=null}}
    st.textContent='Đưa QR tem vào giữa khung xanh.';
    scanFrame();
  }catch(e){st.textContent='Không mở được camera: '+(e.message||e)}
}
function stopScanner(){if(state.scanLoop)cancelAnimationFrame(state.scanLoop);state.scanLoop=0;if(state.stream){state.stream.getTracks().forEach(t=>t.stop());state.stream=null}const v=$('#qrVideo');if(v)v.srcObject=null}
async function scanFrame(){
  const v=$('#qrVideo'),st=$('#scanStatus');if(!state.stream||!v)return;
  try{
    if(state.detector){const codes=await state.detector.detect(v);if(codes&&codes.length&&parseQr(codes[0].rawValue)){st.textContent='Đã nhận QR.';return}}
    else if(window.jsQR&&v.videoWidth>0){const c=$('#qrCanvas'),ctx=c.getContext('2d');c.width=v.videoWidth;c.height=v.videoHeight;ctx.drawImage(v,0,0,c.width,c.height);const img=ctx.getImageData(0,0,c.width,c.height);const code=window.jsQR(img.data,img.width,img.height,{inversionAttempts:'dontInvert'});if(code&&parseQr(code.data)){st.textContent='Đã nhận QR.';return}}
  }catch(e){}
  state.scanLoop=requestAnimationFrame(scanFrame);
}
function openScanner(){if(!navigator.mediaDevices||!navigator.mediaDevices.getUserMedia){alert('Trình duyệt không hỗ trợ Camera.');return}$('#scanDialog').showModal();$('#scanStatus').textContent='Bấm BẬT CAMERA để quét.';}

function boot(){
  state.shareId=shareIdFromUrl();state.pendingBoard=boardFromUrl();
  $('#projectLogin').value=localStorage.getItem('tt_project_login')||'';
  if(state.shareId){$('#qrModeHint').classList.remove('hidden');$('#qrModeHint').textContent='QR đã xác định dự án'+(state.pendingBoard?' và tấm '+state.pendingBoard:'')+'. Nhập thông tin đăng nhập.'} if(new URLSearchParams(location.search).get('scanner')==='1'){setTimeout(openScanner,250)}
  bindModel();setStatus('CHỜ ĐĂNG NHẬP');
}

$('#loginBtn').onclick=login;$('#projectPassword').onkeydown=e=>{if(e.key==='Enter')login()};$('#togglePassword').onclick=()=>{const p=$('#projectPassword'),show=p.type==='password';p.type=show?'text':'password';$('#togglePassword').textContent=show?'ẨN':'HIỆN'};
$('#logoutBtn').onclick=logout;$('#closeDetail').onclick=()=>$('#detailDialog').close();
['#scanTopBtn','#scanLoginBtn','#scanProjectBtn'].forEach(s=>$(s).onclick=openScanner);$('#closeScanner').onclick=()=>{stopScanner();$('#scanDialog').close()};$('#startScanner').onclick=startScanner;$('#stopScanner').onclick=stopScanner;$('#manualQrBtn').onclick=()=>{if(!parseQr($('#manualQrText').value))$('#scanStatus').textContent='Không nhận được mã QR hợp lệ.'};
['search','thicknessFilter','labelFilter'].forEach(id=>$('#'+id).addEventListener(id==='search'?'input':'change',render));
boot();