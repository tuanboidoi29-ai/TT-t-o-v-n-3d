module TranTuan
  module TaoVan
    module Drawer
      module_function

      # TT - Tạo ngăn kéo: 2 điểm tự động + thủ công.
      # TAB chuyển chế độ: TỰ ĐỘNG 2 ĐIỂM <-> THỦ CÔNG.
      def start
        Sketchup.active_model.select_tool(TwoPointTool.new)
      end

      class TwoPointTool
        def initialize
          @ip=Sketchup::InputPoint.new
          @p1=nil; @p2=nil; @container=nil; @preview=nil
          @manual_mode=false
          @manual_ready=false
          @manual_origin=nil
          @manual_values=nil
        end

        def activate
          update_status
        end

        def deactivate(view)
          @preview=nil
          view.invalidate if view
        end

        def onMouseMove(_flags,x,y,view)
          @ip.pick(view,x,y)
          return unless @ip.valid?
          p=@ip.position

          if @manual_mode
            @manual_origin ||= p
            if @manual_ready && @manual_values
              @preview=[@manual_origin,p]
              view.invalidate
            else
              @preview=[p]
              view.invalidate
            end
            return
          end

          @preview=@p1 ? [@p1,p] : [p]
          view.invalidate
          if @p1
            h=(@p1.z-p.z).abs.to_mm
            Sketchup.set_status_text("CLICK 2 = ĐÁY | Cao: #{h.round(1)} mm | TAB = THỦ CÔNG",SB_VCB_LABEL)
          end
        end

        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width=3
          view.drawing_color=Sketchup::Color.new(255,128,0,255)

          if @manual_mode && @manual_ready && @manual_values
            ox=@manual_origin.x; oy=@manual_origin.y; oz=@manual_origin.z
            w,d,h=@manual_values[0..2].map{|v| v.mm}
            pts=box_points(ox,oy,oz,w,d,h)
            [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|view.draw(GL_LINES,pts[i],pts[j])}
            return
          end

          if @preview.length==1
            p=@preview[0]; s=12.mm
            view.draw(GL_LINES,
              Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),
              Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z))
            return
          end

          a,b=@preview
          z0=[a.z,b.z].min; z1=[a.z,b.z].max
          bb=(@container && @container.valid?) ? @container.bounds : nil
          if bb
            x0=bb.min.x; x1=bb.max.x; y0=bb.min.y; y1=bb.max.y
          else
            x0=[a.x,b.x].min; x1=[a.x,b.x].max; y0=[a.y,b.y].min; y1=[a.y,b.y].max
          end
          pts=box_points(x0,y0,z0,x1-x0,y1-y0,z1-z0)
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|view.draw(GL_LINES,pts[i],pts[j])}
        end

        def onLButtonDown(_flags,x,y,view)
          @ip.pick(view,x,y)
          return unless @ip.valid?
          p=@ip.position

          if @manual_mode
            if !@manual_ready
              @manual_origin=p
              manual_create
              return
            end
            create_manual_from_preview
            return
          end

          if @p1.nil?
            @p1=p
            @container=direct_container(@ip)
            Sketchup.set_status_text('ĐIỂM 1 OK → CLICK 2 = ĐÁY | TAB = THỦ CÔNG',SB_PROMPT)
            view.invalidate
          else
            @p2=p
            create_from_two_points
          end
        end

        def onKeyDown(key,_repeat,_flags,view)
          # TAB = chuyển giữa 2 chế độ, không dùng phím M nữa.
          if key == 9
            @manual_mode=!@manual_mode
            clear_state
            update_status
            view.invalidate if view
          elsif key == 27
            Sketchup.active_model.select_tool(nil)
          end
        end

        private

        def update_status
          if @manual_mode
            if @manual_ready
              Sketchup.set_status_text('TT Ngăn kéo: THỦ CÔNG | CLICK để ĐẶT NGĂN KÉO | TAB = TỰ ĐỘNG',SB_PROMPT)
              Sketchup.set_status_text('Preview 3D màu cam đang hiển thị',SB_VCB_LABEL)
            else
              Sketchup.set_status_text('TT Ngăn kéo: THỦ CÔNG | CLICK để nhập thông số | TAB = TỰ ĐỘNG',SB_PROMPT)
              Sketchup.set_status_text('Rộng / Sâu / Cao / Dày ván / Khe hở / Đáy',SB_VCB_LABEL)
            end
          else
            Sketchup.set_status_text('TT Ngăn kéo: TỰ ĐỘNG | CLICK 1 = MẶT TRÊN | TAB = THỦ CÔNG',SB_PROMPT)
            Sketchup.set_status_text('CLICK 2 = ĐÁY → tự động tạo ngăn kéo',SB_VCB_LABEL)
          end
        end

        def box_points(x,y,z,w,d,h)
          [
            Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z),
            Geom::Point3d.new(x,y,z+h),Geom::Point3d.new(x+w,y,z+h),Geom::Point3d.new(x+w,y+d,z+h),Geom::Point3d.new(x,y+d,z+h)
          ]
        end

        def direct_container(ip)
          path=ip.instance_path
          return nil unless path && path.respond_to?(:to_a)
          path.to_a.reverse_each do |e|
            return e if e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)
          end
          nil
        end

        def create_from_two_points
          model=Sketchup.active_model
          z_top=[@p1.z,@p2.z].max; z_bottom=[@p1.z,@p2.z].min
          h=(z_top-z_bottom).abs.to_mm
          if h<=1.0
            UI.messagebox('Điểm 1 phải ở MẶT TRÊN và điểm 2 ở ĐÁY.')
            reset; return
          end
          unless @container && @container.valid?
            UI.messagebox('Hãy click điểm 1 và điểm 2 trên cùng Group/Component của khoang tủ để hệ thống tự lấy Rộng + Sâu.')
            reset; return
          end
          bb=@container.bounds
          w=bb.width.to_mm; d=bb.depth.to_mm
          if w<=1 || d<=1
            UI.messagebox('Không xác định được Rộng/Sâu từ Group/Component.')
            reset; return
          end
          create_drawer(model,bb.min.x,bb.min.y,z_bottom,w,d,h,18,9,2,2)
        rescue => e
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          reset
        end

        # Thủ công: click điểm đặt trước, nhập thông số, sau đó preview 3D và click lần nữa để tạo.
        def manual_create
          prompts=['Rộng phủ bì (mm)','Sâu phủ bì (mm)','Cao ngăn kéo (mm)','Độ dày ván (mm)','Khe hở trái/phải (mm)','Khe hở trước/sau (mm)','Độ dày đáy (mm)','Đáy cách đáy hông (mm)']
          defaults=[600,450,150,18,2,2,9,0]
          values=UI.inputbox(prompts,defaults,'TT - Tạo ngăn kéo thủ công')
          return unless values
          w,d,h,t,gl,gf,bt,bo=values.map(&:to_f)
          unless [w,d,h,t,bt].all?{|v| v.finite? && v>0} && [gl,gf,bo].all?{|v| v.finite? && v>=0}
            UI.messagebox('Thông số không hợp lệ.'); return
          end
          @manual_values=[w,d,h,t,gl,gf,bt,bo]
          @manual_ready=true
          update_status
        rescue => e
          UI.messagebox("Không thể nhập thông số ngăn kéo:\n#{e.message}")
        end

        def create_manual_from_preview
          return unless @manual_ready && @manual_origin && @manual_values
          w,d,h,t,gl,gf,bt,bo=@manual_values
          create_drawer(Sketchup.active_model,@manual_origin.x,@manual_origin.y,@manual_origin.z,w,d,h,t,bt,gl,gf,bo)
        end

        def create_drawer(model,ox,oy,oz,w,d,h,t,bt,gl,gf,bo=0)
          iw=w-2*t-2*gl; id=d-2*t-2*gf
          if iw<=0 || id<=0 || h<=t
            UI.messagebox("Kích thước khoang không đủ cho ván #{t.round(1)} mm và khe hở đã nhập.")
            reset; return
          end
          model.start_operation('TT - Tạo ngăn kéo',true)
          outer=model.entities.add_group
          outer.name='TT - Ngăn kéo'
          add=lambda do |name,x,y,z,sx,sy,sz|
            g=outer.entities.add_group; g.name=name
            f=g.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+sx,y,z),Geom::Point3d.new(x+sx,y+sy,z),Geom::Point3d.new(x,y+sy,z)])
            f.reverse! if f.normal.z<0
            f.pushpull(sz); g
          end
          add.call('Đáy',ox+t+gl,oy+t+gf,oz+bo,iw,id,bt)
          add.call('Hông trái',ox,oy,oz,t,d,h)
          add.call('Hông phải',ox+w-t,oy,oz,t,d,h)
          add.call('Mặt trước',ox+t,oy+d-t,oz,iw+2*gl,t,h)
          add.call('Mặt sau',ox+t,oy,oz,iw+2*gl,t,h)
          outer.set_attribute('TT_TaoVan','loai','ngan_keo')
          outer.set_attribute('TT_TaoVan','tao_bang_2_diem',!@manual_mode)
          outer.set_attribute('TT_TaoVan','tao_thu_cong',@manual_mode)
          outer.set_attribute('TT_TaoVan','rong_mm',w); outer.set_attribute('TT_TaoVan','sau_mm',d); outer.set_attribute('TT_TaoVan','cao_mm',h); outer.set_attribute('TT_TaoVan','day_mm',t); outer.set_attribute('TT_TaoVan','day_da_mm',bt)
          model.commit_operation
          model.selection.clear; model.selection.add(outer)
          Sketchup.set_status_text("Đã tạo ngăn kéo: #{w.round(1)} × #{d.round(1)} × #{h.round(1)} mm",SB_PROMPT)
          reset
        rescue
          model.abort_operation rescue nil
          raise
        end

        def clear_state
          @p1=nil; @p2=nil; @container=nil; @preview=nil; @manual_ready=false; @manual_origin=nil; @manual_values=nil
        end

        def reset
          clear_state
          update_status
        end
      end
    end
  end
end
