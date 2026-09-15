# encoding: UTF-8
module TranTuanNoiThat
  module Box
    extend self

    VERSION = '1.1.0'.freeze unless const_defined?(:VERSION, false)

    def show_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - TẠO KHỐI BOX',
        preferences_key: 'TranTuanNoiThat.Box',
        scrollable: false,
        resizable: false,
        width: 430,
        height: 490,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('create_box') do |_context, json|
        begin
          data = JSON.parse(json)
          width = data.fetch('width').to_f
          depth = data.fetch('depth').to_f
          height = data.fetch('height').to_f
          mode = data['mode'].to_s == 'frame' ? :frame : :solid
          raise 'Cao, rộng và sâu phải lớn hơn 0 mm.' unless width > 0 && depth > 0 && height > 0

          save_defaults(width, depth, height, mode)
          @dialog.close
          Sketchup.active_model.select_tool(Tool.new(width.mm, depth.mm, height.mm, mode))
        rescue StandardError => error
          @dialog.execute_script("notice(#{JSON.generate(error.message)})")
        end
      end
      @dialog.show
    end

    def save_defaults(width, depth, height, mode)
      TranTuanNoiThat.save_setting('box_width', width)
      TranTuanNoiThat.save_setting('box_depth', depth)
      TranTuanNoiThat.save_setting('box_height', height)
      TranTuanNoiThat.save_setting('box_mode', mode.to_s)
    end

    def dialog_html
      width = TranTuanNoiThat.setting('box_width', 600.0).to_f
      depth = TranTuanNoiThat.setting('box_depth', 400.0).to_f
      height = TranTuanNoiThat.setting('box_height', 720.0).to_f
      mode = TranTuanNoiThat.setting('box_mode', 'solid').to_s
      solid_checked = mode == 'frame' ? '' : 'checked'
      frame_checked = mode == 'frame' ? 'checked' : ''
      <<~HTML
        <!doctype html><html><head><meta charset="UTF-8"><style>
        *{box-sizing:border-box} body{margin:0;background:#151515;color:#f5f5f5;font:14px Arial;padding:22px}
        h2{margin:0 0 5px;color:#ff8a22} .sub{color:#aaa;margin-bottom:18px}
        label.title{display:block;margin:12px 0 6px;font-weight:bold} input[type=number]{width:100%;padding:11px;border:1px solid #444;border-radius:7px;background:#242424;color:white;font-size:15px}
        .modes{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:8px}.mode{padding:13px;border:1px solid #444;border-radius:8px;background:#222}
        button{width:100%;margin-top:22px;padding:13px;border:0;border-radius:8px;background:#f47b20;color:white;font-size:16px;font-weight:bold;cursor:pointer}
        #msg{height:18px;color:#ff6767;margin-top:10px}
        </style></head><body>
        <h2>TẠO KHỐI BOX</h2><div class="sub">TRẦN TUẤN NỘI THẤT · SHIFT xoay hướng khi đặt BOX</div>
        <label class="title">Cao (mm)</label><input id="height" type="number" min="0.1" step="0.1" value="#{height}">
        <label class="title">Rộng (mm)</label><input id="width" type="number" min="0.1" step="0.1" value="#{width}">
        <label class="title">Sâu (mm)</label><input id="depth" type="number" min="0.1" step="0.1" value="#{depth}">
        <label class="title">Kiểu BOX</label><div class="modes">
          <label class="mode"><input type="radio" name="mode" value="solid" #{solid_checked}> Khối đặc</label>
          <label class="mode"><input type="radio" name="mode" value="frame" #{frame_checked}> Tạo khung</label>
        </div>
        <button onclick="createBox()">TẠO BOX</button><div id="msg"></div>
        <script>
        function createBox(){
          const mode=document.querySelector('input[name=mode]:checked').value;
          sketchup.create_box(JSON.stringify({
            height:document.getElementById('height').value,
            width:document.getElementById('width').value,
            depth:document.getElementById('depth').value,
            mode:mode
          }));
        }
        function notice(text){document.getElementById('msg').textContent=text}
        </script></body></html>
      HTML
    end

    class Tool
      FACE = Sketchup::Color.new(255, 164, 70, 75)
      EDGE = Sketchup::Color.new(235, 92, 0, 255)
      TEXT = Sketchup::Color.new(255, 130, 20, 255)

      def initialize(width, depth, height, mode)
        @width = width
        @depth = depth
        @height = height
        @mode = mode
        @ip = Sketchup::InputPoint.new
        @origin = nil
        @rotation_index = 0
        @shift_down = false
      end

      def activate
        update_status
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @origin = @ip.valid? ? @ip.position : nil
        view.tooltip = @ip.tooltip if @ip.valid?
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @ip.pick(view, x, y)
        return UI.beep unless @ip.valid?
        @origin = @ip.position
        create_box
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless shift_key?(key)
        return if @shift_down

        @shift_down = true
        @rotation_index = (@rotation_index + 1) % 4
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT BOX SHIFT] #{error.class}: #{error.message}"
      end

      def onKeyUp(key, _repeat, _flags, _view)
        @shift_down = false if shift_key?(key)
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.display?
        return unless @origin

        points = corners(@origin)
        view.line_width = 3
        view.drawing_color = EDGE
        view.draw(GL_LINES, edge_lines(points))

        unless @mode == :frame
          view.drawing_color = FACE
          faces(points).each { |face| view.draw(GL_QUADS, face) }
        end

        draw_direction_label(view, points)
      end

      def getExtents
        box = Geom::BoundingBox.new
        corners(@origin).each { |point| box.add(point) } if @origin
        box
      end

      private

      def shift_key?(key)
        key == 16 || (defined?(VK_SHIFT) && key == VK_SHIFT)
      end

      def rotation_degrees
        @rotation_index * 90
      end

      def plan_vectors
        case @rotation_index
        when 1
          [Geom::Vector3d.new(0, @width, 0), Geom::Vector3d.new(-@depth, 0, 0)]
        when 2
          [Geom::Vector3d.new(-@width, 0, 0), Geom::Vector3d.new(0, -@depth, 0)]
        when 3
          [Geom::Vector3d.new(0, -@width, 0), Geom::Vector3d.new(@depth, 0, 0)]
        else
          [Geom::Vector3d.new(@width, 0, 0), Geom::Vector3d.new(0, @depth, 0)]
        end
      end

      def corners(origin)
        x, y = plan_vectors
        z = Geom::Vector3d.new(0, 0, @height)
        p0 = origin
        p1 = origin.offset(x)
        p3 = origin.offset(y)
        p2 = p1.offset(y)
        [p0, p1, p2, p3, p0.offset(z), p1.offset(z), p2.offset(z), p3.offset(z)]
      end

      def edge_lines(p)
        pairs = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
        pairs.flat_map { |a, b| [p[a], p[b]] }
      end

      def faces(p)
        [[p[0],p[1],p[2],p[3]],[p[4],p[7],p[6],p[5]],[p[0],p[4],p[5],p[1]],
         [p[1],p[5],p[6],p[2]],[p[2],p[6],p[7],p[3]],[p[3],p[7],p[4],p[0]]]
      end

      def draw_direction_label(view, points)
        center = Geom::Point3d.new(
          points.map(&:x).sum / points.length.to_f,
          points.map(&:y).sum / points.length.to_f,
          points.map(&:z).sum / points.length.to_f
        )
        screen = view.screen_coords(center)
        label = "SHIFT XOAY · #{rotation_degrees}°"
        begin
          view.draw_text(
            Geom::Point3d.new(screen.x + 12, screen.y - 18, 0),
            label,
            size: 14,
            bold: true,
            color: TEXT
          )
        rescue StandardError
          view.drawing_color = TEXT
          view.draw_text(Geom::Point3d.new(screen.x + 12, screen.y - 18, 0), label)
        end
      rescue StandardError
        nil
      end

      def update_status
        Sketchup.status_text = "TẠO BOX: Di chuột chọn vị trí · SHIFT xoay 90° (hiện #{rotation_degrees}°) · Click tạo · ESC thoát."
      end

      def create_box
        model = Sketchup.active_model
        model.start_operation('TRẦN TUẤN - Tạo Khối BOX', true)
        group = model.active_entities.add_group
        if @mode == :solid
          p = corners(@origin)
          face = group.entities.add_face(p[0], p[1], p[2], p[3])
          raise 'Không tạo được mặt BOX.' unless face && face.valid?
          face.reverse! if face.normal.dot(Z_AXIS) < 0
          face.pushpull(@height)
        else
          p = corners(@origin)
          edge_lines(p).each_slice(2) { |a, b| group.entities.add_line(a, b) }
        end

        group.name = @mode == :solid ? 'TT_BOX_DAC' : 'TT_BOX_KHUNG'
        dict = 'TRẦN TUẤN NỘI THẤT'
        group.set_attribute(dict, 'loai', @mode == :solid ? 'BOX_DAC' : 'BOX_KHUNG')
        group.set_attribute(dict, 'rong_mm', @width.to_mm)
        group.set_attribute(dict, 'sau_mm', @depth.to_mm)
        group.set_attribute(dict, 'cao_mm', @height.to_mm)
        group.set_attribute(dict, 'huong_xoay_do', rotation_degrees)
        group.set_attribute(dict, 'box_version', VERSION)

        model.commit_operation
        model.selection.clear
        model.selection.add(group)
      rescue StandardError => error
        model.abort_operation if model
        UI.messagebox("Lỗi tạo BOX:\n#{error.message}")
      end
    end
  end
end
