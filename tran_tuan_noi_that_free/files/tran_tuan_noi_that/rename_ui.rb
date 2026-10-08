# encoding: UTF-8
module TranTuanNoiThat
  module RenameUI
    def self.html
      <<~'TT_RENAME_HTML'
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TT – Đổi Tên</title>
<style>
*{box-sizing:border-box}body{font:14px Arial,sans-serif;background:#0f172a;color:#e5e7eb;margin:0}
.top{background:#f97316;color:#fff;padding:16px 18px}.top h1{font-size:21px;margin:0 0 4px}.top p{margin:0;opacity:.95}
.wrap{padding:14px}.bar{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:10px}
button,input{font:inherit}button{padding:9px 12px;border:0;border-radius:6px;background:#334155;color:#fff;cursor:pointer}
button.primary{background:#ea580c}button.danger{background:#991b1b}button:disabled{opacity:.45;cursor:wait}
input[type=text]{width:100%;padding:9px;border:1px solid #475569;border-radius:6px;background:#111827;color:#fff}
.grid{display:grid;grid-template-columns:minmax(520px,1.3fr) minmax(300px,.7fr);gap:12px}
.panel{background:#172033;border:1px solid #334155;border-radius:9px;padding:12px}
.table-wrap{height:500px;overflow:auto;border:1px solid #334155;border-radius:7px}
table{border-collapse:collapse;width:100%;font-size:13px}th{position:sticky;top:0;background:#1e293b;z-index:1}
th,td{padding:8px 7px;border-bottom:1px solid #334155;text-align:left}tr{cursor:pointer}tr:hover{background:#1e293b}tr.active{background:#7c2d12}
.muted{color:#94a3b8;font-size:12px}.ok{color:#86efac}.err{color:#fca5a5;min-height:20px}
label{display:block;margin:10px 0}.tagline{padding:8px 10px;background:#0b1220;border-radius:6px;margin:8px 0}
.name{font-weight:bold;font-size:16px;color:#fdba74;word-break:break-word}.dims{font-size:16px;margin:8px 0}
.actions{display:flex;gap:8px;flex-wrap:wrap}.count{color:#cbd5e1;margin-top:8px}
@media(max-width:900px){.grid{grid-template-columns:1fr}.table-wrap{height:360px}}
</style>
</head>
<body>
<div class="top">
  <h1>ĐỔI TÊN TẤM / GROUP / COMPONENT</h1>
  <p>Chức năng riêng để đổi Tên và Tag/Layer. Không chứa thống kê ván.</p>
</div>
<div class="wrap">
  <div class="bar">
    <button id="scan" class="primary" onclick="scan(false)">QUÉT VÙNG ĐANG CHỌN</button>
    <button id="scan-all" onclick="scan(true)">QUÉT TOÀN MODEL</button>
    <button onclick="checkAll()">CHỌN TẤT CẢ ĐANG HIỆN</button>
    <button onclick="checked.clear();render()">BỎ CHỌN</button>
  </div>
  <div id="message" class="ok">Chưa quét.</div>
  <div id="error" class="err"></div>

  <div class="grid">
    <section class="panel">
      <input id="filter" type="text" placeholder="Tìm theo tên hoặc Tag/Layer…" oninput="render()">
      <div class="table-wrap">
        <table>
          <thead><tr><th>Chọn</th><th>Tên hiện tại</th><th>Loại</th><th>Tag/Layer</th><th>Kích thước mm</th><th>Tìm</th></tr></thead>
          <tbody id="rows"></tbody>
        </table>
      </div>
      <div id="selected-count" class="count"></div>
    </section>

    <section class="panel">
      <div class="muted">ĐỐI TƯỢNG ĐANG XEM</div>
      <div id="detail-name" class="name">Chưa chọn đối tượng</div>
      <div id="dimensions" class="dims">—</div>
      <div id="detail-tag" class="tagline">Tag: —</div>

      <label>Tên mới
        <input id="new-name" type="text" maxlength="120" placeholder="Ví dụ: Hậu phủ">
      </label>

      <label><input id="change-tag" type="checkbox"> Đổi Tag/Layer cùng lượt</label>
      <label>Tag/Layer mới
        <input id="new-tag" type="text" maxlength="120" placeholder="Để trống = Untagged">
      </label>

      <div class="actions">
        <button class="primary action" onclick="saveRename()">LƯU ĐỔI TÊN</button>
        <button class="action" onclick="findPart()">TÌM + ZOOM</button>
      </div>

      <hr style="border:0;border-top:1px solid #334155;margin:16px 0">
      <div class="muted">XÓA / ĐẶT LẠI HÀNG LOẠT</div>
      <label>Tên sau khi xóa
        <input id="reset-name" type="text" maxlength="120" placeholder="Trống = không tên">
      </label>
      <label>Tag sau khi xóa
        <input id="reset-tag" type="text" maxlength="120" placeholder="Trống = Untagged">
      </label>
      <button class="danger action" onclick="clearNames()">XÓA TÊN + TAG / ĐẶT LẠI</button>

      <p class="muted">Ctrl chọn nhiều Group/Component trong SketchUp hoặc tích nhiều dòng trong bảng. Mỗi lượt đổi tên là một Undo.</p>
    </section>
  </div>
</div>

<script>
let rows=[],checked=new Set(),active=null,busy=false;
const el=id=>document.getElementById(id);
function showError(s){el('error').textContent=s||''}
function resetScope(){checked.clear();active=null;rows=[];el('filter').value='';el('new-name').value='';el('new-tag').value='';el('detail-name').textContent='Chưa chọn đối tượng';el('detail-tag').textContent='Tag: —';el('dimensions').textContent='—';showError('');render()}
function scan(all){checked.clear();active=null;sketchup.scan(all)}
function scanState(s){busy=!!s.busy;el('message').textContent=s.message||'';document.querySelectorAll('.action,#scan,#scan-all').forEach(b=>b.disabled=busy)}
function visible(){let q=el('filter').value.trim().toLocaleLowerCase();return rows.filter(r=>!q||[r.name,r.tag,r.type].join(' ').toLocaleLowerCase().includes(q))}
function render(){
  let body=el('rows');body.innerHTML='';
  visible().forEach(r=>{
    let tr=document.createElement('tr');if(r.id===active)tr.className='active';
    let tc=document.createElement('td'),cb=document.createElement('input');cb.type='checkbox';cb.checked=checked.has(r.id);
    cb.onclick=e=>{e.stopPropagation();cb.checked?checked.add(r.id):checked.delete(r.id);updateCount()};tc.appendChild(cb);tr.appendChild(tc);
    [r.name||'(Không tên)',r.type,r.tag||'Untagged',(r.dims||[]).map(x=>Number(x).toFixed(1)).join(' × ')].forEach(v=>{let td=document.createElement('td');td.textContent=v;tr.appendChild(td)});
    let ta=document.createElement('td'),b=document.createElement('button');b.textContent='Tìm';b.onclick=e=>{e.stopPropagation();selectRow(r,true)};ta.appendChild(b);tr.appendChild(ta);
    tr.onclick=()=>selectRow(r,false);body.appendChild(tr)
  });updateCount()
}
function updateCount(){el('selected-count').textContent='Đã chọn '+checked.size+' / '+visible().length+' đối tượng đang hiện'}
function selectRow(r,zoom){active=r.id;if(!checked.has(r.id))checked=new Set([r.id]);render();zoom?sketchup.find_part(r.id):sketchup.choose(r.id)}
function checkAll(){visible().forEach(r=>checked.add(r.id));render()}
function setRows(data){rows=data.rows||[];checked=new Set([...checked].filter(id=>rows.some(r=>r.id===id)));scanState({busy:false,message:'Đã quét '+rows.length+' Group/Component.'});render()}
function showDetail(r){active=r.id;el('detail-name').textContent=r.name||'(Không tên)';el('detail-tag').textContent='Tag: '+(r.tag||'Untagged');el('dimensions').textContent=(r.dims||[]).map(x=>Number(x).toFixed(1)).join(' × ')+' mm';if(!el('new-name').value)el('new-name').value=r.name||'';if(!el('new-tag').value)el('new-tag').value=r.tag||'';render()}
function ids(){let a=[...checked];if(!a.length&&active)a=[active];return a}
function saveRename(){let a=ids();if(!a.length)return showError('Chọn ít nhất một đối tượng.');showError('');sketchup.save(JSON.stringify({ids:a,name:el('new-name').value,tag:el('new-tag').value,change_tag:el('change-tag').checked}))}
function clearNames(){let a=ids();if(!a.length)return showError('Chọn ít nhất một đối tượng.');showError('');sketchup.clear_names(JSON.stringify({ids:a,name:el('reset-name').value,tag:el('reset-tag').value,change_tag:true}))}
function findPart(){if(!active)return showError('Chọn một đối tượng trước.');sketchup.find_part(active)}
function saved(data){el('message').textContent=data.message||('Đã đổi tên '+data.count+' đối tượng.');showError('')}
function selectRows(ids){checked=new Set(ids||[]);active=(ids||[])[0]||null;render()}
window.addEventListener('load',()=>sketchup.ready())
</script>
</body>
</html>
      TT_RENAME_HTML
    end
  end
end
