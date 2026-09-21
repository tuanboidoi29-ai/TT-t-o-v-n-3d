# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module CamChot
    extend self

    VERSION = '1.9.107'.freeze
    DICT = 'TT_CAM_CHOT'.freeze

    DEFAULTS = {
      'cam_diameter' => 15.0,
      'cam_depth'    => 13.5,
      'b_offset'     => 34.0,
      'pin_diameter' => 8.0,
      'pin_depth'    => 12.0,
      'end_offset'   => 37.0,
      'count'        => 2
    }.freeze

    def model
      Sketchup.active_model
    end

    def setting_key(key)
      "cam_chot_#{key}"
    end

    def load_settings
      DEFAULTS.each_with_object({}) do |(key, value), out|
        saved = Sketchup.read_default(TranTuanNoiThat::NAME, setting_key(key), value)
        out[key] = key == 'count' ? saved.to_i : saved.to_f
      end
    end

    def save_settings(data)
      clean = sanitize_settings(data)
      clean.each { |key, value| Sketchup.write_default(TranTuanNoiThat::NAME, setting_key(key), value) }
      clean
    end

    def sanitize_settings(data)
      src = data.is_a?(Hash) ? data : {}
      out = {}
      DEFAULTS.each do |key, default|
        raw = src.key?(key) ? src[key] : default
        out[key] = key == 'count' ? raw.to_i : raw.to_f
      end
      out['cam_diameter'] = 15.0 unless out['cam_diameter'] > 0.0
      out['cam_depth'] = 13.5 unless out['cam_depth'] > 0.0
      out['b_offset'] = 34.0 unless out['b_offset'] > 0.0
      out['pin_diameter'] = 8.0 unless out['pin_diameter'] > 0.0
      out['pin_depth'] = 12.0 unless out['pin_depth'] > 0.0
      out['end_offset'] = 37.0 if out['end_offset'] < 0.0
      out['count'] = 2 if out['count'] < 1
      out['count'] = 20 if out['count'] > 20
      out
    end

    def show
      @tool ||= LinkTool.new
      @tool.reset_for_model(model, load_settings)

      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        model.select_tool(@tool)
        sync_dialog
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TT - LIÊN KẾT CAM - CHỐT',
        preferences_key: 'TranTuanNoiThat.CamChot.107',
        scrollable: true,
        resizable: true,
        width: 610,
        height: 690,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)

      @dialog.add_action_callback('ready') do |_ctx|
        sync_dialog
      end

      @dialog.add_action_callback('apply_settings') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          @tool.settings = sanitize_settings(data)
          @tool.invalidate
          sync_dialog
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('save_settings') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          @tool.settings = save_settings(data)
          @tool.invalidate
          sync_dialog
          notify('Đã lưu thông số CAM - CHỐT làm mặc định.', 'ok')
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('use_selection') do |_ctx|
        @tool.assign_from_selection
        sync_dialog
      end

      @dialog.add_action_callback('flip') do |_ctx|
        @tool.flip_cam_face
        sync_dialog
      end

      @dialog.add_action_callback('create') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          @tool.settings = sanitize_settings(data)
          @tool.create_link
          sync_dialog
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('reset') do |_ctx|
        @tool.reset_picks
        sync_dialog
      end

      @dialog.set_on_closed do
        @dialog = nil
        begin
          model.select_tool(nil)
        rescue StandardError
        end
      end

      @dialog.show
      model.select_tool(@tool)
    rescue StandardError => error
      UI.messagebox("Không mở được Liên kết CAM - CHỐT:\n#{error.message}")
    end

    def sync_dialog
      return unless @dialog && @dialog.visible?
      state = @tool ? @tool.state_payload : {}
      @dialog.execute_script("TT.setState(#{JSON.generate(state)});")
    rescue StandardError => error
      warn "[TT CamChot sync] #{error.class}: #{error.message}"
    end

    def notify(message, kind = 'ok')
      if @dialog && @dialog.visible?
        @dialog.execute_script("TT.notice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind.to_s)});")
      else
        UI.messagebox(message.to_s)
      end
    rescue StandardError
      UI.messagebox(message.to_s) rescue nil
    end

    def dialog_html
      <<~HTML
        <!doctype html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            *{box-sizing:border-box}
            body{font-family:Arial,sans-serif;margin:0;background:#f2f4f7;color:#222}
            .top{padding:14px;background:#fff;border-bottom:1px solid #ddd;position:sticky;top:0;z-index:5}
            h2{margin:0 0 7px;font-size:18px}
            .state{font-size:13px;line-height:1.55;background:#eef5ff;border:1px solid #cbdfff;border-radius:7px;padding:9px}
            .content{padding:14px}
            .card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:12px}
            .grid{display:grid;grid-template-columns:1fr 110px 42px;gap:7px;align-items:center}
            .grid label{font-size:13px;font-weight:bold}
            input,select{width:100%;padding:8px;border:1px solid #bbb;border-radius:6px}
            .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
            button{border:0;border-radius:6px;padding:9px 12px;font-weight:bold;cursor:pointer;background:#2d6cdf;color:#fff}
            button.orange{background:#d86e16} button.green{background:#178a4b} button.gray{background:#66707e}
            button.preset{background:#8a5a12}
            .hint{font-size:12px;color:#626a74;line-height:1.5}
            .legend{display:flex;gap:14px;font-size:12px;margin-top:8px}
            .dot{display:inline-block;width:11px;height:11px;border-radius:50%;vertical-align:-1px;margin-right:4px}
            .cam{background:#f07a24}.pin{background:#1677d2}
            .notice{display:none;padding:9px;border-radius:6px;margin-top:10px;font-size:13px;white-space:pre-wrap}
            .notice.ok{display:block;background:#e7f6ee;color:#175f38}
            .notice.warn{display:block;background:#fff3d8;color:#805600}
            .notice.error{display:block;background:#fdeaea;color:#8d2323}
          </style>
        </head>
        <body>
          <div class="top">
            <h2>LIÊN KẾT CAM - CHỐT</h2>
            <div id="state" class="state">Click tấm CAM rồi click tấm CHỐT trong SketchUp.</div>
            <div class="legend">
              <span><span class="dot cam"></span>CAM</span>
              <span><span class="dot pin"></span>CHỐT</span>
            </div>
          </div>
          <div class="content">
            <div class="card">
              <div class="grid">
                <label>CAM Ø</label><input id="cam_diameter" type="number" value="15" step="0.1"><span>mm</span>
                <label>Sâu CAM</label><input id="cam_depth" type="number" value="13.5" step="0.1"><span>mm</span>
                <label>B - tâm CAM cách mép</label><input id="b_offset" type="number" value="34" step="1"><span>mm</span>
                <label>CHỐT Ø</label><input id="pin_diameter" type="number" value="8" step="0.1"><span>mm</span>
                <label>Sâu CHỐT</label><input id="pin_depth" type="number" value="12" step="0.1"><span>mm</span>
                <label>Cách hai đầu</label><input id="end_offset" type="number" value="37" step="1"><span>mm</span>
                <label>Số bộ</label><input id="count" type="number" value="2" min="1" max="20" step="1"><span>bộ</span>
              </div>
              <div class="row">
                <button class="preset" onclick="presetB(24)">B24</button>
                <button class="preset" onclick="presetB(34)">B34</button>
                <button onclick="applySettings()">Áp dụng xem trước</button>
                <button class="gray" onclick="saveSettings()">Lưu mặc định</button>
              </div>
            </div>

            <div class="card">
              <div class="row">
                <button onclick="sketchup.use_selection()">Dùng 2 tấm đang chọn</button>
                <button class="gray" onclick="sketchup.flip()">Đảo mặt CAM (TAB)</button>
                <button class="gray" onclick="sketchup.reset()">Chọn lại</button>
              </div>
              <div class="row">
                <button class="green" onclick="createLink()">TẠO LIÊN KẾT (ENTER)</button>
              </div>
              <div class="hint">
                Cách dùng: click tấm nhận CAM → click tấm nhận CHỐT. Hai tấm cần vuông góc và nằm trong cùng ngữ cảnh đang mở.
                TAB đổi mặt đặt CAM. Preview cam màu cam, chốt màu xanh.
              </div>
            </div>

            <div id="notice" class="notice"></div>
          </div>
          <script>
            const TT={
              settings:{},
              setState(s){
                this.settings=s.settings||this.settings||{};
                for(const k of ['cam_diameter','cam_depth','b_offset','pin_diameter','pin_depth','end_offset','count']){
                  if(this.settings[k]!==undefined) document.getElementById(k).value=this.settings[k];
                }
                const cam=s.cam_name||'Chưa chọn';
                const pin=s.pin_name||'Chưa chọn';
                const joint=s.joint||'';
                document.getElementById('state').innerHTML=
                  '<b>Tấm CAM:</b> '+esc(cam)+'<br><b>Tấm CHỐT:</b> '+esc(pin)+
                  '<br><b>Mặt CAM:</b> '+(s.flip_cam?'Mặt đối diện':'Mặt mặc định')+
                  (joint?'<br><b>Preview:</b> '+esc(joint):'');
              },
              notice(msg,kind){
                const e=document.getElementById('notice');
                e.className='notice '+(kind||'ok'); e.textContent=msg||'';
              }
            };
            function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}
            function values(){
              const o={};
              for(const k of ['cam_diameter','cam_depth','b_offset','pin_diameter','pin_depth','end_offset','count']){
                o[k]=Number(document.getElementById(k).value);
              }
              return o;
            }
            function applySettings(){sketchup.apply_settings(JSON.stringify(values()));}
            function saveSettings(){sketchup.save_settings(JSON.stringify(values()));}
            function createLink(){sketchup.create(JSON.stringify(values()));}
            function presetB(v){document.getElementById('b_offset').value=v;applySettings();}
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body>
        </html>
      HTML
    end

    class LinkTool
      attr_accessor :settings

      def initialize
        @model = nil
        @cam = nil
        @pin = nil
        @hover = nil
        @flip_cam = false
        @settings = DEFAULTS.dup
      end

      def reset_for_model(model, settings)
        if @model != model
          @cam = nil
          @pin = nil
          @hover = nil
          @flip_cam = false
        end
        @model = model
        @settings = CamChot.sanitize_settings(settings)
        invalidate
      end

      def activate
        Sketchup.status_text = 'TT CAM-CHỐT: click tấm CAM → click tấm CHỐT · TAB đảo mặt CAM · ENTER tạo.'
        invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onCancel(_reason, view)
        reset_picks
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        picked = pick_container(view, x, y)
        if picked != @hover
          @hover = picked
          view.invalidate
        end
      end

      def onLButtonDown(_flags, x, y, view)
        entity = pick_container(view, x, y)
        unless entity
          UI.beep
          Sketchup.status_text = 'Không bắt được Group/Component trong ngữ cảnh hiện tại.'
          return
        end

        if @cam.nil?
          @cam = entity
        elsif @pin.nil?
          if entity == @cam
            UI.beep
            Sketchup.status_text = 'Tấm CHỐT phải khác tấm CAM.'
            return
          end
          @pin = entity
        else
          @cam = entity
          @pin = nil
        end

        CamChot.sync_dialog
        invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when 9
          flip_cam_face
        when 13
          create_link
        when 27
          reset_picks
        end
        view.invalidate
      end

      def getMenu(menu)
        menu.add_item('Đảo mặt CAM (TAB)') { flip_cam_face }
        menu.add_item('Tạo liên kết (ENTER)') { create_link }
        menu.add_item('Chọn lại') { reset_picks }
      end

      def assign_from_selection
        objects = @model.selection.to_a.select do |entity|
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid?
        end
        objects = objects.select { |entity| active_entities.include?(entity) }
        if objects.length < 2
          CamChot.notify('Hãy chọn đúng 2 Group/Component trong cùng ngữ cảnh hiện tại.', 'warn')
          return false
        end
        @cam = objects[0]
        @pin = objects[1]
        invalidate
        true
      end

      def flip_cam_face
        @flip_cam = !@flip_cam
        CamChot.sync_dialog
        invalidate
        true
      end

      def reset_picks
        @cam = nil
        @pin = nil
        @hover = nil
        CamChot.sync_dialog
        invalidate
        true
      end

      def state_payload
        joint = ''
        if @cam && @pin
          begin
            layout = compute_layout
            joint = "#{layout[:cam_points].length} bộ · B#{CamChot.format_number(@settings['b_offset'])}"
          rescue StandardError => error
            joint = error.message
          end
        end
        {
          cam_name: @cam ? display_name(@cam) : nil,
          pin_name: @pin ? display_name(@pin) : nil,
          flip_cam: @flip_cam,
          joint: joint,
          settings: @settings
        }
      end

      def invalidate
        @model.active_view.invalidate if @model && @model.active_view
      rescue StandardError
      end

      def draw(view)
        draw_box(view, @hover, Sketchup::Color.new(120, 120, 120), 1) if @hover
        draw_box(view, @cam, Sketchup::Color.new(240, 122, 36), 3) if @cam
        draw_box(view, @pin, Sketchup::Color.new(22, 119, 210), 3) if @pin

        return unless @cam && @pin
        layout = compute_layout

        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(240, 122, 36)
        layout[:cam_points].each do |point|
          view.draw(GL_LINE_LOOP, circle_points(point, layout[:cam_face_normal], mm(@settings['cam_diameter']) / 2.0, 24))
          view.draw_points(point, 8, 2, Sketchup::Color.new(240, 122, 36))
        end

        view.drawing_color = Sketchup::Color.new(22, 119, 210)
        layout[:pin_points].each do |point|
          view.draw(GL_LINE_LOOP, circle_points(point, layout[:pin_face_normal], mm(@settings['pin_diameter']) / 2.0, 24))
          view.draw_points(point, 8, 2, Sketchup::Color.new(22, 119, 210))
        end

        view.line_width = 1
        layout[:cam_points].zip(layout[:pin_points]).each do |cam_point, pin_point|
          view.drawing_color = Sketchup::Color.new(245, 165, 80)
          view.draw(GL_LINES, [cam_point, pin_point])
        end
      rescue StandardError => error
        Sketchup.status_text = "TT CAM-CHỐT: #{error.message}"
      end

      def create_link
        unless @cam && @pin
          CamChot.notify('Chưa chọn đủ tấm CAM và tấm CHỐT.', 'warn')
          return false
        end

        layout = compute_layout
        @model.start_operation('TT - Liên kết CAM CHỐT', true)
        started = true

        make_unique_if_needed(@cam)
        make_unique_if_needed(@pin)
        layout = compute_layout

        cam_tag = layer("TT_CAM_D#{CamChot.format_number(@settings['cam_diameter'])}_B#{CamChot.format_number(@settings['b_offset'])}")
        pin_tag = layer("TT_CHOT_D#{CamChot.format_number(@settings['pin_diameter'])}")
        link_id = "TTCC-#{Time.now.to_i}-#{rand(100000)}"

        layout[:cam_points].each_with_index do |point, index|
          add_marker(
            @cam,
            point,
            layout[:cam_face_normal],
            layout[:cam_inward],
            @settings['cam_diameter'],
            @settings['cam_depth'],
            cam_tag,
            'cam',
            link_id,
            index + 1
          )
        end

        layout[:pin_points].each_with_index do |point, index|
          add_marker(
            @pin,
            point,
            layout[:pin_face_normal],
            layout[:pin_inward],
            @settings['pin_diameter'],
            @settings['pin_depth'],
            pin_tag,
            'chot',
            link_id,
            index + 1
          )
        end

        @model.commit_operation
        started = false

        count = layout[:cam_points].length
        CamChot.notify("Đã tạo #{count} bộ CAM - CHỐT. Đường tròn và trục khoan là hình học thật trong tấm. Ctrl+Z hoàn tác một lần.", 'ok')
        reset_picks
        true
      rescue StandardError => error
        @model.abort_operation if started rescue nil
        CamChot.notify("Không tạo được CAM - CHỐT:\n#{error.message}", 'error')
        false
      end

      def compute_layout
        raise 'Tấm CAM không còn hợp lệ.' unless valid_container?(@cam)
        raise 'Tấm CHỐT không còn hợp lệ.' unless valid_container?(@pin)

        cam = board_frame(@cam)
        pin = board_frame(@pin)

        n_cam = cam[:normal]
        n_pin_raw = pin[:normal]
        dot = n_cam.dot(n_pin_raw).abs
        raise 'Hai tấm phải vuông góc với nhau.' if dot > 0.25

        direction = n_cam.cross(n_pin_raw)
        raise 'Không xác định được hướng giao hai tấm.' if direction.length < 0.001
        direction.normalize!

        n_pin = direction.cross(n_cam)
        n_pin.normalize!
        n_pin.reverse! if n_pin.dot(n_pin_raw) < 0.0

        cam_d = projection(cam[:corners], direction)
        cam_n = projection(cam[:corners], n_cam)
        cam_p = projection(cam[:corners], n_pin)
        pin_d = projection(pin[:corners], direction)
        pin_n = projection(pin[:corners], n_cam)
        pin_p = projection(pin[:corners], n_pin)

        overlap_min = [cam_d[0], pin_d[0]].max
        overlap_max = [cam_d[1], pin_d[1]].min
        raise 'Hai tấm không có vùng giao đủ để đặt liên kết.' unless overlap_max > overlap_min

        cam_center_p = scalar(cam[:center], n_pin)
        pin_surface_candidates = [pin_p[0], pin_p[1]]
        pin_surface = pin_surface_candidates.min_by { |value| (value - cam_center_p).abs }

        cam_edge_candidates = [cam_p[0], cam_p[1]]
        cam_edge = cam_edge_candidates.min_by { |value| (value - pin_surface).abs }
        inward_sign = (cam_edge - cam_p[0]).abs < (cam_edge - cam_p[1]).abs ? 1.0 : -1.0
        cam_housing_p = cam_edge + inward_sign * mm(@settings['b_offset'])

        if cam_housing_p <= cam_p[0] || cam_housing_p >= cam_p[1]
          raise "B#{CamChot.format_number(@settings['b_offset'])} vượt ra ngoài chiều rộng tấm CAM."
        end

        cam_face_s = @flip_cam ? cam_n[0] : cam_n[1]
        cam_face_sign = @flip_cam ? -1.0 : 1.0
        cam_mid_s = (cam_n[0] + cam_n[1]) / 2.0

        pin_face_sign = (pin_surface - pin_p[1]).abs < (pin_surface - pin_p[0]).abs ? 1.0 : -1.0
        pin_face_normal = scaled(n_pin, pin_face_sign)
        pin_inward = scaled(pin_face_normal, -1.0)
        cam_face_normal = scaled(n_cam, cam_face_sign)
        cam_inward = scaled(cam_face_normal, -1.0)

        positions = connector_positions(overlap_min, overlap_max, mm(@settings['end_offset']), @settings['count'].to_i)
        raise 'Không còn vị trí đặt CAM - CHỐT sau khi trừ khoảng cách hai đầu.' if positions.empty?

        cam_points = positions.map { |t| point_from_basis(direction, t, n_cam, cam_face_s, n_pin, cam_housing_p) }
        pin_points = positions.map { |t| point_from_basis(direction, t, n_cam, cam_mid_s, n_pin, pin_surface) }

        {
          cam_points: cam_points,
          pin_points: pin_points,
          cam_face_normal: cam_face_normal,
          cam_inward: cam_inward,
          pin_face_normal: pin_face_normal,
          pin_inward: pin_inward
        }
      end

      def connector_positions(min_value, max_value, end_offset, count)
        length = max_value - min_value
        return [] if length <= 0.0
        n = [count.to_i, 1].max

        if n == 1
          return [(min_value + max_value) / 2.0]
        end

        start_value = min_value + end_offset
        end_value = max_value - end_offset
        if end_value <= start_value
          return [(min_value + max_value) / 2.0]
        end

        step = (end_value - start_value) / (n - 1).to_f
        Array.new(n) { |index| start_value + step * index }
      end

      def add_marker(entity, center_world, normal_world, inward_world, diameter_mm, depth_mm, tag, kind, link_id, index)
        tr = full_transform(entity)
        inverse = tr.inverse
        points_world = circle_points(center_world, normal_world, mm(diameter_mm) / 2.0, 24)
        points_local = points_world.map { |point| point.transform(inverse) }
        entities = entity.definition.entities

        edges = entities.add_edges(*(points_local + [points_local.first]))
        axis_end_world = center_world + scaled(inward_world, mm(depth_mm))
        axis = entities.add_line(center_world.transform(inverse), axis_end_world.transform(inverse))
        all_edges = Array(edges)
        all_edges << axis if axis

        u, v = plane_axes(normal_world)
        cross_size = [mm(diameter_mm) * 0.22, mm(2.5)].min
        cross_world = [
          [center_world + scaled(u, -cross_size), center_world + scaled(u, cross_size)],
          [center_world + scaled(v, -cross_size), center_world + scaled(v, cross_size)]
        ]
        cross_world.each do |a, b|
          edge = entities.add_line(a.transform(inverse), b.transform(inverse))
          all_edges << edge if edge
        end

        all_edges.compact.each do |edge|
          edge.layer = tag
          edge.set_attribute(DICT, 'kind', kind)
          edge.set_attribute(DICT, 'link_id', link_id)
          edge.set_attribute(DICT, 'index', index)
          edge.set_attribute(DICT, 'diameter_mm', diameter_mm.to_f)
          edge.set_attribute(DICT, 'depth_mm', depth_mm.to_f)
          edge.set_attribute(DICT, 'b_offset_mm', @settings['b_offset'].to_f)
        end

        entity.set_attribute(DICT, "link_#{link_id}_#{kind}", {
          'count' => @settings['count'].to_i,
          'diameter_mm' => diameter_mm.to_f,
          'depth_mm' => depth_mm.to_f,
          'b_offset_mm' => @settings['b_offset'].to_f
        }.to_json)
      end

      def layer(name)
        @model.layers[name] || @model.layers.add(name)
      end

      def make_unique_if_needed(entity)
        definition = entity.definition
        if definition && definition.instances.length > 1 && entity.respond_to?(:make_unique)
          entity.make_unique
        end
        entity
      end

      def board_frame(entity)
        bounds = entity.definition.bounds
        raise 'Tấm không có BoundingBox hợp lệ.' unless bounds && bounds.valid?

        tr = full_transform(entity)
        raw_axes = [tr.xaxis, tr.yaxis, tr.zaxis]
        lengths = raw_axes.map(&:length)
        dimensions = [bounds.width.to_f * lengths[0], bounds.height.to_f * lengths[1], bounds.depth.to_f * lengths[2]]
        axis_index = (0..2).min_by { |index| dimensions[index] }

        axis = raw_axes[axis_index].clone
        raise 'Tấm có phép biến đổi không hợp lệ.' if axis.length < 0.000001
        axis.normalize!

        {
          center: bounds.center.transform(tr),
          normal: axis,
          corners: (0..7).map { |index| bounds.corner(index).transform(tr) },
          thickness: dimensions[axis_index]
        }
      end

      def full_transform(entity)
        tr = Geom::Transformation.new
        Array(@model.active_path).each { |instance| tr = tr * instance.transformation }
        tr * entity.transformation
      end

      def active_entities
        @model.active_entities.to_a
      end

      def pick_container(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)
        path = helper.path_at(0)
        return nil unless path

        allowed = active_entities
        path.reverse.find do |entity|
          valid_container?(entity) && allowed.include?(entity)
        end
      rescue StandardError
        nil
      end

      def valid_container?(entity)
        entity && entity.valid? &&
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
      rescue StandardError
        false
      end

      def display_name(entity)
        name = entity.name.to_s.strip
        if name.empty? && entity.is_a?(Sketchup::ComponentInstance)
          name = entity.definition.name.to_s.strip
        end
        name.empty? ? (entity.is_a?(Sketchup::Group) ? 'Group' : 'Component') : name
      end

      def projection(points, axis)
        values = points.map { |point| scalar(point, axis) }
        [values.min, values.max]
      end

      def scalar(point, axis)
        point.x.to_f * axis.x.to_f + point.y.to_f * axis.y.to_f + point.z.to_f * axis.z.to_f
      end

      def point_from_basis(axis_a, scalar_a, axis_b, scalar_b, axis_c, scalar_c)
        Geom::Point3d.new(
          axis_a.x * scalar_a + axis_b.x * scalar_b + axis_c.x * scalar_c,
          axis_a.y * scalar_a + axis_b.y * scalar_b + axis_c.y * scalar_c,
          axis_a.z * scalar_a + axis_b.z * scalar_b + axis_c.z * scalar_c
        )
      end

      def scaled(vector, amount)
        Geom::Vector3d.new(vector.x * amount, vector.y * amount, vector.z * amount)
      end

      def mm(value)
        value.to_f.mm.to_f
      end

      def plane_axes(normal)
        reference = normal.z.abs < 0.85 ? Z_AXIS : X_AXIS
        u = normal.cross(reference)
        reference = Y_AXIS if u.length < 0.001
        u = normal.cross(reference) if u.length < 0.001
        u.normalize!
        v = normal.cross(u)
        v.normalize!
        [u, v]
      end

      def circle_points(center, normal, radius, segments)
        u, v = plane_axes(normal)
        Array.new(segments) do |index|
          angle = Math::PI * 2.0 * index.to_f / segments.to_f
          center + scaled(u, Math.cos(angle) * radius) + scaled(v, Math.sin(angle) * radius)
        end
      end

      def draw_box(view, entity, color, width)
        return unless valid_container?(entity)
        frame = board_frame(entity)
        corners = frame[:corners]
        pairs = [
          [0,1],[1,3],[3,2],[2,0],
          [4,5],[5,7],[7,6],[6,4],
          [0,4],[1,5],[2,6],[3,7]
        ]
        points = pairs.flat_map { |a, b| [corners[a], corners[b]] }
        view.drawing_color = color
        view.line_width = width
        view.draw(GL_LINES, points)
      rescue StandardError
      end
    end
  end
end

module TranTuanNoiThat
  module CamChot
    def self.format_number(value)
      text = format('%.2f', value.to_f)
      text.sub!(/\.00\z/, '')
      text.sub!(/(\.\d)0\z/, '\\1')
      text
    end
  end
end
