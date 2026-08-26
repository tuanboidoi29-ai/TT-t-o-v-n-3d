module TranTuan
  module TaoVan
    module Drawer
      module_function
      TAB_KEY = 9
      DICT = 'TT_TaoVan_Drawer'
      ZERO_TOL_MM = 0.5

      def mm(v); v.to_f.mm; end
      def mm_text(v); format('%.1f mm', v.to_f); end
      def parse_mm(v)
        Float(v.to_s.strip.downcase.gsub(',', '.').sub(/\s*mm\s*\z/, ''))
      rescue
        nil
      end

      def defaults
        m = Sketchup.active_model
        {
          # Khe công nghệ / ray: mặc định 14 mm MỖI BÊN.
          'rail_gap'=>m.get_attribute(DICT,'rail_gap',14.0),
          # Chừa phía trên: mặc định 20 mm.
          'gap_top'=>m.get_attribute(DICT,'gap_top',20.0),
          'gap_bottom'=>m.get_attribute(DICT,'gap_bottom',0.0),
          # Chừa trước/sau; chiều sâu tự động sẽ trừ depth_reserve.
          'gap_front'=>m.get_attribute(DICT,'gap_front',0.0),
          'depth_reserve'=>m.get_attribute(DICT,'depth_reserve',60.0),
          # Vật liệu.
          'side_t'=>m.get_attribute(DICT,'side_t',18.0),
          'back_t'=>m.get_attribute(DICT,'back_t',9.0),
          'bottom_t'=>m.get_attribute(DICT,'bottom_t',9.0),
          'front_t'=>m.get_attribute(DICT,'front_t',18.0)
        }
      end

      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end

      def save_settings(vals)
        vals.each { |k,v| Sketchup.active_model.set_attribute(DICT,k,v.to_f) }
      end

      def show_settings(tool=nil)
        d = defaults
        @dialog ||= UI::HtmlDialog.new(
          dialog_title:'TT - CÀI ĐẶT NGĂN KÉO AUTO',
          preferences_key:'TT_TaoVan_Drawer_Auto_v118',
          scrollable:true, resizable:true, width:450, height:680,
          style:UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save_settings') do |_ctx,json|
          begin
            data = JSON.parse(json)
            vals = {}
            data.each { |k,v| vals[k] = parse_mm(v) }
            raise 'Thông số phải là số mm không âm.' if vals.any? { |_,v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Độ dày vật liệu phải lớn hơn 0.' if %w[side_t back_t bottom_t front_t].any? { |k| vals[k] <= 0 }
            save_settings(vals)
            @dialog.close
            if tool
              tool.apply_settings(vals)
              Sketchup.active_model.select_tool(tool)
            else
              Sketchup.active_model.select_tool(TwoPointTool.new(vals))
            end
          rescue => e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end

      def settings_html(d)
        rows = [
          ['rail_gap','Khoảng hở ray mỗi bên',d['rail_gap']],
          ['gap_top','Hở trên',d['gap_top']],
          ['gap_bottom','Hở dưới',d['gap_bottom']],
          ['gap_front','Hở phía trước',d['gap_front']],
          ['depth_reserve','Chừa chiều sâu phía sau',d['depth_reserve']],
          ['side_t','Độ dày hông',d['side_t']],
          ['back_t','Độ dày hậu',d['back_t']],
          ['bottom_t','Độ dày đáy',d['bottom_t']],
          ['front_t','Độ dày mặt trước',d['front_t']]
        ].map { |k,v,n| "<label>#{v}</label><input id='#{k}' value='#{n}' style='width:95px;background:#252930;color:white;border:1px solid #444;border-radius:6px;padding:8px;text-align:right'>" }.join
        "<!doctype html><html><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'><h2 style='margin:0 0 6px'>TT - CÀI ĐẶT NGĂN KÉO AUTO</h2><div style='color:#ff9b43;font-weight:bold;margin-bottom:12px'>TAB = CÀI ĐẶT | AUTO 2 ĐIỂM | ĐƠN VỊ mm</div><div style='background:#242830;padding:10px;border-radius:8px;line-height:1.5'>Sau khi click điểm 2, hệ thống lấy <b>tổng Rộng × Cao</b> của vùng preview và tự quét <b>chiều sâu local</b> của Group/Component lớn nhất chứa điểm. Kích thước ngăn kéo được tính tự động, không lấy độ dày hông để trừ khỏi khoảng ray.</div><div style='display:grid;grid-template-columns:1fr 95px;gap:8px;align-items:center;margin-top:16px'>#{rows}</div><div style='font-size:12px;color:#9da3ad;margin-top:14px'>Ví dụ: vùng 300 mm → rộng ngăn kéo = 300 - 14 - 14 = 272 mm. Cao 300 mm → nếu hở trên 20 mm thì cao ngăn kéo = 280 mm. Sâu 300 mm → mặc định chừa 60 mm phía sau, sâu ngăn kéo = 240 mm.</div><button style='margin-top:18px;width:100%;padding:12px;background:#ff7a00;color:white;border:0;border-radius:8px;font-weight:bold' onclick='save()'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let ids=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','side_t','back_t','bottom_t','front_t'];let o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.save_settings(JSON.stringify(o));}</script></body></html>"
      end

      class TwoPointTool
        def initialize(cfg)
          @cfg = cfg
          @ip = Sketchup::InputPoint.new
          @p1 = nil
          @container = nil
          @preview = nil
          @preview_region = nil
          @preview_drawer = nil
        end

        def activate
          status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 | TAB: CÀI ĐẶT | ESC: THOÁT')
        end

        def deactivate(view); view.invalidate if view; end

        def apply_settings(c)
          @cfg = c
          @p1 = nil; @container = nil; @preview = nil; @preview_region = nil; @preview_drawer = nil
          status('ĐÃ LƯU CÀI ĐẶT → AUTO: CLICK ĐIỂM 1')
        end

        def onKeyDown(k,*_args)
          if k == TAB_KEY
            Drawer.show_settings(self); return true
          elsif k == 27
            Sketchup.active_model.select_tool(nil); return true
          end
          false
        end

        def onMouseMove(_f,x,y,v)
          @ip.pick(v,x,y)
          return unless @ip.valid?
          p = @ip.position
          @preview = @p1 ? [@p1,p] : [p]
          if @p1
            d = measure(@p1,p)
            @preview_region = region(@p1,p)
            @preview_drawer = drawer_preview(@preview_region,d)
            status("VÙNG #{Drawer.mm_text(d[:w])} × #{Drawer.mm_text(d[:d])} × #{Drawer.mm_text(d[:h])} → NGĂN KÉO #{Drawer.mm_text(d[:dw])} × #{Drawer.mm_text(d[:dd])} × #{Drawer.mm_text(d[:dh])} | RAY #{Drawer.mm_text(@cfg['rail_gap'])}/BÊN | SÂU CHỪA #{Drawer.mm_text(@cfg['depth_reserve'])}")
          end
          v.invalidate
        end

        def onLButtonDown(_f,x,y,v)
          @ip.pick(v,x,y); return unless @ip.valid?
          p = @ip.position
          if @p1.nil?
            @p1 = p
            @container = best_container(@ip)
            status('ĐÃ NHẬN ĐIỂM 1 → CLICK ĐIỂM 2 | HỆ THỐNG SẼ TỰ QUÉT RỘNG/Cao/SÂU')
          else
            create(p)
          end
          v.invalidate
        end

        def draw(v)
          return unless @preview && !@preview.empty?
          v.line_width = 3
          v.drawing_color = Sketchup::Color.new(255,128,0,255)
          if @preview.length == 1
            p=@preview[0]; s=Drawer.mm(12)
            v.draw(GL_LINES,Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z))
            return
          end
          r=@preview_drawer || @preview_region
          return unless r
          pts=box_points(r[:x],r[:y],r[:z],r[:w],r[:d],r[:h],r[:tr])
          v.drawing_color=Sketchup::Color.new(255,128,0,110)
          v.line_width=4
          edges=[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
          edges.each{|i,j|v.draw(GL_LINES,pts[i],pts[j])}
          v.line_width=1
        end

        private

        def status(s)
          Sketchup.set_status_text('TT NGĂN KÉO AUTO | mm',SB_PROMPT)
          Sketchup.set_status_text(s,SB_VCB_LABEL)
        end

        # Chọn container có không gian lớn nhất trong instance_path, tránh lấy nhầm
        # Group của một tấm ván mỏng làm "chiều sâu tủ".
        def best_container(ip)
          path=ip.instance_path
          return nil unless path
          candidates=path.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
          candidates.max_by do |e|
            bb=e.bounds
            bb.width.to_f*bb.depth.to_f*bb.height.to_f
          end
        rescue
          nil
        end

        def local_bounds
          return nil unless @container && @container.valid?
          bb=@container.bounds
          return nil if bb.empty?
          bb
        rescue
          nil
        end

        def local_points(a,b)
          return [a,b,nil] unless @container && @container.valid?
          tr=@container.transformation
          [a.transform(tr.inverse),b.transform(tr.inverse),tr]
        end

        def region(a,b)
          x,y,tr=local_points(a,b)
          xmin,xmax=[x.x,y.x].minmax
          zmin,zmax=[x.z,y.z].minmax
          ymin,ymax=[x.y,y.y].minmax
          inferred=false
          if (ymax-ymin).abs.to_mm < ZERO_TOL_MM
            bb=local_bounds
            if bb && bb.depth.to_mm > ZERO_TOL_MM
              ymin=bb.min.y; ymax=bb.max.y; inferred=true
            end
          end
          {x:xmin,y:ymin,z:zmin,w:xmax-xmin,d:ymax-ymin,h:zmax-zmin,tr:tr,inferred_depth:inferred}
        end

        def measure(a,b)
          r=region(a,b)
          w=r[:w].to_mm; d=r[:d].to_mm; h=r[:h].to_mm
          rail=@cfg['rail_gap'].to_f
          dw=w-(rail*2.0)
          dd=d-@cfg['depth_reserve'].to_f-@cfg['gap_front'].to_f
          dh=h-@cfg['gap_top'].to_f-@cfg['gap_bottom'].to_f
          {w:w,d:d,h:h,dw:dw,dd:dd,dh:dh,inferred_depth:r[:inferred_depth]}
        end

        def drawer_preview(r,d)
          return nil if d[:dw] <= 0 || d[:dd] <= 0 || d[:dh] <= 0
          side=Drawer.mm(@cfg['rail_gap'])
          {x:r[:x]+side.mm,y:r[:y]+Drawer.mm(@cfg['gap_front']),z:r[:z]+Drawer.mm(@cfg['gap_bottom']),w:Drawer.mm(d[:dw]),d:Drawer.mm(d[:dd]),h:Drawer.mm(d[:dh]),tr:r[:tr]}
        end

        def create(p2)
          d=measure(@p1,p2)
          if d.values_at(:dw,:dd,:dh).any?{|x|x<=0}
            UI.messagebox("Không đủ không gian để tạo ngăn kéo.\n\nVùng quét: #{Drawer.mm_text(d[:w])} × #{Drawer.mm_text(d[:d])} × #{Drawer.mm_text(d[:h])}\nKích thước ngăn kéo: #{Drawer.mm_text(d[:dw])} × #{Drawer.mm_text(d[:dd])} × #{Drawer.mm_text(d[:dh])}\n\nRay: #{Drawer.mm_text(@cfg['rail_gap'])}/bên | Chừa sâu: #{Drawer.mm_text(@cfg['depth_reserve'])}")
            return
          end

          m=Sketchup.active_model
          m.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            r=region(@p1,p2)
            rw=Drawer.mm(d[:dw]); rd=Drawer.mm(d[:dd]); rh=Drawer.mm(d[:dh])
            side_t=Drawer.mm(@cfg['side_t']); back=Drawer.mm(@cfg['back_t']); bottom=Drawer.mm(@cfg['bottom_t']); front=Drawer.mm(@cfg['front_t'])
            x=r[:x]+Drawer.mm(@cfg['rail_gap']); y=r[:y]+Drawer.mm(@cfg['gap_front']); z=r[:z]+Drawer.mm(@cfg['gap_bottom'])
            g=m.entities.add_group; g.name='TT - Ngăn kéo AUTO'
            add_part(g,'Hông trái',x,y,z,side_t,rd,rh)
            add_part(g,'Hông phải',x+rw-side_t,y,z,side_t,rd,rh)
            add_part(g,'Đáy',x,y,z,rw,rd,bottom)
            add_part(g,'Mặt trước',x,y,z,rw,front,rh)
            add_part(g,'Hậu',x,y+rd-back,z,rw,back,rh)
            g.set_attribute(DICT,'don_vi','mm')
            g.set_attribute(DICT,'vung_rong_mm',d[:w]); g.set_attribute(DICT,'vung_sau_mm',d[:d]); g.set_attribute(DICT,'vung_cao_mm',d[:h])
            g.set_attribute(DICT,'rong_mm',d[:dw]); g.set_attribute(DICT,'sau_mm',d[:dd]); g.set_attribute(DICT,'cao_mm',d[:dh])
            g.set_attribute(DICT,'ray_moi_ben_mm',@cfg['rail_gap'].to_f); g.set_attribute(DICT,'cho_sau_mm',@cfg['depth_reserve'].to_f); g.set_attribute(DICT,'chieu_sau_tu_dong',!!d[:inferred_depth])
            g.transform!(r[:tr]) if r[:tr]
            m.commit_operation
            @p1=nil; @container=nil; @preview=nil; @preview_region=nil; @preview_drawer=nil
            Sketchup.active_model.select_tool(self); status('ĐÃ TẠO → CLICK ĐIỂM 1 TIẾP')
          rescue=>e
            m.abort_operation rescue nil
            UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          end
        end

        def box_points(x,y,z,w,d,h,tr)
          p=[Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z),Geom::Point3d.new(x,y,z+h),Geom::Point3d.new(x+w,y,z+h),Geom::Point3d.new(x+w,y+d,z+h),Geom::Point3d.new(x,y+d,z+h)]
          tr ? p.map{|q|q.transform(tr)} : p
        end

        def add_part(g,name,x,y,z,w,d,h)
          return if w<=0 || d<=0 || h<=0
          p=g.entities.add_group; p.name=name
          f=p.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z)])
          f.pushpull(h) if f
        end
      end
    end
  end
end