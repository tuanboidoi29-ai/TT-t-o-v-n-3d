module TranTuan
  module TaoVan
    module Drawer
      module_function

      # TT - Tạo ngăn kéo theo 2 điểm
      # Click 1 = điểm trên / mặt trên
      # Click 2 = điểm dưới / đáy
      # Hệ thống lấy Group/Component chứa 2 điểm để suy ra rộng + sâu.
      # Chiều cao = khoảng cách Z giữa 2 điểm.
      def start
        Sketchup.active_model.select_tool(TwoPointTool.new)
      end

      class TwoPointTool
        def initialize
          @ip = Sketchup::InputPoint.new
          @p1 = nil
          @p2 = nil
          @container = nil
          @preview = nil
        end

        def activate
          Sketchup.set_status_text('TT Ngăn kéo: CLICK ĐIỂM 1 = MẶT TRÊN', SB_PROMPT)
          Sketchup.set_status_text('Chọn điểm trên trước, sau đó chọn điểm đáy.', SB_VCB_LABEL)
        end

        def deactivate(view)
          @preview = nil
          view.invalidate if view
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p = @ip.position
          @preview = if @p1
                        [@p1, p]
                      else
                        [p]
                      end
          view.invalidate
          if @p1
            h = (@p1.z - p.z).abs.to_mm
            Sketchup.set_status_text("Điểm 2 = ĐÁY | Cao preview: #{h.round(1)} mm", SB_VCB_LABEL)
          end
        end

        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(255, 128, 0, 255)
          if @preview.length == 1
            p = @preview[0]
            s = 12
            view.draw(GL_LINES,
              Geom::Point3d.new(p.x-s.mm,p.y,p.z), Geom::Point3d.new(p.x+s.mm,p.y,p.z),
              Geom::Point3d.new(p.x,p.y-s.mm,p.z), Geom::Point3d.new(p.x,p.y+s.mm,p.z))
          else
            a,b=@preview
            x0=[a.x,b.x].min; x1=[a.x,b.x].max
            y0=[a.y,b.y].min; y1=[a.y,b.y].max
            z0=[a.z,b.z].min; z1=[a.z,b.z].max
            # Preview khung đứng màu cam; nếu 2 điểm thẳng đứng thì mở rộng theo container.
            bb = container_bounds_at(a)
            if bb
              x0=bb.min.x; x1=bb.max.x
              y0=bb.min.y; y1=bb.max.y
            end
            pts=[
              Geom::Point3d.new(x0,y0,z0),Geom::Point3d.new(x1,y0,z0),
              Geom::Point3d.new(x1,y1,z0),Geom::Point3d.new(x0,y1,z0),
              Geom::Point3d.new(x0,y0,z1),Geom::Point3d.new(x1,y0,z1),
              Geom::Point3d.new(x1,y1,z1),Geom::Point3d.new(x0,y1,z1)
            ]
            edges=[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
            edges.each{|i,j| view.draw(GL_LINES,pts[i],pts[j])}
          end
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p=@ip.position
          if @p1.nil?
            @p1=p
            @container=direct_container(@ip)
            Sketchup.set_status_text('ĐIỂM 1 OK → CLICK ĐIỂM 2 = ĐÁY', SB_PROMPT)
            view.invalidate
            return
          end

          @p2=p
          create_from_two_points(view)
        end

        def onKeyDown(key, _repeat, _flags, _view)
          return unless key == 27
          Sketchup.active_model.select_tool(nil)
        end

        private

        def direct_container(ip)
          ph=Sketchup.active_model.active_view.pick_helper
          return nil unless ph
          path=ip.instance_path
          return nil unless path && path.respond_to?(:to_a)
          path.to_a.reverse_each do |e|
            return e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          end
          nil
        end

        def container_bounds_at(p)
          return @container.bounds if @container && @container.valid?
          nil
        end

        def create_from_two_points(view)
          model=Sketchup.active_model
          z_top=[@p1.z,@p2.z].max
          z_bottom=[@p1.z,@p2.z].min
          h=(z_top-z_bottom).abs.to_mm
          if h <= 1.0
            UI.messagebox('Hai điểm phải tạo thành chiều cao lớn hơn 1 mm.')
            reset
            return
          end

          bb=(@container && @container.valid?) ? @container.bounds : nil
          if bb
            w=bb.width.to_mm
            d=bb.depth.to_mm
            ox=bb.min.x
            oy=bb.min.y
          else
            # Không có Group/Component: cho phép nhập rộng/sâu để vẫn tạo được.
            vals=UI.inputbox(['Rộng ngăn kéo (mm)','Sâu ngăn kéo (mm)','Độ dày ván (mm)','Độ dày đáy (mm)'],[600,450,18,9],'TT - Tạo ngăn kéo 2 điểm')
            unless vals; reset; return end
            w,d,t,bt=vals.map(&:to_f)
            create_drawer(model,ox_from_points,oy_from_points,z_bottom,w,d,h,t,bt)
            return
          end

          prompts=['Độ dày ván (mm)','Độ dày đáy (mm)','Khe hở trái/phải (mm)','Khe hở trước/sau (mm)']
          vals=UI.inputbox(prompts,[18,9,2,2],'TT - Tạo ngăn kéo 2 điểm')
          unless vals; reset; return end
          t,bt,gl,gf=vals.map(&:to_f)
          gl=0 if gl<0; gf=0 if gf<0
          create_drawer(model,bb.min.x,bb.min.y,z_bottom,w,d,h,t,bt,gl,gf)
        rescue => e
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          reset
        end

        def ox_from_points; @p1.x; end
        def oy_from_points; @p1.y; end

        def create_drawer(model,ox,oy,oz,w,d,h,t,bt,gl=0,gf=0)
          raise 'Rộng/Sâu/Độ dày không hợp lệ.' if w<=0 || d<=0 || t<=0 || bt<=0
          iw=w-2*t-2*gl
          id=d-2*t-2*gf
          raise 'Kích thước không đủ so với độ dày ván/khe hở.' if iw<=0 || id<=0 || h<=t

          model.start_operation('TT - Tạo ngăn kéo 2 điểm',true)
          outer=model.entities.add_group
          outer.name='TT - Ngăn kéo'

          add=lambda do |name,x,y,z,sx,sy,sz|
            g=outer.entities.add_group
            g.name=name
            pts=[Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+sx,y,z),Geom::Point3d.new(x+sx,y+sy,z),Geom::Point3d.new(x,y+sy,z)]
            f=g.entities.add_face(pts)
            f.reverse! if f.normal.z<0
            f.pushpull(sz)
            g
          end

          add.call('Đáy',ox+t+gl,oy+t+gf,oz,iw,id,bt)
          add.call('Hông trái',ox,oy,oz,t,d,h)
          add.call('Hông phải',ox+w-t,oy,oz,t,d,h)
          add.call('Mặt trước',ox+t,oy+d-t,oz,iw+2*gl,t,h)
          add.call('Mặt sau',ox+t,oy,oz,iw+2*gl,t,h)

          outer.set_attribute('TT_TaoVan','loai','ngan_keo')
          outer.set_attribute('TT_TaoVan','rong_mm',w)
          outer.set_attribute('TT_TaoVan','sau_mm',d)
          outer.set_attribute('TT_TaoVan','cao_mm',h)
          outer.set_attribute('TT_TaoVan','day_mm',t)
          outer.set_attribute('TT_TaoVan','day_da_mm',bt)
          outer.set_attribute('TT_TaoVan','tao_bang_2_diem',true)
          outer.set_attribute('TT_TaoVan','diem_tren_z',oz+h)
          outer.set_attribute('TT_TaoVan','diem_day_z',oz)

          model.commit_operation
          model.selection.clear
          model.selection.add(outer)
          UI.messagebox("Đã tạo ngăn kéo theo 2 điểm.\nCao: #{h.round(1)} mm\nRộng: #{w.round(1)} mm\nSâu: #{d.round(1)} mm")
          reset
        rescue
          model.abort_operation rescue nil
          raise
        end

        def reset
          @p1=nil; @p2=nil; @container=nil; @preview=nil
          Sketchup.set_status_text('TT Ngăn kéo: CLICK ĐIỂM 1 = MẶT TRÊN',SB_PROMPT)
        end
      end
    end
  end
end
