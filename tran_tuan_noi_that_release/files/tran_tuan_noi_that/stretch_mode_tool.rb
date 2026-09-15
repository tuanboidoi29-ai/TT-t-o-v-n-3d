# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.6.0 - QUÉT BIÊN 3D
#
# QUY TRÌNH CHÍNH:
# - P1 = BIÊN CỐ ĐỊNH (đường/mặt cắt nơi bắt đầu vùng co giãn).
# - P2 = chỉ phía cần co/kéo và là vị trí tham chiếu hiện tại.
# - Sau P1/P2 có 2 cách dùng song song:
#     + Gõ trực tiếp 200mm + Enter => kéo ra đúng 200mm theo phía P2.
#     + Bắt P3 => vị trí mới; delta = P3 - P2 theo trục đã nhận.
# - Có thể CLICK P1 rồi CLICK P2, hoặc giữ chuột tại P1 và QUÉT sang P2 rồi thả.
#
# HÌNH HỌC:
# - Trục X/Y/Z lấy theo Model Axis trong active context, KHÔNG theo camera.
# - Vùng chọn là nửa không gian từ mặt cắt P1 về phía P2.
# - Group/Component nằm trọn phía chọn => tịnh tiến nguyên khối.
# - Tấm leaf cắt qua P1 và dài theo trục => chỉ dịch TOÀN BỘ mặt đầu cực trị về phía P2.
# - Tấm mỏng theo trục => tịnh tiến nguyên khối, giữ nguyên độ dày.
# - Container thuần => đi vào các phần tử con.
# - Cụm ngăn kéo/ray/phụ kiện được coi là rigid để tránh biến dạng.
# - Component/Group dùng chung được Make Unique trước khi sửa geometry.
# - Một lượt co/kéo = một Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    %i[
      VERSION AXES AXIS_COLORS MIN_GESTURE_PX MIN_AXIS_DELTA
      CUT_TOL END_TOL THIN_AXIS_MAX THIN_AXIS_RATIO
    ].each do |name|
      remove_const(name) if const_defined?(name, false)
    end

    VERSION = '0.6.0'.freeze
    MIN_GESTURE_PX = 6.0
    MIN_AXIS_DELTA = 2.mm
    CUT_TOL = 0.5.mm
    END_TOL = 0.75.mm
    THIN_AXIS_MAX = 120.mm
    THIN_AXIS_RATIO = 0.18

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
      end

      def activate
        if @scope.empty?
          UI.messagebox('Co Giãn Khối MODE: không có Group/Component trong vùng làm việc. Hãy chọn tủ/module hoặc mở đúng context rồi chạy lại.')
          @model.select_tool(nil)
          return
        end
        update_status('P1 · Bắt điểm/biên CỐ ĐỊNH ở nơi bắt đầu co giãn.')
        @model.active_view.invalidate
      end

      def deactivate(view)
        clear_vcb
        view.invalidate if view
      end

      def onCancel(_reason, view)
        case @state
        when :p3
          reset_points
          update_status('Đã hủy vùng · bắt lại P1.')
        when :p2
          reset_points
          update_status('Đã hủy P1 · bắt lại P1.')
        else
          @model.select_tool(nil)
          return
        end
        view.invalidate
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
        puts "[TT Stretch Boundary move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
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
          update_status('P2 · Kéo/quét về PHÍA cần co giãn rồi thả, hoặc click điểm thứ 2.')

        when :p2
          # Click lần 2 sau khi P1 đã được đặt.
          finalize_p2(view, x, y)

        when :p3
          return UI.beep if @delta.abs < 0.001.mm
          commit_stretch
          reset_points
          update_status('Đã co/kéo xong · bắt P1 cho lượt tiếp theo.')
        end
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
        puts "[TT Stretch Boundary click] #{error.class}: #{error.message}"
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @state == :p2 && @first_press_active
        @first_press_active = false

        finish = Geom::Point3d.new(x.to_f, y.to_f, 0)
        distance = @gesture_start ? @gesture_start.distance(finish) : 0.0

        # Nếu người dùng giữ chuột từ P1 và quét đủ xa => thả chuột chính là P2.
        if distance >= MIN_GESTURE_PX
          finalize_p2(view, x, y)
          view.invalidate
        end
      rescue StandardError => error
        UI.messagebox("Không nhận được P2:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @state == :p3 && @axis
        raw = text.to_s.strip
        return UI.beep if raw.empty?

        amount = raw.to_l
        # Số dương luôn co/kéo theo phía P2; số âm co ngược lại.
        @delta = amount.to_f * @side_sign
        update_vcb

        return UI.beep if @delta.abs < 0.001.mm
        commit_stretch
        reset_points
        update_status("Đã co/kéo #{Sketchup.format_length(amount.abs)} · bắt P1 cho lượt tiếp theo.")
        view.invalidate
      rescue StandardError => error
        UI.beep
        UI.messagebox("Không thể co/kéo theo kích thước nhập:\n#{error.message}")
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && (@state == :p1 || @state == :p2)
        @ip1.draw(view) if @ip1.valid?
        @ip2.draw(view) if @ip2.valid?

        return unless @p1_root

        if @state == :p2 && @ip.valid?
          preview_p2 = world_to_root(@ip.position)
          axis = dominant_axis(@p1_root, preview_p2)
          draw_axis_hint(view, @p1_root, preview_p2, axis) if axis
        end

        return unless @axis && @cut_coord

        draw_cut_plane(view, @cut_coord, Sketchup::Color.new(255, 80, 0), 3)
        draw_selected_region(view)

        if @ref_coord
          draw_cut_plane(view, @ref_coord, Sketchup::Color.new(255, 165, 0), 1)
        end

        if @state == :p3 && @delta.abs > 0.001.mm
          draw_cut_plane(view, @ref_coord + @delta, AXIS_COLORS[@axis], 3)
          draw_delta_arrow(view)
        end
      rescue StandardError => error
        puts "[TT Stretch Boundary draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @scope.each { |entity| bb.add(entity.bounds) if entity.valid? }
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      # ------------------------------
      # INPUT / STATE
      # ------------------------------

      def reset_points
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
        clear_vcb
      end

      def update_p2_preview
        return unless @p1_root && @ip.valid?
        p2 = world_to_root(@ip.position)
        axis = dominant_axis(@p1_root, p2)
        return unless axis
        diff = coord(p2, axis) - coord(@p1_root, axis)
        Sketchup.set_status_text('Vùng', SB_VCB_LABEL)
        Sketchup.set_status_text("#{axis_name(axis)} #{diff >= 0 ? '+' : '-'}", SB_VCB_VALUE)
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
          update_status('P2 quá gần P1 · hãy quét rõ về trái/phải/trên/dưới/sâu.')
          return false
        end

        diff = coord(p2, axis) - coord(@p1_root, axis)
        if diff.abs < MIN_AXIS_DELTA
          UI.beep
          update_status('P2 chưa tạo được hướng co giãn rõ ràng · chọn lại P2.')
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
        update_status("Vùng đã chọn: từ P1 về phía #{side_name}. Gõ 200mm + Enter HOẶC bắt P3 tại vị trí mới.")
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

      # ------------------------------
      # GEOMETRY ENGINE
      # ------------------------------

      def commit_stretch
        raise 'Chưa xác định P1/P2.' unless @axis && @cut_coord
        return true if @delta.abs < 0.001.mm

        root_vector = AXES[@axis].clone
        root_vector.length = @delta.abs
        root_vector.reverse! if @delta < 0

        @model.start_operation("TRẦN TUẤN - Co Giãn Biên 3D V#{VERSION}", true)
        begin
          actions = []
          keys = {}

          @scope.each do |entity|
            next unless entity.valid?
            collect_entity_actions(
              entity,
              Geom::Transformation.new,
              root_vector,
              actions,
              keys
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

      def collect_entity_actions(entity, parent_to_root, root_vector, actions, keys)
        return unless entity.valid? && selectable?(entity)
        key = entity_key(entity)
        return if keys[key]

        bb = instance_bounds_root(entity, parent_to_root)
        return unless bb

        relation = halfspace_relation(bb)
        return if relation == :fixed

        if relation == :selected
          add_move_instance(entity, parent_to_root, root_vector, actions, keys)
          return
        end

        # Crossing mặt cắt P1.
        if rigid_assembly?(entity)
          center = (coord(bb[:min], @axis) + coord(bb[:max], @axis)) * 0.5
          if selected_coord?(center)
            add_move_instance(entity, parent_to_root, root_vector, actions, keys)
          end
          return
        end

        ensure_unique(entity)
        entities = child_entities(entity)
        children = entities.to_a.select { |e| e.valid? && selectable?(e) }
        raw_edges = entities.grep(Sketchup::Edge).select(&:valid?)
        entity_to_root = parent_to_root * entity.transformation

        # Container thuần: đi xuống các tấm/cụm con, không biến dạng parent.
        if raw_edges.empty? && !children.empty?
          children.each do |child|
            collect_entity_actions(child, entity_to_root, root_vector, actions, keys)
          end
          return
        end

        # Raw geometry của chính entity.
        unless raw_edges.empty?
          collect_raw_geometry_action(
            entity,
            entities,
            raw_edges,
            entity_to_root,
            root_vector,
            actions,
            keys
          )
        end

        # Nếu vừa có raw geometry vừa có children, xử lý children riêng theo cùng mặt cắt.
        children.each do |child|
          collect_entity_actions(child, entity_to_root, root_vector, actions, keys)
        end
      end

      def collect_raw_geometry_action(owner, entities, edges, local_to_root, root_vector, actions, keys)
        vertices = edges.flat_map(&:vertices).select(&:valid?).uniq
        return if vertices.empty?

        values = vertices.map { |v| coord(v.position.transform(local_to_root), @axis) }
        min_v = values.min
        max_v = values.max
        span = max_v - min_v
        return if span <= 0.001.mm

        all_min, all_mid, all_max = root_span_dimensions(owner, local_to_root)
        max_dim = [all_min, all_mid, all_max].max
        thin_limit = [THIN_AXIS_MAX, max_dim * THIN_AXIS_RATIO].min

        # Tấm/cụm rất mỏng theo trục stretch => không bóp độ dày, move nguyên instance nếu có owner.
        if span <= thin_limit && selectable?(owner)
          parent_to_root = local_to_root * owner.transformation.inverse
          add_move_instance(owner, parent_to_root, root_vector, actions, keys)
          return
        end

        extreme = @side_sign > 0 ? max_v : min_v
        selected_vertices = vertices.select do |vertex|
          c = coord(vertex.position.transform(local_to_root), @axis)
          (c - extreme).abs <= END_TOL
        end
        return if selected_vertices.empty?

        key = "geo:#{definition_key(owner)}:#{@axis}:#{@side_sign}"
        return if keys[key]
        keys[key] = true

        local_vector = root_vector.transform(local_to_root.inverse)
        actions << {
          kind: :move_vertices,
          entities: entities,
          vertices: selected_vertices,
          vector: Geom::Vector3d.new(local_vector.x, local_vector.y, local_vector.z)
        }
      end

      def halfspace_relation(bb)
        mn = coord(bb[:min], @axis)
        mx = coord(bb[:max], @axis)

        if @side_sign > 0
          return :fixed if mx < @cut_coord - CUT_TOL
          return :selected if mn >= @cut_coord - CUT_TOL
        else
          return :fixed if mn > @cut_coord + CUT_TOL
          return :selected if mx <= @cut_coord + CUT_TOL
        end
        :crossing
      end

      def selected_coord?(value)
        @side_sign > 0 ? value >= @cut_coord - CUT_TOL : value <= @cut_coord + CUT_TOL
      end

      def add_move_instance(entity, parent_to_root, root_vector, actions, keys)
        key = "move:#{entity_key(entity)}"
        return if keys[key]
        keys[key] = true
        actions << {
          kind: :move_instance,
          entity: entity,
          parent_to_root: parent_to_root,
          root_vector: Geom::Vector3d.new(root_vector.x, root_vector.y, root_vector.z)
        }
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

      # ------------------------------
      # ENTITY HELPERS
      # ------------------------------

      def selectable?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def initial_scope
        selected = @model.selection.to_a.select { |e| selectable?(e) && e.valid? }
        return selected.uniq unless selected.empty?
        @model.active_entities.to_a.select { |e| selectable?(e) && e.valid? }
      end

      def definition_for(entity)
        if entity.is_a?(Sketchup::Group)
          entity.entities.parent
        else
          entity.definition
        end
      end

      def child_entities(entity)
        entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
      end

      def ensure_unique(entity)
        definition = definition_for(entity)
        return unless definition && definition.instances.length > 1
        entity.make_unique if entity.respond_to?(:make_unique)
      rescue StandardError
        nil
      end

      def instance_bounds_root(entity, parent_to_root)
        definition = definition_for(entity)
        return nil unless definition
        tr = parent_to_root * entity.transformation
        bb = definition.bounds
        root_bb = Geom::BoundingBox.new
        8.times { |i| root_bb.add(bb.corner(i).transform(tr)) }
        return nil if root_bb.empty?
        { min: clone_point(root_bb.min), max: clone_point(root_bb.max) }
      rescue StandardError
        nil
      end

      def scope_bounds_root
        bb = Geom::BoundingBox.new
        @scope.each do |entity|
          data = instance_bounds_root(entity, Geom::Transformation.new)
          next unless data
          8.times { |i| bb.add(bounds_corner(data, i)) }
        end
        if bb.empty?
          Geom::BoundingBox.new
        else
          bb
        end
      end

      def root_span_dimensions(owner, local_to_root)
        definition = definition_for(owner)
        return [0.0, 0.0, 0.0] unless definition
        bb = definition.bounds
        root_bb = Geom::BoundingBox.new
        8.times { |i| root_bb.add(bb.corner(i).transform(local_to_root)) }
        [root_bb.width, root_bb.height, root_bb.depth]
      rescue StandardError
        [0.0, 0.0, 0.0]
      end

      def rigid_assembly?(entity)
        definition = definition_for(entity)
        text = [
          (entity.respond_to?(:name) ? entity.name : nil),
          (definition.respond_to?(:name) ? definition.name : nil)
        ].compact.join(' ').downcase

        keywords = [
          'ngăn kéo', 'ngan keo', 'drawer',
          'ray', 'runner', 'slide',
          'phụ kiện', 'phu kien', 'hardware',
          'bản lề', 'ban le', 'hinge'
        ]
        keywords.any? { |word| text.include?(word) }
      rescue StandardError
        false
      end

      def entity_key(entity)
        if entity.respond_to?(:persistent_id)
          "e:#{entity.persistent_id}"
        else
          "e:#{entity.object_id}"
        end
      end

      def definition_key(entity)
        definition = definition_for(entity)
        if definition && definition.respond_to?(:persistent_id)
          definition.persistent_id
        else
          definition ? definition.object_id : entity.object_id
        end
      end

      # ------------------------------
      # DRAWING
      # ------------------------------

      def draw_axis_hint(view, a, b, axis)
        return unless axis
        p1 = root_to_world(a)
        projected = clone_point(a)
        set_coord(projected, axis, coord(b, axis))
        p2 = root_to_world(projected)
        view.drawing_color = AXIS_COLORS[axis]
        view.line_width = 3
        view.draw(GL_LINES, [p1, p2])
      end

      def draw_cut_plane(view, plane_coord, color, width)
        return if @scope_bounds.empty?
        points = plane_points(plane_coord)
        world = points.map { |p| root_to_world(p) }
        view.drawing_color = color
        view.line_width = width
        view.draw(GL_LINE_LOOP, world)
      end

      def draw_selected_region(view)
        return if @scope_bounds.empty?
        min_p = @scope_bounds.min
        max_p = @scope_bounds.max
        region_min = clone_point(min_p)
        region_max = clone_point(max_p)

        if @side_sign > 0
          set_coord(region_min, @axis, @cut_coord)
        else
          set_coord(region_max, @axis, @cut_coord)
        end

        points = box_points(region_min, region_max).map { |p| root_to_world(p) }
        indices = [
          0,1, 1,2, 2,3, 3,0,
          4,5, 5,6, 6,7, 7,4,
          0,4, 1,5, 2,6, 3,7
        ]
        view.drawing_color = Sketchup::Color.new(255, 140, 0)
        view.line_width = 2
        view.draw(GL_LINES, indices.map { |i| points[i] })
      end

      def draw_delta_arrow(view)
        base = clone_point(@p2_root)
        target = clone_point(@p2_root)
        set_coord(target, @axis, @ref_coord + @delta)
        view.drawing_color = AXIS_COLORS[@axis]
        view.line_width = 4
        view.draw(GL_LINES, [root_to_world(base), root_to_world(target)])
      end

      def plane_points(c)
        mn = @scope_bounds.min
        mx = @scope_bounds.max
        case @axis
        when 0
          [
            Geom::Point3d.new(c, mn.y, mn.z),
            Geom::Point3d.new(c, mx.y, mn.z),
            Geom::Point3d.new(c, mx.y, mx.z),
            Geom::Point3d.new(c, mn.y, mx.z)
          ]
        when 1
          [
            Geom::Point3d.new(mn.x, c, mn.z),
            Geom::Point3d.new(mx.x, c, mn.z),
            Geom::Point3d.new(mx.x, c, mx.z),
            Geom::Point3d.new(mn.x, c, mx.z)
          ]
        else
          [
            Geom::Point3d.new(mn.x, mn.y, c),
            Geom::Point3d.new(mx.x, mn.y, c),
            Geom::Point3d.new(mx.x, mx.y, c),
            Geom::Point3d.new(mn.x, mx.y, c)
          ]
        end
      end

      def box_points(mn, mx)
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

      def bounds_corner(bounds, index)
        box_points(bounds[:min], bounds[:max])[index]
      end

      # ------------------------------
      # COORD / STATUS
      # ------------------------------

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

      def axis_name(axis)
        %w[X Y Z][axis] || '?'
      end

      def side_name
        "#{axis_name(@axis)}#{@side_sign > 0 ? '+' : '-'}"
      end

      def update_vcb
        Sketchup.set_status_text('Co/kéo', SB_VCB_LABEL)
        display = @delta * @side_sign
        Sketchup.set_status_text(Sketchup.format_length(display), SB_VCB_VALUE)
      end

      def clear_vcb
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      end

      def update_status(extra = nil)
        text = extra
        unless text
          text = case @state
                 when :p1
                   'P1 · Bắt BIÊN CỐ ĐỊNH.'
                 when :p2
                   'P2 · Quét/click về phía cần co giãn.'
                 when :p3
                   update_vcb
                   "P3 hoặc nhập số · vùng #{side_name} · gõ 200mm + Enter hoặc click vị trí mới."
                 else
                   'CO GIÃN BIÊN 3D'
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
