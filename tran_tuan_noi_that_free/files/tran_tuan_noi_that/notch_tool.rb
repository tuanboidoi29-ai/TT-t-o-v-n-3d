# encoding: UTF-8
module TranTuanNoiThat
  module NotchTool
    extend self
    PREF = 'TT_KHAU_VAN_AUTO'.freeze unless const_defined?(:PREF, false)
    def container?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end
    def activate
      Sketchup.active_model.select_tool(Tool.new)
    end
    def dot(a,b); a.zip(b).sum { |x,y| x*y }; end
    def cross(a,b)
      [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
    end
    def solve_planes(planes)
      planes.combination(3) do |a,b,c|
        bc=cross(b[0,3],c[0,3]); det=dot(a[0,3],bc)
        next if det.abs<1e-9
        ca=cross(c[0,3],a[0,3]); ab=cross(a[0,3],b[0,3])
        p=(0..2).map { |i| (-a[3]*bc[i]-b[3]*ca[i]-c[3]*ab[i])/det }
        return p if planes.all? { |q| (dot(q[0,3],p)+q[3]).abs < 1e-5 }
      end
      raise 'Không mở rộng được góc khuôn này. Hãy dùng 0 mm.'
    end
    # Offset supporting planes in world units. No bounding-box substitution.
    def expanded(entity, transform, gap)
      faces=entity.definition.entities.grep(Sketchup::Face)
      vertices=faces.flat_map(&:vertices).uniq
      positions=vertices.to_h { |v| [v,v.position.transform(transform)] }
      center=Geom::Point3d.new(*(0..2).map { |i| positions.values.sum { |p| p.to_a[i] }/vertices.length })
      planes={}
      faces.each do |face|
        pts=face.outer_loop.vertices.map { |v| positions[v] }
        plane=Geom.fit_plane_to_points(pts)
        raise 'Không xác định được mặt khuôn.' unless plane
        norm=Math.sqrt(dot(plane[0,3],plane[0,3])); plane=plane.map { |v| v/norm }
        plane=plane.map { |v| -v } if dot(plane[0,3],center.to_a)+plane[3]>0
        if positions.values.any? { |p| dot(plane[0,3],p.to_a)+plane[3]>1e-5 } || face.loops.length>1
          raise 'Mở rộng biên hiện hỗ trợ khuôn khối lồi (ván phẳng/vát). Khuôn lõm hoặc có lỗ: đặt 0 mm.'
        end
        planes[face]=plane[0,3]+[plane[3]-gap]
      end
      moved=vertices.to_h { |v| [v,Geom::Point3d.new(solve_planes(v.faces.map { |f| planes.fetch(f) }))] }
      faces.map { |f| f.outer_loop.vertices.map { |v| moved[v] } }
    end
    def validate!(e)
      raise 'Tấm đã bị xóa hoặc đang khóa.' unless e && e.valid? && !e.locked?
      raise "#{e.name}: cần Group/Component kín (Solid)." unless e.manifold?
      unless e.definition.entities.all? { |x| x.is_a?(Sketchup::Face) || x.is_a?(Sketchup::Edge) }
        raise "#{e.name}: hãy chọn khối ván chỉ có mặt/cạnh, không kèm nhóm con hoặc DIM."
      end
    end
    class Tool
      def activate
        @model=Sketchup.active_model
        @context=@model.active_entities
        @edit=@model.edit_transform
        @cutters=@model.selection.to_a.select { |e| NotchTool.container?(e) }
        @targets=[]; @phase=:cutters; @hover=nil
        @gap=Sketchup.read_default(PREF,'gap_mm',0.0).to_f
        @gap=0.0 unless @gap.finite? && @gap>=0 && @gap<=100
        @model.selection.clear
        rebuild
        status
      end
      def status
        role=@phase==:cutters ? 'KHUÔN xanh nhạt' : 'TẤM BỊ KHẤU xanh đậm'
        Sketchup.set_status_text("KHẤU AUTO · Chọn #{role} · SHIFT+click thêm/bỏ · ENTER tiếp tục/khấu · TAB mở rộng #{@gap} mm · #{@cutters.size} khuôn / #{@targets.size} tấm. Chọn ván trong cùng cấp; mở nhóm cha để chọn ván con.",SB_PROMPT)
      end
      def onMouseMove(flags,x,y,view)
        ph=view.pick_helper; ph.do_pick(x,y)
        @hover=ph.best_picked
        @hover=nil unless NotchTool.container?(@hover) && @context.include?(@hover)
        view.invalidate
      end
      def onLButtonDown(flags,x,y,view)
        onMouseMove(flags,x,y,view)
        return UI.beep unless @hover
        NotchTool.validate!(@hover)
        list=@phase==:cutters ? @cutters : @targets
        other=@phase==:cutters ? @targets : @cutters
        return UI.beep if other.include?(@hover)
        shift=(flags & CONSTRAIN_MODIFIER_MASK)!=0
        if shift
          list.include?(@hover) ? list.delete(@hover) : list.push(@hover)
        else
          list.replace([@hover])
        end
        rebuild; status; view.invalidate
      rescue StandardError=>e
        UI.messagebox(e.message)
      end
      def onKeyDown(key,repeat,flags,view)
        return if repeat.to_i>0
        case key
        when 9
          values=UI.inputbox(['Mở rộng mỗi biên (mm, 0 = sát)'],[@gap],'Khấu ván AUTO')
          if values
            value=Float(values[0].to_s.tr(',','.'))
            raise 'Nhập số từ 0 đến 100 mm.' unless value.finite? && value>=0 && value<=100
            @gap=value
            Sketchup.write_default(PREF,'gap_mm',@gap)
            rebuild
            raise @preview_error if @preview_error
          end
        when 13
          if @phase==:cutters
            raise 'Chọn ít nhất một tấm khuôn.' if @cutters.empty?
            @cutters.each { |e| NotchTool.validate!(e) }
            raise @preview_error if @preview_error
            @phase=:targets
          else
            execute
          end
        when 8
          @phase=:cutters
        end
        status; view.invalidate
      rescue StandardError=>e
        UI.messagebox(e.message)
      end
      def onCancel(reason,view); @model.select_tool(nil); end
      def deactivate(view); view.invalidate; end
      def rebuild
        @preview_error=nil
        @expanded={}
        if @gap>0
          @cutters.each { |e| @expanded[e]=NotchTool.expanded(e,@edit*e.transformation,@gap/25.4) }
        end
      rescue StandardError=>e
        @preview_error=e.message
        Sketchup.set_status_text(e.message,SB_PROMPT)
      end
      def draw_entity(view,e,color)
        return unless e.valid?
        tr=@edit*e.transformation
        view.drawing_color=color
        e.definition.entities.grep(Sketchup::Face).each do |f|
          mesh=f.mesh
          triangles=mesh.polygons.select { |p| p.length==3 }.flat_map { |p| p.map { |i| mesh.point_at(i.abs).transform(tr) } }
          view.draw(GL_TRIANGLES,triangles) unless triangles.empty?
        end
        view.line_width=2
        lines=e.definition.entities.grep(Sketchup::Edge).flat_map { |ed| [ed.start.position.transform(tr),ed.end.position.transform(tr)] }
        view.draw(GL_LINES,lines) unless lines.empty?
      end
      def draw(view)
        @cutters.each { |e| draw_entity(view,e,Sketchup::Color.new(95,215,255,110)) }
        @targets.each { |e| draw_entity(view,e,Sketchup::Color.new(15,65,190,155)) }
        view.drawing_color=Sketchup::Color.new(65,190,255)
        view.line_width=2; view.line_stipple='-'
        @expanded.each_value do |faces|
          faces.each { |pts| view.draw(GL_LINE_LOOP,pts) }
        end
        view.line_stipple=''
      end
      def copy_solid(work,e)
        g=work.add_group
        g.entities.add_instance(e.definition,@edit*e.transformation).explode
        g.material=e.material
        raise 'Bản sao tấm không kín.' unless g.manifold?
        g
      end
      def cutter_copy(work,e)
        return copy_solid(work,e) if @gap==0
        g=work.add_group
        polygons=@expanded.fetch(e)
        center=Geom::Point3d.new(*(0..2).map { |i| polygons.flatten(1).sum { |p| p.to_a[i] }/polygons.flatten(1).length })
        polygons.each do |pts|
          f=g.entities.add_face(pts)
          raise 'Không dựng được khuôn mở rộng.' unless f
          f.reverse! if f.normal.dot(f.bounds.center-center)<0
        end
        raise 'Khuôn mở rộng không kín.' unless g.manifold?
        g
      end
      def overlap?(a,b)
        box=a.bounds.intersect(b.bounds)
        box.valid? && box.width>1e-6 && box.height>1e-6 && box.depth>1e-6
      end
      def execute
        raise 'Chọn ít nhất một tấm bị khấu.' if @targets.empty?
        raise 'Ngữ cảnh model đã thay đổi. Mở lại công cụ.' unless @context==@model.active_entities
        (@cutters+@targets).each { |e| NotchTool.validate!(e) }
        rebuild
        raise @preview_error if @preview_error
        started=false
        @model.start_operation('TRẦN TUẤN - Khấu ván AUTO',true)
        started=true
        workspace=@context.add_group
        workspace.transformation=@edit.inverse
        work=workspace.entities
        results=[]
        @targets.each do |target|
          current=copy_solid(work,target)
          before=current.volume
          @cutters.each do |cutter|
            tool=cutter_copy(work,cutter)
            if overlap?(tool,current)
              result=tool.trim(current)
              raise 'SketchUp không cắt được cặp tấm này (hoặc khuôn phủ hết tấm). Đã hủy toàn bộ lượt.' unless result && result.valid? && result.manifold?
              current=result
            end
            tool.erase! if tool.valid?
          end
          results << [target,current] if before-current.volume>1e-7
        end
        results.each do |target,result|
          target.make_unique
          dest=target.definition.entities
          dest.clear!
          # World-baked result -> original target local coordinates.
          inst=dest.add_instance(result.definition,(@edit*target.transformation).inverse*result.transformation)
          inst.explode
          raise 'Tấm sau khấu không kín.' unless target.manifold?
        end
        workspace.erase!
        if results.empty?
          @model.abort_operation
        else
          @model.commit_operation
        end
        started=false
        UI.messagebox("Đã khấu #{results.length}/#{@targets.length} tấm. Khuôn giữ nguyên. Ctrl+Z hoàn tác cả lượt.")
        @targets=[]; @phase=:targets
      rescue StandardError
        @model.abort_operation if started
        raise
      end
    end
  end
end
