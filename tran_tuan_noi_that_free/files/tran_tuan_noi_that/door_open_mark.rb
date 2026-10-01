# encoding: UTF-8
module TranTuanNoiThat
  module DoorOpenMark
    extend self
    DICT = 'TT_DOOR_OPEN_MARK'.freeze unless const_defined?(:DICT, false)
    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end
    def container?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end
    def dashes(a, b, count = 20)
      (0...count).map do |i|
        [Geom.linear_combination(1.0-i.to_f/count,a,i.to_f/count,b),
         Geom.linear_combination(1.0-(i+0.60)/count,a,(i+0.60)/count,b)]
      end
    end
    def center_zone?(u, v)
      u >= 0.30 && u <= 0.70 && v >= 0.30 && v <= 0.70
    end
    def mark_segments(points, mids, side, cross)
      if cross
        [[points[0], points[2]], [points[1], points[3]]].flat_map { |a,b| dashes(a,b) }
      else
        [points[(side+2)%4], points[(side+3)%4]].flat_map { |p| dashes(mids[side],p) }
      end
    end
    class Tool
      def activate
        @model = Sketchup.active_model
        Sketchup.set_status_text('HƯỚNG MỞ CÁNH: giữa tấm: X · gần cạnh bản lề: V · Click tạo dấu nét đứt · ESC thoát', SB_PROMPT)
      end
      def deactivate(view); view.invalidate; end
      def onCancel(reason, view); @model.select_tool(nil); end
      def onMouseMove(flags,x,y,view)
        @segments = nil
        ph = view.pick_helper
        ph.do_pick(x,y)
        ph.count.times do |i|
          path = ph.path_at(i)
          face = path && path.last
          next unless face.is_a?(Sketchup::Face)
          next unless face.outer_loop.vertices.length == 4 && face.loops.length == 1
          parents = (@model.active_path || []) + path.select { |e| DoorOpenMark.container?(e) }
          next if parents.empty? || parents.any? { |e| e.locked? || e.get_attribute(DICT,'marker',false) }
          points = face.outer_loop.vertices.map(&:position)
          # Rectangular planar doors only; do not draw outside irregular panels.
          sides = (0..3).map { |j| points[(j+1)%4] - points[j] }
          next unless (0..3).all? { |j| sides[j].length > 0.001 && sides[j].dot(sides[(j+1)%4]).abs / (sides[j].length*sides[(j+1)%4].length) < 0.001 }
          tr = @model.edit_transform * ph.transformation_at(i)
          center = Geom.linear_combination(0.5,points[0],0.5,points[2])
          inset = points.map { |p| Geom.linear_combination(0.92,p,0.08,center) }
          mids = (0..3).map { |j| Geom.linear_combination(0.5,inset[j],0.5,inset[(j+1)%4]) }
          side = (0..3).min_by do |j|
            screen = view.screen_coords(mids[j].transform(tr))
            (screen.x-x)**2+(screen.y-y)**2
          end
          ray = view.pickray(x,y)
          inverse = tr.inverse
          hit = Geom.intersect_line_plane([ray[0].transform(inverse), ray[1].transform(inverse)], face.plane)
          next unless hit
          u_axis, v_axis = points[1]-points[0], points[3]-points[0]
          delta = hit-points[0]
          u = delta.dot(u_axis) / u_axis.dot(u_axis)
          v = delta.dot(v_axis) / v_axis.dot(v_axis)
          @cross = DoorOpenMark.center_zone?(u,v)
          @local_segments = DoorOpenMark.mark_segments(inset,mids,side,@cross)
          @segments = @local_segments.map { |pair| pair.map { |p| p.transform(tr) } }
          @parents, @face_points = parents, points
          @face_key = points.map { |p| p.to_a.map { |n| n.round(7) } }.sort.inspect
          break
        end
        view.invalidate
      rescue StandardError => e
        @segments=nil
        Sketchup.set_status_text("Hướng mở: #{e.message}", SB_PROMPT)
      end
      def draw(view)
        return unless @segments
        view.drawing_color = Sketchup::Color.new(235,100,20)
        view.line_width = 3
        view.draw(GL_LINES,@segments.flatten(1))
      end
      def signature(e)
        [e.definition, e.transformation.to_a, e.name]
      end
      def onLButtonDown(flags,x,y,view)
        onMouseMove(flags,x,y,view)
        return UI.beep unless @segments
        started=false
        # Resolve each descendant again after copying a shared ancestor.
        steps = @parents.each_cons(2).map do |parent,child|
          sig=signature(child)
          matches=parent.definition.entities.select { |e| DoorOpenMark.container?(e) && signature(e)==sig }
          [sig,matches.index(child)]
        end
        @model.start_operation('TRẦN TUẤN - Đánh dấu hướng mở cánh',true)
        started=true
        target=@parents.first
        @parents.length.times do |i|
          target.make_unique
          if i < steps.length
            sig,ordinal=steps[i]
            matches=target.definition.entities.select { |e| DoorOpenMark.container?(e) && signature(e)==sig }
            target=matches[ordinal]
            raise 'Không xác định được cánh sau khi tách bản sao.' unless target
          end
        end
        es=target.definition.entities
        old=es.grep(Sketchup::Group).select { |g| g.get_attribute(DICT,'face_key','')==@face_key }
        es.erase_entities(old) unless old.empty?
        marker=es.add_group
        marker.name = @cross ? 'Hướng mở - X nét đứt' : 'Hướng mở cánh - đỉnh phía bản lề'
        marker.set_attribute(DICT,'kind',@cross ? 'X' : 'V')
        marker.set_attribute(DICT,'marker',true)
        marker.set_attribute(DICT,'face_key',@face_key)
        marker.layer=@model.layers.add('TT_HUONG_MO_CANH')
        @local_segments.each { |a,b| marker.entities.add_line(a,b) }
        @model.commit_operation
        started=false
        @segments=nil
        view.invalidate
      rescue StandardError => e
        @model.abort_operation if started
        UI.messagebox("Không tạo được hướng mở cánh: #{e.message}")
      end
    end
  end
end
