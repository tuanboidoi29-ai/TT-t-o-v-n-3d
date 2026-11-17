# encoding: UTF-8
require 'json'
require 'fileutils'
require_relative 'material_catalog_seed'

module TranTuanNoiThat
  module MaterialCatalog
    extend self
    CATEGORIES = ['Gỗ công nghiệp','Ván phủ bề mặt','Vân đá','Phụ kiện','Thiết bị bếp','Thiết bị nội thất','Kính / Nhôm / Inox','Vật liệu khác'].freeze

    def data_path
      dir = File.join(TranTuanNoiThat::ROOT, 'data')
      FileUtils.mkdir_p(dir)
      File.join(dir, 'material_catalog.json')
    end

    def load_records
      unless File.file?(data_path)
        records = defined?(TranTuanNoiThat::MaterialCatalogSeed::RECORDS) ? TranTuanNoiThat::MaterialCatalogSeed::RECORDS : []
        save_records(records) unless records.empty?
        return records
      end
      data = JSON.parse(File.read(data_path, encoding: 'UTF-8'))
      data.is_a?(Array) ? data : []
    rescue StandardError => e
      puts "[TT MaterialCatalog] #{e.class}: #{e.message}"
      []
    end

    def save_records(records)
      raise 'Dữ liệu không hợp lệ.' unless records.is_a?(Array)
      clean = records.first(5000).select { |x| x.is_a?(Hash) }.map do |x|
        h = {}
        %w[id name code brand category color surface length width thickness unit price price_note image url notes updated_at].each { |k| h[k] = x[k].to_s[0, 2000] }
        h['suppliers'] = Array(x['suppliers']).first(30).select { |s| s.is_a?(Hash) }.map do |s|
          %w[name phone address url price note].each_with_object({}) { |k, a| a[k] = s[k].to_s[0, 1000] }
        end
        h
      end
      tmp = data_path + '.tmp'
      File.write(tmp, JSON.pretty_generate(clean), mode: 'w:UTF-8')
      # Windows cannot rename over an existing destination file.
      FileUtils.mv(tmp, data_path, force: true)
      true
    end

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return true
      end
      @dialog = UI::HtmlDialog.new(dialog_title: 'THƯ VIỆN VẬT LIỆU & THIẾT BỊ NỘI THẤT',
        preferences_key: 'TranTuanNoiThat.MaterialCatalog', scrollable: true, resizable: true,
        width: 1160, height: 760, min_width: 820, min_height: 580, style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(html)
      @dialog.add_action_callback('catalog_load') { |_c| @dialog.execute_script("window.TTMaterialCatalog.receive(#{JSON.generate(load_records).gsub('</', '<\\/')})") }
      @dialog.add_action_callback('catalog_save') do |_c, payload|
        begin
          save_records(JSON.parse(payload.to_s))
          @dialog.execute_script('window.TTMaterialCatalog.saved(true)')
        rescue StandardError => e
          @dialog.execute_script("window.TTMaterialCatalog.saved(false, #{e.message.to_s.to_json})")
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
      true
    rescue StandardError => e
      UI.messagebox("Không mở được thư viện vật liệu:\n#{e.class}: #{e.message}")
      false
    end

    def close
      @dialog.close if @dialog
      @dialog = nil
    rescue StandardError
      nil
    end

    def html
      cats = CATEGORIES.map { |x| "<option>#{x}</option>" }.join
      <<~HTML
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <style>
      *{box-sizing:border-box}body{margin:0;background:#f3f5f8;color:#202a36;font:14px Segoe UI,Arial}header{background:white;padding:18px 22px;border-bottom:1px solid #dce2e8;display:flex;justify-content:space-between;align-items:center}h1{font-size:20px;margin:0}.wrap{padding:18px;max-width:1450px;margin:auto}.panel,.card{background:white;border:1px solid #dfe5ec;border-radius:10px;padding:14px;margin-bottom:13px}.filters{display:grid;grid-template-columns:2fr 1fr 1fr 1fr 1fr auto;gap:10px;align-items:end}label{display:block;font-size:12px;color:#657184;margin-bottom:5px}input,select,textarea{width:100%;padding:9px;border:1px solid #cbd4df;border-radius:7px;font:inherit}.btn{border:0;border-radius:7px;padding:10px 13px;background:#26394e;color:white;cursor:pointer}.light{background:#e8edf3;color:#26394e}.green{background:#16794b}.red{background:#a53d3d}.toolbar{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}.muted{color:#748196;font-size:12px}.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(255px,1fr));gap:12px}.card{padding:0;overflow:hidden;margin:0}.photo{height:140px;background:#edf1f5;display:grid;place-items:center;color:#8290a1}.photo img{width:100%;height:100%;object-fit:cover}.body{padding:12px}.name{font-weight:700;font-size:15px}.price{font-size:17px;font-weight:700;color:#16794b;margin:7px 0}.actions{display:flex;gap:6px;margin-top:10px}.actions button{flex:1}.tag{display:inline-block;background:#edf2f7;border-radius:15px;padding:3px 8px;font-size:11px;margin:5px 3px 0 0}.modal{display:none;position:fixed;inset:0;background:#17253699;overflow:auto;padding:22px;z-index:3}.modal.open{display:block}.dialog{max-width:900px;margin:auto;background:white;border-radius:12px;padding:20px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:9px}.span2{grid-column:span 2}.span3{grid-column:span 3}.supplier{border:1px solid #e0e5eb;border-radius:8px;padding:10px;margin:8px 0}.sgrid{display:grid;grid-template-columns:2fr 1fr 2fr 1fr;gap:8px}.foot{display:flex;justify-content:space-between;align-items:center;margin-top:16px;gap:8px}@media(max-width:1000px){.filters{grid-template-columns:1fr 1fr}.grid{grid-template-columns:1fr 1fr}.span3{grid-column:span 2}.sgrid{grid-template-columns:1fr 1fr}}
      </style></head><body>
      <header><div><h1>THƯ VIỆN VẬT LIỆU & THIẾT BỊ NỘI THẤT</h1><div class="muted">Tìm kiếm và quản lý dữ liệu nội bộ · không cần Internet</div></div><button class="btn green" onclick="openForm()">＋ Thêm sản phẩm</button></header>
      <main class="wrap">
      <section class="panel filters"><div><label>TÌM KIẾM TẤT CẢ THÔNG TIN</label><input id="q" placeholder="Tên, mã, hãng, màu vân, bề mặt, kích thước, nhà cung cấp, SĐT..." oninput="render()"></div><div><label>NHÓM VẬT LIỆU</label><select id="cat" onchange="render()"><option value="">Tất cả nhóm</option>#{cats}</select></div><div><label>THƯƠNG HIỆU</label><select id="brand" onchange="render()"><option value="">Tất cả hãng</option></select></div><div><label>BỀ MẶT</label><select id="surfaceFilter" onchange="render()"><option value="">Tất cả bề mặt</option></select></div><div><label>NHÀ CUNG CẤP</label><select id="supplierFilter" onchange="render()"><option value="">Tất cả đơn vị</option></select></div><button class="btn light" onclick="resetFilters()">Xóa lọc</button></section>
      <div class="toolbar"><button class="btn" onclick="openForm()">＋ Nhập sản phẩm</button><button class="btn light" onclick="exportCsv()">Xuất CSV/Excel</button><button class="btn light" onclick="document.getElementById('csvfile').click()">Nhập CSV</button><input id="csvfile" type="file" accept=".csv" hidden onchange="importCsv(event)"><span id="stats" class="muted" style="margin:auto 0 auto auto"></span></div>
      <section id="cards" class="cards"></section>
      </main>
      <div id="modal" class="modal"><div class="dialog"><h2 id="formtitle">Thêm sản phẩm</h2><input id="editid" type="hidden"><div class="grid">
      <div class="span2"><label>TÊN SẢN PHẨM *</label><input id="name"></div><div><label>MÃ SẢN PHẨM</label><input id="code"></div>
      <div><label>THƯƠNG HIỆU</label><input id="brandin"></div><div><label>DANH MỤC</label><select id="category">#{cats}</select></div><div><label>MÀU / MÃ VÂN</label><input id="color"></div>
      <div><label>BỀ MẶT</label><input id="surface"></div><div><label>DÀI (mm)</label><input id="length"></div><div><label>RỘNG (mm)</label><input id="width"></div>
      <div><label>DÀY (mm)</label><input id="thickness"></div><div><label>ĐƠN VỊ</label><input id="unit" placeholder="tấm, bộ, cái..."></div><div><label>GIÁ THAM KHẢO (VNĐ)</label><input id="price"></div>
      <div><label>GHI CHÚ GIÁ</label><input id="price_note" placeholder="giá/tấm, chưa VAT..."></div><div class="span2"><label>LINK HÌNH ẢNH</label><input id="image" placeholder="https://..."></div><div class="span3"><label>LINK HÃNG / SẢN PHẨM</label><input id="url"></div><div class="span3"><label>MÔ TẢ</label><textarea id="notes"></textarea></div></div>
      <hr><b>NHÀ CUNG CẤP</b> <button class="btn light" onclick="addSupplier()">＋ Thêm nhà cung cấp</button><div id="suppliers"></div>
      <div class="foot"><span class="muted">Dữ liệu lưu cục bộ trên máy tính chạy SketchUp.</span><span><button class="btn light" onclick="closeForm()">Hủy</button> <button class="btn green" onclick="saveProduct()">Lưu sản phẩm</button></span></div></div></div>
      <script>
      const CATS=#{JSON.generate(CATEGORIES)};let rows=[],suppliers=[];const $=id=>document.getElementById(id);
      const normalize=s=>String(s==null?'':s).normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').replace(/đ/g,'d').replace(/Đ/g,'D').toLowerCase().trim();
      const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
      function init(){if(window.sketchup)sketchup.catalog_load()}
      function receive(a){rows=Array.isArray(a)?a:[];refreshFilters();render()}
      function fillSelect(id,values,label){let old=$(id).value,items=[...new Set(values.filter(Boolean).map(v=>String(v).trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'vi'));$(id).innerHTML='<option value="">'+label+'</option>'+items.map(v=>'<option value="'+esc(v)+'">'+esc(v)+'</option>').join('');$(id).value=items.includes(old)?old:''}
      function refreshFilters(){fillSelect('brand',rows.map(x=>x.brand),'Tất cả hãng');fillSelect('surfaceFilter',rows.map(x=>x.surface),'Tất cả bề mặt');fillSelect('supplierFilter',rows.flatMap(x=>(x.suppliers||[]).map(y=>y.name)),'Tất cả đơn vị')}
      function render(){let q=normalize($('q').value),c=$('cat').value,b=$('brand').value,sf=$('surfaceFilter').value,sup=$('supplierFilter').value;let a=rows.filter(x=>{let ss=x.suppliers||[],hay=[x.name,x.code,x.brand,x.color,x.category,x.surface,x.length,x.width,x.thickness,x.unit,x.price,x.price_note,x.url,x.notes,...ss.flatMap(y=>[y.name,y.phone,y.address,y.price,y.url,y.note])].join(' ');return(!c||normalize(x.category)===normalize(c))&&(!b||normalize(x.brand)===normalize(b))&&(!sf||normalize(x.surface)===normalize(sf))&&(!sup||ss.some(y=>normalize(y.name)===normalize(sup)))&&(!q||normalize(hay).includes(q))});let brandCount=new Set(a.map(x=>String(x.brand||'').trim()).filter(Boolean)).size;let supplierCount=new Set(a.flatMap(x=>(x.suppliers||[]).map(y=>String(y.name||'').trim()).filter(Boolean))).size;$('stats').textContent='Đang hiển thị '+a.length+' / '+rows.length+' sản phẩm · '+brandCount+' hãng · '+supplierCount+' nhà cung cấp';if(!a.length){$('cards').innerHTML='<div class="panel muted">Không tìm thấy sản phẩm phù hợp với điều kiện lọc. Hãy đổi từ khóa hoặc bấm Xóa lọc.</div>';return}
      $('cards').innerHTML=a.map(x=>'<article class="card"><div class="photo">'+(x.image?'<img src="'+esc(x.image)+'" onerror="this.parentNode.textContent=\'Không tải được ảnh\'">':'Chưa có hình ảnh')+'</div><div class="body"><div class="name">'+esc(x.name)+'</div><div class="muted">'+esc(x.brand||'Chưa rõ hãng')+' · Mã: '+esc(x.code||'—')+'</div><span class="tag">'+esc(x.category||'Chưa phân loại')+'</span><div class="muted">Kích thước: '+esc(x.length||'—')+' × '+esc(x.width||'—')+' × '+esc(x.thickness||'—')+' mm</div><div class="price">'+(x.price?esc(x.price)+' đ':'Chưa có giá')+'</div><div class="muted">'+(x.suppliers||[]).length+' nhà cung cấp · '+esc(x.price_note||'Giá tham khảo')+'</div><div class="actions"><button class="btn light" onclick="editProduct(\''+esc(x.id)+'\')">Chi tiết / Sửa</button></div></div></article>').join('')}
      function resetFilters(){$('q').value='';$('cat').value='';$('brand').value='';$('surfaceFilter').value='';$('supplierFilter').value='';render()}
      function openForm(x){x=x||{};$('formtitle').textContent=x.id?'Sửa sản phẩm':'Thêm sản phẩm';$('editid').value=x.id||'';['name','code','color','surface','length','width','thickness','unit','price','price_note','image','url','notes'].forEach(k=>$(k).value=x[k]||'');$('brandin').value=x.brand||'';$('category').value=x.category||CATS[0];suppliers=JSON.parse(JSON.stringify(x.suppliers||[]));drawSuppliers();$('modal').classList.add('open')}
      function closeForm(){$('modal').classList.remove('open')}function editProduct(id){let x=rows.find(r=>r.id===id);if(x)openForm(x)}
      function addSupplier(){suppliers.push({});drawSuppliers()}
      function drawSuppliers(){$('suppliers').innerHTML=suppliers.map((s,i)=>'<div class="supplier"><div class="sgrid">'+['name','phone','address','price','url','note'].map(k=>'<div><label>'+({name:'TÊN ĐƠN VỊ',phone:'ĐIỆN THOẠI',address:'ĐỊA CHỈ',price:'GIÁ BÁN',url:'WEBSITE / ĐẶT HÀNG',note:'GHI CHÚ'}[k])+'</label><input data-si="'+i+'" data-sk="'+k+'" value="'+esc(s[k])+'"></div>').join('')+'</div><button class="btn red" style="margin-top:7px" onclick="suppliers.splice('+i+',1);drawSuppliers()">Xóa nhà cung cấp</button></div>').join('')}
      function saveProduct(){let x={id:$('editid').value||'sp_'+Date.now(),updated_at:new Date().toISOString()};['name','code','color','surface','length','width','thickness','unit','price','price_note','image','url','notes'].forEach(k=>x[k]=$(k).value.trim());x.brand=$('brandin').value.trim();x.category=$('category').value;if(!x.name)return alert('Nhập tên sản phẩm');document.querySelectorAll('[data-si]').forEach(el=>suppliers[+el.dataset.si][el.dataset.sk]=el.value.trim());x.suppliers=suppliers;let i=rows.findIndex(r=>r.id===x.id);if(i<0)rows.unshift(x);else rows[i]=x;refreshFilters();render();if(window.sketchup&&sketchup.catalog_save){sketchup.catalog_save(JSON.stringify(rows))}else{alert('Không kết nối được chức năng lưu của SketchUp. Biểu mẫu vẫn được giữ mở.')}}
      function saved(ok,msg){if(ok){closeForm();alert('Đã lưu dữ liệu trên máy tính.')}else{alert('Không lưu được dữ liệu: '+(msg||'Lỗi không xác định')+'\\nDữ liệu vẫn đang hiển thị, vui lòng thử lưu lại.')}}
      function exportCsv(){let ks=['name','code','brand','category','color','surface','length','width','thickness','unit','price','price_note','image','url','notes','suppliers'];let csv=[ks.join(','),...rows.map(r=>ks.map(k=>'"'+String(k==='suppliers'?JSON.stringify(r[k]||[]):(r[k]||'')).replace(/"/g,'""')+'"').join(','))].join('\\r\\n');let a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['\\ufeff'+csv],{type:'text/csv;charset=utf-8'}));a.download='thu-vien-vat-lieu.csv';a.click();URL.revokeObjectURL(a.href)}
      function importCsv(e){let f=e.target.files[0];if(!f)return;let rd=new FileReader();rd.onload=()=>{let lines=rd.result.replace(/^\\ufeff/,'').split(/\\r?\\n/).filter(Boolean);let parse=line=>{let a=[],v='',q=false;for(let i=0;i<line.length;i++){let c=line[i];if(c==='"'&&line[i+1]==='"'){v+='"';i++}else if(c==='"')q=!q;else if(c===','&&!q){a.push(v);v=''}else v+=c}a.push(v);return a};let ks=parse(lines.shift()||''),added=lines.map(l=>{let a=parse(l),o={id:'sp_'+Date.now()+'_'+Math.random().toString(36).slice(2)};ks.forEach((k,i)=>o[k]=a[i]||'');try{o.suppliers=JSON.parse(o.suppliers||'[]')}catch(_){o.suppliers=[]}return o}).filter(x=>x.name);rows=added.concat(rows);refreshFilters();render();sketchup.catalog_save(JSON.stringify(rows));alert('Đã nhập '+added.length+' sản phẩm')};rd.readAsText(f,'UTF-8');e.target.value=''}
      window.TTMaterialCatalog={receive,saved};window.addEventListener('DOMContentLoaded',init);
      </script></body></html>
      HTML
    end
  end
end
