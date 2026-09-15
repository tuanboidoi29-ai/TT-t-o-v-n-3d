# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.1.0
# Mục tiêu:
# - Chọn 1 Group/Component module.
# - Rê vào 1 trong 6 mặt khung bao -> click -> kéo -> click xác nhận.
# - Giữ nguyên độ dày tấm ván mỏng ở mép; tấm chạy dài theo trục sẽ được kéo dài.
# - Tấm/ngăn bên trong được tịnh tiến theo tỷ lệ khoảng trống.
# - Hỗ trợ Group/Component lồng bằng cách tác động vào leaf instance trong đúng hệ tọa độ cha.
# - 1 lần co giãn = 1 Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    VERSION = '0.1.0'.freeze
    MIN_SIZE = 30.mm
    PICK_TOL = 0.5.mm
    EDGE_TOL_MIN = 2.mm
    FULL_SPAN_RATIO = 0.35

    AXES = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, 0, 1)
    ].freeze

    class Tool
      def initialize(target)
        @target = target
        @dragging = false
        @hover_side = nil
        @side = nil
        @delta = 0.0
        @start_world = nil
        @start_coord = nil
        refresh_bounds
      end

      def activate
        unless valid_target?
          UI.messagebox('Co Giãn Khối MODE: hãy chọn đúng 1 Group hoặc Component.')
          Sketchup.active_model.select_tool(nil)
          return
        end
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onCancel(reason, view)
        if @dragging
          @dragging = false
          @side = nil
          @delta = 0.0
          update_status
          view.invalidate
        else
          Sketchup.active_model.select_tool(nil)
        end
      end

      def onMouseMove(flags, x, y, view)
        return unless valid_target?

        if @dragging
          update_drag_from_mouse(view, x, y)
        else
          @hover_side = pick_bbox_side(view, x, y)
        end
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT StretchMode move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(flags, x, y, view)
        return unless valid_target?

        unless @dragging
          side = @hover_side || pick_bbox_side(view, x, y)
          return UI.beep unless side
          @side = side
          @dragging = true
          @delta = 0.0
          @start_world = side[:hit]
          @start_coord = side[:coord]
          update_status
          view.invalidate
          return
        end

        commit_resize
        @dragging = false
        @side = nil
        @hover_side = nil
        @delta = 0.0
        refresh_bounds
        update_status('Đã co giãn xong. Chọn mặt khác để tiếp tục.')
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
        puts "[TT StretchMode click] #{error.class}: #{error.message}"
      end

      def onUserText(text, view)
        return UI.beep unless @dragging && @side
        raw = text.to_s.strip
        return UI.beep if raw.empty?

        old_size = axis_size(@side[:axis])
        sign = @side[:sign]

        if raw.start_with?('+', '-')
          value = raw.to_l
          @delta = value
        else
          new_size = raw.to_l
          raise 'Kích thước mới phải lớn hơn 0.' unless new_size && new_size > 0
          @delta = (new_size - old_size) / sign.to_f
        end

        clamp_delta!
        update_status
        view.invalidate
      rescue StandardError => error
        UI.beep
        Sketchup.set_status_text(error.message.to_s, SB_PROMPT)
      end

      def draw(view)
        return unless valid_target?

        side = @dragging ? @side : @hover_side
        draw_box(view, preview_bounds, Sketchup::Color.new(255, 128, 0), 2) if @dragging
        draw_box(view, @bounds, Sketchup::Color.new(100, 100, 100), 1) unless @dragging
        draw_side(view, side, @dragging ? preview_bounds : @bounds) if side
      rescue StandardError => error
        puts "[TT StretchMode draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        corners_for(preview_bounds).each { |p| bb.add(p.transform(@target.transformation)) }
        bb
      rescue StandardError
        @target.bounds
      end

      private

      def valid_target?
        @target && @target.valid? &&
          (@target.is_a?(Sketchup::Group) || @target.is_a?(Sketchup::ComponentInstance))
      end

      def refresh_bounds
        return unless valid_target?
        b = @target.definition.bounds
        @bounds = {
          min: Geom::Point3d.new(b.min.x, b.min.y, b.min.z),
          max: Geom::Point3d.new(b.max.x, b.max.y, b.max.z)
        }
      end

      def axis_size(axis)
        coord(@bounds[:max], axis) - coord(@bounds[:min], axis)
      end

      def preview_bounds
        return @bounds unless @dragging && @side
        mn = Geom::Point3d.new(@bounds[:min].x, @bounds[:min].y, @bounds[:min].z)
        mx = Geom::Point3d.new(@bounds[:max].x, @bounds[:max].y, @bounds[:max].z)
        axis = @side[:axis]
        if @side[:sign] > 0
          set_coord(mx, axis, coord(mx, axis) + @delta)
        else
          set_coord(mn, axis, coord(mn, axis) + @delta)
        end
        { min: mn, max: mx }
      end

      def clamp_delta!
        return unless @side
        old_size = axis_size(@side[:axis])
        new_size = old_size + @side[:sign] * @delta
        if new_size < MIN_SIZE
          @delta = (MIN_SIZE - old_size) / @side[:sign].to_f
        end
      end

      def update_drag_from_mouse(view, x, y)
        axis = @side[:axis]
        local_axis = AXES[axis]
        world_axis = local_axis.transform(@target.transformation)
        return if world_axis.length < 0.001
        world_axis.normalize!

        ray = view.pickray(x, y)
        axis_line = [@start_world, world_axis]
        points = Geom.closest_points(ray, axis_line)
        return unless points && points[1]

        local_point = points[1].transform(@target.transformation.inverse)
        @delta = coord(local_point, axis) - @start_coord
        clamp_delta!
      end

      def pick_bbox_side(view, x, y)
        ray = view.pickray(x, y)
        tr = @target.transformation
        inv = tr.inverse
        candidates = []

        3.times do |axis|
          [-1, 1].each do |sign|
            plane_coord = sign > 0 ? coord(@bounds[:max], axis) : coord(@bounds[:min], axis)
            local_origin = Geom::Point3d.new(0, 0, 0)
            set_coord(local_origin, axis, plane_coord)
            local_normal = AXES[axis].clone
            local_normal.reverse! if sign < 0

            world_origin = local_origin.transform(tr)
            world_normal = local_normal.transform(tr)
            next if world_normal.length < 0.001
            world_normal.normalize!

            hit = Geom.intersect_line_plane(ray, [world_origin, world_normal])
            next unless hit
            to_hit = hit - ray[0]
            next if to_hit.dot(ray[1]) < 0

            lp = hit.transform(inv)
            next unless point_on_bbox_face?(lp, axis, plane_coord)

            candidates << {
              axis: axis,
              sign: sign,
              hit: hit,
              coord: coord(lp, axis),
              distance: ray[0].distance(hit)
            }
          end
        end

        candidates.min_by { |item| item[:distance] }
      rescue StandardError
        nil
      end

      def point_on_bbox_face?(p, axis, plane_coord)
        return false if (coord(p, axis) - plane_coord).abs > PICK_TOL
        3.times.all? do |i|
          next true if i == axis
          v = coord(p, i)
          v >= coord(@bounds[:min], i) - PICK_TOL && v <= coord(@bounds[:max], i) + PICK_TOL
        end
      end

      def commit_resize
        raise 'Không còn đối tượng để co giãn.' unless valid_target?
        raise 'Chưa chọn mặt co giãn.' unless @side
        return if @delta.abs < 0.001.mm

        model = Sketchup.active_model
        model.start_operation("TRẦN TUẤN - Co Giãn Khối MODE V#{VERSION}", true)
        begin
          if @target.is_a?(Sketchup::ComponentInstance) && @target.definition.instances.length > 1
            @target.make_unique
          end

          refresh_bounds
          axis = @side[:axis]
          sign = @side[:sign]
          old_size = axis_size(axis)
          new_size = old_size + sign * @delta
          raise "Kích thước sau co giãn quá nhỏ (#{Sketchup.format_length(new_size)})." if new_size < MIN_SIZE

          old_min = coord(@bounds[:min], axis)
          old_max = coord(@bounds[:max], axis)
          fixed_coord = sign > 0 ? old_min : old_max
          moving_coord = sign > 0 ? old_max : old_min
          ratio = new_size / old_size

          actions = []
          root_entities = @target.definition.entities
          collect_actions(
            root_entities,
            Geom::Transformation.new,
            actions,
            axis,
            sign,
            @delta,
            old_min,
            old_max,
            fixed_coord,
            moving_coord,
            ratio,
            old_size
          )

          actions.each { |action| apply_action(action) }

          model.commit_operation
          true
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def collect_actions(entities, parent_to_root, actions, axis, sign, delta,
                          old_min, old_max, fixed_coord, moving_coord, ratio, old_size)
        raw_edges = entities.grep(Sketchup::Edge).select(&:valid?)
        unless raw_edges.empty?
          actions << {
            kind: :raw,
            entities: entities,
            items: raw_edges,
            parent_to_root: parent_to_root,
            root_transform: scale_transform(axis, fixed_coord, ratio)
          }
        end

        children = entities.to_a.select do |e|
          e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        end

        children.each do |child|
          child_entities = child.is_a?(Sketchup::Group) ? child.entities : child.definition.entities
          nested = child_entities.any? do |e|
            e.valid? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
          end

          if nested
            if child.is_a?(Sketchup::ComponentInstance) && child.definition.instances.length > 1
              child.make_unique
              child_entities = child.definition.entities
            end
            child_to_root = parent_to_root * child.transformation
            collect_actions(
              child_entities, child_to_root, actions, axis, sign, delta,
              old_min, old_max, fixed_coord, moving_coord, ratio, old_size
            )
            next
          end

          bb = entity_bounds_in_root(child, parent_to_root)
          next unless bb
          cmin = coord(bb[:min], axis)
          cmax = coord(bb[:max], axis)
          cspan = cmax - cmin
          next if cspan <= 0.001

          tol = [EDGE_TOL_MIN, old_size * 0.01].max
          near_moving = ((sign > 0 ? cmax : cmin) - moving_coord).abs <= tol
          near_fixed = ((sign > 0 ? cmin : cmax) - fixed_coord).abs <= tol
          span_ratio = cspan / old_size

          root_transform = if near_moving && !near_fixed && span_ratio < FULL_SPAN_RATIO
                             translation_transform(axis, delta)
                           elsif near_fixed && !near_moving && span_ratio < FULL_SPAN_RATIO
                             nil
                           elsif (near_fixed && near_moving) || span_ratio >= FULL_SPAN_RATIO
                             scale_transform(axis, fixed_coord, ratio)
                           else
                             center = (cmin + cmax) * 0.5
                             new_center = fixed_coord + (center - fixed_coord) * ratio
                             translation_transform(axis, new_center - center)
                           end

          next unless root_transform
          actions << {
            kind: :instance,
            entities: entities,
            item: child,
            parent_to_root: parent_to_root,
            root_transform: root_transform
          }
        end
      end

      def apply_action(action)
        parent_to_root = action[:parent_to_root]
        local_transform = parent_to_root.inverse * action[:root_transform] * parent_to_root
        if action[:kind] == :instance
          action[:entities].transform_entities(local_transform, action[:item])
        else
          action[:entities].transform_entities(local_transform, action[:items])
        end
      end

      def entity_bounds_in_root(entity, parent_to_root)
        local_to_root = parent_to_root * entity.transformation
        db = entity.definition.bounds
        points = 8.times.map { |i| db.corner(i).transform(local_to_root) }
        bb = Geom::BoundingBox.new
        points.each { |p| bb.add(p) }
        { min: bb.min, max: bb.max }
      rescue StandardError
        nil
      end

      def scale_transform(axis, fixed_coord, ratio)
        origin = Geom::Point3d.new(0, 0, 0)
        set_coord(origin, axis, fixed_coord)
        scales = [1.0, 1.0, 1.0]
        scales[axis] = ratio
        Geom::Transformation.scaling(origin, scales[0], scales[1], scales[2])
      end

      def translation_transform(axis, amount)
        vector = AXES[axis].clone
        vector.length = amount.abs
        vector.reverse! if amount < 0
        Geom::Transformation.translation(vector)
      end

      def corners_for(bounds)
        mn = bounds[:min]
        mx = bounds[:max]
        [
          Geom::Point3d.new(mn.x, mn.y, mn.z),
          Geom::Point3d.new(mx.x, mn.y, mn.z),
          Geom::Point3d.new(mx.x, mx.y, mn.z),
          Geom::Point3d.new(mn.x, mx.y, mn.z),
          Geom::Point3d.new(mn.x, mn.y, mx.z),
          Geom::Point3d.new(mx.x, mn.y, mx.z),
          Geom::Point3d.new(mx.x, mx.y, mx.z),
          Geom::Point3d.new(mn.x, mx.y, mx.z)
        ]
      end

      def draw_box(view, bounds, color, width)
        pts = corners_for(bounds).map { |p| p.transform(@target.transformation) }
        edges = [
          0,1, 1,2, 2,3, 3,0,
          4,5, 5,6, 6,7, 7,4,
          0,4, 1,5, 2,6, 3,7
        ]
        line_pts = edges.map { |i| pts[i] }
        view.drawing_color = color
        view.line_width = width
        view.draw(GL_LINES, line_pts)
      end

      def draw_side(view, side, bounds)
        points = side_points(bounds, side[:axis], side[:sign]).map { |p| p.transform(@target.transformation) }
        view.drawing_color = Sketchup::Color.new(255, 145, 0, 80)
        view.draw(GL_QUADS, points)
        view.drawing_color = Sketchup::Color.new(255, 115, 0)
        view.line_width = 3
        view.draw(GL_LINE_LOOP, points)
      end

      def side_points(bounds, axis, sign)
        mn, mx = bounds[:min], bounds[:max]
        c = sign > 0 ? coord(mx, axis) : coord(mn, axis)
        case axis
        when 0
          [
            Geom::Point3d.new(c, mn.y, mn.z), Geom::Point3d.new(c, mx.y, mn.z),
            Geom::Point3d.new(c, mx.y, mx.z), Geom::Point3d.new(c, mn.y, mx.z)
          ]
        when 1
          [
            Geom::Point3d.new(mn.x, c, mn.z), Geom::Point3d.new(mx.x, c, mn.z),
            Geom::Point3d.new(mx.x, c, mx.z), Geom::Point3d.new(mn.x, c, mx.z)
          ]
        else
          [
            Geom::Point3d.new(mn.x, mn.y, c), Geom::Point3d.new(mx.x, mn.y, c),
            Geom::Point3d.new(mx.x, mx.y, c), Geom::Point3d.new(mn.x, mx.y, c)
          ]
        end
      end

      def update_status(extra = nil)
        if @dragging && @side
          size = axis_size(@side[:axis]) + @side[:sign] * @delta
          Sketchup.set_status_text('Kích thước mới', SB_VCB_LABEL)
          Sketchup.set_status_text(Sketchup.format_length(size), SB_VCB_VALUE)
          text = extra || 'Kéo chuột hoặc nhập kích thước mới rồi Enter · Click để xác nhận · ESC hủy lượt kéo'
        else
          Sketchup.set_status_text('', SB_VCB_LABEL)
          Sketchup.set_status_text('', SB_VCB_VALUE)
          text = extra || 'CO GIÃN KHỐI MODE · Rê vào 1 trong 6 mặt khung cam · Click để bắt đầu kéo · ESC thoát'
        end
        Sketchup.set_status_text(text, SB_PROMPT)
      end

      def coord(point, axis)
        axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
      end

      def set_coord(point, axis, value)
        if axis == 0
          point.x = value
        elsif axis == 1
          point.y = value
        else
          point.z = value
        end
      end
    end

    def self.activate
      selection = Sketchup.active_model.selection.to_a
      target = selection.one? ? selection.first : nil
      unless target.is_a?(Sketchup::Group) || target.is_a?(Sketchup::ComponentInstance)
        UI.messagebox('Co Giãn Khối MODE: chọn đúng 1 Group hoặc Component module trước khi chạy.')
        return false
      end
      Sketchup.active_model.select_tool(Tool.new(target))
      true
    end
  end
end
