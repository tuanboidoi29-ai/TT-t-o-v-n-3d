# encoding: UTF-8
require 'json'
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
        @cutters=[]
        @targets=[]; @role=:cutter; @hover=nil; @chosen=nil
        @diameter=6.0; @dogbone=true; @reliefs=[]; @result_lines=[]; @ready=false; @busy=false
        @gap=Sketchup.read_default(PREF,'gap_mm',0.0).to_f
        @gap=0.0 unless @gap.finite? && @gap>=0 && @gap<=100
        @model.selection.clear
        rebuild
        status
      end
      def status
        role=@role==:cutter ? 'KHUÔN GIỮ NGUYÊN' : 'TẤM BỊ KHẤU'
        Sketchup.set_status_text("KHẤU · #{role} · SHIFT đổi vai trò · Click chọn và mở cài đặt · TAB mở lại bảng · Chỉ ÁP DỤNG mới cắt · Cùng cấp nhóm đang chỉnh sửa.",SB_PROMPT)
      end
      def report(message,error=false)
        @dialog.execute_script("document.getElementById('msg').textContent=#{JSON.generate(message)};document.getElementById('apply').disabled=#{!@ready};") if @dialog && @dialog.visible?
        Sketchup.set_status_text(message,SB_PROMPT)
      end
      def expanded_box(e)
        return world_bounds(e) if @gap<=0
        box=Geom::BoundingBox.new
        box.add(NotchTool.expanded(e,@edit*e.transformation,@gap/25.4).flatten(1))
        box
      end
      def gather
        @ready=false; @cutters=[]; @targets=[]; @skipped=0
        @reliefs=[];@result_lines=[]
        return unless @chosen && @chosen.valid?
        NotchTool.validate!(@chosen)
        if @role==:cutter
          @cutters=[@chosen]
          box=expanded_box(@chosen)
          @context.to_a.each do |e|
            next if e==@chosen || !NotchTool.container?(e) || !e.valid?
            next unless boxes_overlap?(box,world_bounds(e))
            begin
              NotchTool.validate!(e);@targets<<e
            rescue StandardError
              @skipped+=1
            end
          end
        else
          @targets=[@chosen]
          @context.to_a.each do |e|
            next if e==@chosen || !NotchTool.container?(e) || !e.valid?
            begin
              NotchTool.validate!(e)
              @cutters<<e if boxes_overlap?(expanded_box(e),world_bounds(@chosen))
            rescue StandardError
              @skipped+=1
            end
          end
        end
        rebuild
        raise @preview_error if @preview_error
      end
      def world_bounds(e)
        box=Geom::BoundingBox.new
        tr=@edit*e.transformation
        box.add((0..7).map { |i| e.definition.bounds.corner(i).transform(tr) })
        box
      end
      def boxes_overlap?(a,b)
        box=a.intersect(b)
        box.valid? && box.width>1e-6 && box.height>1e-6 && box.depth>1e-6
      end
      def onMouseMove(flags,x,y,view)
        return if @chosen || @busy
        ph=view.pick_helper; ph.do_pick(x,y)
        picked=ph.best_picked
        @hover=NotchTool.container?(picked) && @context.include?(picked) ? picked : nil
        @cutters=@role==:cutter && @hover ? [@hover] : []
        @targets=@role==:target && @hover ? [@hover] : []
        view.invalidate
      end
      def onLButtonDown(flags,x,y,view)
        return if @busy
        ph=view.pick_helper;ph.do_pick(x,y)
        picked=ph.best_picked
        return UI.beep unless NotchTool.container?(picked) && @context.include?(picked)
        NotchTool.validate!(picked)
        @chosen=picked
        open_settings
      rescue StandardError=>e
        @ready=false;report(e.message,true)
      end
      def flip_role
        return if @busy
        @role=@role==:cutter ? :target : :cutter
        unless @chosen
          @cutters=@role==:cutter && @hover ? [@hover] : []
          @targets=@role==:target && @hover ? [@hover] : []
        end
        @dialog.execute_script("document.getElementById('role').textContent=#{JSON.generate(@role==:cutter ? 'Khuôn giữ nguyên' : 'Tấm bị khấu')}") if @dialog && @dialog.visible?
        refresh_preview if @chosen
        status
      end
      def onKeyDown(key,repeat,flags,view)
        return if repeat.to_i>0 || @busy
        flip_role if key==16
        open_settings if key==9 && @chosen
        view.invalidate
      end
      def open_settings
        if @dialog && @dialog.visible?
          @dialog.bring_to_front;refresh_preview;return
        end
        @dialog=UI::HtmlDialog.new(dialog_title:'Khấu ván / Dogbone',preferences_key:'TT.Notch205',width:420,height:440,resizable:true,scrollable:true,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(<<~HTML)
          <!doctype html><html lang="vi"><meta charset="utf-8"><style>
          body{font:15px Arial;padding:16px;background:#f3f6fa;color:#19324c}label{display:block;margin:14px 0 6px}input[type=number]{padding:9px;width:90%}button{padding:11px;margin:12px 4px 0 0;border:0;background:#186a80;color:white;border-radius:5px}#msg{line-height:1.5;margin-top:16px}button:disabled{opacity:.4}</style>
          <b id="role">#{@role==:cutter ? 'Khuôn giữ nguyên' : 'Tấm bị khấu'}</b>
          <button onclick="sketchup.flip()">SHIFT · Đổi vai trò</button>
          <label>Mở rộng mỗi biên (mm)</label><input id="gap" type="number" min="0" max="100" step="0.1" value="#{@gap}">
          <label><input id="bone" type="checkbox" #{@dogbone ? 'checked' : ''}> Khử góc dogbone — preview đỏ</label>
          <label>Đường kính dao (mm)</label><input id="diameter" type="number" min="0.5" max="50" step="0.1" value="#{@diameter}">
          <button onclick="preview()">Xem trước</button><button id="apply" disabled onclick="this.disabled=true;sketchup.apply(Number(document.getElementById('gap').value),Number(document.getElementById('diameter').value),document.getElementById('bone').checked)">Áp dụng</button>
          <div id="msg">Chưa cắt model. Chỉnh số để cập nhật preview.</div>
          <script>let timer;function preview(){document.getElementById('apply').disabled=true;sketchup.preview(Number(document.getElementById('gap').value),Number(document.getElementById('diameter').value),document.getElementById('bone').checked)}
          document.querySelectorAll('input').forEach(e=>e.addEventListener('input',()=>{clearTimeout(timer);document.getElementById('apply').disabled=true;timer=setTimeout(preview,400)}));
          document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
          document.addEventListener('keydown',e=>{if(e.key==='Shift'&&!e.repeat){e.preventDefault();sketchup.flip()}});</script></html>
        HTML
        @dialog.add_action_callback('ready') { |_ctx| refresh_preview }
        @dialog.add_action_callback('flip') { |_ctx| flip_role }
        @dialog.add_action_callback('preview') do |_ctx,gap,diameter,bone|
          begin
            raise 'Mở rộng: 0–100 mm; đường kính dao: 0,5–50 mm.' unless gap.is_a?(Numeric) && gap.finite? && gap.between?(0,100) && diameter.is_a?(Numeric) && diameter.finite? && diameter.between?(0.5,50)
            @gap=gap.to_f;@diameter=diameter.to_f;@dogbone=bone==true
            refresh_preview
          rescue StandardError=>e
            @ready=false;report(e.message,true)
          end
        end
        @dialog.add_action_callback('apply') do |_ctx,gap,diameter,bone|
          begin
            raise 'Thông số đã đổi: bấm Xem trước trước khi áp dụng.' unless gap==@gap && diameter==@diameter && bone==@dogbone
            raise 'Cần preview hợp lệ trước khi áp dụng.' unless @ready
            execute
            @chosen=nil;@ready=false;@cutters=[];@targets=[];@reliefs=[];@result_lines=[]
            @dialog.close if @dialog
          rescue StandardError=>e
            @ready=false;report(e.message,true)
          ensure
            @model.active_view.invalidate
          end
        end
        @dialog.set_on_closed { @dialog=nil }
        @dialog.show
      end
      def onCancel(reason,view)
        if @chosen
          @chosen=nil;@ready=false;@cutters=[];@targets=[];@reliefs=[];@result_lines=[]
          @dialog.close if @dialog
          status;view.invalidate
        else
          @model.select_tool(nil)
        end
      end
      def deactivate(view)
        @dialog.close if @dialog
        view.invalidate
      end
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
        view.drawing_color=Sketchup::Color.new(10,45,130)
        view.draw(GL_LINES,@result_lines) unless @result_lines.empty?
        view.drawing_color=Sketchup::Color.new(240,35,35)
        @reliefs.each do |bone|
          bottom,top=bone[:bottom],bone[:top]
          view.draw(GL_LINE_LOOP,bottom);view.draw(GL_LINE_LOOP,top)
          view.draw(GL_LINES,(0...bottom.length).step(4).flat_map { |i| [bottom[i],top[i]] })
        end
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
      # Native intersection is performed on disposable copies to exclude
      # disjoint solids whose bounding boxes overlap. Never probe originals.
      def volume_overlap?(a,b)
        left=a.copy; right=b.copy
        intersection=left.intersect(right)
        intersection && intersection.valid? && intersection.manifold? && intersection.volume>1e-7
      ensure
        [intersection,left,right].compact.uniq.each { |e| e.erase! if e.valid? }
      end
      def dogbone_plan(target,result)
        return [] unless @dogbone
        tr=@edit*target.transformation
        axes=[tr.xaxis,tr.yaxis,tr.zaxis]
        norms=axes.map { |v| v.normalize }
        raise 'Dogbone chưa hỗ trợ tấm bị xiên trục.' if norms.combination(2).any? { |a,b| a.dot(b).abs>1e-5 }
        box=target.definition.bounds
        sizes=[box.width,box.height,box.depth].each_with_index.map { |v,i| v*axes[i].length }
        axis=norms[sizes.each_with_index.min_by(&:first)[1]]
        original=target.definition.entities.grep(Sketchup::Edge).flat_map { |e| [e.start.position.transform(tr),e.end.position.transform(tr)] }
        low,high=original.map { |p| p.to_a.zip(axis.to_a).sum { |x,y| x*y } }.minmax
        radius=@diameter/50.8
        plans=[]
        result_points=result.definition.entities.grep(Sketchup::Edge).flat_map { |e| [e.start.position.transform(result.transformation),e.end.position.transform(result.transformation)] }
        result.definition.entities.grep(Sketchup::Face).each do |face|
          ft=result.transformation
          normal=face.normal.transform(ft).normalize
          next unless normal.dot(axis).abs>0.9999
          face_points=face.vertices.map { |v| v.position.transform(ft) }
          next unless face_points.all? { |p| (NotchTool.dot(p.to_a,axis.to_a)-high).abs<0.001 }
          face.loops.each do |loop|
            pts=loop.vertices.map { |v| v.position.transform(ft) }
            pts.each_with_index do |point,i|
              previous=pts[(i-1)%pts.length];following=pts[(i+1)%pts.length]
              incoming=point-previous;outgoing=following-point
              next if incoming.length<1e-6 || outgoing.length<1e-6
              next unless incoming.normalize.cross(outgoing.normalize).dot(normal)<-0.001
              next if original.any? { |p| p.distance(point)<0.0001 }
              opposite=point.offset(axis,low-high)
              unless result_points.any? { |p| p.distance(opposite)<0.0001 }
                raise 'Dogbone hiện hỗ trợ khấu xuyên độ dày. Rãnh mù: tắt dogbone để khấu thường.'
              end
              a=previous-point;b=following-point
              raise 'Dogbone hiện hỗ trợ góc lõm 90°. Tắt dogbone cho góc khác.' if a.normalize.dot(b.normalize).abs>0.001
              raise 'Đường kính dao quá lớn so với cạnh góc khấu. Giảm đường kính dao.' if [a.length,b.length].min<radius*2
              next if plans.any? { |q| q[:corner].distance(point)<0.0001 }
              bisector=(a.normalize+b.normalize).normalize
              center=point.offset(bisector,radius*0.999)
              base=center.offset(axis,low-NotchTool.dot(center.to_a,axis.to_a)-0.001)
              # Start the circle toward the original sharp corner, keeping
              # preview and native cutter polygon identical.
              u=(point-center).normalize
              v=axis.cross(u).normalize
              bottom=(0...48).map do |j|
                angle=2*Math::PI*j/48
                base.offset(u,radius*Math.cos(angle)).offset(v,radius*Math.sin(angle))
              end
              top=bottom.map { |p| p.offset(axis,high-low+0.002) }
              plans<<{corner:point,bottom:bottom,top:top,axis:axis,height:high-low+0.002}
            end
          end
        end
        raise 'Quá nhiều góc dogbone trong một tấm; chia thao tác thành lượt nhỏ.' if plans.length>128
        plans
      end
      def relief_solid(work,bone)
        group=work.add_group
        face=group.entities.add_face(bone[:bottom])
        raise 'Không dựng được vòng dao.' unless face
        face.reverse! if face.normal.dot(bone[:axis])<0
        face.pushpull(bone[:height])
        raise 'Khối dao dogbone không kín.' unless group.manifold?
        group
      end
      def build_results(work)
        @reliefs=[]
        results=[]
        @targets.each do |target|
          current=copy_solid(work,target)
          before=current.volume
          @cutters.each do |cutter|
            tool=cutter_copy(work,cutter)
            if overlap?(tool,current) && volume_overlap?(tool,current)
              result=tool.trim(current)
              raise 'Không cắt được cặp tấm hoặc khuôn phủ hết tấm. Đã hủy lượt.' unless result && result.valid? && result.manifold?
              current=result
            end
            tool.erase! if tool.valid?
          end
          next unless before-current.volume>1e-7
          bones=dogbone_plan(target,current)
          bones.each do |bone|
            tool=relief_solid(work,bone)
            result=tool.trim(current)
            raise 'Không cắt được dogbone; đã hủy lượt để giữ nguyên model.' unless result && result.valid? && result.manifold?
            current=result
            tool.erase! if tool.valid?
          end
          @reliefs.concat(bones)
          results<<[target,current]
        end
        results
      end
      def refresh_preview
        return if @busy || !@chosen
        @busy=true;@ready=false
        report('Đang dựng bản sao xem trước…')
        gather
        raise 'Không có cặp tấm Solid giao nhau trong cấp đang chỉnh sửa.' if @cutters.empty? || @targets.empty?
        raise 'Hơn 30 cặp tấm: hãy mở nhóm nhỏ hơn để tránh preview quá nặng.' if @cutters.length*@targets.length>30
        started=false
        @model.start_operation('TT - Xem trước khấu (tạm)',true)
        started=true
        workspace=@context.add_group
        workspace.transformation=@edit.inverse
        results=build_results(workspace.entities)
        @result_lines=results.flat_map do |_target,result|
          result.definition.entities.grep(Sketchup::Edge).flat_map { |e| [e.start.position.transform(result.transformation),e.end.position.transform(result.transformation)] }
        end
        changed=results.length
        @model.abort_operation;started=false
        @ready=changed>0
        report("Xem trước #{changed} tấm; #{@reliefs.length} góc dogbone màu đỏ. Bỏ qua #{@skipped} khối khóa/không hợp lệ. Chưa cắt model.")
      rescue StandardError=>e
        @model.abort_operation if started
        @ready=false;@reliefs=[];@result_lines=[]
        report(e.message,true)
      ensure
        @busy=false
        @model.active_view.invalidate
      end
      def execute
        raise 'Chọn ít nhất một tấm bị khấu.' if @targets.empty?
        raise 'Ngữ cảnh model đã thay đổi. Mở lại công cụ.' unless @context==@model.active_entities
        (@cutters+@targets).each { |e| NotchTool.validate!(e) }
        gather
        raise 'Không có khuôn/tấm giao nhau.' if @cutters.empty? || @targets.empty?
        started=false
        @model.start_operation('TRẦN TUẤN - Khấu ván AUTO',true)
        started=true
        workspace=@context.add_group
        workspace.transformation=@edit.inverse
        work=workspace.entities
        raise 'Hơn 30 cặp tấm: hãy mở nhóm nhỏ hơn.' if @cutters.length*@targets.length>30
        results=build_results(work)
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
        Sketchup.set_status_text("Đã khấu #{results.length} tấm; #{@reliefs.length} góc dogbone. Ctrl+Z hoàn tác cả lượt.",SB_PROMPT)
        UI.beep unless results.empty?
        @targets=[]; @phase=:targets
      rescue StandardError
        @model.abort_operation if started
        raise
      end
    end
  end
end
