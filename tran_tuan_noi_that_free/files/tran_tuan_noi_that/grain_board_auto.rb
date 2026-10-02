# encoding: UTF-8
# Physical face frames, fixed sheet UV, independent boards in shared containers.
module TranTuanNoiThat
  module GrainBoardAuto
    extend self
    DICT = 'TT_GRAIN_BOARD_AUTO'.freeze unless const_defined?(:DICT, false)
    def sub(a,b); a.zip(b).map { |x,y| x-y }; end
    def dot(a,b); a.zip(b).sum { |x,y| x*y }; end
    def cross(a,b); [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]; end
    def norm(a); Math.sqrt(dot(a,a)); end
    def unit(a); n=norm(a); raise 'Mặt ván suy biến.' if n<1e-9; a.map { |x| x/n }; end
    def offset(p,v,d); p.zip(v).map { |x,y| x+y*d }; end
    def span(points,axis); values=points.map { |p| dot(p,axis) }; values.max-values.min; end
    def canonical(v)
      index=v[2].abs>0.5 ? 2 : (0..2).max_by { |i| v[i].abs }
      v[index]<0 ? v.map { |x| -x } : v
    end

    # Fit the whole outline, not the shortest edge or the container bounds.
    def frame(points)
      return nil if points.length<3
      edges=points.each_with_index.map { |p,i| sub(points[(i+1)%points.length],p) }
      longest=edges.max_by { |v| norm(v) }
      return nil if norm(longest)<1e-8
      other=edges.max_by { |v| norm(cross(longest,v)) }
      return nil if norm(cross(longest,other))<1e-8
      normal=unit(cross(longest,other))
      candidates=edges.select { |v| norm(v)>=norm(longest)*0.2 }.map do |v|
        u=unit(v); w=unit(cross(normal,u)); a=span(points,u); b=span(points,w)
        g,c,l,s=a>=b ? [u,w,a,b] : [w,u,b,a]
        {g:canonical(g), c:canonical(c), n:normal, length:l, width:s, area:a*b}
      end
      best=candidates.min_by { |f| [f[:area].round(7),-f[:g][2].abs] }
      # Upright boards use model Z even when the horizontal span is longer.
      # Horizontal/inclined boards keep the fitted longest outline direction.
      if normal[2].abs <= 0.0174524064
        up=unit(sub([0.0,0.0,1.0],normal.map { |v| v*normal[2] }))
        across=canonical(unit(cross(normal,up)))
        best=best.merge(g:up,c:across,length:span(points,up),width:span(points,across))
      end
      best[:origin]=points.first
      best
    end

    def texture_axis(texture)
      texture.image_height.to_i>texture.image_width.to_i ? :v : :u
    end

    def uv_mapping(frame,texture,tr,quarter_turn=false)
      g,c=quarter_turn ? [frame[:c],frame[:g]] : [frame[:g],frame[:c]]
      # UV is normalized 0..1. World-space references keep scale and shear
      # of Group/Component from stretching the physical 1220 x 2440 sheet.
      u,v,du,dv=texture_axis(texture)==:v ? [c,g,1220.0/25.4,2440.0/25.4] : [g,c,2440.0/25.4,1220.0/25.4]
      inv=tr.inverse
      p=frame[:origin]
      [Geom::Point3d.new(*p).transform(inv),Geom::Point3d.new(0,0,0),
       Geom::Point3d.new(*offset(p,u,du)).transform(inv),Geom::Point3d.new(1,0,0),
       Geom::Point3d.new(*offset(p,v,dv)).transform(inv),Geom::Point3d.new(0,1,0)]
    end

    def container?(e); e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance); end
    def entities(e); e.definition.entities; end
    def locked?(e)
      e.locked? || e.get_attribute('TT_GRAIN','locked',false)==true ||
        e.get_attribute('TT_ABF_GRAIN','grain_locked',false)==true
    end
    def points(face,tr); face.outer_loop.vertices.map { |v| v.position.transform(tr).to_a }; end
    def textured?(m); m && m.texture; end

    def components(faces)
      remaining=faces.to_h { |f| [f,true] }; result=[]
      until remaining.empty?
        pending=[remaining.keys.first]; group=[]
        until pending.empty?
          face=pending.pop
          next unless remaining.delete(face)
          group << face
          face.edges.each { |edge| edge.faces.each { |f| pending << f if remaining.key?(f) } }
        end
        result << group
      end
      result
    end

    def face_plans(es,tr,inherited,max_thickness)
      components(es.grep(Sketchup::Face)).flat_map do |faces|
        frames=faces.to_h { |f| [f,frame(points(f,tr))] }.reject { |_f,a| a.nil? }
        next [] if frames.empty?
        principal=frames.max_by { |f,_a| f.area(tr).to_f }[1]
        all_points=frames.keys.flat_map { |f| points(f,tr) }
        depth=span(all_points,principal[:n])*25.4
        single_board=depth<=max_thickness && depth<=principal[:width]*25.4*0.35
        frames.filter_map do |face,own|
          next if single_board && dot(own[:n],principal[:n]).abs<0.999999
          basis=single_board ? principal : own
          # A point on this face prevents projection onto the opposite side.
          basis=basis.merge(origin:points(face,tr).first)
          mats=[[true,face.material || inherited],[false,face.back_material || inherited]].select { |_front,m| textured?(m) }
          next if mats.empty?
          {face:face,frame:basis,tr:tr,materials:mats}
        end
      end
    end

    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end

    class Tool
      include GrainBoardAuto
      def initialize
        @model=Sketchup.active_model; @manual=false; @down={}; @preview=[]; @batch=nil
        @max_thickness=80.0
      end
      def activate; status; end
      def deactivate(view); @down.clear; view.invalidate; end
      def resume(view); @down.clear; status; view.invalidate; end
      def status(message=nil)
        Sketchup.set_status_text(message || "XOAY VÂN · #{@manual ? 'THỦ CÔNG: click xoay 90°' : 'TỰ ĐỘNG: click căn từng tấm'} · TAB đổi chế độ · A quét vùng chọn/tất cả · ENTER áp dụng · UV 1220 × 2440 mm",SB_PROMPT)
      end
      def onKeyDown(key,repeat,_flags,view)
        return false unless [9,65,13].include?(key)
        return true if @down[key]
        @down[key]=true
        case key
        when 9
          @manual=!@manual; @batch=nil; @hover=nil; @preview=[]; status
        when 65
          scan(view)
        when 13
          if @batch && !@batch_context.equal?(@model.active_entities)
            @batch=nil; @preview=[]; status('Phạm vi đã đổi. Bấm A để quét lại.')
          else
            apply(@batch,view) if @batch
          end
        end
        view.invalidate
        true
      end
      def onKeyUp(key,_repeat,_flags,_view); @down.delete(key); [9,65,13].include?(key); end
      def getMenu(menu)
        menu.add_item('Quét vùng chọn / tất cả trong model đang mở') { scan(@model.active_view) }
        menu.add_item('Tự động xoay vân toàn model') do
          @manual=false
          apply(@model.entities.to_a.select { |e| container?(e) },@model.active_view,Geom::Transformation.new)
        end
      end
      def onCancel(_reason,view)
        if @batch
          @batch=nil; @preview=[]; status; view.invalidate
        else
          @model.select_tool(nil)
        end
      end
      def scope
        selected=@model.selection.to_a.select { |e| container?(e) }
        selected.empty? ? @model.active_entities.to_a.select { |e| container?(e) } : selected
      end
      def inherited_context
        (@model.active_path || []).reverse_each do |e|
          return e.material if e.material
        end
        nil
      end
      def scan(view)
        @batch=scope; @batch_context=@model.active_entities; @preview=[]
        @batch.each { |e| walk(e,@model.edit_transform,inherited_context,false) { |p| @preview << p } }
        status("Đã quét #{@preview.length} mặt có texture · ENTER áp dụng · ESC hủy · TAB đổi chế độ")
        view.invalidate
      rescue StandardError=>e
        @batch=nil; @preview=[]; status("Không quét được: #{e.message}")
      end
      def pick(view,x,y)
        ph=view.pick_helper; ph.do_pick(x,y)
        ph.count.times do |i|
          path=ph.path_at(i)
          root=path && path.find { |e| container?(e) && @model.active_entities.include?(e) }
          return root if root
        end
        nil
      end
      def onMouseMove(_flags,x,y,view)
        return if @batch
        root=pick(view,x,y)
        return if root==@hover
        @hover=root; @preview=[]
        walk(root,@model.edit_transform,inherited_context,false) { |p| @preview << p } if root
        view.invalidate
      rescue StandardError=>e
        @preview=[]; status(e.message)
      end
      def onLButtonDown(flags,x,y,view)
        return if @batch
        root=pick(view,x,y)
        return unless root
        mask=defined?(COPY_MODIFIER_MASK) ? COPY_MODIFIER_MASK : 2
        if (flags & mask)!=0
          toggle_lock(root,view)
        else
          apply([root],view)
        end
      end
      def toggle_lock(root,view)
        return if root.locked?
        was_locked=locked?(root)
        @model.start_operation('TRẦN TUẤN - Khóa hướng vân',true)
        begin
          root.set_attribute('TT_GRAIN','locked',!was_locked)
          root.set_attribute('TT_ABF_GRAIN','grain_locked',!was_locked)
          @model.commit_operation
        rescue StandardError
          @model.abort_operation
          raise
        end
        @hover=nil; @preview=[]
        status(was_locked ? 'Đã mở khóa vân.' : 'Đã khóa vân. Ctrl+Click để mở khóa.')
        view.invalidate
      end
      def preview_turn(face)
        @manual ? !face.get_attribute(DICT,'quarter_turn',false) : false
      end
      def walk(root,parent,inherited,mutate,&block)
        return unless root && root.valid? && container?(root)
        return if locked?(root)
        # Re-fetch descendants after uniquing to protect other instances.
        root.make_unique if mutate
        tr=parent*root.transformation
        material=root.material || inherited
        es=entities(root)
        face_plans(es,tr,material,@max_thickness).each(&block)
        es.to_a.each { |e| walk(e,tr,material,mutate,&block) if container?(e) }
      end
      def apply(roots,view,parent=nil)
        return if @busy || !roots || roots.empty?
        @busy=true; started=false; count=0
        @model.start_operation('TRẦN TUẤN - Xoay vân từng tấm',true); started=true
        roots.each do |root|
          walk(root,parent || @model.edit_transform,parent ? nil : inherited_context,true) do |plan|
            face=plan[:face]
            turn=preview_turn(face)
            plan[:materials].each do |front,material|
              face.clear_texture_projection(front) if face.respond_to?(:texture_projected?) && face.texture_projected?(front)
              mapped=face.position_material(material,uv_mapping(plan[:frame],material.texture,plan[:tr],turn),front)
              raise 'SketchUp không nhận tọa độ UV.' unless mapped
            end
            face.set_attribute(DICT,'quarter_turn',turn)
            face.set_attribute(DICT,'sheet_mm','1220x2440')
            face.set_attribute(DICT,'grain_world',turn ? plan[:frame][:c] : plan[:frame][:g])
            count+=1
          end
        end
        count>0 ? @model.commit_operation : @model.abort_operation
        started=false
        @batch=nil; @preview=[]; @hover=nil
        status(count>0 ? "Đã căn #{count} mặt · UV 1220 × 2440 mm · TAB đổi Tự động / Thủ công" : 'Không có mặt texture hợp lệ; kiểm tra vật liệu hoặc khóa vân.')
      rescue StandardError=>e
        @model.abort_operation if started
        status("Đã hủy lượt xoay vân: #{e.message}")
      ensure
        @busy=false; view.invalidate
      end
      def draw(view)
        view.draw_text(Geom::Point3d.new(20,25,0),@manual ? 'THỦ CÔNG · Click xoay 90°' : 'TỰ ĐỘNG · Ván đứng: vân đứng · Ván nằm: theo chiều dài',size:17,bold:true)
        view.drawing_color=Sketchup::Color.new(255,150,50)
        view.line_width=3
        @preview.each do |plan|
          f=plan[:frame]; g=preview_turn(plan[:face]) ? f[:c] : f[:g]
          p=points(plan[:face],plan[:tr]); center=3.times.map { |i| p.sum { |v| v[i] }/p.length }
          d=[f[:length],f[:width]].min*0.3
          a=offset(center,g,-d); b=offset(center,g,d)
          side=unit(cross(f[:n],g)); back=offset(b,g,-d*0.3)
          view.draw(GL_LINES,[a,b,b,offset(back,side,d*0.15),b,offset(back,side,-d*0.15)].map { |v| Geom::Point3d.new(*v) })
        end
      end
    end
  end
  module Grain
    def self.activate; GrainBoardAuto.activate; end
  end
end
