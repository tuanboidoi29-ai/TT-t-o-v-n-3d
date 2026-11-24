# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - THIẾT KẾ & IN TEM NHÃN
require 'sketchup.rb'
require 'json'
require 'uri'
require 'securerandom'

module TranTuanNoiThat
  module LabelTool
    extend self

    WEB_URL = 'https://tt-kiem-tra-tam-web.vercel.app/'.freeze
    DICT = 'TT_ModelExport'.freeze
    EDGE_KEYS = {
      'U-' => 'TRÁI', 'V+' => 'TRÊN', 'U+' => 'PHẢI', 'V-' => 'DƯỚI',
      'left' => 'TRÁI', 'top' => 'TRÊN', 'right' => 'PHẢI', 'bottom' => 'DƯỚI',
      'trai' => 'TRÁI', 'tren' => 'TRÊN', 'phai' => 'PHẢI', 'duoi' => 'DƯỚI'
    }.freeze

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        push_objects(@dialog)
        return true
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'THIẾT KẾ & IN TEM NHÃN',
        preferences_key: 'TranTuanNoiThat_LabelTool',
        scrollable: true,
        resizable: true,
        width: 980,
        height: 760,
        min_width: 720,
        min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('tt_label_ready') { |dialog, _| push_objects(dialog) }
      @dialog.add_action_callback('tt_label_refresh') { |dialog, _| push_objects(dialog) }
      @dialog.add_action_callback('tt_label_refresh_settings') do |_dialog, json|
        begin
          settings = JSON.parse(json.to_s)
          Sketchup.write_default('TRẦN TUẤN NỘI THẤT', 'label_workshop', settings['workshop'].to_s)
          Sketchup.write_default('TRẦN TUẤN NỘI THẤT', 'label_width', settings['width'].to_f)
          Sketchup.write_default('TRẦN TUẤN NỘI THẤT', 'label_height', settings['height'].to_f)
        rescue StandardError => error
          puts "[TT Label settings] #{error.class}: #{error.message}"
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
      true
    rescue StandardError => error
      UI.messagebox("Không mở được THIẾT KẾ & IN TEM NHÃN:\n#{error.class}: #{error.message}")
      false
    end

    def model
      Sketchup.active_model
    end

    def instance?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    rescue StandardError
      false
    end

    def entity_uid(entity)
      if defined?(TranTuanNoiThat::ModelExport) && ModelExport.respond_to?(:entity_uid)
        return ModelExport.entity_uid(entity).to_s
      end
      value = entity.get_attribute(DICT, 'uid').to_s
      if value.empty?
        value = SecureRandom.uuid
        entity.set_attribute(DICT, 'uid', value)
      end
      value
    end

    def entity_name(entity)
      name = entity.name.to_s.strip
      name = entity.definition.name.to_s.strip if name.empty? && entity.respond_to?(:definition)
      name.empty? ? (entity.is_a?(Sketchup::Group) ? 'Group' : 'Component') : name
    rescue StandardError
      'Đối tượng SketchUp'
    end

    def dimensions(entity)
      if defined?(TranTuanNoiThat::ModelExport) && ModelExport.respond_to?(:bounds_dimensions)
        return ModelExport.bounds_dimensions(entity)
      end
      bounds = entity.bounds
      [(bounds.width.to_f * 25.4).round(1),
       (bounds.depth.to_f * 25.4).round(1),
       (bounds.height.to_f * 25.4).round(1)]
    rescue StandardError
      []
    end

    def normalize_band_key(key)
      raw = key.to_s.strip
      return EDGE_KEYS[raw] if EDGE_KEYS.key?(raw)
      EDGE_KEYS[raw.downcase]
    end

    def parse_band_value(value)
      return value if value == true || value == false || value.is_a?(Numeric)
      return value.to_s unless value.nil?
      nil
    end

    def banding_for(entity)
      result = {}
      dictionaries = entity.attribute_dictionaries
      if dictionaries
        dictionaries.each do |dictionary|
          dictionary.each_pair do |key, value|
            normalized = normalize_band_key(key)
            if !normalized && key.to_s.match?(/band|canh|dan/i)
              begin
                parsed = value.is_a?(String) ? JSON.parse(value) : value
                if parsed.is_a?(Hash)
                  parsed.each do |side, amount|
                    label = normalize_band_key(side)
                    result[label] = parse_band_value(amount) if label
                  end
                end
              rescue StandardError
                nil
              end
            elsif normalized
              result[normalized] = parse_band_value(value)
            end
          end
        end
      end

      %w[TT_Board TT_Van TT_TaoVan TT_ModelExport].each do |dictionary_name|
        %w[banding bands dan_canh edge_banding].each do |key|
          value = entity.get_attribute(dictionary_name, key)
          next if value.nil?
          begin
            parsed = value.is_a?(String) ? JSON.parse(value) : value
            if parsed.is_a?(Hash)
              parsed.each do |side, amount|
                label = normalize_band_key(side)
                result[label] = parse_band_value(amount) if label
              end
            end
          rescue StandardError
            nil
          end
        end
      end
      result.delete_if { |_side, value| value.nil? || value == false || value == 0 || value == '' }
      result
    rescue StandardError
      {}
    end

    def visible?(entity)
      !(entity.respond_to?(:hidden?) && entity.hidden?)
    rescue StandardError
      true
    end

    # Quét đúng 1 cấp bên trong Group/Component Nesting cấp ngoài.
    # Không đi sâu vào các Group cấu tạo nằm trong từng chi tiết.
    def scan_objects
      m = model
      return [] unless m

      selected = m.selection.to_a.select { |entity| instance?(entity) && entity.valid? }
      roots = if selected.empty?
                m.entities.to_a.select { |entity| instance?(entity) && entity.valid? && visible?(entity) }
              else
                selected
              end

      rows = []
      roots.each do |root|
        next unless visible?(root)
        parent_name = entity_name(root)
        children = root.definition.entities.to_a.select do |child|
          instance?(child) && child.is_a?(Sketchup::Group) && child.valid? && visible?(child)
        end

        children.each do |entity|
          next unless entity.valid?
          uid = entity_uid(entity)
          rows << {
            'uid' => uid,
            'name' => entity_name(entity),
            'type' => 'Group',
            'path' => "#{parent_name} / #{entity_name(entity)}",
            'dimensions' => dimensions(entity),
            'banding' => banding_for(entity),
            'qr_url' => qr_url(m, uid)
          }
        end
      end
      rows.uniq { |row| row['uid'] }
    rescue StandardError => error
      puts "[TT Label scan] #{error.class}: #{error.message}"
      []
    end
    def qr_url(m, uid)
      share_id = m.get_attribute(DICT, 'share_id').to_s
      return '' if share_id.empty?
      WEB_URL + '?id=' + URI.encode_www_form_component(share_id) +
        '&object=' + URI.encode_www_form_component(uid)
    rescue StandardError
      ''
    end

    def push_objects(dialog)
      data = {
        workshop: Sketchup.read_default('TRẦN TUẤN NỘI THẤT', 'label_workshop', 'XƯỞNG TRẦN TUẤN'),
        width: Sketchup.read_default('TRẦN TUẤN NỘI THẤT', 'label_width', 70),
        height: Sketchup.read_default('TRẦN TUẤN NỘI THẤT', 'label_height', 40),
        objects: scan_objects
      }
      dialog.execute_script("window.TTLabels && window.TTLabels.setData(#{JSON.generate(data)})")
    rescue StandardError => error
      puts "[TT Label push] #{error.class}: #{error.message}"
    end

    def dialog_html
      <<~'HTML'
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <title>THIẾT KẾ & IN TEM NHÃN</title>
          <style>
            *{box-sizing:border-box}body{margin:0;background:#f3f7fb;color:#172033;font:13px Arial,sans-serif}
            .app{padding:16px}.head{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:14px}
            h1{font-size:20px;margin:0 0 5px}.muted{color:#64748b;font-size:11px;line-height:1.5}
            .panel{background:#fff;border:1px solid #dbe3ec;border-radius:12px;padding:13px;margin-bottom:12px}
            .settings{display:grid;grid-template-columns:2fr 1fr 1fr auto;gap:10px;align-items:end}
            label{display:grid;gap:5px;font-size:10px;font-weight:800;color:#475569}
            input{width:100%;padding:9px;border:1px solid #cbd5e1;border-radius:8px;font:inherit;color:#172033;background:#fff}
            button{border:0;border-radius:8px;padding:10px 13px;font-weight:800;cursor:pointer}
            .primary{background:#16803d;color:#fff}.secondary{background:#e8f0f8;color:#1e293b}
            .actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:10px}
            .columns{display:grid;grid-template-columns:minmax(260px,1fr) minmax(300px,1.25fr);gap:12px}
            .objectList{max-height:360px;overflow:auto;margin-top:9px;border:1px solid #e2e8f0;border-radius:8px}
            .objectRow{display:flex;gap:8px;align-items:flex-start;padding:9px;border-bottom:1px solid #edf1f5}
            .objectRow:last-child{border:0}.objectRow input{width:auto;margin-top:2px}
            .objectRow span{min-width:0;display:grid;gap:3px}.objectRow small{font-size:10px;color:#64748b;overflow-wrap:anywhere}
            .count{font-size:11px;color:#64748b}.preview{display:flex;flex-wrap:wrap;gap:10px;align-content:flex-start;min-height:100px}
            .labelCard{width:var(--label-width,70mm);height:var(--label-height,40mm);padding:2.2mm;border:1px solid #9ca3af;border-radius:1mm;background:#fff;color:#111;display:grid;grid-template-rows:auto 1fr auto auto;gap:1mm;overflow:hidden;break-inside:avoid}
            .labelWorkshop{font-size:9pt;font-weight:800;border-bottom:1px solid #cbd5e1;padding-bottom:1mm}
            .labelDiagram{width:100%;height:15mm;min-height:15mm;display:block}
            .labelDiagram .part{fill:#f4e2c8;stroke:#475569;stroke-width:1.4}
            .labelDiagram .edgeMark{fill:#16803d;stroke:#fff;stroke-width:.8}
            .labelName{font-size:11pt;font-weight:900;line-height:1.1;overflow:hidden}.labelDims{font-size:9pt;font-weight:800}
            .labelEdges{font-size:7pt;line-height:1.2;overflow:hidden}.labelFooter{display:flex;justify-content:space-between;align-items:flex-end;gap:2mm}
            .labelUid{font-size:6pt;overflow-wrap:anywhere;max-width:65%}.labelQr{width:16mm;height:16mm;background:#fff;flex:0 0 16mm}
            .labelQr img,.labelQr canvas{width:100%!important;height:100%!important;display:block}
            .empty{padding:18px;color:#64748b;font-size:11px}
            @media(max-width:780px){.settings{grid-template-columns:1fr 1fr}.settings label:first-child{grid-column:1/-1}.columns{grid-template-columns:1fr}}
            @media print{
              @page{margin:5mm}
              body{background:#fff}.app>*:not(#printArea){display:none!important}
              .app{padding:0}.panel.previewPanel{display:block!important;border:0;padding:0;margin:0}
              .preview{display:flex;gap:0}.labelCard{margin:0;border:0;border-radius:0}
            }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
        </head>
        <body>
          <main class="app">
            <div class="head"><div><h1>🏷️ THIẾT KẾ & IN TEM NHÃN</h1><div class="muted">Công cụ độc lập trong SketchUp · Lấy dữ liệu trực tiếp từ Group / Component đang mở</div></div><button class="secondary" onclick="sketchup.tt_label_refresh()">LÀM MỚI MODEL</button></div>
            <section class="panel">
              <div class="settings">
                <label>TÊN XƯỞNG<input id="workshop" value="XƯỞNG TRẦN TUẤN"></label>
                <label>RỘNG (mm)<input id="width" type="number" min="20" max="300" value="70"></label>
                <label>CAO (mm)<input id="height" type="number" min="15" max="300" value="40"></label>
                <button class="primary" onclick="TTLabels.print()">🖨 IN TEM ĐÃ CHỌN</button>
              </div>
              <div class="actions"><button class="secondary" onclick="TTLabels.selectAll(true)">CHỌN TẤT CẢ</button><button class="secondary" onclick="TTLabels.selectAll(false)">BỎ CHỌN</button><span class="count" id="selectedCount">0 đối tượng được chọn</span></div>
              <div class="muted" id="qrNotice" style="margin-top:8px"></div>
            </section>
            <div class="columns">
              <section class="panel">
                <b>ĐỐI TƯỢNG TRONG MODEL</b>
                <input id="search" placeholder="Tìm tên Group / Component…" oninput="TTLabels.renderList()" style="margin-top:9px">
                <div id="objectList" class="objectList"><div class="empty">Đang đọc model…</div></div>
              </section>
              <section class="panel previewPanel" id="printArea">
                <b>XEM TRƯỚC TEM</b><div id="preview" class="preview" style="margin-top:10px"><div class="empty">Chọn đối tượng để xem tem.</div></div>
              </section>
            </div>
          </main>
          <script>
            const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
            const state={objects:[],selected:new Set(),data:{}};
            window.TTLabels={
              setData(data){state.data=data||{};state.objects=state.data.objects||[];document.getElementById('workshop').value=state.data.workshop||'XƯỞNG TRẦN TUẤN';document.getElementById('width').value=state.data.width||70;document.getElementById('height').value=state.data.height||40;this.renderList();this.renderPreview();document.getElementById('qrNotice').textContent=state.objects.some(o=>!o.qr_url)?'Muốn có QR mở đúng đối tượng trên Web, hãy đồng bộ Model để tạo Mã dự án trước.':''},
              renderList(){const q=document.getElementById('search').value.trim().toLowerCase();const rows=state.objects.filter(o=>[o.name,o.uid,o.path].join(' ').toLowerCase().includes(q));document.getElementById('objectList').innerHTML=rows.map(o=>'<label class="objectRow"><input type="checkbox" data-uid="'+esc(o.uid)+'" '+(state.selected.has(o.uid)?'checked':'')+'><span><b>'+esc(o.name)+'</b><small>'+esc(o.path)+' · '+esc((o.dimensions||[]).join(' × '))+' mm</small></span></label>').join('')||'<div class="empty">Không có đối tượng phù hợp.</div>';document.querySelectorAll('[data-uid]').forEach(el=>el.onchange=()=>{el.checked?state.selected.add(el.dataset.uid):state.selected.delete(el.dataset.uid);this.renderPreview();this.updateCount()});this.updateCount()},
              updateCount(){document.getElementById('selectedCount').textContent=state.selected.size+' đối tượng được chọn'},
              selectAll(yes){state.selected=yes?new Set(state.objects.map(o=>o.uid)):new Set();this.renderList();this.renderPreview()},
              edgeDiagram(o){const b=o.banding||{};const has=(side)=>Object.entries(b).some(([k,v])=>String(k).toUpperCase()===side&&v!==false&&v!==0&&v!==''&&v!=null);let marks='';if(has('TRÁI'))marks+='<path class="edgeMark" d="M8 44 L25 34 L25 54 Z"/>';if(has('PHẢI'))marks+='<path class="edgeMark" d="M152 44 L135 34 L135 54 Z"/>';if(has('TRÊN'))marks+='<path class="edgeMark" d="M80 7 L69 23 L91 23 Z"/>';if(has('DƯỚI'))marks+='<path class="edgeMark" d="M80 81 L69 65 L91 65 Z"/>';return '<svg class="labelDiagram" viewBox="0 0 160 88" role="img" aria-label="Sơ đồ cạnh dán"><rect class="part" x="5" y="5" width="150" height="78" rx="1"/>'+marks+'</svg>'},
              renderPreview(){const chosen=state.objects.filter(o=>state.selected.has(o.uid));const w=Math.max(20,Math.min(300,Number(document.getElementById('width').value)||70)),h=Math.max(15,Math.min(300,Number(document.getElementById('height').value)||40));const host=document.getElementById('preview');host.style.setProperty('--label-width',w+'mm');host.style.setProperty('--label-height',h+'mm');host.innerHTML=chosen.map(o=>'<article class="labelCard"><div class="labelWorkshop">'+esc(document.getElementById('workshop').value||'XƯỞNG TRẦN TUẤN')+'</div><div class="labelName">'+esc(o.name)+'</div><div class="labelDims">'+esc((o.dimensions||[]).join(' × '))+' mm</div>'+this.edgeDiagram(o)+'<div class="labelFooter"><div class="labelUid">'+esc(o.uid)+'</div><div class="labelQr" data-qr="'+esc(o.uid)+'"></div></div></article>').join('')||'<div class="empty">Chọn đối tượng để xem tem.</div>';if(window.QRCode)host.querySelectorAll('[data-qr]').forEach(el=>{const o=chosen.find(x=>x.uid===el.dataset.qr);if(o&&o.qr_url)new QRCode(el,{text:o.qr_url,width:100,height:100,correctLevel:QRCode.CorrectLevel.M});else el.textContent='Chưa có QR'});this.updateCount()},
              print(){if(!state.selected.size){alert('Hãy chọn ít nhất một Group / Component.');return}const w=document.getElementById('workshop').value||'XƯỞNG TRẦN TUẤN';const width=Math.max(20,Math.min(300,Number(document.getElementById('width').value)||70));const height=Math.max(15,Math.min(300,Number(document.getElementById('height').value)||40));sketchup.tt_label_refresh_settings(JSON.stringify({workshop:w,width,height}));window.print()}
            };
            ['workshop','width','height'].forEach(id=>document.getElementById(id).addEventListener('input',()=>TTLabels.renderPreview()));
            window.addEventListener('DOMContentLoaded',()=>sketchup.tt_label_ready());
          </script>
        </body>
        </html>
      HTML
    end
  end
end
