# encoding: UTF-8
# TRẦN TUẤN - BO CONG KHỐI V2.2.7
# FIX HỒI QUY 2 ĐƯỜNG BIÊN:
# - Xác định 2 biên đầu/cuối của cung MỚI bằng topology mặt thật.
# - Không phụ thuộc so khớp tọa độ cho 2 biên của cung vừa tạo.
# - Nếu không tìm đủ 2 biên thì Abort, không để tạo cung bị mất biên.
# - Cung cũ vẫn giữ metadata V2.2.6 và được bảo vệ khi dựng lại topology.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.7'.freeze

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

          # Cung cũ: giữ lại metadata/điểm biên trước khi dựng lại toàn topology.
          old_boundary_specs = capture_boundary_specs(entities)

          profile = data[:profile]
          back = profile.map { |point| point.offset(data[:depth]) }
          range = data[:arc_range]
          raise 'Không xác định được vùng cung bo.' unless range

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

          side_faces = Array.new(profile.length)
          curved_faces = []

          profile.length.times do |i|
            j = (i + 1) % profile.length
            side = entities.add_face(profile[i], profile[j], back[j], back[i])
            raise "Không tạo được mặt hông #{i + 1}." unless side && side.valid?
            side.material = data[:side_mat] if data[:side_mat]
            side.back_material = data[:side_back_mat] if data[:side_back_mat]
            side_faces[i] = side
            curved_faces << side if i >= range.begin && i < range.end
          end

          # Hai biên của cung mới được lấy từ CHÍNH quan hệ kề nhau của các mặt:
          # flat trước <-> segment cong đầu, segment cong cuối <-> flat sau.
          current_boundaries = topology_boundary_edges(side_faces, range)
          unless current_boundaries.length == 2
            raise 'Không xác định đủ 2 đường biên đầu/cuối của cung. Đã hủy thao tác để tránh mất biên.'
          end

          # Biên cung cũ vẫn được khôi phục qua metadata V2.2.6.
          old_boundaries = resolve_boundary_edges(entities, old_boundary_specs)
          protected_edges = (old_boundaries + current_boundaries).compact.select(&:valid?).uniq

          # Đánh dấu cứng TRƯỚC bước smooth để mọi bộ lọc phía sau đều nhận biết.
          protected_edges.each { |edge| harden_boundary_edge(edge) }

          # Chỉ seam nội bộ của cung mới được làm mềm/ẩn.
          hide_curve_internal_seams(curved_faces)

          # Làm mịn các cung cũ nhưng tuyệt đối bỏ qua các biên đã bảo vệ.
          smooth_all_curved_seams(entities, protected_edges)

          # Ép lại lần cuối để SketchUp không giữ trạng thái soft/hidden từ topology cũ.
          protected_edges.each { |edge| harden_boundary_edge(edge) }

          # Kiểm tra bắt buộc 2 biên mới vẫn thật sự nhìn thấy.
          current_boundaries.each do |edge|
            unless edge.valid? && !edge.hidden? && !edge.soft? && !edge.smooth?
              raise 'Đường biên cung bị SketchUp làm mềm ngoài dự kiến. Đã hủy thao tác.'
            end
          end

          open_count = entities.grep(Sketchup::Edge).count do |edge|
            edge.valid? && edge.faces.length != 2
          end
          raise "Khối sau bo chưa kín (#{open_count} cạnh hở)." if open_count > 0

          model.commit_operation
          status('đã bo xong · GIỮ 2 BIÊN ĐẦU/CUỐI · chỉ làm mịn đường chia ở giữa')
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể bo cong V#{Round::VERSION}:\n#{error.message}")
        end
      end

      def topology_boundary_edges(side_faces, range)
        return [] unless range && side_faces && !side_faces.empty?
        first_index = range.begin
        last_index = range.end - 1
        return [] if first_index < 0 || last_index < first_index
        return [] unless side_faces[first_index] && side_faces[last_index]

        previous_index = (first_index - 1) % side_faces.length
        next_index = range.end % side_faces.length

        first_edge = common_valid_edge(side_faces[previous_index], side_faces[first_index])
        last_edge = common_valid_edge(side_faces[last_index], side_faces[next_index])
        [first_edge, last_edge].compact.uniq
      rescue StandardError => error
        puts "[TT Round topology V#{Round::VERSION}] #{error.class}: #{error.message}"
        []
      end

      def common_valid_edge(face_a, face_b)
        return nil unless face_a && face_b && face_a.valid? && face_b.valid?
        (face_a.edges & face_b.edges).find do |edge|
          edge.valid? && edge.faces.include?(face_a) && edge.faces.include?(face_b)
        end
      rescue StandardError
        nil
      end

      # Tăng thêm một lớp bảo vệ: cạnh đã mang cờ boundary không bao giờ được smooth.
      def smooth_all_curved_seams(entities, protected_edges = [])
        max_angle = 50.0 * Math::PI / 180.0

        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid? && edge.faces.length == 2
          next if protected_edges.include?(edge)
          next if edge.get_attribute(Round::BOUNDARY_DICT, Round::BOUNDARY_KEY, false)

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
    end
  end
end
