# encoding: UTF-8
module TranTuanNoiThat
  module Round
    extend self

    VERSION = '2.2.0'.freeze
    ORANGE = Sketchup::Color.new(244, 123, 32, 220)
    RED = Sketchup::Color.new(230, 55, 55, 230)
    SNAP = 28
    MIN_SEG = 4
    MAX_SEG = 96

    def activate
      r = TranTuanNoiThat.setting('round_radius', 20.0).to_f
      seg = TranTuanNoiThat.setting('round_segments', 24).to_i
      seg = [[seg, MIN_SEG].max, MAX_SEG].min
      mode = TranTuanNoiThat.setting('round_mode', 'convex').to_s == 'concave' ? :concave : :convex
      Sketchup.active_model.select_tool(Tool.new([r, 0.1].max.mm, seg, mode))
    end

    class Tool
      def initialize(radius, segments, mode)
        @radius, @segments, @mode = radius, segments, mode
        @ip = Sketchup::InputPoint.new
        @candidate = nil
      end

      def activate
        Sketchup.vcb_label = 'Bán kính R'
        status
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless key == 9
        @mode = (@mode == :convex ? :concave : :convex)
        TranTuanNoiThat.save_setting('round_mode', @mode.to_s)
        @candidate = repick
        status
        view.invalidate
        true
      end

      def onUserText(text, view)
        value = Sketchup.parse_length(text)
        return UI.beep unless value && value > 0
        @radius = value
        TranTuanNoiThat.save_setting('round_radius', @radius.to_mm)
        @candidate = repick
        status
        view.invalidate
      rescue StandardError
        UI.beep
      end

      def onMouseMove(_flags, x, y, view)
        @last_view, @last_x, @last_y = view, x, y
        @ip.pick(view, x, y)
        @candidate = nearby(view, x, y) || candidate_from_ip
        view.tooltip = tooltip
        view.invalidate
      rescue StandardError => error
        @candidate = nil
        puts "[TT Round V#{Round::VERSION}] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        @last_view, @last_x, @last_y = view, x, y
        @ip.pick(view, x, y)
        @candidate = nearby(view, x, y) || candidate_from_ip
        return UI.beep unless @candidate && @candidate[:valid]
        apply_round(@candidate)
        @candidate = nil
        view.invalidate
      end

      def draw(view)
        return unless @candidate
        color = @candidate[:valid] ? Round::ORANGE : Round::RED
        view.drawing_color = color
        view.line_width = 4
        if @candidate[:arc]
          view.draw(GL_LINE_STRIP, @candidate[:arc])
          view.draw(GL_LINE_STRIP, @candidate[:back_arc])
          lines = []
          [0, @candidate[:arc].length / 2, @candidate[:arc].length - 1].uniq.each do |i|
            lines.concat([@candidate[:arc][i], @candidate[:back_arc][i]])
          end
          view.line_width = 2
          view.draw(GL_LINES, lines)
        end
        view.draw_points([@candidate[:vertex]], 10, 3, color) if @candidate[:vertex]
      end

      private

      def status(extra = nil)
        Sketchup.vcb_value = format('%.1f', @radius.to_mm)
        mode = @mode == :convex ? 'CUNG LỒI' : 'CUNG LÕM'
        Sketchup.status_text = "TT BO CONG KHỐI V#{Round::VERSION} | #{mode} | #{extra || 'rê sát góc · nhập R · TAB đổi chế độ · click để bo'}"
      end

      def tooltip
        return 'Rê sát một góc của khối Group/Component kín' unless @candidate
        return @candidate[:reason].to_s unless @candidate[:valid]
        "#{@mode == :convex ? 'CUNG LỒI' : 'CUNG LÕM'} · R#{format('%.1f', @radius.to_mm)} mm · V#{Round::VERSION}"
      end

      def repick
        return nil unless @last_view && @last_x && @last_y
        @ip.pick(@last_view, @last_x, @last_y)
        nearby(@last_view, @last_x, @last_y) || candidate_from_ip
      end

      def candidate_from_ip
        return nil unless @ip.valid? && @ip.vertex
        tr = @ip.transformation || Sketchup.active_model.edit_transform
        if @last_view && @last_x && @last_y
          screen = @last_view.screen_coords(@ip.vertex.position.transform(tr))
          return nil if Math.hypot(screen.x - @last_x, screen.y - @last_y) > Round::SNAP
        end
        build(@ip.vertex, @ip.face, tr)
      end

      def nearby(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y, Round::SNAP)
        best = nil
        ph.count.times do |i|
          leaf = ph.leaf_at(i)
          tr = Sketchup.active_model.edit_transform * ph.transformation_at(i)
          vertices = if leaf.is_a?(Sketchup::Vertex)
                       [leaf]
                     elsif leaf.is_a?(Sketchup::Edge)
                       leaf.vertices
                     elsif leaf.is_a?(Sketchup::Face)
                       leaf.vertices
                     else
                       []
                     end
          vertices.each do |vertex|
            screen = view.screen_coords(vertex.position.transform(tr))
            d = Math.sqrt((screen.x - x)**2 + (screen.y - y)**2)
            next if d > Round::SNAP
            item = [d, vertex, leaf.is_a?(Sketchup::Face) ? leaf : nil, tr]
            best = item if best.nil? || d < best[0]
          end
        end
        return nil unless best
        item = build(best[1], best[2], best[3])
        item || invalid(best[1], best[3], 'Đã bắt đỉnh. Đỉnh này chưa có mặt phù hợp để bo khối.')
      rescue StandardError
        nil
      end

      def build(vertex, direct_face, tr)
        face = pick_face(vertex, direct_face, tr)
        return nil unless face && face.valid?
        entities = face.parent
        entities = entities.entities if entities.respond_to?(:entities)
        return nil unless entities.respond_to?(:grep)

        reason = prism_reason(entities, face)
        return invalid(vertex, tr, reason) if reason

        vertices = face.outer_loop.vertices
        index = vertices.index(vertex)
        return nil unless index
        origin = vertex.position
        va = vertices[(index - 1) % vertices.length].position - origin
        vb = vertices[(index + 1) % vertices.length].position - origin
        return nil if va.length < 0.001 || vb.length < 0.001
        la, lb = va.length, vb.length
        va.normalize!; vb.normalize!
        angle = va.angle_between(vb)
        return invalid(vertex, tr, 'Góc này không hợp lệ để bo.') if angle <= 0.02 || angle >= Math::PI - 0.02

        tangent = @mode == :convex ? @radius / Math.tan(angle / 2.0) : @radius
        return invalid(vertex, tr, 'Bán kính R quá lớn so với cạnh tại góc này.') unless tangent.finite? && tangent > 0 && tangent < [la, lb].min - 0.01.mm

        a = origin.offset(va, tangent)
        b = origin.offset(vb, tangent)
        center = if @mode == :convex
                   bis = va + vb
                   return invalid(vertex, tr, 'Không xác định được tâm cung.') if bis.length < 0.001
                   bis.normalize!
                   origin.offset(bis, @radius / Math.sin(angle / 2.0))
                 else
                   origin
                 end
        normal = face.normal.clone
        normal.normalize!
        arc = arc_points(center, a, b, normal)
        return invalid(vertex, tr, 'Không tạo được cung bo.') unless arc && arc.length >= 3

        allowed = [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex]
        return invalid(vertex, tr, 'Cung bo nằm ngoài mặt đang chọn.') unless allowed.include?(face.classify_point(arc[arc.length / 2]))

        depth = prism_depth(face, vertex)
        return invalid(vertex, tr, 'Không xác định được chiều dày khối kín.') unless depth

        profile = []
        arc_range = nil
        vertices.each_with_index do |v, i|
          if i == index
            first = profile.length
            arc.each { |p| profile << Geom::Point3d.new(p.x, p.y, p.z) }
            arc_range = (first..profile.length - 1)
          else
            p = v.position
            profile << Geom::Point3d.new(p.x, p.y, p.z)
          end
        end

        {
          valid: true, entities: entities, normal: normal, profile: profile, arc_range: arc_range,
          depth: depth[:vector], face_count: entities.grep(Sketchup::Face).length,
          edge_count: entities.grep(Sketchup::Edge).length,
          front_mat: face.material, front_back_mat: face.back_material,
          rear_mat: depth[:opposite].material, rear_back_mat: depth[:opposite].back_material,
          side_mat: dominant(entities.grep(Sketchup::Face) - [face, depth[:opposite]], false),
          side_back_mat: dominant(entities.grep(Sketchup::Face) - [face, depth[:opposite]], true),
          arc: arc.map { |p| p.transform(tr) },
          back_arc: arc.map { |p| p.offset(depth[:vector]).transform(tr) },
          vertex: origin.transform(tr)
        }
      rescue StandardError => error
        puts "[TT Round build] #{error.class}: #{error.message}"
        nil
      end

      def invalid(vertex, tr, reason)
        { valid: false, reason: reason, vertex: vertex.position.transform(tr) }
      end

      def pick_face(vertex, direct_face, tr)
        return direct_face if direct_face && direct_face.valid? && direct_face.outer_loop.vertices.include?(vertex)
        camera = Sketchup.active_model.active_view.camera.direction
        vertex.faces.select(&:valid?).max_by do |face|
          n = face.normal.transform(tr)
          n.normalize!
          n.dot(camera).abs
        end
      end

      def prism_reason(entities, face)
        return 'Mặt có lỗ chưa được hỗ trợ.' unless face.loops.length == 1
        return 'Khối có Group/Component con; hãy bo từng khối trực tiếp.' if entities.any? { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Image) }
        parent = entities.respond_to?(:parent) ? entities.parent : nil
        if parent.is_a?(Sketchup::ComponentDefinition) && parent.instances.length > 1
          return 'Component có nhiều bản sao. Hãy Make Unique trước khi bo.'
        end
        n = face.outer_loop.edges.length
        faces = entities.grep(Sketchup::Face)
        edges = entities.grep(Sketchup::Edge)
        return 'Chỉ hỗ trợ khối lăng trụ kín đơn giản.' unless n >= 3 && faces.length == n + 2 && edges.length == n * 3
        return 'Khối đang có cạnh hở.' unless edges.all? { |e| e.faces.length == 2 }
        nil
      end

      def prism_depth(face, vertex)
        face_edges = face.edges
        extra = vertex.edges.reject { |e| face_edges.include?(e) }
        return nil unless extra.length == 1
        vector = extra[0].other_vertex(vertex).position - vertex.position
        return nil if vector.length < 0.001
        dir = vector.clone; dir.normalize!
        normal = face.normal.clone; normal.normalize!
        return nil if dir.dot(normal).abs < 0.999
        opposite = extra[0].other_vertex(vertex).faces.find do |f|
          next false if f == face || !f.valid? || f.loops.length != 1
          n = f.normal.clone; n.normalize!
          n.dot(normal).abs > 0.999
        end
        return nil unless opposite
        len = vector.length
        face.outer_loop.vertices.each do |v|
          cross = v.edges.reject { |e| face_edges.include?(e) }
          return nil unless cross.length == 1
          ev = cross[0].other_vertex(v).position - v.position
          return nil if ev.length < 0.001
          edir = ev.clone; edir.normalize!
          return nil if edir.dot(dir).abs < 0.999 || (ev.length - len).abs > 0.01.mm
        end
        { vector: vector, opposite: opposite }
      end

      def arc_points(center, a, b, normal)
        v1, v2 = a - center, b - center
        angle = Math.atan2(normal.dot(v1.cross(v2)), v1.dot(v2))
        angle -= 2.0 * Math::PI if angle > Math::PI
        angle += 2.0 * Math::PI if angle < -Math::PI
        return nil if angle.abs < 0.001
        (0..@segments).map do |i|
          a.transform(Geom::Transformation.rotation(center, normal, angle * i.to_f / @segments))
        end
      end

      def apply_round(data)
        model = Sketchup.active_model
        entities = data[:entities]
        model.start_operation("TRẦN TUẤN - BO CONG V#{Round::VERSION}", true)
        begin
          unless entities.grep(Sketchup::Face).length == data[:face_count] && entities.grep(Sketchup::Edge).length == data[:edge_count]
            raise 'Hình học đã đổi sau preview. Hãy rê chuột bắt lại góc.'
          end
          profile = data[:profile]
          back = profile.map { |p| p.offset(data[:depth]) }
          entities.erase_entities(entities.grep(Sketchup::Face) + entities.grep(Sketchup::Edge))

          front = entities.add_face(profile)
          raise 'Không tạo lại được mặt đầu.' unless front
          front.reverse! if front.normal.dot(data[:normal]) < 0
          front.material = data[:front_mat] if data[:front_mat]
          front.back_material = data[:front_back_mat] if data[:front_back_mat]

          rear = entities.add_face(back.reverse)
          raise 'Không tạo lại được mặt đối diện.' unless rear
          rear.reverse! if rear.normal.dot(data[:normal]) > 0
          rear.material = data[:rear_mat] if data[:rear_mat]
          rear.back_material = data[:rear_back_mat] if data[:rear_back_mat]

          profile.length.times do |i|
            j = (i + 1) % profile.length
            side = entities.add_face(profile[i], profile[j], back[j], back[i])
            raise "Không tạo được mặt hông #{i + 1}." unless side
            side.material = data[:side_mat] if data[:side_mat]
            side.back_material = data[:side_back_mat] if data[:side_back_mat]
          end
          smooth_seams(entities, profile, back, data[:arc_range])
          open_count = entities.grep(Sketchup::Edge).count { |e| e.faces.length != 2 }
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0
          model.commit_operation
          status('đã bo xong · tiếp tục chọn góc khác · Ctrl+Z hoàn tác 1 lần')
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể bo cong V#{Round::VERSION}:\n#{error.message}")
        end
      end

      def smooth_seams(entities, profile, back, range)
        return unless range
        ((range.begin + 1)...range.end).each do |i|
          edge = entities.grep(Sketchup::Edge).find do |e|
            a, b = e.start.position, e.end.position
            (close?(a, profile[i]) && close?(b, back[i])) || (close?(a, back[i]) && close?(b, profile[i]))
          end
          next unless edge
          edge.soft = true
          edge.smooth = true
          edge.hidden = true
        end
      end

      def close?(a, b)
        a.distance(b) <= 0.001.mm
      end

      def dominant(faces, back)
        counts = Hash.new(0)
        faces.each { |f| counts[back ? f.back_material : f.material] += 1 }
        pair = counts.max_by { |_m, count| count }
        pair ? pair[0] : nil
      end
    end
  end
end

