# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.4.0 - QUÉT VÙNG
#
# Quy trình:
# 1) Bật tool -> kéo khung QUÉT đúng vùng cần co/kéo.
# 2) Thả chuột -> rê chuột để chọn trục X/Y/Z (hoặc phím mũi tên khóa trục).
# 3) Click điểm bắt đầu -> kéo -> click xác nhận.
#
# Nguyên tắc giống STRETCH:
# - Group/Component nằm hoàn toàn trong vùng quét: di chuyển nguyên khối.
# - Group/Component bị vùng quét cắt qua: KHÔNG scale cả khối.
#   Hệ thống đi vào đúng instance path và chỉ dịch các Vertex nằm trong vùng quét.
# - Nếu có Group/Component lồng: parent không bị kéo lặp; mỗi nhánh chỉ xử lý đúng một lần.
# - Component dùng chung sẽ Make Unique trước khi sửa geometry.
# - Một lượt co/kéo = một Undo.
# - TAB: quét vùng mới. ESC: hủy bước hiện tại / thoát tool.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    %i[VERSION AXES AXIS_COLORS MIN_SCAN_PX GUIDE_LENGTH].each do |name|
      remove_const(name) if const_defined?(name, false)
    end

    VERSION = '0.4.0'.freeze
    MIN_SCAN_PX = 5.0
    GUIDE_LENGTH = 500.mm

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
        Sketchup.set_status_text('CO GIÃN MODE · Kéo khung QUÉT đúng VÙNG cần co/kéo.', SB_PROMPT)
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
          update_status('Đã hủy kéo · rê chuột chọn lại trục hoặc TAB quét vùng mới.')
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
        puts "[TT Stretch Region move] #{error.class}: #{error.message}"
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
          update_status('Đã co/kéo vùng xong · QUÉT vùng tiếp theo.')
        end
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Co Giãn Khối MODE V#{VERSION}:\n#{error.message}")
        puts "[TT Stretch Region click] #{error.class}: #{error.message}"
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
        value = text.to_s.strip.to_l
        @delta = value
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
        puts "[TT Stretch Region draw] #{error.class}: #{error.message}"
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
        update_status("Đã nhận vùng co/kéo · #{@affected_count} khối liên quan · rê chuột chọn trục X/Y/Z.")
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
        line = [root_to_world(@anchor_root), world_axis]
        points = Geom.closest_points(view.pickray(x, y), line)
        points && points[1]
      rescue StandardError
        nil
      end

      def commit_stretch(view)
        return true if @delta.abs < 0.001.mm
        raise 'Chưa có vùng quét.' unless @scan_rect
        raise 'Chưa chọn trục co/kéo.' unless @axis

        root_vector = begin_root_vector
        @model.start_operation("TRẦN TUẤN - Co Giãn Vùng V#{VERSION}", true)
        begin
          actions = []
          @scope.each do |entity|
            next unless entity.valid?
            collect_instance_actions(
              entity,
              @model.active_entities,
              Geom::Transformation.new,
              view,
              root_vector,
              actions
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

      def collect_instance_actions(entity, parent_entities, parent_to_root, view, root_vector, actions)
        return unless entity.valid?

        rect = instance_screen_rect(entity, parent_to_root, view)
        return unless rect
        relation = rect_relation(rect, @scan_rect)
        return if relation == :outside

        if relation == :inside
          actions << {
            kind: :move_instance,
            entity: entity,
            parent_to_root: parent_to_root,
            root_vector: root_vector
          }
          return
        end

        # Bị vùng quét cắt qua: tuyệt đối không move/scale cả parent.
        # Nếu là Component dùng chung, tách definition trước khi sửa geometry/child.
        if entity.is_a?(Sketchup::ComponentInstance) && entity.definition.instances.length > 1
          entity.make_unique
        end

        definition = entity.definition
        entities = definition.entities
        entity_to_root = parent_to_root * entity.transformation

        raw_edges = entities.grep(Sketchup::Edge).select(&:valid?)
        collect_vertex_action(entities, raw_edges, entity_to_root, view, root_vector, actions) unless raw_edges.empty?

        entities.to_a.each do |child|
          next unless child.valid? && selectable?(child)
          collect_instance_actions(child, entities, entity_to_root, view, root_vector, actions)
        end
      end

      def collect_vertex_action(entities, edges, local_to_root, view, root_vector, actions)
        vertices = edges.flat_map(&:vertices).select(&:valid?).uniq
        selected = vertices.select do |vertex|
          root_point = vertex.position.transform(local_to_root)
          screen = view.screen_coords(root_to_world(root_point))
          point_in_rect?(screen.x, screen.y, @scan_rect)
        end
        return if selected.empty?

        local_vector = root_vector.transform(local_to_root.inverse)
        actions << {
          kind: :move_vertices,
          entities: entities,
          vertices: selected,
          vector: local_vector
        }
      end

      def apply_action(action)
        case action[:kind]
        when :move_instance
          parent_to_root = action[:parent_to_root]
          local_vector = action[:root_vector].transform(parent_to_root.inverse)
          transform = Geom::Transformation.translation(local_vector)
          action[:entity].transform!(transform)
        when :move_vertices
          vectors = Array.new(action[:vertices].length) do
            v = action[:vector]
            Geom::Vector3d.new(v.x, v.y, v.z)
          end
          action[:entities].transform_by_vectors(action[:vertices], vectors)
        end
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
        origin = root_to_world(@anchor_root)
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
                   @scanning ? 'Đang QUÉT VÙNG · thả chuột để chốt.' : 'QUÉT VÙNG cần co/kéo · không cần quét cả module.'
                 when :axis
                   axis_text = @axis ? axis_name(@axis) : '-'
                   "Vùng đã chốt · trục #{axis_text} · rê chuột chọn hướng hoặc ←Y →X ↑Z · click bắt đầu."
                 when :drag
                   update_vcb
                   "Đang kéo trục #{axis_name(@axis)} · #{Sketchup.format_length(@delta)} · click xác nhận · ESC hủy."
                 else
                   'CO GIÃN VÙNG'
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
