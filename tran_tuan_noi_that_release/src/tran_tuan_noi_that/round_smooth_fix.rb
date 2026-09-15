# encoding: UTF-8
# TRẦN TUẤN - Bo Cong Khối V2.2.6
# FIX:
# - Giữ HIỆN đúng 2 đường biên đầu tiên và cuối cùng của mỗi cung bo.
# - Chỉ làm mịn/ẩn các đường chia nằm GIỮA cung.
# - Khi bo tiếp góc 2/3/4, các đường biên cung cũ đã đánh dấu vẫn được giữ hiện.
# - Preview chỉ nhấn mạnh 2 đường biên đầu/cuối, không vẽ đường giữa gây nhầm.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.6'.freeze

    BOUNDARY_DICT = 'TRẦN TUẤN BO CONG'.freeze unless const_defined?(:BOUNDARY_DICT, false)
    BOUNDARY_KEY  = 'duong_bien_cung'.freeze unless const_defined?(:BOUNDARY_KEY, false)

    class Tool
      def draw(view)
        return unless @candidate

        color = @candidate[:valid] ? Round::ORANGE : Round::RED
        view.drawing_color = color
        view.line_width = 4

        if @candidate[:arc] && @candidate[:back_arc]
          view.draw(GL_LINE_STRIP, @candidate[:arc])
          view.draw(GL_LINE_STRIP, @candidate[:back_arc])

          if @candidate[:arc].length >= 2 && @candidate[:back_arc].length >= 2
            boundary_lines = [
              @candidate[:arc].first, @candidate[:back_arc].first,
              @candidate[:arc].last,  @candidate[:back_arc].last
            ]
            view.line_width = 5
            view.draw(GL_LINES, boundary_lines)
          end
        end

        view.draw_points([@candidate[:vertex]], 10, 3, color) if @candidate[:vertex]
      rescue StandardError => error
        puts "[TT Round draw V#{Round::VERSION}] #{error.class}: #{error.message}"
      end

      private

      def pick_face(vertex, direct_face, tr)
        candidates = vertex.faces.select { |f| f.valid? && f.loops.length == 1 }
        return nil if candidates.empty?

        if direct_face && direct_face.valid? &&
           direct_face.outer_loop.vertices.include?(vertex) &&
           prism_depth(direct_face, vertex)
          return direct_face
        end

        viable = candidates.select { |face| prism_depth(face, vertex) }
        return nil if viable.empty?

        camera = Sketchup.active_model.active_view.camera.direction
        viable.max_by do |face|
          n = face.normal.transform(tr)
          n.normalize! if n.length > 0.001
          [n.dot(camera).abs, face.outer_loop.edges.length]
        end
      rescue StandardError
        nil
      end

      def prism_reason(entities, face)
        return 'Mặt có lỗ chưa được hỗ trợ.' unless face.loops.length == 1
        if entities.any? { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Image) }
          return 'Khối có Group/Component con; hãy bo từng khối trực tiếp.'
        end

        parent = entities.respond_to?(:parent) ? entities.parent : nil
        if parent.is_a?(Sketchup::ComponentDefinition) && parent.instances.length > 1
          return 'Component có nhiều bản sao. Hãy Make Unique trước khi bo.'
        end

        edges = entities.grep(Sketchup::Edge)
        return 'Khối đang có cạnh hở.' if edges.empty? || edges.any? { |e| !e.valid? || e.faces.length != 2 }
        nil
      end

      def apply_round(data)
        model = Sketchup.active_model
        entities = data[:entities]
        model.start_operation("TRẦN TUẤN - BO CONG V#{Round::VERSION}", true)

        begin
          unless entities.grep(Sketchup::Face).length == data[:face_count] &&
                 entities.grep(Sketchup::Edge).length == data[:edge_count]
            raise 'Hình học đã đổi sau preview. Hãy rê chuột bắt lại góc.'
          end

          old_boundary_specs = capture_boundary_specs(entities)

          profile = data[:profile]
          back = profile.map { |p| p.offset(data[:depth]) }
          range = data[:arc_range]

          entities.erase_entities(entities.grep(Sketchup::Face) + entities.grep(Sketchup::Edge))

          front = entities.add_face(profile)
          raise 'Không tạo lại được mặt đầu.' unless front && front.valid?
          front.reverse! if front.normal.dot(data[:normal]) < 0
          front.material = data[:front_mat] if data[:front_mat]
          front.back_material = data[:front_back_mat] if data[:front_back_mat]

          rear = entities.add_face(back.reverse)
          raise 'Không tạo lại được mặt đối diện.' unless rear && rear.valid?
          rear.reverse! if rear.normal.dot(data[:normal]) > 0
          rear.material = data[:rear_mat] if data[:rear_mat]
          rear.back_material = data[:rear_back_mat] if data[:rear_back_mat]

          curved_faces = []
          profile.length.times do |i|
            j = (i + 1) % profile.length
            side = entities.add_face(profile[i], profile[j], back[j], back[i])
            raise "Không tạo được mặt hông #{i + 1}." unless side && side.valid?
            side.material = data[:side_mat] if data[:side_mat]
            side.back_material = data[:side_back_mat] if data[:side_back_mat]
            curved_faces << side if range && i >= range.begin && i < range.end
          end

          current_boundary_specs = []
          if range
            current_boundary_specs << [clone_point(profile[range.begin]), clone_point(back[range.begin])]
            current_boundary_specs << [clone_point(profile[range.end]), clone_point(back[range.end])]
          end

          boundary_specs = old_boundary_specs + current_boundary_specs
          protected_edges = resolve_boundary_edges(entities, boundary_specs)

          hide_curve_internal_seams(curved_faces)
          smooth_all_curved_seams(entities, protected_edges)
          protected_edges.each { |edge| harden_boundary_edge(edge) }

          open_count = entities.grep(Sketchup::Edge).count { |e| e.valid? && e.faces.length != 2 }
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0

          model.commit_operation
          status('đã bo xong · 2 biên đầu/cuối HIỆN · các đường giữa đã LÀM MỊN')
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể bo cong V#{Round::VERSION}:\n#{error.message}")
        end
      end

      def capture_boundary_specs(entities)
        entities.grep(Sketchup::Edge).each_with_object([]) do |edge, specs|
          next unless edge.valid?
          next unless edge.get_attribute(Round::BOUNDARY_DICT, Round::BOUNDARY_KEY, false)
          specs << [clone_point(edge.start.position), clone_point(edge.end.position)]
        end
      rescue StandardError
        []
      end

      def resolve_boundary_edges(entities, specs)
        edges = entities.grep(Sketchup::Edge).select(&:valid?)
        found = []

        specs.each do |a, b|
          edge = edges.find do |candidate|
            p1 = candidate.start.position
            p2 = candidate.end.position
            (round_close?(p1, a) && round_close?(p2, b)) ||
              (round_close?(p1, b) && round_close?(p2, a))
          end
          found << edge if edge && !found.include?(edge)
        end

        found
      rescue StandardError
        []
      end

      def hide_curve_internal_seams(curved_faces)
        return if curved_faces.nil? || curved_faces.length < 2

        curved_faces.each_cons(2) do |face_a, face_b|
          next unless face_a && face_b && face_a.valid? && face_b.valid?
          edge = (face_a.edges & face_b.edges).find do |candidate|
            candidate.valid? && candidate.faces.include?(face_a) && candidate.faces.include?(face_b)
          end
          soften_edge(edge)
        end
      end

      def smooth_all_curved_seams(entities, protected_edges = [])
        max_angle = 50.0 * Math::PI / 180.0

        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid? && edge.faces.length == 2
          next if protected_edges.include?(edge)

          f1, f2 = edge.faces
          next unless f1.valid? && f2.valid?

          n1 = f1.normal.clone
          n2 = f2.normal.clone
          next if n1.length < 0.001 || n2.length < 0.001
          n1.normalize!
          n2.normalize!

          angle = n1.angle_between(n2)
          angle = [angle, Math::PI - angle].min
          next if angle > max_angle

          soften_edge(edge)
        end
      end

      def harden_boundary_edge(edge)
        return unless edge && edge.valid?
        edge.soft = false
        edge.smooth = false
        edge.hidden = false
        edge.set_attribute(Round::BOUNDARY_DICT, Round::BOUNDARY_KEY, true)
      rescue StandardError => error
        puts "[TT Round boundary] #{error.class}: #{error.message}"
      end

      def soften_edge(edge)
        return unless edge && edge.valid?
        edge.soft = true
        edge.smooth = true
        edge.hidden = true
      end

      def clone_point(point)
        Geom::Point3d.new(point.x, point.y, point.z)
      end

      def round_close?(a, b)
        a.distance(b) <= 0.01.mm
      rescue StandardError
        false
      end
    end
  end
end
