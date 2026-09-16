# encoding: UTF-8
# Co Giãn MODE 0.9.3: stable active-context scope for nested/shared instances.
require 'sketchup.rb'
module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.9.3'.freeze

    class Tool
      private

      def prepare_auto_scope(view, x, y)
        # All queued directions belong to the same explicit set of root instances.
        if @pending_regions && !@pending_regions.empty?
          @scope = @pending_regions.first[:scope].select { |e| selectable?(e) }
          raise 'Khối đã thay đổi; nhấn ESC để chọn lại.' if @scope.empty?
          @scope_bounds = scope_bounds_root
          return
        end
        active = @model.active_entities.to_a
        selected = @model.selection.to_a.select { |e| active.include?(e) && selectable?(e) }
        if selected.empty?
          target = auto_target_under_cursor(view, x, y)
          @scope = target ? [target] : []
          @auto_scope_source = :picked_module
        else
          @scope = selected.uniq
          @auto_scope_source = :selection
        end
        @scope_bounds = scope_bounds_root
      end

      def auto_target_under_cursor(view, x, y)
        picker = view.pick_helper
        picker.do_pick(x, y)
        # A nested leaf's transformation is relative to its parent, not active_entities.
        # Use the picked root (like SketchUp selection). Open the group to edit a child.
        active = @model.active_entities.to_a
        target = picker.best_picked
        return target if active.include?(target) && selectable?(target)
        nil
      end

      def auto_container_under_cursor(view, x, y)
        auto_target_under_cursor(view, x, y)
      end
    end
  end
end
