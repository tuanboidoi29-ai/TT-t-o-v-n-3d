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
    # Dissolve only new boolean seams between coplanar faces.
    # Original edges, material boundaries and non-coplanar edges remain.
    def cleanup_cut_seams(entities, original_segments)
      tolerance=0.001.mm
      entities.grep(Sketchup::Edge).each do |edge|
        next unless edge.valid? && edge.faces.length==2
        next if edge.attribute_dictionaries && edge.attribute_dictionaries.length>0
        a,b=edge.faces
        next unless a.valid? && b.valid?
        next unless a.material==b.material && a.back_material==b.back_material
        next unless a.normal.parallel?(b.normal)
        next unless b.vertices.all? { |v| v.position.distance_to_plane(a.plane).abs<=tolerance }
        ends=[edge.start.position,edge.end.position]
        original=original_segments.any? do |p,q|
          axis=q-p;len=axis.length
          next false if len<=tolerance
          axis.normalize!
          ends.all? do |v|
            delta=v-p;distance=delta.dot(axis)
            delta.cross(axis).length<=tolerance && distance>=-tolerance && distance<=len+tolerance
          end
        end
        edge.erase! unless original
      end
    end

    def perform(model,target,point,normal,mode,operation=true,context_override=nil,parent_world=nil)
      raise 'Cắt khối cần SketchUp Pro có Solid Tools.' if Sketchup.respond_to?(:is_pro?) && !Sketchup.is_pro?
      context=context_override || model.active_entities
      validate!(target,context)
      world=(parent_world || model.edit_transform)*target.transformation
      data=plane_data(corners(target,world),point,normal)
      tolerance=0.001/25.4
      raise 'Mặt phẳng phải nằm bên trong khối, không nằm ngoài hoặc trùng mép.' unless data[:min]<-tolerance && data[:max]>tolerance
      raise 'Chế độ giữ phần không hợp lệ.' unless [:both,:positive,:negative].include?(mode)
      started=false
      if operation
        model.start_operation('TRẦN TUẤN - Cắt khối',true);started=true
      end
      original_segments=target.definition.entities.grep(Sketchup::Edge).map { |e| [e.start.position,e.end.position] }
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
        cleanup_cut_seams(group.entities,original_segments)
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
      if operation
        model.selection.clear
        made.each { |g| model.selection.add(g) }
      end
      model.commit_operation if operation
      started=false
      made
    rescue StandardError, NotImplementedError => error
      model.abort_operation if started
      raise RuntimeError, 'Phiên bản SketchUp này không hỗ trợ cắt khối Solid Tools.' if error.is_a?(NotImplementedError)
      raise
    end
    def leaves(target,parent_world,result=[])
      raise 'Có Group/Component đang khóa; mở khóa trước khi cắt.' if target.locked?
      world=parent_world*target.transformation
      children=target.definition.entities.select { |e| container?(e) && e.valid? }
      if children.empty?
        raise 'Có tấm chưa kín; sửa mặt hở trước khi cắt.' unless target.manifold?
        result << [target,world]
      else
        children.each { |e| leaves(e,world,result) }
      end
      result
    end
    def cut_tree(model,target,context,parent_world,planes)
      children=target.definition.entities.select { |e| container?(e) && e.valid? }
      unless children.empty?
        target.make_unique
        world=parent_world*target.transformation
        target.definition.entities.to_a.select { |e| container?(e) && e.valid? }.each do |child|
          cut_tree(model,child,target.definition.entities,world,planes)
        end
        return [target]
      end
      pieces=[target]
      planes.each do |plane,normal|
        pieces=pieces.flat_map do |part|
          data=plane_data(corners(part,parent_world*part.transformation),plane,normal)
          if data[:min]<-0.001.mm && data[:max]>0.001.mm
            perform(model,part,plane,normal,:both,false,context,parent_world)
          else
            [part]
          end
        end
      end
      pieces
    end
    def activate; Sketchup.active_model.select_tool(Tool.new); end

    class Tool
      def activate
        @model=Sketchup.active_model;@context=@model.active_entities
        @face_mode=false;@face_valid=false;@axis_index=2
        @targets=[];@normal=Geom::Vector3d.new(0,0,1);@down={};@placed=false
        @ip=Sketchup::InputPoint.new
        selected=@model.selection.to_a.select { |e| CutBlock.container?(e) }
        if selected.empty?
          @model.active_path=nil if @model.active_path
          @context=@model.active_entities
          selected=@context.select { |e| CutBlock.container?(e) && e.valid? }
        end
        select_targets(selected) unless selected.empty?
        status
      rescue StandardError=>e
        @targets=[];status(e.message)
      end
      def status(message=nil)
        prompt=@targets.empty? ? 'Click hoặc kéo khung quét chọn khối' : 'Rê preview mặt cắt, CLICK CẮT NGAY — giữ cả hai phần'
        Sketchup.set_status_text(message || "CẮT KHỐI · #{prompt} · ↑ Z / → X / ← Y · SHIFT: #{@face_mode ? 'RÊ FACE' : 'THEO TRỤC'} · TAB đổi trục · Nhập /N chia đều hoặc mm từ tâm · ESC chọn lại",SB_PROMPT)
      end
      def select_targets(targets)
        raise 'Chưa chọn được khối kín.' if targets.empty?
        targets=targets.uniq
        targets.each { |t| raise 'Chọn khối trong cấp đang mở.' unless @context.include?(t) }
        @targets=targets
        @points=targets.flat_map { |t| CutBlock.leaves(t,@model.edit_transform).flat_map { |part,world| CutBlock.corners(part,world) } }
        @center=Geom::Point3d.new(*3.times.map { |i| values=@points.map { |p| p.to_a[i] };(values.min+values.max)/2.0 })
        @point=@center;@placed=false;@division_count=nil
        @model.selection.clear;targets.each { |t| @model.selection.add(t) }
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
        if @drag_start
          @drag_end=[x,y]
        elsif !@targets.empty? && !@placed
          @ip.pick(view,x,y)
          if @face_mode
            @face_valid=false
            ph=view.pick_helper;ph.do_pick(x,y)
            ph.count.times do |i|
              path=ph.path_at(i)
              face=path && path.last
              next unless face.is_a?(Sketchup::Face)
              tr=@model.edit_transform*ph.transformation_at(i)
              pts=face.outer_loop.vertices.map { |v| v.position.transform(tr) }
              n=nil
              (1...pts.length-1).each do |j|
                candidate=(pts[j]-pts[0]).cross(pts[j+1]-pts[0])
                if candidate.length>1e-9;n=candidate.normalize;break;end
              end
              next unless n
              hit=Geom.intersect_line_plane(view.pickray(x,y),[pts[0],n])
              next unless hit
              @normal=n;@point=hit;@face_valid=true
              break
            end
          else
            @point=@ip.position if @ip.valid?
          end
        end
        view.invalidate
      end
      def onLButtonDown(_flags,x,y,view)
        if @targets.empty?
          @drag_start=[x,y];@drag_end=[x,y]
        else
          # Cut at the displayed plane; numeric input must not be overwritten.
          cut_now(view)
        end
        view.invalidate
      rescue StandardError=>e
        status(e.message);UI.beep
      end
      def onLButtonUp(_flags,x,y,view)
        return unless @drag_start
        first=@drag_start;@drag_start=nil;@drag_end=nil
        if Math.hypot(x-first[0],y-first[1])>=5
          ph=view.pick_helper
          kind=x>=first[0] ? Sketchup::PickHelper::PICK_INSIDE : Sketchup::PickHelper::PICK_CROSSING
          ph.window_pick(Geom::Point3d.new(first[0],first[1],0),Geom::Point3d.new(x,y,0),kind)
          selected=ph.all_picked.select { |e| CutBlock.container?(e) && @context.include?(e) }
        else
          selected=[pick(view,x,y)].compact
        end
        select_targets(selected);status;view.invalidate
      rescue StandardError=>e
        status(e.message);view.invalidate
      end
      def cut_planes
        return [@point] unless @division_count
        values=@points.map { |p| (p-@center).dot(@normal) }
        low,high=values.minmax
        (1...@division_count).map { |i| @center.offset(@normal,low+(high-low)*i/@division_count) }
      end
      def cut_now(view)
        raise 'Rê vào Face để nhận mặt cắt trước.' if @face_mode && !@face_valid
        raise 'Cấp chỉnh sửa đã đổi. Thoát công cụ và chọn lại khối.' unless @context==@model.active_entities
        all=@targets.flat_map { |t| CutBlock.leaves(t,@model.edit_transform) }
        planes=cut_planes.map { |p| [p,@normal] }
        crossing=all.any? do |part,world|
          planes.any? do |point,normal|
            data=CutBlock.plane_data(CutBlock.corners(part,world),point,normal)
            data[:min]<-0.001.mm && data[:max]>0.001.mm
          end
        end
        raise 'Mặt cắt chưa đi qua tấm nào.' unless crossing
        started=false
        @model.start_operation('TRẦN TUẤN - Cắt tấm trong cụm',true);started=true
        pieces=@targets.flat_map { |t| CutBlock.cut_tree(@model,t,@context,@model.edit_transform,planes) }
        @model.selection.clear;pieces.each { |g| @model.selection.add(g) }
        @model.commit_operation;started=false
        @targets=[];@placed=false;@division_count=nil
        UI.beep;status('Đã cắt và giữ các phần. Quét chọn khối khác để tiếp tục.');view.invalidate
      rescue StandardError
        @model.abort_operation if started
        raise
      end
      def enableVCB?;true;end
      def onUserText(text,view)
        raise 'Chọn khối trước khi nhập vị trí cắt.' if @targets.empty?
        raw=text.strip
        raw='/2' if raw=='/'
        if raw.start_with?('/')
          raise 'Nhập /2 đến /50.' unless raw.match?(/\A\/\s*\d+\z/)
          count=raw.delete('/').strip.to_i
          raise 'Nhập /2 đến /50.' unless count.between?(2,50)
          @division_count=count;@placed=true
          status("Chia #{count} phần đều theo trục đang chọn · click cắt");view.invalidate;return
        end
        @division_count=nil
        value=Float(text.strip.tr(',','.'))
        raise 'Khoảng cách không hợp lệ.' unless value.finite?
        @point=@center.offset(@normal,value/25.4);@placed=true
        status("Mặt cắt cách tâm #{value} mm · CLICK để cắt, giữ cả hai phần");view.invalidate
      rescue StandardError=>e
        status(e.message)
      end
      def onKeyDown(key,_repeat,_flags,view)
        if key==16
          return true if @down[key]
          @down[key]=true
          @face_mode=!@face_mode;@face_valid=false;@placed=false;@division_count=nil
          @normal=Geom::Vector3d.new(*3.times.map { |i| i==@axis_index ? 1 : 0 }) unless @face_mode
          status;view.invalidate;return true
        end
        if [191,111].include?(key) && !@targets.empty?
          @division_count=2;@placed=true
          status('Chia đôi · nhập thêm N để chia N phần · click cắt')
          view.invalidate
          return false
        end
        return false if key==13
        return false unless [9,37,38,39,88,89,90].include?(key)
        return true if @down[key]
        @down[key]=true
        if key==13
          cut_now(view) unless @targets.empty?
        else
          axis=if key==9
                 (@axis_index+1)%3
               else
                 [39,88].include?(key) ? 0 : ([37,89].include?(key) ? 1 : 2)
               end
          @axis_index=axis;@face_mode=false;@face_valid=false
          @normal=Geom::Vector3d.new(*3.times.map { |i| i==axis ? 1 : 0 });status
        end
        view.invalidate;true
      rescue StandardError=>e
        status(e.message);UI.beep;true
      end
      def onKeyUp(key,*);@down.delete(key);end
      def onCancel(_reason,view)
        if @drag_start
          @drag_start=nil;@drag_end=nil
        elsif @placed
          @placed=false;@division_count=nil
        elsif !@targets.empty?
          @targets=[]
        else
          @model.select_tool(nil)
        end
        status;view.invalidate
      end
      def resume(view);@down.clear;status;view.invalidate;end
      def deactivate(view);view.invalidate;end
      def draw(view)
        if @drag_start && @drag_end
          a,b=@drag_start,@drag_end
          rect=[[a[0],a[1]],[b[0],a[1]],[b[0],b[1]],[a[0],b[1]]].map { |x,y| Geom::Point3d.new(x,y,0) }
          view.drawing_color=Sketchup::Color.new(30,140,210)
          view.line_stipple=b[0]<a[0] ? '-' : '';view.line_width=2
          view.draw2d(GL_LINE_LOOP,rect);view.line_stipple=''
          return
        end
        return if @targets.empty? || @targets.any? { |t| !t.valid? }
        return if @face_mode && !@face_valid
        cut_planes.each do |plane|
        data=CutBlock.plane_data(@points,plane,@normal);polygon=CutBlock.quad(data)
        view.drawing_color=Sketchup::Color.new(255,160,70,65);view.draw(GL_QUADS,polygon)
        view.drawing_color=Sketchup::Color.new(240,120,20);view.line_width=2;view.line_stipple='-'
        view.draw(GL_LINE_LOOP,polygon);view.line_stipple=''
        end
        @ip.draw(view) if @ip.valid? && !@placed
      end
    end
  end
end
