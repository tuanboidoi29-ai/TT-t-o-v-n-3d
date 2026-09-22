# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - TẠO CÁNH CHUẨN
# SketchUp 2021+
#
# Cơ chế:
# - Rê chuột lên Face/khoang: tự nhận mặt và hệ trục.
# - Tự bắt 2 mép ngoài + 1 trung điểm làm tâm chia cánh.
# - Preview 3D cánh cập nhật liên tục theo chuột.
# - Click tạo cánh thật; tool tiếp tục để tạo khoang kế tiếp.
# - TAB mở thông số; SHIFT đổi hướng dày cánh ra/vào.
# - Chia 1..8 cánh theo Dọc hoặc Ngang.
# - Một lần click tạo = một Undo.

require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module DoorStandard
    extend self

    VERSION = '1.9.129'.freeze
    DICT = 'TT_DOOR_STANDARD'.freeze
    SETTINGS_KEY = 'door_standard_settings_v1'.freeze

    DEFAULTS = {
      'fit_mode' => 'Lọt lòng',
      'split_direction' => 'Dọc',
      'door_count' => 2,
      'thickness' => 17.5,
      'gap_left' => 2.0,
      'gap_right' => 2.0,
      'gap_top' => 2.0,
      'gap_bottom' => 2.0,
      'gap_middle' => 2.0,
      'over_left' => 0.0,
      'over_right' => 0.0,
      'over_top' => 0.0,
      'over_bottom' => 0.0,
      'offset' => 0.0,
      'name_prefix' => 'Cánh',
      'preview_alpha' => 88
    }.freeze

    def settings
      raw = Sketchup.read_default(TranTuanNoiThat::NAME, SETTINGS_KEY, '{}').to_s
      parsed = JSON.parse(raw)
      validate(DEFAULTS.merge(parsed.is_a?(Hash) ? parsed : {}))
    rescue StandardError
      DEFAULTS.dup
    end

    def save_settings(value)
      clean = validate(value)
      Sketchup.write_default(TranTuanNoiThat::NAME, SETTINGS_KEY, JSON.generate(clean))
      clean
    end

    def validate(raw)
      source = DEFAULTS.merge(raw || {})
      result = {}

      fit = source['fit_mode'].to_s
      raise 'Lắp đặt chỉ nhận Lọt lòng hoặc Phủ ngoài.' unless ['Lọt lòng', 'Phủ ngoài'].include?(fit)
      result['fit_mode'] = fit

      direction = source['split_direction'].to_s
      raise 'Hướng chia chỉ nhận Dọc hoặc Ngang.' unless ['Dọc', 'Ngang'].include?(direction)
      result['split_direction'] = direction

      count = source['door_count'].to_i
      raise 'Số cánh phải từ 1 đến 8.' unless count.between?(1, 8)
      result['door_count'] = count

      %w[
        thickness gap_left gap_right gap_top gap_bottom gap_middle
        over_left over_right over_top over_bottom
      ].each do |key|
        value = Float(source[key].to_s.tr(',', '.'))
        raise "#{key} phải >= 0." if value < 0.0
        raise "#{key} quá lớn." if value > 10_000.0
        result[key] = value
      end

      offset = Float(source['offset'].to_s.tr(',', '.'))
      raise 'Offset quá lớn.' if offset.abs > 10_000.0
      result['offset'] = offset

      raise 'Dày cánh phải > 0.' unless result['thickness'] > 0.0

      prefix = source['name_prefix'].to_s.strip
      prefix = 'Cánh' if prefix.empty?
      raise 'Tên cánh tối đa 60 ký tự.' if prefix.length > 60
      result['name_prefix'] = prefix

      alpha = source['preview_alpha'].to_i
      alpha = 20 if alpha < 20
      alpha = 180 if alpha > 180
      result['preview_alpha'] = alpha

      result
    rescue ArgumentError, TypeError
      raise 'Thông số cánh không hợp lệ.'
    end

    def activate
      tool = Tool.new(settings)
      @active_tool = tool
      Sketchup.active_model.select_tool(tool)
      tool
    end

    def show_settings(tool = nil)
      @active_tool = tool if tool
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        send_settings
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - TẠO CÁNH CHUẨN',
        preferences_key: 'TranTuanNoiThat.DoorStandard.129',
        scrollable: true,
        resizable: true,
        width: 470,
        height: 690,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(settings_html)
      @dialog.add_action_callback('ready') { |_ctx| send_settings }
      @dialog.add_action_callback('apply') do |_ctx, payload|
        begin
          data = JSON.parse(payload.to_s)
          clean = save_settings(data)
          @active_tool.update_settings(clean) if @active_tool && @active_tool.respond_to?(:update_settings)
          send_settings
          @dialog.execute_script("TT.notice('Đã áp dụng thông số vào preview hiện tại.', false);")
        rescue StandardError => error
          @dialog.execute_script("TT.notice(#{JSON.generate(error.message)}, true);")
        end
      end
      @dialog.add_action_callback('reset') do |_ctx|
        clean = save_settings(DEFAULTS)
        @active_tool.update_settings(clean) if @active_tool && @active_tool.respond_to?(:update_settings)
        send_settings
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    rescue StandardError => error
      UI.messagebox("Không mở được thông số Tạo Cánh Chuẩn:\n#{error.message}")
    end

    def send_settings
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("TT.load(#{JSON.generate(settings)});")
    rescue StandardError
    end

    def settings_html
      <<~'HTML'
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8">
          <style>
            *{box-sizing:border-box}
            body{margin:0;background:#f3f6f9;color:#172033;font:13px Arial,sans-serif}
            .head{padding:14px 16px;background:#172033;color:white;position:sticky;top:0;z-index:2}
            .head h2{margin:0;font-size:18px}.head small{opacity:.78}
            .wrap{padding:12px}.card{background:#fff;border:1px solid #d7dfe8;border-radius:10px;padding:12px;margin-bottom:10px}
            .grid{display:grid;grid-template-columns:1fr 130px 34px;gap:7px;align-items:center}
            label{font-weight:bold} input,select{width:100%;padding:8px;border:1px solid #b9c4d1;border-radius:6px}
            .row{display:flex;gap:8px;flex-wrap:wrap}.row button{flex:1}
            button{border:0;border-radius:7px;padding:9px 12px;background:#176fd1;color:#fff;font-weight:bold;cursor:pointer}
            button.gray{background:#667085}.hint{font-size:12px;color:#667085;line-height:1.55}
            #notice{display:none;margin-top:9px;padding:9px;border-radius:6px}
            #notice.ok{display:block;background:#e7f7ed;color:#166534}
            #notice.err{display:block;background:#fde8e8;color:#9b1c1c}
          </style>
        </head>
        <body>
          <div class="head"><h2>TẠO CÁNH CHUẨN</h2><small>Preview 3D theo chuột · click tạo liên tục</small></div>
          <div class="wrap">
            <div class="card">
              <div class="grid">
                <label>Lắp đặt</label><select id="fit"><option>Lọt lòng</option><option>Phủ ngoài</option></select><span></span>
                <label>Hướng chia</label><select id="dir"><option>Dọc</option><option>Ngang</option></select><span></span>
                <label>Số cánh</label><input id="count" type="number" min="1" max="8" step="1"><span>cánh</span>
                <label>Dày cánh</label><input id="thickness" type="number" step="0.5"><span>mm</span>
                <label>Khe giữa</label><input id="gap_middle" type="number" step="0.5"><span>mm</span>
                <label>Nhô (+) / lùi (-)</label><input id="offset" type="number" step="0.5"><span>mm</span>
                <label>Tên cánh</label><input id="name_prefix"><span></span>
              </div>
            </div>

            <div class="card">
              <b>Hở lọt lòng</b>
              <div class="grid" style="margin-top:9px">
                <label>Trái</label><input id="gap_left" type="number" step="0.5"><span>mm</span>
                <label>Phải</label><input id="gap_right" type="number" step="0.5"><span>mm</span>
                <label>Trên</label><input id="gap_top" type="number" step="0.5"><span>mm</span>
                <label>Dưới</label><input id="gap_bottom" type="number" step="0.5"><span>mm</span>
              </div>
            </div>

            <div class="card">
              <b>Phủ ngoài</b>
              <div class="grid" style="margin-top:9px">
                <label>Phủ trái</label><input id="over_left" type="number" step="0.5"><span>mm</span>
                <label>Phủ phải</label><input id="over_right" type="number" step="0.5"><span>mm</span>
                <label>Phủ trên</label><input id="over_top" type="number" step="0.5"><span>mm</span>
                <label>Phủ dưới</label><input id="over_bottom" type="number" step="0.5"><span>mm</span>
              </div>
            </div>

            <div class="card">
              <div class="row"><button onclick="apply()">ÁP DỤNG</button><button class="gray" onclick="sketchup.reset()">MẶC ĐỊNH</button></div>
              <div class="hint" style="margin-top:10px">
                Rê chuột lên mặt khoang: tool tự nhận hai mép ngoài và tâm chia. Click tạo cánh rồi tiếp tục rê sang khoang khác.
                <b>TAB</b> mở bảng này. <b>SHIFT</b> đảo hướng dày cánh ra/vào.
              </div>
              <div id="notice"></div>
            </div>
          </div>
          <script>
            const ids=['fit','dir','count','thickness','gap_middle','offset','name_prefix',
              'gap_left','gap_right','gap_top','gap_bottom','over_left','over_right','over_top','over_bottom'];
            const TT={
              load(s){
                fit.value=s.fit_mode;dir.value=s.split_direction;count.value=s.door_count;
                thickness.value=s.thickness;gap_middle.value=s.gap_middle;offset.value=s.offset;name_prefix.value=s.name_prefix;
                gap_left.value=s.gap_left;gap_right.value=s.gap_right;gap_top.value=s.gap_top;gap_bottom.value=s.gap_bottom;
                over_left.value=s.over_left;over_right.value=s.over_right;over_top.value=s.over_top;over_bottom.value=s.over_bottom;
              },
              notice(text,error){
                const e=document.getElementById('notice');e.className=error?'err':'ok';e.textContent=text;
              }
            };
            function apply(){
              const s={
                fit_mode:fit.value,split_direction:dir.value,door_count:Number(count.value),
                thickness:Number(thickness.value),gap_middle:Number(gap_middle.value),offset:Number(offset.value),
                name_prefix:name_prefix.value,gap_left:Number(gap_left.value),gap_right:Number(gap_right.value),
                gap_top:Number(gap_top.value),gap_bottom:Number(gap_bottom.value),
                over_left:Number(over_left.value),over_right:Number(over_right.value),
                over_top:Number(over_top.value),over_bottom:Number(over_bottom.value)
              };
              sketchup.apply(JSON.stringify(s));
            }
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body></html>
      HTML
    end

    class Tool
      def initialize(options)
        @model = Sketchup.active_model
        @options = DoorStandard.validate(options)
        @region = nil
        @doors = []
        @flip = false
        @last_mouse = nil
      end

      def activate
        Sketchup.status_text = 'TẠO CÁNH CHUẨN · rê chuột lên Face/khoang để tự nhận · click tạo · TAB thông số · SHIFT đảo hướng dày.'
        @model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def update_settings(options)
        @options = DoorStandard.validate(options)
        rebuild_preview
        @model.active_view.invalidate
        true
      rescue StandardError => error
        UI.messagebox(error.message)
        false
      end

      def onCancel(_reason, view)
        @model.select_tool(nil)
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        if key == 9
          DoorStandard.show_settings(self)
          return
        end

        if key == 16
          @flip = !@flip
          rebuild_preview
          Sketchup.status_text = @flip ? 'Hướng dày: VÀO trong. SHIFT để đổi.' : 'Hướng dày: RA ngoài. SHIFT để đổi.'
          view.invalidate
        end
      rescue StandardError
      end

      def onMouseMove(_flags, x, y, view)
        @last_mouse = [x, y]
        region = detect_region(view, x, y)
        if region
          @region = region
          rebuild_preview
          view.tooltip = "Khoang #{format_mm(region[:width])} × #{format_mm(region[:height])} mm · #{@options['door_count']} cánh"
        else
          @region = nil
          @doors = []
        end
        view.invalidate
      rescue StandardError => error
        @region = nil
        @doors = []
        puts "[TT DoorStandard move] #{error.class}: #{error.message}"
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @region ||= detect_region(view, x, y)
        unless @region && !@doors.empty?
          UI.beep
          return
        end
        create_doors
        # Giữ tool chạy liên tục, preview sẽ tự bắt khoang kế tiếp khi chuột di chuyển.
        @region = nil
        @doors = []
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Không tạo được cánh:\n#{error.message}")
      end

      def draw(view)
        return unless @region && !@doors.empty?

        draw_detected_guides(view)
        @doors.each do |door|
          draw_door(view, door)
        end
        draw_info(view)
      rescue StandardError => error
        puts "[TT DoorStandard draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @doors.each { |door| door[:corners].each { |point| bb.add(point) } }
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def detect_region(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)
        path = helper.path_at(0)
        return nil unless path

        face = path.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
        return nil unless face

        transform = if helper.respond_to?(:transformation_at)
          helper.transformation_at(0)
        else
          Geom::Transformation.new
        end

        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
        return nil if points.length < 3

        normal = face.normal.transform(transform)
        return nil if normal.length < 0.000001
        normal.normalize!

        # Tự chọn phía hướng về camera làm phía mặt cánh.
        camera_dir = view.camera.direction
        normal.reverse! if normal.dot(camera_dir) > 0.0

        origin = average_point(points)
        vertical = project_vector_to_plane(Z_AXIS, normal)

        if vertical.length < 0.1
          vertical = project_vector_to_plane(Y_AXIS, normal)
          vertical = project_vector_to_plane(X_AXIS, normal) if vertical.length < 0.1
        end
        return nil if vertical.length < 0.000001
        vertical.normalize!
        vertical.reverse! if vertical.dot(Z_AXIS) < -0.01

        horizontal = vertical.cross(normal)
        return nil if horizontal.length < 0.000001
        horizontal.normalize!

        # Đảm bảo trục ngang đi từ trái sang phải trên màn hình.
        c_screen = view.screen_coords(origin)
        h_screen = view.screen_coords(origin.offset(horizontal, 100.mm))
        horizontal.reverse! if h_screen.x < c_screen.x

        # Tái tạo vertical để bảo đảm trực giao sau khi đảo horizontal.
        vertical = normal.cross(horizontal)
        vertical.normalize!
        vertical.reverse! if vertical.dot(Z_AXIS) < -0.01

        us = points.map { |point| vector_between(origin, point).dot(horizontal) }
        vs = points.map { |point| vector_between(origin, point).dot(vertical) }
        u0, u1 = us.minmax
        v0, v1 = vs.minmax
        width = u1 - u0
        height = v1 - v0
        return nil if width < 20.mm || height < 20.mm

        {
          face: face,
          origin: origin,
          normal: normal,
          u: horizontal,
          v: vertical,
          u0: u0,
          u1: u1,
          v0: v0,
          v1: v1,
          width: width,
          height: height
        }
      rescue StandardError
        nil
      end

      def average_point(points)
        sx = points.inject(0.0) { |sum, point| sum + point.x }
        sy = points.inject(0.0) { |sum, point| sum + point.y }
        sz = points.inject(0.0) { |sum, point| sum + point.z }
        Geom::Point3d.new(sx / points.length, sy / points.length, sz / points.length)
      end

      def vector_between(a, b)
        Geom::Vector3d.new(b.x - a.x, b.y - a.y, b.z - a.z)
      end

      def project_vector_to_plane(vector, normal)
        dot = vector.dot(normal)
        Geom::Vector3d.new(
          vector.x - normal.x * dot,
          vector.y - normal.y * dot,
          vector.z - normal.z * dot
        )
      end

      def adjusted_bounds
        r = @region
        if @options['fit_mode'] == 'Phủ ngoài'
          [
            r[:u0] - @options['over_left'].mm,
            r[:u1] + @options['over_right'].mm,
            r[:v0] - @options['over_bottom'].mm,
            r[:v1] + @options['over_top'].mm
          ]
        else
          [
            r[:u0] + @options['gap_left'].mm,
            r[:u1] - @options['gap_right'].mm,
            r[:v0] + @options['gap_bottom'].mm,
            r[:v1] - @options['gap_top'].mm
          ]
        end
      end

      def rebuild_preview
        @doors = []
        return unless @region

        u0, u1, v0, v1 = adjusted_bounds
        raise 'Khoang quá nhỏ sau khi trừ khe hở/phủ.' unless u1 > u0 && v1 > v0

        count = @options['door_count']
        gap = @options['gap_middle'].mm
        normal = @flip ? @region[:normal].reverse : @region[:normal]
        offset_vector = @region[:normal].clone
        offset_vector.length = @options['offset'].mm.abs if @options['offset'].abs > 0.0001
        offset_vector.reverse! if @options['offset'] < 0
        thickness_vector = normal.clone
        thickness_vector.length = @options['thickness'].mm

        if @options['split_direction'] == 'Dọc'
          available = (u1 - u0) - gap * (count - 1)
          raise 'Khe giữa quá lớn so với chiều rộng khoang.' unless available > 0
          size = available / count.to_f

          count.times do |index|
            a = u0 + index * (size + gap)
            b = a + size
            @doors << build_box(a, b, v0, v1, offset_vector, thickness_vector, index)
          end
        else
          available = (v1 - v0) - gap * (count - 1)
          raise 'Khe giữa quá lớn so với chiều cao khoang.' unless available > 0
          size = available / count.to_f

          count.times do |index|
            a = v0 + index * (size + gap)
            b = a + size
            @doors << build_box(u0, u1, a, b, offset_vector, thickness_vector, index)
          end
        end
      rescue StandardError => error
        @doors = []
        Sketchup.status_text = "Tạo Cánh Chuẩn: #{error.message}"
      end

      def point_on_plane(u_value, v_value)
        point = @region[:origin].offset(@region[:u], u_value)
        point.offset(@region[:v], v_value)
      end

      def build_box(u0, u1, v0, v1, offset_vector, thickness_vector, index)
        front = [
          point_on_plane(u0, v0),
          point_on_plane(u1, v0),
          point_on_plane(u1, v1),
          point_on_plane(u0, v1)
        ]
        front = front.map { |point| point.offset(offset_vector) } if offset_vector.length > 0.0
        back = front.map { |point| point.offset(thickness_vector) }
        {
          index: index,
          front: front,
          back: back,
          corners: front + back,
          width: (u1 - u0).abs,
          height: (v1 - v0).abs
        }
      end

      def draw_door(view, door)
        alpha = @options['preview_alpha']
        front = door[:front]
        back = door[:back]

        view.drawing_color = Sketchup::Color.new(255, 191, 128, alpha)
        view.draw(GL_QUADS, front)
        view.drawing_color = Sketchup::Color.new(245, 153, 76, [alpha + 30, 210].min)
        view.draw(GL_QUADS, back)

        sides = [
          [front[0], front[1], back[1], back[0]],
          [front[1], front[2], back[2], back[1]],
          [front[2], front[3], back[3], back[2]],
          [front[3], front[0], back[0], back[3]]
        ]
        view.drawing_color = Sketchup::Color.new(241, 168, 96, [alpha + 15, 210].min)
        sides.each { |quad| view.draw(GL_QUADS, quad) }

        edges = [
          [front[0],front[1]],[front[1],front[2]],[front[2],front[3]],[front[3],front[0]],
          [back[0],back[1]],[back[1],back[2]],[back[2],back[3]],[back[3],back[0]],
          [front[0],back[0]],[front[1],back[1]],[front[2],back[2]],[front[3],back[3]]
        ]
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(198, 103, 32)
        view.draw(GL_LINES, edges.flatten(1))
      end

      def draw_detected_guides(view)
        u0, u1, v0, v1 = adjusted_bounds

        if @options['split_direction'] == 'Dọc'
          edge1 = [point_on_plane(u0, v0), point_on_plane(u0, v1)]
          edge2 = [point_on_plane(u1, v0), point_on_plane(u1, v1)]
          center = point_on_plane((u0 + u1) * 0.5, (v0 + v1) * 0.5)
        else
          edge1 = [point_on_plane(u0, v0), point_on_plane(u1, v0)]
          edge2 = [point_on_plane(u0, v1), point_on_plane(u1, v1)]
          center = point_on_plane((u0 + u1) * 0.5, (v0 + v1) * 0.5)
        end

        view.line_width = 5
        view.drawing_color = Sketchup::Color.new(37, 99, 235)
        view.draw(GL_LINES, edge1)
        view.draw(GL_LINES, edge2)

        view.draw_points(center, 14, 2, Sketchup::Color.new(234, 88, 12))

        screen = view.screen_coords(center)
        view.draw_text(
          [screen.x + 10, screen.y - 15],
          @options['door_count'] == 2 ? 'TÂM CHIA 2 CÁNH' : 'TÂM KHOANG',
          color: Sketchup::Color.new(170, 65, 10)
        )
      end

      def draw_info(view)
        center = @region[:origin]
        screen = view.screen_coords(center)
        text = "#{@options['door_count']} CÁNH · #{format_mm(@region[:width])} × #{format_mm(@region[:height])} mm · #{@options['fit_mode']}"
        view.draw_text(
          [screen.x + 18, screen.y + 18],
          text,
          color: Sketchup::Color.new(24, 62, 104)
        )
      rescue StandardError
      end

      def create_doors
        raise 'Chưa nhận được khoang.' unless @region
        raise 'Preview cánh chưa hợp lệ.' if @doors.empty?

        model = @model
        model.start_operation('TT - Tạo Cánh Chuẩn', true)
        started = true

        root = model.active_entities.add_group
        root.name = "Cánh tủ #{@options['door_count']} cánh"
        root.set_attribute(DICT, 'version', VERSION)
        root.set_attribute(DICT, 'settings_json', JSON.generate(@options))
        source_pid = begin
          @region[:face].respond_to?(:persistent_id) ? @region[:face].persistent_id : 0
        rescue StandardError
          0
        end
        root.set_attribute(DICT, 'source_face_pid', source_pid)

        inverse_edit = model.edit_transform.inverse
        tag_name = "Ván #{format('%.1f', @options['thickness']).sub('.0','')}mm"
        board_tag = model.layers[tag_name] || model.layers.add(tag_name)

        created = []
        @doors.each_with_index do |door, index|
          child = root.entities.add_group
          child.name = format('%s %02d', @options['name_prefix'], index + 1)
          child.layer = board_tag
          child.set_attribute(DICT, 'is_door', true)
          child.set_attribute(DICT, 'index', index + 1)
          child.set_attribute(DICT, 'width_mm', door[:width].to_mm)
          child.set_attribute(DICT, 'height_mm', door[:height].to_mm)
          child.set_attribute(DICT, 'thickness_mm', @options['thickness'])

          front = door[:front].map { |point| point.transform(inverse_edit) }
          back = door[:back].map { |point| point.transform(inverse_edit) }
          entities = child.entities

          faces = []
          faces << entities.add_face(front)
          faces << entities.add_face(back.reverse)
          faces << entities.add_face(front[0], front[1], back[1], back[0])
          faces << entities.add_face(front[1], front[2], back[2], back[1])
          faces << entities.add_face(front[2], front[3], back[3], back[2])
          faces << entities.add_face(front[3], front[0], back[0], back[3])
          raise 'Không tạo được hình học cánh.' if faces.compact.length < 6

          created << child
        end

        model.selection.clear
        model.selection.add(root)
        model.commit_operation
        started = false

        Sketchup.status_text = "Đã tạo #{@doors.length} cánh · tiếp tục rê chuột sang khoang khác."
        root
      rescue StandardError
        model.abort_operation if started rescue nil
        raise
      end

      def format_mm(length)
        format('%.1f', length.to_mm).sub(/\.0\z/, '')
      end
    end
  end

  # Tương thích nóng cho UI::Command cũ trong phiên SketchUp đang mở.
  # Source Vẽ Cánh Tủ cũ đã bị gỡ; lệnh cũ nếu còn trên toolbar sẽ gọi tool mới.
  remove_const(:CabinetDoor) if const_defined?(:CabinetDoor, false)
  module CabinetDoor
    extend self

    def show_gallery
      TranTuanNoiThat::DoorStandard.activate
    end

    def show(tool = nil)
      if tool
        TranTuanNoiThat::DoorStandard.show_settings(tool)
      else
        TranTuanNoiThat::DoorStandard.activate
      end
    end
  end
end
