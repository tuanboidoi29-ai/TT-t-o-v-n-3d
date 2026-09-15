# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.9.0
# AUTO QUÉT MẶC ĐỊNH + 3 ĐIỂM DỰ PHÒNG
#
# AUTO QUÉT:
# - Giữ chuột tại P1 (biên cố định) -> quét sang phía cần co/kéo -> thả = tự chốt P2.
# - Tự nhận đủ 6 hướng X+/X-/Y+/Y-/Z+/Z- theo Model Axis.
# - Quét quá ngắn bị hủy, không rơi sang thao tác click P1/P2 ngoài ý muốn.
# - Sau khi thả P2: di chuột/bắt P3 hoặc nhập kích thước như engine V0.8.x.
# - TAB ở bước P1: AUTO QUÉT <-> 3 ĐIỂM.
# - TAB ở bước P3 vẫn giữ chức năng THÊM HƯỚNG.
#
# PHẠM VI TỰ ĐỘNG:
# - Có selection: dùng selection.
# - Không selection + P1 nằm trong container có Group/Component con: tự khóa container cha dưới chuột.
# - Nếu không có container cha: dùng Group/Component trong active context.
#
# File này chỉ thay lớp INPUT/PREVIEW. Engine TRUE DETAIL STRETCH nằm trong stretch_detail_fix.rb.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.9.0'.freeze

    %i[AUTO_SCAN_MIN_PX AUTO_SCAN_ALPHA].each do |name|
      remove_const(name) if const_defined?(name, false)
    end
    AUTO_SCAN_MIN_PX = 10.0
    AUTO_SCAN_ALPHA = 38

    class Tool
      aliases_ready =
        (method_defined?(:tt_v081_on_key_down) || private_method_defined?(:tt_v081_on_key_down)) &&
        (method_defined?(:tt_v081_initialize) || private_method_defined?(:tt_v081_initialize))

      unless aliases_ready
        alias_method :tt_v081_initialize, :initialize
        alias_method :tt_v081_activate, :activate
        alias_method :tt_v081_on_key_down, :onKeyDown
        alias_method :tt_v081_on_mouse_move, :onMouseMove
        alias_method :tt_v081_on_lbutton_down, :onLButtonDown
        alias_method :tt_v081_on_lbutton_up, :onLButtonUp
        alias_method :tt_v081_draw, :draw
        alias_method :tt_v081_update_status, :update_status
      end

      def initialize
        tt_v081_initialize
        @input_mode = :auto_scan
        @auto_dragging = false
        @auto_scan_start_2d = nil
        @auto_scan_current_2d = nil
        @auto_scope_source = :context
      end

      def activate
        tt_v081_activate
        update_status
        @model.active_view.invalidate
      end

      # TAB ở P1 đổi AUTO QUÉT / 3 ĐIỂM.
      # TAB ở P3 để engine cũ xử lý THÊM HƯỚNG.
      def onKeyDown(key, repeat, flags, view)
        if tab_key?(key) && @state == :p1
          @input_mode = (@input_mode == :auto_scan ? :three_point : :auto_scan)
          @auto_dragging = false
          @auto_scan_start_2d = nil
          @auto_scan_current_2d = nil
          update_status
          view.invalidate
          return
        end

        tt_v081_on_key_down(key, repeat, flags, view)
      end

      def onMouseMove(flags, x, y, view)
        if @input_mode == :auto_scan && @auto_dragging
          @auto_scan_current_2d = Geom::Point3d.new(x.to_f, y.to_f, 0)
        end
        tt_v081_on_mouse_move(flags, x, y, view)
      end

      def onLButtonDown(flags, x, y, view)
        if @input_mode == :auto_scan && @state == :p1
          prepare_auto_scope(view, x, y)
          @auto_dragging = true
          @auto_scan_start_2d = Geom::Point3d.new(x.to_f, y.to_f, 0)
          @auto_scan_current_2d = @auto_scan_start_2d.clone
          tt_v081_on_lbutton_down(flags, x, y, view)
          update_status('AUTO QUÉT · giữ chuột và quét sang PHÍA cần co/kéo · thả để chốt P2.')
          view.invalidate
          return
        end

        tt_v081_on_lbutton_down(flags, x, y, view)
      end

      def onLButtonUp(flags, x, y, view)
        if @input_mode == :auto_scan && @auto_dragging && @state == :p2
          @auto_dragging = false
          @auto_scan_current_2d = Geom::Point3d.new(x.to_f, y.to_f, 0)

          distance = if @auto_scan_start_2d
                       @auto_scan_start_2d.distance(@auto_scan_current_2d)
                     else
                       0.0
                     end

          if distance < AUTO_SCAN_MIN_PX
            @first_press_active = false
            reset_current_points
            @auto_scan_start_2d = nil
            @auto_scan_current_2d = nil
            UI.beep
            update_status('AUTO QUÉT quá ngắn · giữ chuột tại biên P1 rồi QUÉT rõ sang phía cần kéo.')
            view.invalidate
            return
          end

          # Dùng finalize chuẩn của engine gốc: snap InputPoint + nhận Model Axis.
          tt_v081_on_lbutton_up(flags, x, y, view)
          if @state == :p3
            update_status("AUTO đã nhận #{side_name} · kéo tới P3 hoặc nhập kích thước trực tiếp.")
          else
            update_status('AUTO chưa nhận được hướng rõ · quét lại theo X/Y/Z.')
          end
          view.invalidate
          return
        end

        tt_v081_on_lbutton_up(flags, x, y, view)
      end

      def draw(view)
        tt_v081_draw(view)

        draw_input_mode_badge(view)

        return unless @input_mode == :auto_scan
        return unless @auto_dragging && @state == :p2
        return unless @p1_root && @ip && @ip.valid?

        p2 = world_to_root(@ip.position)
        axis = dominant_axis(@p1_root, p2)
        return unless axis

        diff = coord(p2, axis) - coord(@p1_root, axis)
        return if diff.abs < MIN_AXIS_DELTA

        region = {
          axis: axis,
          side_sign: diff >= 0 ? 1 : -1,
          cut_coord: coord(@p1_root, axis),
          ref_coord: coord(p2, axis),
          p1_root: clone_point(@p1_root),
          p2_root: clone_point(p2),
          delta: 0.0
        }

        draw_auto_selected_halfspace(view, region)
        draw_auto_scan_gesture(view, region)
      rescue StandardError => error
        puts "[TT Stretch AUTO draw] #{error.class}: #{error.message}"
      end

      def update_status(extra = nil)
        return tt_v081_update_status(extra) if extra
        return tt_v081_update_status if @input_mode != :auto_scan

        pending = @pending_regions && !@pending_regions.empty? ? " · #{@pending_regions.length} hướng chờ" : ''
        text = case @state
               when :p1
                 "AUTO QUÉT · giữ chuột tại P1 -> quét sang phía cần kéo -> thả#{pending} · TAB = 3 ĐIỂM."
               when :p2
                 'AUTO QUÉT · đang nhận hướng X± Y± Z± · thả chuột để chốt P2.'
               when :p3
                 update_vcb
                 mode = @add_mode ? 'THÊM HƯỚNG BẬT' : 'xác nhận để hoàn tất'
                 "AUTO #{side_name} · P3 hoặc nhập số · TAB/SHIFT thêm hướng · #{mode}#{pending}."
               else
                 'CO GIÃN AUTO QUÉT'
               end
        Sketchup.set_status_text(text, SB_PROMPT)
      end

      private

      # Ưu tiên phạm vi người dùng đã chọn. Nếu chưa chọn, thử tự nhận container cha dưới P1.
      def prepare_auto_scope(view, x, y)
        selected = @model.selection.to_a.select { |e| selectable?(e) && e.valid? }
        if !selected.empty?
          @scope = selected.uniq
          @auto_scope_source = :selection
        else
          container = auto_container_under_cursor(view, x, y)
          if container
            @scope = [container]
            @auto_scope_source = :container
          else
            @scope = @model.active_entities.to_a.select { |e| selectable?(e) && e.valid? }
            @auto_scope_source = :context
          end
        end
        @scope_bounds = scope_bounds_root
      rescue StandardError => error
        puts "[TT Stretch AUTO scope] #{error.class}: #{error.message}"
        @scope = initial_scope
        @scope_bounds = scope_bounds_root
        @auto_scope_source = :context
      end

      # Chỉ tự khóa khi entity dưới chuột thực sự giống container (có Group/Component con).
      # Nếu P1 đang nằm trên một tấm leaf rời, không khóa riêng tấm đó; để toàn context cùng tham gia stretch.
      def auto_container_under_cursor(view, x, y)
        picker = view.pick_helper
        picker.do_pick(x, y)
        count = picker.count.to_i
        return nil if count <= 0

        [count, 10].min.times do |index|
          path = picker.path_at(index)
          next unless path.respond_to?(:each)

          candidate = path.find { |entity| selectable?(entity) && entity.valid? }
          next unless candidate
          next unless container_like?(candidate)

          return candidate
        end
        nil
      rescue StandardError
        nil
      end

      def container_like?(entity)
        entities = child_entities(entity)
        entities.any? { |child| child.valid? && selectable?(child) }
      rescue StandardError
        false
      end

      def draw_input_mode_badge(view)
        text = @input_mode == :auto_scan ? 'CO GIÃN: AUTO QUÉT  [TAB = 3 ĐIỂM]' : 'CO GIÃN: 3 ĐIỂM  [TAB = AUTO QUÉT]'
        color = @input_mode == :auto_scan ? Sketchup::Color.new(255, 145, 0) : Sketchup::Color.new(100, 190, 255)
        point = Geom::Point3d.new(18, 28, 0)
        if respond_to?(:draw_text_safe, true)
          draw_text_safe(view, point, text, color)
        else
          view.drawing_color = color
          view.draw_text(point, text)
        end
      rescue StandardError
        nil
      end

      # Trong lúc giữ chuột quét, phủ ngay nửa không gian sẽ được chọn.
      def draw_auto_selected_halfspace(view, region)
        return unless respond_to?(:affected_region_bounds, true)
        bounds = affected_region_bounds(region, 0.0)
        return unless bounds

        if respond_to?(:box_faces, true)
          view.drawing_color = Sketchup::Color.new(255, 145, 0, AUTO_SCAN_ALPHA)
          box_faces(bounds).each do |face|
            view.draw(GL_QUADS, face.map { |p| root_to_world(p) })
          end
        end

        if respond_to?(:box_edge_points, true)
          view.drawing_color = Sketchup::Color.new(255, 125, 0, 210)
          view.line_width = 4
          view.draw(GL_LINES, box_edge_points(bounds).map { |p| root_to_world(p) })
        end
      end

      def draw_auto_scan_gesture(view, region)
        a = root_to_world(region[:p1_root])
        b_root = clone_point(region[:p1_root])
        set_coord(b_root, region[:axis], coord(region[:p2_root], region[:axis]))
        b = root_to_world(b_root)

        color = AXIS_COLORS[region[:axis]]
        view.drawing_color = color
        view.line_width = 7
        view.draw(GL_LINES, [a, b])

        label = "AUTO #{axis_name(region[:axis])}#{region[:side_sign] > 0 ? '+' : '-'} · THẢ CHUỘT = CHỌN VÙNG"
        screen = view.screen_coords(b)
        point = Geom::Point3d.new(screen.x + 14, screen.y - 18, 0)
        if respond_to?(:draw_text_safe, true)
          draw_text_safe(view, point, label, color)
        else
          view.draw_text(point, label)
        end
      rescue StandardError
        nil
      end
    end
  end
end
