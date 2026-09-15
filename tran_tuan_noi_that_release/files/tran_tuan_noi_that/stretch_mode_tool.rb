# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.5.0 - QUÉT VÙNG SAFE
#
# Mục tiêu:
# - QUÉT đúng vùng cần co/kéo, không cần chọn cả module.
# - KHÔNG bao giờ chọn vertex theo khung 2D để kéo trực tiếp (nguyên nhân gây mặt tam giác/spike).
# - Vùng quét chỉ xác định đối tượng và ĐẦU min/max nào của tấm nằm trong vùng.
# - Tấm LEAF dài theo trục: chỉ dịch TOÀN BỘ mặt đầu cực trị -> giữ mặt phẳng, giữ độ dày.
# - Tấm mỏng theo trục: dịch nguyên Group/Component.
# - Cụm nested (ngăn kéo/ray/phụ kiện): giữ nguyên hình dạng; không biến dạng mesh bên trong.
# - Chỉ mở tối đa 1 lớp container thuần để lấy các tấm/cụm trực tiếp.
# - Component dùng chung được Make Unique trước khi sửa geometry.
# - Một lượt co/kéo = một Undo.
# - TAB: quét vùng mới. ESC: hủy bước hiện tại / thoát tool.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    %i[
      VERSION AXES AXIS_COLORS MIN_SCAN_PX GUIDE_LENGTH
      MAX_CONTAINER_DEPTH THIN_AXIS_MAX THIN_AXIS_RATIO END_TOL_MIN END_TOL_MAX
    ].each do |name|
      remove_const(name) if const_defined?(name, false)
    end

    VERSION = '0.5.0'.freeze
    MIN_SCAN_PX = 5.0
    GUIDE_LENGTH = 500.mm
    MAX_CONTAINER_DEPTH = 1
    THIN_AXIS_MAX = 120.mm
    THIN_AXIS_RATIO = 0.18
    END_TOL_MIN = 0.25.mm
    END_TOL_MAX = 2.mm

    AXES = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, 0, 1)
    ].freeze

    AXIS_COLORS = [
      Sketchup::Color.new(220, 45, 45),
      Sketchup::Color.new(35, 165, 65),
      Sketchup::Color.new(45, 95, 220)
    ].freeze

    class Tool
      def initialize
        @model = Sketchup.active_model
        @context_to_world = @model.edit_transform
        @scope = initial_scope
        @mode = :scan
        @scanning = false
        @scan_start = nil
        @scan_current = nil
        @scan_rect = nil
        @affected_count = 0
        @anchor_root = Geom::Point3d.new(0, 0, 0)
        @axis = nil
        @axis_locked = false
        @drag_start_coord = nil
        @delta = 0.0
      end

      def activate
        update_status('CO GIÃN MODE · QUÉT đúng VÙNG đầu tấm/cụm cần kéo.')
        @model.active_view.invalidate
      end

      def deactivate(view)
        clear_vcb
        view.invalidate if view
      end

      def onCancel(_reason, view)
        case @mode
        when :drag
          @mode = :axis
          @drag_start_coord = nil
          @delta = 0.0
          update_status('Đã hủy kéo · chọn lại trục hoặc TAB quét vùng mới.')
        when :axis
          reset_scan
          update_status('Kéo khung QUÉT vùng mới.')
        when :scan
          if @scanning
            @scanning = false
            @scan_start = nil
            @scan_current = nil
          else
            @model.select_tool(nil)
            return
          end
        end
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        if tab_key?(key)
          return if @mode == :drag
          reset_scan
          update_status('TAB · QUÉT LẠI vùng cần co/kéo.')
          view.invalidate
          return
        end

        axis = axis_from_key(key)
        return unless axis && (@mode == :axis || @mode == :drag)
        @axis = axis
        @axis_locked = true
        update_status("Đã khóa trục #{axis_name(@axis)} · click điểm bắt đầu kéo.") if @mode == :axis
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        case @mode
        when :scan
          @scan_current = screen_point(x, y) if @scanning
        when :axis
          update_axis_from_cursor(view, x, y) unless @axis_locked
        when :drag
          update_drag(view, x, y)
        end
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT Stretch Region Safe move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        case @mode
        when :scan
          @scanning = true
          @scan_start = screen_point(x, y)
          @scan_current = @scan_start.clone
          update_status('Đang QUÉT VÙNG · thả chuột để chốt vùng co/kéo.')
        when :axis
          unless @axis
            UI.beep
            update_status('Rê chuột theo hướng cần kéo hoặc dùng ← = Y, → = X, ↑ = Z.')
            return
          end
          point = axis_point_from_mouse(view, x, y)
          unless point
            UI.beep
            return
          end
          @drag_start_coord = coord(world_to_root(point), @axis)
          @delta = 0.0
          @mode = :drag
          update_status("KÉO theo trục #{axis_name(@axis)} · click lần nữa để xác nhận.")
        when :drag
          commit_stretch(view)
          reset_scan
          update_status('Đã co/kéo vùng SAFE xong · QUÉT vùng tiếp theo.')
        end
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
        puts "[TT Stretch Region Safe click] #{error.class}: #{error.message}"
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @mode == :scan && @scanning
        @scan_current = screen_point(x, y)
        finish_scan(view)
        view.invalidate
      rescue StandardError => error
        @scanning = false
        UI.messagebox("Không quét được vùng co/kéo:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @mode == :drag && @axis
        raw = text.to_s.strip
        return UI.beep if raw.empty?
        @delta = raw.to_l
        update_vcb
        update_status("Khoảng co/kéo: #{Sketchup.format_length(@delta)} · click để xác nhận.")
        view.invalidate
      rescue StandardError
        UI.beep
      end

      def draw(view)
        draw_scan_rectangle(view, @scan_start, @scan_current, false) if @mode == :scan && @scanning
        if (@mode == :axis || @mode == :drag) && @scan_rect
          draw_fixed_scan_rect(view)
          draw_axis_guides(view)
          draw_moved_scan_rect(view) if @mode == :drag && @axis && @delta.abs > 0.001.mm
        end
      rescue StandardError => error
        puts "[TT Stretch Region Safe draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @scope.each { |entity| bb.add(entity.bounds) if entity.valid? }
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def selectable?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def initial_scope
        selected = @model.selection.to_a.select { |e| selectable?(e) && e.valid? }
        return selected.uniq unless selected.empty?
        @model.active_entities.to_a.select { |e| selectable?(e) && e.valid? }
      end

      def reset_scan
        @context_to_world = @model.edit_transform
        @scope = initial_scope
        @mode = :scan
        @scanning = false
        @scan_start = nil
        @scan_current = nil
        @scan_rect = nil
        @affected_count = 0
        @axis = nil
        @axis_locked = false
        @drag_start_coord = nil
        @delta = 0.0
        clear_vcb
      end

      def finish_scan(view)
        @scanning = false
        return false unless @scan_start && @scan_current
        if (@scan_current.x - @scan_start.x).abs < MIN_SCAN_PX ||
           (@scan_current.y - @scan_start.y).abs < MIN_SCAN_PX
          UI.beep
          update_status('Vùng quét quá nhỏ · kéo một khung lớn hơn.')
          return false
        end

        @scan_rect = normalize_rect(@scan_start, @scan_current)
        @affected_count = 0
        root_bb = Geom::BoundingBox.new

        @scope.each do |entity|
          next unless entity.valid?
          rect = instance_screen_rect(entity, Geom::Transformation.new, view)
          next unless rect && rect_relation(rect, @scan_rect) != :outside
          @affected_count += 1
          add_instance_bounds_to_root_bb(root_bb, entity, Geom::Transformation.new)
        end

        if @affected_count.zero? || root_bb.empty?
          UI.beep
          @scan_rect = nil
          update_status('Vùng quét chưa cắt qua Group/Component nào · quét lại.')
          return false
        end

        @anchor_root = clone_point(root_bb.center)
        @axis = nil
        @axis_locked = false
        @mode = :axis
        @model.selection.clear
        update_status("Đã nhận vùng · #{@affected_count} khối liên quan · chọn trục X/Y/Z.")
        true
      end

      def update_axis_from_cursor(view, x, y)
        return unless @scan_rect
        center_x = (@scan_rect[0] + @scan_rect[2]) * 0.5
        center_y = (@scan_rect[1] + @scan_rect[3]) * 0.5
        vx = x.to_f - center_x
        vy = y.to_f - center_y
        length = Math.sqrt(vx * vx + vy * vy)
        if length < 8.0
          @axis = nil
          return
        end
        vx /= length
        vy /= length

        origin_world = root_to_world(@anchor_root)
        origin_screen = view.screen_coords(origin_world)
        best_axis = nil
        best_score = -1.0
        3.times do |axis|
          p_root = @anchor_root + (AXES[axis] * GUIDE_LENGTH)
          p_screen = view.screen_coords(root_to_world(p_root))
          ax = p_screen.x - origin_screen.x
          ay = p_screen.y - origin_screen.y
          alen = Math.sqrt(ax * ax + ay * ay)
          next if alen < 0.001
          ax /= alen
          ay /= alen
          score = (vx * ax + vy * ay).abs
          if score > best_score
            best_score = score
            best_axis = axis
          end
        end
        @axis = best_axis
      end

      def begin_root_vector
        vector = AXES[@axis].clone
        return Geom::Vector3d.new(0, 0, 0) if @delta.abs < 0.001.mm
        vector.length = @delta.abs
        vector.reverse! if @delta < 0
        vector
      end

      def update_drag(view, x, y)
        point = axis_point_from_mouse(view, x, y)
        return unless point && @drag_start_coord
        current = coord(world_to_root(point), @axis)
        @delta = current - @drag_start_coord
        update_vcb
      end

      def axis_point_from_mouse(view, x, y)
        return nil unless @axis
        world_axis = AXES[@axis].transform(@context_to_world)
        return nil if world_axis.length < 0.001
        world_axis.normalize!
        points = Geom.closest_points(view.pickray(x, y), [root_to_world(@anchor_root), world_axis])
        points && points[1]
      rescue StandardError
        nil
      end

      def commit_stretch(view)
        return true if @delta.abs < 0.001.mm
        raise 'Chưa có vùng quét.' unless @scan_rect
        raise 'Chưa chọn trục co/kéo.' unless @axis

        root_vector = begin_root_vector
        @model.start_operation("TRẦN TUẤN - Co Giãn Vùng SAFE V#{VERSION}", true)
        begin
          actions = []
          action_keys = {}
          @scope.each do |entity|
            next unless entity.valid?
            collect_safe_actions(
              entity,
              Geom::Transformation.new,
              view,
              root_vector,
              actions,
              action_keys,
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

      # SAFE TREE RULES:
      # 1. entity hoàn toàn trong vùng -> move nguyên instance.
      # 2. crossing + pure container ở depth 0 -> mở đúng 1 lớp.
      # 3. crossing + nested assembly -> giữ nguyên hình dạng; chỉ move nếu đầu của assembly nằm trong vùng.
      # 4. crossing + leaf -> nếu mỏng theo trục: move nguyên khối; nếu dài: kéo đúng mặt đầu cực trị.
      def collect_safe_actions(entity, parent_to_root, view, root_vector, actions, action_keys, depth)
        return unless entity.valid?
        key = entity_key(entity)
        return if action_keys[key]

        rect = instance_screen_rect(entity, parent_to_root, view)
        return unless rect
        relation = rect_relation(rect, @scan_rect)
        return if relation == :outside

        if relation == :inside
          add_move_action(entity, parent_to_root, root_vector, actions, action_keys)
          return
        end

        definition = entity.definition
        children = definition.entities.to_a.select { |e| e.valid? && selectable?(e) }
        raw_edges = definition.entities.grep(Sketchup::Edge).select(&:valid?)
        pure_container = raw_edges.empty? && !children.empty?
        entity_to_root = parent_to_root * entity.transformation

        if pure_container && depth < MAX_CONTAINER_DEPTH
          children.each do |child|
            collect_safe_actions(child, entity_to_root, view, root_vector, actions, action_keys, depth + 1)
          end
          return
        end

        if !children.empty?
          # Assembly thật: tuyệt đối không kéo mesh con. Chỉ di chuyển nguyên cụm nếu đầu đang quét thuộc vùng.
          end_sign = chosen_end_sign_for_instance(entity, parent_to_root, view)
          add_move_action(entity, parent_to_root, root_vector, actions, action_keys) if end_sign
          return
        end

        collect_leaf_action(entity, parent_to_root, view, root_vector, actions, action_keys)
      end

      def collect_leaf_action(entity, parent_to_root, view, root_vector, actions, action_keys)
        if entity.is_a?(Sketchup::ComponentInstance) && entity.definition.instances.length > 1
          entity.make_unique
        end

        definition = entity.definition
        edges = definition.entities.grep(Sketchup::Edge).select(&:valid?)
        if edges.empty?
          end_sign = chosen_end_sign_for_instance(entity, parent_to_root, view)
          add_move_action(entity, parent_to_root, root_vector, actions, action_keys) if end_sign
          return
        end

        entity_to_root = parent_to_root * entity.transformation
        vertices = edges.flat_map(&:vertices).select(&:valid?).uniq
        data = vertex_axis_data(vertices, entity_to_root)
        return unless data

        span = data[:max] - data[:min]
        return if span <= 0.001.mm
        other_span = max_other_axis_span(vertices, entity_to_root, @axis)
        thin_limit = [THIN_AXIS_MAX, other_span * THIN_AXIS_RATIO].min
        end_sign = chosen_end_sign_for_vertices(vertices, entity_to_root, view, data)
        return unless end_sign

        if span <= thin_limit
          add_move_action(entity, parent_to_root, root_vector, actions, action_keys)
          return
        end

        extreme = end_sign > 0 ? data[:max] : data[:min]
        tol = [[span * 0.002, END_TOL_MIN].max, END_TOL_MAX].min
        end_vertices = vertices.select do |vertex|
          p = vertex.position.transform(entity_to_root)
          (coord(p, @axis) - extreme).abs <= tol
        end

        # Không đủ một mặt đầu rõ ràng => không deform để tránh phá mesh.
        if end_vertices.length < 2 || end_vertices.length >= vertices.length
          add_move_action(entity, parent_to_root, root_vector, actions, action_keys)
          return
        end

        local_vector = root_vector.transform(entity_to_root.inverse)
        action_keys[entity_key(entity)] = true
        actions << {
          kind: :move_end_vertices,
          entities: definition.entities,
          vertices: end_vertices,
          vector: local_vector
        }
      end

      def add_move_action(entity, parent_to_root, root_vector, actions, action_keys)
        key = entity_key(entity)
        return if action_keys[key]
        action_keys[key] = true
        actions << {
          kind: :move_instance,
          entity: entity,
          parent_to_root: parent_to_root,
          root_vector: root_vector
        }
      end

      def apply_action(action)
        case action[:kind]
        when :move_instance
          local_vector = action[:root_vector].transform(action[:parent_to_root].inverse)
          action[:entity].transform!(Geom::Transformation.translation(local_vector))
        when :move_end_vertices
          vectors = Array.new(action[:vertices].length) do
            v = action[:vector]
            Geom::Vector3d.new(v.x, v.y, v.z)
          end
          action[:entities].transform_by_vectors(action[:vertices], vectors)
        end
      end

      def entity_key(entity)
        entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.object_id
      end

      def vertex_axis_data(vertices, local_to_root)
        coords = vertices.map { |v| coord(v.position.transform(local_to_root), @axis) }
        return nil if coords.empty?
        { min: coords.min, max: coords.max }
      rescue StandardError
        nil
      end

      def max_other_axis_span(vertices, local_to_root, ignored_axis)
        spans = []
        3.times do |axis|
          next if axis == ignored_axis
          values = vertices.map { |v| coord(v.position.transform(local_to_root), axis) }
          spans << (values.max - values.min) unless values.empty?
        end
        spans.max || 0.0
      rescue StandardError
        0.0
      end

      def chosen_end_sign_for_instance(entity, parent_to_root, view)
        tr = parent_to_root * entity.transformation
        bb = entity.definition.bounds
        points = 8.times.map { |i| bb.corner(i).transform(tr) }
        choose_end_sign_from_root_points(points, view)
      rescue StandardError
        nil
      end

      def chosen_end_sign_for_vertices(vertices, local_to_root, view, data)
        span = data[:max] - data[:min]
        tol = [[span * 0.01, 0.5.mm].max, 5.mm].min
        min_points = []
        max_points = []
        vertices.each do |vertex|
          p = vertex.position.transform(local_to_root)
          c = coord(p, @axis)
          min_points << p if (c - data[:min]).abs <= tol
          max_points << p if (c - data[:max]).abs <= tol
        end
        choose_end_sign_from_sets(min_points, max_points, view)
      rescue StandardError
        nil
      end

      def choose_end_sign_from_root_points(points, view)
        values = points.map { |p| coord(p, @axis) }
        return nil if values.empty?
        min_c = values.min
        max_c = values.max
        tol = [(max_c - min_c) * 0.01, 0.5.mm].max
        min_points = points.select { |p| (coord(p, @axis) - min_c).abs <= tol }
        max_points = points.select { |p| (coord(p, @axis) - max_c).abs <= tol }
        choose_end_sign_from_sets(min_points, max_points, view)
      end

      def choose_end_sign_from_sets(min_points, max_points, view)
        min_score = end_screen_score(min_points, view)
        max_score = end_screen_score(max_points, view)
        return nil if min_score <= 0.0 && max_score <= 0.0
        return 1 if max_score > min_score
        return -1 if min_score > max_score

        # Hòa điểm: đầu nào gần tâm vùng quét hơn thì chọn.
        cx = (@scan_rect[0] + @scan_rect[2]) * 0.5
        cy = (@scan_rect[1] + @scan_rect[3]) * 0.5
        min_d = screen_set_distance(min_points, view, cx, cy)
        max_d = screen_set_distance(max_points, view, cx, cy)
        max_d < min_d ? 1 : -1
      end

      def end_screen_score(points, view)
        return 0.0 if points.empty?
        inside = 0
        points.each do |p|
          screen = view.screen_coords(root_to_world(p))
          inside += 1 if point_in_rect?(screen.x, screen.y, @scan_rect)
        end
        inside.to_f / points.length.to_f
      rescue StandardError
        0.0
      end

      def screen_set_distance(points, view, cx, cy)
        return Float::INFINITY if points.empty?
        points.map do |p|
          s = view.screen_coords(root_to_world(p))
          dx = s.x.to_f - cx
          dy = s.y.to_f - cy
          Math.sqrt(dx * dx + dy * dy)
        end.min
      rescue StandardError
        Float::INFINITY
      end

      def instance_screen_rect(entity, parent_to_root, view)
        tr = parent_to_root * entity.transformation
        bb = entity.definition.bounds
        xs = []
        ys = []
        8.times do |i|
          root_point = bb.corner(i).transform(tr)
          screen = view.screen_coords(root_to_world(root_point))
          xs << screen.x.to_f
          ys << screen.y.to_f
        end
        [xs.min, ys.min, xs.max, ys.max]
      rescue StandardError
        nil
      end

      def add_instance_bounds_to_root_bb(target_bb, entity, parent_to_root)
        tr = parent_to_root * entity.transformation
        bb = entity.definition.bounds
        8.times { |i| target_bb.add(bb.corner(i).transform(tr)) }
      rescue StandardError
        nil
      end

      def normalize_rect(a, b)
        [
          [a.x.to_f, b.x.to_f].min,
          [a.y.to_f, b.y.to_f].min,
          [a.x.to_f, b.x.to_f].max,
          [a.y.to_f, b.y.to_f].max
        ]
      end

      def rect_relation(rect, scan)
        return :outside if rect[2] < scan[0] || rect[0] > scan[2] || rect[3] < scan[1] || rect[1] > scan[3]
        inside = rect[0] >= scan[0] && rect[1] >= scan[1] && rect[2] <= scan[2] && rect[3] <= scan[3]
        inside ? :inside : :crossing
      end

      def point_in_rect?(x, y, rect)
        x.to_f >= rect[0] && x.to_f <= rect[2] && y.to_f >= rect[1] && y.to_f <= rect[3]
      end

      def draw_scan_rectangle(view, a, b, moved)
        return unless a && b
        color = moved ? Sketchup::Color.new(255, 170, 0) : Sketchup::Color.new(255, 120, 0)
        pts = [
          Geom::Point3d.new(a.x, a.y, 0),
          Geom::Point3d.new(b.x, a.y, 0),
          Geom::Point3d.new(b.x, b.y, 0),
          Geom::Point3d.new(a.x, b.y, 0)
        ]
        view.drawing_color = color
        view.line_width = moved ? 3 : 2
        view.draw2d(GL_LINE_LOOP, pts)
      end

      def draw_fixed_scan_rect(view)
        a = Geom::Point3d.new(@scan_rect[0], @scan_rect[1], 0)
        b = Geom::Point3d.new(@scan_rect[2], @scan_rect[3], 0)
        draw_scan_rectangle(view, a, b, false)
      end

      def draw_moved_scan_rect(view)
        origin = view.screen_coords(root_to_world(@anchor_root))
        moved_root = @anchor_root + begin_root_vector
        moved = view.screen_coords(root_to_world(moved_root))
        dx = moved.x - origin.x
        dy = moved.y - origin.y
        a = Geom::Point3d.new(@scan_rect[0] + dx, @scan_rect[1] + dy, 0)
        b = Geom::Point3d.new(@scan_rect[2] + dx, @scan_rect[3] + dy, 0)
        draw_scan_rectangle(view, a, b, true)
      end

      def draw_axis_guides(view)
        3.times do |axis|
          vector = AXES[axis] * GUIDE_LENGTH
          p1 = root_to_world(@anchor_root - vector)
          p2 = root_to_world(@anchor_root + vector)
          view.drawing_color = AXIS_COLORS[axis]
          view.line_width = (@axis == axis ? 4 : 1)
          view.draw(GL_LINES, [p1, p2])
        end
      end

      def screen_point(x, y)
        Geom::Point3d.new(x.to_f, y.to_f, 0)
      end

      def root_to_world(point)
        point.transform(@context_to_world)
      end

      def world_to_root(point)
        point.transform(@context_to_world.inverse)
      end

      def coord(point, axis)
        axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
      end

      def clone_point(point)
        Geom::Point3d.new(point.x, point.y, point.z)
      end

      def tab_key?(key)
        key == 9 || (defined?(VK_TAB) && key == VK_TAB)
      end

      def axis_from_key(key)
        return 0 if (defined?(VK_RIGHT) && key == VK_RIGHT) || key == 39
        return 1 if (defined?(VK_LEFT) && key == VK_LEFT) || key == 37
        return 2 if (defined?(VK_UP) && key == VK_UP) || key == 38
        nil
      end

      def axis_name(axis)
        %w[X Y Z][axis] || '?'
      end

      def update_vcb
        Sketchup.set_status_text('Khoảng co/kéo', SB_VCB_LABEL)
        Sketchup.set_status_text(Sketchup.format_length(@delta), SB_VCB_VALUE)
      end

      def clear_vcb
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      end

      def update_status(extra = nil)
        text = extra
        unless text
          text = case @mode
                 when :scan
                   @scanning ? 'Đang QUÉT VÙNG · thả chuột để chốt.' : 'QUÉT VÙNG đầu tấm/cụm cần co/kéo · không quét cả module.'
                 when :axis
                   axis_text = @axis ? axis_name(@axis) : '-'
                   "Vùng đã chốt · trục #{axis_text} · rê chuột chọn hướng hoặc ←Y →X ↑Z · click bắt đầu."
                 when :drag
                   update_vcb
                   "Đang kéo trục #{axis_name(@axis)} · #{Sketchup.format_length(@delta)} · click xác nhận · ESC hủy."
                 else
                   'CO GIÃN VÙNG SAFE'
                 end
        end
        Sketchup.set_status_text(text, SB_PROMPT)
      end
    end

    def self.activate
      Sketchup.active_model.select_tool(Tool.new)
      true
    end
  end
end
