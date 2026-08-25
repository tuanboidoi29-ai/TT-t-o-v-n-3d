module TranTuan
  module TaoVan
    module Drawer
      module_function
      DICT = 'TT_TaoVan_Drawer'
      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end
      def defaults
        m=Sketchup.active_model
        {'gap_top'=>m.get_attribute(DICT,'gap_top',2.0),'gap_bottom'=>m.get_attribute(DICT,'gap_bottom',2.0),'gap_left'=>m.get_attribute(DICT,'gap_left',2.0),'gap_right'=>m.get_attribute(DICT,'gap_right',2.0),'gap_front'=>m.get_attribute(DICT,'gap_front',2.0),'gap_back'=>m.get_attribute(DICT,'gap_back',2.0),'side_t'=>m.get_attribute(DICT,'side_t',18.0),'back_t'=>m.get_attribute(DICT,'back_t',9.0),'bottom_t'=>m.get_attribute(DICT,'bottom_t',9.0),'front_t'=>m.get_attribute(DICT,'front_t',18.0)}
      end
      def show_settings(tool)
        d=defaults
        html="""<!doctype html><html><head><meta charset='utf-8'><style>body{margin:0;background:#17191d;color:#eee;font:14px Arial;padding:18px}.title{font-size:20px;font-weight:700}.sub{color:#aaa;margin:5px 0 15px}.tag{background:#f57900;padding:9px;border-radius:7px;font-weight:700}.s{color:#ff9b43;font-weight:700;margin:15px 0 7px}.g{display:grid;grid-template-columns:1fr 90px;gap:8px;align-items:center}.f{background:#252930;color:#fff;border:1px solid #444;border-radius:5px;padding:7px;text-align:right;width:100%;box-sizing:border-box}.b{margin-top:18px;width:100%;padding:11px;border:0;border-radius:7px;background:#f57900;color:#fff;font-weight:700}</style></head><body><div class='title'>TT - CÀI ĐẶT NGĂN KÉO</div><div class='sub'>Thiết lập cho AUTO 2 điểm</div><div class='tag'>AUTO — CLICK 2 ĐIỂM CHÉO BẤT KỲ</div><div class='s'>KHE HỞ (mm)</div><div class='g'>#{field('Hở trên','gap_top',d)}#{field('Hở dưới','gap_bottom',d)}#{field('Hở trái','gap_left',d)}#{field('Hở phải','gap_right',d)}#{field('Hở trước','gap_front',d)}#{field('Hở sau','gap_back',d)}</div><div class='s'>ĐỘ DÀY (mm)</div><div class='g'>#{field('Tấm hồi / hông','side_t',d)}#{field('Hậu','back_t',d)}#{field('Đáy','bottom_t',d)}#{field('Mặt trước','front_t',d)}</div><button class='b' onclick='save()'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let a=['gap_top','gap_bottom','gap_left','gap_right','gap_front','gap_back','side_t','back_t','bottom_t','front_t'],o={};a.forEach(k=>o[k]=document.getElementById(k).value);sketchup.save(JSON.stringify(o));}</script></body></html>"""
        @dialog ||= UI::HtmlDialog.new(dialog_title:'TT - Cài đặt Ngăn Kéo',preferences_key:'TT_Drawer_Settings',scrollable:true,resizable:true,width:420,height:620,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(html)
        @dialog.add_action_callback('save'){|_,json| begin; vals=JSON.parse(json); vals.each{|k,v| n=v.to_s.gsub(',','.').sub(/\s*mm\s*$/i,'').to_f; raise 'Thông số không hợp lệ' if n<0; Sketchup.active_model.set_attribute(DICT,k,n)}; @dialog.close; tool.reload_cfg(defaults); rescue=>e; UI.messagebox(e.message); end }
        @dialog.show
      end
      def field(label,id,d); "<label>#{label}</label><input id='#{id}' class='f' value='#{d[id]}' >"; end
      class TwoPointTool
        def initialize(cfg); @cfg=cfg; @ip=Sketchup::InputPoint.new; @p1=nil; @preview=nil; @container=nil; end
        def activate; status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 | TAB: CÀI ĐẶT | ESC: THOÁT'); end
        def reload_cfg(cfg); @cfg=cfg; status('ĐÃ CẬP NHẬT CÀI ĐẶT → CLICK ĐIỂM 1'); end
        def deactivate(v); v.invalidate if v; end
        def onMouseMove(_f,x,y,v); @ip.pick(v,x,y); return unless @ip.valid?; p=@ip.position; @preview=@p1 ? [@p1,p] : [p]; v.invalidate; end
        def onLButtonDown(_f,x,y,v); @ip.pick(v,x,y); return unless @ip.valid?; if @p1.nil?; @p1=@ip.position; @container=container(@ip); status('ĐÃ NHẬN ĐIỂM 1 → CLICK ĐIỂM 2 CHÉO BẤT KỲ'); else; create(@ip.position); end; v.invalidate; end
        def onKeyDown(key,_r,_f,_v); if key==9; Drawer.show_settings(self); elsif key==27; Sketchup.active_model.select_tool(nil); end; end
        def draw(v); return unless @preview; v.line_width=3; v.drawing_color=Sketchup::Color.new(255,128,0,255); if @preview.length==1; p=@preview[0]; s=12.mm; v.draw(GL_LINES,Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z)); else; a,b=@preview; mnx=[a.x,b.x].min;mxx=[a.x,b.x].max;mny=[a.y,b.y].min;mxy=[a.y,b.y].max;mnz=[a.z,b.z].min;mxz=[a.z,b.z].max;p=[Geom::Point3d.new(mnx,mny,mnz),Geom::Point3d.new(mxx,mny,mnz),Geom::Point3d.new(mxx,mxy,mnz),Geom::Point3d.new(mnx,mxy,mnz),Geom::Point3d.new(mnx,mny,mxz),Geom::Point3d.new(mxx,mny,mxz),Geom::Point3d.new(mxx,mxy,mxz),Geom::Point3d.new(mnx,mxy,mxz)];[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j|v.draw(GL_LINES,p[i],p[j])};end;end
        private
        def status(t); Sketchup.set_status_text('TT NGĂN KÉO AUTO | ĐƠN VỊ: mm',SB_PROMPT); Sketchup.set_status_text(t,SB_VCB_LABEL); end
        def container(ip); path=ip.instance_path; path && path.to_a.find{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}; end
        def create(p2)
          a=@container ? @p1.transform(@container.transformation.inverse) : @p1; b=@container ? p2.transform(@container.transformation.inverse) : p2
          w=(a.x-b.x).abs.to_mm; d=(a.y-b.y).abs.to_mm; h=(a.z-b.z).abs.to_mm; dw=w-@cfg['gap_left']-@cfg['gap_right']-2*@cfg['side_t']; dd=d-@cfg['gap_front']-@cfg['gap_back']-@cfg['back_t']; dh=h-@cfg['gap_top']-@cfg['gap_bottom']
          if dw<=0||dd<=0||dh<=@cfg['bottom_t']; UI.messagebox('Vùng chọn không đủ kích thước.'); reset; return; end
          m=Sketchup.active_model;m.start_operation('TT - Tạo Ngăn Kéo AUTO',true)
          begin
            g=m.entities.add_group;g.name='TT - Ngăn kéo AUTO';x=[a.x,b.x].min+@cfg['gap_left'].mm+@cfg['side_t'].mm;y=[a.y,b.y].min+@cfg['gap_front'].mm;z=[a.z,b.z].min+@cfg['gap_bottom'].mm;box=g.entities.add_group;box.name='Thùng ngăn kéo';f=box.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+dw.mm,y,z),Geom::Point3d.new(x+dw.mm,y+dd.mm,z),Geom::Point3d.new(x,y+dd.mm,z)]);f.pushpull(dh.mm) if f;g.set_attribute(DICT,'Rong_mm',dw);g.set_attribute(DICT,'Sau_mm',dd);g.set_attribute(DICT,'Cao_mm',dh);g.set_attribute(DICT,'HinhThuc','AUTO_2_DIEM');g.transform!(@container.transformation) if @container;m.commit_operation;status("ĐÃ TẠO R #{dw.round(1)} × S #{dd.round(1)} × C #{dh.round(1)} mm → TIẾP TỤC: CLICK ĐIỂM 1");reset
          rescue=>e;m.abort_operation rescue nil;UI.messagebox("Lỗi tạo ngăn kéo: #{e.message}");reset;end
        end
        def reset;@p1=nil;@preview=nil;@container=nil;end
      end
    end
  end
end
