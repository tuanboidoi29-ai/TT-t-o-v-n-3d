module TranTuan
  module TaoVan
    module Drawer
      module_function
      TAB_KEY = 9
      DICT = 'TT_TaoVan_Drawer'

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
          'gap_top'=>m.get_attribute(DICT,'gap_top',2.0), 'gap_bottom'=>m.get_attribute(DICT,'gap_bottom',2.0),
          'gap_left'=>m.get_attribute(DICT,'gap_left',2.0), 'gap_right'=>m.get_attribute(DICT,'gap_right',2.0),
          'gap_front'=>m.get_attribute(DICT,'gap_front',2.0), 'gap_back'=>m.get_attribute(DICT,'gap_back',2.0),
          'side_t'=>m.get_attribute(DICT,'side_t',18.0), 'back_t'=>m.get_attribute(DICT,'back_t',9.0),
          'bottom_t'=>m.get_attribute(DICT,'bottom_t',9.0), 'front_t'=>m.get_attribute(DICT,'front_t',18.0)
        }
      end

      # Tạo Ngăn Kéo luôn vào AUTO. Không mở bảng cài đặt khi khởi động.
      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end

      def save_settings(vals)
        vals.each { |k,v| Sketchup.active_model.set_attribute(DICT,k,v.to_f) }
      end

      # TAB gọi hàm này trong khi công cụ AUTO đang hoạt động.
      def show_settings(tool=nil)
        d = defaults
        @dialog ||= UI::HtmlDialog.new(dialog_title:'TT - CÀI ĐẶT NGĂN KÉO', preferences_key:'TT_TaoVan_Drawer_Auto', scrollable:true, resizable:true, width:430, height:650, style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save_settings') do |_ctx, json|
          begin
            data = JSON.parse(json); vals = {}; data.each { |k,v| vals[k] = parse_mm(v) }
            raise 'Thông số phải là số mm không âm.' if vals.any? { |_k,v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Độ dày vật liệu phải lớn hơn 0.' if %w[side_t back_t bottom_t front_t].any? { |k| vals[k] <= 0 }
            save_settings(vals); @dialog.close
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
        labels={'gap_top'=>'Hở trên','gap_bottom'=>'Hở dưới','gap_left'=>'Hở trái','gap_right'=>'Hở phải','gap_front'=>'Hở trước','gap_back'=>'Hở sau','side_t'=>'Độ dày tấm hồi / hông','back_t'=>'Độ dày hậu','bottom_t'=>'Độ dày đáy','front_t'=>'Độ dày mặt trước'}
        rows=labels.map { |k,v| "<label>#{v}</label><input id='#{k}' value='#{d[k]}'>" }.join
        "<!doctype html><html><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'><h2>TT - CÀI ĐẶT NGĂN KÉO</h2><b>AUTO 2 ĐIỂM — ĐƠN VỊ mm</b><p>Hai điểm là hai góc đối diện bất kỳ. TAB mở bảng này; lưu xong quay lại AUTO.</p><div style='display:grid;grid-template-columns:1fr 90px;gap:8px;margin-top:15px'>#{rows}</div><button style='margin-top:18px;width:100%;padding:12px;background:#ff7a00;color:white;border:0' onclick='save()'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let ids=['gap_top','gap_bottom','gap_left','gap_right','gap_front','gap_back','side_t','back_t','bottom_t','front_t'];let o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.save_settings(JSON.stringify(o));}</script></body></html>"
      end

      class TwoPointTool
        def initialize(cfg)
          @cfg=cfg; @ip=Sketchup::InputPoint.new; @p1=nil; @container=nil; @preview=nil
        end
        def activate; status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 | TAB: CÀI ĐẶT | ESC: THOÁT'); end
        def deactivate(view); view.invalidate if view; end
        def apply_settings(c); @cfg=c; @p1=nil; @container=nil; @preview=nil; status('ĐÃ LƯU CÀI ĐẶT → AUTO: CLICK ĐIỂM 1'); end
        def onMouseMove(_f,x,y,v)
          @ip.pick(v,x,y); return unless @ip.valid?; p=@ip.position; @preview=@p1 ? [@p1,p] : [p]
          if @p1
            d=measure(@p1,p); status("VÙNG R #{mm_text(d[:w])} | S #{mm_text(d[:d])} | C #{mm_text(d[:h])} → NGĂN KÉO R #{mm_text(d[:dw])} | S #{mm_text(d[:dd])} | C #{mm_text(d[:dh])}")
          end
          v.invalidate
        end
        def onLButtonDown(_f,x,y,v)
          @ip.pick(v,x,y); return unless @ip.valid?; p=@ip.position
          if @p1.nil?; @p1=p; @container=container(@ip); status('ĐÃ NHẬN ĐIỂM 1 → CLICK ĐIỂM 2'); else create(p); end
          v.invalidate
        end
        def onKeyDown(k,*_args)
          return true if k==TAB_KEY && (Drawer.show_settings(self); true)
          return true if k==27 && (Sketchup.active_model.select_tool(nil); true)
          false
        end
        def draw(v)
          return unless @preview && !@preview.empty?; v.line_width=3; v.drawing_color=Sketchup::Color.new(255,128,0,255)
          if @preview.length==1
            p=@preview[0]; s=mm(12); v.draw(GL_LINES,Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z))
          else
            a,b=@preview; v.draw(GL_LINES,a,b)
          end
        end
        private
        def status(s); Sketchup.set_status_text('TT NGĂN KÉO AUTO | mm',SB_PROMPT); Sketchup.set_status_text(s,SB_VCB_LABEL); end
        def container(ip); p=ip.instance_path; return nil unless p; p.to_a.reverse.find{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)} end
        def local_points(a,b)
          return [a,b,nil] unless @container && @container.valid?
          tr=@container.transformation; [a.transform(tr.inverse),b.transform(tr.inverse),tr]
        end
        def measure(a,b)
          x,y,_tr=local_points(a,b); w=(x.x-y.x).abs.to_mm; d=(x.y-y.y).abs.to_mm; h=(x.z-y.z).abs.to_mm
          {w:w,d:d,h:h,dw:w-@cfg['gap_left']-@cfg['gap_right']-2*@cfg['side_t'],dd:d-@cfg['gap_front']-@cfg['gap_back']-@cfg['back_t'],dh:h-@cfg['gap_top']-@cfg['gap_bottom']}
        end
        def create(p2)
          d=measure(@p1,p2)
          if d.values_at(:dw,:dd,:dh).any?{|x|x<=0}; UI.messagebox("Vùng chọn không đủ kích thước.\n\nVùng: #{mm_text(d[:w])} × #{mm_text(d[:d])} × #{mm_text(d[:h])}"); return; end
          model=Sketchup.active_model; model.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            a,b,tr=local_points(@p1,p2); x=[a.x,b.x].min; y=[a.y,b.y].min; z=[a.z,b.z].min
            rw=mm(d[:dw]); rd=mm(d[:dd]); rh=mm(d[:dh]); side=mm(@cfg['side_t']); back=mm(@cfg['back_t']); bottom=mm(@cfg['bottom_t']); front=mm(@cfg['front_t'])
            left=mm(@cfg['gap_left']); fg=mm(@cfg['gap_front'])
            g=model.entities.add_group; g.name='TT - Ngăn kéo AUTO';
            add_part(g,'Hông trái',x+left,y+fg,z,side,rd,rh); add_part(g,'Hông phải',x+left+rw-side,y+fg,z,side,rd,rh)
            add_part(g,'Đáy',x+left,y+fg,z,rw,rd,bottom); add_part(g,'Mặt trước',x+left,y+fg,z,rw,front,rh); add_part(g,'Hậu',x+left,y+fg+rd-back,z,rw,back,rh)
            g.set_attribute(DICT,'don_vi','mm'); g.set_attribute(DICT,'vung_rong_mm',d[:w]); g.set_attribute(DICT,'vung_sau_mm',d[:d]); g.set_attribute(DICT,'vung_cao_mm',d[:h]); g.set_attribute(DICT,'rong_mm',d[:dw]); g.set_attribute(DICT,'sau_mm',d[:dd]); g.set_attribute(DICT,'cao_mm',d[:dh])
            g.transform!(tr) if tr
            model.commit_operation
            @p1=nil; @container=nil; @preview=nil; Sketchup.active_model.select_tool(self); status('ĐÃ TẠO → CLICK ĐIỂM 1 TIẾP');
          rescue => e
            model.abort_operation rescue nil; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          end
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