module TranTuan
  module TaoVan
    module Drawer
      module_function
      TAB_KEY=9; CTRL_KEY=17; DICT='TT_TaoVan_Drawer'
      def mm(v); v.to_f.mm; end
      def mm_text(v); format('%.1f mm',v.to_f); end
      def parse_mm(v); Float(v.to_s.strip.downcase.gsub(',','.').sub(/\s*mm\s*\z/,'')); rescue; nil end
      def defaults
        m=Sketchup.active_model; wall=m.get_attribute(DICT,'wall_t',17.5).to_f; wall=17.5 if wall<=0
        {'rail_gap'=>m.get_attribute(DICT,'rail_gap',14.0).to_f,'gap_top'=>m.get_attribute(DICT,'gap_top',20.0).to_f,'gap_bottom'=>m.get_attribute(DICT,'gap_bottom',0.0).to_f,'gap_front'=>m.get_attribute(DICT,'gap_front',0.0).to_f,'depth_reserve'=>m.get_attribute(DICT,'depth_reserve',60.0).to_f,'bottom_gap'=>0.0,'wall_t'=>wall,'bottom_t'=>m.get_attribute(DICT,'bottom_t',9.0).to_f}
      end
      def start; Sketchup.active_model.select_tool(TwoPointTool.new(defaults)); end
      def show_settings(tool=nil)
        d=defaults
        @dialog ||= UI::HtmlDialog.new(dialog_title:'TT - CÀI ĐẶT NGĂN KÉO AUTO',preferences_key:'TT_Drawer_Auto_Final',scrollable:true,resizable:true,width:450,height:680,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(settings_html(d)); @dialog.add_action_callback('save') do |_c,json|
          begin
            data=JSON.parse(json); vals={}; data.each{|k,v| vals[k]=parse_mm(v)}
            raise 'Thông số phải là số mm không âm.' if vals.values.any?{|v| !v.is_a?(Numeric)||!v.finite?||v<0}
            raise 'Độ dày 4 thành phải lớn hơn 0.' if vals['wall_t']<=0
            vals['bottom_gap']=0.0
            vals.each{|k,v| Sketchup.active_model.set_attribute(DICT,k,v.to_f)}; @dialog.close
            tool ? tool.apply_settings(vals) : Sketchup.active_model.select_tool(TwoPointTool.new(vals))
          rescue=>e; UI.messagebox("Thông số không hợp lệ:\n#{e.message}"); end
        end; @dialog.show
      end
      def settings_html(d)
        fs=[['rail_gap','Ray mỗi bên'],['gap_top','Hở trên'],['gap_bottom','Hở dưới'],['gap_front','Hở trước'],['depth_reserve','Chừa phía sau'],['wall_t','Độ dày 4 thành'],['bottom_t','Độ dày tấm đáy']].map{|k,l|"<label>#{l}</label><input id='#{k}' value='#{d[k]}' style='width:95px;padding:7px'>"}.join
        "<html><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'><h2>TT - NGĂN KÉO AUTO</h2><b>TAB = CÀI ĐẶT</b><p>Click 2 điểm chéo trên cùng mặt. 4 thành mặc định 17,5 mm. Tấm đáy là chi tiết riêng nhưng <b>mặt trên đáy trùng đúng cao độ đáy thành</b>, không có khe tách.</p><div style='display:grid;grid-template-columns:1fr 100px;gap:8px'>#{fs}</div><p>Ray 14 mm/bên • Hở trên 20 mm • Thành 17,5 mm • Đáy 9 mm • Mặt trên đáy = đáy thành • Chừa sau 60 mm.</p><button onclick='save()' style='width:100%;padding:12px'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let a=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t'],o={};a.forEach(k=>o[k]=document.getElementById(k).value);sketchup.save(JSON.stringify(o));}</script></body></html>"
      end
      class TwoPointTool
        def initialize(cfg); @cfg=cfg; @ip=Sketchup::InputPoint.new; @outward=false; reset; end
        def activate; status('AUTO: CLICK ĐIỂM 1 → RÊ CHÉO → CLICK ĐIỂM 2 | CTRL: ĐỔI HƯỚNG | TAB: CÀI ĐẶT | ESC: THOÁT'); end
        def deactivate(view); view.invalidate if view; end
        def apply_settings(cfg); @cfg=cfg; @cfg['bottom_gap']=0.0; reset; status('ĐÃ LƯU → AUTO: CLICK ĐIỂM 1'); end
        def onKeyDown(key,repeat,*_); return Drawer.show_settings(self) if key==TAB_KEY; if key==CTRL_KEY && !repeat; @outward=!@outward; status("ĐÃ ĐỔI HƯỚNG → #{direction_name}"); return true; end; if key==27; Sketchup.active_model.select_tool(nil); return true; end; false end
        def onMouseMove(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?; p=locked_point(@ip.position); @preview=@p1 ? [@p1,p] : [p]
          if @p1&&@frame; d=measure(@p1,p); @preview_drawer=preview_box(@p1,p,d); status("VÙNG R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])} → NGĂN KÉO R #{Drawer.mm_text(d[:dw])} × C #{Drawer.mm_text(d[:dh])} × S #{Drawer.mm_text(d[:dd])}"); end; view.invalidate
        end
        def onLButtonDown(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?; p=@ip.position
          if @p1.nil?; @p1=p; @face=@ip.face; @path=@ip.instance_path; unless @face; UI.messagebox('Điểm 1 phải nằm trên một Face.'); reset; return; end; @frame=build_frame(@p1,@face,@path); status('ĐÃ NHẬN ĐIỂM 1 → RÊ CHÉO TRÊN CHÍNH MẶT → CLICK ĐIỂM 2'); else create(locked_point(p)); end; view.invalidate
        end
        def draw(view)
          return unless @preview; view.line_width=3; view.drawing_color=Sketchup::Color.new(255,128,0,255)
          if @preview.length==1; p=@preview[0]; s=Drawer.mm(12); view.draw(GL_LINES,Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z)); return; end
          b=@preview_drawer; return unless b; pts=box_points(b); view.line_width=4; view.drawing_color=Sketchup::Color.new(255,128,0,180); [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j| view.draw(GL_LINES,pts[i],pts[j])}
        end
        private
        def reset; @p1=@face=@path=@frame=@preview=@preview_drawer=nil; end
        def status(t); Sketchup.set_status_text("TT NGĂN KÉO AUTO | mm | #{direction_name}",SB_PROMPT); Sketchup.set_status_text(t,SB_VCB_LABEL); end
        def direction_name; @outward ? 'RA NGOÀI' : 'VÀO TRONG' end
        def unit(v); q=v.clone; q.normalize!; q; end
        def build_frame(origin,face,path); tr=path ? path.transformation : Geom::Transformation.new; n=unit(face.normal.transform(tr)); inward=n.reverse; z=Geom::Vector3d.new(0,0,1); z=z-n*z.dot(n); z=unit(z.length<0.001 ? Geom::Vector3d.new(1,0,0) : z); x=unit(z.cross(inward)); z=unit(inward.cross(x)); Geom::Transformation.axes(origin,x,inward,z); rescue; Geom::Transformation.new; end
        def frame_point(p); p.transform(@frame.inverse); end
        def locked_point(p); return p unless @p1&&@frame; n=unit(@frame.yaxis); d=p-@p1; p-n*d.dot(n); rescue; p; end
        def normalized_region(a,b); qa=frame_point(locked_point(a)); qb=frame_point(locked_point(b)); [[qa.x,qb.x].min,[qa.x,qb.x].max,[qa.z,qb.z].min,[qa.z,qb.z].max]; end
        def depth_from_region(a,b); xmin,xmax,zmin,zmax=normalized_region(a,b); o=Geom::Point3d.new((xmin+xmax)*0.5,0,(zmin+zmax)*0.5).transform(@frame); dir=unit(@frame.yaxis); start=o+dir.clone.tap{|v|v.length=1.mm}; hit=Sketchup.active_model.raytest([start,dir]); hit&&hit[0].is_a?(Geom::Point3d) ? start.distance(hit[0]).to_mm : 0.0; rescue; 0.0; end
        def measure(a,b); xmin,xmax,zmin,zmax=normalized_region(a,b); w=(xmax-xmin).to_mm; h=(zmax-zmin).to_mm; d=depth_from_region(a,b); rail=@cfg['rail_gap'].to_f; wall=@cfg['wall_t'].to_f; {w:w,h:h,d:d,dw:w-rail*2,dh:h-@cfg['gap_top'].to_f-@cfg['gap_bottom'].to_f,dd:d-@cfg['depth_reserve'].to_f-@cfg['gap_front'].to_f,wall_t:wall}; end
        def preview_box(a,b,d); return nil if d.values_at(:dw,:dh,:dd).any?{|v|v<=0}; xmin,xmax,zmin,zmax=normalized_region(a,b); depth=Drawer.mm(d[:dd]); y=Drawer.mm(@cfg['gap_front']); y-=depth if @outward; {origin:Geom::Point3d.new(xmin+Drawer.mm(@cfg['rail_gap']),y,zmin+Drawer.mm(@cfg['gap_bottom'])),w:Drawer.mm(d[:dw]),d:depth,h:Drawer.mm(d[:dh]),tr:@frame}; end
        def box_points(b); o=b[:origin]; x=b[:w]; y=b[:d]; z=b[:h]; [Geom::Point3d.new(o.x,o.y,o.z),Geom::Point3d.new(o.x+x,o.y,o.z),Geom::Point3d.new(o.x+x,o.y+y,o.z),Geom::Point3d.new(o.x,o.y+y,o.z),Geom::Point3d.new(o.x,o.y,o.z+z),Geom::Point3d.new(o.x+x,o.y,o.z+z),Geom::Point3d.new(o.x+x,o.y+y,o.z+z),Geom::Point3d.new(o.x,o.y+y,o.z+z)].map{|p|p.transform(b[:tr])}; end
        def create(p2)
          d=measure(@p1,p2); return UI.messagebox("Không đủ không gian. Vùng R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])}") if d.values_at(:dw,:dh,:dd).any?{|v|v<=0}
          m=Sketchup.active_model; m.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            xmin,xmax,zmin,zmax=normalized_region(@p1,p2); x=xmin+Drawer.mm(@cfg['rail_gap']); rw=Drawer.mm(d[:dw]); rd=Drawer.mm(d[:dd]); y=Drawer.mm(@cfg['gap_front']); y-=rd if @outward; z=zmin+Drawer.mm(@cfg['gap_bottom']); rh=Drawer.mm(d[:dh]); t=Drawer.mm(d[:wall_t]); bt=Drawer.mm(@cfg['bottom_t']); iw=rw-2*t; raise 'Chiều rộng không đủ cho 2 hông 17,5 mm.' if iw<=0
            g=m.entities.add_group; g.name='TT - Ngăn kéo AUTO';
            add_part(g,'Hông trái',x,y,z,t,rd,rh); add_part(g,'Hông phải',x+rw-t,y,z,t,rd,rh); add_part(g,'Thành trước',x+t,y,z,iw,t,rh); add_part(g,'Thành sau',x+t,y+rd-t,z,iw,t,rh)
            # Tấm đáy là chi tiết riêng để quản lý, nhưng mặt trên của nó TRÙNG ĐÚNG với đáy 4 thành.
            # Không có khe hở và không hạ thêm 2 mm. Đáy chỉ đi xuống theo đúng độ dày của tấm đáy.
            bottom_z=z-bt
            add_part(g,'Tấm đáy',x+t,y,bottom_z,iw,rd,bt)
            g.transform!(@frame); g.set_attribute(DICT,'don_vi','mm'); g.set_attribute(DICT,'do_day_4_thanh_mm',d[:wall_t]); g.set_attribute(DICT,'do_day_day_mm',@cfg['bottom_t']); g.set_attribute(DICT,'khe_tach_day_mm',0.0); g.set_attribute(DICT,'ten_thanh_sau','Thành sau'); m.commit_operation; reset; Sketchup.active_model.select_tool(self); status('ĐÃ TẠO NGĂN KÉO → CLICK ĐIỂM 1 TIẾP THEO')
          rescue=>e; m.abort_operation rescue nil; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}"); end
        end
        def add_part(g,name,x,y,z,w,d,h); p=g.entities.add_group; p.name=name; f=p.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z)]); f.pushpull(h) if f; end
      end
    end
  end
end
