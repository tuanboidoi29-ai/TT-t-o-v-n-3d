# encoding: UTF-8
# TRẦN TUẤN - Bo Cong Khối V2.2.2
# FIX TRIỆT ĐỂ: ẩn seam bằng cạnh chung giữa 2 Face cong liền nhau.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.2'.freeze

    class Tool
      private

      # Ghi đè thao tác bo để giữ trực tiếp danh sách các Face thuộc cung.
      # Không còn dò seam theo tọa độ/khoảng cách.
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

            if range && i >= range.begin && i < range.end
              curved_faces << side
            end
          end

          hide_curve_internal_seams(curved_faces)

          open_count = entities.grep(Sketchup::Edge).count { |e| e.valid? && e.faces.length != 2 }
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0

          model.commit_operation
          status('đã bo xong · seam độ mịn đã ẩn · Ctrl+Z hoàn tác 1 lần')
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể bo cong V#{Round::VERSION}:\n#{error.message}")
        end
      end

      # Chỉ ẩn cạnh CHUNG của hai Face cong liên tiếp.
      # Hai đường biên ngoài đầu/cuối của cung không có hai Face cong kẹp hai bên,
      # vì vậy luôn được giữ lại.
      def hide_curve_internal_seams(curved_faces)
        return if curved_faces.nil? || curved_faces.length < 2

        hidden_count = 0

        curved_faces.each_cons(2) do |face_a, face_b|
          next unless face_a && face_b && face_a.valid? && face_b.valid?

          shared = face_a.edges & face_b.edges
          edge = shared.find do |candidate|
            candidate.valid? &&
              candidate.faces.include?(face_a) &&
              candidate.faces.include?(face_b)
          end
          next unless edge

          edge.soft = true
          edge.smooth = true
          edge.hidden = true
          hidden_count += 1
        end

        expected = curved_faces.length - 1
        if hidden_count != expected
          puts "[TT Bo Cong V#{Round::VERSION}] Seam ẩn: #{hidden_count}/#{expected}"
        end
      end
    end
  end
end
