# encoding: UTF-8
# TRẦN TUẤN - Bo Cong Khối V2.2.4
# FIX MULTI-ROUND: bo góc 2, 3, 4... vẫn giữ toàn bộ cung cũ mịn.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.4'.freeze

    class Tool
      private

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

          # Cung vừa bo: ẩn seam bằng cạnh chung thật giữa các Face cong.
          hide_curve_internal_seams(curved_faces)

          # QUAN TRỌNG: mỗi lần bo engine dựng lại TOÀN BỘ khối nên các seam
          # của cung cũ cũng bị tái tạo. Quét lại toàn bộ các cạnh chạy theo
          # chiều dày và làm mịn nếu hai mặt bên kề nhau đổi hướng nhỏ.
          smooth_all_curved_seams(entities, data[:depth])

          open_count = entities.grep(Sketchup::Edge).count { |e| e.valid? && e.faces.length != 2 }
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0

          model.commit_operation
          status('đã bo xong · tất cả cung cũ + mới đều được làm mịn')
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

      def smooth_all_curved_seams(entities, depth_vector)
        return unless depth_vector && depth_vector.length > 0.001
        depth_dir = depth_vector.clone
        depth_dir.normalize!

        # Segments tối thiểu 4 có thể tạo góc giữa 2 mặt khoảng 45°.
        # Chọn 50° để bắt được mọi seam của cung nhưng giữ góc tủ 90°.
        max_angle = 50.0 * Math::PI / 180.0

        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid? && edge.faces.length == 2

          ev = edge.end.position - edge.start.position
          next if ev.length < 0.001
          edir = ev.clone
          edir.normalize!

          # Chỉ làm mịn cạnh chạy xuyên theo chiều dày của khối.
          # Không đụng đường biên trên/dưới của tấm.
          next if edir.dot(depth_dir).abs < 0.998

          f1, f2 = edge.faces
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
