module TranTuan
  module TaoVan
    module Drawer
      module_function
      TAB_KEY = 9
      DICT = 'TT_TaoVan_Drawer'

      def mm(v); v.to_f.mm; end
      def mm_text(v, d=1); format("%0.#{d}f mm", v.to_f); end
      def parse_mm(v)
        s=v.to_s.strip.downcase.gsub(',', '.').sub(/\s*mm\s*\z/,''); Float(s)
      rescue; nil end

      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end

      def defaults
        m=Sketchup.active_model
        {'gap_top'=>m.get_attribute(DICT,'gap_top',2.0),'gap_bottom'=>m.get_attribute(DICT,'gap_bottom',2.0),'gap_left'=>m.get_attribute(DICT,'gap_left',2.0),'gap_right'=>m.get_attribute(DICT,'gap_right',2.0),'gap_front'=>m.get_attribute(DICT,'gap_front',2.0),'gap_back'=>m.get_attribute(DICT,'gap_back',2.0),'side_t'=>m.get_attribute(DICT,'side_t',18.0),'back_t'=>m.get_attribute(DICT,'back_t',9.0),'bottom_t'=>m.get_attribute(DICT,'bottom_t',9.0),'front_t'=>m.get_attribute(DICT,'front_t',18.0)}
      end

      def save_settings(h); m=Sketchup.active_model; h.each{|k,v|m.set_attribute(DICT,k,v.to_f)} end

      def show_settings(tool=nil)
        @dialog ||= UI::HtmlDialog.new(dialog_title:'TT - CÀI ĐẶT NGĂN KÉO',preferences_key:'TT_TaoVan_Drawer_Auto',scrollable:true,resizable:true,width:430,height:650,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(settings_html(defaults))
        @dialog.add_action_callback('start_auto') do |_ctx,json|
          begin
            data=JSON.parse(json); vals={}; data.each{|k,v| vals[k]=parse_mm(v)}
            raise 'Thông số phải là số mm không âm.' if vals.any?{|_,v|!v.is_a?(Numeric)||!v.finite?||v<0}
            raise 'Độ dày phải lớn hơn 0.' if vals['side_t']<=0||vals['back_t']<=0||vals['bottom_t']<=0||vals['front_t']<=0
            save_settings(vals); @dialog.close
            if tool.is_a?(TwoPointTool); tool.update_config(vals); Sketchup.active_model.select_tool(tool); else Sketchup.active_model.select_tool(TwoPointTool.new(vals)); end
          rescue=>e; UI.messagebox("Thông số không hợp lệ:\n#{e.message}") end
        end
        @dialog.show
      end

      def settings_html(d)
        labels={'gap_top'=>'Hở trên','gap_bottom'=>'Hở dưới','gap_left'=>'Hở trái','gap_right'=>'Hở phải','gap_front'=>'Hở trước','gap_back'=>'Hở sau','side_t'=>'Độ dày tấm hồi / hông','back_t'=>'Độ dày hậu','bottom_t'=>'Độ dày đáy','front_t'=>'Độ dày mặt trước'}
        fields=labels.map{|id,l|"<label>#{l}</label><input id='#{id}' class='field' value='#{d[id]}' />"}.join
        <<~HTML
        <!doctype html><html><head><meta charset='utf-8'><style>*{box-sizing:border-box}body{margin:0;background:#17191d;color:#eee;font:14px Arial}.wrap{padding:18px}.title{font-size:20px;font-weight:700}.sub{color:#9da3ad;margin:5px 0 16px}.mode{background:#ff7a00;padding:10px;border-radius:8px;font-weight:700}.section{font-weight:700;color:#ff9b43;margin:14px 0 8px}.grid{display:grid;grid-template-columns:1fr 90px;gap:8px;align-items:center}label{color:#d7d9dd}.field{width:100%;background:#252930;border:1px solid #3b4049;color:#fff;border-radius:6px;padding:8px;text-align:right}.hint{font-size:12px;color:#9298a2;line-height:1.45;margin-top:12px}.btn{width:100%;border:0;border-radius:8px;background:#ff7a00;color:#fff;padding:12px;font-weight:700;font-size:15px;cursor:pointer;margin-top:16px}</style></head><body><div class='wrap'><div class='title'>TT - CÀI ĐẶT NGĂN KÉO</div><div class='sub'>Mở bảng này bằng phím TAB trong chế độ AUTO</div><div class='mode'>AUTO — CLICK 2 ĐIỂM CHÉO BẤT KỲ</div><div class='section'>Khe hở & độ dày</div><div class='grid'>#{fields}</div><div class='hint'>Đơn vị: mm. Cài đặt được lưu cho lần sử dụng sau.</div><button class='btn' onclick='save()'>LƯU CÀI ĐẶT</button><script>function save(){const ids=#{labels.keys.to_a.to_json};const o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.start_auto(JSON.stringify(o));}</script></div></body></html>
        HTML
      end

      class TwoPointTool
        def initialize(cfg); @cfg=cfg; @ip=Sketchup::InputPoint.new; @p1=nil; @preview=nil; @container=nil; end
        def update_config(cfg); @cfg=cfg; end
        def activate; status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 | TAB: CÀI ĐẶT | ESC: THOÁT'); end
        def deactivate(v); v.invalidate if v; end
        def onMouseMove(_f,x,y,v)
          @ip.pick(v,x,y); return unless @ip.valid?; p=@ip.position; @preview=@p1 ? [@p1,p] : [p]
          if @p1; d=measure(@p1,p); status("VÙNG R #{mm_text(d[:w])} | S #{mm_text(d[:d])} | C #{mm_text(d[:h])} → NGĂN KÉO R #{mm_text(d[:dw])} | S #{mm_text(d[:dd])} | C #{mm_text(d[:dh])}") end
          v.invalidate
        end
        def draw(v)
          return unless @preview&&@preview.any?; v.line_width=3; v.drawing_color=Sketchup::Color.new(255,128,0,255)
          if @preview.length==1; s=mm(12);q=@preview[0];v.draw(GL_LINES,Geom::Point3d.new(q.x-s,q.y,q.z),Geom::Point3d.new(q.x+s,q.y,q.z),Geom::Point3d.new(q.x,q.y-s,q.z),Geom::Point3d.new(q.x,q.y+s,q.z)); else a,b=@preview; pts=box_points([a.x,b.x].min,[a.y,b.y].min,[a.z,b.z].min,(a.x-b.x).abs,(a.y-b.y).abs,(a.z-b.z).abs); draw_box(v,pts); end
        end
        def onLButtonDown(_f,x,y,v)
          @ip.pick(v,x,y); return unless @ip.valid?; p=@ip.position
          if @p1.nil?; @p1=p; @container=top_container(@ip); status('ĐÃ NHẬN ĐIỂM 1 → CLICK ĐIỂM 2'); else; create_drawer(p); end
        end
        def onKeyDown(key,_r,_f,_v)
          if key==TAB_KEY; Drawer.show_settings(self); elsif key==27; Sketchup.active_model.select_tool(nil); end
        end
        private
        def status(s); Sketchup.set_status_text('TT NGĂN KÉO AUTO | ĐƠN VỊ: mm',SB_PROMPT); Sketchup.set_status_text(s,SB_VCB_LABEL); end
        def top_container(ip); path=ip.instance_path; return nil unless path&&path.respond_to?(:to_a); path.to_a.reverse_each{|e|return e if e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}; nil end
        def measure(a,b)
          if @container&&@container.valid?; tr=@container.transformation;x=a.transform(tr.inverse);y=b.transform(tr.inverse);w=(x.x-y.x).abs.to_mm;d=(x.y-y.y).abs.to_mm;h=(x.z-y.z).abs.to_mm; else w=(a.x-b.x).abs.to_mm;d=(a.y-b.y).abs.to_mm;h=(a.z-b.z).abs.to_mm; end
          {w:w,d:d,h:h,dw:w-@cfg['gap_left']-@cfg['gap_right']-2*@cfg['side_t'],dd:d-@cfg['gap_front']-@cfg['gap_back']-@cfg['back_t'],dh:h-@cfg['gap_top']-@cfg['gap_bottom']}
        end
        def create_drawer(p2)
          d=measure(@p1,p2); if d[:dw]<=0||d[:dd]<=0||d[:dh]<=@cfg['bottom_t']; UI.messagebox('Vùng chọn không đủ kích thước.'); return; end
          m=Sketchup.active_model;m.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            g=m.entities.add_group;g.name='TT - Ngăn kéo AUTO'; add_box(g,'Hông trái',@cfg['side_t'],d[:dd],d[:dh]); add_box(g,'Hông phải',@cfg['side_t'],d[:dd],d[:dh]); add_box(g,'Đáy',d[:dw],d[:dd],@cfg['bottom_t']); add_box(g,'Mặt trước',d[:dw],@cfg['front_t'],d[:dh]); add_box(g,'Hậu',d[:dw],@cfg['back_t'],d[:dh]); g.set_attribute(DICT,'don_vi','mm'); m.commit_operation
          rescue=>e; m.abort_operation rescue nil; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}"); end
          @p1=nil;@preview=nil;@container=nil;status('ĐÃ TẠO NGĂN KÉO → TIẾP TỤC: CLICK ĐIỂM 1')
        end
        def add_box(g,name,w,d,h); return if w.to_f<=0||d.to_f<=0||h.to_f<=0; p=g.entities.add_group;p.name=name;f=p.entities.add_face([[0,0,0],[w.mm,0,0],[w.mm,d.mm,0],[0,d.mm,0]]);f.pushpull(h.mm) if f; end
        def box_points(x,y,z,w,d,h);[Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z),Geom::Point3d.new(x,y,z+h),Geom::Point3d.new(x+w,y,z+h),Geom::Point3d.new(x+w,y+d,z+h),Geom::Point3d.new(x,y+d,z+h)] end
        def draw_box(v,p);[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|v.draw(GL_LINES,p[i],p[j])} end
      end
    end
  end
end