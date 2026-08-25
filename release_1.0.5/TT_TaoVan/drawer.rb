module TranTuan
  module TaoVan
    module Drawer
      module_function

      # TT - Tạo ngăn kéo 2 điểm hoàn toàn tự động.
      # Click 1: điểm trên / mặt trên.
      # Click 2: điểm dưới / đáy.
      # Group/Component chứa điểm được dùng để tự lấy Rộng + Sâu.
      # Chiều cao được lấy từ khoảng cách Z giữa 2 điểm.
      # Mặc định: ván 18 mm, đáy 9 mm.
      def start
        Sketchup.active_model.select_tool(TwoPointTool.new)
      end

      class TwoPointTool
        def initialize
          @ip=Sketchup::InputPoint.new
          @p1=nil; @p2=nil; @container=nil; @preview=nil
        end

        def activate
          Sketchup.set_status_text('TT Ngăn kéo: CLICK 1 = MẶT TRÊN',SB_PROMPT)
          Sketchup.set_status_text('CLICK 2 = ĐÁY → tự động tạo ngăn kéo',SB_VCB_LABEL)
        end

        def deactivate(view); @preview=nil; view.invalidate if view end

        def onMouseMove(_flags,x,y,view)
          @ip.pick(view,x,y)
          return unless @ip.valid?
          p=@ip.position
          @preview=@p1 ? [@p1,p] : [p]
          view.invalidate
          if @p1
            h=(@p1.z-p.z).abs.to_mm
            Sketchup.set_status_text("CLICK 2 = ĐÁY | Cao: #{h.round(1)} mm",SB_VCB_LABEL)
          end
        end

        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width=3
          view.drawing_color=Sketchup::Color.new(255,128,0,255)
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
          pts=[
            Geom::Point3d.new(x0,y0,z0),Geom::Point3d.new(x1,y0,z0),Geom::Point3d.new(x1,y1,z0),Geom::Point3d.new(x0,y1,z0),
            Geom::Point3d.new(x0,y0,z1),Geom::Point3d.new(x1,y0,z1),Geom::Point3d.new(x1,y1,z1),Geom::Point3d.new(x0,y1,z1)
          ]
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|view.draw(GL_LINES,pts[i],pts[j])}
        end

        def onLButtonDown(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?
          p=@ip.position
          if @p1.nil?
            @p1=p
            @container=direct_container(@ip)
            Sketchup.set_status_text('ĐIỂM 1 OK → CLICK 2 = ĐÁY',SB_PROMPT)
            view.invalidate
          else
            @p2=p
            create_from_two_points
          end
        end

        def onKeyDown(key,_repeat,_flags,_view)
          Sketchup.active_model.select_tool(nil) if key==27
        end

        private

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

        def create_drawer(model,ox,oy,oz,w,d,h,t,bt,gl,gf)
          iw=w-2*t-2*gl; id=d-2*t-2*gf
          if iw<=0 || id<=0 || h<=t
            UI.messagebox("Kích thước khoang không đủ cho ván 18 mm và khe hở 2 mm.")
            reset; return
          end

          model.start_operation('TT - Tạo ngăn kéo 2 điểm',true)
          outer=model.entities.add_group
          outer.name='TT - Ngăn kéo'
          add=lambda do |name,x,y,z,sx,sy,sz|
            g=outer.entities.add_group; g.name=name
            f=g.entities.add_face([
              Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+sx,y,z),
              Geom::Point3d.new(x+sx,y+sy,z),Geom::Point3d.new(x,y+sy,z)])
            f.reverse! if f.normal.z<0
            f.pushpull(sz); g
          end
          add.call('Đáy',ox+t+gl,oy+t+gf,oz,iw,id,bt)
          add.call('Hông trái',ox,oy,oz,t,d,h)
          add.call('Hông phải',ox+w-t,oy,oz,t,d,h)
          add.call('Mặt trước',ox+t,oy+d-t,oz,iw+2*gl,t,h)
          add.call('Mặt sau',ox+t,oy,oz,iw+2*gl,t,h)
          outer.set_attribute('TT_TaoVan','loai','ngan_keo')
          outer.set_attribute('TT_TaoVan','tao_bang_2_diem',true)
          outer.set_attribute('TT_TaoVan','rong_mm',w)
          outer.set_attribute('TT_TaoVan','sau_mm',d)
          outer.set_attribute('TT_TaoVan','cao_mm',h)
          outer.set_attribute('TT_TaoVan','day_mm',t)
          outer.set_attribute('TT_TaoVan','day_da_mm',bt)
          model.commit_operation
          model.selection.clear; model.selection.add(outer)
          Sketchup.set_status_text("Đã tạo ngăn kéo: #{w.round(1)} × #{d.round(1)} × #{h.round(1)} mm",SB_PROMPT)
          reset
        rescue
          model.abort_operation rescue nil
          raise
        end

        def reset
          @p1=nil; @p2=nil; @container=nil; @preview=nil
          Sketchup.set_status_text('TT Ngăn kéo: CLICK 1 = MẶT TRÊN',SB_PROMPT)
        end
      end
    end
  end
end
