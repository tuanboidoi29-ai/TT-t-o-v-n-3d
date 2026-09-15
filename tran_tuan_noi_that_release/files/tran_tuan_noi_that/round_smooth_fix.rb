# encoding: UTF-8
# TRẦN TUẤN - Bo Cong Khối V2.2.3
# FIX: bo lần 2+ vẫn giữ Soft/Smooth/Hidden của các cung đã bo trước.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.3'.freeze

    class Tool
      private

      # Mỗi lần bo engine phải dựng lại toàn bộ khối. Vì vậy trước khi xóa hình học
      # phải ghi nhớ các seam đã được làm mịn ở những cung trước, rồi phục hồi chúng
      # ngay trong cùng operation. Nhờ đó bo góc 2, 3, 4... không làm hiện lại đường chia.
      def apply_round(data)
        model = Sketchup.active_model
        entities = data[:entities]
        model.start_operation("TRẦN TUẤN - BO CONG V#{Round::VERSION}", true)

        begin
          unless entities.grep(Sketchup::Face).length == data[:face_count] &&
                 entities.grep(Sketchup::Edge).length == data[:edge_count]
            raise 'Hình học đã đổi sau preview. Hãy rê chuột bắt lại góc.'
          end

          preserved = capture_smooth_edges(entities)
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

          # 1) Ẩn seam của cung vừa bo bằng cạnh chung giữa các Face cong.
          hide_curve_internal_seams(curved_faces)

          # 2) Khôi phục seam đã ẩn của tất cả cung bo trước đó.
          restore_smooth_edges(entities, preserved)

          open_count = entities.grep(Sketchup::Edge).count { |e| e.valid? && e.faces.length != 2 }
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0

          model.commit_operation
          status('đã bo xong · giữ mịn tất cả cung trước · Ctrl+Z hoàn tác 1 lần')
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
          next unless edge

          edge.soft = true
          edge.smooth = true
          edge.hidden = true
        end
      end

      # Lưu chính hai đầu cạnh + trạng thái. Point3d độc lập với Entity nên vẫn dùng được
      # sau khi toàn bộ hình học cũ bị erase.
      def capture_smooth_edges(entities)
        entities.grep(Sketchup::Edge).each_with_object([]) do |edge, list|
          next unless edge.valid?
          next unless edge.hidden? || edge.soft? || edge.smooth?

          list << {
            a: Geom::Point3d.new(edge.start.position.x, edge.start.position.y, edge.start.position.z),
            b: Geom::Point3d.new(edge.end.position.x, edge.end.position.y, edge.end.position.z),
            hidden: edge.hidden?,
            soft: edge.soft?,
            smooth: edge.smooth?
          }
        end
      end

      def restore_smooth_edges(entities, records)
        return if records.nil? || records.empty?

        edges = entities.grep(Sketchup::Edge).select(&:valid?)
        tolerance = 0.05.mm

        records.each do |record|
          edge = edges.find do |candidate|
            edge_matches_points?(candidate, record[:a], record[:b], tolerance)
          end
          next unless edge

          edge.soft = true if record[:soft]
          edge.smooth = true if record[:smooth]
          edge.hidden = true if record[:hidden]
        end
      end

      def edge_matches_points?(edge, a, b, tolerance)
        p1 = edge.start.position
        p2 = edge.end.position
        direct = p1.distance(a) <= tolerance && p2.distance(b) <= tolerance
        reverse = p1.distance(b) <= tolerance && p2.distance(a) <= tolerance
        direct || reverse
      end
    end
  end
end
