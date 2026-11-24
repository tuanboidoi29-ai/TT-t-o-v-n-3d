const API='https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-model-api';
const $=s=>document.querySelector(s);
const state={shareId:'',pendingBoard:'',pendingObject:'',model:null,panels:[],labels:[],objects:[],groupTree:[],selectedObject:'',mutedMaterialObjects:[],productionMode:false,productionScanned:[],lastProductionQr:'',hitTargets:[],model3d:[],textures:{},edges:[],tags:[],hiddenTags:[],explode:0,brightness:1.25,showEdges:true,background:'#e8edf3',viewMode:'color',view:{yaw:-.65,pitch:-.45,zoom:1,drag:false,x:0,y:0},stream:null,scanLoop:0,detector:null};

function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function shareIdFromUrl(){return String(new URLSearchParams(location.search).get('id')||'').trim()}
function boardFromUrl(){return String(new URLSearchParams(location.search).get('board')||'').trim()}
function objectFromUrl(){return String(new URLSearchParams(location.search).get('object')||'').trim()}
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

function savedProjects(){try{return JSON.parse(localStorage.getItem('tt_saved_projects')||'[]')}catch(e){return []}}
function rememberProject(model){
  const id=String(model?.share_id||'');if(!id)return;
  const p=model.payload||{},rows=savedProjects().filter(x=>x.share_id!==id);
  rows.unshift({share_id:id,name:model.project_login||model.model_name||p.model_name||'Dự án chưa đặt tên',model_name:model.model_name||p.model_name||'',revision:Number(model.revision||1),saved_at:model.last_saved_at||model.updated_at||new Date().toISOString()});
  localStorage.setItem('tt_saved_projects',JSON.stringify(rows.slice(0,60)));renderSavedProjects();
}
function renderSavedProjects(){
  const host=$('#savedProjectList');if(!host)return;const rows=savedProjects();
  const markup=rows.map(p=>'<button type="button" class="savedProjectRow" data-saved-id="'+esc(p.share_id)+'"><b>'+esc(p.name)+'</b><span>'+esc(p.share_id)+' · Rev '+Number(p.revision||1)+'</span><small>'+new Date(p.saved_at).toLocaleString('vi-VN')+'</small></button>').join('')||'<span class="smallHint">Chưa có dự án được lưu trên thiết bị này. Mở dự án một lần để lưu vào danh sách.</span>';
  ['#savedProjectList','#savedProjectListLogin'].forEach(sel=>{const node=$(sel);if(!node)return;node.innerHTML=markup;node.querySelectorAll('[data-saved-id]').forEach(b=>b.onclick=()=>{state.shareId=b.dataset.savedId;$('#projectLogin').value='';login()})});
}
function showApp(){ $('#loginCard').classList.add('hidden'); ['#projectCard','#modelPanel','#groupPanel','#historyPanel','#productionPanel','#controls','#summary'].forEach(s=>$(s).classList.remove('hidden')); $('#logoutBtn').classList.remove('hidden'); }
function hideApp(){ $('#loginCard').classList.remove('hidden'); ['#projectCard','#modelPanel','#groupPanel','#historyPanel','#productionPanel','#controls','#summary'].forEach(s=>$(s).classList.add('hidden')); $('#logoutBtn').classList.add('hidden'); $('#list').innerHTML=''; $('#modelObjectList').innerHTML=''; $('#groupTree').innerHTML=''; $('#historyList').innerHTML=''; }

async function login(){
  const login=$('#projectLogin').value.trim();
  if(!state.shareId&&!login){setMsg('Nhập Tên dự án hoặc Mã dự án.');return}
  $('#loginBtn').disabled=true;setMsg('Đang tìm dự án…');setStatus('ĐANG MỞ DỰ ÁN');
  try{
    const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'open',share_id:state.shareId,project_login:login})});
    const j=await res.json().catch(()=>({}));
    if(!res.ok||!j.ok){
      const map={project_code_required:'Nhập Tên dự án hoặc Mã dự án.',project_not_found:'Không tìm thấy dự án. Kiểm tra lại tên hoặc mã dự án.'};
      throw new Error(map[j.error]||j.detail||j.error||'Không mở được dự án');
    }
    state.shareId=j.model.share_id||state.shareId;
    if(login)localStorage.setItem('tt_project_login',login);
    rememberProject(j.model);
    loadModel(j.model);
    setMsg('Đã mở dự án.','ok');
  }catch(e){setStatus('KHÔNG MỞ ĐƯỢC','bad');setMsg(e.message||String(e))}
  finally{$('#loginBtn').disabled=false}
}

function loadModel(model){
  state.model=model||{};const p=state.model.payload||{};
  state.shareId=state.model.share_id||state.shareId;
  state.panels=Array.isArray(p.panels)?p.panels:(Array.isArray(p.boards)?p.boards:[]);
  state.labels=Array.isArray(p.labels)?p.labels:state.panels.filter(x=>labelInfo(x).assigned);
  state.objects=Array.isArray(p.objects)?p.objects:(Array.isArray(p.model3d)?p.model3d:[]);
  state.model3d=Array.isArray(p.model3d)?p.model3d:[];
  state.textures=p.textures&&typeof p.textures==='object'?p.textures:{};
  state.edges=Array.isArray(p.edges)?p.edges:[];
  state.tags=Array.isArray(p.tags)?p.tags:[];
  textureCache.forEach(t=>t.dispose());textureCache.clear();
  state.groupTree=Array.isArray(p.group_tree)?p.group_tree:[];
  state.hiddenTags=state.tags.filter(t=>t.visible===false).map(t=>String(t.name||''));
  state.selectedObject='';
  $('#modelName').textContent=state.model.model_name||p.model_name||'SketchUp Model';
  $('#modelId').textContent='Mã: '+state.shareId;
  $('#savedAt').textContent='Lưu: '+new Date(state.model.last_saved_at||state.model.updated_at||Date.now()).toLocaleString('vi-VN');
  $('#revision').textContent='Revision: '+String(state.model.revision||1);
  $('#panelCount').textContent=state.panels.length;
  $('#objectCount').textContent=state.objects.length;
  $('#objectCount').textContent=state.objects.length;
  $('#modelObjectCount').textContent=state.objects.length;
  $('#labelCount').textContent=state.labels.length;
  $('#bandCount').textContent=state.panels.reduce((a,p)=>a+bandCount(p),0);
  const rootMaterials=(state.objects||[]).filter(o=>Number(o.depth||0)===0);
  const materialTotals=rootMaterials.reduce((a,o)=>({textured:a.textured+Number(o.material_textures||0),colored:a.colored+Number(o.material_colors||0),unassigned:a.unassigned+Number(o.material_unassigned||0)}),{textured:0,colored:0,unassigned:0});
  const materialSummary=$('#materialSummary');if(materialSummary)materialSummary.textContent='Vật liệu thực tế: '+materialTotals.textured+' mặt có vân · '+materialTotals.colored+' mặt màu đơn sắc · '+materialTotals.unassigned+' mặt chưa gán';
  const th=[...new Set(state.panels.map(thickness).filter(Boolean))].sort((a,b)=>num(a)-num(b));
  $('#thicknessFilter').innerHTML='<option value="">Tất cả độ dày</option>'+th.map(v=>'<option value="'+esc(v)+'">'+esc(v)+' mm</option>').join('');
  state.viewMode='color';showApp();render();renderObjects();renderGroups();renderTagFilters();drawModel();renderObjectDetail();syncMaterialToggle();renderProductionCheck();loadHistory();const texturedTriangles=state.model3d.reduce((n,o)=>n+(Array.isArray(o.triangles)?o.triangles.filter(t=>t.tex||t.btex).length:0),0);if(materialTotals.textured>0&&(!Object.keys(state.textures).length||!texturedTriangles)){setStatus('CẢNH BÁO: MODEL CÓ MẶT GÁN TEXTURE NHƯNG DỮ LIỆU ẢNH/UV CHƯA ĐƯỢC ĐỒNG BỘ ĐẦY ĐỦ','bad')}else{setStatus(Object.keys(state.textures).length&&texturedTriangles?'MODEL 3D ĐANG HIỂN THỊ VẬT LIỆU & VÂN THỰC TẾ':'MODEL 3D MÀU ĐƠN SẮC ĐANG HIỂN THỊ','ok')}
  if(state.pendingObject){const hit=findObject(state.pendingObject);state.pendingObject='';if(hit)setTimeout(()=>{state.selectedObject=String(hit.uid||hit.id||'');renderObjects();drawModel();renderObjectDetail();syncMaterialToggle();},100);}
  else if(state.pendingBoard){const hit=findBoard(state.pendingBoard);state.pendingBoard='';if(hit)setTimeout(()=>openDetail(hit),100);}
}

function tagInventory(){
  const counts=new Map();
  const ensure=name=>{const n=String(name||'').trim();if(!n)return null;if(!counts.has(n))counts.set(n,{name:n,entities:0,faces:0,edges:0,abf:n.toUpperCase().startsWith('ABF_')});return counts.get(n)};
  (state.tags||[]).forEach(t=>{const row=ensure(t.name||t.tag);if(row){row.entities=Math.max(row.entities,Number(t.entity_count||0));row.faces=Math.max(row.faces,Number(t.face_count||0));row.edges=Math.max(row.edges,Number(t.edge_count||0));row.abf=row.abf||!!t.abf;row.visible=t.visible!==false}});
  (state.model3d||[]).forEach(obj=>{const row=ensure(obj.tag);if(row)row.entities=Math.max(row.entities,1)});
  (state.model3d||[]).forEach(obj=>(Array.isArray(obj.triangles)?obj.triangles:[]).forEach(tri=>{const row=ensure(tri.tag||obj.tag);if(row)row.faces=Math.max(row.faces,1)}));
  (state.edges||[]).forEach(edge=>{const row=ensure(edge.tag||edge.t);if(row)row.edges=Math.max(row.edges,1)});
  return [...counts.values()].sort((a,b)=>a.name.localeCompare(b.name,'vi'));
}
function toggleWebTag(tag,visible){
  state.hiddenTags=visible?state.hiddenTags.filter(x=>x!==tag):[...new Set([...state.hiddenTags,tag])];
  renderTagFilters();drawModel();
}
function renderAbfQuickFilters(){
  const host=$('#abfTagQuickFilters');if(!host)return;
  const tags=tagInventory().filter(t=>t.name.toUpperCase().startsWith('ABF_'));
  host.innerHTML=tags.map(t=>'<button type="button" class="tagQuickBtn '+(state.hiddenTags.includes(t.name)?'off':'on')+'" data-abf-tag="'+esc(t.name)+'" aria-pressed="'+(!state.hiddenTags.includes(t.name))+'"><b>'+esc(t.name)+'</b><small>'+t.edges.toLocaleString('vi-VN')+' cạnh · '+t.faces.toLocaleString('vi-VN')+' mặt</small></button>').join('')||'<span class="smallHint">Không có Tag bắt đầu bằng ABF_ trong model này.</span>';
  host.querySelectorAll('[data-abf-tag]').forEach(btn=>btn.onclick=()=>toggleWebTag(btn.dataset.abfTag,state.hiddenTags.includes(btn.dataset.abfTag)));
}
function renderTagFilters(){
  const host=$('#webTagFilters');if(!host)return;
  const tags=tagInventory();
  if(!tags.length){host.innerHTML='<span class="smallHint">Model chưa có dữ liệu Tags/Layers.</span>';renderAbfQuickFilters();return}
  host.innerHTML=tags.map(t=>'<label class="webTagItem"><input type="checkbox" data-web-tag="'+esc(t.name)+'" '+(state.hiddenTags.includes(t.name)?'':'checked')+'><span><b>'+esc(t.name)+'</b>'+(t.abf?'<em>ABF_</em>':'')+'</span><small>'+t.entities.toLocaleString('vi-VN')+' đối tượng · '+t.edges.toLocaleString('vi-VN')+' cạnh · '+t.faces.toLocaleString('vi-VN')+' mặt</small></label>').join('');
  host.querySelectorAll('[data-web-tag]').forEach(input=>input.addEventListener('change',()=>toggleWebTag(input.dataset.webTag,input.checked)));
  renderAbfQuickFilters();
}
function setAllWebTags(visible){
  state.hiddenTags=visible?[]:tagInventory().map(t=>t.name);
  renderTagFilters();drawModel();
}
function tagNamesForObject(o){
  if(!o)return [];
  const uid=String(o.uid||o.id||'');const names=new Set();
  if(o.tag)names.add(String(o.tag));
  (state.model3d||[]).forEach(root=>(root.triangles||[]).forEach(tri=>{if(String(tri.oid||tri.object_uid||root.uid||'')===uid&&tri.tag)names.add(String(tri.tag))}));
  (state.edges||[]).forEach(edge=>{if(String(edge.o||edge.object_uid||'')===uid&&(edge.t||edge.tag))names.add(String(edge.t||edge.tag))});
  return [...names].sort((a,b)=>a.localeCompare(b,'vi'));
}
function findBoard(token){const t=String(token||'').trim();return state.panels.find(p=>[p.uid,p.panel_uid,p.code,p.ma_tam,p.id].map(String).includes(t))||null}
function findObject(token){const t=String(token||'').trim();return state.objects.find(o=>[o.uid,o.id,o.persistent_id,o.code].map(String).includes(t))||state.model3d.find(o=>[o.uid,o.id,o.persistent_id].map(String).includes(t))||null}
function render(){
  const q=$('#search').value.trim().toLowerCase(),tf=$('#thicknessFilter').value,lf=$('#labelFilter').value;
  const rows=state.panels.filter(p=>{const li=labelInfo(p);const txt=[nameOf(p),codeOf(p),li.code,li.name,p.tag,p.material,pathOf(p),dim(p)].join(' ').toLowerCase();return(!q||txt.includes(q))&&(!tf||thickness(p)===tf)&&(!lf||(lf==='yes'?li.assigned:!li.assigned))});
  const rootMaterials=(state.objects||[]).filter(o=>Number(o.depth||0)===0);
  const totals=rootMaterials.reduce((a,o)=>({textured:a.textured+Number(o.material_textures||0),colored:a.colored+Number(o.material_colors||0),unassigned:a.unassigned+Number(o.material_unassigned||0)}),{textured:0,colored:0,unassigned:0});
  $('#summary').textContent='Đang hiển thị '+rows.length+'/'+state.panels.length+' tấm • '+state.labels.length+' tem đã lưu • Vật liệu: '+totals.textured+' mặt có vân, '+totals.colored+' mặt màu đơn sắc, '+totals.unassigned+' mặt chưa gán.';
  $('#list').innerHTML=rows.map(p=>{const li=labelInfo(p),b=bandsOf(p);return '<article class="card" data-code="'+esc(codeOf(p))+'"><div class="cardTop"><div><div class="name">'+esc(li.assigned?li.name:nameOf(p))+'</div><div class="code">'+esc(li.code||codeOf(p))+'</div></div><span class="badge thk">'+esc(thickness(p)||'?')+' mm</span></div><div class="dim">'+esc(dim(p))+'</div><div class="path">'+esc(pathOf(p))+'</div><div class="badges">'+(li.assigned?'<span class="badge label">ĐÃ GÁN TEM</span>':'')+(bandCount(p)?'<span class="badge band">'+bandCount(p)+' CẠNH DÁN</span>':'')+'</div><div class="edgeRow">'+['U-','V+','U+','V-'].map((k,i)=>'<div class="edge '+(b[k]?'on':'')+'">'+['TRÁI','TRÊN','PHẢI','DƯỚI'][i]+(b[k]?' '+esc(b[k]):'')+'</div>').join('')+'</div></article>'}).join('');
  document.querySelectorAll('.card').forEach(el=>el.onclick=()=>{const hit=state.panels.find(p=>codeOf(p)===el.dataset.code);if(hit)openDetail(hit)});
}
function openDetail(p){
  const li=labelInfo(p),b=bandsOf(p);$('#dName').textContent=li.assigned?li.name:nameOf(p);
  const items=[['Mã tem',li.code||codeOf(p)],['Tên tấm',nameOf(p)],['Kích thước',dim(p)],['Độ dày',thickness(p)+' mm'],['Tag / Layer',p.tag||'—'],['Vật liệu',p.material||'—'],['Vị trí trong Model',pathOf(p)],['Cạnh trái',b['U-']||'Không dán'],['Cạnh trên',b['V+']||'Không dán'],['Cạnh phải',b['U+']||'Không dán'],['Cạnh dưới',b['V-']||'Không dán'],['UID',p.uid||p.panel_uid||'—']];
  $('#detailBody').innerHTML='<div class="detailGrid">'+items.map((x,i)=>'<div class="detailItem '+(i===6?'wide':'')+'"><span>'+esc(x[0])+'</span><b>'+esc(x[1])+'</b></div>').join('')+'</div>';
  $('#detailDialog').showModal();
}
function objectLink(o){const u=new URL(location.href);u.searchParams.set('id',state.shareId);u.searchParams.set('object',o.uid||o.id||'');u.searchParams.delete('board');u.searchParams.delete('scanner');return u.toString()}
function renderGroupNode(n,depth=0){
  if(depth>30)return '';
  const boards=Array.isArray(n.boards)?n.boards:[];
  const children=Array.isArray(n.children)?n.children:[];
  const boardHtml=boards.length?'<div class="groupBoards"><b>Ván thuộc Group này ('+boards.length+')</b><div class="boardRows">'+boards.map(b=>'<div class="boardRow"><span>'+esc(b.name||'Ván chưa đặt tên')+'</span><small>'+esc((b.dimensions||[]).join(' × '))+' mm · '+esc(b.material||'Chưa có vật liệu')+' · '+esc(b.material_status||'Chưa xác định trạng thái vật liệu')+' · '+esc(b.tag||'')+'</small></div>').join('')+'</div></div>':'<div class="groupEmpty">Không có ván trực tiếp trong cụm này.</div>';
  const childHtml=children.map(c=>renderGroupNode(c,depth+1)).join('');
  return '<details class="groupNode" '+(depth===0?'open':'')+'><summary><span><b>'+esc(n.name||'Group')+'</b><small>'+esc(n.material_status||'Chưa xác định trạng thái vật liệu')+' · '+esc(n.path||'')+'</small></span><em>'+Number(n.board_count||boards.length||0)+' ván</em></summary><div class="groupContent">'+boardHtml+(childHtml?'<div class="nestedGroups"><b>Group con</b>'+childHtml+'</div>':'')+'</div></details>';
}
function renderGroups(){
  const tree=state.groupTree||[];
  $('#groupCount').textContent=tree.length+' cụm gốc · '+state.panels.length+' ván';
  $('#groupTree').innerHTML=tree.map(n=>renderGroupNode(n)).join('')||'<div class="muted">Model chưa có cấu trúc Group lồng nhau.</div>';
}
async function loadHistory(){
  if(!state.shareId)return;
  try{
    const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'history',share_id:state.shareId})});
    const j=await res.json();if(!res.ok||!j.ok)throw new Error(j.detail||j.error||'Lỗi đọc lịch sử');
    const rows=j.history||[];$('#historyCount').textContent=rows.length+' phiên bản';
    $('#historyList').innerHTML=rows.map(h=>'<div class="historyRow"><b>Revision '+Number(h.revision||0)+'</b><span>'+esc(h.model_name||'Model')+'</span><small>'+Number(h.panel_count||0)+' tấm · '+new Date(h.saved_at).toLocaleString('vi-VN')+'</small></div>').join('')||'<div class="muted">Chưa có lịch sử đồng bộ.</div>';
  }catch(e){$('#historyList').textContent='Không tải được lịch sử: '+(e.message||e)}
}

function renderObjects(){const q=($('#modelObjectSearch')?.value||'').trim().toLowerCase();const rows=state.objects.filter(o=>[o.name,o.uid,o.type,o.tag,o.material,(o.dimensions||[]).join(' '),tagNamesForObject(o).join(' ')].join(' ').toLowerCase().includes(q));$('#modelObjectCount').textContent=rows.length+'/'+state.objects.length;$('#modelObjectList').innerHTML=rows.map(o=>{const tags=tagNamesForObject(o);return '<button type="button" class="modelObjectRow '+(String(o.uid||o.id||'')===String(state.selectedObject)?'selected':'')+'" data-openobj="'+esc(o.uid||o.id||'')+'"><b>'+esc(o.name||'Đối tượng chưa đặt tên')+'</b><span>'+esc(o.type||'Object')+' · '+esc((o.dimensions||[]).join(' × '))+' mm</span><small>'+esc(o.material_status||'Chưa xác định trạng thái vật liệu')+'</small><small>Tag: '+esc(tags.join(' · ')||o.tag||'Untagged')+'</small><small>'+esc(o.path||o.uid||'')+'</small></button>'}).join('')||'<div class="muted modelEmpty">Không có đối tượng phù hợp.</div>';document.querySelectorAll('[data-openobj]').forEach(b=>b.onclick=()=>{const o=findObject(b.dataset.openobj);if(o){openObject(o);renderObjects();const target=document.querySelector('[data-openobj="'+CSS.escape(b.dataset.openobj)+'"]');target?.scrollIntoView({block:'nearest',behavior:'smooth'})}})}
function openObject(o){const uid=String(o.uid||o.id||'');state.selectedObject=uid;drawModel();renderObjects();renderObjectDetail();syncMaterialToggle();setStatus('ĐÃ LÀM SÁNG: '+(o.name||uid),'ok')}
function toggleSelectedMaterial(){
  const uid=String(state.selectedObject||'');if(!uid)return;
  const set=new Set(state.mutedMaterialObjects||[]);
  if(set.has(uid))set.delete(uid);else set.add(uid);
  state.mutedMaterialObjects=[...set];ttThreeModelRef=null;drawModel();renderObjectDetail();
  const muted=set.has(uid);setStatus(muted?'ĐÃ TẮT MÀU / VẬT LIỆU ĐỐI TƯỢNG':'ĐÃ KHÔI PHỤC MÀU / VẬT LIỆU GỐC','ok');
}
function syncMaterialToggle(){
  const b=$('#toggleSelectedMaterialBtn');if(!b)return;
  const uid=String(state.selectedObject||''),muted=state.mutedMaterialObjects.includes(uid);
  b.disabled=!uid;b.textContent=muted?'BẬT LẠI MÀU ĐỐI TƯỢNG':'TẮT MÀU ĐỐI TƯỢNG';
  b.classList.toggle('active',!!uid&&muted);
}
function renderObjectDetail(){const host=$('#objectDetails');if(!host)return;const o=findObject(state.selectedObject);if(!o){host.innerHTML='<div class="objectDetailsEmpty">Chọn tên đối tượng để xem thông tin chi tiết tại đây.</div>';return}const uid=o.uid||o.id||'',tags=tagNamesForObject(o),abf=tags.filter(t=>t.toUpperCase().startsWith('ABF_')),edgeCount=(state.edges||[]).filter(e=>String(e.o||e.object_uid||'')===String(uid)).length,items=[['Tên đối tượng / nhãn',o.name||'—'],['Mã định danh',uid||'—'],['Loại',o.type||'—'],['Cấp Group',o.depth??'—'],['Đường dẫn trong Model',o.path||'—'],['Kích thước bao',(o.dimensions||[]).join(' × ')+' mm'],['Group con trực tiếp',o.child_count??0],['Tag / Layer trực tiếp',o.tag||'Untagged'],['Tất cả Tag/Layers gắn trong đối tượng',tags.join(' · ')||'Không có'],['Tag ABF_ / cạnh dán',abf.join(' · ')||'Không có'],['Số cạnh hình học đã xuất',edgeCount],['Vật liệu',o.material||'—'],['Trạng thái vật liệu',o.material_status||'Chưa xác định'],['Mặt có texture / vân',o.material_textures??0],['Mặt có màu đơn sắc',o.material_colors??0],['Mặt chưa gán vật liệu',o.material_unassigned??0],['Persistent ID',o.persistent_id||'—'],['Số tam giác 3D',o.triangle_count||0]];host.innerHTML='<div class="objectDetailsHead"><b>CHI TIẾT ĐỐI TƯỢNG ĐANG CHỌN</b><button type="button" class="secondary" id="objectQrButton">HIỆN MÃ QR</button></div><div class="detailGrid">'+items.map((x,i)=>'<div class="detailItem '+(i===0||i===8||i===9?'wide':'')+'"><span>'+esc(x[0])+'</span><b>'+esc(x[1])+'</b></div>').join('')+'</div><div id="objectDetailQr" class="qrHolder"></div><p class="objectMeta">Quét QR bằng camera điện thoại để mở đúng đối tượng trong trang xem Model.</p>';$('#objectQrButton').onclick=()=>showObjectQr(uid,$('#objectDetailQr'))}
function showObjectQr(uid,holder){const o=findObject(uid);if(!o||!holder)return;holder.innerHTML='';const url=objectLink(o);if(window.QRCode){new QRCode(holder,{text:url,width:132,height:132,correctLevel:QRCode.CorrectLevel.M})}else{holder.textContent=url}}
function printAllQrs(){const grid=$('#qrPrintGrid');grid.innerHTML='';state.objects.forEach(o=>{const card=document.createElement('div');card.className='qrPrintCard';const title=document.createElement('b');title.textContent=o.name||'Đối tượng';const code=document.createElement('small');code.textContent=o.uid||'';const qr=document.createElement('div');qr.className='qrPrintCode';card.append(title,code,qr);grid.appendChild(card);if(window.QRCode)new QRCode(qr,{text:objectLink(o),width:112,height:112,correctLevel:QRCode.CorrectLevel.M});else qr.textContent=objectLink(o)});grid.classList.remove('hidden');setTimeout(()=>window.print(),350)}
window.onafterprint=()=>$('#qrPrintGrid').classList.add('hidden');

function project3d(pt,c,v,scale,W,H){let x=pt[0]-c[0],y=pt[1]-c[1],z=pt[2]-c[2];if(state.viewMode==='2d')return[W/2+x*scale*v.zoom,H/2-y*scale*v.zoom,z];let cy=Math.cos(v.yaw),sy=Math.sin(v.yaw),cp=Math.cos(v.pitch),sp=Math.sin(v.pitch);let x1=x*cy-y*sy,y1=x*sy+y*cy,z1=z;let y2=y1*cp-z1*sp,z2=y1*sp+z1*cp;return[W/2+x1*scale*v.zoom,H/2-z2*scale*v.zoom,y2]}
let ttThreeScene=null,ttThreeCamera=null,ttThreeRenderer=null,ttThreeRoot=null,ttThreeCenter=null,ttThreeRadius=1000,ttThreeRaycaster=null,ttThreePointer=null,ttThreeModelRef=null,ttThreeSelectedRef='',ttThreeHiddenTagsRef='',ttThreeMutedRef='';
const textureCache=new Map();
function getModelTexture(id){
  const key=String(id||'');if(!key||!state.textures[key])return null;
  if(textureCache.has(key))return textureCache.get(key);
  try{
    const tex=new THREE.TextureLoader().load(state.textures[key]);
    tex.colorSpace=THREE.SRGBColorSpace;tex.wrapS=THREE.RepeatWrapping;tex.wrapT=THREE.RepeatWrapping;
    tex.anisotropy=Math.min(8,ttThreeRenderer?.capabilities?.getMaxAnisotropy?.()||1);
    textureCache.set(key,tex);return tex;
  }catch(e){return null}
}
function initThreeModel(){
  const cv=$('#modelCanvas');if(!cv||!window.THREE)return false;
  if(ttThreeRenderer)return true;
  const T=window.THREE;
  ttThreeRenderer=new T.WebGLRenderer({canvas:cv,antialias:true,alpha:false,preserveDrawingBuffer:false});
  ttThreeRenderer.setPixelRatio(Math.min(window.devicePixelRatio||1,2));
  ttThreeRenderer.outputColorSpace=T.SRGBColorSpace;
  ttThreeRenderer.toneMapping=T.NoToneMapping;
  ttThreeRenderer.toneMappingExposure=1;
  ttThreeScene=new T.Scene();ttThreeScene.background=new T.Color(state.background||'#e8edf3');
  ttThreeCamera=new T.PerspectiveCamera(38,1,0.1,10000000);
  ttThreeScene.add(new T.HemisphereLight(0xffffff,0x8b98a8,2.4));
  const key=new T.DirectionalLight(0xffffff,2.5);key.position.set(1,-2,3);ttThreeScene.add(key);
  const fill=new T.DirectionalLight(0xffffff,1.25);fill.position.set(-2,1,1);ttThreeScene.add(fill);
  ttThreeRoot=new T.Group();ttThreeScene.add(ttThreeRoot);
  ttThreeRaycaster=new T.Raycaster();ttThreePointer=new T.Vector2();
  return true;
}
function buildThreeGeometry(){
  if(!initThreeModel())return;
  const T=window.THREE;
  while(ttThreeRoot.children.length){
    const child=ttThreeRoot.children.pop();ttThreeRoot.remove(child);
    child.geometry?.dispose();if(Array.isArray(child.material))child.material.forEach(m=>m.dispose());else child.material?.dispose();
  }
  const hiddenTags=new Set(state.hiddenTags||[]);
  const objectMap=new Map((state.objects||[]).map(o=>[String(o.uid||o.id||''),o]));
  const triGroups=new Map(),edgeGroups=new Map(),all=[];
  (state.model3d||[]).forEach(root=>{
    (Array.isArray(root.triangles)?root.triangles:[]).forEach(tri=>{
      if(hiddenTags.has(String(tri.tag||root.tag||'')))return;
      const uid=String(tri.object_uid||tri.oid||root.uid||root.id||'');
      if(!triGroups.has(uid))triGroups.set(uid,[]);
      triGroups.get(uid).push(tri);
    });
  });
  (state.edges||[]).forEach(edge=>{
    if(hiddenTags.has(String(edge.tag||edge.t||'')))return;
    const uid=String(edge.object_uid||edge.o||'');
    if(!edgeGroups.has(uid))edgeGroups.set(uid,[]);
    edgeGroups.get(uid).push(edge);
  });
  const modelBounds=new T.Box3();
  triGroups.forEach(tris=>tris.forEach(tri=>(tri.v||[]).forEach(p=>modelBounds.expandByPoint(new T.Vector3(Number(p[0])||0,Number(p[1])||0,Number(p[2])||0)))));
  edgeGroups.forEach(edges=>edges.forEach(edge=>(edge.v||[]).forEach(p=>modelBounds.expandByPoint(new T.Vector3(Number(p[0])||0,Number(p[1])||0,Number(p[2])||0)))));
  ttThreeCenter=modelBounds.isEmpty()?new T.Vector3(0,0,0):modelBounds.getCenter(new T.Vector3());
  const explodeVector=(points)=>{
    if(!points.length)return [0,0,0];
    const c=points.reduce((a,p)=>[a[0]+p[0]/points.length,a[1]+p[1]/points.length,a[2]+p[2]/points.length],[0,0,0]);
    const dx=c[0]-ttThreeCenter.x,dy=c[1]-ttThreeCenter.y,dz=c[2]-ttThreeCenter.z;
    const n=Math.hypot(dx,dy,dz)||1;return [dx/n,dy/n,dz/n];
  };
  const objectVectors=new Map();
  triGroups.forEach((tris,uid)=>{
    const selected=uid===String(state.selectedObject||'');
    const batches=new Map(),points=[];
    const addTriangle=(tri,side)=>{
      const muted=state.mutedMaterialObjects.includes(uid);const texId=muted?'':String(side==='front'?(tri.tex||''):(tri.btex||''));
      const uv=side==='front'?tri.uv:tri.buv;
      const usableTexture=!!(texId&&state.textures[texId]&&Array.isArray(uv)&&uv.length===3&&uv.every(p=>Array.isArray(p)&&p.length>=2));
      const key=side+':'+(usableTexture?texId:'none');
      if(!batches.has(key))batches.set(key,{side,texId:usableTexture?texId:'',positions:[],colors:[],uvs:[]});
      const batch=batches.get(key),baseColor=side==='front'?(tri.c||'#f2f2f2'):(tri.bc||'#b8c7d9');
      const color=new T.Color(muted?'#aeb8c4':(selected?(usableTexture?'#ffffff':'#ffb020'):baseColor));
      tri.v.forEach((p,i)=>{
        const x=Number(p[0])||0,y=Number(p[1])||0,z=Number(p[2])||0;
        batch.positions.push(x,y,z);batch.colors.push(color.r,color.g,color.b);points.push([x,y,z]);all.push([x,y,z]);
        if(usableTexture)batch.uvs.push(Number(uv[i][0])||0,Number(uv[i][1])||0);
      });
    };
    tris.forEach(tri=>{if(Array.isArray(tri.v)&&tri.v.length===3){addTriangle(tri,'front');addTriangle(tri,'back')}});
    const vec=explodeVector(points);objectVectors.set(uid,vec);
    batches.forEach(batch=>{
      if(!batch.positions.length)return;
      const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(batch.positions,3));geo.setAttribute('color',new T.Float32BufferAttribute(batch.colors,3));
      if(batch.texId&&batch.uvs.length===batch.positions.length/3*2)geo.setAttribute('uv',new T.Float32BufferAttribute(batch.uvs,2));
      geo.computeVertexNormals();
      const map=batch.texId?getModelTexture(batch.texId):null;
      const mat=new T.MeshBasicMaterial({vertexColors:true,side:batch.side==='front'?T.FrontSide:T.BackSide,map:map||null,color:new T.Color(state.brightness,state.brightness,state.brightness)});
      const mesh=new T.Mesh(geo,mat);mesh.userData.uid=uid;mesh.userData.explodeVector=vec;ttThreeRoot.add(mesh);
    });
  });
  edgeGroups.forEach((edges,uid)=>{
    const coords=[],pts=[];
    edges.forEach(e=>{if(!Array.isArray(e.v)||e.v.length!==2)return;e.v.forEach(p=>{const q=[Number(p[0])||0,Number(p[1])||0,Number(p[2])||0];coords.push(...q);pts.push(q);all.push(q)})});
    if(!coords.length)return;
    const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(coords,3));
    const selected=uid===String(state.selectedObject||'');
    const line=new T.LineSegments(geo,new T.LineBasicMaterial({color:selected?0xf59e0b:0x27364a,transparent:true,opacity:selected?1:.78}));
    line.userData.uid=uid;line.userData.isEdge=true;line.userData.explodeVector=objectVectors.get(uid)||explodeVector(pts);ttThreeRoot.add(line);
  });
  if(!all.length)(state.model3d||[]).forEach(o=>(o.corners||[]).forEach(p=>all.push(p)));
  if(!all.length){ttThreeCenter=new T.Vector3(0,0,0);ttThreeRadius=1000;return}
  const bounds=new T.Box3();all.forEach(p=>bounds.expandByPoint(new T.Vector3(p[0],p[1],p[2])));
  ttThreeCenter=bounds.getCenter(new T.Vector3());const size=bounds.getSize(new T.Vector3());
  ttThreeRadius=Math.max(size.x,size.y,size.z,1)*1.8;ttThreeRoot.position.set(-ttThreeCenter.x,-ttThreeCenter.y,-ttThreeCenter.z);
  ttThreeModelRef=state.model3d;ttThreeSelectedRef=String(state.selectedObject||'');ttThreeHiddenTagsRef=JSON.stringify([...(state.hiddenTags||[])].sort());
  ttThreeMutedRef=JSON.stringify([...(state.mutedMaterialObjects||[])].sort());
}
function drawModel(){
  const cv=$('#modelCanvas');if(!cv)return;
  if(!window.THREE){const ctx=cv.getContext('2d');if(ctx){ctx.clearRect(0,0,cv.width,cv.height);ctx.fillStyle='#334155';ctx.font='14px Arial';ctx.fillText('Đang tải bộ dựng 3D…',18,32)}return}
  if(!initThreeModel())return;
  if(ttThreeModelRef!==state.model3d||ttThreeSelectedRef!==String(state.selectedObject||'')||ttThreeHiddenTagsRef!==JSON.stringify([...(state.hiddenTags||[])].sort())||ttThreeMutedRef!==JSON.stringify([...(state.mutedMaterialObjects||[])].sort())||!ttThreeRoot.children.length)buildThreeGeometry();
  const w=Math.max(1,cv.clientWidth||800),h=Math.max(1,cv.clientHeight||360);
  const pixelRatio=Math.min(window.devicePixelRatio||1,2);
  if(cv.width!==Math.round(w*pixelRatio)||cv.height!==Math.round(h*pixelRatio)){ttThreeRenderer.setSize(w,h,false);ttThreeCamera.aspect=w/h;ttThreeCamera.updateProjectionMatrix()}
  const yaw=state.view.yaw,pitch=Math.max(-1.45,Math.min(1.45,state.view.pitch));
  const distance=ttThreeRadius/Math.max(.2,Math.min(12,state.view.zoom));
  ttThreeCamera.position.set(distance*Math.cos(pitch)*Math.sin(yaw),-distance*Math.cos(pitch)*Math.cos(yaw),distance*Math.sin(pitch));
  ttThreeCamera.up.set(0,0,1);ttThreeCamera.lookAt(0,0,0);
  ttThreeCamera.near=Math.max(.01,distance/10000);ttThreeCamera.far=Math.max(10000,distance*100);ttThreeCamera.updateProjectionMatrix();
  ttThreeRoot.children.forEach(child=>{
    if(child.userData.explodeVector){const k=state.explode*ttThreeRadius*.42;child.position.set(child.userData.explodeVector[0]*k,child.userData.explodeVector[1]*k,child.userData.explodeVector[2]*k)}
    if(child.userData.isEdge)child.visible=!!state.showEdges;
  });
  ttThreeRenderer.render(ttThreeScene,ttThreeCamera);
}

function pickModelObject(e){
  if(!ttThreeRenderer||!ttThreeCamera||!ttThreeRaycaster)return;
  const cv=$('#modelCanvas'),r=cv.getBoundingClientRect();
  ttThreePointer.set(((e.clientX-r.left)/r.width)*2-1,-((e.clientY-r.top)/r.height)*2+1);
  ttThreeRaycaster.setFromCamera(ttThreePointer,ttThreeCamera);
  const hits=ttThreeRaycaster.intersectObjects(ttThreeRoot.children.filter(x=>x.isMesh),false);
  if(!hits.length)return;
  const uid=hits[0].object.userData.uid;
  const o=findObject(uid);if(o){openObject(o);const row=document.querySelector('[data-openobj="'+CSS.escape(uid)+'"]');row?.scrollIntoView({block:'nearest',behavior:'smooth'})}
}
function bindModel(){
  $('#showAllTagsBtn').onclick=()=>setAllWebTags(true);
  $('#hideAllTagsBtn').onclick=()=>setAllWebTags(false);
  const cv=$('#modelCanvas');
  $('#viewXrayBtn').onclick=()=>{state.viewMode='color';$('#viewXrayBtn').classList.add('active');drawModel();setStatus('GÓC NHÌN 3D MÀU','ok')};
  $('#modelObjectSearch').oninput=renderObjects;
  $('#printQrBtn').onclick=printAllQrs;
  $('#toggleSelectedMaterialBtn').onclick=toggleSelectedMaterial;
  $('#productionCheckBtn').onclick=startProductionCheck;
  $('#finishProductionCheckBtn').onclick=finishProductionCheck;
  $('#explodeSlider').oninput=e=>{state.explode=Number(e.target.value)/100;$('#explodeValue').textContent=e.target.value+'%';drawModel()};
  $('#brightnessSlider').oninput=e=>{state.brightness=Number(e.target.value)/100;$('#brightnessValue').textContent=e.target.value+'%';ttThreeModelRef=null;drawModel()};
  $('#backgroundColor').oninput=e=>{state.background=e.target.value;if(ttThreeScene)ttThreeScene.background.set(state.background);drawModel()};
  $('#showEdgesToggle').onchange=e=>{state.showEdges=!!e.target.checked;drawModel()};
  $('#resetExplodeBtn').onclick=()=>{$('#explodeSlider').value=0;state.explode=0;$('#explodeValue').textContent='0%';drawModel()};
  $('#refreshModelBtn').onclick=reloadCurrentProject;
  $('#refreshSavedProjects').onclick=renderSavedProjects;
  $('#refreshSavedProjectsLogin').onclick=renderSavedProjects;
  renderSavedProjects();
  // Pointer events hỗ trợ chuột, bút cảm ứng và màn hình điện thoại.
  const pointers=new Map();
  let pinchStart=0,pinchZoom=1,lastTap=0;
  const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
  cv.style.cursor='grab';
  cv.addEventListener('pointerdown',e=>{
    e.preventDefault();
    cv.setPointerCapture?.(e.pointerId);
    pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
    state.view.drag=true;state.view.dragMoved=false;
    if(pointers.size===1){state.view.x=e.clientX;state.view.y=e.clientY;cv.style.cursor='grabbing'}
    if(pointers.size===2){const p=[...pointers.values()];pinchStart=distance(p[0],p[1]);pinchZoom=state.view.zoom;state.view.dragMoved=true}
  });
  cv.addEventListener('pointermove',e=>{
    if(!pointers.has(e.pointerId))return;
    const prev=pointers.get(e.pointerId);pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});
    if(pointers.size>=2){
      const p=[...pointers.values()],d=distance(p[0],p[1]);
      if(pinchStart>0){state.view.zoom=Math.max(.2,Math.min(12,pinchZoom*d/pinchStart));state.view.dragMoved=true;drawModel()}
      return;
    }
    const dx=e.clientX-prev.x,dy=e.clientY-prev.y;
    if(Math.abs(dx)+Math.abs(dy)>2)state.view.dragMoved=true;
    state.view.yaw+=dx*.008;state.view.pitch+=dy*.008;
    state.view.pitch=Math.max(-1.45,Math.min(1.45,state.view.pitch));
    state.view.x=e.clientX;state.view.y=e.clientY;drawModel();
  });
  const endPointer=e=>{
    if(!pointers.has(e.pointerId))return;
    pointers.delete(e.pointerId);
    if(pointers.size===1){const p=[...pointers.values()][0];state.view.x=p.x;state.view.y=p.y;pinchStart=0}
    else if(pointers.size===0){state.view.drag=false;pinchStart=0;cv.style.cursor='grab';setTimeout(()=>{state.view.dragMoved=false},80)}
  };
  cv.addEventListener('pointerup',endPointer);
  cv.addEventListener('pointercancel',endPointer);
  cv.addEventListener('lostpointercapture',endPointer);
  cv.addEventListener('click',e=>{
    if(state.view.dragMoved)return;
    const now=Date.now();
    if(now-lastTap<320){state.view={...state.view,yaw:-.65,pitch:-.45,zoom:1,drag:false,x:0,y:0};drawModel();lastTap=0;return}
    lastTap=now;pickModelObject(e);
  });
  cv.addEventListener('wheel',e=>{e.preventDefault();state.view.zoom*=e.deltaY<0?1.12:.89;state.view.zoom=Math.max(.2,Math.min(12,state.view.zoom));drawModel()},{passive:false});
  cv.addEventListener('dblclick',e=>{e.preventDefault();state.view={...state.view,yaw:-.65,pitch:-.45,zoom:1,drag:false,x:0,y:0};drawModel()});
}
async function reloadCurrentProject(){
  if(!state.shareId)return;
  const btn=$('#refreshModelBtn');if(btn)btn.disabled=true;setStatus('ĐANG TẢI LẠI DỰ ÁN');
  try{const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'open',share_id:state.shareId})});const j=await res.json().catch(()=>({}));if(!res.ok||!j.ok)throw new Error(j.detail||j.error||'Không tải lại được dự án');rememberProject(j.model);loadModel(j.model);setStatus('ĐÃ CẬP NHẬT DỮ LIỆU MỚI NHẤT','ok')}
  catch(e){setStatus('TẢI LẠI THẤT BẠI','bad');alert(e.message||String(e))}
  finally{if(btn)btn.disabled=false}
}
function logout(){stopScanner();state.model=null;state.shareId='';state.panels=[];state.labels=[];state.objects=[];state.groupTree=[];state.model3d=[];state.edges=[];state.tags=[];state.textures={};state.selectedObject='';state.mutedMaterialObjects=[];state.productionMode=false;state.productionScanned=[];state.hitTargets=[];hideApp();renderSavedProjects();setStatus('Sẵn sàng');setMsg('');}

function parseQr(raw){
  const s=String(raw||'').trim();if(!s)return false;
  if(state.productionMode)return registerProductionQr(s);
  try{const u=new URL(s);const id=u.searchParams.get('id')||'';const board=u.searchParams.get('board')||'';const object=u.searchParams.get('object')||'';if(id)state.shareId=id;state.pendingBoard=board;state.pendingObject=object;handleQrResult();return true}catch(e){}
  const objectHit=findObject(s);if(objectHit){stopScanner();$('#scanDialog').close();openObject(objectHit);return true}
  const hit=findBoard(s);if(hit){stopScanner();$('#scanDialog').close();openDetail(hit);return true}
  if(/^TTB[-_]/i.test(s)){state.pendingBoard=s;handleQrResult();return true}
  return false;
}
function productionExpected(){
  return state.objects.filter(o=>o.is_board===true||Number(o.child_count||0)===0);
}
function resumeProductionScanner(){setTimeout(()=>{if(state.stream&&state.productionMode)state.scanLoop=requestAnimationFrame(scanFrame)},550)}
function registerProductionQr(raw){
  const s=String(raw||'').trim();let token=s,project='';
  try{const u=new URL(s);project=u.searchParams.get('id')||'';token=u.searchParams.get('object')||u.searchParams.get('board')||''}catch(e){}
  if(project&&project!==String(state.shareId)){const st=$('#scanStatus');if(st)st.textContent='QR THUỘC DỰ ÁN KHÁC — KHÔNG GHI NHẬN';resumeProductionScanner();return true}
  const obj=findObject(token)||findBoard(token);
  if(!obj){const st=$('#scanStatus');if(st)st.textContent='Không tìm thấy cấu kiện trong Model: '+token;resumeProductionScanner();return true}
  const uid=String(obj.uid||obj.id||obj.code||'');
  const expected=productionExpected();
  if(!expected.some(o=>String(o.uid||o.id||'')===uid)){const st=$('#scanStatus');if(st)st.textContent='Mã QR này không phải cấu kiện sản xuất cuối cùng: '+(obj.name||uid);resumeProductionScanner();return true}
  if(state.productionScanned.includes(uid)){const st=$('#scanStatus');if(st)st.textContent='ĐÃ QUÉT TRƯỚC ĐÓ: '+(obj.name||uid);resumeProductionScanner();return true}
  state.productionScanned.push(uid);renderProductionCheck();
  const st=$('#scanStatus');if(st)st.textContent='ĐÃ NHẬN: '+(obj.name||uid)+' · '+state.productionScanned.length+'/'+expected.length;
  resumeProductionScanner();return true;
}
function productionDimensions(o){const d=Array.isArray(o.dimensions)?o.dimensions:[];return d.length?d.map(v=>Number(v).toFixed(Number(v)%1?1:0)).join(' × ')+' mm':'Chưa có kích thước'}
function renderProductionCheck(){
  const host=$('#productionResults');if(!host)return;
  const expected=productionExpected(),scanned=new Set(state.productionScanned),missing=expected.filter(o=>!scanned.has(String(o.uid||o.id||'')));
  const pct=expected.length?Math.round(scanned.size/expected.length*100):0;
  $('#productionProgress').textContent=scanned.size+'/'+expected.length+' cấu kiện · '+pct+'%';
  $('#productionProgressBar').style.width=pct+'%';
  $('#productionScannedCount').textContent=scanned.size;
  $('#productionMissingCount').textContent=missing.length;
  const rows=(items,kind)=>items.map(o=>{const uid=String(o.uid||o.id||''),dim=productionDimensions(o);return '<button type="button" class="productionItem '+kind+'" data-production-object="'+esc(uid)+'"><span class="productionItemName"><b>'+esc(o.name||'Cấu kiện chưa đặt tên')+'</b><small>'+esc(uid)+'</small></span><span class="productionItemMeta">'+esc(dim)+'<small>'+esc(o.path||'')+'</small></span><span class="productionItemAction">'+(kind==='missing'?'CÒN THIẾU':'ĐÃ QUÉT')+' · XEM 3D</span></button>'}).join('');
  const done=expected.filter(o=>scanned.has(String(o.uid||o.id||'')));host.innerHTML=expected.length?'<div class="productionResultHead"><b>'+ (missing.length?'CÒN THIẾU '+missing.length+' CẤU KIỆN':'ĐÃ QUÉT ĐỦ TẤT CẢ CẤU KIỆN')+'</b><span>'+scanned.size+' / '+expected.length+'</span></div><div class="productionList">'+rows(missing,'missing')+'</div><details class="productionDone"><summary>ĐÃ QUÉT ĐƯỢC '+done.length+' CẤU KIỆN</summary><div class="productionList">'+rows(done,'done')+'</div></details>':'<div class="productionEmpty">Model chưa có danh sách cấu kiện cuối cùng. Hãy đồng bộ Model có Group/Component cấu kiện.</div>';
  host.querySelectorAll('[data-production-object]').forEach(b=>b.onclick=()=>{const o=findObject(b.dataset.productionObject);if(o){openObject(o);$('#modelPanel').scrollIntoView({behavior:'smooth',block:'start'})}});
  const result=$('#productionStatus');
  if(result){result.className='productionStatus '+(expected.length&&missing.length===0?'success':'warning');result.textContent=!expected.length?'CHƯA CÓ DỮ LIỆU CẤU KIỆN':missing.length?'CHƯA ĐỦ CẤU KIỆN — CẦN KIỂM TRA DANH SÁCH CÒN THIẾU':'ĐÃ QUÉT ĐỦ CẤU KIỆN — KÍCH THƯỚC THEO MODEL ĐÃ CÓ, SẴN SÀNG ĐỐI CHIẾU LẮP ĐẶT';}
}
function startProductionCheck(){
  if(!state.model){setStatus('HÃY MỞ DỰ ÁN TRƯỚC KHI KIỂM TRA','bad');return}
  state.productionMode=true;state.productionScanned=[];renderProductionCheck();$('#productionPanel').classList.remove('hidden');$('#productionPanel').scrollIntoView({behavior:'smooth',block:'start'});
  $('#scanDialog').showModal();$('#scanDialog .eyebrow').textContent='KIỂM TRA CẤU KIỆN SẢN XUẤT';$('#scanDialog h3').textContent='Quét liên tục QR cấu kiện';$('#scanStatus').textContent='Bật camera và lần lượt đưa từng tem QR vào khung quét.';
}
function finishProductionCheck(){
  state.productionMode=false;stopScanner();if($('#scanDialog').open)$('#scanDialog').close();$('#scanDialog .eyebrow').textContent='CAMERA QR';$('#scanDialog h3').textContent='Quét mã tem / QR dự án';
  renderProductionCheck();
}
function handleQrResult(){
  stopScanner();if($('#scanDialog').open)$('#scanDialog').close();
  if(state.model&&state.shareId===state.model.share_id){const objectHit=findObject(state.pendingObject);if(objectHit){openObject(objectHit);return}const hit=findBoard(state.pendingBoard);if(hit){openDetail(hit);return}}
  $('#qrModeHint').classList.remove('hidden');$('#qrModeHint').textContent='Đã đọc QR. Mã dự án: '+(state.shareId||'—')+(state.pendingObject?' • Đối tượng: '+state.pendingObject:'')+(state.pendingBoard?' • Tấm: '+state.pendingBoard:'')+'. Hãy đăng nhập để xem dữ liệu.';hideApp();$('#projectLogin').focus();
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
  state.shareId=shareIdFromUrl();state.pendingBoard=boardFromUrl();state.pendingObject=objectFromUrl();
  $('#projectLogin').value=localStorage.getItem('tt_project_login')||'';
  if(state.shareId){$('#qrModeHint').classList.remove('hidden');$('#qrModeHint').textContent='Đã nhận mã dự án từ liên kết QR. Đang mở Model 3D…';setTimeout(login,80)} else {$('#projectLogin').value=localStorage.getItem('tt_project_login')||''}
  if(new URLSearchParams(location.search).get('scanner')==='1'){setTimeout(openScanner,250)}
  bindModel();setStatus('NHẬP TÊN HOẶC MÃ DỰ ÁN');
}

$('#loginBtn').onclick=login;$('#projectLogin').onkeydown=e=>{if(e.key==='Enter')login()};
$('#logoutBtn').onclick=logout;$('#closeDetail').onclick=()=>$('#detailDialog').close();
['#scanTopBtn','#scanLoginBtn','#scanProjectBtn'].forEach(s=>$(s).onclick=openScanner);$('#closeScanner').onclick=()=>{stopScanner();$('#scanDialog').close()};$('#startScanner').onclick=startScanner;$('#stopScanner').onclick=stopScanner;$('#manualQrBtn').onclick=()=>{if(!parseQr($('#manualQrText').value))$('#scanStatus').textContent='Không nhận được mã QR hợp lệ.'};
['search','thicknessFilter','labelFilter'].forEach(id=>$('#'+id).addEventListener(id==='search'?'input':'change',render));
boot();