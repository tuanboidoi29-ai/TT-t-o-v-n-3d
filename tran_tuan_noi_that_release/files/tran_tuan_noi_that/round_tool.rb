# encoding: UTF-8
module TranTuanNoiThat
  module Round
    extend self

    ORANGE = Sketchup::Color.new(244, 123, 32, 210)
    FILL = Sketchup::Color.new(255, 151, 61, 75)
    ERROR = Sketchup::Color.new(230, 55, 55, 230)
    SEGMENTS = 18

    def activate
      diameter = TranTuanNoiThat.setting('round_diameter', 40.0).to_f
      @tool = Tool.new([diameter, 0.1].max.mm)
      Sketchup.active_model.select_tool(@tool)
      show_palette(@tool)
    end

    def show_palette(tool)
      @palette.close if @palette && @palette.visible?
      @palette = UI::HtmlDialog.new(
        dialog_title: 'BO CONG KHỐI', preferences_key: 'TranTuanNoiThat.Round',
        scrollable: false, resizable: false, width: 360, height: 245,
        style: UI::HtmlDialog::STYLE_UTILITY
      )
      @palette.set_html(palette_html(tool.mode, tool.diameter.to_mm))
      @palette.add_action_callback('set_mode') { |_c, value| tool.set_mode(value.to_s == 'concave' ? :concave : :convex) }
      @palette.add_action_callback('set_diameter') { |_c, value| tool.set_diameter_mm(value.to_f) }
      @palette.add_action_callback('close_tool') { |_c| Sketchup.active_model.select_tool(nil) }
      @palette.set_on_closed { @palette = nil }
      @palette.show
    end

    def close_palette
      @palette.close if @palette && @palette.visible?
      @palette = nil
    end

    def sync_palette(mode, diameter)
      return unless @palette && @palette.visible?
      @palette.execute_script("syncState(#{JSON.generate(mode.to_s)}, #{diameter.to_mm})")
    end

    def palette_html(mode, diameter)
      <<~HTML
        <!doctype html><html><head><meta charset="UTF-8"><style>
        *{box-sizing:border-box}body{margin:0;padding:16px;background:#242424;color:#fff;font:14px Arial}
        h3{margin:0 0 12px;color:#ff9a3d}.modes{display:grid;grid-template-columns:1fr 1fr;gap:8px}
        button{padding:12px 6px;border:2px solid #f47b20;border-radius:8px;background:#3a2a20;color:#ffb06b;font-weight:bold;cursor:pointer}
        button.active{background:#f47b20;color:#fff}.row{display:flex;align-items:center;gap:9px;margin-top:14px}
        input{min-width:0;flex:1;padding:9px;border:1px solid #f47b20;border-radius:6px;background:#171717;color:#fff}
        .hint{margin-top:12px;color:#ccc;font-size:12px;line-height:1.45}.close{margin-top:10px;width:100%;padding:7px;background:#333;border-color:#555}
        </style></head><body><h3>BO CONG KHỐI</h3><div class="modes">
        <button id="convex" onclick="mode('convex')">CUNG LỒI</button><button id="concave" onclick="mode('concave')">CUNG LÕM</button></div>
        <div class="row"><b>Đường kính</b><input id="diameter" type="number" min="0.1" step="0.1" value="#{diameter}" onchange="diameter()"><span>mm</span></div>
        <div class="hint">TAB: đổi chế độ · Gõ số: đổi đường kính<br>Di chuột vào đỉnh để xem trước, click để bo.</div>
        <button class="close" onclick="sketchup.close_tool()">ĐÓNG</button>
        <script>
        function mode(v){sketchup.set_mode(v)}
        function diameter(){sketchup.set_diameter(document.getElementById('diameter').value)}
        function syncState(m,d){document.getElementById('convex').classList.toggle('active',m==='convex');document.getElementById('concave').classList.toggle('active',m==='concave');document.getElementById('diameter').value=Number(d).toFixed(1)}
        syncState(#{JSON.generate(mode.to_s)},#{diameter});
        </script></body></html>
      HTML
    end

    class Tool
      attr_reader :mode, :diameter

      def initialize(diameter)
        @diameter = diameter
        @mode = :convex
        @ip = Sketchup::InputPoint.new
        @candidate = nil
      end

      def activate
        Sketchup.vcb_label = 'Đường kính'
        update_status
      end

      def deactivate(view)
        Round.close_palette
        view.invalidate
      end

      def resume(view)
        Sketchup.vcb_label = 'Đường kính'
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @candidate = build_candidate(@ip)
        view.tooltip = @candidate ? "#{label} - Ø#{fmt_mm(@diameter)} mm" : 'Đưa chuột sát một đỉnh thuộc mặt đang chỉnh sửa'
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @ip.pick(view, x, y)
        @candidate = build_candidate(@ip)
        return UI.beep unless @candidate && @candidate[:valid]
        apply_round(@candidate)
        @candidate = nil
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless key == 9
        set_mode(@mode == :convex ? :concave : :convex)
        view.invalidate
        true
      end

      def onUserText(text, view)
        length = Sketchup.parse_length(text)
        if length && length > 0
          @diameter = length
          TranTuanNoiThat.save_setting('round_diameter', @diameter.to_mm)
          @candidate = build_candidate(@ip)
          Round.sync_palette(@mode, @diameter)
          update_status
          view.invalidate
        else
          UI.beep
        end
      rescue StandardError
        UI.beep
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def set_mode(value)
        @mode = value
        @candidate = build_candidate(@ip)
        Round.sync_palette(@mode, @diameter)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def set_diameter_mm(value)
        return UI.beep unless value > 0
        @diameter = value.mm
        TranTuanNoiThat.save_setting('round_diameter', value)
        @candidate = build_candidate(@ip)
        Round.sync_palette(@mode, @diameter)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.display?
        return unless @candidate
        color = @candidate[:valid] ? Round::ORANGE : Round::ERROR
        points = @candidate[:world_points]
        if points && points.length > 2
          view.drawing_color = @candidate[:valid] ? Round::FILL : Round::ERROR
          view.draw(GL_POLYGON, points)
          view.drawing_color = color
          view.line_width = 4
          view.draw(GL_LINE_STRIP, points[1..-2])
          view.draw_points([@candidate[:world_vertex]], 10, 3, color)
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        @candidate[:world_points].each { |p| box.add(p) } if @candidate
        box
      end

      private

      def build_candidate(ip)
        return nil unless ip.valid? && ip.vertex && ip.face
        model = Sketchup.active_model
        face = ip.face
        return nil unless face.valid? && face.parent == model.active_entities
        vertices = face.outer_loop.vertices
        index = vertices.index(ip.vertex)
        return nil unless index
        vertex = vertices[index]
        prev_point = vertices[(index - 1) % vertices.length].position
        next_point = vertices[(index + 1) % vertices.length].position
        origin = vertex.position
        va = prev_point - origin
        vb = next_point - origin
        return nil if va.length < 0.001 || vb.length < 0.001
        angle = va.angle_between(vb)
        radius = @diameter / 2.0
        tangent = @mode == :convex ? radius / Math.tan(angle / 2.0) : radius
        valid = angle > 0.02 && angle < Math::PI - 0.02 && tangent > 0 && tangent < va.length * 0.98 && tangent < vb.length * 0.98
        tangent = [tangent, va.length * 0.95, vb.length * 0.95].min unless valid
        a = origin.offset(va.normalize, tangent)
        b = origin.offset(vb.normalize, tangent)
        arc = arc_points(origin, a, b, face.normal, radius, angle)
        points = [origin, a] + arc[1..-2] + [b]
        tr = model.edit_transform
        { face: face, vertex: vertex, local_points: points, world_points: points.map { |p| p.transform(tr) },
          world_vertex: origin.transform(tr), valid: valid, normal: face.normal }
      rescue StandardError
        nil
      end

      def arc_points(vertex, a, b, normal, radius, angle)
        if @mode == :concave
          center = vertex
        else
          ua = (a - vertex).normalize
          ub = (b - vertex).normalize
          bisector = (ua + ub).normalize
          center = vertex.offset(bisector, radius / Math.sin(angle / 2.0))
        end
        start = a - center
        finish = b - center
        signed = start.angle_between(finish)
        sign = start.cross(finish).dot(normal) >= 0 ? 1.0 : -1.0
        signed *= sign
        if @mode == :convex
          mid = start.transform(Geom::Transformation.rotation(ORIGIN, normal, signed / 2.0))
          alt = signed > 0 ? signed - 2.0 * Math::PI : signed + 2.0 * Math::PI
          alt_mid = start.transform(Geom::Transformation.rotation(ORIGIN, normal, alt / 2.0))
          signed = alt if center.offset(alt_mid).distance(vertex) < center.offset(mid).distance(vertex)
        end
        (0..Round::SEGMENTS).map do |i|
          vector = start.transform(Geom::Transformation.rotation(ORIGIN, normal, signed * i / Round::SEGMENTS.to_f))
          center.offset(vector)
        end
      end

      def apply_round(data)
        model = Sketchup.active_model
        entities = model.active_entities
        model.start_operation("TRẦN TUẤN - #{label}", true)
        before = entities.grep(Sketchup::Face)
        curve = data[:local_points][1..-2]
        entities.add_edges(curve)
        candidates = data[:vertex].faces.select { |f| f.valid? && f.normal.parallel?(data[:normal]) }
        cut_face = candidates.reject { |f| before.include?(f) }.min_by(&:area)
        cut_face ||= candidates.min_by(&:area)
        raise 'Không tách được vùng bo cong tại góc này.' unless cut_face && cut_face.valid?
        depth = solid_depth(cut_face, data[:normal])
        if depth && depth > 0.1.mm
          cut_face.pushpull(-depth)
        else
          entities.erase_entities(cut_face)
        end
        model.commit_operation
      rescue StandardError => error
        model.abort_operation if model
        UI.messagebox("Không thể bo cong:\n#{error.message}")
      end

      def solid_depth(face, normal)
        model = Sketchup.active_model
        tr = model.edit_transform
        world_normal = normal.transform(tr).normalize
        world_origin = face.bounds.center.transform(tr)
        inward = world_normal.reverse
        hit = model.raytest([world_origin.offset(inward, 0.5.mm), inward], true)
        return nil unless hit
        distance = world_origin.distance(hit[0])
        distance > 0.5.mm ? distance : nil
      rescue StandardError
        nil
      end

      def label
        @mode == :convex ? 'BO CUNG LỒI' : 'BO CUNG LÕM'
      end

      def update_status
        Sketchup.vcb_value = fmt_mm(@diameter)
        Sketchup.status_text = "#{label}: rê vào đỉnh để preview màu cam · gõ đường kính · TAB đổi chế độ · click để tạo"
      end

      def fmt_mm(length)
        format('%.1f', length.to_mm)
      end
    end
  end
end
