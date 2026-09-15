# encoding: UTF-8
# TRẦN TUẤN - Bo Cong Khối V2.2.1
# Hotfix: ẩn chính xác các cạnh chia độ mịn bên trong mặt cong.

module TranTuanNoiThat
  module Round
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.2.1'.freeze

    class Tool
      private

      # V2.2.1: không còn phụ thuộc so tọa độ tuyệt đối 0.001mm.
      # Dò seam theo hướng chiều dày của khối + khoảng cách tới trục seam.
      # Chỉ các seam GIỮA cung bị Soft/Smooth/Hidden; 2 biên ngoài vẫn giữ nguyên.
      def smooth_seams(entities, profile, back, range)
        return unless range
        return if range.end - range.begin < 2

        depth = back[range.begin] - profile[range.begin]
        depth_len = depth.length
        return if depth_len < 0.001

        depth_dir = depth.clone
        depth_dir.normalize!
        axis_tol = [0.25.mm, depth_len * 0.002].max
        len_tol = [0.5.mm, depth_len * 0.01].max
        edges = entities.grep(Sketchup::Edge)

        ((range.begin + 1)...range.end).each do |i|
          top_point = profile[i]
          bottom_point = back[i]
          axis = [top_point, depth_dir]

          candidates = edges.select do |edge|
            next false unless edge.valid? && edge.faces.length == 2
            vector = edge.end.position - edge.start.position
            next false if vector.length < 0.001
            dir = vector.clone
            dir.normalize!
            next false if dir.dot(depth_dir).abs < 0.999
            next false if (vector.length - depth_len).abs > len_tol

            d1 = edge.start.position.distance_to_line(axis)
            d2 = edge.end.position.distance_to_line(axis)
            d1 <= axis_tol && d2 <= axis_tol
          end

          edge = candidates.min_by do |candidate|
            a = candidate.start.position
            b = candidate.end.position
            direct = a.distance(top_point) + b.distance(bottom_point)
            reverse = a.distance(bottom_point) + b.distance(top_point)
            [direct, reverse].min
          end
          next unless edge

          edge.soft = true
          edge.smooth = true
          edge.hidden = true
        end
      end
    end
  end
end
