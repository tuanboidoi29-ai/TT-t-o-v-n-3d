# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.9.2
# FIX AUTO SCOPE / PREVIEW BOUNDS ÔM SÁT MODULE

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.9.2'.freeze

    class Tool
      private

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

        candidates.min_by do |entity|
          module_penalty = container_like?(entity) ? 0 : 1
          [module_penalty, entity_bounds_metric(entity)]
        end
      rescue StandardError => error
        puts "[TT Stretch AUTO pick V0.9.2] #{error.class}: #{error.message}"
        nil
      end

      def auto_container_under_cursor(view, x, y)
        auto_target_under_cursor(view, x, y)
      end

      def entity_bounds_metric(entity)
        bb = entity.bounds
        return Float::INFINITY if bb.nil? || bb.empty?

        dx = (bb.max.x - bb.min.x).abs.to_f
        dy = (bb.max.y - bb.min.y).abs.to_f
        dz = (bb.max.z - bb.min.z).abs.to_f
        dx * dx + dy * dy + dz * dz
      rescue StandardError
        Float::INFINITY
      end
    end
  end
end
