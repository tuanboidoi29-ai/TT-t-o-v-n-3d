# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - KHÓA SCALE 4 CẠNH
# SketchUp 2021+
#
# Quy trình:
# - Chọn/hover 1 Group hoặc Component.
# - Tool tự chọn mặt BoundingBox hướng về camera.
# - Hiện 4 TAY NẮM ở trung điểm: Trái / Phải / Trên / Dưới.
# - Nhấn giữ trực tiếp TRUNG ĐIỂM để kéo Scale.
# - Cạnh đối diện tự KHÓA cố định.
# - Thả chuột để áp dụng; hoặc gõ hệ số (vd 1.2).
# - Một thao tác = một Undo.
#
# Lưu ý:
# - Không sửa geometry bên trong.
# - Chỉ thay Transformation của Group/Component.
# - Không Scale âm/lật khối qua cạnh khóa.

require 'sketchup.rb'

module TranTuanNoiThat
  module ScaleCornerLock
    extend self

    VERSION = '1.9.137'.freeze
    PICK_RADIUS = 20.0
    MIN_FACTOR = 0.001

    EDGE_NAMES = {
      u_min: 'TRÁI',
      u_max: 'PHẢI',
      v_min: 'DƯỚI',
      v_max: 'TRÊN'
    }.freeze

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
        @original_transform = nil
        @preview_transform_context = nil

        @depth_axis = nil
        @u_axis = nil
        @v_axis = nil
        @face_depth_coord = nil

        @hover_edge = nil
        @locked_edge = nil
        @drag_edge = nil
        @scale_axis = nil
        @fixed_coord = nil
        @factor = 1.0
        @dragging = false

        @anchor_screen = nil
        @drag_screen = nil
        @screen_axis = nil
        @screen_axis_len2 = 1.0

        use_selection_if_valid
      end

      def activate
        refresh_view_plane
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
          reset_scale
          @dragging = false
          @state = :pick_edge
        when :pick_edge
          @entity = nil
          @bbox = nil
          @hover_edge = nil
          @state = :pick_entity
        else
          @model.select_tool(nil)
          return
        end
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        case @state
        when :pick_entity
          @hover_entity = pick_container(view, x, y)
        when :pick_edge
          refresh_view_plane
          @hover_edge = nearest_midpoint_key(view, x, y)
        when :scale
          update_scale_preview(view, x, y)
        end
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT Scale4Edges move] #{error.class}: #{error.message}"
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
          refresh_view_plane
          @state = :pick_edge

        when :pick_edge
          refresh_view_plane
          edge = nearest_midpoint_key(view, x, y)
          unless edge
            UI.beep
            return
          end
          begin_drag(edge, view)
          @dragging = true
          update_scale_preview(view, x, y)

        when :scale
          # Đang kéo bằng chuột; không cần click lần hai.
          update_scale_preview(view, x, y)
        end

        update_status
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Scale 4 Cạnh:\n#{error.message}")
        puts "[TT Scale4Edges click] #{error.class}: #{error.message}"
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @state == :scale && @dragging

        update_scale_preview(view, x, y)
        @dragging = false

        if (@factor - 1.0).abs < 0.0001
          reset_scale
          @state = :pick_edge
          update_status
        else
          commit_scale
        end
        view.invalidate
      rescue StandardError => error
        @dragging = false
        UI.messagebox("Không hoàn tất Scale 4 Cạnh:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @state == :scale

        raw = text.to_s.strip.tr(',', '.')
        return UI.beep if raw.empty?

        @factor = valid_factor(Float(raw))
        rebuild_preview_transform
        commit_scale
        view.invalidate
      rescue StandardError => error
        UI.beep
        UI.messagebox("Không nhận được hệ số Scale:\n#{error.message}\nVí dụ: 1.2")
      end

      def draw(view)
        if @state == :pick_entity && @hover_entity
          draw_entity_box(view, @hover_entity, Sketchup::Color.new(120, 120, 120), 1)
          return
        end

        return unless @entity && @bbox

        refresh_view_plane if @state == :pick_edge

        case @state
        when :pick_edge
          draw_entity_box(view, @entity, Sketchup::Color.new(241, 150, 170), 2)
          draw_four_midpoints(view)
        when :scale
          draw_preview_box(view)
          draw_scale_edges(view)
          draw_factor_text(view)
        end
      rescue StandardError => error
        puts "[TT Scale4Edges draw] #{error.class}: #{error.message}"
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
        selected = @model.selection.to_a.select do |entity|
          valid_container?(entity) && active_entities.include?(entity)
        end
        return unless selected.length == 1

        set_entity(selected.first)
        refresh_view_plane
        @state = :pick_edge
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
        @bbox = definition_bounds(entity)
        raise 'Không đọc được BoundingBox của đối tượng.' unless @bbox && !@bbox.empty?

        @original_transform = entity.transformation
        @preview_transform_context = @original_transform
        reset_scale
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

      def axis_value(point, axis)
        case axis
        when 0 then point.x
        when 1 then point.y
        else point.z
        end
      end

      def axis_min(axis)
        axis_value(@bbox.min, axis)
      end

      def axis_max(axis)
        axis_value(@bbox.max, axis)
      end

      def point_local(a0, a1, a2)
        values = [0.0, 0.0, 0.0]
        values[@u_axis] = a0
        values[@v_axis] = a1
        values[@depth_axis] = a2
        Geom::Point3d.new(values[0], values[1], values[2])
      end

      def refresh_view_plane
        return unless @entity && @bbox

        view = @model.active_view
        camera_direction_world = view.camera.direction.clone
        tr = entity_to_world
        local_direction = camera_direction_world.transform(tr.inverse)
        local_direction.normalize! if local_direction.length > 0.000001

        values = [local_direction.x.abs, local_direction.y.abs, local_direction.z.abs]
        @depth_axis = values.each_with_index.max[1]
        plane_axes = [0, 1, 2] - [@depth_axis]
        @u_axis = plane_axes[0]
        @v_axis = plane_axes[1]

        component = [local_direction.x, local_direction.y, local_direction.z][@depth_axis]
        @face_depth_coord = component >= 0.0 ? axis_min(@depth_axis) : axis_max(@depth_axis)
      rescue StandardError
        @depth_axis = 2
        @u_axis = 0
        @v_axis = 1
        @face_depth_coord = axis_max(@depth_axis)
      end

      def edge_local_points(key)
        u0 = axis_min(@u_axis)
        u1 = axis_max(@u_axis)
        v0 = axis_min(@v_axis)
        v1 = axis_max(@v_axis)
        d = @face_depth_coord

        case key
        when :u_min
          [point_local(u0, v0, d), point_local(u0, v1, d)]
        when :u_max
          [point_local(u1, v0, d), point_local(u1, v1, d)]
        when :v_min
          [point_local(u0, v0, d), point_local(u1, v0, d)]
        when :v_max
          [point_local(u0, v1, d), point_local(u1, v1, d)]
        else
          []
        end
      end

      def edge_world_points(key, transform_context = nil)
        tr = entity_to_world(@entity, transform_context || @entity.transformation)
        edge_local_points(key).map { |point| point.transform(tr) }
      end

      def edge_midpoint_world(key, transform_context = nil)
        points = edge_world_points(key, transform_context)
        Geom::Point3d.linear_combination(0.5, points[0], 0.5, points[1])
      end

      def nearest_midpoint_key(view, x, y)
        best_key = nil
        best_distance = PICK_RADIUS + 1.0

        %i[u_min u_max v_min v_max].each do |key|
          midpoint = view.screen_coords(edge_midpoint_world(key))
          dx = midpoint.x.to_f - x.to_f
          dy = midpoint.y.to_f - y.to_f
          distance = Math.sqrt(dx * dx + dy * dy)

          if distance <= PICK_RADIUS && distance < best_distance
            best_key = key
            best_distance = distance
          end
        end
        best_key
      rescue StandardError
        nil
      end

      def opposite_edge(key)
        {
          u_min: :u_max,
          u_max: :u_min,
          v_min: :v_max,
          v_max: :v_min
        }.fetch(key)
      end

      def edge_axis(key)
        [:u_min, :u_max].include?(key) ? @u_axis : @v_axis
      end

      def edge_fixed_coord(key)
        case key
        when :u_min then axis_min(@u_axis)
        when :u_max then axis_max(@u_axis)
        when :v_min then axis_min(@v_axis)
        when :v_max then axis_max(@v_axis)
        end
      end

      def begin_drag(key, view)
        @drag_edge = key
        @locked_edge = opposite_edge(key)
        @scale_axis = edge_axis(key)
        @fixed_coord = edge_fixed_coord(@locked_edge)
        @factor = 1.0
        @preview_transform_context = @original_transform

        @anchor_screen = view.screen_coords(edge_midpoint_world(@locked_edge))
        @drag_screen = view.screen_coords(edge_midpoint_world(@drag_edge))
        @screen_axis = Geom::Vector3d.new(
          @drag_screen.x.to_f - @anchor_screen.x.to_f,
          @drag_screen.y.to_f - @anchor_screen.y.to_f,
          0.0
        )
        @screen_axis_len2 = @screen_axis.x * @screen_axis.x + @screen_axis.y * @screen_axis.y
        @screen_axis_len2 = 1.0 if @screen_axis_len2 < 1.0

        @state = :scale
        Sketchup.set_status_text('Scale', SB_VCB_LABEL)
        Sketchup.set_status_text('1.000', SB_VCB_VALUE)
      end

      def reset_scale
        @hover_edge = nil
        @locked_edge = nil
        @drag_edge = nil
        @scale_axis = nil
        @fixed_coord = nil
        @factor = 1.0
        @dragging = false
        @preview_transform_context = @original_transform if @original_transform
        @anchor_screen = nil
        @drag_screen = nil
        @screen_axis = nil
        @screen_axis_len2 = 1.0
        clear_vcb
      end

      def update_scale_preview(view, x, y)
        return unless @locked_edge && @drag_edge && @screen_axis && @anchor_screen

        px = x.to_f - @anchor_screen.x.to_f
        py = y.to_f - @anchor_screen.y.to_f
        numerator = px * @screen_axis.x + py * @screen_axis.y
        @factor = valid_factor(numerator / @screen_axis_len2)

        rebuild_preview_transform
        Sketchup.set_status_text(format('%.3f', @factor), SB_VCB_VALUE)
      end

      def valid_factor(value)
        factor = value.to_f
        raise 'Hệ số Scale phải lớn hơn 0.' unless factor > 0.0
        [factor, MIN_FACTOR].max
      end

      def rebuild_preview_transform
        raise 'Chưa chọn cạnh khóa.' unless @scale_axis

        factors = [1.0, 1.0, 1.0]
        factors[@scale_axis] = @factor

        center = @bbox.center
        anchor_values = [center.x, center.y, center.z]
        anchor_values[@scale_axis] = @fixed_coord
        anchor = Geom::Point3d.new(anchor_values[0], anchor_values[1], anchor_values[2])

        to_anchor = Geom::Transformation.translation(
          Geom::Vector3d.new(anchor.x, anchor.y, anchor.z)
        )
        from_anchor = Geom::Transformation.translation(
          Geom::Vector3d.new(-anchor.x, -anchor.y, -anchor.z)
        )
        scale = Geom::Transformation.scaling(
          Geom::Point3d.new(0, 0, 0),
          factors[0], factors[1], factors[2]
        )

        @preview_transform_context =
          @original_transform * to_anchor * scale * from_anchor
      end

      def commit_scale
        raise 'Đối tượng không còn hợp lệ.' unless valid_container?(@entity)
        raise 'Chưa chọn cạnh khóa.' unless @locked_edge
        raise 'Hệ số Scale không hợp lệ.' unless @factor > 0.0

        @model.start_operation('TT - Scale 4 Cạnh', true)
        started = true

        @entity.transformation = @preview_transform_context

        @model.commit_operation
        started = false

        @original_transform = @entity.transformation
        @bbox = definition_bounds(@entity)
        reset_scale
        refresh_view_plane
        @state = :pick_edge

        Sketchup.status_text =
          'Đã Scale · cạnh khóa giữ nguyên · Ctrl+Z hoàn tác · chọn cạnh khác để tiếp tục.'
        true
      rescue StandardError
        @model.abort_operation if started rescue nil
        raise
      end

      def preview_world_corners
        return [] unless @entity && @bbox
        entity_world_corners(
          @entity,
          @preview_transform_context || @entity.transformation
        )
      end

      def draw_entity_box(view, entity, color, width)
        draw_box_edges(view, entity_world_corners(entity), color, width)
      end

      def draw_preview_box(view)
        draw_box_edges(
          view,
          preview_world_corners,
          Sketchup::Color.new(241, 150, 170),
          3
        )
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

      def draw_four_midpoints(view)
        %i[u_min u_max v_min v_max].each do |key|
          hovered = key == @hover_edge
          midpoint = edge_midpoint_world(key)

          color = hovered ?
            Sketchup::Color.new(255, 170, 30) :
            Sketchup::Color.new(50, 135, 235)

          # Chỉ tay nắm TRUNG ĐIỂM là vùng thao tác.
          view.draw_points(
            midpoint,
            hovered ? 18 : 13,
            2,
            color
          )

          screen = view.screen_coords(midpoint)
          view.draw_text(
            [screen.x + 10, screen.y - 10],
            EDGE_NAMES[key],
            color: color
          )
        end
      end

      def draw_scale_edges(view)
        locked_mid = edge_midpoint_world(
          @locked_edge,
          @preview_transform_context
        )
        drag_mid = edge_midpoint_world(
          @drag_edge,
          @preview_transform_context
        )

        # Đường hướng chỉ để nhìn trục kéo, không phải vùng bắt chuột.
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(120, 150, 190)
        view.draw(GL_LINES, [locked_mid, drag_mid])

        view.draw_points(
          locked_mid,
          17,
          2,
          Sketchup::Color.new(230, 45, 45)
        )
        view.draw_points(
          drag_mid,
          19,
          2,
          Sketchup::Color.new(40, 130, 240)
        )
      end

      def draw_factor_text(view)
        point = edge_midpoint_world(@drag_edge, @preview_transform_context)
        screen = view.screen_coords(point)
        text = "#{EDGE_NAMES[@locked_edge]} KHÓA · SCALE #{format('%.3f', @factor)}x"
        view.draw_text(
          [screen.x + 14, screen.y - 18],
          text,
          color: Sketchup::Color.new(30, 80, 160)
        )
      rescue StandardError
      end

      def update_status
        Sketchup.status_text = case @state
        when :pick_entity
          'SCALE 4 CẠNH · click Group/Component cần Scale.'
        when :pick_edge
          '4 TRUNG ĐIỂM đang hiện · nhấn giữ đúng điểm TRÁI/PHẢI/TRÊN/DƯỚI rồi kéo. Điểm đối diện tự khóa.'
        when :scale
          "ĐANG KÉO TRUNG ĐIỂM · điểm đỏ = mốc khóa · điểm xanh = đang kéo · thả chuột để áp dụng."
        end
      end

      def clear_vcb
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      rescue StandardError
      end
    end
  end
end
