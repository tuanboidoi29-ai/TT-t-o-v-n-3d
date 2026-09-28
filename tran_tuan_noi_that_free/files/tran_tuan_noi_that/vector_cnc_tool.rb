# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'rexml/document'

module TranTuanNoiThat
  module VectorCNC
    extend self

    VERSION = '1.1.0'.freeze
    KEY = 'TT_VECTOR_CNC'.freeze
    DATA_DIR = File.join(TranTuanNoiThat::ROOT, 'data', 'vector_cnc').freeze
    LIBRARY_FILE = File.join(DATA_DIR, 'library.json').freeze
    DEFAULT_SIZE = 200.0
    DEFAULT_DEPTH = 3.0
    DEFAULT_CNC = {
      'depth' => 3.0,
      'offset_x' => 20.0,
      'offset_y' => 20.0,
      'anchor' => 'center',
      'cut_mode' => 'inside'
    }.freeze
    MAX_POINTS = 720

    BUILTINS = [
      ['circle', 'Tròn'],
      ['square', 'Vuông'],
      ['rectangle', 'Chữ nhật'],
      ['triangle', 'Tam giác'],
      ['right_triangle', 'Tam giác vuông'],
      ['diamond', 'Hình thoi'],
      ['hexagon', 'Lục giác'],
      ['octagon', 'Bát giác'],
      ['oval', 'Oval'],
      ['star', 'Ngôi sao']
    ].freeze

    def ensure_data
      FileUtils.mkdir_p(DATA_DIR)
    end

    def circle_points(segments = 64)
      segments.times.map do |i|
        a = 2.0 * Math::PI * i / segments
        [Math.cos(a), Math.sin(a)]
      end
    end

    def regular_polygon(sides, rotate = -Math::PI / 2.0)
      sides.times.map do |i|
        a = rotate + 2.0 * Math::PI * i / sides
        [Math.cos(a), Math.sin(a)]
      end
    end

    def builtin_template(id)
      points = case id.to_s
      when 'circle' then circle_points(72)
      when 'square' then [[-1,-1],[1,-1],[1,1],[-1,1]]
      when 'rectangle' then [[-1,-0.6],[1,-0.6],[1,0.6],[-1,0.6]]
      when 'triangle' then regular_polygon(3)
      when 'right_triangle' then [[-1,-1],[1,-1],[-1,1]]
      when 'diamond' then [[0,-1],[1,0],[0,1],[-1,0]]
      when 'hexagon' then regular_polygon(6)
      when 'octagon' then regular_polygon(8)
      when 'oval' then circle_points(72).map { |x,y| [x, y*0.6] }
      when 'star'
        10.times.map do |i|
          a = -Math::PI/2.0 + Math::PI*i/5.0
          r = i.even? ? 1.0 : 0.42
          [Math.cos(a)*r, Math.sin(a)*r]
        end
      else
        raise "Không có mẫu vector #{id}."
      end
      label = BUILTINS.to_h[id.to_s] || id.to_s
      {
        'id'=>id.to_s, 'name'=>"ABF_#{slug(label)}", 'label'=>label,
        'points'=>normalize_unit(points), 'width'=>DEFAULT_SIZE, 'height'=>DEFAULT_SIZE,
        'builtin'=>true
      }
    end

    def builtins
      BUILTINS.map { |id,_| builtin_template(id) }
    end

    def custom_templates
      ensure_data
      return [] unless File.file?(LIBRARY_FILE)
      data = JSON.parse(File.read(LIBRARY_FILE, encoding: 'UTF-8'))
      data.is_a?(Array) ? data : []
    rescue StandardError
      []
    end

    def library
      builtins + custom_templates
    end

    def slug(text)
      value = text.to_s.strip
      value = value.unicode_normalize(:nfd).gsub(/\p{Mn}/, '') if value.respond_to?(:unicode_normalize)
      value = value.upcase.gsub(/[^A-Z0-9_]+/, '_').gsub(/_+/, '_').gsub(/\A_|_\z/, '')
      value = 'VECTOR' if value.empty?
      value
    rescue StandardError
      text.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')
    end

    def abf_name(text)
      value = slug(text.to_s.sub(/\AABF_/i,''))
      "ABF_#{value}"
    end

    def normalize_unit(points)
      pts = points.map { |p| [Float(p[0]), Float(p[1])] }
      raise 'Vector cần ít nhất 3 điểm.' if pts.length < 3
      raise "Vector quá nhiều điểm (#{pts.length}/#{MAX_POINTS})." if pts.length > MAX_POINTS
      min_x,max_x = pts.map(&:first).minmax
      min_y,max_y = pts.map(&:last).minmax
      w = max_x - min_x
      h = max_y - min_y
      raise 'Vector có kích thước bằng 0.' if w.abs < 1.0e-9 || h.abs < 1.0e-9
      cx = (min_x + max_x) / 2.0
      cy = (min_y + max_y) / 2.0
      pts.map { |x,y| [(x-cx)/(w/2.0), (y-cy)/(h/2.0)] }
    end

    def polygon_area(points)
      points.each_with_index.sum do |p,i|
        q = points[(i+1)%points.length]
        p[0]*q[1] - q[0]*p[1]
      end / 2.0
    end

    def sanitize_template(template)
      points = normalize_unit(template['points'] || template[:points])
      points.reverse! if polygon_area(points) < 0
      {
        'id'=>(template['id'] || template[:id] || "custom_#{Time.now.to_i}").to_s,
        'name'=>abf_name(template['name'] || template[:name] || 'VECTOR'),
        'label'=>(template['label'] || template[:label] || template['name'] || 'Vector').to_s,
        'points'=>points,
        'width'=>[(template['width'] || template[:width] || DEFAULT_SIZE).to_f,0.1].max,
        'height'=>[(template['height'] || template[:height] || DEFAULT_SIZE).to_f,0.1].max,
        'builtin'=>false
      }
    end

    def save_custom(template, requested_name)
      ensure_data
      item = sanitize_template(template.merge('name'=>abf_name(requested_name), 'label'=>requested_name.to_s))
      item['id'] = "custom_#{slug(requested_name)}"
      rows = custom_templates.reject { |row| row['id'].to_s == item['id'] || row['name'].to_s == item['name'] }
      rows << item
      File.write(LIBRARY_FILE, JSON.pretty_generate(rows), encoding: 'UTF-8')
      item
    end

    def delete_custom(id)
      ensure_data
      rows = custom_templates.reject { |row| row['id'].to_s == id.to_s }
      File.write(LIBRARY_FILE, JSON.pretty_generate(rows), encoding: 'UTF-8')
      true
    end

    def scaled_points(template, width, height)
      unit = template['points']
      sx = width.to_f / 2.0
      sy = height.to_f / 2.0
      unit.map { |x,y| [x.to_f*sx, y.to_f*sy] }
    end

    def parse_svg_length(value)
      text = value.to_s.strip
      return nil if text.empty?
      num = text[/[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?/]
      num ? num.to_f : nil
    end

    def svg_points(path)
      doc = REXML::Document.new(File.read(path, encoding: 'UTF-8'))
      root = doc.root
      raise 'SVG không hợp lệ.' unless root
      candidates = []
      REXML::XPath.each(root, '//*') do |node|
        name = node.name.to_s.downcase
        case name
        when 'circle'
          cx = parse_svg_length(node.attributes['cx']) || 0.0
          cy = parse_svg_length(node.attributes['cy']) || 0.0
          r = parse_svg_length(node.attributes['r']) || 0.0
          candidates << circle_points(96).map { |x,y| [cx+x*r,cy+y*r] } if r > 0
        when 'ellipse'
          cx = parse_svg_length(node.attributes['cx']) || 0.0
          cy = parse_svg_length(node.attributes['cy']) || 0.0
          rx = parse_svg_length(node.attributes['rx']) || 0.0
          ry = parse_svg_length(node.attributes['ry']) || 0.0
          candidates << circle_points(96).map { |x,y| [cx+x*rx,cy+y*ry] } if rx > 0 && ry > 0
        when 'rect'
          x = parse_svg_length(node.attributes['x']) || 0.0
          y = parse_svg_length(node.attributes['y']) || 0.0
          w = parse_svg_length(node.attributes['width']) || 0.0
          h = parse_svg_length(node.attributes['height']) || 0.0
          candidates << [[x,y],[x+w,y],[x+w,y+h],[x,y+h]] if w > 0 && h > 0
        when 'polygon'
          nums = node.attributes['points'].to_s.scan(/[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?/).map(&:to_f)
          pts = nums.each_slice(2).select { |pair| pair.length == 2 }.to_a
          candidates << pts if pts.length >= 3
        when 'path'
          pts = simple_svg_path_points(node.attributes['d'].to_s)
          candidates << pts if pts.length >= 3
        end
      end
      points = candidates.max_by(&:length)
      raise 'SVG chưa có vector kín được hỗ trợ.' unless points
      points
    end

    def simple_svg_path_points(data)
      tokens = data.scan(/[MLHVZmlhvz]|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?/)
      points = []
      x = y = 0.0
      start = nil
      cmd = nil
      i = 0
      while i < tokens.length
        token = tokens[i]
        if token =~ /[MLHVZmlhvz]/
          cmd = token
          i += 1
          if cmd =~ /[Zz]/
            break
          end
          next
        end
        case cmd
        when 'M','L'
          x = tokens[i].to_f; y = tokens[i+1].to_f; i += 2
        when 'm','l'
          x += tokens[i].to_f; y += tokens[i+1].to_f; i += 2
        when 'H'
          x = tokens[i].to_f; i += 1
        when 'h'
          x += tokens[i].to_f; i += 1
        when 'V'
          y = tokens[i].to_f; i += 1
        when 'v'
          y += tokens[i].to_f; i += 1
        else
          i += 1
          next
        end
        start ||= [x,y]
        points << [x,y]
      end
      points.pop if points.length > 2 && start && points.last == start
      points
    end

    def dxf_points(path)
      lines = File.readlines(path, chomp: true)
      pairs = []
      lines.each_slice(2) { |a,b| pairs << [a.to_s.strip,b.to_s.strip] if b }
      points = []
      in_lw = false
      current_x = nil
      pairs.each do |code,value|
        if code == '0'
          if value == 'LWPOLYLINE'
            in_lw = true
            points = []
            current_x = nil
            next
          elsif in_lw
            break
          elsif value == 'CIRCLE'
            # handled below in a second pass
          end
        end
        next unless in_lw
        if code == '10'
          current_x = value.to_f
        elsif code == '20' && current_x
          points << [current_x,value.to_f]
          current_x = nil
        end
      end
      return points if points.length >= 3

      idx = pairs.index { |pair| pair == ['0','CIRCLE'] }
      if idx
        cx = cy = r = nil
        pairs[(idx+1)..-1].each do |code,value|
          break if code == '0'
          cx = value.to_f if code == '10'
          cy = value.to_f if code == '20'
          r = value.to_f if code == '40'
        end
        return circle_points(96).map { |x,y| [cx+x*r,cy+y*r] } if cx && cy && r && r > 0
      end
      raise 'DXF cần LWPOLYLINE kín hoặc CIRCLE.'
    end

    def json_points(path)
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      points = data.is_a?(Hash) ? data['points'] : data
      raise 'JSON vector cần trường points.' unless points.is_a?(Array)
      points
    end

    def import_file(path)
      ext = File.extname(path).downcase
      points = case ext
      when '.svg' then svg_points(path)
      when '.dxf' then dxf_points(path)
      when '.json' then json_points(path)
      else
        raise 'Chỉ hỗ trợ SVG, DXF hoặc JSON.'
      end
      min_x,max_x = points.map { |p| p[0].to_f }.minmax
      min_y,max_y = points.map { |p| p[1].to_f }.minmax
      name = abf_name(File.basename(path,'.*'))
      sanitize_template(
        'id'=>"import_#{slug(name)}",
        'name'=>name,
        'label'=>File.basename(path,'.*'),
        'points'=>points,
        'width'=>[(max_x-min_x).abs,DEFAULT_SIZE].max,
        'height'=>[(max_y-min_y).abs,DEFAULT_SIZE].max
      )
    end

    def ensure_tag(model, name)
      model.layers[name] || model.layers.add(name)
    end

    def activate_template(template, settings = {})
      tpl = sanitize_template(template)
      cfg = DEFAULT_CNC.merge(settings.transform_keys(&:to_s))
      cfg['width'] = (cfg['width'] || tpl['width']).to_f
      cfg['height'] = (cfg['height'] || tpl['height']).to_f
      cfg['depth'] = (cfg['depth'] || DEFAULT_DEPTH).to_f
      cfg['offset_x'] = cfg['offset_x'].to_f
      cfg['offset_y'] = cfg['offset_y'].to_f
      cfg['anchor'] = cfg['anchor'].to_s
      cfg['cut_mode'] = cfg['cut_mode'].to_s
      raise 'Rộng/Cao vector phải lớn hơn 0.' unless cfg['width'] > 0 && cfg['height'] > 0
      raise 'Sâu CNC không được âm.' if cfg['depth'] < 0
      @active_tool = PlacementTool.new(tpl,cfg)
      Sketchup.active_model.select_tool(@active_tool)
      true
    end

    def instance_entity?(entity)
      (defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)) ||
        (entity.respond_to?(:definition) && entity.respond_to?(:transformation))
    rescue StandardError
      false
    end

    def instance_scale(transform, axis)
      origin = Geom::Point3d.new(0,0,0).transform(transform)
      point = Geom::Point3d.new(axis[0],axis[1],axis[2]).transform(transform)
      origin.distance(point)
    rescue StandardError
      1.0
    end

    def instance_dimensions(instance, world_transform = nil)
      definition = instance.definition
      bounds = definition.bounds
      transform = world_transform || instance.transformation
      sx = instance_scale(transform,[1,0,0])
      sy = instance_scale(transform,[0,1,0])
      sz = instance_scale(transform,[0,0,1])
      dims = [bounds.width.to_f*25.4*sx, bounds.height.to_f*25.4*sy, bounds.depth.to_f*25.4*sz]
      sorted = dims.sort.reverse
      {
        'length'=>sorted[0].round(3),
        'width'=>sorted[1].round(3),
        'thickness'=>sorted[2].round(3),
        'axes'=>dims.map { |v| v.round(3) },
        'name'=>(instance.respond_to?(:name) && !instance.name.to_s.empty? ? instance.name.to_s : definition.name.to_s)
      }
    end

    def selected_target_info
      selection = Sketchup.active_model.selection.to_a
      target = selection.find { |entity| instance_entity?(entity) }
      target ? instance_dimensions(target) : nil
    rescue StandardError
      nil
    end

    def show
      @dialog ||= build_dialog
      @dialog.show
      send_library
      send_target_info(selected_target_info)
    rescue StandardError => e
      UI.messagebox("VECTOR CNC: #{e.message}")
    end

    def build_dialog
      dlg = UI::HtmlDialog.new(
        dialog_title: 'TT – VECTOR CNC',
        preferences_key: 'TT_VECTOR_CNC',
        scrollable: true, resizable: true, width: 520, height: 650,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg.set_html(dialog_html)
      dlg.add_action_callback('ready') do
        send_library
        send_target_info(selected_target_info)
      end
      dlg.add_action_callback('select') do |_ctx,id|
        item = library.find { |row| row['id'].to_s == id.to_s }
        @dialog.execute_script("setSelectedTemplate(#{JSON.generate(item)})") if item
      end
      dlg.add_action_callback('start') do |_ctx,id,w,h,depth,offset_x,offset_y,anchor,cut_mode|
        item = library.find { |row| row['id'].to_s == id.to_s }
        raise 'Chưa chọn mẫu vector.' unless item
        activate_template(item,{
          'width'=>w.to_f,'height'=>h.to_f,'depth'=>depth.to_f,
          'offset_x'=>offset_x.to_f,'offset_y'=>offset_y.to_f,
          'anchor'=>anchor.to_s,'cut_mode'=>cut_mode.to_s
        })
      rescue StandardError => e
        UI.messagebox(e.message)
      end
      dlg.add_action_callback('update_settings') do |_ctx,w,h,depth,offset_x,offset_y,anchor,cut_mode|
        next unless @active_tool
        @active_tool.update_settings(
          'width'=>w.to_f,'height'=>h.to_f,'depth'=>depth.to_f,
          'offset_x'=>offset_x.to_f,'offset_y'=>offset_y.to_f,
          'anchor'=>anchor.to_s,'cut_mode'=>cut_mode.to_s
        )
      rescue StandardError => e
        puts "[VECTOR CNC settings] #{e.class}: #{e.message}"
      end
      dlg.add_action_callback('save') do |_ctx,id,name,w,h|
        item = library.find { |row| row['id'].to_s == id.to_s }
        raise 'Chưa chọn vector để lưu.' unless item
        saved = save_custom(item.merge('width'=>w.to_f,'height'=>h.to_f),name)
        send_library
        UI.messagebox("Đã lưu mẫu #{saved['name']}.")
      rescue StandardError => e
        UI.messagebox(e.message)
      end
      dlg.add_action_callback('delete') do |_ctx,id|
        delete_custom(id)
        send_library
      end
      dlg.add_action_callback('import') do |_ctx|
        path = UI.openpanel('Nhập VECTOR CNC', nil, 'Vector|*.svg;*.dxf;*.json||')
        next unless path
        item = import_file(path)
        saved = save_custom(item,item['name'])
        send_library
        UI.messagebox("Đã nhập #{saved['name']}.")
      rescue StandardError => e
        UI.messagebox("Không nhập được vector:\n#{e.message}")
      end
      dlg
    end

    def send_target_info(info)
      return unless @dialog
      @dialog.execute_script("setTargetInfo(#{JSON.generate(info)})")
    rescue StandardError
      false
    end

    def send_library
      return unless @dialog
      payload = library.map do |row|
        row.merge('points'=>row['points'].length, 'custom'=>!row['builtin'])
      end
      @dialog.execute_script("renderLibrary(#{JSON.generate(payload)})")
    rescue StandardError
      false
    end

    def dialog_html
      <<~HTML
      <!doctype html><html><head><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{font-family:Arial,sans-serif;background:#f3f4f6;margin:0;color:#222}
      header{background:#1f1f1f;color:#fff;padding:13px 16px;font-weight:700}
      main{padding:12px}.panel{background:#fff;border:1px solid #ddd;border-radius:9px;padding:10px;margin-bottom:10px}
      .title{font-weight:700;margin-bottom:8px;color:#9b4d13}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
      label{font-size:13px}input,select{padding:7px;border:1px solid #bbb;border-radius:5px;width:92px;background:#fff}
      select{width:145px}#name{width:180px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}
      button.card{min-height:54px;background:#fff;border:2px solid #ddd;border-radius:7px;cursor:pointer}
      button.card.active{border-color:#c56b20;background:#fff3e8}
      button.action{padding:9px 12px;border:0;border-radius:6px;background:#c56b20;color:#fff;font-weight:700;cursor:pointer}
      button.start{width:100%;font-size:15px;padding:12px;background:#186a3b;margin-top:9px}
      #preview{width:100%;height:190px;border:1px solid #bbb;border-radius:6px;background:#fafafa}
      #target{font-size:13px;line-height:1.5;background:#f8f8f8;padding:7px;border-radius:5px}
      small{display:block;margin-top:8px;line-height:1.4;color:#555}
      </style></head><body><header>TT – VECTOR CNC · CHỌN KHỐI GROUP / COMPONENT</header><main>

      <div class="panel">
        <div class="title">1. ĐỐI TƯỢNG GIA CÔNG</div>
        <div id="target">Chưa chọn Group/Component. Chọn một khối trong SketchUp hoặc bắt đầu tool rồi rà vào khối.</div>
      </div>

      <div class="panel">
        <div class="title">2. THƯ VIỆN VECTOR</div>
        <div class="grid" id="grid"></div>
      </div>

      <div class="panel">
        <div class="title">3. XEM TRƯỚC</div>
        <canvas id="preview" width="470" height="190"></canvas>
        <div id="previewInfo"></div>
      </div>

      <div class="panel">
        <div class="title">4. THIẾT LẬP CNC</div>
        <div class="row">
          <label>Rộng vector <input id="w" type="number" value="200" min="0.1"> mm</label>
          <label>Cao vector <input id="h" type="number" value="200" min="0.1"> mm</label>
          <label>Sâu CNC <input id="depth" type="number" value="3" min="0"> mm</label>
        </div>
        <div class="row" style="margin-top:8px">
          <label>Cách X <input id="offsetX" type="number" value="20"> mm</label>
          <label>Cách Y <input id="offsetY" type="number" value="20"> mm</label>
          <label>Vị trí
            <select id="anchor">
              <option value="center">Tâm khối</option>
              <option value="left_bottom">Trái - Dưới</option>
              <option value="right_bottom">Phải - Dưới</option>
              <option value="left_top">Trái - Trên</option>
              <option value="right_top">Phải - Trên</option>
            </select>
          </label>
          <label>Chạy dao
            <select id="cutMode">
              <option value="inside">Trong biên</option>
              <option value="on">Trên biên</option>
              <option value="outside">Ngoài biên</option>
            </select>
          </label>
        </div>
        <button class="action start" onclick="startPlacement()">BẮT ĐẦU ĐẶT VECTOR</button>
        <small>Tool nhận trực tiếp Group/Component, tự chọn mặt lớn nhất để gia công. Khi khối đang chọn, bảng sẽ hiện Dài × Rộng × Dày. Cách X/Y được tính theo vị trí neo đã chọn.</small>
      </div>

      <div class="panel">
        <div class="title">5. THƯ VIỆN RIÊNG</div>
        <div class="row"><input id="name" placeholder="Tên mẫu mới"><button class="action" onclick="save()">LƯU MẪU ABF_</button><button class="action" onclick="importVector()">NHẬP SVG/DXF/JSON</button></div>
      </div>

      </main><script>
      let selected=null,rows=[],selectedTemplate=null,targetInfo=null;
      function val(id){return parseFloat(document.getElementById(id).value)||0}
      function esc(s){return String(s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
      function renderLibrary(data){
        rows=data;let g=document.getElementById('grid');g.innerHTML='';
        data.forEach(r=>{
          let b=document.createElement('button');
          b.className='card'+(selected===r.id?' active':'');
          b.textContent=r.label+(r.custom?' ★':'');
          b.onclick=()=>{selected=r.id;renderLibrary(rows);window.sketchup.select(r.id)};
          g.appendChild(b)
        });
      }
      function setSelectedTemplate(t){
        selectedTemplate=t;
        if(!t)return;
        document.getElementById('w').value=t.width||200;
        document.getElementById('h').value=t.height||200;
        drawPreview();
      }
      function setTargetInfo(info){
        targetInfo=info;
        let el=document.getElementById('target');
        if(!info){el.textContent='Chưa chọn Group/Component. Chọn một khối trong SketchUp hoặc bắt đầu tool rồi rà vào khối.'}
        else{
          el.innerHTML='<b>'+esc(info.name||'Đối tượng')+'</b><br>Dài: <b>'+Number(info.length).toFixed(1)+' mm</b> · Rộng: <b>'+Number(info.width).toFixed(1)+' mm</b> · Dày: <b>'+Number(info.thickness).toFixed(1)+' mm</b>';
        }
        drawPreview();
      }
      function pushSettings(){
        if(window.sketchup&&window.sketchup.update_settings){
          window.sketchup.update_settings(val('w'),val('h'),val('depth'),val('offsetX'),val('offsetY'),document.getElementById('anchor').value,document.getElementById('cutMode').value)
        }
        drawPreview()
      }
      function drawPreview(){
        let c=document.getElementById('preview'),ctx=c.getContext('2d'),W=c.width,H=c.height;
        ctx.clearRect(0,0,W,H);ctx.fillStyle='#fafafa';ctx.fillRect(0,0,W,H);
        let objW=targetInfo?Math.max(1,Number(targetInfo.length)):600;
        let objH=targetInfo?Math.max(1,Number(targetInfo.width)):400;
        let margin=24,scale=Math.min((W-2*margin)/objW,(H-2*margin)/objH);
        let rw=objW*scale,rh=objH*scale,ox=(W-rw)/2,oy=(H-rh)/2;
        ctx.strokeStyle='#555';ctx.lineWidth=2;ctx.strokeRect(ox,oy,rw,rh);
        if(selectedTemplate&&selectedTemplate.points){
          let pts=selectedTemplate.points,w=val('w'),h=val('h');
          let pxScale=w*scale/2,pyScale=h*scale/2,cx=W/2,cy=H/2;
          ctx.beginPath();pts.forEach((p,i)=>{let x=cx+p[0]*pxScale,y=cy-p[1]*pyScale;i?ctx.lineTo(x,y):ctx.moveTo(x,y)});
          ctx.closePath();ctx.strokeStyle='#c56b20';ctx.lineWidth=2;ctx.stroke();
        }
        document.getElementById('previewInfo').textContent=selectedTemplate?((selectedTemplate.name||'')+' · '+val('w')+' × '+val('h')+' mm'):'Chọn một vector để xem trước.';
      }
      function startPlacement(){
        if(!selected){alert('Chưa chọn vector.');return}
        window.sketchup.start(selected,val('w'),val('h'),val('depth'),val('offsetX'),val('offsetY'),document.getElementById('anchor').value,document.getElementById('cutMode').value)
      }
      function save(){if(!selected)return;let n=document.getElementById('name').value.trim();if(!n)return;window.sketchup.save(selected,n,val('w'),val('h'))}
      function importVector(){window.sketchup.import()}
      ['w','h','depth','offsetX','offsetY','anchor','cutMode'].forEach(id=>document.addEventListener('DOMContentLoaded',()=>document.getElementById(id).addEventListener('input',pushSettings)));
      document.addEventListener('DOMContentLoaded',()=>window.sketchup.ready())
      </script></body></html>
      HTML
    end

    class PlacementTool
      def initialize(template,width,height,depth)
        @template = template
        @width = [width.to_f,0.1].max
        @height = [height.to_f,0.1].max
        @depth = [depth.to_f,0.0].max
        @ip = Sketchup::InputPoint.new
        reset_hover
      end

      def activate
        Sketchup.status_text = status_text
        Sketchup.vcb_label = 'Rộng x Cao'
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
      end

      def deactivate(view)
        view.invalidate
      end

      def reset_hover
        @face = nil
        @definition = nil
        @face_transform = nil
        @pick_path = nil
        @owner_instance = nil
        @basis = nil
        @center = nil
        @polygon_world = []
        @face_boundary = []
        @face_size = nil
        @guide = nil
        @error = nil
      end

      def status_text
        "VECTOR CNC #{@template['name']} · PickHelper nhận Face lồng Group/Component · nhập W x H · lăn chuột co giãn · click tạo"
      end

      def face_entity?(entity)
        return false unless entity
        return entity.is_a?(Sketchup::Face) if defined?(Sketchup::Face)
        entity.respond_to?(:outer_loop) && entity.respond_to?(:parent)
      rescue StandardError
        false
      end

      def instance_entity?(entity)
        return false unless entity
        return true if defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)
        return true if defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)
        entity.respond_to?(:definition) && entity.respond_to?(:transformation)
      rescue StandardError
        false
      end

      def pick_grouped_face(view,x,y)
        ph = view.pick_helper
        count = ph.do_pick(x,y,6)
        return nil if count.to_i <= 0

        candidates = []
        ph.count.times do |index|
          leaf = ph.leaf_at(index)
          path = ph.path_at(index)
          next unless face_entity?(leaf)
          path = Array(path)
          instances = path[0...-1].select { |entity| instance_entity?(entity) }

          # Khi đang edit bên trong Group/Component, PickHelper có thể chỉ trả Face.
          if instances.empty?
            active_path = Sketchup.active_model.respond_to?(:active_path) ? Array(Sketchup.active_model.active_path) : []
            instances = active_path.select { |entity| instance_entity?(entity) }
          end
          next if instances.empty?

          transform = begin
            ph.transformation_at(index)
          rescue StandardError
            nil
          end
          transform ||= begin
            instances.inject(Geom::Transformation.new) { |memo,instance| memo * instance.transformation }
          rescue StandardError
            Geom::Transformation.new
          end

          owner_instance = instances.last
          definition = owner_instance.respond_to?(:definition) ? owner_instance.definition : nil
          definition ||= begin
            entities = leaf.parent
            entities.respond_to?(:parent) ? entities.parent : nil
          rescue StandardError
            nil
          end
          next unless definition && definition.respond_to?(:entities)

          candidates << {
            face: leaf,
            definition: definition,
            transform: transform,
            path: path,
            instances: instances,
            owner_instance: owner_instance,
            depth: (ph.respond_to?(:depth_at) ? ph.depth_at(index).to_f : index.to_f)
          }
        end
        return nil if candidates.empty?

        # Ưu tiên Face sâu nhất/đúng dưới con trỏ trong chuỗi lồng.
        candidates.max_by { |row| [row[:path].length, row[:depth]] }
      rescue StandardError
        nil
      end

      def shared_instance_conflict(info)
        Array(info[:instances]).find do |instance|
          definition = instance.respond_to?(:definition) ? instance.definition : nil
          definition && definition.respond_to?(:instances) && definition.instances.length > 1
        end
      rescue StandardError
        nil
      end

      def face_basis(face, transform, view)
        pts = face.outer_loop.vertices.map { |v| v.position.transform(transform) }
        raise 'Face không đủ điểm.' if pts.length < 3
        a,b = pts[0],pts[1]
        normal = nil
        pts.drop(2).each do |c|
          n = a.vector_to(b).cross(a.vector_to(c))
          if n.length > 1.0e-8
            normal = n.normalize
            break
          end
        end
        raise 'Không nhận được pháp tuyến Face.' unless normal
        normal.reverse! if normal.dot(view.camera.direction) > 0
        axis = Geom::Vector3d.new(0,0,1)
        dot = axis.dot(normal)
        v = Geom::Vector3d.new(axis.x-normal.x*dot,axis.y-normal.y*dot,axis.z-normal.z*dot)
        axis = Geom::Vector3d.new(0,1,0) if v.length < 1.0e-6
        if v.length < 1.0e-6
          dot = axis.dot(normal)
          v = Geom::Vector3d.new(axis.x-normal.x*dot,axis.y-normal.y*dot,axis.z-normal.z*dot)
        end
        v.normalize!
        u = v.cross(normal); u.normalize!
        Geom::Transformation.axes(a,u,v,normal)
      end

      def cursor_on_face_plane(view,x,y,face,transform)
        world = face.outer_loop.vertices.map { |v| v.position.transform(transform) }
        return nil if world.length < 3
        a = world[0]
        normal = nil
        b = world[1]
        world.drop(2).each do |c|
          n = a.vector_to(b).cross(a.vector_to(c))
          if n.length > 1.0e-8
            normal = n.normalize
            break
          end
        end
        return nil unless normal
        Geom.intersect_line_plane(view.pickray(x,y),[a,normal])
      rescue StandardError
        nil
      end

      def update_hover(view,x,y)
        @ip.pick(view,x,y)
        info = pick_grouped_face(view,x,y)
        unless info
          reset_hover
          @error = 'Rê vào Face nằm trong Group/Component để hiện preview.'
          return false
        end
        conflict = shared_instance_conflict(info)
        if conflict
          reset_hover
          @error = 'Component có nhiều bản sao. Hãy Make Unique trước để tránh sửa nhầm.'
          return false
        end

        face = info[:face]
        definition = info[:definition]
        transform = info[:transform]
        basis = face_basis(face,transform,view)
        inverse = basis.inverse
        face_world = face.outer_loop.vertices.map { |v| v.position.transform(transform) }
        local_face = face_world.map { |p| p.transform(inverse) }
        min_x,max_x = local_face.map(&:x).minmax
        min_y,max_y = local_face.map(&:y).minmax
        cursor_world = cursor_on_face_plane(view,x,y,face,transform)
        cursor_world ||= @ip.position if @ip.valid?
        raise 'Không xác định được vị trí chuột trên Face.' unless cursor_world
        cursor_local = cursor_world.transform(inverse)
        cx = [[cursor_local.x,min_x].max,max_x].min
        cy = [[cursor_local.y,min_y].max,max_y].min
        center_local = Geom::Point3d.new(cx,cy,0)
        center_world = center_local.transform(basis)

        points = VectorCNC.scaled_points(@template,@width,@height)
        @polygon_world = points.map { |px,py| Geom::Point3d.new(cx+px.mm,cy+py.mm,0).transform(basis) }
        @face_boundary = local_face.map { |p| Geom::Point3d.new(p.x,p.y,0).transform(basis) }
        @face_size = [(max_x-min_x).to_f*25.4,(max_y-min_y).to_f*25.4]
        face_center_local = Geom::Point3d.new((min_x+max_x)/2.0,(min_y+max_y)/2.0,0)
        dx = (cx-face_center_local.x).to_f*25.4
        dy = (cy-face_center_local.y).to_f*25.4
        if dx.abs >= dy.abs
          guide_end = Geom::Point3d.new(cx,face_center_local.y,0)
          @guide = [face_center_local.transform(basis),guide_end.transform(basis),"X #{dx.round(1)} mm"]
        else
          guide_end = Geom::Point3d.new(face_center_local.x,cy,0)
          @guide = [face_center_local.transform(basis),guide_end.transform(basis),"Y #{dy.round(1)} mm"]
        end

        @face = face
        @definition = definition
        @face_transform = transform
        @pick_path = info[:path]
        @owner_instance = info[:owner_instance]
        @basis = basis
        @center = center_world
        @error = nil
        true
      rescue StandardError => e
        reset_hover
        @error = e.message
        false
      end

      def onMouseMove(_flags,x,y,view)
        update_hover(view,x,y)
        face_text = @face_size ? " · FACE #{@face_size[0].round(1)} x #{@face_size[1].round(1)} mm" : ''
        view.tooltip = @error || "#{@template['name']} · #{@width.round(1)} x #{@height.round(1)} mm#{face_text}"
        Sketchup.status_text = @error || (status_text + face_text)
        view.invalidate
      end

      def onMouseWheel(_flags,delta,x,y,view)
        factor = delta.to_i > 0 ? 1.05 : 0.95
        @width = [@width*factor,0.1].max
        @height = [@height*factor,0.1].max
        update_hover(view,x,y)
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
        view.invalidate
        true
      end

      def onUserText(text,view)
        raw = text.to_s.strip.downcase.tr('×','x')
        nums = raw.scan(/[-+]?\d+(?:[\.,]\d+)?/).map { |v| v.tr(',','.').to_f }
        if nums.length >= 2
          @width = nums[0]
          @height = nums[1]
        elsif nums.length == 1
          ratio = @height / @width
          @width = nums[0]
          @height = @width * ratio
        else
          raise 'Nhập kích thước dạng 500x300.'
        end
        raise 'Kích thước phải lớn hơn 0.' unless @width > 0 && @height > 0
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
        view.invalidate
      rescue StandardError => e
        UI.messagebox(e.message)
      end

      def create_vector
        raise(@error || 'Chưa rà vào Face hợp lệ.') unless @face && @definition && @face_transform && @polygon_world.length >= 3
        conflict = Array(@pick_path && @pick_path[0...-1]).find do |entity|
          next false unless instance_entity?(entity)
          definition = entity.definition
          definition.respond_to?(:instances) && definition.instances.length > 1
        end
        raise 'Component có nhiều bản sao. Hãy Make Unique trước.' if conflict

        model = Sketchup.active_model
        model.start_operation('TT - VECTOR CNC', true)
        started = true
        parent_entities = @face.parent
        group = parent_entities.add_group
        group.name = '_ABF_Intersect'
        tag_name = @template['name'].to_s.start_with?('ABF_') ? @template['name'] : VectorCNC.abf_name(@template['name'])
        tag = VectorCNC.ensure_tag(model,tag_name)
        group.layer = tag
        group.set_attribute('ABF','is-intersect',true)
        group.set_attribute('ABF','intersect-offset',0.0)
        group.set_attribute('ABF','setting-name',tag_name.sub(/\AABF_/,'').downcase.tr('_',' '))
        group.set_attribute('ABF','intersect-group-b-id',@face.respond_to?(:persistent_id) ? @face.persistent_id : @face.object_id)
        group.set_attribute(KEY,'template',tag_name)
        group.set_attribute(KEY,'width_mm',@width)
        group.set_attribute(KEY,'height_mm',@height)
        group.set_attribute(KEY,'depth_mm',@depth)

        inverse = @face_transform.inverse
        local_points = @polygon_world.map { |p| p.transform(inverse) }
        face = group.entities.add_face(local_points)
        raise 'Không tạo được Face vector kín.' unless face
        face.reverse! if face.normal.z < 0 rescue nil
        face.layer = tag
        face.edges.each { |edge| edge.layer = tag }
        @face.set_attribute('ABF','is-cnced-face',true)
        model.commit_operation
        started = false
        model.selection.clear
        model.selection.add(group)
        group
      rescue StandardError
        model.abort_operation if started
        raise
      end

      def onLButtonDown(_flags,x,y,view)
        unless @face && @definition && @polygon_world.length >= 3
          update_hover(view,x,y)
          UI.beep
          Sketchup.status_text = @error || status_text
          view.invalidate
          return
        end
        create_vector
        view.invalidate
      rescue StandardError => e
        UI.messagebox("VECTOR CNC: #{e.message}")
      end

      def draw(view)
        @ip.draw(view) if @ip.valid?
        if @face_boundary.length > 2
          view.drawing_color = Sketchup::Color.new(255,130,0)
          view.line_width = 2
          view.draw(GL_LINE_LOOP,@face_boundary)
        end
        if @polygon_world.length > 2
          view.drawing_color = Sketchup::Color.new(40,180,80)
          view.line_width = 2
          view.draw(GL_LINE_LOOP,@polygon_world)
          view.draw_points([@center],7,3,Sketchup::Color.new(255,100,0)) if @center
        end
        if @guide
          a,b,label = @guide
          view.drawing_color = Sketchup::Color.new(50,120,220)
          view.line_width = 1
          view.draw(GL_LINES,[a,b])
          view.draw_text(b,label,color: Sketchup::Color.new(50,100,190))
        end
        face_text = @face_size ? " · FACE #{@face_size[0].round(1)} x #{@face_size[1].round(1)}" : ''
        text = @error || "#{@template['name']} · VECTOR #{@width.round(1)} x #{@height.round(1)} mm · sâu #{@depth.round(1)} mm#{face_text}"
        view.draw_text([20,35],text,color: Sketchup::Color.new(145,75,20))
      end

      def getExtents
        box = Geom::BoundingBox.new
        @face_boundary.each { |p| box.add(p) }
        @polygon_world.each { |p| box.add(p) }
        box
      end

      def onCancel(_reason,_view)
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
