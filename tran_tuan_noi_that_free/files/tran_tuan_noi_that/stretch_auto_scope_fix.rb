# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.9.2
# FIX AUTO SCOPE / PREVIEW BOUNDS ÔM SÁT MODULE
#
# Mục tiêu:
# - Không lấy cả active context khi P1 thực tế đang nằm trên một module/group cụ thể.
# - Nếu P1 đi qua nhiều Group/Component lồng nhau, ưu tiên container sâu nhất gần P1.
# - Nếu không có container có child Group/Component, vẫn lấy Group/Component gần P1 làm scope.
# - Nhờ vậy khung 3D nét đứt bám sát module thay vì phóng theo toàn model/context.
# - Không thay đổi engine TRUE DETAIL STRETCH.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.9.2'.freeze

    class Tool
      private

      # AUTO scope mới: selection > target dưới P1 > active context.
      def prepare_auto_scope(view, x, y)
        selected = @model.selection.to_a.select { |e| selectable?(e) && e.valid? }

        if !selected.empty?
          @scope = selected.uniq
          @auto_scope_source = :selection
        else
          target = auto_target_under_cursor(view, x, y)
          if target
            @scope = [target]
            @auto_scope_source = :picked_module
          else
            @scope = @model.active_entities.to_a.select { |e| selectable?(e) && e.valid? }
            @auto_scope_source = :context
          end
        end

        @scope_bounds = scope_bounds_root
      rescue StandardError => error
        puts "[TT Stretch AUTO scope V0.9.2] #{error.class}: #{error.message}"
        @scope = initial_scope
        @scope_bounds = scope_bounds_root
        @auto_scope_source = :context
      end

      # Tìm đúng module dưới P1.
      # - Mỗi pick path: ưu tiên container sâu nhất có Group/Component con.
      # - Nếu không có container kiểu module, lấy Group/Component sâu nhất của path.
      # - Giữa nhiều pick path, chọn candidate có bounds nhỏ nhất để tránh bắt wrapper ngoài quá lớn.
      def auto_target_under_cursor(view, x, y)
        picker = view.pick_helper
        picker.do_pick(x, y)
        count = picker.count.to_i
        return nil if count <= 0

        candidates = []

        [count, 12].min.times do |index|
          path = picker.path_at(index)
          next unless path.respond_to?(:each)

          selectable_path = path.to_a.select { |entity| selectable?(entity) && entity.valid? }
          next if selectable_path.empty?

          module_candidate = selectable_path.reverse.find { |entity| container_like?(entity) }
          candidate = module_candidate || selectable_path.reverse.first
          candidates << candidate if candidate && candidate.valid?
        end

        candidates.uniq!
        return nil if candidates.empty?

        # Ưu tiên module thực có child; trong cùng nhóm chọn bounds nhỏ hơn.
        candidates.min_by do |entity|
          module_penalty = container_like?(entity) ? 0 : 1
          [module_penalty, entity_bounds_metric(entity)]
        end
      rescue StandardError => error
        puts "[TT Stretch AUTO pick V0.9.2] #{error.class}: #{error.message}"
        nil
      end

      # Giữ compatibility với code V0.9.0/V0.9.1 gọi tên cũ.
      def auto_container_under_cursor(view, x, y)
        auto_target_under_cursor(view, x, y)
      end

      def entity_bounds_metric(entity)
        bb = entity.bounds
        return Float::INFINITY if bb.nil? || bb.empty?

        dx = (bb.max.x - bb.min.x).abs.to_f
        dy = (bb.max.y - bb.min.y).abs.to_f
        dz = (bb.max.z - bb.min.z).abs.to_f

        # Diagonal bình phương ổn định hơn volume khi một chiều rất mỏng.
        dx * dx + dy * dy + dz * dz
      rescue StandardError
        Float::INFINITY
      end
    end
  end
end
