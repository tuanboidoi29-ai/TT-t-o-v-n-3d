module TranTuan
  module TaoVan
    module Drawer
      module_function

      TAB_KEY = 9
      DICT = 'TT_TaoVan_Drawer'

      def mm(v); v.to_f.mm; end
      def mm_text(v, decimals = 1); format("%0.#{decimals}f mm", v.to_f); end
      def parse_mm(v)
        s = v.to_s.strip.downcase.gsub(',', '.')
        s = s.sub(/\s*mm\s*\z/, '')
        Float(s)
      rescue
        nil
      end

      def start
        show_settings
      end

      def defaults
        model = Sketchup.active_model
        {
          'gap_top' => model.get_attribute(DICT, 'gap_top', 2.0),
          'gap_bottom' => model.get_attribute(DICT, 'gap_bottom', 2.0),
          'gap_left' => model.get_attribute(DICT, 'gap_left', 2.0),
          'gap_right' => model.get_attribute(DICT, 'gap_right', 2.0),
          'gap_front' => model.get_attribute(DICT, 'gap_front', 2.0),
          'gap_back' => model.get_attribute(DICT, 'gap_back', 2.0),
          'side_t' => model.get_attribute(DICT, 'side_t', 18.0),
          'back_t' => model.get_attribute(DICT, 'back_t', 9.0),
          'bottom_t' => model.get_attribute(DICT, 'bottom_t', 9.0),
          'front_t' => model.get_attribute(DICT, 'front_t', 18.0)
        }
      end

      def save_settings(h)
        m = Sketchup.active_model
        h.each { |k, v| m.set_attribute(DICT, k, v.to_f) }
      end

      def show_settings
        @dialog ||= UI::HtmlDialog.new(
          dialog_title: 'TT - TẠO NGĂN KÉO TỰ ĐỘNG',
          preferences_key: 'TT_TaoVan_Drawer_Auto',
          scrollable: true,
          resizable: true,
          width: 430,
          height: 650,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(settings_html(defaults))
        @dialog.add_action_callback('start_auto') do |_ctx, json|
          begin
            data = JSON.parse(json)
            vals = {}
            data.each { |k, v| vals[k] = parse_mm(v) }
            bad = vals.any? { |_k, v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Thông số phải là số mm không âm.' if bad
            raise 'Độ dày phải lớn hơn 0.' if vals['side_t'] <= 0 || vals['back_t'] <= 0 || vals['bottom_t'] <= 0 || vals['front_t'] <= 0
            save_settings(vals)
            @dialog.close
            Sketchup.active_model.select_tool(TwoPointTool.new(vals))
          rescue => e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end

      def settings_html(d)
        esc = ->(v) { v.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;') }
        <<~HTML
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          *{box-sizing:border-box}body{margin:0;background:#17191d;color:#eee;font:14px Arial,sans-serif}
          .wrap{padding:18px}.title{font-size:20px;font-weight:700;margin-bottom:4px}.sub{color:#9da3ad;margin-bottom:16px}
          .mode{background:#ff7a00;color:#fff;padding:10px 12px;border-radius:8px;font-weight:700;margin-bottom:14px}
          .section{font-weight:700;color:#ff9b43;margin:14px 0 8px}.grid{display:grid;grid-template-columns:1fr 90px;gap:8px;align-items:center}
          label{color:#d7d9dd}.field{width:100%;background:#252930;border:1px solid #3b4049;color:#fff;border-radius:6px;padding:8px;text-align:right}
          .hint{font-size:12px;color:#9298a2;line-height:1.45;margin-top:12px}.btn{width:100%;border:0;border-radius:8px;background:#ff7a00;color:#fff;padding:12px;font-weight:700;font-size:15px;cursor:pointer;margin-top:16px}
          .btn:hover{background:#ff8b22}.sep{height:1px;background:#30343b;margin:14px 0}
        </style></head><body><div class="wrap">
        <div class="title">TT - TẠO NGĂN KÉO</div>
        <div class="sub">Tự động tính kích thước từ 2 điểm chéo</div>
        <div class="mode">CHẾ ĐỘ AUTO — CHỈ CẦN CLICK 2 ĐIỂM</div>
        <div class="section">Khe hở</div>
        <div class="grid">
          <label>Hở trên</label><input id="gap_top" class="field" value="#{esc.call(d['gap_top'])}">
          <label>Hở dưới</label><input id="gap_bottom" class="field" value="#{esc.call(d['gap_bottom'])}">
          <label>Hở trái</label><input id="gap_left" class="field" value="#{esc.call(d['gap_left'])}">
          <label>Hở phải</label><input id="gap_right" class="field" value="#{esc.call(d['gap_right'])}">
          <label>Hở trước</label><input id="gap_front" class="field" value="#{esc.call(d['gap_front'])}">
          <label>Hở sau</label><input id="gap_back" class="field" value="#{esc.call(d['gap_back'])}">
        </div>
        <div class="sep"></div>
        <div class="section">Độ dày vật liệu</div>
        <div class="grid">
          <label>Độ dày tấm hồi / hông</label><input id="side_t" class="field" value="#{esc.call(d['side_t'])}">
          <label>Độ dày hậu</label><input id="back_t" class="field" value="#{esc.call(d['back_t'])}">
          <label>Độ dày đáy</label><input id="bottom_t" class="field" value="#{esc.call(d['bottom_t'])}">
          <label>Độ dày mặt trước</label><input id="front_t" class="field" value="#{esc.call(d['front_t'])}">
        </div>
        <div class="hint">Đơn vị: mm. Hai điểm có thể nằm chéo nhau bất kỳ trong vùng cần tạo. Hệ thống lấy chênh lệch X/Y/Z theo trục local của Group/Component nếu bắt được; sau đó tự trừ khe hở và độ dày.</div>
        <button class="btn" onclick="start()">BẮT ĐẦU TẠO NGĂN KÉO AUTO</button>
        <script>
          function start(){const ids=['gap_top','gap_bottom','gap_left','gap_right','gap_front','gap_back','side_t','back_t','bottom_t','front_t'];const o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.start_auto(JSON.stringify(o));}
        </script></div></body></html>
        HTML
      end

      class TwoPointTool
        def initialize(cfg)
          @cfg = cfg
          @ip = Sketchup::InputPoint.new
          @p1 = nil
          @p2 = nil
          @container = nil
          @preview = nil
          @dims = nil
        end

        def activate
          set_status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 CHÉO NHAU BẤT KỲ')
        end

        def deactivate(view)
          view.invalidate if view
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p = @ip.position
          @preview = @p1 ? [@p1, p] : [p]
          if @p1
            dims = measure(@p1, p)
            @dims = dims
            set_status("VÙNG: R #{mm_text(dims[:w])} | S #{mm_text(dims[:d])} | C #{mm_text(dims[:h])} → NGĂN KÉO: R #{mm_text(dims[:dw])} | S #{mm_text(dims[:dd])} | C #{mm_text(dims[:dh])}")
          end
          view.invalidate
        end

        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(255, 128, 0, 255)
          if @preview.length == 1
            p=@preview[0]; s=Drawer.mm(12)
            view.draw(GL_LINES, Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z))
            return
          end
          a,b=@preview
          if @container && @container.valid?
            tr=@container.transformation; la=a.transform(tr.inverse); lb=b.transform(tr.inverse)
            pts=box_points([la.x,lb.x].min,[la.y,lb.y].min,[la.z,lb.z].min,(la.x-lb.x).abs,(la.y-lb.y).abs,(la.z-lb.z).abs).map{|q|q.transform(tr)}
          else
            pts=box_points([a.x,b.x].min,[a.y,b.y].min,[a.z,b.z].min,(a.x-b.x).abs,(a.y-b.y).abs,(a.z-b.z).abs)
          end
          draw_box(view,pts)
        end

        def onLButtonDown(_flags,x,y,view)
          @ip.pick(view,x,y)
          return unless @ip.valid?
          p=@ip.position
          if @p1.nil?
            @p1=p
            @container=top_container(@ip)
            set_status('ĐÃ NHẬN ĐIỂM 1 — DI CHUỘT VÀ CLICK ĐIỂM 2 CHÉO NHAU BẤT KỲ')
            view.invalidate
          else
            @p2=p
            create_drawer
          end
        end

        def onKeyDown(key,_repeat,_flags,_view)
          Sketchup.active_model.select_tool(nil) if key==27
        end

        private

        def set_status(text)
          Sketchup.set_status_text('TT NGĂN KÉO AUTO | ĐƠN VỊ: mm', SB_PROMPT)
          Sketchup.set_status_text(text, SB_VCB_LABEL)
        end

        def top_container(ip)
          path=ip.instance_path
          return nil unless path && path.respond_to?(:to_a)
          path.to_a.each{|e| return e if e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
          nil
        end

        def measure(a,b)
          if @container && @container.valid?
            tr=@container.transformation; x=a.transform(tr.inverse); y=b.transform(tr.inverse)
            w=(x.x-y.x).abs*unit_scale(tr,0)*25.4
            d=(x.y-y.y).abs*unit_scale(tr,1)*25.4
            h=(x.z-y.z).abs*unit_scale(tr,2)*25.4
          else
            w=(a.x-b.x).abs.to_mm; d=(a.y-b.y).abs.to_mm; h=(a.z-b.z).abs.to_mm
          end
          dw=w-@cfg['gap_left']-@cfg['gap_right']-2.0*@cfg['side_t']
          dd=d-@cfg['gap_front']-@cfg['gap_back']-@cfg['back_t']
          dh=h-@cfg['gap_top']-@cfg['gap_bottom']
          {w:w,d:d,h:h,dw:dw,dd:dd,dh:dh}
        end

        def unit_scale(tr,axis)
          v=[[1,0,0],[0,1,0],[0,0,1]][axis]
          Geom::Vector3d.new(*v).transform(tr).length
        end

        def create_drawer
          dims=measure(@p1,@p2)
          if dims[:dw] <= 0 || dims[:dd] <= 0 || dims[:dh] <= @cfg['bottom_t']
            UI.messagebox("Vùng chọn không đủ kích thước sau khi trừ khe hở/độ dày.\n\nVùng: #{mm_text(dims[:w])} × #{mm_text(dims[:d])} × #{mm_text(dims[:h])}\nNgăn kéo: #{mm_text(dims[:dw])} × #{mm_text(dims[:dd])} × #{mm_text(dims[:dh])}")
            return
          end

          model=Sketchup.active_model
          model.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            if @container && @container.valid?
              tr=@container.transformation; a=@p1.transform(tr.inverse); b=@p2.transform(tr.inverse)
              ox=[a.x,b.x].min; oy=[a.y,b.y].min; oz=[a.z,b.z].min
              rw=[a.x,b.x].max-[a.x,b.x].min; rd=[a.y,b.y].max-[a.y,b.y].min; rh=[a.z,b.z].max-[a.z,b.z].min
              create_local(model,tr,ox,oy,oz,rw,rd,rh,dims)
            else
              ox=[@p1.x,@p2.x].min; oy=[@p1.y,@p2.y].min; oz=[@p1.z,@p2.z].min
              rw=(@p1.x-@p2.x).abs; rd=(@p1.y-@p2.y).abs; rh=(@p1.z-@p2.z).abs
              create_world(model,ox,oy,oz,rw,rd,rh,dims)
            end
            model.commit_operation
            model.selection.clear
            model.selection.add(@last_group) if @last_group && @last_group.valid?
            set_status("ĐÃ TẠO: R #{mm_text(dims[:dw])} | S #{mm_text(dims[:dd])} | C #{mm_text(dims[:dh])}")
          rescue => e
            model.abort_operation rescue nil
            UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          ensure
            Sketchup.active_model.select_tool(nil)
          end
        end

        def create_local(model,tr,ox,oy,oz,rw,rd,rh,dims)
          sx=unit_scale(tr,0); sy=unit_scale(tr,1); sz=unit_scale(tr,2)
          left=Drawer.mm(@cfg['gap_left'])/sx; right=Drawer.mm(@cfg['gap_right'])/sx
          top=Drawer.mm(@cfg['gap_top'])/sz; bottom=Drawer.mm(@cfg['gap_bottom'])/sz
          front_gap=Drawer.mm(@cfg['gap_front'])/sy; rear_gap=Drawer.mm(@cfg['gap_back'])/sy
          side=Drawer.mm(@cfg['side_t'])/sx; back=Drawer.mm(@cfg['back_t'])/sy; bt=Drawer.mm(@cfg['bottom_t'])/sz; ft=Drawer.mm(@cfg['front_t'])/sy
          dw=rw-left-right-2*side; dd=rd-front_gap-rear_gap-back; dh=rh-top-bottom
          make_parts(model,ox+left+side,oy+front_gap,oz+bottom,rw,rd,rh,dw,dd,dh,side,back,bt,ft,tr)
        end

        def create_world(model,ox,oy,oz,rw,rd,rh,dims)
          left=Drawer.mm(@cfg['gap_left']); right=Drawer.mm(@cfg['gap_right']); top=Drawer.mm(@cfg['gap_top']); bottom=Drawer.mm(@cfg['gap_bottom'])
          fg=Drawer.mm(@cfg['gap_front']); rg=Drawer.mm(@cfg['gap_back']); side=Drawer.mm(@cfg['side_t']); back=Drawer.mm(@cfg['back_t']); bt=Drawer.mm(@cfg['bottom_t']); ft=Drawer.mm(@cfg['front_t'])
          dw=rw-left-right-2*side; dd=rd-fg-rg-back; dh=rh-top-bottom
          make_parts(model,ox+left+side,oy+fg,oz+bottom,rw,rd,rh,dw,dd,dh,side,back,bt,ft,nil)
        end

        def make_parts(model,ox,oy,oz,rw,rd,rh,dw,dd,dh,side,back,bt,ft,tr)
          g=model.entities.add_group; g.name='TT - Ngăn kéo AUTO'; @last_group=g
          add=lambda do |name,x,y,z,sx,sy,sz|
            return if sx<=0||sy<=0||sz<=0
            part=g.entities.add_group; part.name=name
            f=part.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+sx,y,z),Geom::Point3d.new(x+sx,y+sy,z),Geom::Point3d.new(x,y+sy,z)])
            f.pushpull(sz) if f
          end
          # Kích thước thực tế đã trừ toàn bộ khe hở. Hông dùng đúng độ dày tấm hồi.
          add.call('Hông trái',ox-side,oy,oz,side,dd,dh)
          add.call('Hông phải',ox+dw,oy,oz,side,dd,dh)
          add.call('Đáy',ox,oy,oz,dw,dd,bt)
          add.call('Mặt trước',ox,oy,oz,dw,ft,dh)
          add.call('Hậu',ox,oy+dd-back,oz,dw,back,dh)
          g.set_attribute(DICT,'loai','ngan_keo_auto')
          g.set_attribute(DICT,'don_vi','mm')
          g.set_attribute(DICT,'vung_rong_mm',rw.to_f*25.4)
          g.set_attribute(DICT,'vung_sau_mm',rd.to_f*25.4)
          g.set_attribute(DICT,'vung_cao_mm',rh.to_f*25.4)
          g.set_attribute(DICT,'rong_ngan_keo_mm',dw.to_f*25.4)
          g.set_attribute(DICT,'sau_ngan_keo_mm',dd.to_f*25.4)
          g.set_attribute(DICT,'cao_ngan_keo_mm',dh.to_f*25.4)
          g.set_attribute(DICT,'ho_tren_mm',@cfg['gap_top']); g.set_attribute(DICT,'ho_duoi_mm',@cfg['gap_bottom'])
          g.set_attribute(DICT,'ho_trai_mm',@cfg['gap_left']); g.set_attribute(DICT,'ho_phai_mm',@cfg['gap_right'])
          g.set_attribute(DICT,'day_hong_mm',@cfg['side_t']); g.set_attribute(DICT,'day_hau_mm',@cfg['back_t']); g.set_attribute(DICT,'day_day_mm',@cfg['bottom_t'])
          g.transform!(tr) if tr
        end

        def box_points(x,y,z,w,d,h)
          [Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z),Geom::Point3d.new(x,y,z+h),Geom::Point3d.new(x+w,y,z+h),Geom::Point3d.new(x+w,y+d,z+h),Geom::Point3d.new(x,y+d,z+h)]
        end

        def draw_box(view,p)
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|view.draw(GL_LINES,p[i],p[j])}
        end
      end
    end
  end
end
