# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.7.0 - ĐA HƯỚNG 3D
#
# QUY TRÌNH:
# - P1 = biên cố định.
# - P2 = phía cần co/kéo. Tự nhận đủ 6 hướng: X+/X-/Y+/Y-/Z+/Z- theo Model Axis.
# - P3 = vị trí mới; hoặc gõ 200mm để co/kéo thêm 200mm.
# - Gõ =1200mm để đặt khoảng P1 -> biên mới thành đúng 1200mm.
# - TAB ở bước P3 bật/tắt THÊM HƯỚNG.
# - Hoặc giữ SHIFT khi xác nhận P3 để lưu hướng hiện tại và tiếp tục P1/P2 hướng khác.
# - Hướng cuối xác nhận bình thường => áp dụng toàn bộ hướng trong CÙNG 1 Undo.
# - Khi đang có hướng chờ, Enter ở bước P1 => áp dụng các hướng đã lưu.
#
# HÌNH HỌC AN TOÀN:
# - Không phụ thuộc camera để chọn trục.
# - Không scale toàn bộ tấm.
# - Không kéo vertex theo khung 2D.
# - Khối nằm trọn phía được chọn => tịnh tiến nguyên khối.
# - Tấm leaf cắt qua P1 => chỉ dịch TOÀN BỘ mặt đầu cực trị phía P2.
# - Container thuần => đi vào các phần tử con.
# - Cụm nested có hình học riêng (ngăn kéo/ray/phụ kiện) => giữ nguyên hình dạng.
# - Một thao tác đa hướng = một Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    %i[
      VERSION AXES AXIS_COLORS MIN_GESTURE_PX MIN_AXIS_DELTA
      CUT_TOL END_TOL THIN_AXIS_MAX THIN_AXIS_RATIO SHIFT_MASK
    ].each do |name|
      remove_const(name) if const_defined?(name, false)
    end

    VERSION = '0.7.0'.freeze
    MIN_GESTURE_PX = 6.0
    MIN_AXIS_DELTA = 2.mm
    CUT_TOL = 0.5.mm
    END_TOL = 0.75.mm
    THIN_AXIS_MAX = 120.mm
    THIN_AXIS_RATIO = 0.18
    SHIFT_MASK = 4

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
        @scope_bounds = scope_bounds_root

        @state = :p1
        @ip = Sketchup::InputPoint.new
        @ip1 = Sketchup::InputPoint.new
        @ip2 = Sketchup::InputPoint.new

        @p1_root = nil
        @p2_root = nil
        @axis = nil
        @side_sign = 1
        @cut_coord = nil
        @ref_coord = nil
        @delta = 0.0

        @gesture_start = nil
        @first_press_active = false
        @pending_regions = []
        @add_mode = false
        @shift_down = false
      end

      def activate
        if @scope.empty?
          UI.messagebox('Co Giãn Khối MODE: không có Group/Component trong vùng làm việc. Hãy chọn tủ/module hoặc mở đúng context rồi chạy lại.')
          @model.select_tool(nil)
          return
        end
        update_status('P1 · Bắt BIÊN CỐ ĐỊNH. Có thể co/kéo đủ 6 hướng X± Y± Z±.')
        @model.active_view.invalidate
      end

      def deactivate(view)
        clear_vcb
        view.invalidate if view
      end

      def onCancel(_reason, view)
        case @state
        when :p3, :p2
          reset_current_points
          update_status(@pending_regions.empty? ? 'Đã hủy vùng hiện tại · bắt lại P1.' : "Đã hủy vùng hiện tại · còn #{@pending_regions.length} hướng chờ · bắt P1 tiếp hoặc Enter để áp dụng.")
        else
          unless @pending_regions.empty?
            @pending_regions.clear
            @add_mode = false
            update_status('Đã hủy toàn bộ các hướng đang chờ. Bắt P1 để làm lại.')
          else
            @model.select_tool(nil)
            return
          end
        end
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        @shift_down = true if shift_key?(key)

        if tab_key?(key) && @state == :p3
          @add_mode = !@add_mode
          update_status(@add_mode ? 'THÊM HƯỚNG = BẬT · xác nhận P3/nhập số sẽ lưu hướng rồi quay lại P1.' : 'THÊM HƯỚNG = TẮT · xác nhận tiếp theo sẽ hoàn tất và áp dụng.')
          view.invalidate
          return
        end

        if enter_key?(key) && @state == :p1 && !@pending_regions.empty?
          commit_regions(@pending_regions)
          count = @pending_regions.length
          @pending_regions.clear
          reset_current_points
          update_status("Đã áp dụng #{count} hướng trong 1 Undo · bắt P1 cho lượt mới.")
          view.invalidate
        end
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
      end

      def onKeyUp(key, _repeat, _flags, _view)
        @shift_down = false if shift_key?(key)
      end

      def onMouseMove(_flags, x, y, view)
        case @state
        when :p1
          @ip.pick(view, x, y)
        when :p2
          @ip.pick(view, x, y, @ip1)
          update_p2_preview
        when :p3
          update_p3_delta(view, x, y)
        end
        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT Stretch Multi move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when :p1
          @ip1.pick(view, x, y)
          unless @ip1.valid?
            UI.beep
            return
          end
          @p1_root = world_to_root(@ip1.position)
          @gesture_start = Geom::Point3d.new(x.to_f, y.to_f, 0)
          @first_press_active = true
          @state = :p2
          @ip.pick(view, x, y, @ip1)
          update_status('P2 · Kéo/quét về PHÍA cần co giãn rồi thả, hoặc click P2.')

        when :p2
          finalize_p2(view, x, y)

        when :p3
          return UI.beep if @delta.abs < 0.001.mm
          finish_current_direction(add_direction?(flags))
        end
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
        puts "[TT Stretch Multi click] #{error.class}: #{error.message}"
      end

      def onLButtonUp(flags, x, y, view)
        return unless @state == :p2 && @first_press_active
        @first_press_active = false

        finish = Geom::Point3d.new(x.to_f, y.to_f, 0)
        distance = @gesture_start ? @gesture_start.distance(finish) : 0.0
        finalize_p2(view, x, y) if distance >= MIN_GESTURE_PX
        @shift_down = true if shift_modifier?(flags)
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Không nhận được P2:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @state == :p3 && @axis
        raw = text.to_s.strip
        return UI.beep if raw.empty?

        if raw.start_with?('=')
          desired = raw[1..-1].to_s.strip.to_l
          raise 'Kích thước đích phải lớn hơn 0.' unless desired && desired > 0
          current_span = (@ref_coord - @cut_coord).abs
          delta_mag = desired.to_f - current_span
          @delta = delta_mag * @side_sign
        else
          amount = raw.to_l
          @delta = amount.to_f * @side_sign
        end

        return UI.beep if @delta.abs < 0.001.mm
        finish_current_direction(@add_mode || @shift_down)
        view.invalidate
      rescue StandardError => error
        UI.beep
        UI.messagebox("Không thể co/kéo theo kích thước nhập:\n#{error.message}")
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && (@state == :p1 || @state == :p2)
        @ip1.draw(view) if @ip1.valid?
        @ip2.draw(view) if @ip2.valid?

        draw_pending_regions(view)

        return unless @p1_root

        if @state == :p2 && @ip.valid?
          preview_p2 = world_to_root(@ip.position)
          axis = dominant_axis(@p1_root, preview_p2)
          draw_axis_hint(view, @p1_root, preview_p2, axis) if axis
        end

        return unless @axis && @cut_coord

        draw_cut_plane(view, @axis, @cut_coord, Sketchup::Color.new(255, 80, 0), 3)
        draw_side_arrow(view, current_region(false)) if @ref_coord
        draw_cut_plane(view, @axis, @ref_coord, Sketchup::Color.new(255, 165, 0), 1) if @ref_coord

        if @state == :p3 && @delta.abs > 0.001.mm
          draw_cut_plane(view, @axis, @ref_coord + @delta, AXIS_COLORS[@axis], 3)
          draw_delta_arrow(view)
        end
      rescue StandardError => error
        puts "[TT Stretch Multi draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @scope.each { |entity| bb.add(entity.bounds) if entity.valid? }
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      # ------------------------------------------------------------
      # STATE / INPUT
      # ------------------------------------------------------------

      def reset_current_points
        @context_to_world = @model.edit_transform
        @scope = initial_scope
        @scope_bounds = scope_bounds_root
        @state = :p1
        @ip = Sketchup::InputPoint.new
        @ip1 = Sketchup::InputPoint.new
        @ip2 = Sketchup::InputPoint.new
        @p1_root = nil
        @p2_root = nil
        @axis = nil
        @side_sign = 1
        @cut_coord = nil
        @ref_coord = nil
        @delta = 0.0
        @gesture_start = nil
        @first_press_active = false
        @add_mode = false
        clear_vcb
      end

      def update_p2_preview
        return unless @p1_root && @ip.valid?
        p2 = world_to_root(@ip.position)
        axis = dominant_axis(@p1_root, p2)
        return unless axis
        diff = coord(p2, axis) - coord(@p1_root, axis)
        Sketchup.set_status_text('Vùng', SB_VCB_LABEL)
        Sketchup.set_status_text("#{axis_name(axis)}#{diff >= 0 ? '+' : '-'}", SB_VCB_VALUE)
      end

      def finalize_p2(view, x, y)
        @ip2.pick(view, x, y, @ip1)
        unless @ip2.valid?
          UI.beep
          return false
        end

        p2 = world_to_root(@ip2.position)
        axis = dominant_axis(@p1_root, p2)
        unless axis
          UI.beep
          update_status('P2 quá gần P1 · hãy quét rõ theo một trong 6 hướng X± Y± Z±.')
          return false
        end

        diff = coord(p2, axis) - coord(@p1_root, axis)
        if diff.abs < MIN_AXIS_DELTA
          UI.beep
          update_status('P2 chưa tạo được hướng rõ ràng · chọn lại P2.')
          return false
        end

        @p2_root = p2
        @axis = axis
        @side_sign = diff >= 0 ? 1 : -1
        @cut_coord = coord(@p1_root, @axis)
        @ref_coord = coord(@p2_root, @axis)
        @delta = 0.0
        @state = :p3
        @first_press_active = false

        Sketchup.set_status_text('Co/kéo', SB_VCB_LABEL)
        Sketchup.set_status_text('0', SB_VCB_VALUE)
        update_status("#{axis_name(@axis)}#{@side_sign > 0 ? '+' : '-'} · gõ 200mm, =kích-thước-đích, hoặc bắt P3. TAB/SHIFT để thêm hướng.")
        true
      end

      def update_p3_delta(view, x, y)
        return unless @axis && @p2_root
        world_axis = AXES[@axis].transform(@context_to_world)
        return if world_axis.length < 0.001
        world_axis.normalize!

        base_world = root_to_world(@p2_root)
        points = Geom.closest_points(view.pickray(x, y), [base_world, world_axis])
        return unless points && points[1]

        root_point = world_to_root(points[1])
        @delta = coord(root_point, @axis) - @ref_coord
        update_vcb
      end

      def dominant_axis(a, b)
        diffs = [
          (b.x - a.x).abs,
          (b.y - a.y).abs,
          (b.z - a.z).abs
        ]
        max = diffs.max
        return nil if max.nil? || max < MIN_AXIS_DELTA
        diffs.index(max)
      end

      def finish_current_direction(queue_only)
        region = current_region(true)
        raise 'Khoảng co/kéo bằng 0.' if region[:delta].abs < 0.001.mm

        if queue_only
          add_pending_region(region)
          count = @pending_regions.length
          reset_current_points
          update_status("Đã lưu #{count} hướng · bắt P1/P2 cho hướng tiếp theo. Hướng cuối xác nhận bình thường hoặc Enter để áp dụng.")
        else
          regions = @pending_regions + [region]
          commit_regions(regions)
          count = regions.length
          @pending_regions.clear
          reset_current_points
          update_status("Đã co/kéo #{count} hướng trong 1 Undo · bắt P1 cho lượt tiếp theo.")
        end
      end

      def add_pending_region(region)
        # Nếu cùng hướng/cùng biên gần như trùng nhau, thay giá trị cũ thay vì kéo lặp.
        index = @pending_regions.index do |r|
          r[:axis] == region[:axis] &&
            r[:side_sign] == region[:side_sign] &&
            (r[:cut_coord] - region[:cut_coord]).abs <= CUT_TOL
        end
        if index
          @pending_regions[index] = region
        else
          @pending_regions << region
        end
      end

      def current_region(include_delta)
        {
          axis: @axis,
          side_sign: @side_sign,
          cut_coord: @cut_coord,
          ref_coord: @ref_coord,
          p1_root: @p1_root ? clone_point(@p1_root) : nil,
          p2_root: @p2_root ? clone_point(@p2_root) : nil,
          delta: include_delta ? @delta : 0.0
        }
      end

      def add_direction?(flags)
        @add_mode || @shift_down || shift_modifier?(flags)
      end

      # ------------------------------------------------------------
      # MULTI-DIRECTION GEOMETRY ENGINE
      # ------------------------------------------------------------

      def commit_regions(regions)
        valid = Array(regions).select { |r| r && r[:axis] && r[:delta].abs >= 0.001.mm }
        return true if valid.empty?

        @model.start_operation("TRẦN TUẤN - Co Giãn Đa Hướng V#{VERSION}", true)
        begin
          valid.each do |region|
            root_vector = AXES[region[:axis]].clone
            root_vector.length = region[:delta].abs
            root_vector.reverse! if region[:delta] < 0

            actions = []
            keys = {}
            @scope.each do |entity|
              next unless entity.valid?
              collect_entity_actions(
                entity,
                Geom::Transformation.new,
                root_vector,
                region,
                actions,
                keys
              )
            end
            actions.each { |action| apply_action(action) }
          end
          @model.commit_operation
          true
        rescue StandardError
          @model.abort_operation
          raise
        end
      end

      def collect_entity_actions(entity, parent_to_root, root_vector, region, actions, keys)
        return unless entity.valid? && selectable?(entity)
        key = [entity_key(entity), region[:axis], region[:side_sign], region[:cut_coord].round(6)]
        return if keys[key]

        bb = instance_bounds_root(entity, parent_to_root)
        return unless bb

        relation = halfspace_relation(bb, region)
        return if relation == :fixed

        if relation == :selected
          add_move_instance(entity, parent_to_root, root_vector, actions, keys, key)
          return
        end

        # Crossing mặt cắt P1.
        if rigid_assembly?(entity)
          center = (coord(bb[:min], region[:axis]) + coord(bb[:max], region[:axis])) * 0.5
          if selected_coord?(center, region)
            add_move_instance(entity, parent_to_root, root_vector, actions, keys, key)
          end
          return
        end

        ensure_unique(entity)
        entities = child_entities(entity)
        children = entities.to_a.select { |e| e.valid? && selectable?(e) }
        raw_edges = entities.grep(Sketchup::Edge).select(&:valid?)
        entity_to_root = parent_to_root * entity.transformation

        # Container thuần: đi xuống từng tấm/cụm con.
        if raw_edges.empty? && !children.empty?
          children.each do |child|
            collect_entity_actions(child, entity_to_root, root_vector, region, actions, keys)
          end
          return
        end

        unless raw_edges.empty?
          collect_raw_geometry_action(
            entity,
            entities,
            raw_edges,
            entity_to_root,
            root_vector,
            region,
            actions,
            keys,
            key
          )
        end

        # Entity hỗn hợp raw + child: child được xử lý riêng nhưng không kéo lặp parent.
        children.each do |child|
          collect_entity_actions(child, entity_to_root, root_vector, region, actions, keys)
        end
      end

      def collect_raw_geometry_action(entity, entities, edges, entity_to_root, root_vector, region, actions, keys, key)
        bb = raw_bounds_root(edges, entity_to_root)
        return unless bb

        relation = halfspace_relation(bb, region)
        return if relation == :fixed

        if relation == :selected
          # Raw geometry thuộc leaf crossing parent nhưng toàn bộ raw nằm phía chọn.
          local_vector = root_vector.transform(entity_to_root.inverse)
          vertices = edges.flat_map(&:vertices).select(&:valid?).uniq
          actions << { kind: :move_vertices, entities: entities, vertices: vertices, vector: local_vector }
          keys[key] = true
          return
        end

        axis = region[:axis]
        span = coord(bb[:max], axis) - coord(bb[:min], axis)
        scope_span = scope_axis_span(axis)
        thin_limit = [THIN_AXIS_MAX, scope_span * THIN_AXIS_RATIO].min

        if span <= thin_limit
          center = (coord(bb[:min], axis) + coord(bb[:max], axis)) * 0.5
          if selected_coord?(center, region)
            add_move_instance(entity, entity_to_root_without_self(entity_to_root, entity), root_vector, actions, keys, key)
          end
          return
        end

        # Tấm dài cắt qua P1: chỉ dịch TOÀN BỘ mặt đầu cực trị phía P2.
        extreme = region[:side_sign] > 0 ? coord(bb[:max], axis) : coord(bb[:min], axis)
        tol = [END_TOL, span * 0.002].max

        vertices = edges.flat_map(&:vertices).select(&:valid?).uniq.select do |vertex|
          root_point = vertex.position.transform(entity_to_root)
          (coord(root_point, axis) - extreme).abs <= tol
        end
        return if vertices.empty?

        local_vector = root_vector.transform(entity_to_root.inverse)
        actions << {
          kind: :move_vertices,
          entities: entities,
          vertices: vertices,
          vector: local_vector
        }
        keys[key] = true
      end

      def add_move_instance(entity, parent_to_root, root_vector, actions, keys, key)
        actions << {
          kind: :move_instance,
          entity: entity,
          parent_to_root: parent_to_root,
          root_vector: root_vector
        }
        keys[key] = true
      end

      def apply_action(action)
        case action[:kind]
        when :move_instance
          local_vector = action[:root_vector].transform(action[:parent_to_root].inverse)
          action[:entity].transform!(Geom::Transformation.translation(local_vector))
        when :move_vertices
          vectors = Array.new(action[:vertices].length) do
            v = action[:vector]
            Geom::Vector3d.new(v.x, v.y, v.z)
          end
          action[:entities].transform_by_vectors(action[:vertices], vectors)
        end
      end

      def halfspace_relation(bb, region)
        axis = region[:axis]
        min_v = coord(bb[:min], axis)
        max_v = coord(bb[:max], axis)
        cut = region[:cut_coord]

        if region[:side_sign] > 0
          return :fixed if max_v <= cut + CUT_TOL
          return :selected if min_v >= cut - CUT_TOL
        else
          return :fixed if min_v >= cut - CUT_TOL
          return :selected if max_v <= cut + CUT_TOL
        end
        :crossing
      end

      def selected_coord?(value, region)
        region[:side_sign] > 0 ? value > region[:cut_coord] + CUT_TOL : value < region[:cut_coord] - CUT_TOL
      end

      # Cụm có cả raw geometry và nested instance được xem là assembly cứng.
      def rigid_assembly?(entity)
        entities = child_entities(entity)
        has_raw = !entities.grep(Sketchup::Edge).empty?
        has_nested = entities.any? { |e| e.valid? && selectable?(e) }
        has_raw && has_nested
      rescue StandardError
        true
      end

      def ensure_unique(entity)
        return unless entity.respond_to?(:make_unique)
        if entity.is_a?(Sketchup::ComponentInstance)
          entity.make_unique if entity.definition.instances.length > 1
        elsif entity.is_a?(Sketchup::Group)
          entity.make_unique if entity.definition.instances.length > 1
        end
      rescue StandardError
        nil
      end

      def entity_to_root_without_self(entity_to_root, entity)
        entity_to_root * entity.transformation.inverse
      rescue StandardError
        Geom::Transformation.new
      end

      # ------------------------------------------------------------
      # BOUNDS / SCOPE
      # ------------------------------------------------------------

      def selectable?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def child_entities(entity)
        entity.definition.entities
      end

      def initial_scope
        selected = @model.selection.to_a.select { |e| selectable?(e) && e.valid? }
        return selected.uniq unless selected.empty?
        @model.active_entities.to_a.select { |e| selectable?(e) && e.valid? }
      end

      def scope_bounds_root
        bb = Geom::BoundingBox.new
        @scope.each do |entity|
          data = instance_bounds_root(entity, Geom::Transformation.new)
          next unless data
          8.times { |i| bb.add(bounds_corner(data, i)) }
        end
        bb
      end

      def scope_axis_span(axis)
        return 1.mm unless @scope_bounds && !@scope_bounds.empty?
        coord(@scope_bounds.max, axis) - coord(@scope_bounds.min, axis)
      end

      def instance_bounds_root(entity, parent_to_root)
        tr = parent_to_root * entity.transformation
        bb = entity.definition.bounds
        out = Geom::BoundingBox.new
        8.times { |i| out.add(bb.corner(i).transform(tr)) }
        { min: clone_point(out.min), max: clone_point(out.max) }
      rescue StandardError
        nil
      end

      def raw_bounds_root(edges, local_to_root)
        bb = Geom::BoundingBox.new
        edges.each do |edge|
          bb.add(edge.start.position.transform(local_to_root))
          bb.add(edge.end.position.transform(local_to_root))
        end
        return nil if bb.empty?
        { min: clone_point(bb.min), max: clone_point(bb.max) }
      end

      def bounds_corner(bounds, index)
        mn = bounds[:min]
        mx = bounds[:max]
        Geom::Point3d.new(
          (index & 1).zero? ? mn.x : mx.x,
          (index & 2).zero? ? mn.y : mx.y,
          (index & 4).zero? ? mn.z : mx.z
        )
      end

      # ------------------------------------------------------------
      # DRAW
      # ------------------------------------------------------------

      def draw_pending_regions(view)
        @pending_regions.each_with_index do |region, index|
          color = AXIS_COLORS[region[:axis]]
          draw_cut_plane(view, region[:axis], region[:cut_coord], color, 2)
          draw_side_arrow(view, region)
          if region[:ref_coord]
            draw_cut_plane(view, region[:axis], region[:ref_coord] + region[:delta], color, 2)
          end
          draw_region_label(view, region, index + 1)
        end
      end

      def draw_axis_hint(view, a, b, axis)
        return unless axis
        aa = clone_point(a)
        bb = clone_point(a)
        set_coord(bb, axis, coord(b, axis))
        view.drawing_color = AXIS_COLORS[axis]
        view.line_width = 4
        view.draw(GL_LINES, [root_to_world(aa), root_to_world(bb)])
      end

      def draw_cut_plane(view, axis, plane_coord, color, width)
        return unless @scope_bounds && !@scope_bounds.empty?
        mn = @scope_bounds.min
        mx = @scope_bounds.max
        pad = 50.mm
        points = case axis
                 when 0
                   [
                     Geom::Point3d.new(plane_coord, mn.y - pad, mn.z - pad),
                     Geom::Point3d.new(plane_coord, mx.y + pad, mn.z - pad),
                     Geom::Point3d.new(plane_coord, mx.y + pad, mx.z + pad),
                     Geom::Point3d.new(plane_coord, mn.y - pad, mx.z + pad)
                   ]
                 when 1
                   [
                     Geom::Point3d.new(mn.x - pad, plane_coord, mn.z - pad),
                     Geom::Point3d.new(mx.x + pad, plane_coord, mn.z - pad),
                     Geom::Point3d.new(mx.x + pad, plane_coord, mx.z + pad),
                     Geom::Point3d.new(mn.x - pad, plane_coord, mx.z + pad)
                   ]
                 else
                   [
                     Geom::Point3d.new(mn.x - pad, mn.y - pad, plane_coord),
                     Geom::Point3d.new(mx.x + pad, mn.y - pad, plane_coord),
                     Geom::Point3d.new(mx.x + pad, mx.y + pad, plane_coord),
                     Geom::Point3d.new(mn.x - pad, mx.y + pad, plane_coord)
                   ]
                 end
        world = points.map { |p| root_to_world(p) }
        view.drawing_color = color
        view.line_width = width
        view.draw(GL_LINE_LOOP, world)
      end

      def draw_side_arrow(view, region)
        return unless region[:p1_root] && region[:p2_root]
        a = clone_point(region[:p1_root])
        b = clone_point(a)
        set_coord(b, region[:axis], coord(region[:p2_root], region[:axis]))
        view.drawing_color = AXIS_COLORS[region[:axis]]
        view.line_width = 4
        view.draw(GL_LINES, [root_to_world(a), root_to_world(b)])
      end

      def draw_delta_arrow(view)
        a = clone_point(@p2_root)
        b = clone_point(@p2_root)
        set_coord(b, @axis, @ref_coord + @delta)
        view.drawing_color = AXIS_COLORS[@axis]
        view.line_width = 5
        view.draw(GL_LINES, [root_to_world(a), root_to_world(b)])
      end

      def draw_region_label(view, region, index)
        return unless region[:p2_root]
        screen = view.screen_coords(root_to_world(region[:p2_root]))
        text = "#{index}:#{axis_name(region[:axis])}#{region[:side_sign] > 0 ? '+' : '-'} #{Sketchup.format_length(region[:delta].abs)}"
        view.draw_text(screen, text)
      rescue StandardError
        nil
      end

      # ------------------------------------------------------------
      # HELPERS
      # ------------------------------------------------------------

      def root_to_world(point)
        point.transform(@context_to_world)
      end

      def world_to_root(point)
        point.transform(@context_to_world.inverse)
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

      def entity_key(entity)
        entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.object_id
      end

      def axis_name(axis)
        %w[X Y Z][axis] || '?'
      end

      def side_name
        return '?' unless @axis
        "#{axis_name(@axis)}#{@side_sign > 0 ? '+' : '-'}"
      end

      def shift_modifier?(flags)
        (flags.to_i & SHIFT_MASK) != 0
      end

      def shift_key?(key)
        key == 16 || (defined?(VK_SHIFT) && key == VK_SHIFT)
      end

      def tab_key?(key)
        key == 9 || (defined?(VK_TAB) && key == VK_TAB)
      end

      def enter_key?(key)
        key == 13 || (defined?(VK_RETURN) && key == VK_RETURN)
      end

      def update_vcb
        Sketchup.set_status_text('Co/kéo', SB_VCB_LABEL)
        Sketchup.set_status_text(Sketchup.format_length(@delta.abs), SB_VCB_VALUE)
      end

      def clear_vcb
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      end

      def update_status(extra = nil)
        text = extra
        unless text
          pending = @pending_regions.empty? ? '' : " · #{@pending_regions.length} hướng chờ"
          text = case @state
                 when :p1
                   "P1 · bắt biên cố định#{pending}."
                 when :p2
                   'P2 · chỉ phía cần co/kéo; tự nhận X± Y± Z±.'
                 when :p3
                   update_vcb
                   mode = @add_mode ? 'THÊM HƯỚNG BẬT' : 'hoàn tất bình thường'
                   "#{side_name} · P3 hoặc nhập số · TAB/SHIFT thêm hướng · #{mode}#{pending}."
                 else
                   'CO GIÃN ĐA HƯỚNG'
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
