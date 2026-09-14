# encoding: UTF-8
module TranTuanNoiThat
  module Round
    extend self

    ORANGE = Sketchup::Color.new(244, 123, 32, 210)
    FILL = Sketchup::Color.new(255, 151, 61, 75)
    ERROR = Sketchup::Color.new(230, 55, 55, 230)
    DEFAULT_SEGMENTS = 24
    MIN_SEGMENTS = 4
    MAX_SEGMENTS = 96

    def activate
      saved = TranTuanNoiThat.setting('round_radius', nil)
      radius = saved.nil? ? TranTuanNoiThat.setting('round_diameter', 40.0).to_f / 2.0 : saved.to_f
      segments = TranTuanNoiThat.setting('round_segments', DEFAULT_SEGMENTS).to_i
      segments = [[segments, MIN_SEGMENTS].max, MAX_SEGMENTS].min
      mode = TranTuanNoiThat.setting('round_mode', 'convex').to_s == 'concave' ? :concave : :convex
      @tool = Tool.new([radius, 0.1].max.mm, segments, mode)
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
      @palette.set_html(palette_html(tool.mode, tool.radius.to_mm, tool.segments))
      @palette.add_action_callback('set_mode') { |_c, value| tool.set_mode(value.to_s == 'concave' ? :concave : :convex) }
      @palette.add_action_callback('set_radius') { |_c, value| tool.set_radius_mm(value.to_f) }
      @palette.add_action_callback('set_segments') { |_c, value| tool.set_segments(value.to_i) }
      @palette.add_action_callback('close_tool') { |_c| Sketchup.active_model.select_tool(nil) }
      @palette.set_on_closed { @palette = nil }
      @palette.show
    end

    def close_palette
      @palette.close if @palette && @palette.visible?
      @palette = nil
    end

    def sync_palette(mode, radius, segments)
      return unless @palette && @palette.visible?
      @palette.execute_script("syncState(#{JSON.generate(mode.to_s)}, #{radius.to_mm}, #{segments})")
    end

    def palette_html(mode, radius, segments)
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
        <div class="row"><b>Bán kính R</b><input id="radius" type="number" min="0.1" step="0.1" value="#{radius}" onchange="radius()"><span>mm</span></div>
        <div class="row"><b>Độ mịn cung</b><input id="segments" type="number" min="4" max="96" step="1" value="#{segments}" onchange="segments()"><span>đoạn</span></div>
        <div class="hint">TAB: đổi chế độ · Gõ số: nhập trực tiếp bán kính R<br>Độ mịn 4–96 đoạn được tự động lưu.</div>
        <button class="close" onclick="sketchup.close_tool()">ĐÓNG</button>
        <script>
        function mode(v){sketchup.set_mode(v)}
        function radius(){sketchup.set_radius(document.getElementById('radius').value)}
        function segments(){sketchup.set_segments(document.getElementById('segments').value)}
        function syncState(m,r,s){document.getElementById('convex').classList.toggle('active',m==='convex');document.getElementById('concave').classList.toggle('active',m==='concave');document.getElementById('radius').value=Number(r).toFixed(1);document.getElementById('segments').value=s}
        syncState(#{JSON.generate(mode.to_s)},#{radius},#{segments});
        </script></body></html>
      HTML
    end

    class Tool
      attr_reader :mode, :radius, :segments

      def initialize(radius, segments, mode)
        @radius = radius
        @segments = segments
        @mode = mode
        @ip = Sketchup::InputPoint.new
        @candidate = nil
      end

      def activate
        Sketchup.vcb_label = 'Bán kính R'
        update_status
      end

      def deactivate(view)
        Round.close_palette
        view.invalidate
      end

      def resume(view)
        Sketchup.vcb_label = 'Bán kính R'
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @candidate = build_candidate(@ip)
        view.tooltip = @candidate ? "#{label} - R#{fmt_mm(@radius)} mm" : 'Đưa chuột sát một đỉnh của Group/Component'
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
          @radius = length
          TranTuanNoiThat.save_setting('round_radius', @radius.to_mm)
          @candidate = build_candidate(@ip)
          Round.sync_palette(@mode, @radius, @segments)
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
        TranTuanNoiThat.save_setting('round_mode', @mode.to_s)
        @candidate = build_candidate(@ip)
        Round.sync_palette(@mode, @radius, @segments)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def set_radius_mm(value)
        return UI.beep unless value > 0
        @radius = value.mm
        TranTuanNoiThat.save_setting('round_radius', value)
        @candidate = build_candidate(@ip)
        Round.sync_palette(@mode, @radius, @segments)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def set_segments(value)
        @segments = [[value.to_i, Round::MIN_SEGMENTS].max, Round::MAX_SEGMENTS].min
        TranTuanNoiThat.save_setting('round_segments', @segments)
        @candidate = build_candidate(@ip)
        Round.sync_palette(@mode, @radius, @segments)
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
          view.draw(GL_LINE_STRIP, points[1..-1])
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
        return nil unless ip.valid? && ip.vertex
        model = Sketchup.active_model
        tr = ip.transformation || model.edit_transform
        face = pick_face(ip, tr)
        return nil unless face && face.valid?
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
        radius = @radius
        tangent = @mode == :convex ? radius / Math.tan(angle / 2.0) : radius
        valid = angle > 0.02 && angle < Math::PI - 0.02 && tangent > 0 && tangent < va.length * 0.98 && tangent < vb.length * 0.98
        tangent = [tangent, va.length * 0.95, vb.length * 0.95].min unless valid
        a = origin.offset(va.normalize, tangent)
        b = origin.offset(vb.normalize, tangent)
        arc = arc_points(origin, a, b, face.normal, radius, angle)
        points = [origin, a] + arc[1..-2] + [b]
        owner = face.parent
        entities = owner.respond_to?(:entities) ? owner.entities : owner
        { face: face, vertex: vertex, local_points: points, world_points: points.map { |p| p.transform(tr) },
          world_vertex: origin.transform(tr), valid: valid, normal: face.normal,
          entities: entities, transformation: tr }
      rescue StandardError
        nil
      end

      def pick_face(ip, transformation)
        vertex = ip.vertex
        direct = ip.face
        return direct if direct && direct.valid? && direct.vertices.include?(vertex)

        camera_direction = Sketchup.active_model.active_view.camera.direction
        vertex.faces.select(&:valid?).max_by do |face|
          world_normal = face.normal.transform(transformation).normalize
          world_normal.dot(camera_direction).abs
        end
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
        (0..@segments).map do |i|
          vector = start.transform(Geom::Transformation.rotation(ORIGIN, normal, signed * i / @segments.to_f))
          center.offset(vector)
        end
      end

      def apply_round(data)
        model = Sketchup.active_model
        entities = data[:entities]
        model.start_operation("TRẦN TUẤN - #{label}", true)
        before = entities.grep(Sketchup::Face)
        curve = data[:local_points][1..-1]
        entities.add_edges(curve)
        candidates = data[:vertex].faces.select { |f| f.valid? && f.normal.parallel?(data[:normal]) }
        cut_face = candidates.reject { |f| before.include?(f) }.min_by(&:area)
        cut_face ||= candidates.min_by(&:area)
        raise 'Không tách được vùng bo cong tại góc này.' unless cut_face && cut_face.valid?
        push_distance = solid_depth(cut_face, data[:normal], entities)
        raise 'Không tìm thấy mặt đối diện để nối kín khối.' unless push_distance && push_distance.abs > 0.1.mm
        cut_face.pushpull(push_distance)
        heal_arc_boundaries(entities, data[:local_points][1..-1], data[:normal], push_distance)
        verify_closed_round(entities, data[:local_points][1..-1], data[:normal], push_distance)
        model.commit_operation
      rescue StandardError => error
        model.abort_operation if model
        UI.messagebox("Không thể bo cong:\n#{error.message}")
      end

      def solid_depth(face, normal, entities)
        origin = face.bounds.center
        hits = []
        [normal, normal.reverse].each do |direction|
          entities.grep(Sketchup::Face).each do |target|
            next unless target.valid? && target != face
            next unless target.normal.parallel?(normal)
            point = Geom.intersect_line_plane([origin, direction], target.plane)
            next unless point
            distance = (point - origin).dot(direction)
            next unless distance > 0.1.mm
            state = target.classify_point(point)
            next if state == Sketchup::Face::PointOutside || state == Sketchup::Face::PointUnknown
            sign = direction.dot(normal) >= 0 ? 1.0 : -1.0
            hits << distance * sign
          end
        end
        hits.min_by(&:abs)
      rescue StandardError
        nil
      end

      def heal_arc_boundaries(entities, top_arc, normal, push_distance)
        bottom_arc = top_arc.map { |point| point.offset(normal, push_distance) }
        (0...(top_arc.length - 1)).each do |index|
          points = [top_arc[index], top_arc[index + 1], bottom_arc[index + 1], bottom_arc[index]]
          next if side_face_exists?(entities, points)
          face = entities.add_face(points)
          face.reverse! if face && face.valid? && face.normal.dot(normal.cross(top_arc[index + 1] - top_arc[index])) < 0
        end
      end

      def side_face_exists?(entities, points)
        center = Geom::Point3d.new(
          points.sum { |p| p.x } / points.length.to_f,
          points.sum { |p| p.y } / points.length.to_f,
          points.sum { |p| p.z } / points.length.to_f
        )
        entities.grep(Sketchup::Face).any? do |face|
          next false unless face.valid?
          state = face.classify_point(center)
          [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(state)
        end
      end

      def verify_closed_round(entities, top_arc, normal, push_distance)
        bottom_arc = top_arc.map { |point| point.offset(normal, push_distance) }
        sample_points = top_arc + bottom_arc
        open_edges = entities.grep(Sketchup::Edge).select do |edge|
          next false unless edge.valid? && edge.faces.length < 2
          sample_points.any? { |point| edge.bounds.contains?(point) }
        end
        raise 'Các đường biên sau khi bo chưa được nối kín.' unless open_edges.empty?
      end

      def label
        @mode == :convex ? 'BO CUNG LỒI' : 'BO CUNG LÕM'
      end

      def update_status
        Sketchup.vcb_value = fmt_mm(@radius)
        Sketchup.status_text = "#{label}: rê vào đỉnh Group/Component · gõ bán kính R · TAB đổi chế độ · click để tạo"
      end

      def fmt_mm(length)
        format('%.1f', length.to_mm)
      end
    end
  end
end
