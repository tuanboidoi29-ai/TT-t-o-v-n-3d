# encoding: UTF-8
module TranTuanNoiThat
  module CutBlock
    extend self
    def container?(e); e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance); end
    def validate!(target,context)
      raise 'Chọn một Group/Component khối kín trong cấp đang mở.' unless target && target.valid? && container?(target) && context.include?(target)
      raise 'Khối đang bị khóa.' if target.locked?
      raise 'Khối chưa kín. Hãy sửa mặt hở trước khi cắt.' unless target.manifold?
      raise 'Mở Group cha rồi chọn khối con cần cắt.' if target.definition.entities.any? { |e| container?(e) }
    end
    def basis(normal)
      n=normal.normalize
      seed=n.z.abs<0.9 ? Geom::Vector3d.new(0,0,1) : Geom::Vector3d.new(1,0,0)
      u=n.cross(seed).normalize
      [u,n.cross(u).normalize,n]
    end
    def corners(target,world)
      b=target.definition.bounds
      (0..7).map { |i| b.corner(i).transform(world) }
    end
    def plane_data(points,point,normal)
      u,v,n=basis(normal)
      center=Geom::Point3d.new(*3.times.map { |i| points.sum { |p| p.to_a[i] }/points.length })
      center=center.offset(n,(point-center).dot(n))
      radii=points.map { |p| (p-center).length }
      extent=[radii.max*1.5,1.0].max
      distances=points.map { |p| (p-point).dot(n) }
      {center:center,u:u,v:v,n:n,extent:extent,min:distances.min,max:distances.max}
    end
    def quad(data,distance=0.0)
      c=data[:center].offset(data[:n],distance);r=data[:extent]
      [[-1,-1],[1,-1],[1,1],[-1,1]].map { |x,y| c.offset(data[:u],x*r).offset(data[:v],y*r) }
    end
    def cutter(es,data,inverse,positive)
      lo,hi=positive ? [0.0,data[:extent]] : [-data[:extent],0.0]
      pts=(quad(data,lo)+quad(data,hi)).map { |p| p.transform(inverse) }
      center=Geom::Point3d.new(*3.times.map { |i| pts.sum { |p| p.to_a[i] }/8.0 })
      group=es.add_group
      [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each do |indices|
        face=group.entities.add_face(indices.map { |i| pts[i] })
        raise 'Không tạo được khối cắt.' unless face
        face.reverse! if face.normal.dot(face.vertices.first.position-center)<0
      end
      raise 'Khối cắt chưa kín.' unless group.manifold?
      group
    end
    def copy_solid(es,target)
      g=es.add_group
      g.entities.add_instance(target.definition,Geom::Transformation.new).explode
      raise 'Bản sao hình học không kín.' unless g.manifold?
      g
    end
    def perform(model,target,point,normal,mode)
      raise 'Cắt khối cần SketchUp Pro có Solid Tools.' if Sketchup.respond_to?(:is_pro?) && !Sketchup.is_pro?
      context=model.active_entities
      validate!(target,context)
      world=model.edit_transform*target.transformation
      data=plane_data(corners(target,world),point,normal)
      tolerance=0.001/25.4
      raise 'Mặt phẳng phải nằm bên trong khối, không nằm ngoài hoặc trùng mép.' unless data[:min]<-tolerance && data[:max]>tolerance
      raise 'Chế độ giữ phần không hợp lệ.' unless [:both,:positive,:negative].include?(mode)
      started=false
      model.start_operation('TRẦN TUẤN - Cắt khối',true);started=true
      work=context.add_group;es=work.entities
      results=[true,false].map do |positive|
        source=copy_solid(es,target)
        raise 'Cắt khối cần SketchUp Pro có Solid Tools.' unless source.respond_to?(:intersect)
        clip=cutter(es,data,world.inverse,positive)
        result=source.intersect(clip)
        raise 'Không cắt được khối kín. Khối gốc được giữ nguyên.' unless result && result.valid? && result.manifold? && result.volume.abs>1e-9
        result
      end
      original=copy_solid(es,target).volume.abs
      total=results.sum { |r| r.volume.abs }
      raise 'Thể tích sau cắt không khớp; đã hủy để giữ khối gốc.' if (total-original).abs>[original*1e-5,1e-7].max
      keep=mode==:both ? [0,1] : [mode==:positive ? 0 : 1]
      made=keep.map do |index|
        result=results[index]
        group=context.add_group
        group.entities.add_instance(result.definition,result.transformation).explode
        group.transformation=target.transformation
        group.material=target.material
        group.layer=target.layer
        name=target.name.to_s.strip
        name=target.definition.name.to_s if name.empty?
        name='Khối' if name.empty?
        group.name="#{name} — Cắt #{index==0 ? '+' : '-'}"
        if target.attribute_dictionaries
          target.attribute_dictionaries.each { |dict| dict.each_pair { |k,v| group.set_attribute(dict.name,k,v) } }
        end
        group.casts_shadows=target.casts_shadows? if group.respond_to?(:casts_shadows=)
        group.receives_shadows=target.receives_shadows? if group.respond_to?(:receives_shadows=)
        raise 'Phần cắt chưa kín; đã hủy.' unless group.manifold?
        group
      end
      work.erase!
      target.erase!
      model.selection.clear
      made.each { |g| model.selection.add(g) }
      model.commit_operation;started=false
      made
    rescue StandardError, NotImplementedError => error
      model.abort_operation if started
      raise RuntimeError, 'Phiên bản SketchUp này không hỗ trợ cắt khối Solid Tools.' if error.is_a?(NotImplementedError)
      raise
    end
    def activate; Sketchup.active_model.select_tool(Tool.new); end

    class Tool
      def activate
        @model=Sketchup.active_model;@context=@model.active_entities
        @target=nil;@normal=Geom::Vector3d.new(0,0,1);@mode=:both;@down={};@placed=false
        @ip=Sketchup::InputPoint.new
        selected=@model.selection.to_a.select { |e| CutBlock.container?(e) }
        select_target(selected.first) if selected.length==1
        status
      rescue StandardError=>e
        @target=nil;status(e.message)
      end
      def status(message=nil)
        label={both:'Giữ hai phần',positive:'Giữ phía +',negative:'Giữ phía -'}[@mode]
        Sketchup.set_status_text(message || "CẮT KHỐI · #{@target ? 'Rê điểm, click giữ mặt cắt; ENTER cắt' : 'Click chọn khối kín'} · ↑ Z / → X / ← Y · TAB: #{label} · Nhập mm từ tâm",SB_PROMPT)
      end
      def select_target(target)
        CutBlock.validate!(target,@context)
        @target=target;@world=@model.edit_transform*target.transformation
        @points=CutBlock.corners(target,@world)
        @center=target.definition.bounds.center.transform(@world)
        @point=@center;@placed=false
        @model.selection.clear;@model.selection.add(target)
      end
      def pick(view,x,y)
        ph=view.pick_helper;ph.do_pick(x,y)
        ph.count.times do |i|
          path=ph.path_at(i)
          e=path && path.find { |item| CutBlock.container?(item) && @context.include?(item) }
          return e if e
        end
        nil
      end
      def onMouseMove(_flags,x,y,view)
        return unless @target && !@placed
        @ip.pick(view,x,y)
        @point=@ip.position if @ip.valid?
        view.invalidate
      end
      def onLButtonDown(_flags,x,y,view)
        if @target
          @ip.pick(view,x,y)
          @point=@ip.position if @ip.valid?
          @placed=true
        else
          select_target(pick(view,x,y))
        end
        status;view.invalidate
      rescue StandardError=>e
        status(e.message)
      end
      def enableVCB?;true;end
      def onUserText(text,view)
        raise 'Chọn khối trước khi nhập vị trí cắt.' unless @target
        value=Float(text.strip.tr(',','.'))
        raise 'Khoảng cách không hợp lệ.' unless value.finite?
        @point=@center.offset(@normal,value/25.4);@placed=true
        status("Mặt cắt cách tâm #{value} mm · ENTER để cắt");view.invalidate
      rescue StandardError=>e
        status(e.message)
      end
      def settings(view)
        labels=['Giữ cả hai phần','Giữ phía +','Giữ phía -'];modes=[:both,:positive,:negative]
        values=UI.inputbox(['Phần giữ lại'],[labels[modes.index(@mode)]],[labels.join('|')],'Cắt khối')
        @mode=modes[labels.index(values[0])] if values && labels.include?(values[0])
        @down.clear;status;view.invalidate
      end
      def onKeyDown(key,_repeat,_flags,view)
        return false unless [9,13,37,38,39,88,89,90].include?(key)
        return true if @down[key]
        @down[key]=true
        case key
        when 9 then settings(view)
        when 13
          return true unless @target
          raise 'Cấp chỉnh sửa đã đổi. Thoát công cụ và chọn lại khối.' unless @context==@model.active_entities
          CutBlock.perform(@model,@target,@point,@normal,@mode)
          @target=nil;@placed=false;UI.beep;status('Đã cắt khối. Click khối khác để tiếp tục. Ctrl+Z hoàn tác.')
        else
          axis=([39,88].include?(key) ? 0 : ([37,89].include?(key) ? 1 : 2))
          @normal=Geom::Vector3d.new(*3.times.map { |i| i==axis ? 1 : 0 });status
        end
        view.invalidate;true
      rescue StandardError=>e
        status(e.message);UI.beep;true
      end
      def onKeyUp(key,*);@down.delete(key);end
      def onCancel(_reason,view)
        if @placed
          @placed=false;status
        elsif @target
          @target=nil;status
        else
          @model.select_tool(nil)
        end
        view.invalidate
      end
      def resume(view);@down.clear;status;view.invalidate;end
      def deactivate(view);view.invalidate;end
      def getMenu(menu)
        menu.add_item('Cài đặt phần giữ lại') { settings(@model.active_view) }
      end
      def draw(view)
        return unless @target && @target.valid?
        data=CutBlock.plane_data(@points,@point,@normal)
        polygon=CutBlock.quad(data)
        view.drawing_color=Sketchup::Color.new(255,160,70,65)
        view.draw(GL_QUADS,polygon)
        view.drawing_color=Sketchup::Color.new(240,120,20)
        view.line_width=2;view.line_stipple='-'
        view.draw(GL_LINE_LOOP,polygon)
        view.line_stipple=''
        @ip.draw(view) if @ip.valid? && !@placed
      end
    end
  end
end
