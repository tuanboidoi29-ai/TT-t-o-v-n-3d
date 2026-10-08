# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - KÉO MẶT FACE
# SketchUp 2021+
#
# Quy trình 1 click:
# 1) Gọi công cụ.
# 2) Rà vào Face trong Group/Component.
# 3) Face sáng cam + hiện kích thước chính mặt đang rà.
# 4) Face đang rà tự xác định và khóa hướng kéo theo pháp tuyến gần trục local nhất.
# 5) Đưa chuột kéo ra/vào; bắt Endpoint / Edge / Face / Inference.
# 6) Click 1 lần để tạo. Có thể nhập kích thước mm + Enter.
#
# Mặt đối diện giữ cố định. Một thao tác = một Undo.

require 'sketchup.rb'

module TranTuanNoiThat
  module ScaleCornerLock
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.9.261'.freeze

    MIN_FACTOR = 0.001
    AXIS_ALIGN_MIN = 0.70

    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end

    class Tool
      def initialize
        @model = Sketchup.active_model
        @context_to_world = @model.edit_transform

        @state = :hover_face
        @hover = nil
        @target = nil

        @entity = nil
        @bbox = nil
        @original_transform = nil
        @preview_transform = nil

        @axis = nil
        @side = nil
        @drag_coord = nil
        @fixed_coord = nil

        @original_size = 0.0
        @current_size = 0.0
        @factor = 1.0

        @input_point = Sketchup::InputPoint.new
        @snap_point = nil
        @guide_point = nil
        @face_center_world = nil
        @axis_world = nil
      end

      def activate
        Sketchup.status_text =
          'KÉO MẶT FACE · rà vào Face → tự khóa hướng → kéo → bắt điểm → click 1 lần để tạo.'
        @model.active_view.invalidate
      end

      def deactivate(view)
        clear_vcb
        view.invalidate if view
      end

      def enableVCB?
        @state == :drag_face
      end

      def onCancel(_reason, view)
        if @state == :drag_face
          clear_drag
          @state = :hover_face
          @hover = nil
          Sketchup.status_text = 'Đã hủy · rà Face khác để tiếp tục.'
          view.invalidate
        else
          @model.select_tool(nil)
        end
      end

      def onMouseMove(_flags, x, y, view)
        if @state == :hover_face
          picked = pick_face_target(view, x, y)

          if picked
            @hover = picked
            update_hover_status
          elsif @hover
            # Không cần click để khóa Face.
            # Face cuối cùng vừa rà tự khóa hướng, chuyển thẳng sang preview kéo.
            begin_drag(@hover)
            @state = :drag_face
            update_drag_preview(view, x, y)
          else
            Sketchup.status_text =
              'KÉO MẶT FACE · rà vào Face của Group/Component để nhận mặt và hướng kéo.'
          end
        else
          update_drag_preview(view, x, y)
        end

        view.invalidate
      rescue StandardError => error
        puts "[TT KeoMatFace move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        if @state == :drag_face
          update_drag_preview(view, x, y)

          if (@factor - 1.0).abs < 0.000001
            UI.beep
            Sketchup.status_text =
              'Chưa có khoảng kéo · rê chuột ra/vào theo hướng Face rồi click 1 lần để tạo.'
            return
          end

          commit_drag
          @state = :hover_face
          @hover = nil
          view.invalidate
        else
          # Ở trạng thái rà Face, click không dùng để khóa hướng.
          # Hướng được khóa tự động khi rời Face và bắt đầu kéo.
          UI.beep if @hover.nil?
        end
      rescue StandardError => error
        UI.messagebox("Kéo Mặt Face:\n#{error.message}")
      end

      def onUserText(text, view)
        return UI.beep unless @state == :drag_face

        raw = text.to_s.strip.tr(',', '.')
        return UI.beep if raw.empty?

        target_length =
          if raw.downcase.end_with?('x')
            factor = Float(raw[0...-1].strip)
            raise 'Hệ số phải lớn hơn 0.' unless factor > 0.0
            @original_size * factor
          elsif raw.match?(/\A[-+]?\d+(?:\.\d+)?\z/)
            raw.to_f.mm
          else
            raw.to_l
          end

        raise 'Kích thước phải lớn hơn 0.' unless target_length > 0.0

        @factor = valid_factor(target_length / @original_size)
        @current_size = @original_size * @factor
        rebuild_preview_transform
        commit_drag
        @state = :hover_face
        @hover = nil
        view.invalidate
      rescue StandardError => error
        UI.beep
        UI.messagebox(
          "Không nhận được kích thước:\n#{error.message}\n"           "Ví dụ: 500 hoặc 500mm. Hệ số: 1.2x"
        )
      end

      def draw(view)
        if @state == :hover_face
          draw_hover(view) if @hover
        else
          draw_drag(view)
          @input_point.draw(view) if @input_point && @input_point.valid?
        end
      rescue StandardError => error
        puts "[TT KeoMatFace draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        info = @state == :hover_face ? @hover : @target

        if info
          preview_face_world_points(info).each { |point| bb.add(point) }

          if @entity && @bbox && @preview_transform
            entity_world_corners(@preview_transform).each { |point| bb.add(point) }
          end
        end

        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def active_entities
        @model.active_entities
      end

      def valid_container?(entity)
        entity &&
          entity.valid? &&
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
          !entity.locked?
      end

      def pick_face_target(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)

        count = helper.count
        return nil if count <= 0

        0.upto([count - 1, 10].min) do |index|
          path = helper.path_at(index)
          next unless path && !path.empty?

          face_index = path.rindex { |item| item.is_a?(Sketchup::Face) }
          next unless face_index

          face = path[face_index]

          container_index = path.index do |item|
            valid_container?(item) && active_entities.include?(item)
          end
          next unless container_index && container_index < face_index

          container = path[container_index]
          info = build_face_info(path, face_index, face, container)
          return info if info
        end

        nil
      rescue StandardError
        nil
      end

      def build_face_info(path, face_index, face, container)
        container_world = @context_to_world * container.transformation

        face_world = @context_to_world
        path[0...face_index].each do |item|
          if item.is_a?(Sketchup::Group) || item.is_a?(Sketchup::ComponentInstance)
            face_world *= item.transformation
          end
        end

        face_to_container = container_world.inverse * face_world

        normal = face.normal.transform(face_to_container)
        return nil if normal.length < 0.000001
        normal.normalize!

        comps = [normal.x.abs, normal.y.abs, normal.z.abs]
        axis = comps.each_with_index.max[1]
        return nil if comps[axis] < AXIS_ALIGN_MIN

        bounds = container.definition.bounds
        center_local = face.bounds.center.transform(face_to_container)
        center_value = coord(center_local, axis)
        middle = coord(bounds.center, axis)
        side = center_value >= middle ? :max : :min

        mesh = face.mesh(0)
        triangles = []
        mesh.polygons.each do |poly|
          indices = poly.map(&:abs)
          next if indices.length < 3

          p0 = mesh.point_at(indices[0]).transform(face_to_container)
          (1...(indices.length - 1)).each do |i|
            triangles << [
              p0,
              mesh.point_at(indices[i]).transform(face_to_container),
              mesh.point_at(indices[i + 1]).transform(face_to_container)
            ]
          end
        end

        loop_points = face.outer_loop.vertices.map do |vertex|
          vertex.position.transform(face_to_container)
        end

        {
          face: face,
          entity: container,
          axis: axis,
          side: side,
          triangles: triangles,
          loop: loop_points,
          center_local: center_local
        }
      rescue StandardError
        nil
      end

      def begin_drag(info)
        @target = info
        @entity = info[:entity]
        @bbox = @entity.definition.bounds
        @original_transform = @entity.transformation
        @preview_transform = @original_transform
        @axis = info[:axis]
        @side = info[:side]

        @drag_coord =
          @side == :max ? axis_max(@bbox, @axis) : axis_min(@bbox, @axis)
        @fixed_coord =
          @side == :max ? axis_min(@bbox, @axis) : axis_max(@bbox, @axis)

        world_transform = @context_to_world * @original_transform
        axis_vector = transform_axis(world_transform, @axis)
        axis_scale = axis_vector.length
        raise 'Không đọc được hướng kéo của Face.' if axis_scale < 0.000001

        @original_size = (@drag_coord - @fixed_coord).abs * axis_scale
        raise 'Kích thước theo hướng kéo bằng 0.' if @original_size < 0.000001

        @current_size = @original_size
        @factor = 1.0

        @face_center_world = info[:center_local].transform(world_transform)
        @axis_world = axis_vector.clone
        @axis_world.normalize!

        @input_point.clear
        @snap_point = nil
        @guide_point = @face_center_world

        @model.selection.clear
        @model.selection.add(@entity)

        Sketchup.set_status_text('Kích thước', SB_VCB_LABEL)
        Sketchup.set_status_text(format_mm(@current_size), SB_VCB_VALUE)
        Sketchup.status_text =
          "ĐÃ KHÓA HƯỚNG #{axis_name(@axis)} THEO FACE · kéo ra/vào · bắt điểm · click 1 lần để tạo."
      end

      def update_drag_preview(view, x, y)
        return unless @state == :drag_face && @entity && @axis_world

        @input_point.pick(view, x, y)
        target_world = nil

        if @input_point.valid?
          target_world = @input_point.position
          @snap_point = target_world
          view.tooltip = @input_point.tooltip if view.respond_to?(:tooltip=)
        else
          @snap_point = nil
          ray = view.pickray(x, y)
          pair = Geom.closest_points([@face_center_world, @axis_world], ray)
          target_world = pair && pair[0]
        end

        return unless target_world

        @guide_point = target_world

        world_to_local = (@context_to_world * @original_transform).inverse
        target_local = target_world.transform(world_to_local)
        target_coord = coord(target_local, @axis)

        denominator = @drag_coord - @fixed_coord
        candidate = (target_coord - @fixed_coord) / denominator

        if candidate <= MIN_FACTOR
          Sketchup.status_text =
            'Không kéo xuyên qua mặt đối diện đang khóa.'
          return
        end

        @factor = valid_factor(candidate)
        @current_size = @original_size * @factor
        rebuild_preview_transform

        Sketchup.set_status_text(format_mm(@current_size), SB_VCB_VALUE)
        Sketchup.status_text =
          "KÉO THEO #{axis_name(@axis)} · #{format_mm(@current_size)} · bắt điểm rồi CLICK 1 LẦN để tạo."
      rescue StandardError => error
        puts "[TT KeoMatFace preview] #{error.class}: #{error.message}"
      end

      def valid_factor(value)
        factor = value.to_f
        raise 'Hệ số kéo không hợp lệ.' unless factor.finite? && factor > 0.0
        [factor, MIN_FACTOR].max
      end

      def rebuild_preview_transform
        factors = [1.0, 1.0, 1.0]
        factors[@axis] = @factor

        center = @bbox.center
        values = [center.x, center.y, center.z]
        values[@axis] = @fixed_coord
        anchor = Geom::Point3d.new(values[0], values[1], values[2])

        to_anchor = Geom::Transformation.translation(
          Geom::Vector3d.new(anchor.x, anchor.y, anchor.z)
        )
        from_anchor = Geom::Transformation.translation(
          Geom::Vector3d.new(-anchor.x, -anchor.y, -anchor.z)
        )
        scaling = Geom::Transformation.scaling(
          ORIGIN,
          factors[0],
          factors[1],
          factors[2]
        )

        @preview_transform =
          @original_transform * to_anchor * scaling * from_anchor
      end

      def commit_drag
        raise 'Đối tượng không còn hợp lệ.' unless valid_container?(@entity)
        raise 'Chưa có preview hợp lệ.' unless @preview_transform

        @model.start_operation('TT - Kéo Mặt Face', true)
        started = true

        @entity.transformation = @preview_transform

        @model.commit_operation
        started = false

        Sketchup.status_text =
          "Đã kéo Face → #{format_mm(@current_size)} · mặt đối diện giữ nguyên · tiếp tục rà Face khác."

        clear_drag
        true
      rescue StandardError
        @model.abort_operation if started rescue nil
        raise
      end

      def clear_drag
        @target = nil
        @entity = nil
        @bbox = nil
        @original_transform = nil
        @preview_transform = nil
        @axis = nil
        @side = nil
        @drag_coord = nil
        @fixed_coord = nil
        @original_size = 0.0
        @current_size = 0.0
        @factor = 1.0
        @snap_point = nil
        @guide_point = nil
        @face_center_world = nil
        @axis_world = nil
        @input_point.clear if @input_point
        clear_vcb
      end

      def update_hover_status
        dims = face_dimensions_mm(@hover)
        Sketchup.status_text =
          "FACE #{format_face_dims(dims)} · hướng kéo #{axis_name(@hover[:axis])} · đưa chuột ra khỏi Face để kéo."
      end

      def face_dimensions_mm(info)
        bb = Geom::BoundingBox.new
        info[:loop].each { |point| bb.add(point) }

        plane_axes = [0, 1, 2] - [info[:axis]]
        tr = @context_to_world * info[:entity].transformation

        plane_axes.map do |axis|
          local_span = axis_max(bb, axis) - axis_min(bb, axis)
          (local_span.abs * transform_axis(tr, axis).length).to_mm.round(1)
        end.sort.reverse
      rescue StandardError
        [0.0, 0.0]
      end

      def format_face_dims(dims)
        "#{dims[0]} × #{dims[1]} mm"
      end

      def preview_face_world_points(info)
        tr =
          if @state == :drag_face && info.equal?(@target)
            @context_to_world * (@preview_transform || @original_transform)
          else
            @context_to_world * info[:entity].transformation
          end

        info[:loop].map { |point| point.transform(tr) }
      end

      def preview_triangles_world(info)
        tr =
          if @state == :drag_face && info.equal?(@target)
            @context_to_world * (@preview_transform || @original_transform)
          else
            @context_to_world * info[:entity].transformation
          end

        info[:triangles].map do |triangle|
          triangle.map { |point| point.transform(tr) }
        end
      end

      def draw_hover(view)
        draw_face_fill(
          view,
          @hover,
          Sketchup::Color.new(255, 145, 30, 100)
        )

        draw_loop(
          view,
          preview_face_world_points(@hover),
          Sketchup::Color.new(255, 120, 0),
          4
        )

        center = @hover[:center_local].transform(
          @context_to_world * @hover[:entity].transformation
        )
        dims = face_dimensions_mm(@hover)

        view.draw_text(
          center,
          "MẶT #{format_face_dims(dims)} · KÉO #{axis_name(@hover[:axis])}",
          color: Sketchup::Color.new(255, 100, 0)
        )
      end

      def draw_drag(view)
        draw_entity_box(
          view,
          entity_world_corners(@preview_transform),
          Sketchup::Color.new(241, 150, 170),
          2
        )

        draw_face_fill(
          view,
          @target,
          Sketchup::Color.new(255, 145, 30, 110)
        )

        draw_loop(
          view,
          preview_face_world_points(@target),
          Sketchup::Color.new(255, 120, 0),
          5
        )

        fixed_points =
          bbox_face_world_points(@axis, opposite_side(@side), @preview_transform)

        draw_loop(
          view,
          fixed_points,
          Sketchup::Color.new(230, 45, 45),
          4
        )

        if @guide_point && @face_center_world
          view.line_width = 2
          view.drawing_color = Sketchup::Color.new(40, 130, 240)
          view.draw(GL_LINES, [@face_center_world, @guide_point])
        end

        if @snap_point
          view.draw_points(
            [@snap_point],
            12,
            3,
            Sketchup::Color.new(255, 150, 20)
          )
        end

        view.draw_text(
          preview_face_center_world,
          "#{format_mm(@current_size)} · CLICK 1 LẦN TẠO",
          color: Sketchup::Color.new(30, 90, 180)
        )
      end

      def draw_face_fill(view, info, color)
        view.drawing_color = color
        preview_triangles_world(info).each do |triangle|
          view.draw(GL_TRIANGLES, triangle)
        end
      end

      def draw_loop(view, points, color, width)
        return if points.length < 2

        view.line_width = width
        view.drawing_color = color
        view.draw(GL_LINE_STRIP, points + [points.first])
      end

      def draw_entity_box(view, corners, color, width)
        pairs = [
          [0,1],[1,3],[3,2],[2,0],
          [4,5],[5,7],[7,6],[6,4],
          [0,4],[1,5],[2,6],[3,7]
        ]

        view.line_width = width
        view.drawing_color = color
        view.draw(
          GL_LINES,
          pairs.flat_map { |a, b| [corners[a], corners[b]] }
        )
      end

      def entity_world_corners(transform_context)
        tr = @context_to_world * transform_context
        8.times.map { |index| @bbox.corner(index).transform(tr) }
      end

      def bbox_face_world_points(axis, side, transform_context)
        min = @bbox.min
        max = @bbox.max
        value = side == :max ? coord(max, axis) : coord(min, axis)

        points =
          case axis
          when 0
            [
              Geom::Point3d.new(value, min.y, min.z),
              Geom::Point3d.new(value, max.y, min.z),
              Geom::Point3d.new(value, max.y, max.z),
              Geom::Point3d.new(value, min.y, max.z)
            ]
          when 1
            [
              Geom::Point3d.new(min.x, value, min.z),
              Geom::Point3d.new(max.x, value, min.z),
              Geom::Point3d.new(max.x, value, max.z),
              Geom::Point3d.new(min.x, value, max.z)
            ]
          else
            [
              Geom::Point3d.new(min.x, min.y, value),
              Geom::Point3d.new(max.x, min.y, value),
              Geom::Point3d.new(max.x, max.y, value),
              Geom::Point3d.new(min.x, max.y, value)
            ]
          end

        tr = @context_to_world * transform_context
        points.map { |point| point.transform(tr) }
      end

      def preview_face_center_world
        @target[:center_local].transform(
          @context_to_world * @preview_transform
        )
      end

      def transform_axis(transform, axis)
        case axis
        when 0 then transform.xaxis
        when 1 then transform.yaxis
        else transform.zaxis
        end
      end

      def coord(point, axis)
        axis == 0 ? point.x : (axis == 1 ? point.y : point.z)
      end

      def axis_min(bounds, axis)
        coord(bounds.min, axis)
      end

      def axis_max(bounds, axis)
        coord(bounds.max, axis)
      end

      def opposite_side(side)
        side == :max ? :min : :max
      end

      def axis_name(axis)
        case axis
        when 0 then 'X'
        when 1 then 'Y'
        else 'Z'
        end
      end

      def format_mm(length)
        "#{length.to_mm.round(1)} mm"
      rescue StandardError
        length.to_s
      end

      def clear_vcb
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      rescue StandardError
      end
    end
  end
end
