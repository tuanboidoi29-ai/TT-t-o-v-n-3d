# encoding: UTF-8
# TRẦN TUẤN - Bo Cong Khối V2.2.5
# FIX: bo liên tiếp trên khối đã bo + làm mịn lại TOÀN BỘ cung sau mỗi lần bo.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.5'.freeze

    class Tool
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

          hide_curve_internal_seams(curved_faces)
          smooth_all_curved_seams(entities)

          open_count = entities.grep(Sketchup::Edge).count { |e| e.valid? && e.faces.length != 2 }
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0

          model.commit_operation
          status('đã bo xong · giữ mịn toàn bộ cung cũ + mới')
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể bo cong V#{Round::VERSION}:\n#{error.message}")
        end
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

      def smooth_all_curved_seams(entities, _depth_vector = nil)
        max_angle = 50.0 * Math::PI / 180.0

        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid? && edge.faces.length == 2

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

      def soften_edge(edge)
        return unless edge && edge.valid?
        edge.soft = true
        edge.smooth = true
        edge.hidden = true
      end
    end
  end
end
