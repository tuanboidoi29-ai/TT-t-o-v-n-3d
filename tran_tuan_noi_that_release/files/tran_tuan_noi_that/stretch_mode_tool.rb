# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.3.0 SAFE
# FIX CHÍNH:
# - Giữ chế độ QUÉT nhiều Group/Component.
# - Không đệ quy biến dạng sâu làm cụm ngăn kéo / ray / phụ kiện bị kéo văng.
# - Chỉ mở tối đa 1 lớp container thuần (không có raw geometry) để lấy các cụm/tấm trực tiếp.
# - Cụm có Group/Component con được coi là ASSEMBLY: chỉ tịnh tiến nguyên cụm, không scale bên trong.
# - Chỉ tấm LEAF chạy gần hết kích thước module mới được kéo dài.
# - Tấm mỏng ở mép kéo chỉ tịnh tiến; mép neo đứng nguyên; vách giữa dịch theo tỷ lệ.
# - Mỗi đối tượng chỉ nhận đúng 1 action trong một lần co giãn.
# - Một lần co giãn = một Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    %i[
      VERSION MIN_SIZE PICK_TOL EDGE_TOL_MIN EDGE_TOL_MAX
      FULL_SPAN_RATIO THIN_SPAN_RATIO THIN_SPAN_MAX MAX_CONTAINER_DEPTH
      AXES
    ].each do |name|
      remove_const(name) if const_defined?(name, false)
    end

    VERSION = '0.3.0'.freeze
    MIN_SIZE = 30.mm
    PICK_TOL = 0.5.mm
    EDGE_TOL_MIN = 25.mm
    EDGE_TOL_MAX = 50.mm
    FULL_SPAN_RATIO = 0.72
    THIN_SPAN_RATIO = 0.18
    THIN_SPAN_MAX = 120.mm
    MAX_CONTAINER_DEPTH = 1

    AXES = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, 0, 1)
    ].freeze

    class Tool
      def initialize(initial_targets = nil)
        @model = Sketchup.active_model
        @targets = Array(initial_targets).select { |e| selectable?(e) && e.valid? }.uniq
        @context_to_world = @model.edit_transform
        @mode = @targets.empty? ? :scan : :stretch
        @scanning = false
        @scan_start = nil
        @scan_current = nil
        @dragging = false
        @hover_side = nil
        @side = nil
        @delta = 0.0
        @start_world = nil
        @start_coord = nil
        refresh_bounds if @mode == :stretch
      end

      def activate
        sync_selection if @mode == :stretch
        update_status
        @model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onCancel(_reason, view)
        if @dragging
          cancel_drag
        elsif @scanning
          @scanning = false
          @scan_start = nil
          @scan_current = nil
        elsif @mode == :stretch
          enter_scan_mode
        else
          @model.select_tool(nil)
          return
        end
        update_status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        tab = (key == 9) || (defined?(VK_TAB) && key == VK_TAB)
        return unless tab
        return if @dragging
        enter_scan_mode
        update_status('QUÉT LẠI: kéo khung qua các tấm/cụm cần co giãn.')
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        if @mode == :scan
          @scan_current = screen_point(x, y) if @scanning
        elsif @dragging
          update_drag_from_mouse(view, x, y)
        else
          @hover_side = pick_bbox_side(view, x, y)
        end
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT StretchMode move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        if @mode == :scan
          @scanning = true
          @scan_start = screen_point(x, y)
          @scan_current = @scan_start.clone
          update_status
          view.invalidate
          return
        end

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
        sync_selection
        update_status('Đã co giãn SAFE · cụm ngăn kéo/phụ kiện không bị biến dạng · TAB để quét lại.')
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
        puts "[TT StretchMode click] #{error.class}: #{error.message}"
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @mode == :scan && @scanning
        @scan_current = screen_point(x, y)
        finish_scan(view)
        view.invalidate
      rescue StandardError => error
        @scanning = false
        UI.messagebox("Không quét được module:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @mode == :stretch && @dragging && @side
        raw = text.to_s.strip
        return UI.beep if raw.empty?

        old_size = axis_size(@side[:axis])
        sign = @side[:sign]

        if raw.start_with?('+', '-')
          @delta = raw.to_l
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
        if @mode == :scan
          draw_scan_rectangle(view) if @scanning && @scan_start && @scan_current
          return
        end
        return unless valid_targets?

        side = @dragging ? @side : @hover_side
        draw_box(view, @dragging ? preview_bounds : @bounds,
                 @dragging ? Sketchup::Color.new(255, 128, 0) : Sketchup::Color.new(95, 95, 95),
                 @dragging ? 2 : 1)
        draw_side(view, side, @dragging ? preview_bounds : @bounds) if side
      rescue StandardError => error
        puts "[TT StretchMode draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        if @mode == :stretch && @bounds
          corners_for(preview_bounds).each { |p| bb.add(root_to_world(p)) }
        else
          @targets.each { |e| bb.add(e.bounds) if e.valid? }
        end
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def selectable?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def valid_targets?
        @targets && !@targets.empty? && @targets.all? { |e| selectable?(e) && e.valid? }
      end

      def screen_point(x, y)
        Geom::Point3d.new(x.to_f, y.to_f, 0)
      end

      def active_parent
        @model.active_entities.parent
      rescue StandardError
        nil
      end

      def same_active_context?(entity)
        parent = active_parent
        parent.nil? || entity.parent == parent
      rescue StandardError
        true
      end

      def enter_scan_mode
        cancel_drag
        @mode = :scan
        @targets = []
        @bounds = nil
        @hover_side = nil
        @scanning = false
        @scan_start = nil
        @scan_current = nil
        @model.selection.clear
      end

      def finish_scan(view)
        start_pt = @scan_start
        end_pt = @scan_current
        @scanning = false
        @scan_start = nil
        @scan_current = nil

        dx = (end_pt.x - start_pt.x).abs
        dy = (end_pt.y - start_pt.y).abs
        ph = view.pick_helper

        picked = if dx < 4.0 && dy < 4.0
                   ph.do_pick(end_pt.x.to_i, end_pt.y.to_i, 3)
                   ph.all_picked
                 else
                   pick_type = end_pt.x >= start_pt.x ? Sketchup::PickHelper::PICK_INSIDE : Sketchup::PickHelper::PICK_CROSSING
                   ph.window_pick(start_pt, end_pt, pick_type)
                   ph.all_picked
                 end

        targets = Array(picked).select do |e|
          selectable?(e) && e.valid? && same_active_context?(e)
        end.uniq

        if targets.empty?
          UI.beep
          update_status('Không bắt được Group/Component ở context hiện tại. Quét lại qua module.')
          return false
        end

        @targets = remove_duplicate_nested_targets(targets)
        @mode = :stretch
        refresh_bounds
        sync_selection
        @hover_side = nil
        update_status("Đã quét #{@targets.length} khối cấp hiện tại · rê vào mặt khung cam để co/kéo.")
        true
      end

      def remove_duplicate_nested_targets(targets)
        # PickHelper có thể trả cả parent lẫn child. Ở chế độ SAFE chỉ giữ entity cùng active context.
        targets.select { |e| same_active_context?(e) }.uniq
      end

      def sync_selection
        @model.selection.clear
        @targets.each { |e| @model.selection.add(e) if e.valid? }
      rescue StandardError
        nil
      end

      def draw_scan_rectangle(view)
        x1, y1 = @scan_start.x, @scan_start.y
        x2, y2 = @scan_current.x, @scan_current.y
        pts = [
          Geom::Point3d.new(x1, y1, 0),
          Geom::Point3d.new(x2, y1, 0),
          Geom::Point3d.new(x2, y2, 0),
          Geom::Point3d.new(x1, y2, 0)
        ]
        view.drawing_color = Sketchup::Color.new(255, 128, 0)
        view.line_width = 2
        view.draw2d(GL_LINE_LOOP, pts)
      end

      def refresh_bounds
        return unless valid_targets?
        bb = Geom::BoundingBox.new
        @targets.each do |target|
          data = instance_bounds_in_root(target, Geom::Transformation.new)
          next unless data
          corners_for(data).each { |p| bb.add(p) }
        end
        raise 'Không đọc được khung bao module.' if bb.empty?
        @bounds = {
          min: clone_point(bb.min),
          max: clone_point(bb.max)
        }
      end

      def axis_size(axis)
        coord(@bounds[:max], axis) - coord(@bounds[:min], axis)
      end

      def preview_bounds
        return @bounds unless @dragging && @side
        mn = clone_point(@bounds[:min])
        mx = clone_point(@bounds[:max])
        axis = @side[:axis]
        if @side[:sign] > 0
          set_coord(mx, axis, coord(mx, axis) + @delta)
        else
          set_coord(mn, axis, coord(mn, axis) + @delta)
        end
        { min: mn, max: mx }
      end

      def cancel_drag
        @dragging = false
        @side = nil
        @delta = 0.0
        @start_world = nil
        @start_coord = nil
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
        world_axis = AXES[axis].transform(@context_to_world)
        return if world_axis.length < 0.001
        world_axis.normalize!

        ray = view.pickray(x, y)
        points = Geom.closest_points(ray, [@start_world, world_axis])
        return unless points && points[1]

        root_point = world_to_root(points[1])
        @delta = coord(root_point, axis) - @start_coord
        clamp_delta!
      end

      def pick_bbox_side(view, x, y)
        return nil unless @bounds
        ray = view.pickray(x, y)
        candidates = []

        3.times do |axis|
          [-1, 1].each do |sign|
            plane_coord = sign > 0 ? coord(@bounds[:max], axis) : coord(@bounds[:min], axis)
            root_origin = Geom::Point3d.new(0, 0, 0)
            set_coord(root_origin, axis, plane_coord)
            root_normal = AXES[axis].clone
            root_normal.reverse! if sign < 0

            world_origin = root_to_world(root_origin)
            world_normal = root_normal.transform(@context_to_world)
            next if world_normal.length < 0.001
            world_normal.normalize!

            hit = Geom.intersect_line_plane(ray, [world_origin, world_normal])
            next unless hit
            to_hit = hit - ray[0]
            next if to_hit.dot(ray[1]) < 0

            rp = world_to_root(hit)
            next unless point_on_bbox_face?(rp, axis, plane_coord)

            candidates << {
              axis: axis,
              sign: sign,
              hit: hit,
              coord: coord(rp, axis),
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
        raise 'Chưa quét module cần co giãn.' unless valid_targets?
        raise 'Chưa chọn mặt co giãn.' unless @side
        return true if @delta.abs < 0.001.mm

        refresh_bounds
        axis = @side[:axis]
        sign = @side[:sign]
        old_size = axis_size(axis)
        new_size = old_size + sign * @delta
        raise "Kích thước sau co giãn quá nhỏ (#{Sketchup.format_length(new_size)})." if new_size < MIN_SIZE

        fixed_coord = sign > 0 ? coord(@bounds[:min], axis) : coord(@bounds[:max], axis)
        moving_coord = sign > 0 ? coord(@bounds[:max], axis) : coord(@bounds[:min], axis)

        @model.start_operation("TRẦN TUẤN - Co Giãn Khối MODE SAFE V#{VERSION}", true)
        begin
          actions = []
          action_keys = {}

          @targets.each do |target|
            collect_safe_actions(
              target,
              @model.active_entities,
              Geom::Transformation.new,
              actions,
              action_keys,
              axis,
              sign,
              @delta,
              old_size,
              fixed_coord,
              moving_coord,
              0
            )
          end

          actions.each { |action| apply_action(action) }
          @model.commit_operation
          true
        rescue StandardError
          @model.abort_operation
          raise
        end
      end

      def collect_safe_actions(entity, parent_entities, parent_to_root, actions, action_keys,
                               axis, sign, delta, old_size, fixed_coord, moving_coord, depth)
        return unless entity.valid?

        definition = entity.definition
        child_entities = definition.entities
        nested = child_entities.to_a.select { |e| e.valid? && selectable?(e) }
        raw_edges = child_entities.grep(Sketchup::Edge).select(&:valid?)

        # Chỉ mở đúng 1 lớp nếu đây là container THUẦN: không raw geometry, chỉ chứa các khối con.
        if depth < MAX_CONTAINER_DEPTH && raw_edges.empty? && !nested.empty?
          if entity.is_a?(Sketchup::ComponentInstance) && definition.instances.length > 1
            entity.make_unique
            definition = entity.definition
            child_entities = definition.entities
            nested = child_entities.to_a.select { |e| e.valid? && selectable?(e) }
          end

          entity_to_root = parent_to_root * entity.transformation
          nested.each do |child|
            collect_safe_actions(
              child,
              child_entities,
              entity_to_root,
              actions,
              action_keys,
              axis,
              sign,
              delta,
              old_size,
              fixed_coord,
              moving_coord,
              depth + 1
            )
          end
          return
        end

        bb = instance_bounds_in_root(entity, parent_to_root)
        return unless bb

        # Có nested ở lớp này => coi là assembly nguyên khối, KHÔNG biến dạng geometry con.
        if !nested.empty?
          decision = classify_assembly_bounds(bb, axis, sign, delta, old_size, fixed_coord, moving_coord)
          add_move_action(actions, action_keys, parent_entities, entity, parent_to_root, axis, decision[:amount]) if decision
          return
        end

        # Leaf thực sự => có thể move hoặc stretch geometry đúng 1 lần.
        decision = classify_leaf_bounds(bb, axis, sign, delta, old_size, fixed_coord, moving_coord)
        return unless decision

        if decision[:kind] == :move
          add_move_action(actions, action_keys, parent_entities, entity, parent_to_root, axis, decision[:amount])
          return
        end

        if entity.is_a?(Sketchup::ComponentInstance) && entity.definition.instances.length > 1
          entity.make_unique
        end

        edges = entity.definition.entities.grep(Sketchup::Edge).select(&:valid?)
        return if edges.empty?
        key = [:deform, entity.persistent_id]
        return if action_keys[key]
        action_keys[key] = true

        entity_to_root = parent_to_root * entity.transformation
        actions << {
          kind: :deform_geometry,
          entities: entity.definition.entities,
          items: edges,
          entity_to_root: entity_to_root,
          root_transform: scale_transform(axis, decision[:anchor], decision[:ratio])
        }
      end

      def add_move_action(actions, action_keys, parent_entities, entity, parent_to_root, axis, amount)
        return if amount.nil? || amount.abs < 0.001.mm
        key = [:move, entity.persistent_id]
        return if action_keys[key]
        action_keys[key] = true
        actions << {
          kind: :move_instance,
          parent_entities: parent_entities,
          entity: entity,
          parent_to_root: parent_to_root,
          root_transform: translation_transform(axis, amount)
        }
      end

      def classify_assembly_bounds(bb, axis, sign, delta, old_size, fixed_coord, moving_coord)
        cmin = coord(bb[:min], axis)
        cmax = coord(bb[:max], axis)
        span = cmax - cmin
        return nil if span <= 0.001.mm

        tol = edge_tolerance(old_size)
        near_moving = ((sign > 0 ? cmax : cmin) - moving_coord).abs <= tol
        near_fixed = ((sign > 0 ? cmin : cmax) - fixed_coord).abs <= tol
        compact = (span / old_size) <= 0.40

        return { kind: :move, amount: delta } if near_moving && !near_fixed && compact
        return nil if near_fixed && !near_moving && compact

        { kind: :move, amount: proportional_move(cmin, cmax, fixed_coord, moving_coord, delta) }
      end

      def classify_leaf_bounds(bb, axis, sign, delta, old_size, fixed_coord, moving_coord)
        cmin = coord(bb[:min], axis)
        cmax = coord(bb[:max], axis)
        span = cmax - cmin
        return nil if span <= 0.001.mm

        tol = edge_tolerance(old_size)
        near_moving = ((sign > 0 ? cmax : cmin) - moving_coord).abs <= tol
        near_fixed = ((sign > 0 ? cmin : cmax) - fixed_coord).abs <= tol
        thin_limit = [old_size * THIN_SPAN_RATIO, THIN_SPAN_MAX].min
        thin = span <= thin_limit
        span_ratio = span / old_size
        full_span = (near_fixed && near_moving) || span_ratio >= FULL_SPAN_RATIO

        if thin
          return { kind: :move, amount: delta } if near_moving && !near_fixed
          return nil if near_fixed && !near_moving
          return { kind: :move, amount: proportional_move(cmin, cmax, fixed_coord, moving_coord, delta) }
        end

        if full_span
          new_span = span + sign * delta
          raise 'Một tấm chạy toàn module sẽ bị co về kích thước quá nhỏ.' if new_span < 1.mm
          anchor = sign > 0 ? cmin : cmax
          return { kind: :stretch, anchor: anchor, ratio: new_span / span }
        end

        # Không đủ dài để chắc chắn là nóc/đáy/đợt toàn module => chỉ dịch, tuyệt đối không stretch.
        { kind: :move, amount: proportional_move(cmin, cmax, fixed_coord, moving_coord, delta) }
      end

      def edge_tolerance(old_size)
        [[old_size * 0.03, EDGE_TOL_MIN].max, EDGE_TOL_MAX].min
      end

      def proportional_move(cmin, cmax, fixed_coord, moving_coord, delta)
        center = (cmin + cmax) * 0.5
        denominator = moving_coord - fixed_coord
        t = denominator.abs < 0.001.mm ? 0.0 : (center - fixed_coord) / denominator
        t = [[t, 0.0].max, 1.0].min
        delta * t
      end

      def apply_action(action)
        case action[:kind]
        when :move_instance
          local = action[:parent_to_root].inverse * action[:root_transform] * action[:parent_to_root]
          action[:parent_entities].transform_entities(local, action[:entity])
        when :deform_geometry
          local = action[:entity_to_root].inverse * action[:root_transform] * action[:entity_to_root]
          action[:entities].transform_entities(local, action[:items])
        end
      end

      def instance_bounds_in_root(entity, parent_to_root)
        local_to_root = parent_to_root * entity.transformation
        db = entity.definition.bounds
        bb = Geom::BoundingBox.new
        8.times { |i| bb.add(db.corner(i).transform(local_to_root)) }
        { min: clone_point(bb.min), max: clone_point(bb.max) }
      rescue StandardError
        nil
      end

      def scale_transform(axis, anchor_coord, ratio)
        origin = Geom::Point3d.new(0, 0, 0)
        set_coord(origin, axis, anchor_coord)
        scales = [1.0, 1.0, 1.0]
        scales[axis] = ratio
        Geom::Transformation.scaling(origin, scales[0], scales[1], scales[2])
      end

      def translation_transform(axis, amount)
        vector = AXES[axis].clone
        return Geom::Transformation.new if amount.abs < 0.001.mm
        vector.length = amount.abs
        vector.reverse! if amount < 0
        Geom::Transformation.translation(vector)
      end

      def root_to_world(point)
        point.transform(@context_to_world)
      end

      def world_to_root(point)
        point.transform(@context_to_world.inverse)
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
        pts = corners_for(bounds).map { |p| root_to_world(p) }
        indices = [
          0,1, 1,2, 2,3, 3,0,
          4,5, 5,6, 6,7, 7,4,
          0,4, 1,5, 2,6, 3,7
        ]
        view.drawing_color = color
        view.line_width = width
        view.draw(GL_LINES, indices.map { |i| pts[i] })
      end

      def draw_side(view, side, bounds)
        points = side_points(bounds, side[:axis], side[:sign]).map { |p| root_to_world(p) }
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
        if @mode == :scan
          if @scanning
            direction = @scan_current && @scan_start && @scan_current.x < @scan_start.x ? 'CẮT QUA' : 'NẰM TRONG'
            text = extra || "QUÉT #{direction} · thả chuột để nhận Group/Component cấp hiện tại"
          else
            text = extra || 'CO GIÃN SAFE · QUÉT module · cụm ngăn kéo/phụ kiện sẽ giữ nguyên hình dạng'
          end
          Sketchup.set_status_text('', SB_VCB_LABEL)
          Sketchup.set_status_text('', SB_VCB_VALUE)
        elsif @dragging && @side
          size = axis_size(@side[:axis]) + @side[:sign] * @delta
          Sketchup.set_status_text('Kích thước mới', SB_VCB_LABEL)
          Sketchup.set_status_text(Sketchup.format_length(size), SB_VCB_VALUE)
          text = extra || 'Kéo chuột hoặc nhập kích thước mới rồi Enter · Click xác nhận · ESC hủy lượt kéo'
        else
          Sketchup.set_status_text('', SB_VCB_LABEL)
          Sketchup.set_status_text('', SB_VCB_VALUE)
          text = extra || "Đã chọn #{@targets.length} khối · rê vào mặt khung · Click kéo · TAB quét lại"
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

      def clone_point(point)
        Geom::Point3d.new(point.x, point.y, point.z)
      end
    end

    def self.activate
      model = Sketchup.active_model
      parent = model.active_entities.parent rescue nil
      preselected = model.selection.to_a.select do |entity|
        next false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        parent.nil? || entity.parent == parent
      end
      model.select_tool(Tool.new(preselected))
      true
    end
  end
end
