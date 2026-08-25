module TranTuan
  module TaoVan
    module Drawer
      module_function
      # Chuẩn hóa toàn bộ kích thước người dùng theo mm.
      def mm(v); v.to_f.mm; end
      def mm_text(v, decimals=1); format("%0.#{decimals}f mm", v.to_f); end
      def parse_mm(v)
        s=v.to_s.strip.downcase.gsub(',', '.')
        s=s.sub(/\s*mm\s*\z/,'')
        Float(s)
      rescue
        nil
      end
      def start; Sketchup.active_model.select_tool(TwoPointTool.new); end
      class TwoPointTool
        def initialize
          @ip=Sketchup::InputPoint.new; @p1=@p2=@container=@preview=nil
          @manual_mode=false; @manual_ready=false; @manual_origin=nil; @manual_values=nil
        end
        def activate; update_status; end
        def deactivate(view); @preview=nil; view.invalidate if view; end
        def onMouseMove(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?; p=@ip.position
          if @manual_mode
            @manual_origin ||= p; @preview=@manual_ready ? [@manual_origin,p] : [p]; view.invalidate; return
          end
          @preview=@p1 ? [@p1,p] : [p]; view.invalidate
          if @p1
            h_mm=(@p1.z-p.z).to_mm.abs
            Sketchup.set_status_text("TỰ ĐỘNG 2 ĐIỂM | ĐIỂM 1: MẶT TRÊN → ĐIỂM 2: ĐÁY | Cao: #{Drawer.mm_text(h_mm)} | ĐƠN VỊ: mm | TAB = THỦ CÔNG",SB_VCB_LABEL)
          end
        end
        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width=3; view.drawing_color=Sketchup::Color.new(255,128,0,255)
          if @manual_mode && @manual_ready && @manual_values
            ox=@manual_origin.x; oy=@manual_origin.y; oz=@manual_origin.z; w,d,h=@manual_values[0,3]
            draw_box(view,box_points(ox,oy,oz,Drawer.mm(w),Drawer.mm(d),Drawer.mm(h))); return
          end
          if @preview.length==1
            p=@preview[0]; s=Drawer.mm(12)
            view.draw(GL_LINES,Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z)); return
          end
          a,b=@preview; z0=[a.z,b.z].min; z1=[a.z,b.z].max; bb=(@container&&@container.valid?) ? @container.bounds : nil
          x0=bb ? bb.min.x : [a.x,b.x].min; x1=bb ? bb.max.x : [a.x,b.x].max; y0=bb ? bb.min.y : [a.y,b.y].min; y1=bb ? bb.max.y : [a.y,b.y].max
          draw_box(view,box_points(x0,y0,z0,x1-x0,y1-y0,z1-z0))
        end
        def onLButtonDown(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?; p=@ip.position
          if @manual_mode
            unless @manual_ready; @manual_origin=p; manual_create; return end
            create_manual_from_preview; return
          end
          if @p1.nil?
            @p1=p; @container=direct_container(@ip)
            unless @container; UI.messagebox('Điểm 1 phải nằm trên Face thuộc Group/Component của khoang tủ.'); reset; return end
            set_waiting_status('TỰ ĐỘNG 2 ĐIỂM','ĐIỂM 1 ĐÃ NHẬN → DI CHUỘT XUỐNG MẶT ĐÁY → CLICK ĐIỂM 2'); view.invalidate
          else @p2=p; create_from_two_points end
        end
        def onKeyDown(key,_repeat,_flags,view)
          if key==9; @manual_mode=!@manual_mode; clear_state; update_status; view.invalidate if view
          elsif key==27; Sketchup.active_model.select_tool(nil) end
        end
        private
        def set_waiting_status(mode,detail)
          Sketchup.set_status_text("TT NGĂN KÉO | CHẾ ĐỘ CHỜ | #{mode} | ĐƠN VỊ: mm | TAB = ĐỔI CHẾ ĐỘ",SB_PROMPT)
          Sketchup.set_status_text(detail,SB_VCB_LABEL)
        end
        def update_status
          if @manual_mode
            detail=@manual_ready ? 'ĐÃ NHẬP THÔNG SỐ (mm) → DI CHUỘT ĐỂ XEM PREVIEW → CLICK ĐỂ TẠO' : 'CLICK VỊ TRÍ ĐẶT → NHẬP THÔNG SỐ (mm) | TAB = TỰ ĐỘNG 2 ĐIỂM'
            set_waiting_status('THỦ CÔNG',detail)
          else set_waiting_status('TỰ ĐỘNG 2 ĐIỂM','CLICK 1 = MẶT TRÊN → CLICK 2 = ĐÁY | KÍCH THƯỚC: mm | TAB = THỦ CÔNG') end
        end
        def box_points(x,y,z,w,d,h)
          [Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z),Geom::Point3d.new(x,y,z+h),Geom::Point3d.new(x+w,y,z+h),Geom::Point3d.new(x+w,y+d,z+h),Geom::Point3d.new(x,y+d,z+h)]
        end
        def draw_box(view,pts); [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|view.draw(GL_LINES,pts[i],pts[j])}; end
        def direct_container(ip)
          path=ip.instance_path; return nil unless path&&path.respond_to?(:to_a)
          path.to_a.reverse_each{|e|return e if e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}; nil
        end
        def same_container?(a,b)
          return false unless a&&b&&a.valid?&&b.valid?; a.equal?(b)||(a.respond_to?(:persistent_id)&&b.respond_to?(:persistent_id)&&a.persistent_id==b.persistent_id)
        end
        def create_from_two_points
          model=Sketchup.active_model; z_top=@p1.z; z_bottom=@p2.z
          if z_top<=z_bottom; UI.messagebox('Sai thứ tự: ĐIỂM 1 phải ở MẶT TRÊN và ĐIỂM 2 phải ở ĐÁY.'); reset; return end
          h_mm=(z_top-z_bottom).to_mm.abs; if h_mm<=1; UI.messagebox('Chiều cao giữa điểm 1 và điểm 2 phải lớn hơn 1 mm.'); reset; return end
          c2=direct_container(@ip); unless same_container?(@container,c2); UI.messagebox('Điểm 2 phải nằm trên Face thuộc cùng Group/Component với điểm 1.'); reset; return end
          bb=@container.bounds; w_mm=bb.width.to_mm; d_mm=bb.depth.to_mm
          if w_mm<=1||d_mm<=1; UI.messagebox('Không xác định được Rộng/Sâu từ Group/Component.'); reset; return end
          create_drawer(model,bb.min.x,bb.min.y,z_bottom,w_mm,d_mm,h_mm,18,9,2,2)
        rescue=>e; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}"); reset end
        def manual_create
          prompts=['Rộng phủ bì (mm)','Sâu phủ bì (mm)','Cao ngăn kéo (mm)','Độ dày ván (mm)','Khe hở trái/phải (mm)','Khe hở trước/sau (mm)','Độ dày đáy (mm)','Đáy cách đáy hông (mm)']; defaults=[600,450,150,18,2,2,9,0]
          values=UI.inputbox(prompts,defaults,'TT - Tạo ngăn kéo thủ công | Đơn vị: mm'); return unless values
          vals=values.map{|v| Drawer.parse_mm(v)}
          unless vals.all?{|v|v.is_a?(Numeric)&&v.finite?} && [0,1,2,3,4,5,6].all?{|i| vals[i]>0 rescue false} && vals[7]>=0
            UI.messagebox('Thông số không hợp lệ. Tất cả kích thước phải nhập bằng mm. Ví dụ: 600 hoặc 600 mm.'); return
          end
          @manual_values=vals; @manual_ready=true; update_status
        end
        def create_manual_from_preview
          w,d,h,t,gl,gf,bt,bo=@manual_values; create_drawer(Sketchup.active_model,@manual_origin.x,@manual_origin.y,@manual_origin.z,w,d,h,t,bt,gl,gf,bo)
        end
        def create_drawer(model,ox,oy,oz,w_mm,d_mm,h_mm,t_mm,bt_mm,gl_mm,gf_mm,bo_mm=0)
          vals=[w_mm,d_mm,h_mm,t_mm,bt_mm,gl_mm,gf_mm,bo_mm].map(&:to_f); w_mm,d_mm,h_mm,t_mm,bt_mm,gl_mm,gf_mm,bo_mm=vals
          iw_mm=w_mm-2*t_mm-2*gl_mm; id_mm=d_mm-2*t_mm-2*gf_mm
          if iw_mm<=0||id_mm<=0||h_mm<=t_mm; UI.messagebox("Kích thước khoang không đủ cho ván #{t_mm.round(1)} mm và khe hở đã nhập. Đơn vị: mm"); reset; return end
          w=Drawer.mm(w_mm); d=Drawer.mm(d_mm); h=Drawer.mm(h_mm); t=Drawer.mm(t_mm); bt=Drawer.mm(bt_mm); gl=Drawer.mm(gl_mm); gf=Drawer.mm(gf_mm); bo=Drawer.mm(bo_mm); iw=Drawer.mm(iw_mm); id=Drawer.mm(id_mm)
          model.start_operation('TT - Tạo ngăn kéo',true); outer=model.entities.add_group; outer.name='TT - Ngăn kéo'
          add=lambda do|name,x,y,z,sx,sy,sz|; g=outer.entities.add_group; g.name=name; f=g.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+sx,y,z),Geom::Point3d.new(x+sx,y+sy,z),Geom::Point3d.new(x,y+sy,z)]); f.reverse! if f.normal.z<0; f.pushpull(sz); g end
          add.call('Đáy',ox+t+gl,oy+t+gf,oz+bo,iw,id,bt); add.call('Hông trái',ox,oy,oz,t,d,h); add.call('Hông phải',ox+w-t,oy,oz,t,d,h); add.call('Mặt trước',ox+t,oy+d-t,oz,iw+2*gl,t,h); add.call('Mặt sau',ox+t,oy,oz,iw+2*gl,t,h)
          outer.set_attribute('TT_TaoVan','loai','ngan_keo'); outer.set_attribute('TT_TaoVan','don_vi','mm'); outer.set_attribute('TT_TaoVan','tao_bang_2_diem',!@manual_mode); outer.set_attribute('TT_TaoVan','tao_thu_cong',@manual_mode); outer.set_attribute('TT_TaoVan','rong_mm',w_mm); outer.set_attribute('TT_TaoVan','sau_mm',d_mm); outer.set_attribute('TT_TaoVan','cao_mm',h_mm); outer.set_attribute('TT_TaoVan','day_mm',t_mm); outer.set_attribute('TT_TaoVan','day_da_mm',bt_mm)
          model.commit_operation; model.selection.clear; model.selection.add(outer); Sketchup.set_status_text("Đã tạo ngăn kéo: #{Drawer.mm_text(w_mm)} × #{Drawer.mm_text(d_mm)} × #{Drawer.mm_text(h_mm)}",SB_PROMPT); reset
        rescue=>e; model.abort_operation rescue nil; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}"); reset end
        def clear_state; @p1=@p2=@container=@preview=nil; @manual_ready=false; @manual_origin=nil; @manual_values=nil; end
        def reset; clear_state; update_status; end
      end
    end
  end
end