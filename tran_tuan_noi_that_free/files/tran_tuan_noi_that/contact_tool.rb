# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'

module TranTuanNoiThat
  module ContactTool
    extend self

    VERSION = '1.0.1'.freeze
    KEY = 'TT_TIEP_DIEN'.freeze
    DATA_DIR = File.join(TranTuanNoiThat::ROOT, 'data', 'contact_tool').freeze
    PRESET_FILE = File.join(DATA_DIR, 'presets.json').freeze
    DEFAULT_PRESET = 'Tiếp diện chữ nhật'.freeze
    KEY_LEFT = 37
    KEY_UP = 38
    KEY_RIGHT = 39
    KEY_DOWN = 40
    KEY_SHIFT = 16
    KEY_TAB = 9

    DEFAULTS = {
      'width'=>80.0,
      'height'=>40.0,
      'radius'=>0.0,
      'corner_mode'=>'all',
      'instance_name'=>'ABF_TIEP_DIEN',
      'tag_name'=>'ABF_TIEP_DIEN',
      'template'=>{'kind'=>'rect','points'=>[]}
    }.freeze

    def number(value, fallback = 0.0)
      Float(value)
    rescue ArgumentError, TypeError
      fallback.to_f
    end

    def abf_name(value, fallback = 'TIEP_DIEN')
      text = value.to_s.strip
      begin
        text = text.unicode_normalize(:nfkd).encode('ASCII', invalid: :replace, undef: :replace, replace: '')
      rescue StandardError
        nil
      end
      text = text.upcase.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
      text = fallback if text.empty?
      text = "ABF_#{text}" unless text.start_with?('ABF_')
      text[0,64]
    end

    def normalize_points(points)
      rows = Array(points).map { |p| [Float(p[0]),Float(p[1])] }
      raise 'Biên dạng cần ít nhất 3 điểm.' if rows.length < 3
      rows.pop if rows.length > 3 && rows.first == rows.last
      raise 'Biên dạng cần ít nhất 3 điểm khác nhau.' if rows.uniq.length < 3
      min_x,max_x = rows.map(&:first).minmax
      min_y,max_y = rows.map(&:last).minmax
      width = max_x-min_x
      height = max_y-min_y
      raise 'Biên dạng có kích thước bằng 0.' if width.abs < 1.0e-9 || height.abs < 1.0e-9
      cx = (min_x+max_x)/2.0
      cy = (min_y+max_y)/2.0
      rows.map { |x,y| [(x-cx)/(width/2.0),(y-cy)/(height/2.0)] }
    end

    def validate(raw)
      source = DEFAULTS.merge((raw || {}).transform_keys(&:to_s))
      width = number(source['width'])
      height = number(source['height'])
      radius = [number(source['radius']),0.0].max
      raise 'Dài biên dạng phải > 0 mm.' unless width > 0
      raise 'Rộng biên dạng phải > 0 mm.' unless height > 0
      radius = [radius,width/2.0,height/2.0].min
      mode = source['corner_mode'].to_s
      mode = 'all' unless %w[none all top bottom].include?(mode)
      template = source['template'].is_a?(Hash) ? source['template'] : {}
      kind = template['kind'].to_s == 'custom' ? 'custom' : 'rect'
      points = kind == 'custom' ? normalize_points(template['points']) : []
      {
        'width'=>width,
        'height'=>height,
        'radius'=>radius,
        'corner_mode'=>mode,
        'instance_name'=>abf_name(source['instance_name']),
        'tag_name'=>abf_name(source['tag_name']),
        'template'=>{'kind'=>kind,'points'=>points}
      }
    end

    def default_presets
      { DEFAULT_PRESET => validate(DEFAULTS) }
    end

    def presets
      FileUtils.mkdir_p(DATA_DIR)
      if File.file?(PRESET_FILE)
        parsed = JSON.parse(File.read(PRESET_FILE, encoding: 'UTF-8'))
        return parsed if parsed.is_a?(Hash) && !parsed.empty?
      end
      save_presets(default_presets)
    rescue StandardError => error
      puts "[TT Contact presets] #{error.class}: #{error.message}"
      default_presets
    end

    def save_presets(data)
      FileUtils.mkdir_p(DATA_DIR)
      clean = data.is_a?(Hash) && !data.empty? ? data : default_presets
      temp = PRESET_FILE + '.tmp'
      File.write(temp, JSON.pretty_generate(clean), encoding: 'UTF-8')
      FileUtils.mv(temp, PRESET_FILE)
      clean
    rescue StandardError => error
      FileUtils.rm_f(temp) if defined?(temp) && temp
      raise "Không lưu được thư viện tiếp diện: #{error.message}"
    end

    def selected_preset
      rows = presets
      @selected_preset = DEFAULT_PRESET if @selected_preset.to_s.empty? && rows.key?(DEFAULT_PRESET)
      @selected_preset = rows.keys.first unless rows.key?(@selected_preset)
      @selected_preset
    end

    def current_options
      @options ||= validate(presets[selected_preset] || DEFAULTS)
    end

    def save_preset(name, raw)
      preset_name = name.to_s.strip
      raise 'Hãy nhập tên biên dạng.' if preset_name.empty?
      raise 'Tên biên dạng tối đa 60 ký tự.' if preset_name.length > 60
      rows = presets
      rows[preset_name] = validate(raw)
      save_presets(rows)
      @selected_preset = preset_name
      @options = rows[preset_name].dup
      @active_tool.update_options(@options) if @active_tool
      @options
    end

    def delete_preset(name)
      rows = presets
      rows.delete(name.to_s)
      rows = default_presets if rows.empty?
      save_presets(rows)
      @selected_preset = rows.key?(DEFAULT_PRESET) ? DEFAULT_PRESET : rows.keys.first
      @options = validate(rows[@selected_preset])
      @active_tool.update_options(@options) if @active_tool
      @options
    end

    def arc_points(cx,cy,r,a0,a1,segments)
      count = [segments.to_i,1].max
      (0..count).map do |i|
        t = i.to_f/count
        a = (a0+(a1-a0)*t)*Math::PI/180.0
        [cx+Math.cos(a)*r,cy+Math.sin(a)*r]
      end
    end

    def append_unique(target, points)
      points.each do |point|
        next if target.last && (target.last[0]-point[0]).abs < 1.0e-9 && (target.last[1]-point[1]).abs < 1.0e-9
        target << point
      end
      target
    end

    def rounded_rect_points(width,height,radius,mode = 'all',segments = 5)
      w = width.to_f
      h = height.to_f
      r = [[radius.to_f,0.0].max,w/2.0,h/2.0].min
      hx = w/2.0
      hy = h/2.0
      top = %w[all top].include?(mode.to_s) && r > 0
      bottom = %w[all bottom].include?(mode.to_s) && r > 0
      points = []

      if bottom
        append_unique(points,arc_points(hx-r,-hy+r,r,-90,0,segments))
      else
        points << [hx,-hy]
      end
      if top
        append_unique(points,arc_points(hx-r,hy-r,r,0,90,segments))
        append_unique(points,arc_points(-hx+r,hy-r,r,90,180,segments))
      else
        points << [hx,hy]
        points << [-hx,hy]
      end
      if bottom
        append_unique(points,arc_points(-hx+r,-hy+r,r,180,270,segments))
      else
        points << [-hx,-hy]
      end
      points
    end

    def shape_points_mm(options)
      opts = validate(options)
      template = opts['template']
      if template['kind'] == 'custom'
        sx = opts['width']/2.0
        sy = opts['height']/2.0
        template['points'].map { |x,y| [x*sx,y*sy] }
      else
        rounded_rect_points(opts['width'],opts['height'],opts['radius'],opts['corner_mode'],5)
      end
    end

    def vector_length(vector)
      Math.sqrt(vector.x.to_f**2 + vector.y.to_f**2 + vector.z.to_f**2)
    end

    def normalized(vector)
      length = vector_length(vector)
      raise 'Vector bằng 0.' if length < 1.0e-10
      Geom::Vector3d.new(vector.x/length,vector.y/length,vector.z/length)
    end

    def dot(a,b)
      a.x*b.x + a.y*b.y + a.z*b.z
    end

    def cross(a,b)
      Geom::Vector3d.new(
        a.y*b.z-a.z*b.y,
        a.z*b.x-a.x*b.z,
        a.x*b.y-a.y*b.x
      )
    end

    def face_basis(points)
      raise 'Face cần ít nhất 3 điểm.' unless points && points.length >= 3
      origin = points.first
      edges = []
      points.each_with_index do |p,index|
        q = points[(index+1)%points.length]
        vec = p.vector_to(q)
        edges << vec if vector_length(vec) > 1.0e-8
      end
      raise 'Không xác định được cạnh Face.' if edges.empty?
      xaxis = normalized(edges.max_by { |v| vector_length(v) })
      normal = nil
      points.drop(2).each do |point|
        candidate = cross(points[0].vector_to(points[1]),points[0].vector_to(point))
        if vector_length(candidate) > 1.0e-8
          normal = normalized(candidate)
          break
        end
      end
      raise 'Không xác định được pháp tuyến Face.' unless normal
      yaxis = normalized(cross(normal,xaxis))
      [origin,xaxis,yaxis,normal]
    end

    def point_in_polygon?(point, polygon)
      x,y = point
      inside = false
      j = polygon.length-1
      polygon.each_with_index do |pi,i|
        pj = polygon[j]
        yi = pi[1]; yj = pj[1]
        if ((yi > y) != (yj > y))
          cross_x = (pj[0]-pi[0])*(y-yi)/(yj-yi).to_f + pi[0]
          inside = !inside if x < cross_x
        end
        j = i
      end
      inside
    end

    def contact_plan(face_points,cursor,raw_options,rotation_deg = 0)
      opts = validate(raw_options)
      origin,xaxis,yaxis,normal = face_basis(face_points)
      rad = rotation_deg.to_f*Math::PI/180.0
      rx = Geom::Vector3d.new(
        xaxis.x*Math.cos(rad)+yaxis.x*Math.sin(rad),
        xaxis.y*Math.cos(rad)+yaxis.y*Math.sin(rad),
        xaxis.z*Math.cos(rad)+yaxis.z*Math.sin(rad)
      )
      ry = Geom::Vector3d.new(
        -xaxis.x*Math.sin(rad)+yaxis.x*Math.cos(rad),
        -xaxis.y*Math.sin(rad)+yaxis.y*Math.cos(rad),
        -xaxis.z*Math.sin(rad)+yaxis.z*Math.cos(rad)
      )

      world = shape_points_mm(opts).map do |x_mm,y_mm|
        Geom::Point3d.new(
          cursor.x + rx.x*x_mm.mm + ry.x*y_mm.mm,
          cursor.y + rx.y*x_mm.mm + ry.y*y_mm.mm,
          cursor.z + rx.z*x_mm.mm + ry.z*y_mm.mm
        )
      end
      face_2d = face_points.map do |point|
        delta = origin.vector_to(point)
        [dot(delta,xaxis),dot(delta,yaxis)]
      end
      shape_2d = world.map do |point|
        delta = origin.vector_to(point)
        [dot(delta,xaxis),dot(delta,yaxis)]
      end
      valid = shape_2d.all? { |point| point_in_polygon?(point,face_2d) }
      {
        options: opts,
        points: world,
        normal: normal,
        rotation_deg: rotation_deg.to_f % 360.0,
        valid: valid,
        face_length_mm: (face_2d.map(&:first).max-face_2d.map(&:first).min)*25.4,
        face_width_mm: (face_2d.map(&:last).max-face_2d.map(&:last).min)*25.4
      }
    end

    def valid_container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def target_entities(entity)
      entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
    end

    def make_unique(target)
      return target unless target.is_a?(Sketchup::ComponentInstance)
      if target.definition.respond_to?(:instances) && target.definition.instances.length > 1
        target.make_unique
      end
      target
    end

    def ensure_tag(model,name)
      model.layers[name] || model.layers.add(name)
    end

    def entity_reference_id(entity)
      entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
    rescue StandardError
      entity.object_id
    end

    def create_contact(target,world_transform,plan)
      raise 'Biên dạng đang vượt khỏi Face.' unless plan[:valid]
      model = Sketchup.active_model
      model.start_operation('TT - TẠO TIẾP DIỆN',true)
      started = true

      make_unique(target)
      entities = target_entities(target)
      inverse = world_transform.inverse
      local_points = plan[:points].map { |point| point.transform(inverse) }
      opts = plan[:options]
      tag = ensure_tag(model,opts['tag_name'])
      edges = []

      local_points.each_with_index do |point,index|
        nxt = local_points[(index+1)%local_points.length]
        edge = entities.add_line(point,nxt)
        raise "Không tạo được cạnh tiếp diện số #{index+1}." unless edge && edge.valid?
        edge.layer = tag
        edge.set_attribute('ABF','is-intersect',true)
        edge.set_attribute('ABF','instance',opts['instance_name'])
        edge.set_attribute('ABF','instance-name',opts['instance_name'])
        edge.set_attribute('ABF','tag-name',opts['tag_name'])
        edge.set_attribute('ABF','setting-name',opts['instance_name'].sub(/\AABF_/,'').downcase.tr('_',' '))
        edge.set_attribute('ABF','intersect-group-b-id',entity_reference_id(target))
        edge.set_attribute(KEY,'role','contact_edge')
        edge.set_attribute(KEY,'closed_profile',true)
        edge.set_attribute(KEY,'rotation_deg',plan[:rotation_deg])
        edges << edge
      end

      target.set_attribute('ABF','is-board',true)
      target.set_attribute('ABF','has-contact-profile',true)
      target.set_attribute(KEY,'last_instance',opts['instance_name'])
      target.set_attribute(KEY,'last_tag',opts['tag_name'])

      model.commit_operation
      started = false
      edges
    rescue StandardError
      model.abort_operation if started
      raise
    end

    def selection_template
      model = Sketchup.active_model
      selection = model.selection.to_a
      face = selection.find { |entity| entity.is_a?(Sketchup::Face) }
      points3d = nil
      if face
        points3d = face.outer_loop.vertices.map(&:position)
      else
        edges = selection.grep(Sketchup::Edge)
        raise 'Hãy chọn 1 Face hoặc một chuỗi Edge kín.' if edges.empty?
        points3d = ordered_edge_loop(edges)
      end
      raise 'Biên dạng SketchUp cần ít nhất 3 điểm.' unless points3d && points3d.length >= 3
      origin,xaxis,yaxis,_normal = face_basis(points3d)
      coords = points3d.map do |point|
        delta = origin.vector_to(point)
        [dot(delta,xaxis),dot(delta,yaxis)]
      end
      min_x,max_x = coords.map(&:first).minmax
      min_y,max_y = coords.map(&:last).minmax
      {
        'points'=>normalize_points(coords),
        'width'=>(max_x-min_x)*25.4,
        'height'=>(max_y-min_y)*25.4
      }
    end

    def ordered_edge_loop(edges)
      remaining = edges.dup
      first = remaining.shift
      result = [first.start.position,first.end.position]
      current = first.end
      guard = 0
      until remaining.empty? || guard > edges.length+2
        guard += 1
        index = remaining.index { |edge| edge.start.equal?(current) || edge.end.equal?(current) }
        raise 'Các Edge được chọn chưa tạo thành chuỗi kín liên tục.' unless index
        edge = remaining.delete_at(index)
        current = edge.start.equal?(current) ? edge.end : edge.start
        result << current.position
      end
      raise 'Chuỗi Edge chưa kín.' unless current.equal?(first.start)
      result.pop
      result
    end

    def dialog_alive?
      @dialog && @dialog_version == VERSION
    rescue StandardError
      false
    end

    def show
      unless dialog_alive?
        begin
          @dialog.close if @dialog
        rescue StandardError
          nil
        end
        @dialog = build_dialog
        @dialog_version = VERSION
      end
      @dialog.show
      send_state
      activate
    rescue StandardError => error
      UI.messagebox("TẠO TIẾP DIỆN: #{error.message}")
    end

    def activate
      @active_tool = Tool.new(current_options)
      Sketchup.active_model.select_tool(@active_tool)
    end

    def update_active(raw)
      @options = validate(raw)
      @active_tool.update_options(@options) if @active_tool
      @options
    end

    def send_state
      return unless @dialog
      @dialog.execute_script("setContactState(#{JSON.generate({
        presets: presets,
        selected: selected_preset,
        options: current_options
      })})")
    rescue StandardError => error
      puts "[TT Contact send_state] #{error.class}: #{error.message}"
    end

    def push_hover(info)
      return unless @dialog
      @dialog.execute_script("setContactHover(#{JSON.generate(info || {})})")
    rescue StandardError
      nil
    end

    def build_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title:'TẠO TIẾP DIỆN',
        preferences_key:'TT_TIEP_DIEN',
        scrollable:true,resizable:true,width:820,height:690,
        style:UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_html(dialog_html)
      dialog.set_on_closed do
        @dialog = nil
        @dialog_version = nil
      end
      dialog.add_action_callback('ready') { send_state }
      dialog.add_action_callback('update') do |_ctx,json|
        update_active(JSON.parse(json.to_s))
      rescue StandardError => error
        UI.messagebox(error.message)
      end
      dialog.add_action_callback('select_preset') do |_ctx,name|
        rows = presets
        raise 'Không tìm thấy mẫu tiếp diện.' unless rows[name.to_s]
        @selected_preset = name.to_s
        @options = validate(rows[@selected_preset])
        @active_tool.update_options(@options) if @active_tool
        send_state
      rescue StandardError => error
        UI.messagebox(error.message)
      end
      dialog.add_action_callback('save_preset') do |_ctx,name,json|
        save_preset(name,JSON.parse(json.to_s))
        send_state
      rescue StandardError => error
        UI.messagebox(error.message)
      end
      dialog.add_action_callback('delete_preset') do |_ctx,name|
        delete_preset(name)
        send_state
      rescue StandardError => error
        UI.messagebox(error.message)
      end
      dialog.add_action_callback('import_selection') do
        info = selection_template
        @dialog.execute_script("setImportedContactShape(#{JSON.generate(info)})")
      rescue StandardError => error
        UI.messagebox("NHẬP BIÊN DẠNG: #{error.message}")
      end
      dialog.add_action_callback('activate') { activate }
      dialog
    end

    def dialog_html
      <<~HTML
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{margin:0;font:13px Arial;background:#eef9f1;color:#234633}
      header{padding:13px 16px;background:#2f8f5b;color:#fff;font-size:18px;font-weight:bold}
      .layout{display:grid;grid-template-columns:245px 1fr;gap:12px;padding:12px}
      .panel{background:#dff4e7;border:1px solid #abd7ba;border-radius:9px;padding:11px}
      .title{font-weight:bold;color:#246b43;margin-bottom:8px}.library{height:485px;overflow:auto}
      .preset{width:100%;padding:9px;margin:3px 0;text-align:left;border:1px solid #a7cfb5;border-radius:6px;background:#f6fff8;cursor:pointer}
      .preset.active{background:#bfeccc;border-color:#57ad75;font-weight:bold}
      .grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.full{grid-column:1/-1}
      label{font-weight:bold}input,select{width:100%;padding:7px;margin-top:3px;border:1px solid #9bc8aa;border-radius:6px;background:#fff}
      button{padding:8px 10px;border:0;border-radius:6px;font-weight:bold;cursor:pointer}.primary{background:#2f8f5b;color:#fff}.dark{background:#526f5c;color:#fff}.danger{background:#b44747;color:#fff}
      .buttons{display:flex;gap:7px;flex-wrap:wrap;margin-top:8px}canvas{width:100%;height:200px;background:#fff;border:1px solid #9bc8aa;border-radius:7px}
      .hint{font-size:12px;color:#52705e;line-height:1.45}.hover{margin-top:8px;padding:8px;background:#f7fff9;border:1px dashed #7fbd94;border-radius:7px}
      @media(max-width:720px){.layout{grid-template-columns:1fr}.library{height:180px}}
      </style></head><body>
      <header>TẠO TIẾP DIỆN · AUTO FACE · ABF_...</header>
      <div class="layout">
        <div class="panel">
          <div class="title">THƯ VIỆN BIÊN DẠNG</div>
          <div id="library" class="library"></div>
          <div class="buttons"><button class="primary" onclick="newPreset()">TẠO MỚI</button><button class="danger" onclick="deletePreset()">XÓA MẪU</button></div>
          <div class="hint">TAB mở lại bảng. Chọn mẫu là preview trên model cập nhật ngay.</div>
        </div>
        <div class="panel">
          <div class="title">THÔNG SỐ TIẾP DIỆN</div>
          <div class="grid">
            <label class="full">Tên mẫu<input id="presetName"></label>
            <label>INSTANCE<input id="instance_name"></label>
            <label>Tag<input id="tag_name"></label>
            <label>Dài (mm)<input id="width" type="number" min="0.1" step="0.1"></label>
            <label>Rộng (mm)<input id="height" type="number" min="0.1" step="0.1"></label>
            <label>Bán kính bo góc (mm)<input id="radius" type="number" min="0" step="0.1"></label>
            <label>Kiểu bo góc<select id="corner_mode"><option value="none">Không bo</option><option value="all">Bo 4 góc</option><option value="top">Bo 2 góc trên</option><option value="bottom">Bo 2 góc dưới</option></select></label>
          </div>

          <div class="title" style="margin-top:10px">MÔ PHỎNG / VẼ BIÊN DẠNG</div>
          <canvas id="shapeCanvas" width="520" height="200"></canvas>
          <div class="buttons">
            <button class="dark" onclick="useRectangle()">HCN / BO GÓC</button>
            <button class="dark" onclick="startDraw()">VẼ TRỰC TIẾP</button>
            <button class="dark" onclick="clearDraw()">XÓA NÉT VẼ</button>
            <button class="primary" onclick="sketchup.import_selection()">LẤY TỪ SKETCHUP</button>
          </div>
          <div class="hint">Vẽ trực tiếp: bấm các điểm trên khung preview; khi đủ ≥3 điểm bấm LƯU MẪU. Hoặc chọn Face/chuỗi Edge kín trong SketchUp rồi bấm LẤY TỪ SKETCHUP.</div>

          <div class="buttons">
            <button class="primary" onclick="savePreset()">LƯU MẪU</button>
            <button class="primary" onclick="applyNow()">CẬP NHẬT PREVIEW</button>
            <button class="dark" onclick="sketchup.activate()">BẬT LẠI AUTO</button>
          </div>
          <div class="hover">
            <b>AUTO:</b> <span id="target">Rà chuột vào Face của Group/Component.</span><br>
            <span id="faceDims"></span><br>
            <span id="rotationText">Hướng 0°</span>
          </div>
          <div class="hint" style="margin-top:8px"><b>Phím:</b> ← ↑ → ↓ chọn hướng · SHIFT xoay 90° · TAB mở thư viện/cài đặt · Click tạo tiếp diện và tiếp tục chạy.</div>
        </div>
      </div>
      <script>
      let state={presets:{},selected:null},template={kind:'rect',points:[]},drawing=false,drawPoints=[];
      const canvas=document.getElementById('shapeCanvas'),ctx=canvas.getContext('2d');
      function opts(){return {width:+width.value,height:+height.value,radius:+radius.value,corner_mode:corner_mode.value,instance_name:instance_name.value,tag_name:tag_name.value,template:template}}
      function abfName(s){s=(s||'TIEP_DIEN').toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^A-Z0-9]+/g,'_').replace(/^_+|_+$/g,'');return s.startsWith('ABF_')?s:'ABF_'+s}
      function fill(o){width.value=o.width;height.value=o.height;radius.value=o.radius;corner_mode.value=o.corner_mode;instance_name.value=o.instance_name;tag_name.value=o.tag_name;template=o.template||{kind:'rect',points:[]};drawShape()}
      function renderLibrary(){library.innerHTML='';Object.keys(state.presets).forEach(name=>{let b=document.createElement('button');b.className='preset'+(name===state.selected?' active':'');b.textContent=name;b.onclick=()=>sketchup.select_preset(name);library.appendChild(b)})}
      window.setContactState=d=>{state=d;renderLibrary();presetName.value=d.selected||'';if(d.options)fill(d.options)}
      window.setContactHover=d=>{target.textContent=d.target?('Đối tượng: '+d.target+(d.valid?'':' · BIÊN DẠNG VƯỢT MẶT')):'Rà chuột vào Face của Group/Component.';faceDims.textContent=d.face_length_mm?('Face: '+d.face_length_mm.toFixed(1)+' × '+d.face_width_mm.toFixed(1)+' mm'):'';rotationText.textContent='Hướng '+(d.rotation_deg||0)+'°'}
      window.setImportedContactShape=info=>{template={kind:'custom',points:info.points};width.value=info.width.toFixed(1);height.value=info.height.toFixed(1);drawPoints=[];drawing=false;drawShape();applyNow()}
      function newPreset(){presetName.value='Tiếp diện mới';instance_name.value='ABF_TIEP_DIEN_MOI';tag_name.value='ABF_TIEP_DIEN_MOI';useRectangle();applyNow()}
      function useRectangle(){template={kind:'rect',points:[]};drawing=false;drawPoints=[];drawShape();applyNow()}
      function startDraw(){template={kind:'custom',points:[]};drawing=true;drawPoints=[];drawShape()}
      function clearDraw(){drawPoints=[];template={kind:'custom',points:[]};drawShape()}
      function normalizeDraw(){if(drawPoints.length<3)return [];let xs=drawPoints.map(p=>p[0]),ys=drawPoints.map(p=>p[1]),minX=Math.min(...xs),maxX=Math.max(...xs),minY=Math.min(...ys),maxY=Math.max(...ys),cx=(minX+maxX)/2,cy=(minY+maxY)/2;return drawPoints.map(p=>[(p[0]-cx)/Math.max(1,(maxX-minX)/2),(cy-p[1])/Math.max(1,(maxY-minY)/2)])}
      canvas.addEventListener('click',e=>{if(!drawing)return;let r=canvas.getBoundingClientRect(),x=(e.clientX-r.left)*canvas.width/r.width,y=(e.clientY-r.top)*canvas.height/r.height;drawPoints.push([x,y]);template={kind:'custom',points:normalizeDraw()};drawShape();applyNow()})
      function roundedPoints(){let W=+width.value,H=+height.value,R=Math.max(0,Math.min(+radius.value,W/2,H/2)),mode=corner_mode.value,hx=W/2,hy=H/2,out=[];function arc(cx,cy,a0,a1){for(let i=0;i<=5;i++){let a=(a0+(a1-a0)*i/5)*Math.PI/180;out.push([cx+Math.cos(a)*R,cy+Math.sin(a)*R])}}let top=(mode==='all'||mode==='top')&&R>0,bottom=(mode==='all'||mode==='bottom')&&R>0;if(bottom)arc(hx-R,-hy+R,-90,0);else out.push([hx,-hy]);if(top){arc(hx-R,hy-R,0,90);arc(-hx+R,hy-R,90,180)}else out.push([hx,hy],[-hx,hy]);if(bottom)arc(-hx+R,-hy+R,180,270);else out.push([-hx,-hy]);return out}
      function drawShape(){ctx.clearRect(0,0,canvas.width,canvas.height);ctx.strokeStyle='#d7eadf';for(let x=20;x<canvas.width;x+=20){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,canvas.height);ctx.stroke()}for(let y=20;y<canvas.height;y+=20){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(canvas.width,y);ctx.stroke()}let pts;if(template.kind==='custom'&&template.points.length>=3)pts=template.points.map(p=>[canvas.width/2+p[0]*canvas.width*.38,canvas.height/2-p[1]*canvas.height*.38]);else{let raw=roundedPoints(),W=Math.max(1,+width.value),H=Math.max(1,+height.value),sc=Math.min(canvas.width*.75/W,canvas.height*.75/H);pts=raw.map(p=>[canvas.width/2+p[0]*sc,canvas.height/2-p[1]*sc])}if(!pts.length)return;ctx.beginPath();pts.forEach((p,i)=>i?ctx.lineTo(p[0],p[1]):ctx.moveTo(p[0],p[1]));ctx.closePath();ctx.fillStyle='rgba(47,143,91,.12)';ctx.fill();ctx.strokeStyle='#2f8f5b';ctx.lineWidth=2;ctx.stroke();if(drawing){ctx.fillStyle='#176b42';drawPoints.forEach(p=>{ctx.beginPath();ctx.arc(p[0],p[1],3,0,Math.PI*2);ctx.fill()})}}
      function applyNow(){if(template.kind==='custom'&&drawPoints.length>=3)template.points=normalizeDraw();sketchup.update(JSON.stringify(opts()));drawShape()}
      function savePreset(){if(template.kind==='custom'&&drawPoints.length>=3)template.points=normalizeDraw();sketchup.save_preset(presetName.value,JSON.stringify(opts()))}
      function deletePreset(){if(state.selected&&confirm('Xóa mẫu '+state.selected+'?'))sketchup.delete_preset(state.selected)}
      ['width','height','radius','corner_mode','instance_name','tag_name'].forEach(id=>{document.getElementById(id).addEventListener('input',applyNow);document.getElementById(id).addEventListener('change',applyNow)})
      presetName.addEventListener('input',()=>{if(document.activeElement===presetName){instance_name.value=abfName(presetName.value);tag_name.value=abfName(presetName.value);applyNow()}})
      document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      </script></body></html>
      HTML
    end

    class Tool
      def initialize(options)
        @options = ContactTool.validate(options)
        @candidate = nil
        @plan = nil
        @rotation_deg = 0
        @shift_down = false
      end

      def activate
        Sketchup.set_status_text('TẠO TIẾP DIỆN · AUTO FACE | Rê trực tiếp lên Face trong Group/Component · preview bám mặt · Click tạo',SB_PROMPT)
      end

      def deactivate(view)
        ContactTool.instance_variable_set(:@active_tool,nil) if ContactTool.instance_variable_get(:@active_tool).equal?(self)
        ContactTool.push_hover(nil)
        view.invalidate if view
      end

      def update_options(options)
        @options = ContactTool.validate(options)
        rebuild
        @view.invalidate if @view
      rescue StandardError => error
        puts "[TT Contact update] #{error.class}: #{error.message}"
      end

      def onMouseMove(_flags,x,y,view)
        @view = view
        @candidate = pick_candidate(view,x,y)
        rebuild
        view.tooltip = @candidate ? (@plan && @plan[:valid] ? 'ĐÃ NHẬN FACE · Click tạo tiếp diện' : 'ĐÃ NHẬN FACE · Biên dạng vượt khỏi mặt') : 'Rê chuột trực tiếp lên Face của Group/Component'
        view.invalidate
      rescue StandardError => error
        @candidate = nil
        @plan = nil
        puts "[TT Contact hover] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags,x,y,view)
        @view = view
        @candidate = pick_candidate(view,x,y)
        rebuild
        unless @candidate && @plan && @plan[:valid]
          UI.beep
          return
        end
        ContactTool.create_contact(@candidate[:target],@candidate[:transform],@plan)
        Sketchup.set_status_text("Đã tạo #{@plan[:options]['instance_name']} · tiếp tục rà để tạo tiếp",SB_PROMPT)
        @candidate = nil
        @plan = nil
        view.invalidate
      rescue StandardError => error
        UI.messagebox("TẠO TIẾP DIỆN: #{error.message}")
      end

      def onKeyDown(key,repeat,_flags,view)
        if key == KEY_TAB
          ContactTool.show
          return true
        end
        if key == KEY_SHIFT
          return true if @shift_down || repeat.to_i > 1
          @shift_down = true
          @rotation_deg = (@rotation_deg+90)%360
          rebuild
          view.invalidate
          return true
        end
        case key
        when KEY_RIGHT then @rotation_deg = 0
        when KEY_UP then @rotation_deg = 90
        when KEY_LEFT then @rotation_deg = 180
        when KEY_DOWN then @rotation_deg = 270
        else return false
        end
        rebuild
        view.invalidate
        true
      end

      def onKeyUp(key,_repeat,_flags,_view)
        @shift_down = false if key == KEY_SHIFT
      end

      def onCancel(_reason,view)
        @candidate = nil
        @plan = nil
        ContactTool.push_hover(nil)
        view.invalidate if view
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        return unless @candidate && @plan

        n = ContactTool.normalized(@plan[:normal])

        # Viền xanh/cam của chính Face đang AUTO nhận diện.
        face_outline = @candidate[:points].map do |point|
          Geom::Point3d.new(
            point.x + n.x * 0.15.mm,
            point.y + n.y * 0.15.mm,
            point.z + n.z * 0.15.mm
          )
        end
        if face_outline.length >= 3
          view.drawing_color = Sketchup::Color.new(70,145,235)
          view.line_width = 2
          view.draw(GL_LINE_LOOP, face_outline)
        end

        # Biên tiếp diện preview: xanh khi nằm trọn trên Face, đỏ khi vượt Face.
        view.drawing_color = @plan[:valid] ? Sketchup::Color.new(58,190,112) : Sketchup::Color.new(220,70,70)
        view.line_width = 4
        points = @plan[:points].map do |point|
          Geom::Point3d.new(
            point.x + n.x * 0.30.mm,
            point.y + n.y * 0.30.mm,
            point.z + n.z * 0.30.mm
          )
        end
        lines = []
        points.each_with_index { |point,index| lines.concat([point,points[(index+1)%points.length]]) }
        view.draw(GL_LINES,lines)
      end

      private

      def current_edit_transform
        model = Sketchup.active_model
        transform = model.respond_to?(:edit_transform) ? model.edit_transform : nil
        transform || Geom::Transformation.new
      rescue StandardError
        Geom::Transformation.new
      end

      def path_entities(path)
        return [] unless path
        path.respond_to?(:to_a) ? path.to_a : Array(path)
      rescue StandardError
        []
      end

      # Tính transform từ local của Face/target ra world bằng chính instance path.
      # Không dùng face.parent để nhận chủ Face vì cách đó dễ rớt ở Group/Component lồng nhau.
      def target_and_transform_from_path(path)
        rows = path_entities(path)
        containers = rows.select { |entity| ContactTool.valid_container?(entity) }

        model = Sketchup.active_model
        if containers.empty?
          active_path = model.respond_to?(:active_path) ? model.active_path : nil
          active_target = Array(active_path).last
          if active_target && ContactTool.valid_container?(active_target)
            return [active_target, current_edit_transform]
          end
          return nil
        end

        target = containers.last
        transform = current_edit_transform

        # path_at() là path tương đối với active edit context.
        # Nhân lần lượt đến container sâu nhất chứa Face.
        rows.each do |entity|
          if ContactTool.valid_container?(entity)
            transform = transform * entity.transformation
            break if entity.equal?(target)
          end
        end

        [target, transform]
      rescue StandardError => error
        puts "[TT Contact path] #{error.class}: #{error.message}"
        nil
      end

      def candidate_from_path(view,x,y,helper,index,path)
        rows = path_entities(path)
        return nil if rows.empty?

        face = rows.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
        return nil unless face && face.valid?

        resolved = target_and_transform_from_path(rows)
        return nil unless resolved
        target, transform = resolved
        return nil unless target && target.valid?

        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
        return nil if points.length < 3

        _origin,_x,_y,normal = ContactTool.face_basis(points)
        cursor = Geom.intersect_line_plane(view.pickray(x,y),[points[0],normal])
        return nil unless cursor

        # Nếu cursor không nằm trên polygon Face thì tiếp tục thử hit kế tiếp.
        origin,xaxis,yaxis,_n = ContactTool.face_basis(points)
        polygon_2d = points.map do |point|
          delta = origin.vector_to(point)
          [ContactTool.dot(delta,xaxis),ContactTool.dot(delta,yaxis)]
        end
        delta = origin.vector_to(cursor)
        cursor_2d = [ContactTool.dot(delta,xaxis),ContactTool.dot(delta,yaxis)]
        return nil unless ContactTool.point_in_polygon?(cursor_2d,polygon_2d)

        {
          target:target,
          face:face,
          transform:transform,
          points:points,
          cursor:cursor,
          pick_index:index
        }
      rescue StandardError => error
        puts "[TT Contact candidate] #{error.class}: #{error.message}"
        nil
      end

      def pick_candidate(view,x,y)
        helper = view.pick_helper
        picked_count = helper.do_pick(x,y).to_i
        helper_count = helper.respond_to?(:count) ? helper.count.to_i : 0
        count = [picked_count,helper_count,1].max

        count.times do |index|
          path = helper.path_at(index)
          candidate = candidate_from_path(view,x,y,helper,index,path)
          return candidate if candidate
        end

        # Fallback khi đang edit trực tiếp Group/Component và PickHelper chỉ trả Face.
        best = helper.respond_to?(:best_picked) ? helper.best_picked : nil
        if best.is_a?(Sketchup::Face)
          candidate = candidate_from_path(view,x,y,helper,0,[best])
          return candidate if candidate
        end

        nil
      rescue StandardError => error
        puts "[TT Contact auto-face] #{error.class}: #{error.message}"
        nil
      end

      def rebuild
        unless @candidate
          @plan = nil
          ContactTool.push_hover(nil)
          return
        end
        @plan = ContactTool.contact_plan(@candidate[:points],@candidate[:cursor],@options,@rotation_deg)
        target = @candidate[:target]
        name = target.respond_to?(:name) && !target.name.to_s.empty? ? target.name.to_s : target.class.name.split('::').last
        ContactTool.push_hover(
          target:name,
          face_length_mm:@plan[:face_length_mm],
          face_width_mm:@plan[:face_width_mm],
          rotation_deg:@plan[:rotation_deg],
          valid:@plan[:valid]
        )
      rescue StandardError => error
        @plan = nil
        ContactTool.push_hover(target:error.message)
      end
    end
  end
end
