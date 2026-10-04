# encoding: UTF-8
module TranTuanNoiThat
  module DivideBoards
    extend self
    def activate; Sketchup.active_model.select_tool(Tool.new); end
    def container?(e); e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance); end
    def spacing(clear, thickness, count)
      raise 'Số tấm phải từ 1 đến 100.' unless count.is_a?(Integer) && count.between?(1,100)
      raise 'Không đo được khoảng lọt lòng hoặc độ dày.' unless clear.finite? && thickness.finite? && clear>0 && thickness>0
      gap=(clear-count*thickness)/(count+1)
      raise 'Không đủ chỗ cho số tấm này. Giảm /N.' unless gap>1e-6
      [(0...count).map { |i| (i+1)*(gap+thickness) },gap]
    end
    def anchor_offset(thickness,index)
      [-thickness/2.0,0.0,thickness/2.0].fetch(index)
    end
    # Convex planar polygon subtraction. Subject faces and cutters come from meshes.
    def area2(poly)
      poly.each_with_index.sum { |p,i| q=poly[(i+1)%poly.length];p[0]*q[1]-q[0]*p[1] }
    end
    def clip_half(poly,a,b,inside)
      result=[]
      poly.each_with_index do |p,i|
        q=poly[(i+1)%poly.length]
        dp=(b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        dq=(b[0]-a[0])*(q[1]-a[1])-(b[1]-a[1])*(q[0]-a[0])
        dp=-dp unless inside;dq=-dq unless inside
        pin=dp>=-1e-9;qin=dq>=-1e-9
        result << p if pin
        if pin!=qin && (dp-dq).abs>1e-12
          t=dp.to_f/(dp-dq);result << [p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])]
        end
      end
      result=result.each_with_object([]) { |p,out| out << p if out.empty? || Math.hypot(p[0]-out[-1][0],p[1]-out[-1][1])>1e-8 }
      result.pop if result.length>1 && Math.hypot(result[0][0]-result[-1][0],result[0][1]-result[-1][1])<1e-8
      result
    end
    def subtract_polygon(subject,cutter)
      cutter=cutter.reverse if area2(cutter)<0
      remainder=subject;outside=[]
      cutter.each_with_index do |a,i|
        break if remainder.length<3
        b=cutter[(i+1)%cutter.length]
        piece=clip_half(remainder,a,b,false)
        outside << piece if piece.length>=3 && area2(piece).abs>1e-8
        remainder=clip_half(remainder,a,b,true)
      end
      outside
    end
    def boundary_segments(polygons)
      points=polygons.flatten(1)
      segments={}
      polygons.each do |poly|
        poly.each_with_index do |a,i|
          b=poly[(i+1)%poly.length];dx=b[0]-a[0];dy=b[1]-a[1];len=dx*dx+dy*dy
          next if len<1e-14
          ts=[0.0,1.0]
          points.each do |p|
            t=((p[0]-a[0])*dx+(p[1]-a[1])*dy).to_f/len
            next unless t>1e-8 && t<1-1e-8
            ts << t if ((p[0]-a[0])*dy-(p[1]-a[1])*dx).abs/Math.sqrt(len)<1e-7
          end
          ts.sort.uniq.each_cons(2) do |l,r|
            next if r-l<1e-8
            p=[a[0]+l*dx,a[1]+l*dy];q=[a[0]+r*dx,a[1]+r*dy]
            key=[p.map{|v|v.round(7)},q.map{|v|v.round(7)}].sort
            segments[key] ? segments.delete(key) : segments[key]=[p,q]
          end
        end
      end
      segments.values
    end
    def boundary_loops(segments)
      key=->(p) { p.map { |v| v.round(7) } }
      remaining=segments.map { |a,b| [a,b] }
      loops=[]
      until remaining.empty?
        first=remaining.shift;loop=[first[0]];current=first[1]
        limit=remaining.length+2
        until key.call(current)==key.call(loop.first)
          loop << current
          index=remaining.index { |a,b| key.call(a)==key.call(current) }
          raise 'Biên dạng chưa kín; không tạo ván để tránh sinh cạnh thừa.' unless index
          current=remaining.delete_at(index)[1]
          raise 'Biên dạng tự giao.' if loop.length>limit
        end
        # Remove collinear segmentation inherited from clipped triangles.
        loop=loop.each_with_index.reject do |p,i|
          a=loop[(i-1)%loop.length];b=loop[(i+1)%loop.length]
          ((p[0]-a[0])*(b[1]-p[1])-(p[1]-a[1])*(b[0]-p[0])).abs<1e-8
        end.map(&:first)
        loops << loop if loop.length>=3
      end
      loops.sort_by { |poly| -area2(poly).abs }
    end
    def inside_polygon?(point,poly)
      x,y=point;inside=false
      poly.each_with_index do |a,i|
        b=poly[(i+1)%poly.length]
        next unless (a[1]>y)!=(b[1]>y)
        cross=a[0]+(y-a[1])*(b[0]-a[0]).to_f/(b[1]-a[1])
        inside=!inside if x<cross
      end
      inside
    end
    def compartment_pieces(pieces,point)
      loops=boundary_loops(boundary_segments(pieces))
      candidates=loops.select { |poly| area2(poly)>0 && inside_polygon?(point,poly) }
      outer=candidates.min_by { |poly| area2(poly).abs }
      raise 'Click vào phần lọt lòng trống trên Face, tránh phần đang tiếp xúc với tấm khác.' unless outer
      holes=loops.select { |poly| area2(poly)<0 && inside_polygon?(point,poly) }
      raise 'Điểm chọn nằm trên vùng tiếp xúc. Chọn phần trống trong khoang.' unless holes.empty?
      pieces.select do |poly|
        center=[poly.sum(&:first)/poly.length.to_f,poly.sum(&:last)/poly.length.to_f]
        inside_polygon?(center,outer)
      end
    end
    class Tool
      def activate
        @model=Sketchup.active_model; @context=@model.active_entities
        @edit=@model.edit_transform
        @ip=Sketchup::InputPoint.new
        @anchor_mode=0; @count=nil; @source=nil; @deltas=[]
        @typing=false; @skip_enter_until=0.0
        status
      end
      def enableVCB?; true; end
      def status
        label=['MÉP TRÁI / đầu','TÂM VÁN','MÉP PHẢI / cuối'][@anchor_mode]
        text=if !@source
          'CHIA VÁN LỌT LÒNG · Click mặt Face của tấm mẫu (Group/Component).'
        else
          mode=@count ? "/#{@count+1}: #{@count} ván mới · click tạo · ESC về tấm đơn" : 'Tấm đơn bám chuột · Click đặt · Nhập /2 chia đôi hoặc số mm đặt khoảng cách'
          hit=@clear ? "Lọt lòng #{(@clear*25.4).round(1)} mm" : 'Chưa gặp mặt chắn: /N chưa dùng được'
          "#{mode} · TAB: #{label} · #{hit}#{@error ? ' · '+@error : ''}"
        end
        Sketchup.set_status_text(text,SB_PROMPT)
        Sketchup.vcb_label='/ số khoang hoặc mm'
      end
      def pick_face(view,x,y)
        ph=view.pick_helper; ph.do_pick(x,y)
        ph.count.times do |i|
          path=ph.path_at(i); face=path && path.last
          next unless face.is_a?(Sketchup::Face)
          source=path.reverse.find { |e| DivideBoards.container?(e) }
          next unless source && source.valid?
          tr=@edit*ph.transformation_at(i)
          return [source,face,tr]
        end
        nil
      end
      def choose_sample(view,x,y)
        found=pick_face(view,x,y)
        raise 'Chọn mặt của tấm nằm trong Group/Component.' unless found
        @source,@face,@source_tr=found
        es=@source.definition.entities
        raise 'Chọn tấm ván riêng, không chọn cụm có nhóm con.' if es.any? { |e| DivideBoards.container?(e) }
        vertices=@face.outer_loop.vertices.map { |v| v.position.transform(@source_tr) }
        normal=vertices.each_cons(3).map { |a,b,c| (b-a).cross(c-a) }.find { |v| v.length>1e-8 }
        raise 'Face không có biên dạng hợp lệ.' unless normal
        raise 'Face không có biên dạng hợp lệ.' if normal.length<1e-8
        normal.normalize!
        all_points=es.grep(Sketchup::Face).flat_map { |f| f.vertices.map { |v| v.position.transform(@source_tr) } }
        distances=all_points.map { |v| (v-vertices[0]).dot(normal) }
        lo,hi=distances.minmax
        inward=hi.abs>lo.abs ? normal : normal.reverse
        @face_thickness=hi-lo
        raise 'Không nhận được độ dày tấm từ Face.' if @face_thickness<0.001
        back_vector=inward.clone;back_vector.length=@face_thickness
        @axes=[normal]
        @face_polygons=[]
        basis_x=(vertices[1]-vertices[0]).normalize
        basis_y=normal.cross(basis_x).normalize
        base=vertices[0]
        to2=->(p) { d=p-base;[d.dot(basis_x),d.dot(basis_y)] }
        to3=->(p) { base.offset(basis_x,p[0]).offset(basis_y,p[1]) }
        pieces=@face.mesh.polygons.map { |poly| poly.map { |i| to2.call(@face.mesh.point_at(i.abs).transform(@source_tr)) } }
        cutters=[]
        scan=lambda do |entities,tr,depth|
          raise 'Model lồng quá sâu.' if depth>64
          entities.each do |entity|
            next if entity.respond_to?(:visible?) && !entity.visible?
            next if entity.respond_to?(:layer) && !entity.layer.visible?
            if DivideBoards.container?(entity)
              wt=tr*entity.transformation
              next if entity==@source && wt.to_a.zip(@source_tr.to_a).all? { |x,y| (x-y).abs<1e-8 }
              scan.call(entity.definition.entities,wt,depth+1)
            elsif entity.is_a?(Sketchup::Face)
              pts=entity.vertices.map { |v| v.position.transform(tr) }
              next unless pts.all? { |p| (p-base).dot(normal).abs<0.1.mm }
              mesh=entity.mesh
              mesh.polygons.each { |poly| cutters << poly.map { |i| to2.call(mesh.point_at(i.abs).transform(tr)) } }
            end
          end
        end
        scan.call(@model.entities,Geom::Transformation.new,0)
        cutters.each do |cut|
          xs=cut.map(&:first);ys=cut.map(&:last)
          pieces=pieces.flat_map do |poly|
            px=poly.map(&:first);py=poly.map(&:last)
            if px.max<=xs.min+1e-8 || px.min>=xs.max-1e-8 || py.max<=ys.min+1e-8 || py.min>=ys.max-1e-8
              [poly]
            else
              DivideBoards.subtract_polygon(poly,cut)
            end
          end
          raise 'Biên dạng quá phức tạp; hãy chọn cụm nhỏ hơn.' if pieces.length>1000
        end
        raise 'Face mẫu bị che kín bởi các tấm tiếp xúc.' if pieces.empty?
        pieces.map! { |poly| DivideBoards.area2(poly)<0 ? poly.reverse : poly }
        ray=view.pickray(x,y)
        picked=Geom.intersect_line_plane(ray,[base,normal])
        raise 'Không xác định được điểm trong khoang.' unless picked
        pieces=DivideBoards.compartment_pieces(pieces,to2.call(picked))
        boundaries=DivideBoards.boundary_segments(pieces)
        loops=DivideBoards.boundary_loops(boundaries)
        @cap_loops=loops.map { |poly| [poly.map { |p| to3.call(p) },DivideBoards.area2(poly)>0] }
        boundaries=loops.flat_map { |poly| poly.each_with_index.map { |p,i| [p,poly[(i+1)%poly.length]] } }
        @back_vector=back_vector
        @cap_normal=inward.reverse
        @side_polygons=[]
        pieces.each do |poly|
          front=poly.map { |p| to3.call(p) }
          front.reverse! if (front[1]-front[0]).cross(front[2]-front[0]).dot(inward)>0
          @face_polygons << front
          @face_polygons << front.reverse.map { |v| v+back_vector }
        end
        @edges=[]
        boundaries.each do |a,b|
          v=to3.call(a);w=to3.call(b)
          v,w=w,v if normal.dot(inward)<0
          side=[v,w,w+back_vector,v+back_vector]
          @face_polygons << side
          @side_polygons << side
          @edges.concat([v,w,v+back_vector,w+back_vector,v,v+back_vector])
        end
        @corners=@face_polygons.flatten
        @center=Geom::Point3d.new(*3.times.map { |i| @corners.sum { |v| v.to_a[i] }/@corners.length.to_f })
        @triangles=@face_polygons.flat_map { |poly| (1...poly.length-1).flat_map { |i| [poly[0],poly[i],poly[i+1]] } }
        ray=view.pickray(x,y)
        local_ray=[ray[0].transform(@source_tr.inverse),ray[1].transform(@source_tr.inverse)]
        p=Geom.intersect_line_plane(local_ray,@face.plane)
        @origin=p ? p.transform(@source_tr) : @center
        @direction=nil; @count=nil; @distance=nil; @deltas=[]
        status
      rescue StandardError
        @source=nil
        raise
      end
      def choose_direction(view,x,y)
        screen=view.screen_coords(@origin)
        dx=x-screen.x;dy=y-screen.y
        return nil if Math.hypot(dx,dy)<5
        candidates=@axes.flat_map do |axis|
          [1,-1].map do |sign|
            v=axis.clone;v.reverse! if sign<0
            endpoint=view.screen_coords(@origin.offset(v,10.0))
            sx=endpoint.x-screen.x;sy=endpoint.y-screen.y
            length=Math.hypot(sx,sy)
            [length>0.01 ? (dx*sx+dy*sy)/length : -Float::INFINITY,v]
          end
        end
        candidates.max_by(&:first)[1]
      end
      def update_preview(view,x,y)
        @deltas=[];@error=nil
        return unless @source && @source.valid?
        @direction=choose_direction(view,x,y) unless @count || @distance
        return unless @direction
        projections=@corners.map { |p| (p-@center).dot(@direction) }
        @low,@high=projections.minmax
        @thickness=@high-@low
        @ray_start=@origin.offset(@direction,@high-(@origin-@center).dot(@direction))
        hit=@model.raytest([@ray_start.offset(@direction,0.001),@direction],true)
        @hit=hit && hit[0]
        @clear=@hit ? (@hit-@ray_start).dot(@direction) : nil
        if @count
          raise 'Chưa gặp mặt chắn theo hướng kéo. Rê về tấm đơn để chọn hướng khác.' unless @clear
          @deltas,@gap=DivideBoards.spacing(@clear,@thickness,@count)
        elsif @distance
          # Distance is measured from the selected face to the chosen new-board anchor.
          coordinate=(@origin-@center).dot(@direction)+@distance
          @deltas=[coordinate-DivideBoards.anchor_offset(@thickness,@anchor_mode)]
        else
          @ip.pick(view,x,y)
          if @ip.valid? && (@ip.vertex || @ip.edge || @ip.face)
            cursor=@ip.position
          else
            pair=Geom.closest_points([@origin,@direction],view.pickray(x,y))
            return unless pair
            cursor=pair[0]
          end
          coordinate=(cursor-@center).dot(@direction)
          shift=coordinate-DivideBoards.anchor_offset(@thickness,@anchor_mode)
          @deltas=[shift] if shift.abs>0.001
        end
      rescue StandardError=>e
        @deltas=[];@error=e.message
      ensure
        status
      end
      def onMouseMove(flags,x,y,view)
        @mouse=[x,y]
        if @source
          update_preview(view,x,y)
        else
          @hover_triangles=[]
          found=pick_face(view,x,y)
          if found
            source,face,tr=found
            mesh=face.mesh
            mesh.polygons.each do |poly|
              @hover_triangles.concat(poly.map { |i| mesh.point_at(i.abs).transform(tr) }) if poly.length==3
            end
          end
        end
        view.invalidate
      end
      def onLButtonDown(flags,x,y,view)
        if @source
          update_preview(view,x,y)
          create
        else
          choose_sample(view,x,y)
          @mouse=[x,y]
        end
        view.invalidate
      rescue StandardError=>e
        UI.messagebox(e.message)
      end
      def onUserText(text,view)
        @typing=false; @skip_enter_until=Time.now.to_f+0.25
        raise 'Chọn tấm mẫu và kéo hướng trước.' unless @source && @direction
        input=text.strip
        if input.start_with?('/')
          match=input.match(%r{\A/\s*(\d*)\s*\z})
          raise 'Nhập /2, /3... để chia số khoang.' unless match
          bays=match[1].empty? ? 2 : match[1].to_i
          bays=2 if bays==1
          raise 'Số khoang phải từ 2 đến 101.' unless bays.between?(2,101)
          raise 'Chưa có mặt chắn theo hướng kéo.' unless @clear
          DivideBoards.spacing(@clear,@thickness,bays-1)
          @count=bays-1;@distance=nil
        else
          mm=Float(input.tr(',','.'))
          raise 'Khoảng cách phải lớn hơn 0 mm.' unless mm.finite? && mm>0
          @distance=mm.mm;@count=nil
        end
        update_preview(view,*@mouse)
        Sketchup.vcb_value=input
        view.invalidate
      rescue StandardError=>e
        UI.messagebox(e.message)
      end
      def onKeyDown(key,repeat,flags,view)
        @typing=true if [191,111,47].include?(key) || key.between?(48,57) || key.between?(96,105)
        return if repeat.to_i>0
        if key==9 && @source
          @anchor_mode=(@anchor_mode+1)%3
          update_preview(view,*@mouse) if @mouse
        elsif key==13 && @source && !@typing && Time.now.to_f>@skip_enter_until
          create
        end
        view.invalidate
      rescue StandardError=>e
        UI.messagebox(e.message)
      end
      def onCancel(reason,view)
        if @count || @distance
          @count=nil;@distance=nil;@typing=false
          update_preview(view,*@mouse) if @mouse
        elsif @source
          @source=nil;@deltas=[];@direction=nil
        else
          @model.select_tool(nil)
        end
        status;view.invalidate
      end
      def draw(view)
        unless @source && @source.valid?
          if @hover_triangles && !@hover_triangles.empty?
            view.drawing_color=Sketchup::Color.new(255,155,65,120)
            view.draw(GL_TRIANGLES,@hover_triangles)
          end
          return
        end
        @deltas.each do |distance|
          transform=Geom::Transformation.translation(@direction.clone.tap { |v| v.length=distance.abs;v.reverse! if distance<0 })
          view.drawing_color=Sketchup::Color.new(255,180,195,100)
          view.draw(GL_TRIANGLES,@triangles.map { |p| p.transform(transform) })
          view.drawing_color=Sketchup::Color.new(210,95,120)
          view.line_width=2
          view.draw(GL_LINES,@edges.map { |p| p.transform(transform) })
        end
        if !@count && !@deltas.empty?
          anchor=@center.offset(@direction,@deltas.first+DivideBoards.anchor_offset(@thickness,@anchor_mode))
          view.draw_points([anchor],9,3,Sketchup::Color.new(20,140,240))
        end
        if @hit && @ray_start
          view.drawing_color=Sketchup::Color.new(235,130,25)
          view.line_stipple='-'
          view.draw(GL_LINES,[@ray_start,@hit])
          view.line_stipple=''
        end
        @ip.draw(view) if !@count && @ip.valid?
      end
      def create
        raise 'Chưa có preview hợp lệ. Kéo chuột hoặc kiểm tra khoảng lọt lòng.' if @deltas.empty? || @error
        raise 'Tấm mẫu đã bị xóa.' unless @source.valid?
        raise 'Nhóm đang chỉnh sửa đã thay đổi; mở lại công cụ.' unless @context==@model.active_entities
        started=false
        @model.start_operation('TRẦN TUẤN - Chia ván lọt lòng',true)
        started=true
        created=[]
        @deltas.each do |distance|
          vec=@direction.clone;vec.length=distance.abs;vec.reverse! if distance<0
          transform=@edit.inverse*Geom::Transformation.translation(vec)
          copy=@context.add_group
          # Build entire planar faces from boundary loops, never mesh triangles.
          [false,true].each do |back|
            @cap_loops.each do |points,outer|
              polygon=points.map { |v| (back ? v+@back_vector : v).transform(transform) }
              face=copy.entities.add_face(polygon)
              raise 'Không tạo được mặt theo vòng biên kín.' unless face
              unless outer
                face.erase!
                next
              end
              expected=(back ? @cap_normal.reverse : @cap_normal).transform(@edit.inverse)
              face.reverse! if face.normal.dot(expected)<0
            end
          end
          @side_polygons.each do |polygon|
            face=copy.entities.add_face(polygon.map { |v| v.transform(transform) })
            raise 'Không tạo được mặt cạnh ván.' unless face
          end
          copy.entities.grep(Sketchup::Edge).each do |edge|
            next unless edge.valid? && edge.faces.length==2
            a,b=edge.faces
            next unless a.normal.cross(b.normal).length<1e-8
            next unless b.vertices.all? { |v| v.position.distance_to_plane(a.plane).abs<1e-6 }
            edge.erase!
          end
          # Reverse the complete closed shell if its signed volume is inward.
          if copy.respond_to?(:volume) && copy.volume < 0
            copy.entities.grep(Sketchup::Face).each(&:reverse!)
          end
          copy.name=@source.name
          copy.layer=@source.layer
          copy.material=@source.material
          if @source.attribute_dictionaries
            @source.attribute_dictionaries.each do |dict|
              dict.each_pair { |k,v| copy.set_attribute(dict.name,k,v) }
            end
          end
          created << copy
        end
        @model.commit_operation;started=false
        @count=nil;@distance=nil;@deltas=[];@typing=false
        Sketchup.set_status_text("Đã tạo #{created.size} tấm. Tấm mẫu giữ nguyên. Rê chuột đặt tiếp hoặc ESC chọn mẫu khác.",SB_PROMPT)
      rescue StandardError
        @model.abort_operation if started
        raise
      end
      def deactivate(view);view.invalidate;end
    end
  end
end
