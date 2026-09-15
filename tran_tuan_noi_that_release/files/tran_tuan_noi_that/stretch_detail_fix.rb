# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.8.1
# TRUE 3D DETAIL STRETCH + PREVIEW RÕ
#
# HÌNH HỌC V0.8.x:
# - Group crossing P1 KHÔNG Move parent; đi vào geometry thật.
# - Chỉ vertex phía P2 được dịch; phía P1 giữ nguyên => co/kéo chi tiết thật.
# - Group/Component nằm hoàn toàn phía P2 mới Move nguyên khối.
# - Chọn theo Model Axis 3D, không theo camera.
#
# PREVIEW V0.8.1:
# - P1/biên cố định: đỏ-cam đậm, nét dày.
# - Vùng sẽ bị tác động: phủ cam trong suốt + khung 3D.
# - Biên ngoài hiện tại: cam.
# - Biên ngoài dự kiến sau co/kéo: xanh theo trục, nét dày.
# - Mũi tên kéo lớn + nhãn TĂNG/GIẢM và số mm ngay trên model.
# - P1/P2/P3 có nhãn rõ ràng.
# - Chỉ vẽ overlay; không sửa geometry cho đến khi xác nhận.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.8.1'.freeze

    %i[PREVIEW_PAD PREVIEW_ALPHA PREVIEW_FACE_ALPHA].each do |name|
      remove_const(name) if const_defined?(name, false)
    end
    PREVIEW_PAD = 20.mm
    PREVIEW_ALPHA = 55
    PREVIEW_FACE_ALPHA = 34

    class Tool
      # ------------------------------------------------------------
      # TRUE 3D DETAIL STRETCH ENGINE
      # ------------------------------------------------------------

      # - fixed: không đổi
      # - selected hoàn toàn: move nguyên instance
      # - crossing: KHÔNG move parent; đi vào raw geometry + children
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

        # CROSSING P1: tuyệt đối không MOVE parent.
        ensure_unique(entity)

        entities = child_entities(entity)
        entity_to_root = parent_to_root * entity.transformation
        raw_edges = entities.grep(Sketchup::Edge).select(&:valid?)
        children = entities.to_a.select { |e| e.valid? && selectable?(e) }

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

        children.each do |child|
          collect_entity_actions(
            child,
            entity_to_root,
            root_vector,
            region,
            actions,
            keys
          )
        end
      end

      # Raw geometry crossing P1 => dịch mọi vertex thuộc phía P2.
      # Không dùng khung 2D nên không phụ thuộc camera.
      def collect_raw_geometry_action(_entity, entities, edges, entity_to_root, root_vector, region, actions, keys, key)
        bb = raw_bounds_root(edges, entity_to_root)
        return unless bb

        relation = halfspace_relation(bb, region)
        return if relation == :fixed

        vertices = edges.flat_map(&:vertices).select(&:valid?).uniq
        return if vertices.empty?

        selected_vertices = if relation == :selected
                              vertices
                            else
                              vertices.select do |vertex|
                                root_point = vertex.position.transform(entity_to_root)
                                selected_coord?(coord(root_point, region[:axis]), region)
                              end
                            end

        return if selected_vertices.empty?

        local_vector = root_vector.transform(entity_to_root.inverse)
        actions << {
          kind: :move_vertices,
          entities: entities,
          vertices: selected_vertices,
          vector: local_vector
        }
        keys[key] = true
      end

      # ------------------------------------------------------------
      # PREVIEW RÕ V0.8.1
      # ------------------------------------------------------------

      def draw(view)
        # Điểm bắt chuẩn của SketchUp.
        @ip.draw(view) if @ip && @ip.valid? && (@state == :p1 || @state == :p2)
        @ip1.draw(view) if @ip1 && @ip1.valid?
        @ip2.draw(view) if @ip2 && @ip2.valid?

        draw_pending_regions(view) if respond_to?(:draw_pending_regions, true)

        # P1 vừa bắt: hiển thị ngay nhãn cố định.
        if @p1_root
          draw_preview_label(view, @p1_root, 'P1  CỐ ĐỊNH', Sketchup::Color.new(235, 55, 35))
        end

        # Khi đang chọn P2: đường trục dày + nhãn P2 động.
        if @state == :p2 && @p1_root && @ip && @ip.valid?
          preview_p2 = world_to_root(@ip.position)
          axis = dominant_axis(@p1_root, preview_p2)
          if axis
            draw_axis_hint(view, @p1_root, preview_p2, axis)
            draw_preview_label(
              view,
              preview_p2,
              "P2  CHỌN PHÍA #{axis_name(axis)}#{coord(preview_p2, axis) >= coord(@p1_root, axis) ? '+' : '-'}",
              AXIS_COLORS[axis]
            )
          end
        end

        return unless @axis && @cut_coord && @scope_bounds && !@scope_bounds.empty?

        region = current_region(false)

        # 1) P1 / mặt cắt cố định.
        draw_cut_plane(view, @axis, @cut_coord, Sketchup::Color.new(245, 55, 30), 5)

        # 2) Vùng phía P2 sẽ bị tác động.
        draw_affected_region_preview(view, region)

        # 3) Biên hiện tại thật của module phía đang kéo.
        current_extreme = preview_current_extreme(region)
        if current_extreme
          draw_cut_plane(view, @axis, current_extreme, Sketchup::Color.new(255, 155, 20), 2)
          draw_preview_plane_label(view, @axis, current_extreme, 'BIÊN HIỆN TẠI', Sketchup::Color.new(255, 155, 20))
        end

        # Nhãn P2 tại điểm người dùng chọn.
        if @p2_root
          draw_preview_label(view, @p2_root, 'P2  PHÍA CO/KÉO', Sketchup::Color.new(255, 150, 20))
        end

        # 4) P3 / biên dự kiến sau kéo.
        if @state == :p3 && @delta && @delta.abs > 0.001.mm
          target_extreme = current_extreme ? current_extreme + @delta : (@ref_coord + @delta)
          color = AXIS_COLORS[@axis]
          draw_cut_plane(view, @axis, target_extreme, color, 5)
          draw_target_ghost_box(view, region, target_extreme, color)
          draw_preview_plane_label(view, @axis, target_extreme, 'P3  BIÊN MỚI', color)
          draw_big_delta_arrow(view, region, current_extreme, target_extreme, color)
          draw_delta_text(view, region, current_extreme, target_extreme, color)
        elsif @state == :p3
          draw_preview_status_text(view, 'DI CHUỘT / NHẬP KÍCH THƯỚC ĐỂ XEM TRƯỚC')
        end
      rescue StandardError => error
        puts "[TT Stretch Preview V0.8.1] #{error.class}: #{error.message}"
      end

      # Vẽ khối bán trong suốt từ P1 tới biên phía được chọn.
      def draw_affected_region_preview(view, region)
        bounds = affected_region_bounds(region, 0.0)
        return unless bounds

        faces = box_faces(bounds)
        view.drawing_color = Sketchup::Color.new(255, 145, 0, PREVIEW_FACE_ALPHA)
        faces.each do |face|
          world = face.map { |p| root_to_world(p) }
          view.draw(GL_QUADS, world)
        end

        view.drawing_color = Sketchup::Color.new(255, 120, 0, 190)
        view.line_width = 3
        view.draw(GL_LINES, box_edge_points(bounds).map { |p| root_to_world(p) })
      end

      # Ghost box cho vùng sau khi co/kéo. Không thay đổi model thật.
      def draw_target_ghost_box(view, region, target_extreme, color)
        bounds = affected_region_bounds(region, @delta)
        return unless bounds

        c = Sketchup::Color.new(color.red, color.green, color.blue, PREVIEW_ALPHA)
        view.drawing_color = c
        view.line_width = 4
        view.draw(GL_LINES, box_edge_points(bounds).map { |p| root_to_world(p) })

        # Mặt đích phủ nhẹ để nhìn rõ vị trí cuối.
        face = plane_face_points(bounds, region[:axis], target_extreme)
        if face
          view.drawing_color = Sketchup::Color.new(color.red, color.green, color.blue, PREVIEW_FACE_ALPHA + 18)
          view.draw(GL_QUADS, face.map { |p| root_to_world(p) })
        end
      end

      def draw_big_delta_arrow(view, region, current_extreme, target_extreme, color)
        return unless current_extreme && target_extreme

        center = preview_plane_center(region[:axis], current_extreme)
        target = clone_point(center)
        set_coord(target, region[:axis], target_extreme)

        a = root_to_world(center)
        b = root_to_world(target)
        view.drawing_color = color
        view.line_width = 6
        view.draw(GL_LINES, [a, b])

        # Đầu mũi tên 2D để luôn dễ thấy dù camera xoay.
        sa = view.screen_coords(a)
        sb = view.screen_coords(b)
        dx = sb.x - sa.x
        dy = sb.y - sa.y
        len = Math.sqrt(dx * dx + dy * dy)
        return if len < 2.0

        ux = dx / len
        uy = dy / len
        px = -uy
        py = ux
        size = 13.0
        wing = 6.5

        p1 = Geom::Point3d.new(sb.x - ux * size + px * wing, sb.y - uy * size + py * wing, 0)
        p2 = Geom::Point3d.new(sb.x, sb.y, 0)
        p3 = Geom::Point3d.new(sb.x - ux * size - px * wing, sb.y - uy * size - py * wing, 0)
        view.line_width = 5
        view.draw2d(GL_LINE_STRIP, [p1, p2, p3])
      end

      def draw_delta_text(view, region, current_extreme, target_extreme, color)
        return unless current_extreme && target_extreme

        center = preview_plane_center(region[:axis], (current_extreme + target_extreme) * 0.5)
        screen = view.screen_coords(root_to_world(center))
        signed = @delta.to_f * region[:side_sign].to_f
        mode = signed >= 0 ? 'TĂNG' : 'GIẢM'
        amount = Sketchup.format_length(@delta.abs)
        text = "#{mode}  #{signed >= 0 ? '+' : '-'}#{amount}"
        draw_text_safe(view, Geom::Point3d.new(screen.x + 14, screen.y - 20, 0), text, color)
      end

      def draw_preview_label(view, root_point, text, color)
        screen = view.screen_coords(root_to_world(root_point))
        draw_text_safe(view, Geom::Point3d.new(screen.x + 10, screen.y - 14, 0), text, color)
      end

      def draw_preview_plane_label(view, axis, plane_coord, text, color)
        center = preview_plane_center(axis, plane_coord)
        draw_preview_label(view, center, text, color)
      end

      def draw_preview_status_text(view, text)
        return unless @p2_root
        screen = view.screen_coords(root_to_world(@p2_root))
        draw_text_safe(
          view,
          Geom::Point3d.new(screen.x + 16, screen.y + 18, 0),
          text,
          Sketchup::Color.new(245, 245, 245)
        )
      end

      def draw_text_safe(view, point2d, text, color)
        old = view.drawing_color
        view.drawing_color = color
        begin
          view.draw_text(point2d, text, size: 14, bold: true)
        rescue StandardError
          view.draw_text(point2d, text)
        ensure
          view.drawing_color = old if old
        end
      end

      def preview_current_extreme(region)
        axis = region[:axis]
        region[:side_sign] > 0 ? coord(@scope_bounds.max, axis) : coord(@scope_bounds.min, axis)
      rescue StandardError
        nil
      end

      def preview_plane_center(axis, plane_coord)
        mn = @scope_bounds.min
        mx = @scope_bounds.max
        point = Geom::Point3d.new(
          (mn.x + mx.x) * 0.5,
          (mn.y + mx.y) * 0.5,
          (mn.z + mx.z) * 0.5
        )
        set_coord(point, axis, plane_coord)
        point
      end

      def affected_region_bounds(region, delta)
        return nil unless @scope_bounds && !@scope_bounds.empty?
        mn = clone_point(@scope_bounds.min)
        mx = clone_point(@scope_bounds.max)
        axis = region[:axis]
        cut = region[:cut_coord]

        if region[:side_sign] > 0
          set_coord(mn, axis, cut)
          set_coord(mx, axis, coord(mx, axis) + delta.to_f)
        else
          set_coord(mx, axis, cut)
          set_coord(mn, axis, coord(mn, axis) + delta.to_f)
        end

        # Nếu co quá mức làm đảo min/max thì vẫn tạo preview ổn định bằng cách sắp lại.
        a = [mn.x, mn.y, mn.z]
        b = [mx.x, mx.y, mx.z]
        minp = Geom::Point3d.new([a[0], b[0]].min, [a[1], b[1]].min, [a[2], b[2]].min)
        maxp = Geom::Point3d.new([a[0], b[0]].max, [a[1], b[1]].max, [a[2], b[2]].max)
        { min: minp, max: maxp }
      rescue StandardError
        nil
      end

      def box_corners(bounds)
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

      def box_faces(bounds)
        p = box_corners(bounds)
        [
          [p[0], p[1], p[2], p[3]],
          [p[4], p[5], p[6], p[7]],
          [p[0], p[1], p[5], p[4]],
          [p[1], p[2], p[6], p[5]],
          [p[2], p[3], p[7], p[6]],
          [p[3], p[0], p[4], p[7]]
        ]
      end

      def box_edge_points(bounds)
        p = box_corners(bounds)
        indices = [
          0,1, 1,2, 2,3, 3,0,
          4,5, 5,6, 6,7, 7,4,
          0,4, 1,5, 2,6, 3,7
        ]
        indices.map { |i| p[i] }
      end

      def plane_face_points(bounds, axis, plane_coord)
        mn = bounds[:min]
        mx = bounds[:max]
        case axis
        when 0
          [
            Geom::Point3d.new(plane_coord, mn.y, mn.z),
            Geom::Point3d.new(plane_coord, mx.y, mn.z),
            Geom::Point3d.new(plane_coord, mx.y, mx.z),
            Geom::Point3d.new(plane_coord, mn.y, mx.z)
          ]
        when 1
          [
            Geom::Point3d.new(mn.x, plane_coord, mn.z),
            Geom::Point3d.new(mx.x, plane_coord, mn.z),
            Geom::Point3d.new(mx.x, plane_coord, mx.z),
            Geom::Point3d.new(mn.x, plane_coord, mx.z)
          ]
        when 2
          [
            Geom::Point3d.new(mn.x, mn.y, plane_coord),
            Geom::Point3d.new(mx.x, mn.y, plane_coord),
            Geom::Point3d.new(mx.x, mx.y, plane_coord),
            Geom::Point3d.new(mn.x, mx.y, plane_coord)
          ]
        end
      end
    end
  end
end
