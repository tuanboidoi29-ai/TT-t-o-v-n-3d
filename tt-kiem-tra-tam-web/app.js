const API='https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-model-api';
const $=s=>document.querySelector(s);
const state={panels:[],model:null};

function shareId(){
  const m=location.pathname.match(/\/m\/([^/?#]+)/);
  return decodeURIComponent(m?.[1]||new URLSearchParams(location.search).get('id')||'').trim();
}
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function dim(p){
  const d=p.kt_cat||p.cut_size||p.dimensions||p.size||'';
  if(typeof d==='string'&&d.trim())return d;
  const a=[p.length||p.dai,p.width||p.rong,p.thickness||p.do_day].filter(v=>v!==undefined&&v!==null&&v!=='');
  return a.length?a.join(' × ')+' mm':'—';
}
function edgeMap(p){
  const src=p.dan_canh||p.edge_banding||p.edges||{};
  const get=(...keys)=>{for(const k of keys){const v=src?.[k]??p?.[k];if(v!==undefined&&v!==null&&v!==false&&v!==0&&v!=='0'&&v!=='')return v}return null};
  return {top:get('tren','top'),right:get('phai','right'),bottom:get('duoi','bottom'),left:get('trai','left')};
}
function edgeCount(p){return Object.values(edgeMap(p)).filter(Boolean).length}
function thickness(p){
  const v=p.do_day??p.thickness??p.t??'';
  if(v!==''&&v!=null)return String(v);
  const s=dim(p);const m=s.match(/(?:x|×)\s*([\d.]+)\s*mm?\s*$/i);return m?m[1]:'';
}
function panelCode(p){return p.ma_tam||p.code||p.uid||p.panel_uid||p.id||'—'}
function panelName(p){return p.ten||p.name||p.panel_name||'Tấm chưa đặt tên'}
function panelPath(p){return p.path||p.vi_tri||p.location||p.parent_path||'Chưa có vị trí'}
function render(){
  const q=$('#search').value.trim().toLowerCase();
  const tf=$('#thicknessFilter').value;
  const ef=$('#edgeFilter').value;
  const rows=state.panels.filter(p=>{
    const text=[panelName(p),panelCode(p),panelPath(p),dim(p)].join(' ').toLowerCase();
    const passQ=!q||text.includes(q);
    const passT=!tf||thickness(p)===tf;
    const ec=edgeCount(p);
    const passE=!ef||(ef==='has'?ec>0:ec===0);
    return passQ&&passT&&passE;
  });
  $('#summary').textContent=`Đang hiển thị ${rows.length}/${state.panels.length} tấm.`;
  $('#list').innerHTML=rows.map((p,i)=>{
    const e=edgeMap(p);
    return `<article class="card" data-idx="${state.panels.indexOf(p)}">
      <div class="cardTop"><div><div class="name">${esc(panelName(p))}</div><div class="code">${esc(panelCode(p))}</div></div><span class="badge thk">${esc(thickness(p)||'?')} mm</span></div>
      <div class="dim">${esc(dim(p))}</div>
      <div class="path">${esc(panelPath(p))}</div>
      <div class="badges">${edgeCount(p)?`<span class="badge edge">${edgeCount(p)} cạnh dán</span>`:''}</div>
      <div class="edgebox"><div class="edgeTitle">DÁN CẠNH</div><div class="edgeRow">
        <div class="edge ${e.left?'on':''}">TRÁI${e.left?' '+esc(e.left):''}</div>
        <div class="edge ${e.top?'on':''}">TRÊN${e.top?' '+esc(e.top):''}</div>
        <div class="edge ${e.right?'on':''}">PHẢI${e.right?' '+esc(e.right):''}</div>
        <div class="edge ${e.bottom?'on':''}">DƯỚI${e.bottom?' '+esc(e.bottom):''}</div>
      </div></div>
    </article>`;
  }).join('');
  document.querySelectorAll('.card').forEach(el=>el.addEventListener('click',()=>openDetail(state.panels[Number(el.dataset.idx)])));
}
function openDetail(p){
  $('#dName').textContent=panelName(p);
  const e=edgeMap(p);
  const items=[
    ['Mã tấm',panelCode(p)],['Kích thước cắt',dim(p)],['Độ dày',thickness(p)?thickness(p)+' mm':'—'],
    ['Vị trí trong Model',panelPath(p)],['Tag / Layer',p.tag||p.layer||'—'],['Vật liệu',p.vat_lieu||p.material||'—'],
    ['Cạnh TRÁI',e.left||'Không dán'],['Cạnh TRÊN',e.top||'Không dán'],['Cạnh PHẢI',e.right||'Không dán'],['Cạnh DƯỚI',e.bottom||'Không dán'],
    ['UID',p.uid||p.panel_uid||'—']
  ];
  $('#detailBody').innerHTML='<div class="detailGrid">'+items.map((x,i)=>`<div class="detailItem ${i===3?'detailWide':''}"><span>${esc(x[0])}</span><b>${esc(x[1])}</b></div>`).join('')+'</div>';
  $('#detailDialog').showModal();
}
async function boot(){
  const id=shareId();
  if(!id){showError('QR/đường dẫn không có mã Model.');return}
  try{
    const res=await fetch(API+'?share_id='+encodeURIComponent(id),{cache:'no-store'});
    const j=await res.json();
    if(!res.ok||!j.ok)throw new Error(j.error==='not_found'?'Chưa có dữ liệu Model trên máy chủ. Hãy mở plugin và bấm đồng bộ QR chính.':(j.detail||j.error||'Không tải được dữ liệu'));
    state.model=j.model;
    const p=j.model.payload||{};
    state.panels=Array.isArray(p.panels)?p.panels:(Array.isArray(p.tam)?p.tam:[]);
    $('#modelName').textContent=j.model.model_name||p.model_name||'SketchUp Model';
    $('#modelId').textContent='Mã: '+id;
    $('#updatedAt').textContent='Cập nhật: '+new Date(j.model.updated_at).toLocaleString('vi-VN');
    $('#panelCount').textContent=state.panels.length;
    $('#edgeCount').textContent=state.panels.reduce((a,x)=>a+edgeCount(x),0);
    const th=[...new Set(state.panels.map(thickness).filter(Boolean))].sort((a,b)=>num(a)-num(b));
    $('#thicknessCount').textContent=th.length;
    $('#thicknessFilter').innerHTML='<option value="">Tất cả độ dày</option>'+th.map(v=>`<option value="${esc(v)}">${esc(v)} mm</option>`).join('');
    $('#modelCard').classList.remove('hidden');$('#controls').classList.remove('hidden');$('#summary').classList.remove('hidden');
    $('#status').textContent='DỮ LIỆU OK';$('#status').classList.add('ok');
    render();
  }catch(e){showError(e.message||String(e))}
}
function showError(msg){
  $('#status').textContent='LỖI';$('#status').classList.add('bad');
  $('#errorText').textContent=msg;$('#errorBox').classList.remove('hidden');
}
$('#closeDialog').addEventListener('click',()=>$('#detailDialog').close());
['search','thicknessFilter','edgeFilter'].forEach(id=>$('#'+id).addEventListener(id==='search'?'input':'change',render));
boot();