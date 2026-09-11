# encoding: UTF-8
module TranTuanNoiThat
  module Board
    extend self
    def activate
      value = UI.inputbox(['Độ dày ván (mm):'], [TranTuanNoiThat.setting('thickness', 18.0)], 'TRẦN TUẤN - VẼ VÁN')
      return unless value
      mm = value[0].to_f
      return UI.messagebox('Độ dày phải lớn hơn 0 mm.') unless mm > 0
      TranTuanNoiThat.save_setting('thickness', mm)
      Sketchup.active_model.select_tool(Tool.new(mm.mm))
    end

    class Tool
      TAB = 9
      FACE = Sketchup::Color.new(255, 164, 70, 105)
      SIDE = Sketchup::Color.new(255, 125, 25, 72)
      EDGE = Sketchup::Color.new(235, 92, 0, 255)

      def initialize(thickness)
        @thickness = thickness
        @ip = Sketchup::InputPoint.new
        @ip1 = Sketchup::InputPoint.new
        reset
      end

      def activate; status; end
      def deactivate(view); view.invalidate; end
      def resume(view); status; view.invalidate; end

      def reset
        @state = 0
        @direction = 1
        @base = @normal = @axes = nil
        @sx = @sy = nil
        @ip.clear
        @ip1.clear
        status
      end

      def onCancel(reason, view)
        @state.zero? ? Sketchup.active_model.select_tool(nil) : reset
        view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        if @state.zero?
          @ip.pick(view, x, y)
          view.tooltip = @ip.tooltip if @ip.valid?
        elsif @state == 1
          @ip.pick(view, x, y, @ip1)
          rectangle(view, x, y)
          view.tooltip = size_text if valid?
        end
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        if @state.zero?
          @ip.pick(view, x, y)
          return unless @ip.valid?
          @ip1.copy!(@ip)
          @sx, @sy = x, y
          @state = 1
        elsif @state == 1
          rectangle(view, x, y)
          return UI.beep unless valid?
          @state = 2
        else
          create_board
          reset
        end
        status
        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        return unless key == TAB && @state == 2
        @direction *= -1
        status
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @state.zero? && @ip.display?
        @ip1.draw(view) if @state > 0 && @ip1.display?
        return unless valid?
        view.line_width = 2
        view.drawing_color = FACE
        view.draw(GL_QUADS, @base)
        if @state == 2
          top = offset_points
          view.drawing_color = SIDE
          4.times { |i| view.draw(GL_QUADS, [@base[i], @base[(i + 1) % 4], top[(i + 1) % 4], top[i]]) }
          view.draw(GL_QUADS, top)
          view.drawing_color = EDGE
          view.draw(GL_LINE_LOOP, @base)
          view.draw(GL_LINE_LOOP, top)
          lines = []
          4.times { |i| lines.concat([@base[i], top[i]]) }
          view.draw(GL_LINES, lines)
        else
          view.drawing_color = EDGE
          view.draw(GL_LINE_LOOP, @base)
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        (@base || []).each { |p| box.add(p) }
        offset_points.each { |p| box.add(p) } if valid?
        box
      end

      private

      def rectangle(view, x, y)
        origin = @ip1.position
        delta = @ip.valid? ? origin.vector_to(@ip.position) : nil
        candidate_axes = choose_axes(delta, view)
        @axes ||= candidate_axes if @sx && Math.hypot(x - @sx, y - @sy) >= 8
        axes = @axes || candidate_axes
        normal = axes[0].cross(axes[1])
        point = Geom.intersect_line_plane(view.pickray(x, y), [origin, normal])
        return unless point
        vector = origin.vector_to(point)
        a = vector.dot(axes[0]); b = vector.dot(axes[1])
        pa = origin.offset(axes[0], a); pb = origin.offset(axes[1], b)
        @base = [origin, pa, pa.offset(axes[1], b), pb]
        @normal = normal.normalize
      rescue ArgumentError
        @base = @normal = nil
      end

      def choose_axes(delta, view)
        list = [X_AXIS, Y_AXIS, Z_AXIS]
        return list.sort_by { |axis| -delta.dot(axis).abs }.first(2) if delta && delta.length > 0.1.mm
        n = list.max_by { |axis| view.camera.direction.dot(axis).abs }
        list.reject { |axis| axis.parallel?(n) }
      end

      def valid?
        @base && @normal && @base[0].distance(@base[1]) > 0.1.mm && @base[0].distance(@base[3]) > 0.1.mm
      end

      def vector
        v = @normal.clone
        v.reverse! if @direction < 0
        v.length = @thickness
        v
      end

      def offset_points; valid? ? @base.map { |p| p.offset(vector) } : []; end
      def size_text
        format('%.1f × %.1f × %.1f mm', @base[0].distance(@base[1]).to_mm, @base[0].distance(@base[3]).to_mm, @thickness.to_mm)
      end

      def create_board
        model = Sketchup.active_model
        model.start_operation('TRẦN TUẤN - Vẽ Ván', true)
        group = model.active_entities.add_group
        face = group.entities.add_face(@base)
        raise 'Không tạo được mặt ván.' unless face && face.valid?
        wanted = @normal.clone; wanted.reverse! if @direction < 0
        face.reverse! if face.normal.dot(wanted) < 0
        face.pushpull(@thickness)
        group.name = 'TT_VAN'
        group.set_attribute('TRẦN TUẤN NỘI THẤT', 'loai', 'VAN')
        group.set_attribute('TRẦN TUẤN NỘI THẤT', 'do_day_mm', @thickness.to_mm)
        model.commit_operation
        model.selection.clear; model.selection.add(group)
      rescue StandardError => error
        model.abort_operation if model
        UI.messagebox("Lỗi tạo ván:\n#{error.message}")
      end

      def status
        Sketchup.status_text = case @state
        when 0 then 'VẼ VÁN: Click P1. ESC để thoát.'
        when 1 then 'Kéo chéo và click P2 để khóa mặt.'
        else "#{@direction > 0 ? 'NGOÀI' : 'TRONG'} | TAB đổi hướng | Click tạo ván"
        end
      end
    end
  end
end
