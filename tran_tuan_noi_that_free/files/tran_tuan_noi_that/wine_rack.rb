# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  # Giữ tên module WineRack để command cũ đang sống trong phiên hot-reload
  # tự chuyển sang công cụ mới. Toàn bộ logic ô rượu đã được thay thế.
  module WineRack
    extend self

    PREF = 'TT_KHAU_AM_DUONG'.freeze
    EPS_VOL = 1.0e-7

    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) ||
        entity.is_a?(Sketchup::ComponentInstance)
    end

    class Tool
      def initialize
        @model = Sketchup.active_model
        @context = @model.active_entities
        @edit = @model.edit_transform

        @a = nil
        @b = nil
        @hover = nil
        @stage = :pick_a

        @gap_mm = Sketchup.read_default(PREF, 'gap_mm', 0.0).to_f
        @gap_mm = 0.0 unless @gap_mm.finite? && @gap_mm.between?(0.0, 5.0)

        raw_swap = Sketchup.read_default(PREF, 'swap_roles', false)
        @swap_roles = raw_swap == true || raw_swap.to_s.downcase == 'true'

        @preview_lines = []
        @preview_center = nil
        @preview_volume_mm3 = 0.0
        @preview_ready = false
        @preview_a_cut_lines = []
        @preview_b_cut_lines = []
        @busy = false

        use_selection
      end

      def activate
        status
        rebuild_preview if @a && @b
        @model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onCancel(_reason, view)
        if @stage == :ready
          @b = nil
          @preview_ready = false
          @preview_lines = []
          @preview_a_cut_lines = []
          @preview_b_cut_lines = []
          @stage = :pick_b
        elsif @stage == :pick_b
          @a = nil
          @b = nil
          @stage = :pick_a
        else
          @model.select_tool(nil)
          return
        end

        @model.selection.clear
        @model.selection.add(@a) if valid_board?(@a)
        status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        return if @busy || @stage == :ready

        picked = pick_board(view, x, y)
        picked = nil if picked == @a
        @hover = picked
        status
        view.invalidate
      rescue StandardError => error
        puts "[TT KhauAmDuong move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        return if @busy

        if @stage == :ready
          execute
          reset_after_execute
          view.invalidate
          return
        end

        picked = pick_board(view, x, y)
        return UI.beep unless picked && valid_board?(picked)

        if @stage == :pick_a
          @a = picked
          @b = nil
          @stage = :pick_b
          @model.selection.clear
          @model.selection.add(@a)
        else
          return UI.beep if picked == @a

          @b = picked
          validate_pair!
          @model.selection.clear
          @model.selection.add(@a)
          @model.selection.add(@b)
          rebuild_preview
          @stage = :ready
        end

        status
        view.invalidate
      rescue StandardError => error
        @preview_ready = false
        @preview_lines = []
        @b = nil if @stage != :pick_a
        @stage = @a ? :pick_b : :pick_a
        UI.messagebox("KHẤU ÂM DƯƠNG:\n#{error.message}")
        status
        view.invalidate
      end

      def onKeyDown(key, repeat, _flags, view)
        return if @busy || repeat.to_i > 0

        case key
        when 9 # TAB
          open_settings
          rebuild_preview if @a && @b
          status
          view.invalidate
          true
        when 16 # SHIFT - tiện đảo vai nhanh
          @swap_roles = !@swap_roles
          Sketchup.write_default(PREF, 'swap_roles', @swap_roles)
          status
          view.invalidate
          true
        else
          false
        end
      rescue StandardError => error
        UI.messagebox(error.message)
        true
      end

      def draw(view)
        # Preview vai A/B rõ ràng:
        # A = xanh, B = hồng. Đây chỉ là overlay, không sửa model.
        if valid_board?(@a)
          draw_board_preview(
            view,
            @a,
            Sketchup::Color.new(60, 150, 255, 65),
            Sketchup::Color.new(25, 105, 235)
          )
        end

        second = @stage == :pick_b ? @hover : @b
        if valid_board?(second)
          draw_board_preview(
            view,
            second,
            Sketchup::Color.new(255, 135, 185, 65),
            Sketchup::Color.new(225, 65, 130)
          )
        end

        if @preview_ready
          unless @preview_a_cut_lines.empty?
            view.line_stipple = '-'
            view.line_width = 5
            view.drawing_color = Sketchup::Color.new(20, 105, 245)
            view.draw(GL_LINES, @preview_a_cut_lines)
          end

          unless @preview_b_cut_lines.empty?
            view.line_stipple = '-'
            view.line_width = 5
            view.drawing_color = Sketchup::Color.new(235, 65, 145)
            view.draw(GL_LINES, @preview_b_cut_lines)
          end
          view.line_stipple = ''

          unless @preview_lines.empty?
            view.line_width = 2
            view.drawing_color = Sketchup::Color.new(190, 35, 35)
            view.draw(GL_LINES, @preview_lines)
          end

          if @preview_center
            text =
              if @swap_roles
                "A XANH: 1/2 MẶT SAU · B HỒNG: 1/2 MẶT TRƯỚC"
              else
                "A XANH: 1/2 MẶT TRƯỚC · B HỒNG: 1/2 MẶT SAU"
              end

            view.draw_text(
              @preview_center,
              "#{text}\nGIAO THẬT: #{format_volume(@preview_volume_mm3)}",
              size: 13,
              bold: true,
              color: Sketchup::Color.new(35, 35, 35)
            )
          end
        end
      rescue StandardError => error
        puts "[TT KhauAmDuong draw] #{error.class}: #{error.message}"
      end

      def getExtents
        box = Geom::BoundingBox.new

        [@a, @b, @hover].compact.uniq.each do |entity|
          next unless valid_board?(entity)
          world_corners(entity).each { |point| box.add(point) }
        end

        @preview_lines.each { |point| box.add(point) }
        box
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def use_selection
        selected = @model.selection.to_a.select do |entity|
          WineRack.container?(entity) &&
            @context.include?(entity) &&
            entity.valid? &&
            !entity.locked?
        end

        if selected.length == 2
          @a, @b = selected
          @stage = :ready
        elsif selected.length == 1
          @a = selected.first
          @stage = :pick_b
        end
      end

      def valid_board?(entity)
        entity &&
          entity.valid? &&
          WineRack.container?(entity) &&
          @context.include?(entity) &&
          !entity.locked?
      end

      def validate_board!(entity, label)
        raise "#{label}: đối tượng đã bị xóa hoặc đang khóa." unless valid_board?(entity)
        raise "#{label}: cần Group/Component kín (Solid)." unless entity.manifold?

        nested = entity.definition.entities.any? do |child|
          WineRack.container?(child)
        end
        raise "#{label}: Group phải là một khối ván, không chứa Group con." if nested
      end

      def validate_pair!
        validate_board!(@a, 'Tấm A')
        validate_board!(@b, 'Tấm B')
        raise 'Tấm A và B phải là hai Group/Component khác nhau.' if @a == @b

        overlap = world_bounds(@a).intersect(world_bounds(@b))
        unless overlap.valid? &&
               overlap.width > 1.0e-6 &&
               overlap.height > 1.0e-6 &&
               overlap.depth > 1.0e-6
          raise 'Hai tấm không có vùng giao 3D.'
        end
      end

      def pick_board(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)

        0.upto([helper.count - 1, 12].min) do |index|
          path = helper.path_at(index)
          next unless path

          entity = path.find do |item|
            WineRack.container?(item) && @context.include?(item)
          end
          return entity if entity && entity.valid? && !entity.locked?
        end

        nil
      rescue StandardError
        nil
      end

      def status
        text =
          case @stage
          when :pick_a
            'KHẤU ÂM DƯƠNG · click TẤM A.'
          when :pick_b
            'KHẤU ÂM DƯƠNG · A đã chọn · click TẤM B giao với A.'
          else
            if @swap_roles
              'PREVIEW GIAO THẬT · A khấu 1/2 MẶT SAU · B khấu 1/2 MẶT TRƯỚC · click để tạo · TAB cài đặt · SHIFT đảo A/B.'
            else
              'PREVIEW GIAO THẬT · A khấu 1/2 MẶT TRƯỚC · B khấu 1/2 MẶT SAU · click để tạo · TAB cài đặt · SHIFT đảo A/B.'
            end
          end

        Sketchup.set_status_text(text, SB_PROMPT)
      end

      def open_settings
        swap_text = @swap_roles ? 'Có' : 'Không'

        values = UI.inputbox(
          [
            'Độ hở mỗi bên rãnh (mm)',
            'Đảo vai A/B'
          ],
          [
            @gap_mm,
            swap_text
          ],
          [
            '',
            'Không|Có'
          ],
          'KHẤU ÂM DƯƠNG · CÀI ĐẶT'
        )

        return unless values

        gap, swap = values
        gap = Float(gap)
        raise 'Độ hở cho phép: 0–5 mm.' unless gap.finite? && gap.between?(0.0, 5.0)

        @gap_mm = gap
        @swap_roles = swap.to_s == 'Có'

        Sketchup.write_default(PREF, 'gap_mm', @gap_mm)
        Sketchup.write_default(PREF, 'swap_roles', @swap_roles)
      end

      def world_transform(entity)
        @edit * entity.transformation
      end

      def world_bounds(entity)
        box = Geom::BoundingBox.new
        tr = world_transform(entity)
        bounds = entity.definition.bounds

        8.times do |index|
          box.add(bounds.corner(index).transform(tr))
        end
        box
      end

      def world_corners(entity)
        tr = world_transform(entity)
        bounds = entity.definition.bounds
        8.times.map { |index| bounds.corner(index).transform(tr) }
      end

      def draw_board(view, entity, color)
        points = world_corners(entity)
        pairs = [
          [0,1],[1,3],[3,2],[2,0],
          [4,5],[5,7],[7,6],[6,4],
          [0,4],[1,5],[2,6],[3,7]
        ]

        view.line_width = 2
        view.drawing_color = color
        view.draw(GL_LINES, pairs.flat_map { |a, b| [points[a], points[b]] })
      end

      def draw_board_preview(view, entity, fill_color, edge_color)
        tr = world_transform(entity)

        view.drawing_color = fill_color
        entity.definition.entities.grep(Sketchup::Face).each do |face|
          mesh = face.mesh(0)

          mesh.polygons.each do |polygon|
            indices = polygon.map(&:abs)
            next if indices.length < 3

            p0 = mesh.point_at(indices[0]).transform(tr)
            triangles = []

            (1...(indices.length - 1)).each do |index|
              triangles << p0
              triangles << mesh.point_at(indices[index]).transform(tr)
              triangles << mesh.point_at(indices[index + 1]).transform(tr)
            end

            view.draw(GL_TRIANGLES, triangles) unless triangles.empty?
          end
        end

        draw_board(view, entity, edge_color)
      end

      def solid_snapshot(group)
        raise 'Preview Solid đã bị xóa.' unless group && group.valid?

        tr = group.transformation
        lines = group.definition.entities
          .grep(Sketchup::Edge)
          .flat_map do |edge|
            [
              edge.start.position.transform(tr),
              edge.end.position.transform(tr)
            ]
          end

        bounds = group.bounds
        {
          lines: lines,
          center: bounds.center.transform(tr),
          volume_mm3: group.volume.to_f * 25.4**3
        }
      end

      def duplicate_solid(work, source)
        raise 'Nguồn Solid tạm đã bị xóa.' unless source && source.valid?

        group = work.add_group
        instance = group.entities.add_instance(
          source.definition,
          source.transformation
        )
        instance.explode

        raise 'Không nhân bản được Solid tạm.' unless group.valid? && group.manifold?
        group
      end

      def copy_solid(work, entity)
        group = work.add_group
        group.entities.add_instance(
          entity.definition,
          world_transform(entity)
        ).explode

        raise 'Không tạo được bản sao Solid.' unless group.manifold?
        group
      end

      def build_intersection_solid(work, entity_a = @a, entity_b = @b)
        left = copy_solid(work, entity_a)
        right = copy_solid(work, entity_b)
        intersection = left.intersect(right)

        unless intersection &&
               intersection.valid? &&
               intersection.respond_to?(:volume) &&
               intersection.volume > EPS_VOL
          raise 'Hai tấm chỉ chạm mặt/cạnh, không có thể tích giao thật.'
        end

        # Không erase left/right ở đây:
        # Solid Tools có thể tái sử dụng/xóa operand. Workspace sẽ được
        # abort/erase nguyên khối, tránh reference to deleted Group.
        intersection
      end

      def rebuild_preview
        return unless @a && @b
        validate_pair!

        started = false
        @model.start_operation('TT - Preview Khấu Âm Dương', true)
        started = true

        workspace = @context.add_group
        workspace.transformation = @edit.inverse
        work = workspace.entities

        intersection = build_intersection_solid(work)
        snapshot = solid_snapshot(intersection)

        a_role = @swap_roles ? :back : :front
        b_role = @swap_roles ? :front : :back

        intersection_a = duplicate_solid(work, intersection)
        intersection_b = duplicate_solid(work, intersection)

        cutter_a = cutter_for_half(
          work,
          intersection_a,
          @a,
          board_cut_side(@a, a_role)
        )
        cutter_b = cutter_for_half(
          work,
          intersection_b,
          @b,
          board_cut_side(@b, b_role)
        )

        a_snapshot = solid_snapshot(cutter_a)
        b_snapshot = solid_snapshot(cutter_b)

        @preview_lines = snapshot[:lines]
        @preview_center = snapshot[:center]
        @preview_volume_mm3 = snapshot[:volume_mm3]
        @preview_a_cut_lines = a_snapshot[:lines]
        @preview_b_cut_lines = b_snapshot[:lines]

        # Hủy toàn bộ workspace sau khi đã lấy dữ liệu thuần.
        # Không giữ Group tạm ra ngoài operation.
        @model.abort_operation
        started = false
        @preview_ready = true
      rescue StandardError
        @model.abort_operation if started
        @preview_ready = false
        @preview_lines = []
        @preview_a_cut_lines = []
        @preview_b_cut_lines = []
        @preview_center = nil
        @preview_volume_mm3 = 0.0
        raise
      end

      def axis_vectors(transform)
        [transform.xaxis, transform.yaxis, transform.zaxis]
      end

      def thickness_axis(entity)
        tr = world_transform(entity)
        bounds = entity.definition.bounds
        local_sizes = [bounds.width, bounds.height, bounds.depth]
        axes = axis_vectors(tr)

        world_sizes = local_sizes.each_with_index.map do |size, index|
          size * axes[index].length
        end

        world_sizes.each_with_index.min_by(&:first)[1]
      end

      def toward_camera_side(entity)
        tr = world_transform(entity)
        axis_index = thickness_axis(entity)
        axis = axis_vectors(tr)[axis_index].clone
        raise 'Không xác định được trục độ dày.' if axis.length < 1.0e-9
        axis.normalize!

        center_world = entity.definition.bounds.center.transform(tr)
        to_eye = @model.active_view.camera.eye - center_world

        to_eye.dot(axis) >= 0.0 ? :max : :min
      end

      def opposite_side(side)
        side == :max ? :min : :max
      end

      def board_cut_side(entity, role)
        front = toward_camera_side(entity)

        case role
        when :front then front
        else opposite_side(front)
        end
      end

      def local_axis_scale(transform, index)
        axis_vectors(transform)[index].length
      end

      def build_half_slab(work, entity, side)
        tr = world_transform(entity)
        bounds = entity.definition.bounds
        thin = thickness_axis(entity)

        min_values = [bounds.min.x, bounds.min.y, bounds.min.z]
        max_values = [bounds.max.x, bounds.max.y, bounds.max.z]
        mid = (min_values[thin] + max_values[thin]) / 2.0

        3.times do |axis|
          scale = local_axis_scale(tr, axis)
          raise 'Scale đối tượng không hợp lệ.' if scale < 1.0e-9
          epsilon_local = 0.05.mm / scale

          if axis == thin
            if side == :max
              min_values[axis] = mid
              max_values[axis] += epsilon_local
            else
              min_values[axis] -= epsilon_local
              max_values[axis] = mid
            end
          else
            min_values[axis] -= epsilon_local
            max_values[axis] += epsilon_local
          end
        end

        add_oriented_box(work, min_values, max_values, tr)
      end

      def add_oriented_box(work, min_values, max_values, transform)
        points = []

        [0, 1].each do |z|
          [0, 1].each do |y|
            [0, 1].each do |x|
              values = [
                x.zero? ? min_values[0] : max_values[0],
                y.zero? ? min_values[1] : max_values[1],
                z.zero? ? min_values[2] : max_values[2]
              ]
              points << Geom::Point3d.new(*values).transform(transform)
            end
          end
        end

        # index = z*4 + y*2 + x
        faces = [
          [0, 2, 3, 1],
          [4, 5, 7, 6],
          [0, 1, 5, 4],
          [2, 6, 7, 3],
          [0, 4, 6, 2],
          [1, 3, 7, 5]
        ]

        group = work.add_group
        center = Geom::Point3d.new(
          points.sum(&:x) / 8.0,
          points.sum(&:y) / 8.0,
          points.sum(&:z) / 8.0
        )

        faces.each do |indices|
          face = group.entities.add_face(indices.map { |i| points[i] })
          raise 'Không dựng được nửa chiều sâu.' unless face

          face_center = face.bounds.center
          outward = face_center - center
          face.reverse! if face.normal.dot(outward) < 0.0
        end

        raise 'Khối nửa chiều sâu chưa kín.' unless group.manifold?
        group
      end

      def cutter_for_half(work, intersection, entity, side)
        slab = build_half_slab(work, entity, side)
        cutter = intersection.intersect(slab)

        unless cutter &&
               cutter.valid? &&
               cutter.manifold? &&
               cutter.volume > EPS_VOL
          raise 'Không dựng được dao khấu 1/2 chiều sâu.'
        end

        # Không tự erase operands. Solid Tools có thể đã xóa/tái dùng operand;
        # workspace sẽ dọn toàn bộ sau cùng.
        expand_cutter_in_plane(cutter, entity, @gap_mm)
        cutter
      end

      def expand_cutter_in_plane(cutter, entity, gap_mm)
        return cutter if gap_mm <= 0.0

        target_tr = world_transform(entity)
        inverse = target_tr.inverse
        thin = thickness_axis(entity)

        vertices = cutter.definition.entities
          .grep(Sketchup::Face)
          .flat_map(&:vertices)
          .uniq

        raise 'Dao khấu không có đỉnh.' if vertices.empty?

        cutter_tr = cutter.transformation
        local_points = vertices.map do |vertex|
          vertex.position.transform(cutter_tr).transform(inverse)
        end

        box = Geom::BoundingBox.new
        box.add(local_points)

        mins = [box.min.x, box.min.y, box.min.z]
        maxs = [box.max.x, box.max.y, box.max.z]
        center = box.center

        factors = [1.0, 1.0, 1.0]

        3.times do |axis|
          next if axis == thin

          size = maxs[axis] - mins[axis]
          next if size < 1.0e-9

          scale = local_axis_scale(target_tr, axis)
          gap_local = gap_mm.mm / scale
          factors[axis] = (size + 2.0 * gap_local) / size
        end

        local_scale = Geom::Transformation.scaling(
          center,
          factors[0],
          factors[1],
          factors[2]
        )
        world_scale = target_tr * local_scale * inverse
        cutter.transform!(world_scale)
        cutter
      end

      def replace_geometry(target, result)
        target.make_unique if target.respond_to?(:make_unique)

        original_name = target.name
        original_layer = target.layer
        original_material = target.material

        destination = target.definition.entities
        destination.clear!

        world_to_target = world_transform(target).inverse
        instance = destination.add_instance(
          result.definition,
          world_to_target * result.transformation
        )
        instance.explode

        target.name = original_name
        target.layer = original_layer
        target.material = original_material if original_material

        raise "#{original_name}: tấm sau khấu không còn Solid." unless target.manifold?
      end

      def execute
        validate_pair!
        raise 'Chưa có preview giao thật.' unless @preview_ready

        @busy = true
        started = false

        @model.start_operation('TT - Khấu Âm Dương 1/2', true)
        started = true

        workspace = @context.add_group
        workspace.transformation = @edit.inverse
        work = workspace.entities

        # Dùng một intersection riêng làm mẫu dao và hai bản sao riêng
        # để trim A/B. Không tái sử dụng operand đã bị Solid Tools tiêu thụ.
        intersection = build_intersection_solid(work)
        intersection_a = duplicate_solid(work, intersection)
        intersection_b = duplicate_solid(work, intersection)

        a_copy = copy_solid(work, @a)
        b_copy = copy_solid(work, @b)

        a_role = @swap_roles ? :back : :front
        b_role = @swap_roles ? :front : :back

        cutter_a = cutter_for_half(
          work,
          intersection_a,
          @a,
          board_cut_side(@a, a_role)
        )
        cutter_b = cutter_for_half(
          work,
          intersection_b,
          @b,
          board_cut_side(@b, b_role)
        )

        result_a = cutter_a.trim(a_copy)
        result_b = cutter_b.trim(b_copy)

        unless result_a && result_a.valid? && result_a.manifold?
          raise 'Tấm A khấu 1/2 thất bại.'
        end
        unless result_b && result_b.valid? && result_b.manifold?
          raise 'Tấm B khấu 1/2 thất bại.'
        end

        replace_geometry(@a, result_a)
        replace_geometry(@b, result_b)

        @a.set_attribute(PREF, 'half_lap_role', a_role.to_s)
        @b.set_attribute(PREF, 'half_lap_role', b_role.to_s)
        @a.set_attribute(PREF, 'gap_mm', @gap_mm)
        @b.set_attribute(PREF, 'gap_mm', @gap_mm)

        workspace.erase! if workspace.valid?

        @model.commit_operation
        started = false

        @model.selection.clear
        @model.selection.add(@a)
        @model.selection.add(@b)

        Sketchup.set_status_text(
          'Đã KHẤU ÂM DƯƠNG 1/2 · hai rãnh gặp tại tâm chiều sâu · Ctrl+Z hoàn tác.',
          SB_PROMPT
        )
        UI.beep
      rescue StandardError
        @model.abort_operation if started
        raise
      ensure
        @busy = false
      end

      def reset_after_execute
        @preview_ready = false
        @preview_lines = []
        @preview_a_cut_lines = []
        @preview_b_cut_lines = []
        @preview_center = nil
        @preview_volume_mm3 = 0.0
        @a = nil
        @b = nil
        @hover = nil
        @stage = :pick_a
        status
      end

      def format_volume(mm3)
        if mm3 >= 1_000_000.0
          "#{(mm3 / 1_000_000.0).round(2)} dm³"
        else
          "#{mm3.round(1)} mm³"
        end
      end
    end
  end
end
