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
          mode=@count ? "/#{@count}: ENTER/click tạo dãy · ESC về tấm đơn" : 'Tấm đơn bám chuột · Click đặt · Nhập /N chia đều'
          hit=@clear ? "Lọt lòng #{(@clear*25.4).round(1)} mm" : 'Chưa gặp mặt chắn: /N chưa dùng được'
          "#{mode} · TAB: #{label} · #{hit}#{@error ? ' · '+@error : ''}"
        end
        Sketchup.set_status_text(text,SB_PROMPT)
        Sketchup.vcb_label='Chia /N'
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
        @center=@source.definition.bounds.center.transform(@source_tr)
        @corners=(0..7).map { |i| @source.definition.bounds.corner(i).transform(@source_tr) }
        @axes=[@source_tr.xaxis,@source_tr.yaxis,@source_tr.zaxis].map { |v| v.normalize }
        raise 'Tấm bị xiên trục (shear), chưa hỗ trợ chia chính xác.' if @axes.combination(2).any? { |a,b| a.dot(b).abs>1e-5 }
        @triangles=[]
        es.grep(Sketchup::Face).each do |f|
          mesh=f.mesh
          mesh.polygons.each do |poly|
            next unless poly.length==3
            @triangles.concat(poly.map { |idx| mesh.point_at(idx.abs).transform(@source_tr) })
          end
        end
        @edges=es.grep(Sketchup::Edge).flat_map { |e| [e.start.position.transform(@source_tr),e.end.position.transform(@source_tr)] }
        raise 'Tấm không có mặt để mô phỏng.' if @triangles.empty?
        ray=view.pickray(x,y)
        local_ray=[ray[0].transform(@source_tr.inverse),ray[1].transform(@source_tr.inverse)]
        p=Geom.intersect_line_plane(local_ray,@face.plane)
        @origin=p ? p.transform(@source_tr) : @center
        @direction=nil; @count=nil; @deltas=[]
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
        @direction=choose_direction(view,x,y) unless @count
        return unless @direction
        projections=@corners.map { |p| (p-@center).dot(@direction) }
        @low,@high=projections.minmax
        @thickness=@high-@low
        @ray_start=@center.offset(@direction,@high)
        hit=@model.raytest([@ray_start.offset(@direction,0.001),@direction],true)
        @hit=hit && hit[0]
        @clear=@hit ? (@hit-@ray_start).dot(@direction) : nil
        if @count
          raise 'Chưa gặp mặt chắn theo hướng kéo. Rê về tấm đơn để chọn hướng khác.' unless @clear
          @deltas,@gap=DivideBoards.spacing(@clear,@thickness,@count)
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
        match=text.strip.match(%r{\A/\s*(\d+)\z})
        raise 'Nhập /N, ví dụ /3 = ba tấm mới.' unless match
        n=match[1].to_i
        raise 'Chưa có mặt chắn theo hướng kéo.' unless @clear
        DivideBoards.spacing(@clear,@thickness,n)
        @count=n
        update_preview(view,*@mouse)
        Sketchup.vcb_value="/#{n}"
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
        if @count
          @count=nil;@typing=false
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
          transform=@edit.inverse*Geom::Transformation.translation(vec)*@source_tr
          if @source.is_a?(Sketchup::Group)
            copy=@context.add_group
            copy.entities.add_instance(@source.definition,Geom::Transformation.new).explode
            copy.transformation=transform
          else
            copy=@context.add_instance(@source.definition,transform)
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
        @count=nil;@deltas=[];@typing=false
        Sketchup.set_status_text("Đã tạo #{created.size} tấm. Tấm mẫu giữ nguyên. Rê chuột đặt tiếp hoặc ESC chọn mẫu khác.",SB_PROMPT)
      rescue StandardError
        @model.abort_operation if started
        raise
      end
      def deactivate(view);view.invalidate;end
    end
  end
end
