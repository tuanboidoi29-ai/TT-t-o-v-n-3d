# encoding: UTF-8
module TranTuanNoiThat
  module Board
    extend self
    def activate
      mm=Float(TranTuanNoiThat.setting('thickness',17.5)) rescue 17.5
      mm=17.5 unless mm.finite? && mm>0 && mm<=1000
      Sketchup.active_model.select_tool(Tool.new(mm.mm))
    end
    def parse_thickness(text)
      s=text.to_s.strip.downcase.tr(',','.').sub(/\s*mm\z/,'')
      raise 'Nhập độ dày từ 0.1 đến 1000 mm.' unless s.match?(/\A\d+(?:\.\d*)?\z/)
      n=Float(s)
      raise 'Nhập độ dày từ 0.1 đến 1000 mm.' unless n.finite? && n.between?(0.1,1000)
      n
    end
    class Tool
      def initialize(thickness)
        @thickness=thickness;@mode=:rectangle;@snap=0;@direction=1;@typed='';@held={};@input_invalid=false
        @ip=Sketchup::InputPoint.new;@ip1=Sketchup::InputPoint.new
        @model=Sketchup.active_model;@context=@model.active_entities;@edit=@model.edit_transform
        clear_shape
      end
      def enableVCB?;true;end
      def activate;status;end
      def resume(view);status;view.invalidate;end
      def deactivate(view);view.invalidate;end
      def clear_shape
        @p1=nil;@loops=[];@triangles=[];@normal=nil;@point=nil;@lock=nil;@auto_axes=nil;@source=nil;@shift_axes=nil;@shift_direction=nil;@preview_axes=nil;@preview_point=nil
        @ip.clear;@ip1.clear
      end
      def same_context?
        Sketchup.active_model==@model && @model.active_entities==@context && @model.edit_transform.to_a==@edit.to_a
      end
      def onCancel(reason,view)
        if @p1;clear_shape;else;@model.select_tool(nil);end
        @typed='';@input_invalid=false;status;view.invalidate
      end
      def onMouseMove(flags,x,y,view)
        return unless same_context?
        @mouse=[x,y];update(view,x,y);view.invalidate
      rescue StandardError=>e
        @loops=[];@triangles=[];view.tooltip=e.message;view.invalidate
      end
      def update(view,x,y)
        @p1 ? @ip.pick(view,x,y,@ip1) : @ip.pick(view,x,y)
        hit=pick_face(view,x,y)
        if @mode==:face
          face_preview(hit,view,x,y)
        else
          @point=@ip.valid? ? snap_point(@ip.position,hit,view,x,y) : nil
          rectangle_preview(view,x,y,hit) if @p1
        end
        view.tooltip=status_text
      end
      def onLButtonDown(flags,x,y,view)
        return unless same_context?
        if @input_invalid;UI.beep;return;end
        update(view,x,y)
        if @mode==:rectangle && !@p1
          return unless @point
          @p1=@point.clone;@ip1.copy!(@ip);@typed=''
        elsif valid?
          if create_board
            clear_shape;@typed=''
          end
        else
          UI.beep
        end
        status;view.invalidate
      rescue StandardError=>e
        UI.messagebox("Không tạo được ván: #{e.message}")
      end
      def onKeyDown(key,repeat,flags,view)
        if [9,16,17,70,37,38,39,40].include?(key)
          return true if @held[key]
          @held[key]=true
          case key
          when 9
            @mode=@mode==:rectangle ? :face : :rectangle;clear_shape;@typed='';@input_invalid=false
          when 16
            if @p1 && @preview_axes && @preview_point
              delta=@preview_point-@p1
              if delta.length>0.1.mm
                @shift_axes=@preview_axes.map(&:clone)
                @shift_direction=delta.normalize
              end
            end
          when 17,70 then @direction*=-1
          when 38 then @lock=[X_AXIS,Y_AXIS] if @p1
          when 37 then @lock=[X_AXIS,Z_AXIS] if @p1
          when 39 then @lock=[Y_AXIS,Z_AXIS] if @p1
          when 40 then @lock=nil;@auto_axes=nil
          end
          update(view,*@mouse) if @mouse
          status;view.invalidate;return true
        end
        # Live numeric preview; onUserText remains the authoritative VCB commit.
        char=if key.between?(48,57);(key-48).to_s;elsif key.between?(96,105);(key-96).to_s;elsif [110,188,190].include?(key);'.';end
        if char || key==8
          @typed=key==8 ? @typed[0...-1] : @typed+char
          begin
            @thickness=Board.parse_thickness(@typed).mm;@input_invalid=false
            update(view,*@mouse) if @mouse
          rescue ArgumentError,RuntimeError
            @input_invalid=!@typed.empty?
          end
          view.invalidate
        end
        false
      end
      def onKeyUp(key,repeat,flags,view)
        @held.delete(key)
        if key==16
          @shift_axes=nil;@shift_direction=nil
          update(view,*@mouse) if @mouse
          status;view.invalidate
          return true
        end
        false
      end
      def onUserText(text,view)
        mm=Board.parse_thickness(text);@thickness=mm.mm;@typed='';@input_invalid=false
        TranTuanNoiThat.save_setting('thickness',mm)
        update(view,*@mouse) if @mouse
        status;view.invalidate
      rescue StandardError=>e
        @typed='';@input_invalid=true;UI.beep;Sketchup.status_text=e.message
      end
      def pick_face(view,x,y)
        ph=view.pick_helper;ph.do_pick(x,y)
        ph.count.times do |i|
          path=ph.path_at(i);next unless path && path.last.is_a?(Sketchup::Face)
          return {face:path.last,path:path,tr:@edit*ph.transformation_at(i)}
        end
        nil
      end
      def face_points(hit)
        hit[:face].outer_loop.vertices.map{|v|v.position.transform(hit[:tr])}
      end
      def polygon_normal(points)
        a=points.first
        (1...points.length-1).each do |i|
          n=(points[i]-a).cross(points[i+1]-a)
          return n.normalize if n.length>1e-9
        end
        nil
      end
      def snap_point(point,hit,view=nil,x=nil,y=nil)
        return point unless hit
        container=hit[:path].reverse.find{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
        return point unless container
        ents=container.definition.entities
        return point if ents.any?{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
        bounds=container.definition.bounds;lo=bounds.min.to_a;hi=bounds.max.to_a
        sizes=3.times.map do |i|
          a=lo.dup;b=lo.dup;b[i]=hi[i]
          Geom::Point3d.new(a).transform(hit[:tr]).distance(Geom::Point3d.new(b).transform(hit[:tr]))
        end
        axis=(0..2).min_by{|i|sizes[i]}
        return point unless sizes[axis]>0 && sizes[axis]<=100.mm && sizes[axis]<sizes.max*0.4
        p=point.transform(hit[:tr].inverse).to_a
        candidates=[lo[axis],(lo[axis]+hi[axis])/2,hi[axis]].map do |value|
          q=p.dup;q[axis]=value
          Geom::Point3d.new(q).transform(hit[:tr])
        end
        distances=candidates.map do |q|
          if view && x && y
            screen=view.screen_coords(q)
            Math.sqrt((screen.x-x)**2+(screen.y-y)**2)
          else
            q.distance(point)
          end
        end
        index=(0..2).min_by{|i|distances[i]}
        return point if view && distances[index]>14
        @snap=index
        candidates[index]
      end
      def face_preview(hit,view,x,y)
        @loops=[];@triangles=[];@normal=nil
        return unless hit
        @source=hit[:face]
        raise 'Face quá nhiều cạnh; chọn mặt đơn giản hơn.' if @source.edges.length>5000
        @loops=[@source.outer_loop]+@source.loops.reject{|l|l==@source.outer_loop}
        @loops=@loops.map{|loop|loop.vertices.map{|v|v.position.transform(hit[:tr])}}
        @normal=polygon_normal(@loops.first);return unless @normal
        @normal.reverse! if @normal.dot(view.pickray(x,y)[1])>0
        mesh=@source.mesh
        @triangles=mesh.polygons.flat_map do |poly|
          p=poly.map{|i|mesh.point_at(i.abs).transform(hit[:tr])}
          (1...p.length-1).flat_map{|i|[p[0],p[i],p[i+1]]}
        end
      end
      def axes_at_p2(hit,delta,view)
        return @shift_axes if @shift_axes
        return @lock if @lock
        if hit
          normal=polygon_normal(face_points(hit))
          if normal
            edge=face_points(hit).each_cons(2).map{|a,b|b-a}.max_by(&:length)
            if edge && edge.length>1e-8
              u=edge.normalize;return [u,normal.cross(u).normalize]
            end
          end
        end
        axes=[X_AXIS,Y_AXIS,Z_AXIS]
        scores=[[X_AXIS,Y_AXIS],[X_AXIS,Z_AXIS],[Y_AXIS,Z_AXIS]].map{|pair|[pair,pair.sum{|a|delta.dot(a).abs}]}
        best=scores.max_by(&:last)
        if best[1]>0.1.mm
          old=scores.find{|p,s|p==@auto_axes}
          @auto_axes=old && old[1]>=best[1]*0.85 ? old[0] : best[0]
        else
          n=axes.max_by{|a|view.camera.direction.dot(a).abs};@auto_axes=axes.reject{|a|a==n}
        end
        @auto_axes
      end
      def rectangle_preview(view,x,y,hit)
        @loops=[];@triangles=[];@normal=nil
        delta=@point ? @point-@p1 : Geom::Vector3d.new(0,0,0)
        u,v=axes_at_p2(hit,delta,view);@preview_axes=[u,v];n=u.cross(v).normalize
        point=@point || Geom.intersect_line_plane(view.pickray(x,y),[@p1,n]);return unless point
        point=constrained_point(point)
        d=point-@p1;a=d.dot(u);b=d.dot(v)
        @preview_point=@p1.offset(u,a).offset(v,b)
        return if a.abs<0.1.mm || b.abs<0.1.mm
        p=@p1.offset(u,a);q=p.offset(v,b);r=@p1.offset(v,b)
        @loops=[[@p1,p,q,r]];@normal=n
        @triangles=[@p1,p,q,@p1,q,r]
      end
      def constrained_point(point)
        return point unless @shift_direction && @p1
        @p1.offset(@shift_direction,(point-@p1).dot(@shift_direction))
      end
      def valid?;@normal && !@loops.empty? && @loops.first.length>=3;end
      def displacement;@normal.clone.tap{|v|v.reverse! if @direction<0};end
      def base_shift;0.0;end
      def shifted(p,top=false);p.offset(displacement,base_shift+(top ? @thickness : 0));end
      def draw(view)
        @ip.draw(view) if @mode==:rectangle && @ip.display?
        if @mode==:rectangle && @point
          view.draw_points([@point],9,2,Sketchup::Color.new(32,151,204))
        end
        return unless valid?
        view.drawing_color=Sketchup::Color.new(255,179,200,100)
        [false,true].each{|top|view.draw(GL_TRIANGLES,@triangles.map{|p|shifted(p,top)})} unless @triangles.empty?
        @loops.each do |loop|
          low=loop.map{|p|shifted(p)};high=loop.map{|p|shifted(p,true)}
          view.drawing_color=Sketchup::Color.new(245,132,164,80)
          view.draw(GL_QUADS,low.each_index.flat_map{|i|j=(i+1)%low.length;[low[i],low[j],high[j],high[i]]})
          view.drawing_color=Sketchup::Color.new(193,67,109);view.line_width=2
          view.draw(GL_LINE_LOOP,low);view.draw(GL_LINE_LOOP,high)
          view.draw(GL_LINES,low.each_index.flat_map{|i|[low[i],high[i]]})
        end
      end
      def getExtents
        box=Geom::BoundingBox.new
        @loops.flatten.each{|p|box.add(shifted(p),shifted(p,true))} if valid?
        box
      end
      def create_board
        return false unless same_context? && valid?
        @model.start_operation('TRẦN TUẤN - Vẽ Ván',true)
        begin
          group=@context.add_group
          # World-space shell first: thickness stays physical under scaled edit contexts.
          cap=group.entities.add_face(@loops.first.map{|p|shifted(p)})
          raise 'Không tạo được mặt ván.' unless cap && cap.valid?
          @loops.drop(1).each do |hole|
            inner=group.entities.add_face(hole.map{|p|shifted(p)})
            raise 'Không tạo được lỗ trên mặt ván.' unless inner && inner.valid?
            inner.erase!
          end
          cap=group.entities.grep(Sketchup::Face).max_by(&:area) unless cap.valid?
          raise 'Không còn mặt ván hợp lệ.' unless cap && cap.valid?
          cap.reverse! if cap.normal.dot(displacement)<0
          cap.pushpull(@thickness)
          raise 'Ván chưa kín; đã hủy lượt tạo.' unless group.manifold?
          group.transformation=@edit.inverse
          group.name='TT_VAN'
          group.set_attribute('TRẦN TUẤN NỘI THẤT','loai','VAN')
          group.set_attribute('TRẦN TUẤN NỘI THẤT','do_day_mm',@thickness.to_mm)
          @model.commit_operation
          @model.selection.clear;@model.selection.add(group)
          TranTuanNoiThat.save_setting('thickness',@thickness.to_mm)
          true
        rescue StandardError=>e
          @model.abort_operation;UI.messagebox("Lỗi tạo ván: #{e.message}");false
        end
      end
      def status_text
        mode=@mode==:face ? 'THEO FACE: Rê mặt → click tạo' : (@p1 ? 'P2: Rê chọn hướng → click tạo' : 'P1: Click điểm đầu')
        "#{mode} | Dày #{@thickness.to_mm.round(2)} mm | Tự bắt mép/tâm/mép | Giữ SHIFT khóa hướng kéo P1–P2 | TAB đổi chế độ | Nhập số + Enter đổi dày | CTRL: #{@direction > 0 ? 'VÁN NGOÀI' : 'VÁN TRONG'}"
      end
      def status
        Sketchup.status_text=status_text;Sketchup.vcb_label='Độ dày (mm)';Sketchup.vcb_value=@thickness.to_mm.round(2).to_s
      end
    end
  end
end
