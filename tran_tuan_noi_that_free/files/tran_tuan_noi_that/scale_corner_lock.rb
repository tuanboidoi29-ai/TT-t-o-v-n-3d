# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - SCALE KÉO CẠNH BẮT ĐIỂM
# SketchUp 2021+
#
# Quy trình:
# 1) Chọn Group/Component hoặc click đối tượng.
# 2) Rê trực tiếp vào 1 trong 4 cạnh của mặt tấm đang nhìn.
# 3) Giữ chuột và kéo cạnh. Cạnh đối diện được khóa.
# 4) Bắt Endpoint / Edge / Face / Inference bằng Sketchup::InputPoint.
# 5) Thả chuột để áp dụng. Có thể nhập kích thước mới theo mm rồi Enter.
#    Nhập 1.2x để scale theo hệ số.
#
# Không sửa geometry bên trong; chỉ thay Transformation.
# Một thao tác = một Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module ScaleCornerLock
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.9.259'.freeze

    PICK_RADIUS = 14.0
    MIN_FACTOR = 0.001
    MOVE_EPS_PX = 2.0

    EDGE_NAMES = {
      u_min: 'TRÁI',
      u_max: 'PHẢI',
      v_min: 'DƯỚI',
      v_max: 'TRÊN'
    }.freeze

    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end

    class SelectionFrame
      attr_reader :transformation, :definition

      def initialize(items)
        @items = items
        bounds = Geom::BoundingBox.new
        items.each do |entity|
          8.times do |index|
            bounds.add(entity.definition.bounds.corner(index).transform(entity.transformation))
          end
        end
        @definition = Struct.new(:bounds).new(bounds)
        @transformation = Geom::Transformation.new
      end

      def valid?
        @items.all? { |entity| entity.valid? && !entity.locked? }
      end

      def transformation=(value)
        delta = value * @transformation.inverse
        @items.each { |entity| entity.transformation = delta * entity.transformation }
        @transformation = value
      end
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

        @depth_axis = 2
        @u_axis = 0
        @v_axis = 1
        @face_depth_coord = 0.0

        @hover_edge = nil
        @drag_edge = nil
        @locked_edge = nil
        @scale_axis = nil
        @fixed_coord = nil
        @drag_coord = nil
        @original_size = 0.0
        @factor = 1.0
        @current_size = 0.0
        @dragging = false
        @moved = false

        @input_point = Sketchup::InputPoint.new
        @snap_point = nil

        @anchor_screen = nil
        @drag_screen = nil
        @screen_axis = nil
        @screen_axis_len2 = 1.0
        @press_x = nil
        @press_y = nil

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
        if @state == :scale
          reset_scale
          @state = :pick_edge
        elsif @state == :pick_edge
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
          @hover_edge = nearest_edge_key(view, x, y)
        when :scale
          @moved ||= Math.hypot(x.to_f - @press_x.to_f, y.to_f - @press_y.to_f) >= MOVE_EPS_PX
          update_scale_preview(view, x, y)
        end

        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT Scale Edge move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        case @state
        when :pick_entity
          entity = pick_container(view, x, y)
          unless entity
            UI.beep
            return
          end
          @model.selection.clear
          @model.selection.add(entity)
          set_entity(entity)
          refresh_view_plane
          @state = :pick_edge

        when :pick_edge
          refresh_view_plane
          edge = nearest_edge_key(view, x, y)
          unless edge
            UI.beep
            return
          end
          begin_drag(edge, view, x, y)

        when :scale
          update_scale_preview(view, x, y)
        end

        update_status
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Scale Kéo Cạnh:\n#{error.message}")
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @state == :scale && @dragging

        update_scale_preview(view, x, y)
        @dragging = false

        if !@moved || (@factor - 1.0).abs < 0.000001
          reset_scale
          @state = :pick_edge
          update_status
        else
          commit_scale
        end

        view.invalidate
      rescue StandardError => error
        @dragging = false
        UI.messagebox("Không hoàn tất Scale Kéo Cạnh:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @state == :scale

        raw = text.to_s.strip.tr(',', '.')
        return UI.beep if raw.empty?

        if raw.downcase.end_with?('x')
          factor_text = raw[0...-1].strip
          @factor = valid_factor(Float(factor_text))
        else
          target = parse_target_length(raw)
          raise 'Kích thước phải lớn hơn 0.' unless target > 0.0
          @factor = valid_factor(target / @original_size)
        end

        @current_size = @original_size * @factor
        rebuild_preview_transform
        @moved = true
        commit_scale
        view.invalidate
      rescue StandardError => error
        UI.beep
        UI.messagebox(
          "Không nhận được kích thước Scale:\n#{error.message}\n"           "Ví dụ: 500 hoặc 500mm. Hệ số: 1.2x"
        )
      end

      def draw(view)
        if @state == :pick_entity && @hover_entity
          draw_entity_box(view, @hover_entity, Sketchup::Color.new(120, 120, 120), 1)
          return
        end

        return unless @entity && @bbox

        case @state
        when :pick_edge
          draw_entity_box(view, @entity, Sketchup::Color.new(241, 150, 170), 2)
          draw_face_edges(view)

        when :scale
          draw_preview_box(view)
          draw_drag_state(view)
          @input_point.draw(view) if @input_point && @input_point.valid?
          draw_dimension_text(view)
        end
      rescue StandardError => error
        puts "[TT Scale Edge draw] #{error.class}: #{error.message}"
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
        return if selected.empty?

        set_entity(selected.length == 1 ? selected.first : SelectionFrame.new(selected))
        refresh_view_plane
        @state = :pick_edge
      end

      def active_entities
        @model.active_entities
      end

      def valid_container?(entity)
        return false unless entity
        return entity.valid? if entity.is_a?(SelectionFrame)

        entity.valid? &&
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
          !entity.locked?
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

        path.reverse.find do |entity|
          valid_container?(entity) && active_entities.include?(entity)
        end
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
        axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
      end

      def axis_min(axis)
        axis_value(@bbox.min, axis)
      end

      def axis_max(axis)
        axis_value(@bbox.max, axis)
      end

      def point_local(u, v, depth)
        values = [0.0, 0.0, 0.0]
        values[@u_axis] = u
        values[@v_axis] = v
        values[@depth_axis] = depth
        Geom::Point3d.new(*values)
      end

      def refresh_view_plane
        return unless @entity && @bbox

        view = @model.active_view
        world_to_local = entity_to_world(@entity, @original_transform).inverse
        local_direction = view.camera.direction.transform(world_to_local)
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
        when :u_min then [point_local(u0, v0, d), point_local(u0, v1, d)]
        when :u_max then [point_local(u1, v0, d), point_local(u1, v1, d)]
        when :v_min then [point_local(u0, v0, d), point_local(u1, v0, d)]
        when :v_max then [point_local(u0, v1, d), point_local(u1, v1, d)]
        else []
        end
      end

      def edge_world_points(key, transform_context = nil)
        tr = entity_to_world(@entity, transform_context || @original_transform)
        edge_local_points(key).map { |point| point.transform(tr) }
      end

      def edge_midpoint_world(key, transform_context = nil)
        points = edge_world_points(key, transform_context)
        Geom::Point3d.linear_combination(0.5, points[0], 0.5, points[1])
      end

      def nearest_edge_key(view, x, y)
        best_key = nil
        best_distance = PICK_RADIUS + 1.0

        %i[u_min u_max v_min v_max].each do |key|
          a, b = edge_world_points(key).map { |point| view.screen_coords(point) }
          distance = distance_to_segment_2d(x.to_f, y.to_f, a.x.to_f, a.y.to_f, b.x.to_f, b.y.to_f)
          if distance <= PICK_RADIUS && distance < best_distance
            best_distance = distance
            best_key = key
          end
        end

        best_key
      rescue StandardError
        nil
      end

      def distance_to_segment_2d(px, py, ax, ay, bx, by)
        dx = bx - ax
        dy = by - ay
        len2 = dx * dx + dy * dy
        return Math.hypot(px - ax, py - ay) if len2 < 0.000001

        t = ((px - ax) * dx + (py - ay) * dy) / len2
        t = [[t, 0.0].max, 1.0].min
        Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
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

      def edge_coord(key)
        case key
        when :u_min then axis_min(@u_axis)
        when :u_max then axis_max(@u_axis)
        when :v_min then axis_min(@v_axis)
        when :v_max then axis_max(@v_axis)
        end
      end

      def begin_drag(key, view, x, y)
        @drag_edge = key
        @locked_edge = opposite_edge(key)
        @scale_axis = edge_axis(key)
        @fixed_coord = edge_coord(@locked_edge)
        @drag_coord = edge_coord(@drag_edge)
        @original_size = (@drag_coord - @fixed_coord).abs
        raise 'Kích thước theo hướng kéo bằng 0.' if @original_size < 0.000001

        @factor = 1.0
        @current_size = @original_size
        @preview_transform_context = @original_transform
        @dragging = true
        @moved = false
        @press_x = x
        @press_y = y

        @input_point.clear
        @snap_point = nil

        @anchor_screen = view.screen_coords(edge_midpoint_world(@locked_edge, @original_transform))
        @drag_screen = view.screen_coords(edge_midpoint_world(@drag_edge, @original_transform))
        @screen_axis = Geom::Vector3d.new(
          @drag_screen.x.to_f - @anchor_screen.x.to_f,
          @drag_screen.y.to_f - @anchor_screen.y.to_f,
          0.0
        )
        @screen_axis_len2 = @screen_axis.x * @screen_axis.x + @screen_axis.y * @screen_axis.y
        @screen_axis_len2 = 1.0 if @screen_axis_len2 < 1.0

        @state = :scale
        Sketchup.set_status_text('Kích thước', SB_VCB_LABEL)
        Sketchup.set_status_text(format_mm(@current_size), SB_VCB_VALUE)
        update_scale_preview(view, x, y)
      end

      def reset_scale
        @hover_edge = nil
        @drag_edge = nil
        @locked_edge = nil
        @scale_axis = nil
        @fixed_coord = nil
        @drag_coord = nil
        @original_size = 0.0
        @factor = 1.0
        @current_size = 0.0
        @dragging = false
        @moved = false
        @preview_transform_context = @original_transform if @original_transform
        @snap_point = nil
        @input_point.clear if @input_point
        clear_vcb
      end

      def update_scale_preview(view, x, y)
        return unless @dragging && @scale_axis

        target_coord = nil
        @input_point.pick(view, x, y)

        if @input_point.valid?
          world_to_local = entity_to_world(@entity, @original_transform).inverse
          local_point = @input_point.position.transform(world_to_local)
          target_coord = axis_value(local_point, @scale_axis)
          @snap_point = @input_point.position
          view.tooltip = @input_point.tooltip if view.respond_to?(:tooltip=)
        else
          @snap_point = nil
        end

        unless target_coord
          px = x.to_f - @anchor_screen.x.to_f
          py = y.to_f - @anchor_screen.y.to_f
          projection = (px * @screen_axis.x + py * @screen_axis.y) / @screen_axis_len2
          target_coord = @fixed_coord + (@drag_coord - @fixed_coord) * projection
        end

        denominator = @drag_coord - @fixed_coord
        candidate = (target_coord - @fixed_coord) / denominator

        if candidate <= MIN_FACTOR
          Sketchup.status_text = 'Không cho phép kéo vượt qua cạnh đang khóa.'
          return
        end

        @factor = valid_factor(candidate)
        @current_size = @original_size * @factor
        rebuild_preview_transform
        Sketchup.set_status_text(format_mm(@current_size), SB_VCB_VALUE)
      rescue StandardError => error
        puts "[TT Scale Edge preview] #{error.class}: #{error.message}"
      end

      def valid_factor(value)
        factor = value.to_f
        raise 'Hệ số Scale không hữu hạn.' unless factor.finite?
        raise 'Hệ số Scale phải lớn hơn 0.' unless factor > 0.0
        [factor, MIN_FACTOR].max
      end

      def rebuild_preview_transform
        raise 'Chưa chọn cạnh kéo.' unless @scale_axis

        factors = [1.0, 1.0, 1.0]
        factors[@scale_axis] = @factor

        center = @bbox.center
        anchor_values = [center.x, center.y, center.z]
        anchor_values[@scale_axis] = @fixed_coord
        anchor = Geom::Point3d.new(*anchor_values)

        to_anchor = Geom::Transformation.translation(anchor.to_a)
        from_anchor = Geom::Transformation.translation([-anchor.x, -anchor.y, -anchor.z])
        scale = Geom::Transformation.scaling(ORIGIN, factors[0], factors[1], factors[2])

        @preview_transform_context = @original_transform * to_anchor * scale * from_anchor
      end

      def commit_scale
        raise 'Đối tượng không còn hợp lệ.' unless valid_container?(@entity)
        raise 'Chưa chọn cạnh kéo.' unless @drag_edge

        @model.start_operation('TT - Scale Kéo Cạnh', true)
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
          'Đã Scale theo cạnh · cạnh đối diện giữ nguyên · tiếp tục rê cạnh khác để kéo.'
        true
      rescue StandardError
        @model.abort_operation if started rescue nil
        raise
      end

      def parse_target_length(raw)
        text = raw.to_s.strip
        if text.match?(/\A[-+]?\d+(?:\.\d+)?\z/)
          text.to_f.mm
        else
          text.to_l
        end
      end

      def format_mm(length)
        "#{length.to_mm.round(1)} mm"
      rescue StandardError
        length.to_s
      end

      def preview_world_corners
        return [] unless @entity && @bbox
        entity_world_corners(@entity, @preview_transform_context || @entity.transformation)
      end

      def draw_entity_box(view, entity, color, width)
        draw_box_edges(view, entity_world_corners(entity), color, width)
      end

      def draw_preview_box(view)
        draw_box_edges(
          view,
          preview_world_corners,
          Sketchup::Color.new(241, 150, 170),
          2
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

      def draw_face_edges(view)
        %i[u_min u_max v_min v_max].each do |key|
          hover = key == @hover_edge
          view.line_width = hover ? 5 : 3
          view.drawing_color = hover ?
            Sketchup::Color.new(255, 145, 20) :
            Sketchup::Color.new(45, 135, 235)
          view.draw(GL_LINES, edge_world_points(key))
        end

        if @hover_edge
          point = edge_midpoint_world(@hover_edge)
          view.draw_text(
            point,
            "KÉO CẠNH #{EDGE_NAMES[@hover_edge]}",
            color: Sketchup::Color.new(255, 120, 0)
          )
        end
      end

      def draw_drag_state(view)
        view.line_width = 5
        view.drawing_color = Sketchup::Color.new(45, 135, 235)
        view.draw(GL_LINES, edge_world_points(@drag_edge, @preview_transform_context))

        view.line_width = 4
        view.drawing_color = Sketchup::Color.new(230, 45, 45)
        view.draw(GL_LINES, edge_world_points(@locked_edge, @preview_transform_context))

        if @snap_point
          view.draw_points(
            [@snap_point],
            10,
            3,
            Sketchup::Color.new(255, 150, 20)
          )
        end
      end

      def draw_dimension_text(view)
        point = edge_midpoint_world(@drag_edge, @preview_transform_context)
        text = "#{format_mm(@current_size)} · #{EDGE_NAMES[@locked_edge]} KHÓA"
        view.draw_text(
          point,
          text,
          color: Sketchup::Color.new(30, 80, 160)
        )
      rescue StandardError
      end

      def update_status
        Sketchup.status_text = case @state
        when :pick_entity
          'SCALE KÉO CẠNH · click Group/Component cần chỉnh.'
        when :pick_edge
          if @hover_edge
            "Giữ chuột và kéo CẠNH #{EDGE_NAMES[@hover_edge]} · cạnh đối diện sẽ khóa · có bắt điểm."
          else
            'Rê trực tiếp vào 1 trong 4 cạnh màu xanh của mặt tấm rồi kéo.'
          end
        when :scale
          'ĐANG KÉO CẠNH · bắt Endpoint/Edge/Face/Inference · thả chuột để tạo · nhập mm rồi Enter.'
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
