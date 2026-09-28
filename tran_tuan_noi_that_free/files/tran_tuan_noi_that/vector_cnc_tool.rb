# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'rexml/document'

module TranTuanNoiThat
  module VectorCNC
    extend self

    VERSION = '1.1.1'.freeze
    KEY = 'TT_VECTOR_CNC'.freeze
    DATA_DIR = File.join(TranTuanNoiThat::ROOT, 'data', 'vector_cnc').freeze
    LIBRARY_FILE = File.join(DATA_DIR, 'library.json').freeze
    DEFAULT_SIZE = 200.0
    DEFAULT_DEPTH = 3.0
    DEFAULT_CNC = {
      'depth' => 3.0,
      'offset_x' => 20.0,
      'offset_y' => 20.0,
      'border_width' => 0.0,
      'smoothness' => 72,
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

    def clamp_smoothness(value)
      [[value.to_i, 12].max, 240].min
    end

    def points_for_template(template, smoothness = nil)
      segments = clamp_smoothness(smoothness || 72)
      case template['id'].to_s
      when 'circle'
        circle_points(segments)
      when 'oval'
        circle_points(segments).map { |x,y| [x, y*0.6] }
      else
        template['points']
      end
    end

    def scaled_points(template, width, height, smoothness = nil)
      unit = points_for_template(template,smoothness)
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
      cfg['border_width'] = [cfg['border_width'].to_f,0.0].max
      cfg['smoothness'] = clamp_smoothness(cfg['smoothness'])
      cfg['anchor'] = cfg['anchor'].to_s
      cfg['cut_mode'] = cfg['cut_mode'].to_s
      raise 'Rộng/Cao vector phải lớn hơn 0.' unless cfg['width'] > 0 && cfg['height'] > 0
      raise 'Sâu CNC không được âm.' if cfg['depth'] < 0
      @active_tool = PlacementTool.new(tpl,cfg)
      Sketchup.active_model.select_tool(@active_tool)
      true
    end

    def cnc_settings(width,height,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode)
      {
        'width'=>width.to_f,
        'height'=>height.to_f,
        'depth'=>depth.to_f,
        'offset_x'=>offset_x.to_f,
        'offset_y'=>offset_y.to_f,
        'border_width'=>border_width.to_f,
        'smoothness'=>smoothness.to_i,
        'anchor'=>anchor.to_s,
        'cut_mode'=>cut_mode.to_s
      }
    end

    def apply_template_to_selected(template, settings)
      tpl = sanitize_template(template)
      tool = PlacementTool.new(tpl,settings)
      tool.apply_selected
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
        'name'=>(instance.respond_to?(:name) && !instance.name.to_s.empty? ? instance.name.to_s : (definition.respond_to?(:name) ? definition.name.to_s : 'Group/Component'))
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
        scrollable: true, resizable: true, width: 580, height: 780,
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
      dlg.add_action_callback('refresh_target') do |_ctx|
        send_target_info(selected_target_info)
      end
      dlg.add_action_callback('apply_selected') do |_ctx,id,w,h,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode|
        item = library.find { |row| row['id'].to_s == id.to_s }
        raise 'Chưa chọn mẫu vector.' unless item
        apply_template_to_selected(item,cnc_settings(w,h,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode))
        send_target_info(selected_target_info)
      rescue StandardError => e
        UI.messagebox(e.message)
      end
      dlg.add_action_callback('start') do |_ctx,id,w,h,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode|
        item = library.find { |row| row['id'].to_s == id.to_s }
        raise 'Chưa chọn mẫu vector.' unless item
        activate_template(item,cnc_settings(w,h,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode))
      rescue StandardError => e
        UI.messagebox(e.message)
      end
      dlg.add_action_callback('update_settings') do |_ctx,w,h,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode|
        next unless @active_tool
        @active_tool.update_settings(cnc_settings(w,h,depth,offset_x,offset_y,border_width,smoothness,anchor,cut_mode))
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
      *{box-sizing:border-box}
      body{font-family:Arial,sans-serif;background:#f3f4f6;margin:0;color:#222}
      header{background:#1f1f1f;color:#fff;padding:13px 16px;font-weight:700}
      main{padding:12px}.panel{background:#fff;border:1px solid #ddd;border-radius:9px;padding:10px;margin-bottom:10px}
      .title{font-weight:700;margin-bottom:8px;color:#9b4d13}
      .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
      label{font-size:13px}input,select{padding:7px;border:1px solid #bbb;border-radius:5px;width:92px;background:#fff}
      select{width:145px}#name{width:180px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}
      button.card{min-height:54px;background:#fff;border:2px solid #ddd;border-radius:7px;cursor:pointer}
      button.card.active{border-color:#c56b20;background:#fff3e8}
      button.action{padding:9px 12px;border:0;border-radius:6px;background:#c56b20;color:#fff;font-weight:700;cursor:pointer}
      button.apply{width:100%;font-size:15px;padding:12px;background:#186a3b;margin-top:9px}
      button.secondary{background:#555}
      #preview{width:100%;height:210px;border:1px solid #bbb;border-radius:6px;background:#fafafa}
      #target{font-size:13px;line-height:1.5;background:#f8f8f8;padding:7px;border-radius:5px}
      .align-grid{display:grid;grid-template-columns:repeat(3,42px);gap:4px}
      .align-grid button{height:34px;border:1px solid #bbb;background:#fff;border-radius:4px;cursor:pointer;font-size:15px}
      .align-grid button.active{background:#c56b20;color:#fff;border-color:#c56b20}
      small{display:block;margin-top:8px;line-height:1.4;color:#555}
      </style></head><body><header>TT – VECTOR CNC · ÁP DỤNG VÀO GROUP / COMPONENT ĐANG CHỌN</header><main>

      <div class="panel">
        <div class="title">1. KHỐI ĐANG CHỌN</div>
        <div id="target">Chưa chọn Group/Component.</div>
        <div class="row" style="margin-top:8px">
          <button class="action secondary" onclick="refreshTarget()">LẤY KHỐI ĐANG CHỌN</button>
        </div>
      </div>

      <div class="panel">
        <div class="title">2. CHỌN VECTOR MẪU</div>
        <div class="grid" id="grid"></div>
      </div>

      <div class="panel">
        <div class="title">3. XEM TRƯỚC TRÊN MẶT CNC</div>
        <canvas id="preview" width="530" height="210"></canvas>
        <div id="previewInfo"></div>
      </div>

      <div class="panel">
        <div class="title">4. KÍCH THƯỚC + GIA CÔNG CNC</div>
        <div class="row">
          <label>Rộng vector <input id="w" type="number" value="200" min="0.1"> mm</label>
          <label>Cao vector <input id="h" type="number" value="200" min="0.1"> mm</label>
          <label>Sâu CNC <input id="depth" type="number" value="3" min="0"> mm</label>
        </div>
        <div class="row" style="margin-top:8px">
          <label>Viền rộng <input id="borderWidth" type="number" value="0" min="0"> mm</label>
          <label>Làm mịn <input id="smoothness" type="number" value="72" min="12" max="240" step="12"> đoạn</label>
          <label>Chạy dao
            <select id="cutMode">
              <option value="inside">Trong biên</option>
              <option value="on">Trên biên</option>
              <option value="outside">Ngoài biên</option>
            </select>
          </label>
        </div>
      </div>

      <div class="panel">
        <div class="title">5. CĂN CHỈNH VECTOR</div>
        <div class="row">
          <div class="align-grid">
            <button data-anchor="left_top" onclick="setAnchor('left_top')" title="Trái - Trên">↖</button>
            <button data-anchor="top" onclick="setAnchor('top')" title="Giữa - Trên">↑</button>
            <button data-anchor="right_top" onclick="setAnchor('right_top')" title="Phải - Trên">↗</button>
            <button data-anchor="left" onclick="setAnchor('left')" title="Trái - Giữa">←</button>
            <button data-anchor="center" onclick="setAnchor('center')" title="Căn giữa">●</button>
            <button data-anchor="right" onclick="setAnchor('right')" title="Phải - Giữa">→</button>
            <button data-anchor="left_bottom" onclick="setAnchor('left_bottom')" title="Trái - Dưới">↙</button>
            <button data-anchor="bottom" onclick="setAnchor('bottom')" title="Giữa - Dưới">↓</button>
            <button data-anchor="right_bottom" onclick="setAnchor('right_bottom')" title="Phải - Dưới">↘</button>
          </div>
          <div>
            <div class="row">
              <label>Cách/Dịch X <input id="offsetX" type="number" value="20"> mm</label>
              <label>Cách/Dịch Y <input id="offsetY" type="number" value="20"> mm</label>
            </div>
            <small>Ở mép Trái/Phải/Trên/Dưới, X/Y là cách mép. Ở Căn giữa, X/Y là độ dịch khỏi tâm.</small>
          </div>
        </div>
        <input id="anchor" type="hidden" value="center">
      </div>

      <div class="panel">
        <button class="action apply" onclick="applySelected()">ÁP DỤNG VECTOR VÀO KHỐI ĐANG CHỌN</button>
        <div class="row" style="margin-top:8px">
          <button class="action secondary" onclick="startPlacement()">RÀ / ĐẶT TRÊN KHỐI KHÁC</button>
        </div>
        <small>ÁP DỤNG: tool tự đọc Dài × Rộng × Dày, tự chọn mặt CNC lớn nhất của khối và tạo vector thật bên trong Group/Component. Một lần áp dụng = một Undo.</small>
      </div>

      <div class="panel">
        <div class="title">6. THƯ VIỆN RIÊNG</div>
        <div class="row"><input id="name" placeholder="Tên mẫu mới"><button class="action" onclick="save()">LƯU MẪU ABF_</button><button class="action" onclick="importVector()">NHẬP SVG/DXF/JSON</button></div>
      </div>

      </main><script>
      let selected=null,rows=[],selectedTemplate=null,targetInfo=null;

      function val(id){return parseFloat(document.getElementById(id).value)||0}
      function intval(id){return parseInt(document.getElementById(id).value||'0',10)||0}
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
        if(!info){el.textContent='Chưa chọn Group/Component.'}
        else{
          let face=info.face_length?('<br>Mặt CNC tự động: <b>'+Number(info.face_length).toFixed(1)+' × '+Number(info.face_width).toFixed(1)+' mm</b>'):'';
          el.innerHTML='<b>'+esc(info.name||'Đối tượng')+'</b><br>Dài: <b>'+Number(info.length).toFixed(1)+' mm</b> · Rộng: <b>'+Number(info.width).toFixed(1)+' mm</b> · Dày: <b>'+Number(info.thickness).toFixed(1)+' mm</b>'+face;
        }
        drawPreview();
      }

      function setAnchor(value){
        document.getElementById('anchor').value=value;
        document.querySelectorAll('.align-grid button').forEach(b=>b.classList.toggle('active',b.dataset.anchor===value));
        pushSettings();
      }

      function currentSettings(){
        return [
          val('w'),val('h'),val('depth'),val('offsetX'),val('offsetY'),
          val('borderWidth'),intval('smoothness'),
          document.getElementById('anchor').value,
          document.getElementById('cutMode').value
        ];
      }

      function pushSettings(){
        if(window.sketchup&&window.sketchup.update_settings){
          window.sketchup.update_settings(...currentSettings());
        }
        drawPreview();
      }

      function previewPoints(){
        if(!selectedTemplate)return [];
        let smooth=Math.max(12,Math.min(240,intval('smoothness')||72));
        if(selectedTemplate.id==='circle'||selectedTemplate.id==='oval'){
          let pts=[];
          for(let i=0;i<smooth;i++){
            let a=2*Math.PI*i/smooth;
            pts.push([Math.cos(a),Math.sin(a)*(selectedTemplate.id==='oval'?0.6:1)]);
          }
          return pts;
        }
        return selectedTemplate.points||[];
      }

      function anchorCenter(objW,objH,w,h,dx,dy,anchor){
        let cx=objW/2+dx,cy=objH/2+dy;
        if(anchor==='left'){cx=w/2+dx;cy=objH/2+dy}
        if(anchor==='right'){cx=objW-w/2-dx;cy=objH/2+dy}
        if(anchor==='top'){cx=objW/2+dx;cy=objH-h/2-dy}
        if(anchor==='bottom'){cx=objW/2+dx;cy=h/2+dy}
        if(anchor==='left_bottom'){cx=w/2+dx;cy=h/2+dy}
        if(anchor==='right_bottom'){cx=objW-w/2-dx;cy=h/2+dy}
        if(anchor==='left_top'){cx=w/2+dx;cy=objH-h/2-dy}
        if(anchor==='right_top'){cx=objW-w/2-dx;cy=objH-h/2-dy}
        cx=Math.max(w/2,Math.min(objW-w/2,cx));
        cy=Math.max(h/2,Math.min(objH-h/2,cy));
        return [cx,cy];
      }

      function drawPreview(){
        let c=document.getElementById('preview'),ctx=c.getContext('2d'),W=c.width,H=c.height;
        ctx.clearRect(0,0,W,H);ctx.fillStyle='#fafafa';ctx.fillRect(0,0,W,H);
        let objW=targetInfo?Math.max(1,Number(targetInfo.face_length||targetInfo.length)):600;
        let objH=targetInfo?Math.max(1,Number(targetInfo.face_width||targetInfo.width)):400;
        let margin=24,scale=Math.min((W-2*margin)/objW,(H-2*margin)/objH);
        let rw=objW*scale,rh=objH*scale,ox=(W-rw)/2,oy=(H-rh)/2;
        ctx.strokeStyle='#555';ctx.lineWidth=2;ctx.strokeRect(ox,oy,rw,rh);

        if(selectedTemplate){
          let pts=previewPoints(),w=val('w'),h=val('h'),dx=val('offsetX'),dy=val('offsetY');
          let anchor=document.getElementById('anchor').value,[cx,cy]=anchorCenter(objW,objH,w,h,dx,dy,anchor);
          let pcx=ox+cx*scale,pcy=oy+(objH-cy)*scale,pxScale=w*scale/2,pyScale=h*scale/2;

          function trace(){
            ctx.beginPath();
            pts.forEach((p,i)=>{let x=pcx+p[0]*pxScale,y=pcy-p[1]*pyScale;i?ctx.lineTo(x,y):ctx.moveTo(x,y)});
            ctx.closePath();
          }

          let border=val('borderWidth');
          if(border>0){
            trace();ctx.strokeStyle='rgba(197,107,32,.25)';ctx.lineWidth=Math.max(2,border*scale*2);ctx.stroke();
          }
          trace();
          let mode=document.getElementById('cutMode').value;
          ctx.setLineDash(mode==='on'?[]:(mode==='inside'?[6,3]:[2,3]));
          ctx.strokeStyle='#c56b20';ctx.lineWidth=2;ctx.stroke();ctx.setLineDash([]);
        }

        let extra=' · Viền '+val('borderWidth')+' mm · Mịn '+intval('smoothness');
        document.getElementById('previewInfo').textContent=selectedTemplate?((selectedTemplate.name||'')+' · '+val('w')+' × '+val('h')+' mm'+extra):'Chọn một vector để xem trước.';
      }

      function refreshTarget(){window.sketchup.refresh_target()}
      function applySelected(){
        if(!selected){alert('Chưa chọn vector.');return}
        window.sketchup.apply_selected(selected,...currentSettings())
      }
      function startPlacement(){
        if(!selected){alert('Chưa chọn vector.');return}
        window.sketchup.start(selected,...currentSettings())
      }
      function save(){if(!selected)return;let n=document.getElementById('name').value.trim();if(!n)return;window.sketchup.save(selected,n,val('w'),val('h'))}
      function importVector(){window.sketchup.import()}

      document.addEventListener('DOMContentLoaded',()=>{
        ['w','h','depth','offsetX','offsetY','borderWidth','smoothness','cutMode'].forEach(id=>{
          let el=document.getElementById(id);el.addEventListener('input',pushSettings);el.addEventListener('change',pushSettings)
        });
        setAnchor('center');
        window.sketchup.ready();
      })
      </script></body></html>
      HTML
    end

    class PlacementTool
      BOX_EDGES = [[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]].freeze

      def initialize(template, settings = {})
        @template = template
        @settings = DEFAULT_CNC.merge(settings.transform_keys(&:to_s))
        @ip = Sketchup::InputPoint.new
        reset_target
        sync_settings
      end

      def sync_settings
        @width = [(@settings['width'] || @template['width']).to_f,0.1].max
        @height = [(@settings['height'] || @template['height']).to_f,0.1].max
        @depth = [(@settings['depth'] || DEFAULT_DEPTH).to_f,0.0].max
        @offset_x = @settings['offset_x'].to_f
        @offset_y = @settings['offset_y'].to_f
        @border_width = [@settings['border_width'].to_f,0.0].max
        @smoothness = VectorCNC.clamp_smoothness(@settings['smoothness'])
        @anchor = @settings['anchor'].to_s
        @cut_mode = @settings['cut_mode'].to_s
        @anchor = 'center' unless %w[center left right top bottom left_bottom right_bottom left_top right_top].include?(@anchor)
        @cut_mode = 'inside' unless %w[inside on outside].include?(@cut_mode)
      end

      def activate
        view = Sketchup.active_model.active_view
        use_selected_target(view)
        Sketchup.status_text = status_text
        Sketchup.vcb_label = 'Rộng x Cao'
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
        view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def update_settings(settings)
        @settings = @settings.merge(settings.transform_keys(&:to_s))
        sync_settings
        rebuild_preview if @target_instance && @machining_face
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
        Sketchup.active_model.active_view.invalidate
      end

      def reset_target
        @target_instance = nil
        @target_definition = nil
        @target_transform = nil
        @target_path = []
        @target_info = nil
        @machining_face = nil
        @basis = nil
        @face_boundary = []
        @target_box = []
        @polygon_world = []
        @border_polygon_world = []
        @center = nil
        @guides = []
        @error = nil
      end

      def status_text
        if @target_instance && @target_info
          "VECTOR CNC #{@template['name']} · #{@target_info['name']} #{@target_info['length']}×#{@target_info['width']}×#{@target_info['thickness']} mm · #{@cut_mode.upcase} · click tạo"
        else
          "VECTOR CNC #{@template['name']} · rà/chọn Group hoặc Component · tool tự đọc Dài×Rộng×Dày và chọn mặt CNC"
        end
      end

      def instance_entity?(entity)
        VectorCNC.instance_entity?(entity)
      end

      def composed_transform(instances)
        Array(instances).inject(Geom::Transformation.new) do |memo,instance|
          memo * instance.transformation
        end
      rescue StandardError
        Geom::Transformation.new
      end

      def world_transform_for_selected(instance)
        model = Sketchup.active_model
        parents = model.respond_to?(:active_path) ? Array(model.active_path) : []
        composed_transform(parents + [instance])
      end

      def use_selected_target(view)
        target = Sketchup.active_model.selection.to_a.find { |entity| instance_entity?(entity) }
        return false unless target
        info = {
          instance: target,
          definition: target.definition,
          transform: world_transform_for_selected(target),
          path: [target]
        }
        set_target(info,view)
      rescue StandardError => e
        @error = e.message
        false
      end

      def pick_target_instance(view,x,y)
        ph = view.pick_helper
        count = ph.do_pick(x,y,6)
        return nil if count.to_i <= 0
        candidates = []

        ph.count.times do |index|
          path = Array(ph.path_at(index))
          leaf = ph.leaf_at(index)
          instances = path.select { |entity| instance_entity?(entity) }
          instances << leaf if instance_entity?(leaf) && !instances.include?(leaf)

          if instances.empty?
            active = Sketchup.active_model.respond_to?(:active_path) ? Array(Sketchup.active_model.active_path) : []
            instances = active.select { |entity| instance_entity?(entity) }
          end
          next if instances.empty?

          target = instances.last
          definition = target.definition
          transform = begin
            ph.transformation_at(index)
          rescue StandardError
            nil
          end
          transform ||= composed_transform(instances)

          candidates << {
            instance: target,
            definition: definition,
            transform: transform,
            path: instances,
            depth: (ph.respond_to?(:depth_at) ? ph.depth_at(index).to_f : index.to_f)
          }
        end
        return nil if candidates.empty?
        candidates.max_by { |row| [row[:path].length,row[:depth]] }
      rescue StandardError
        nil
      end

      def shared_definition?(definition)
        definition.respond_to?(:instances) && definition.instances.length > 1
      rescue StandardError
        false
      end

      def face_entities(definition)
        if defined?(Sketchup::Face)
          definition.entities.grep(Sketchup::Face)
        else
          definition.entities.select { |entity| entity.respond_to?(:outer_loop) && entity.respond_to?(:normal) }
        end
      end

      def transformed_face_area(face, transform)
        face.area(transform).to_f
      rescue StandardError
        face.respond_to?(:area) ? face.area.to_f : 0.0
      end

      def transformed_face_normal(face, transform)
        normal = face.normal.transform(transform)
        normal.normalize!
        normal
      rescue StandardError
        face.normal
      end

      def choose_machining_face(definition, transform, view)
        faces = face_entities(definition)
        raise 'Khối không có Face trực tiếp để gia công CNC.' if faces.empty?
        direction = view.camera.direction
        faces.max_by do |face|
          area = transformed_face_area(face,transform)
          normal = transformed_face_normal(face,transform)
          facing = normal.length > 0 ? [-normal.normalize.dot(direction),0.0].max : 0.0
          area * (0.35 + facing)
        end
      end

      def face_basis(face, transform, view)
        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
        raise 'Mặt CNC không đủ điểm.' if points.length < 3
        a,b = points[0],points[1]
        normal = nil
        points.drop(2).each do |c|
          n = a.vector_to(b).cross(a.vector_to(c))
          if n.length > 1.0e-8
            normal = n.normalize
            break
          end
        end
        raise 'Không xác định được mặt phẳng CNC.' unless normal
        normal.reverse! if normal.dot(view.camera.direction) > 0

        candidates = [Geom::Vector3d.new(0,0,1),Geom::Vector3d.new(0,1,0),Geom::Vector3d.new(1,0,0)]
        v = nil
        candidates.each do |axis|
          dot = axis.dot(normal)
          projected = Geom::Vector3d.new(axis.x-normal.x*dot,axis.y-normal.y*dot,axis.z-normal.z*dot)
          if projected.length > 1.0e-6
            v = projected.normalize
            break
          end
        end
        raise 'Không xác định được trục Dài/Rộng của mặt CNC.' unless v
        u = v.cross(normal)
        u.normalize!
        Geom::Transformation.axes(a,u,v,normal)
      end

      def target_box_points(definition, transform)
        bounds = definition.bounds
        8.times.map { |i| bounds.corner(i).transform(transform) }
      rescue StandardError
        []
      end

      def face_geometry(face, transform, view)
        basis = face_basis(face,transform,view)
        inverse = basis.inverse
        world = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
        local = world.map { |point| point.transform(inverse) }
        min_x,max_x = local.map(&:x).minmax
        min_y,max_y = local.map(&:y).minmax
        {
          basis: basis, inverse: inverse, world: world, local: local,
          min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y,
          width_mm: (max_x-min_x).to_f*25.4,
          height_mm: (max_y-min_y).to_f*25.4
        }
      end

      def center_for_anchor(geometry)
        min_x,max_x = geometry[:min_x],geometry[:max_x]
        min_y,max_y = geometry[:min_y],geometry[:max_y]
        half_w = @width.mm/2.0
        half_h = @height.mm/2.0
        face_w = max_x-min_x
        face_h = max_y-min_y
        raise "Vector rộng #{@width.round(1)} mm lớn hơn mặt CNC #{(face_w.to_f*25.4).round(1)} mm." if half_w*2 > face_w + 0.01.mm
        raise "Vector cao #{@height.round(1)} mm lớn hơn mặt CNC #{(face_h.to_f*25.4).round(1)} mm." if half_h*2 > face_h + 0.01.mm

        ox = @offset_x.mm
        oy = @offset_y.mm
        center_x = (min_x+max_x)/2.0
        center_y = (min_y+max_y)/2.0
        cx,cy,rx,ry = case @anchor
        when 'left'
          [min_x+half_w+ox,center_y+oy,min_x,center_y]
        when 'right'
          [max_x-half_w-ox,center_y+oy,max_x,center_y]
        when 'top'
          [center_x+ox,max_y-half_h-oy,center_x,max_y]
        when 'bottom'
          [center_x+ox,min_y+half_h+oy,center_x,min_y]
        when 'left_bottom'
          [min_x+half_w+ox,min_y+half_h+oy,min_x,min_y]
        when 'right_bottom'
          [max_x-half_w-ox,min_y+half_h+oy,max_x,min_y]
        when 'left_top'
          [min_x+half_w+ox,max_y-half_h-oy,min_x,max_y]
        when 'right_top'
          [max_x-half_w-ox,max_y-half_h-oy,max_x,max_y]
        else
          [center_x+ox,center_y+oy,center_x,center_y]
        end

        cx = [[cx,min_x+half_w].max,max_x-half_w].min
        cy = [[cy,min_y+half_h].max,max_y-half_h].min
        [Geom::Point3d.new(cx,cy,0),Geom::Point3d.new(rx,ry,0)]
      end

      def rebuild_preview
        return false unless @target_instance && @machining_face
        view = Sketchup.active_model.active_view
        geometry = face_geometry(@machining_face,@target_transform,view)
        @basis = geometry[:basis]
        center_local,reference_local = center_for_anchor(geometry)
        @center = center_local.transform(@basis)
        @face_boundary = geometry[:local].map { |point| Geom::Point3d.new(point.x,point.y,0).transform(@basis) }
        @target_box = target_box_points(@target_definition,@target_transform)

        points = VectorCNC.scaled_points(@template,@width,@height,@smoothness)
        @polygon_world = points.map do |px,py|
          Geom::Point3d.new(center_local.x+px.mm,center_local.y+py.mm,0).transform(@basis)
        end

        if @border_width > 0
          border_points = VectorCNC.scaled_points(
            @template,
            @width + @border_width*2.0,
            @height + @border_width*2.0,
            @smoothness
          )
          @border_polygon_world = border_points.map do |px,py|
            Geom::Point3d.new(center_local.x+px.mm,center_local.y+py.mm,0).transform(@basis)
          end
        else
          @border_polygon_world = []
        end

        ref_world = reference_local.transform(@basis)
        x_mid = Geom::Point3d.new(center_local.x,reference_local.y,0).transform(@basis)
        @guides = [
          [ref_world,x_mid,"X #{@offset_x.round(1)} mm"],
          [x_mid,@center,"Y #{@offset_y.round(1)} mm"]
        ]

        face_info = {
          'face_length'=>geometry[:width_mm].round(3),
          'face_width'=>geometry[:height_mm].round(3)
        }
        @target_info = VectorCNC.instance_dimensions(@target_instance,@target_transform).merge(face_info)
        VectorCNC.send_target_info(@target_info)
        @error = nil
        true
      rescue StandardError => e
        @polygon_world = []
        @border_polygon_world = []
        @guides = []
        @error = e.message
        false
      end

      def set_target(info,view)
        definition = info[:definition]
        if shared_definition?(definition)
          raise 'Component/Group đang dùng chung nhiều instance. Hãy Make Unique trước để tránh sửa nhầm.'
        end

        @target_instance = info[:instance]
        @target_definition = definition
        @target_transform = info[:transform]
        @target_path = Array(info[:path])
        @machining_face = choose_machining_face(definition,@target_transform,view)
        rebuild_preview
      end

      def update_hover(view,x,y)
        info = pick_target_instance(view,x,y)
        unless info
          @error = 'Rê vào Group hoặc Component để nhận khối.'
          return false
        end
        if @target_instance.equal?(info[:instance]) && @target_transform == info[:transform]
          return true
        end
        set_target(info,view)
      rescue StandardError => e
        @error = e.message
        false
      end

      def onMouseMove(_flags,x,y,view)
        update_hover(view,x,y)
        view.tooltip = @error || "#{@target_info && @target_info['name']} · #{@width.round(1)}×#{@height.round(1)} mm · #{@cut_mode}"
        Sketchup.status_text = @error || status_text
        view.invalidate
      end

      def onMouseWheel(_flags,delta,_x,_y,view)
        factor = delta.to_i > 0 ? 1.05 : 0.95
        @width = [@width*factor,0.1].max
        @height = [@height*factor,0.1].max
        @settings['width'] = @width
        @settings['height'] = @height
        rebuild_preview
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
        view.invalidate
        true
      end

      def onUserText(text,view)
        raw = text.to_s.strip.downcase.tr('×','x')
        nums = raw.scan(/[-+]?\d+(?:[\.,]\d+)?/).map { |value| value.tr(',','.').to_f }
        if nums.length >= 2
          @width,@height = nums[0],nums[1]
        elsif nums.length == 1
          ratio = @height/@width
          @width = nums[0]
          @height = @width*ratio
        else
          raise 'Nhập kích thước dạng 500x300.'
        end
        raise 'Kích thước phải lớn hơn 0.' unless @width > 0 && @height > 0
        @settings['width'],@settings['height'] = @width,@height
        rebuild_preview
        Sketchup.vcb_value = "#{@width.round(1)} x #{@height.round(1)}"
        view.invalidate
      rescue StandardError => e
        UI.messagebox(e.message)
      end

      def apply_selected
        view = Sketchup.active_model.active_view
        raise 'Hãy chọn một Group hoặc Component trước khi bấm ÁP DỤNG.' unless use_selected_target(view)
        raise(@error || 'Không tạo được preview trên khối đang chọn.') if @polygon_world.length < 3
        create_vector
      end

      def create_vector
        raise(@error || 'Chưa nhận Group/Component hợp lệ.') unless @target_instance && @target_definition && @machining_face && @polygon_world.length >= 3
        raise 'Component/Group đang dùng chung nhiều instance. Hãy Make Unique trước.' if shared_definition?(@target_definition)

        model = Sketchup.active_model
        model.start_operation('TT - VECTOR CNC',true)
        started = true
        parent_entities = @target_definition.entities
        group = parent_entities.add_group
        group.name = '_ABF_Intersect'
        tag_name = @template['name'].to_s.start_with?('ABF_') ? @template['name'] : VectorCNC.abf_name(@template['name'])
        tag = VectorCNC.ensure_tag(model,tag_name)
        group.layer = tag
        group.set_attribute('ABF','is-intersect',true)
        group.set_attribute('ABF','intersect-offset',0.0)
        group.set_attribute('ABF','setting-name',tag_name.sub(/\AABF_/,'').downcase.tr('_',' '))
        group.set_attribute('ABF','intersect-group-b-id',@machining_face.respond_to?(:persistent_id) ? @machining_face.persistent_id : @machining_face.object_id)
        group.set_attribute(KEY,'template',tag_name)
        group.set_attribute(KEY,'width_mm',@width)
        group.set_attribute(KEY,'height_mm',@height)
        group.set_attribute(KEY,'depth_mm',@depth)
        group.set_attribute(KEY,'border_width_mm',@border_width)
        group.set_attribute(KEY,'smoothness',@smoothness)
        group.set_attribute(KEY,'offset_x_mm',@offset_x)
        group.set_attribute(KEY,'offset_y_mm',@offset_y)
        group.set_attribute(KEY,'anchor',@anchor)
        group.set_attribute(KEY,'cut_mode',@cut_mode)
        if @target_info
          group.set_attribute(KEY,'target_length_mm',@target_info['length'])
          group.set_attribute(KEY,'target_width_mm',@target_info['width'])
          group.set_attribute(KEY,'target_thickness_mm',@target_info['thickness'])
        end

        inverse = @target_transform.inverse
        local_points = @polygon_world.map { |point| point.transform(inverse) }
        face = group.entities.add_face(local_points)
        raise 'Không tạo được Face vector kín.' unless face
        face.layer = tag
        face.edges.each { |edge| edge.layer = tag }
        @machining_face.set_attribute('ABF','is-cnced-face',true)

        model.commit_operation
        started = false
        model.selection.clear
        model.selection.add(@target_instance)
        group
      rescue StandardError
        model.abort_operation if started
        raise
      end

      def onLButtonDown(_flags,x,y,view)
        update_hover(view,x,y) unless @target_instance
        unless @target_instance && @polygon_world.length >= 3
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
        if @target_box.length == 8
          view.drawing_color = Sketchup::Color.new(60,120,220)
          view.line_width = 2
          view.draw(GL_LINES,BOX_EDGES.flat_map { |a,b| [@target_box[a],@target_box[b]] })
        end
        if @face_boundary.length > 2
          view.drawing_color = Sketchup::Color.new(255,130,0)
          view.line_width = 2
          view.draw(GL_LINE_LOOP,@face_boundary)
        end
        if @border_polygon_world.length > 2
          view.drawing_color = Sketchup::Color.new(210,150,80)
          view.line_width = 1
          view.line_stipple = '.' if view.respond_to?(:line_stipple=)
          view.draw(GL_LINE_LOOP,@border_polygon_world)
          view.line_stipple = '' if view.respond_to?(:line_stipple=)
        end
        if @polygon_world.length > 2
          view.drawing_color = Sketchup::Color.new(40,180,80)
          view.line_width = 3
          view.draw(GL_LINE_LOOP,@polygon_world)
          view.draw_points([@center],7,3,Sketchup::Color.new(255,100,0)) if @center
        end
        @guides.each do |a,b,label|
          view.drawing_color = Sketchup::Color.new(50,120,220)
          view.line_width = 1
          view.draw(GL_LINES,[a,b])
          view.draw_text(b,label,color: Sketchup::Color.new(50,100,190))
        end

        target = if @target_info
          "#{@target_info['name']} · #{@target_info['length']}×#{@target_info['width']}×#{@target_info['thickness']} mm"
        else
          'Chưa nhận khối'
        end
        text = @error || "#{target} · #{@template['name']} #{@width.round(1)}×#{@height.round(1)} · viền #{@border_width.round(1)} · mịn #{@smoothness} · CNC #{@depth.round(1)} mm · #{@cut_mode.upcase}"
        view.draw_text([20,35],text,color: Sketchup::Color.new(145,75,20))
      end

      def getExtents
        box = Geom::BoundingBox.new
        @target_box.each { |point| box.add(point) }
        @face_boundary.each { |point| box.add(point) }
        @polygon_world.each { |point| box.add(point) }
        @border_polygon_world.each { |point| box.add(point) }
        box
      end

      def onCancel(_reason,_view)
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
