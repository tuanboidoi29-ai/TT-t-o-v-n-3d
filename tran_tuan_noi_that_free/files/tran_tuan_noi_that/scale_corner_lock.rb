# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - KHÓA GÓC SCALE
# SketchUp 2021+
#
# Quy trình:
# - Chọn/hover 1 Group hoặc Component.
# - Click 1 trong 8 góc BoundingBox để KHÓA.
# - Rê chuột: preview scale quanh góc khóa.
# - TAB: Đồng tỷ lệ <-> XYZ tự do.
# - Click lần nữa để áp dụng.
# - Gõ 1.2 = scale đồng tỷ lệ.
# - Gõ 1.2,1,0.8 = scale X,Y,Z.
# - Một thao tác = một Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module ScaleCornerLock
    extend self

    VERSION = '1.9.123'.freeze
    PICK_RADIUS = 18.0
    MIN_FACTOR = 0.001

    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end

    class Tool
      def initialize
        @model = Sketchup.active_model
        @context_to_world = @model.edit_transform
        @state = :pick_entity
        @entity = nil
        @hover_entity = nil
        @bbox = nil
        @anchor_index = nil
        @hover_corner = nil
        @opposite_index = nil
        @ip = Sketchup::InputPoint.new
        @factors = [1.0, 1.0, 1.0]
        @uniform = true
        @preview_transform_context = nil
        @original_transform = nil
        @anchor_world = nil
        @opposite_world = nil
        @start_screen_distance = 1.0
        use_selection_if_valid
      end

      def activate
        update_status
        @model.active_view.invalidate
      end

      def deactivate(view)
        clear_vcb
        view.invalidate if view
      end

      def enableVCB?
        @state == :scale
      end

      def onCancel(_reason, view)
        case @state
        when :scale
          reset_anchor
          @state = :pick_anchor
        when :pick_anchor
          @entity = nil
          @bbox = nil
          @state = :pick_entity
        else
          @model.select_tool(nil)
          return
        end
        update_status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless tab_key?(key)
        return unless @entity

        @uniform = !@uniform
        update_preview_from_last_input(view)
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT ScaleCornerLock key] #{error.class}: #{error.message}"
      end

      def onMouseMove(_flags, x, y, view)
        case @state
        when :pick_entity
          @hover_entity = pick_container(view, x, y)
        when :pick_anchor
          @hover_corner = nearest_corner_index(view, x, y)
        when :scale
          @last_x = x
          @last_y = y
          update_scale_preview(view, x, y)
        end
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT ScaleCornerLock move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        case @state
        when :pick_entity
          entity = pick_container(view, x, y)
          unless entity
            UI.beep
            return
          end
          set_entity(entity)
          @state = :pick_anchor

        when :pick_anchor
          index = nearest_corner_index(view, x, y)
          unless index
            UI.beep
            return
          end
          lock_corner(index, view)

        when :scale
          update_scale_preview(view, x, y)
          commit_scale
        end
        update_status
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Khóa Góc Scale:\n#{error.message}")
        puts "[TT ScaleCornerLock click] #{error.class}: #{error.message}"
      end

      def onUserText(text, view)
        return UI.beep unless @state == :scale
        raw = text.to_s.strip
        return UI.beep if raw.empty?

        values = raw.split(/[;,xX\s]+/).reject(&:empty?).map { |item| Float(item.tr(',', '.')) }
        if values.length == 1
          factor = valid_factor(values[0])
          @uniform = true
          @factors = [factor, factor, factor]
        elsif values.length == 3
          @uniform = false
          @factors = values.map { |value| valid_factor(value) }
        else
          raise 'Nhập 1 hệ số (vd 1.2) hoặc 3 hệ số X,Y,Z (vd 1.2,1,0.8).'
        end

        rebuild_preview_transform
        commit_scale
        view.invalidate
      rescue StandardError => error
        UI.beep
        UI.messagebox("Không nhận được hệ số Scale:\n#{error.message}")
      end

      def draw(view)
        draw_entity_box(view, @hover_entity, Sketchup::Color.new(120, 120, 120), 1) if @state == :pick_entity && @hover_entity

        return unless @entity && @bbox

        case @state
        when :pick_anchor
          draw_entity_box(view, @entity, Sketchup::Color.new(241, 150, 170), 3)
          draw_corners(view)
        when :scale
          draw_preview_box(view)
          draw_locked_corner(view)
          draw_drag_corner(view)
          draw_factor_text(view)
        end
      rescue StandardError => error
        puts "[TT ScaleCornerLock draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        if @entity && @bbox
          preview_world_corners.each { |point| bb.add(point) }
        elsif @hover_entity
          entity_world_corners(@hover_entity).each { |point| bb.add(point) }
        end
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def use_selection_if_valid
        selected = @model.selection.to_a.select { |entity| valid_container?(entity) && active_entities.include?(entity) }
        return unless selected.length == 1

        set_entity(selected.first)
        @state = :pick_anchor
      end

      def active_entities
        @model.active_entities
      end

      def valid_container?(entity)
        entity &&
          entity.valid? &&
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
      end

      def set_entity(entity)
        @entity = entity
        @hover_entity = entity
        @original_transform = entity.transformation
        @bbox = definition_bounds(entity)
        raise 'Không đọc được BoundingBox của đối tượng.' unless @bbox && !@bbox.empty?

        @anchor_index = nil
        @hover_corner = nil
        @opposite_index = nil
        @factors = [1.0, 1.0, 1.0]
        @preview_transform_context = @original_transform
      end

      def definition_bounds(entity)
        if entity.respond_to?(:definition) && entity.definition
          entity.definition.bounds
        elsif entity.respond_to?(:local_bounds)
          entity.local_bounds
        else
          entity.bounds
        end
      end

      def pick_container(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)
        path = helper.path_at(0)
        return nil unless path

        path.find { |entity| valid_container?(entity) && active_entities.include?(entity) } ||
          path.reverse.find { |entity| valid_container?(entity) && active_entities.include?(entity) }
      rescue StandardError
        nil
      end

      def entity_to_world(entity = @entity, transform_context = nil)
        context_transform = transform_context || entity.transformation
        @context_to_world * context_transform
      end

      def entity_world_corners(entity = @entity, transform_context = nil)
        bounds = entity == @entity ? @bbox : definition_bounds(entity)
        tr = entity_to_world(entity, transform_context)
        8.times.map { |index| bounds.corner(index).transform(tr) }
      end

      def nearest_corner_index(view, x, y)
        return nil unless @entity
        best = nil
        best_distance = PICK_RADIUS + 1.0

        entity_world_corners.each_with_index do |point, index|
          screen = view.screen_coords(point)
          dx = screen.x.to_f - x.to_f
          dy = screen.y.to_f - y.to_f
          distance = Math.sqrt(dx * dx + dy * dy)
          if distance <= PICK_RADIUS && distance < best_distance
            best = index
            best_distance = distance
          end
        end
        best
      rescue StandardError
        nil
      end

      def lock_corner(index, view)
        @anchor_index = index
        @opposite_index = 7 - index
        @anchor_world = entity_world_corners[index]
        @opposite_world = entity_world_corners[@opposite_index]

        a = view.screen_coords(@anchor_world)
        b = view.screen_coords(@opposite_world)
        dx = b.x.to_f - a.x.to_f
        dy = b.y.to_f - a.y.to_f
        @start_screen_distance = Math.sqrt(dx * dx + dy * dy)
        @start_screen_distance = 1.0 if @start_screen_distance < 1.0

        @factors = [1.0, 1.0, 1.0]
        @preview_transform_context = @original_transform
        @state = :scale
        @last_x = b.x.to_i
        @last_y = b.y.to_i

        Sketchup.set_status_text('Scale', SB_VCB_LABEL)
        Sketchup.set_status_text('1.0', SB_VCB_VALUE)
      end

      def reset_anchor
        @anchor_index = nil
        @hover_corner = nil
        @opposite_index = nil
        @anchor_world = nil
        @opposite_world = nil
        @factors = [1.0, 1.0, 1.0]
        @preview_transform_context = @original_transform
        clear_vcb
      end

      def update_scale_preview(view, x, y)
        return unless @anchor_index && @opposite_index

        if @uniform
          anchor_screen = view.screen_coords(@anchor_world)
          dx = x.to_f - anchor_screen.x.to_f
          dy = y.to_f - anchor_screen.y.to_f
          factor = Math.sqrt(dx * dx + dy * dy) / @start_screen_distance
          factor = valid_factor(factor)
          @factors = [factor, factor, factor]
        else
          @ip.pick(view, x, y)
          if @ip.valid? && @ip.degrees_of_freedom < 3
            current_world = @ip.position
            current_local = current_world.transform(entity_to_world.inverse)
            anchor_local = @bbox.corner(@anchor_index)
            opposite_local = @bbox.corner(@opposite_index)
            @factors = [
              factor_from_coords(anchor_local.x, opposite_local.x, current_local.x),
              factor_from_coords(anchor_local.y, opposite_local.y, current_local.y),
              factor_from_coords(anchor_local.z, opposite_local.z, current_local.z)
            ]
            view.tooltip = @ip.tooltip
          else
            anchor_screen = view.screen_coords(@anchor_world)
            dx = x.to_f - anchor_screen.x.to_f
            dy = y.to_f - anchor_screen.y.to_f
            factor = Math.sqrt(dx * dx + dy * dy) / @start_screen_distance
            factor = valid_factor(factor)
            @factors = [factor, factor, factor]
          end
        end

        rebuild_preview_transform
        Sketchup.set_status_text(
          @uniform ? format('%.3f', @factors[0]) : @factors.map { |f| format('%.3f', f) }.join(', '),
          SB_VCB_VALUE
        )
      end

      def update_preview_from_last_input(view)
        return unless @last_x && @last_y
        update_scale_preview(view, @last_x, @last_y)
      end

      def factor_from_coords(anchor, opposite, current)
        denominator = opposite.to_f - anchor.to_f
        return 1.0 if denominator.abs < 0.000001
        valid_factor((current.to_f - anchor.to_f) / denominator)
      end

      def valid_factor(value)
        factor = value.to_f
        raise 'Hệ số scale phải lớn hơn 0.' unless factor > 0.0
        [factor, MIN_FACTOR].max
      end

      def rebuild_preview_transform
        anchor = @bbox.corner(@anchor_index)
        to_anchor = Geom::Transformation.translation(Geom::Vector3d.new(anchor.x, anchor.y, anchor.z))
        from_anchor = Geom::Transformation.translation(Geom::Vector3d.new(-anchor.x, -anchor.y, -anchor.z))
        scale = Geom::Transformation.scaling(
          Geom::Point3d.new(0, 0, 0),
          @factors[0],
          @factors[1],
          @factors[2]
        )
        local_scale_about_anchor = to_anchor * scale * from_anchor
        @preview_transform_context = @original_transform * local_scale_about_anchor
      end

      def commit_scale
        raise 'Đối tượng không còn hợp lệ.' unless valid_container?(@entity)
        raise 'Chưa khóa góc.' unless @anchor_index

        @model.start_operation('TT - Khóa Góc Scale', true)
        started = true
        @entity.transformation = @preview_transform_context
        @model.commit_operation
        started = false

        @original_transform = @entity.transformation
        @bbox = definition_bounds(@entity)
        reset_anchor
        @state = :pick_anchor
        update_status('Đã Scale · góc khóa giữ nguyên · Ctrl+Z để hoàn tác. Chọn góc mới để tiếp tục.')
        true
      rescue StandardError
        @model.abort_operation if started rescue nil
        raise
      end

      def preview_world_corners
        return [] unless @entity && @bbox
        entity_world_corners(@entity, @preview_transform_context || @entity.transformation)
      end

      def draw_entity_box(view, entity, color, width)
        corners = entity_world_corners(entity)
        draw_box_edges(view, corners, color, width)
      end

      def draw_preview_box(view)
        corners = preview_world_corners
        draw_box_edges(view, corners, Sketchup::Color.new(241, 150, 170), 4)
      end

      def draw_box_edges(view, corners, color, width)
        pairs = [
          [0,1],[1,3],[3,2],[2,0],
          [4,5],[5,7],[7,6],[6,4],
          [0,4],[1,5],[2,6],[3,7]
        ]
        view.line_width = width
        view.drawing_color = color
        view.draw(GL_LINES, pairs.flat_map { |a, b| [corners[a], corners[b]] })
      end

      def draw_corners(view)
        corners = entity_world_corners
        corners.each_with_index do |point, index|
          hovered = index == @hover_corner
          color = hovered ? Sketchup::Color.new(255, 70, 40) : Sketchup::Color.new(255, 190, 40)
          view.draw_points(point, hovered ? 14 : 10, 2, color)
        end
      end

      def draw_locked_corner(view)
        return unless @anchor_index
        point = @bbox.corner(@anchor_index).transform(entity_to_world(@entity, @preview_transform_context))
        view.draw_points(point, 16, 2, Sketchup::Color.new(230, 45, 45))
      end

      def draw_drag_corner(view)
        return unless @opposite_index
        point = @bbox.corner(@opposite_index).transform(entity_to_world(@entity, @preview_transform_context))
        view.draw_points(point, 14, 2, Sketchup::Color.new(40, 130, 240))
      end

      def draw_factor_text(view)
        point = @bbox.corner(@opposite_index).transform(entity_to_world(@entity, @preview_transform_context))
        text = if @uniform
          "LOCK SCALE  #{format('%.3f', @factors[0])}x"
        else
          "XYZ  #{@factors.map { |f| format('%.2f', f) }.join(' / ')}"
        end
        screen = view.screen_coords(point)
        view.draw_text([screen.x + 14, screen.y - 16], text)
      rescue StandardError
      end

      def update_status(custom = nil)
        if custom
          Sketchup.status_text = custom
          return
        end

        Sketchup.status_text = case @state
        when :pick_entity
          'KHÓA GÓC SCALE · click Group/Component cần Scale.'
        when :pick_anchor
          'Rê vào 1 trong 8 góc · click để KHÓA góc cố định.'
        when :scale
          mode = @uniform ? 'ĐỒNG TỶ LỆ' : 'XYZ TỰ DO'
          "Góc đỏ = khóa · góc xanh = kéo · #{mode} · TAB đổi mode · click áp dụng · gõ 1.2 hoặc 1.2,1,0.8."
        end
      end

      def clear_vcb
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      rescue StandardError
      end

      def tab_key?(key)
        key == 9 || key == VK_TAB
      rescue StandardError
        key == 9
      end
    end
  end
end
