# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'

module TranTuanNoiThat
  module LedTool
    extend self

    VERSION = '1.0.0'.freeze
    KEY = 'TT_LED'.freeze
    DATA_DIR = File.join(TranTuanNoiThat::ROOT, 'data', 'led_tool').freeze
    PRESET_FILE = File.join(DATA_DIR, 'presets.json').freeze
    DEFAULT_PRESET = 'LED 10MM'.freeze
    DEFAULTS = {
      'name'=>'LED 10MM',
      'end_clearance'=>20.0,
      'edge_offset'=>30.0,
      'groove_width'=>10.0,
      'groove_length'=>0.0,
      'led_color'=>'#ffd36a',
      'simulate'=>true,
      'cnc'=>true,
      'cnc_tag'=>'ABF_RANHLED'
    }.freeze

    def ensure_data
      FileUtils.mkdir_p(DATA_DIR)
      true
    end

    def normalize_tag(value)
      text = value.to_s.strip.upcase.gsub(/[^A-Z0-9_]+/,'_').gsub(/_+/,'_').sub(/\A_+/,'').sub(/_+\z/,'')
      text = 'RANHLED' if text.empty?
      text = 'ABF_' + text unless text.start_with?('ABF_')
      text
    end

    def normalize_color(value)
      text = value.to_s.strip
      text = '#ffd36a' unless text.match?(/\A#[0-9a-fA-F]{6}\z/)
      text.downcase
    end

    def normalize(raw)
      source = DEFAULTS.merge((raw || {}).transform_keys(&:to_s))
      out = source.dup
      out['name'] = source['name'].to_s.strip
      out['name'] = DEFAULTS['name'] if out['name'].empty?
      out['end_clearance'] = [[source['end_clearance'].to_f,0.0].max,5000.0].min
      out['edge_offset'] = [[source['edge_offset'].to_f,0.0].max,5000.0].min
      out['groove_width'] = [[source['groove_width'].to_f,0.5].max,200.0].min
      out['groove_length'] = [[source['groove_length'].to_f,0.0].max,100_000.0].min
      out['led_color'] = normalize_color(source['led_color'])
      out['simulate'] = source['simulate'] == true || source['simulate'].to_s == 'true' || source['simulate'].to_s == '1'
      out['cnc'] = source['cnc'] == true || source['cnc'].to_s == 'true' || source['cnc'].to_s == '1'
      out['cnc_tag'] = normalize_tag(source['cnc_tag'])
      out
    end

    def settings
      raw = Sketchup.read_default(KEY,'settings','{}')
      parsed = JSON.parse(raw.to_s)
      normalize(parsed)
    rescue StandardError
      DEFAULTS.dup
    end

    def save_settings(raw)
      clean = normalize(raw)
      Sketchup.write_default(KEY,'settings',JSON.generate(clean))
      clean
    end

    def custom_presets
      return {} unless File.file?(PRESET_FILE)
      data = JSON.parse(File.read(PRESET_FILE,encoding:'UTF-8'))
      return {} unless data.is_a?(Hash)
      data.each_with_object({}) do |(name,value),memo|
        memo[name.to_s] = normalize(value) if value.is_a?(Hash)
      rescue StandardError
        nil
      end
    rescue StandardError
      {}
    end

    def presets
      {DEFAULT_PRESET=>DEFAULTS.dup}.merge(custom_presets)
    end

    def save_preset(name, raw)
      clean = normalize(raw)
      title = name.to_s.strip
      title = clean['name'] if title.empty?
      raise 'Tên mẫu LED không được để trống.' if title.empty?
      rows = custom_presets
      rows[title] = clean.merge('name'=>title)
      ensure_data
      File.write(PRESET_FILE,JSON.pretty_generate(rows),encoding:'UTF-8')
      title
    end

    def delete_preset(name)
      title = name.to_s
      raise 'Không xóa mẫu mặc định LED 10MM.' if title == DEFAULT_PRESET
      rows = custom_presets
      rows.delete(title)
      ensure_data
      File.write(PRESET_FILE,JSON.pretty_generate(rows),encoding:'UTF-8')
      true
    end

    def groove_plan(length_mm,width_mm,raw,side = :min)
      opts = normalize(raw)
      length = length_mm.to_f
      width = width_mm.to_f
      raise 'Mặt phải có chiều dài và chiều rộng lớn hơn 0.' unless length > 0 && width > 0

      end_gap = opts['end_clearance']
      groove_w = opts['groove_width']
      edge = opts['edge_offset']
      available_l = length - 2.0*end_gap
      available_w = width - edge - groove_w
      raise 'Cách 2 đầu quá lớn so với chiều dài mặt.' unless available_l > 0
      raise 'Cách mép ngoài + độ rộng rãnh vượt quá chiều rộng mặt.' unless available_w >= -1.0e-6

      requested = opts['groove_length']
      groove_l = requested > 0 ? [requested,available_l].min : available_l
      u0 = end_gap + (available_l-groove_l)/2.0
      u1 = u0 + groove_l
      if side.to_sym == :max
        v1 = width - edge
        v0 = v1 - groove_w
      else
        v0 = edge
        v1 = v0 + groove_w
      end
      {
        u0:u0,u1:u1,v0:v0,v1:v1,
        length:groove_l,width:groove_w,
        side:side.to_sym,auto_length:requested <= 0
      }
    end

    def color_from_hex(hex, alpha = 255)
      text = normalize_color(hex).delete_prefix('#')
      Sketchup::Color.new(text[0,2].to_i(16),text[2,2].to_i(16),text[4,2].to_i(16),alpha)
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def target_entities(target)
      target.respond_to?(:entities) ? target.entities : target.definition.entities
    end

    def entity_reference_id(entity)
      return entity.persistent_id if entity.respond_to?(:persistent_id)
      return entity.entityID if entity.respond_to?(:entityID)
      entity.object_id
    rescue StandardError
      entity.object_id
    end

    def operation_setting_name(tag_name)
      tag_name.to_s.sub(/\AABF_/,'').tr('_',' ').downcase.strip
    end

    def ensure_tag(model,name)
      model.layers[name] || model.layers.add(name)
    end

    def point_uv(origin,u,v,uu,vv,normal = nil,normal_offset = 0.0)
      n = normal || Geom::Vector3d.new(0,0,0)
      Geom::Point3d.new(
        origin.x + u.x*uu + v.x*vv + n.x*normal_offset,
        origin.y + u.y*uu + v.y*vv + n.y*normal_offset,
        origin.z + u.z*uu + v.z*vv + n.z*normal_offset
      )
    end

    def analyze_face(face)
      verts = face.outer_loop.vertices.map(&:position)
      raise 'Face cần ít nhất 3 đỉnh.' if verts.length < 3
      pairs = verts.each_with_index.map { |point,index| [point,verts[(index+1)%verts.length]] }
      a,b = pairs.max_by { |p,q| p.distance(q) }
      u = a.vector_to(b)
      raise 'Không xác định được trục dài của mặt.' if u.length <= 1.0e-9
      u = u.normalize
      normal = face.normal
      normal = normal.normalize
      v = normal.cross(u)
      raise 'Không xác định được trục ngang của mặt.' if v.length <= 1.0e-9
      v = v.normalize
      origin = verts.first
      us = verts.map { |p| origin.vector_to(p).dot(u) }
      vs = verts.map { |p| origin.vector_to(p).dot(v) }
      min_u,max_u = us.minmax
      min_v,max_v = vs.minmax
      len = max_u-min_u
      wid = max_v-min_v

      if wid > len
        u,v = v,u
        min_u,max_u = vs.minmax
        min_v,max_v = us.minmax
        len,wid = wid,len
      end
      {
        origin:origin,u:u,v:v,normal:normal,
        min_u:min_u,max_u:max_u,min_v:min_v,max_v:max_v,
        length_mm:len.to_f*25.4,width_mm:wid.to_f*25.4
      }
    end

    def local_rect(analysis,plan,normal_offset_mm = 0.0, width_scale = 1.0)
      center_v = (plan[:v0]+plan[:v1])/2.0
      half = plan[:width]*width_scale/2.0
      v0 = center_v-half
      v1 = center_v+half
      base_u = analysis[:min_u].to_f*25.4
      base_v = analysis[:min_v].to_f*25.4
      uu0 = (base_u+plan[:u0]).mm
      uu1 = (base_u+plan[:u1]).mm
      vv0 = (base_v+v0).mm
      vv1 = (base_v+v1).mm
      off = normal_offset_mm.to_f.mm
      [
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu0,vv0,analysis[:normal],off),
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu1,vv0,analysis[:normal],off),
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu1,vv1,analysis[:normal],off),
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu0,vv1,analysis[:normal],off)
      ]
    end

    def find_host_face(target, local_points)
      target_entities(target).grep(Sketchup::Face).select do |face|
        begin
          local_points.all? { |point| point.distance_to_plane(face.plane).abs <= 0.2.mm }
        rescue StandardError
          false
        end
      end.max_by { |face| face.area.to_f }
    end

    def add_abf_profile(target,host_face,points,opts)
      model = Sketchup.active_model
      tag_name = normalize_tag(opts['cnc_tag'])
      tag = ensure_tag(model,tag_name)
      entities = target_entities(target)
      group = entities.add_group
      group.name = '_ABF_Intersect'
      group.layer = tag
      group.set_attribute('ABF','is-intersect',true)
      group.set_attribute('ABF','intersect-offset',0.0)
      group.set_attribute('ABF','setting-name',operation_setting_name(tag_name))
      group.set_attribute('ABF','intersect-group-b-id',entity_reference_id(target))
      group.set_attribute(KEY,'role','led_cnc_profile')
      group.set_attribute(KEY,'name',opts['name'])
      group.set_attribute(KEY,'cnc_tag',tag_name)
      group.set_attribute(KEY,'groove_width_mm',opts['groove_width'])

      face = group.entities.add_face(points)
      raise 'Không tạo được Face rãnh LED cho ABF/Aspire.' unless face && face.valid?
      face.layer = tag
      face.edges.each do |edge|
        edge.layer = tag
        edge.set_attribute(KEY,'role','led_cnc_edge')
      end
      face.set_attribute(KEY,'role','led_cnc_face')
      host_face.set_attribute('ABF','is-cnced-face',true) if host_face
      target.set_attribute('ABF','is-board',true)
      target.set_attribute('ABF','ranh_led',true)
      target.set_attribute(KEY,'cnc_tag',tag_name)
      target.set_attribute(KEY,'led_profile_embedded',true)
      group
    end

    def ensure_material(model,name,color,alpha)
      mats = model.materials
      material = mats[name] || mats.add(name)
      material.color = color if material.respond_to?(:color=)
      material.alpha = alpha if material.respond_to?(:alpha=)
      material
    end

    def add_led_simulation(world_rect,target_tr,analysis,plan,opts)
      return nil unless opts['simulate']
      model = Sketchup.active_model
      group = model.active_entities.add_group
      group.name = "TT_LED_MO_PHONG_#{opts['name']}"
      group.set_attribute(KEY,'role','led_simulation')
      group.set_attribute(KEY,'host_id',entity_reference_id(target_tr[:target]))
      group.set_attribute(KEY,'led_color',opts['led_color'])

      active_inv = begin
        model.edit_transform.inverse
      rescue StandardError
        Geom::Transformation.new
      end

      bands = [
        [1.0,0.8,0.95],
        [2.6,1.0,0.34],
        [5.0,1.2,0.14]
      ]
      bands.each_with_index do |(scale,offset_mm,alpha),index|
        local = local_rect(analysis,plan,offset_mm,scale)
        world = local.map { |point| point.transform(target_tr[:transform]) }
        active_points = world.map { |point| point.transform(active_inv) }
        face = group.entities.add_face(active_points)
        next unless face
        mat = ensure_material(model,"TT_LED_#{opts['led_color'].delete_prefix('#')}_#{index}",color_from_hex(opts['led_color']),alpha)
        face.material = mat
        face.back_material = mat if face.respond_to?(:back_material=)
        face.edges.each { |edge| edge.hidden = true if edge.respond_to?(:hidden=) }
      end
      group
    end

    def send_dialog_state
      return unless @dialog && @dialog.visible?
      payload = {
        settings: @active_tool ? @active_tool.options : settings,
        presets: presets,
        selected: @current_preset.to_s
      }
      @dialog.execute_script("TTLED.load(#{JSON.generate(payload)})")
    rescue StandardError => error
      puts "[TT LED dialog state] #{error.class}: #{error.message}"
    end

    def send_detected(info)
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("TTLED.detected(#{JSON.generate(info || {})})")
    rescue StandardError
      nil
    end

    def dialog_html
      <<~'HTML'
      <!doctype html><html lang="vi"><head><meta charset="utf-8">
      <style>
      *{box-sizing:border-box}body{margin:0;font:13px Arial,sans-serif;background:#eef7fb;color:#18384a}
      .head{background:#176b87;color:#fff;padding:13px 16px;position:sticky;top:0;z-index:5}.head h2{margin:0;font-size:18px}.head small{opacity:.9}
      .layout{display:grid;grid-template-columns:220px 1fr;gap:10px;padding:10px}.panel{background:#dff4fb;border:1px solid #acd9e8;border-radius:10px;padding:11px}
      .left{min-height:500px}.title{font-weight:bold;color:#14556e;margin-bottom:8px}.preset{width:100%;text-align:left;margin:4px 0;padding:9px;border:1px solid #9cc9d9;background:#f6fcff;border-radius:7px;cursor:pointer}
      .preset.active{background:#bcecff;border-color:#39a7cf;font-weight:bold}.grid{display:grid;grid-template-columns:170px 1fr 44px;gap:7px;align-items:center}
      input,select{width:100%;padding:7px;border:1px solid #91bfd0;border-radius:6px;background:white}input[type=checkbox]{width:auto}input[type=color]{height:35px;padding:2px}
      button{border:0;border-radius:7px;padding:9px 11px;background:#177fa4;color:white;font-weight:bold;cursor:pointer}.gray{background:#607d8b}.red{background:#b84b4b}.row{display:flex;gap:7px;margin-top:9px}.row button{flex:1}
      .detect{background:#f7fdff;border:1px dashed #7bbbd2;padding:9px;border-radius:7px;margin-bottom:10px;line-height:1.55}.hint{font-size:12px;color:#4b6c79;line-height:1.5}
      #notice{min-height:20px;margin-top:8px;font-size:12px}.ok{color:#166534}.err{color:#a61b1b}
      </style></head><body>
      <div class="head"><h2>TẠO LED</h2><small>AUTO rà mặt Group/Component · preview 3D · click tạo ngay</small></div>
      <div class="layout">
        <div class="panel left"><div class="title">MẪU ĐÃ LƯU</div><div id="presets"></div>
          <div class="row"><button onclick="savePreset()">LƯU MẪU</button></div>
          <div class="row"><button class="red" onclick="deletePreset()">XÓA MẪU</button></div>
          <div class="hint" style="margin-top:10px">Chọn mẫu bên trái: thông số và preview áp dụng ngay.</div>
        </div>
        <div class="panel">
          <div class="title">THÔNG SỐ RÃNH LED</div>
          <div class="detect"><b>Đối tượng đang rà:</b> <span id="target">Chưa nhận</span><br><b>Mặt:</b> <span id="dims">-</span><br><b>Rãnh preview:</b> <span id="groove">-</span></div>
          <div class="grid">
            <label>Tên mẫu / rãnh</label><input id="name"><span></span>
            <label>Cách 2 đầu</label><input id="end_clearance" type="number" min="0" step="0.5"><span>mm</span>
            <label>Cách mép ngoài</label><input id="edge_offset" type="number" min="0" step="0.5"><span>mm</span>
            <label>Độ rộng rãnh LED</label><input id="groove_width" type="number" min="0.5" step="0.5"><span>mm</span>
            <label>Chiều dài rãnh</label><input id="groove_length" type="number" min="0" step="1"><span>mm</span>
            <label>Màu LED mô phỏng</label><input id="led_color" type="color"><span></span>
            <label>Mô phỏng ánh sáng</label><input id="simulate" type="checkbox"><span></span>
            <label>Chế độ CNC</label><input id="cnc" type="checkbox"><span></span>
            <label>Tên CNC / Tag ABF</label><input id="cnc_tag"><span></span>
          </div>
          <div class="hint" style="margin-top:7px"><b>Chiều dài = 0</b> → AUTO lấy chiều dài mặt trừ Cách 2 đầu. Rê chuột gần mép nào thì rãnh tự bám mép đó.</div>
          <div class="row"><button onclick="apply()">CẬP NHẬT PREVIEW</button></div>
          <div id="notice"></div>
          <div class="hint" style="margin-top:9px"><b>CNC:</b> tạo biên dạng kín thật <code>_ABF_Intersect</code> nằm trong chính Group/Component, Tag mặc định <b>ABF_RANHLED</b>, mặt được đánh dấu <code>ABF/is-cnced-face</code> để ABF/Aspire nhận đường gia công.</div>
        </div>
      </div>
      <script>
      const ids=['name','end_clearance','edge_offset','groove_width','groove_length','led_color','simulate','cnc','cnc_tag'];let selected='';
      const TTLED={
        state:{},
        load(data){this.state=data||{};selected=data.selected||'';this.renderPresets(data.presets||{});this.fill(data.settings||{});},
        fill(s){ids.forEach(id=>{let e=document.getElementById(id);if(!e)return;if(e.type==='checkbox')e.checked=!!s[id];else if(s[id]!==undefined)e.value=s[id]});},
        values(){let o={};ids.forEach(id=>{let e=document.getElementById(id);o[id]=e.type==='checkbox'?e.checked:(e.type==='number'?Number(e.value):e.value)});return o;},
        renderPresets(rows){let box=document.getElementById('presets');box.innerHTML='';Object.keys(rows).sort().forEach(name=>{let b=document.createElement('button');b.className='preset'+(name===selected?' active':'');b.textContent=name;b.onclick=()=>{selected=name;sketchup.load_preset(name)};box.appendChild(b)})},
        detected(info){target.textContent=info.target||'Chưa nhận';dims.textContent=info.length?Math.round(info.length*10)/10+' × '+Math.round(info.width*10)/10+' mm':'-';groove.textContent=info.groove_length?Math.round(info.groove_length*10)/10+' × '+Math.round(info.groove_width*10)/10+' mm':'-';},
        notice(msg,bad){let n=document.getElementById('notice');n.textContent=msg||'';n.className=bad?'err':'ok'}
      };
      function apply(){sketchup.update(JSON.stringify(TTLED.values()))}
      function savePreset(){let v=TTLED.values();sketchup.save_preset(v.name||'LED',JSON.stringify(v))}
      function deletePreset(){if(!selected){TTLED.notice('Chưa chọn mẫu để xóa.',true);return}sketchup.delete_preset(selected)}
      let timer=null;ids.forEach(id=>document.addEventListener('DOMContentLoaded',()=>{let e=document.getElementById(id);if(!e)return;e.addEventListener('input',()=>{clearTimeout(timer);timer=setTimeout(apply,180)});e.addEventListener('change',apply)}));
      document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      </script></body></html>
      HTML
    end

    def show_dialog(tool = nil)
      @active_tool = tool if tool
      unless @dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title:'Tạo LED',
          preferences_key:'TT_LED_TOOL',
          scrollable:true,resizable:true,width:760,height:620,
          style:UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(dialog_html)
        @dialog.add_action_callback('ready') { send_dialog_state }
        @dialog.add_action_callback('update') do |_ctx,json|
          clean = save_settings(JSON.parse(json.to_s))
          @active_tool.update_options(clean) if @active_tool
          send_dialog_state
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('load_preset') do |_ctx,name|
          row = presets[name.to_s]
          raise 'Không tìm thấy mẫu LED.' unless row
          @current_preset = name.to_s
          clean = save_settings(row)
          @active_tool.update_options(clean) if @active_tool
          send_dialog_state
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('save_preset') do |_ctx,name,json|
          clean = save_settings(JSON.parse(json.to_s))
          @current_preset = save_preset(name,clean)
          @active_tool.update_options(clean) if @active_tool
          send_dialog_state
          @dialog.execute_script("TTLED.notice('Đã lưu mẫu LED.',false)")
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('delete_preset') do |_ctx,name|
          delete_preset(name)
          @current_preset = ''
          send_dialog_state
          @dialog.execute_script("TTLED.notice('Đã xóa mẫu LED.',false)")
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.set_on_closed { @dialog = nil }
      end
      @dialog.show
      send_dialog_state
      @dialog
    end

    def activate
      tool = Tool.new(settings)
      @active_tool = tool
      Sketchup.active_model.select_tool(tool)
      show_dialog(tool)
      tool
    end

    class Tool
      attr_reader :options

      def initialize(options)
        @model = Sketchup.active_model
        @options = LedTool.normalize(options)
        @target = nil
        @target_tr = Geom::Transformation.new
        @face = nil
        @analysis = nil
        @plan = nil
        @side = :min
        @last_detect_key = nil
      end

      def activate
        Sketchup.set_status_text('TẠO LED · Rê vào mặt Group/Component · CLICK tạo rãnh · ESC thoát',SB_PROMPT)
      end

      def deactivate(view)
        view.invalidate if view
      end

      def resume(view)
        Sketchup.set_status_text('TẠO LED · AUTO rà mặt · CLICK tạo ngay',SB_PROMPT)
        view.invalidate
      end

      def onCancel(_reason,view)
        @model.select_tool(nil)
        view.invalidate
      end

      def update_options(raw)
        @options = LedTool.normalize(raw)
        rebuild_plan
        @model.active_view.invalidate
      rescue StandardError => error
        @plan = nil
        LedTool.send_detected(error:error.message)
      end

      def onMouseMove(_flags,x,y,view)
        pick(view,x,y)
        view.invalidate
      rescue StandardError => error
        clear_pick
        Sketchup.set_status_text("TẠO LED: #{error.message}",SB_PROMPT)
      end

      def onLButtonDown(_flags,x,y,view)
        pick(view,x,y)
        return UI.beep unless @target && @face && @analysis && @plan
        create_led
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Tạo LED:\n#{error.message}")
      end

      def draw(view)
        return unless @analysis && @plan && @target
        base = preview_world_rect(0.45,1.0)
        glow1 = preview_world_rect(0.7,2.6)
        glow2 = preview_world_rect(0.9,5.0)
        view.line_width = 2
        view.drawing_color = LedTool.color_from_hex(@options['led_color'],230)
        view.draw(GL_QUADS,base) if defined?(GL_QUADS)
        view.draw(GL_LINE_LOOP,base)
        if @options['simulate'] && defined?(GL_QUADS)
          view.drawing_color = LedTool.color_from_hex(@options['led_color'],75)
          view.draw(GL_QUADS,glow1)
          view.drawing_color = LedTool.color_from_hex(@options['led_color'],35)
          view.draw(GL_QUADS,glow2)
        end
        if view.respond_to?(:draw_text)
          center = base[0].vector_to(base[2])
          label_point = Geom::Point3d.new(base[0].x+center.x*0.5,base[0].y+center.y*0.5,base[0].z+center.z*0.5)
          view.draw_text(label_point,"LED #{@plan[:length].round(1)} × #{@plan[:width].round(1)} mm")
        end
      rescue StandardError => error
        puts "[TT LED draw] #{error.class}: #{error.message}"
      end

      private

      def clear_pick
        @target = @face = @analysis = @plan = nil
        @target_tr = Geom::Transformation.new
        notify_detected
      end

      def pick(view,x,y)
        ph = view.pick_helper
        ph.do_pick(x,y)
        found = nil
        ph.count.times do |index|
          path = ph.path_at(index)
          next unless path
          face = path.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
          next unless face
          containers = path.select { |entity| LedTool.container?(entity) }
          if containers.empty? && @model.active_path && !@model.active_path.empty?
            containers = [@model.active_path.last].select { |entity| LedTool.container?(entity) }
          end
          next if containers.empty?
          target = containers.last
          tr = begin
            @model.edit_transform
          rescue StandardError
            Geom::Transformation.new
          end
          path.each do |entity|
            tr = tr * entity.transformation if LedTool.container?(entity)
            break if entity.equal?(target)
          end
          found = [target,tr,face]
          break
        end
        return clear_pick unless found
        @target,@target_tr,@face = found
        @analysis = LedTool.analyze_face(@face)
        begin
          world_normal = @analysis[:normal].transform(@target_tr)
          if world_normal.dot(view.camera.direction) > 0
            @analysis[:normal] = @analysis[:normal].reverse
          end
        rescue StandardError
          nil
        end
        choose_side(view,x,y)
        rebuild_plan
        notify_detected
      end

      def choose_side(view,x,y)
        world_origin = @analysis[:origin].transform(@target_tr)
        world_normal = @analysis[:normal].transform(@target_tr)
        hit = Geom.intersect_line_plane(view.pickray(x,y),[world_origin,world_normal])
        return unless hit
        local = hit.transform(@target_tr.inverse)
        vv = @analysis[:origin].vector_to(local).dot(@analysis[:v])
        mid = (@analysis[:min_v]+@analysis[:max_v])/2.0
        @side = vv <= mid ? :min : :max
      rescue StandardError
        @side = :min
      end

      def rebuild_plan
        return @plan = nil unless @analysis
        @plan = LedTool.groove_plan(@analysis[:length_mm],@analysis[:width_mm],@options,@side)
      end

      def notify_detected
        info = if @analysis && @plan && @target
          {
            target:(@target.name.to_s.empty? ? @target.class.name.split('::').last : @target.name.to_s),
            length:@analysis[:length_mm],width:@analysis[:width_mm],
            groove_length:@plan[:length],groove_width:@plan[:width],
            side:@plan[:side].to_s
          }
        else
          {}
        end
        key = info.to_s
        return if key == @last_detect_key
        @last_detect_key = key
        LedTool.send_detected(info)
      end

      def preview_world_rect(offset_mm,width_scale)
        LedTool.local_rect(@analysis,@plan,offset_mm,width_scale).map { |point| point.transform(@target_tr) }
      end

      def create_led
        model = @model
        model.start_operation('TT - Tạo LED',true)
        started = true
        target = @target
        if target.respond_to?(:definition) && target.respond_to?(:make_unique)
          instances = target.definition.respond_to?(:instances) ? target.definition.instances : []
          target.make_unique if instances && instances.length > 1
        end

        local_points = LedTool.local_rect(@analysis,@plan,0.0,1.0)
        host_face = LedTool.find_host_face(target,local_points)
        host_face ||= @face if @face && @face.valid?
        raise 'Không tìm lại được Face gia công sau khi Make Unique.' unless host_face

        LedTool.add_abf_profile(target,host_face,local_points,@options) if @options['cnc']
        LedTool.add_led_simulation(preview_world_rect(0.0,1.0),{target:target,transform:@target_tr},@analysis,@plan,@options) if @options['simulate']

        target.set_attribute(KEY,'name',@options['name'])
        target.set_attribute(KEY,'end_clearance_mm',@options['end_clearance'])
        target.set_attribute(KEY,'edge_offset_mm',@options['edge_offset'])
        target.set_attribute(KEY,'groove_width_mm',@options['groove_width'])
        target.set_attribute(KEY,'groove_length_mm',@plan[:length])
        target.set_attribute(KEY,'led_color',@options['led_color'])
        target.set_attribute(KEY,'cnc_enabled',@options['cnc'])
        model.commit_operation
        started = false
        Sketchup.set_status_text("Đã tạo LED #{@plan[:length].round(1)} × #{@plan[:width].round(1)} mm · tiếp tục rà mặt khác",SB_PROMPT)
      rescue StandardError
        model.abort_operation if started
        raise
      end
    end
  end
end
