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
        side = m.get_attribute(DICT, 'side_t', 17.5).to_f
        side = 17.5 if side <= 0
        # Four drawer walls use one thickness by default.
        wall = m.get_attribute(DICT, 'wall_t', side).to_f
        wall = side if wall <= 0
        {
          'rail_gap'      => m.get_attribute(DICT, 'rail_gap', 14.0).to_f,
          'gap_top'       => m.get_attribute(DICT, 'gap_top', 20.0).to_f,
          'gap_bottom'    => m.get_attribute(DICT, 'gap_bottom', 0.0).to_f,
          'gap_front'     => m.get_attribute(DICT, 'gap_front', 0.0).to_f,
          'depth_reserve' => m.get_attribute(DICT, 'depth_reserve', 60.0).to_f,
          'side_t'        => wall,
          'wall_t'        => wall,
          'back_t'        => wall,
          'bottom_t'      => m.get_attribute(DICT, 'bottom_t', 9.0).to_f,
          'front_t'       => wall
        }.tap do |h|
          m.set_attribute(DICT, 'side_t', wall)
          m.set_attribute(DICT, 'wall_t', wall)
          m.set_attribute(DICT, 'back_t', wall)
          m.set_attribute(DICT, 'front_t', wall)
        end
      end

      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end

      def show_settings(tool = nil)
        d = defaults
        @dialog ||= UI::HtmlDialog.new(
          dialog_title: 'TT - CÀI ĐẶT NGĂN KÉO AUTO',
          preferences_key: 'TT_Drawer_Auto_124',
          scrollable: true, resizable: true, width: 450, height: 650,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save') do |_c, json|
          begin
            data = JSON.parse(json)
            vals = {}
            data.each { |k, v| vals[k] = parse_mm(v) }
            raise 'Thông số phải là số mm không âm.' if vals.values.any? { |v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Độ dày thành phải lớn hơn 0.' if vals['wall_t'] <= 0
            vals['side_t'] = vals['wall_t']
            vals['front_t'] = vals['wall_t']
            vals['back_t'] = vals['wall_t']
            vals.each { |k, v| Sketchup.active_model.set_attribute(DICT, k, v.to_f) }
            @dialog.close
            tool ? (tool.apply_settings(vals)) : Sketchup.active_model.select_tool(TwoPointTool.new(vals))
          rescue => e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end

      def settings_html(d)
        fields = [
          ['rail_gap', 'Ray mỗi bên'], ['gap_top', 'Hở trên'], ['gap_bottom', 'Hở dưới'],
          ['gap_front', 'Hở trước'], ['depth_reserve', 'Chừa phía sau'], ['wall_t', 'Độ dày 4 thành'],
          ['bottom_t', 'Độ dày đáy']
        ].map { |k, l| "<label>#{l}</label><input id='#{k}' value='#{d[k]}' style='width:95px;padding:7px;background:#252930;color:#fff;border:1px solid #444;border-radius:6px'>" }.join
        "<!doctype html><html><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'><h2>TT - NGĂN KÉO AUTO</h2><b style='color:#ff9b43'>TAB = CÀI ĐẶT | CLICK 2 ĐIỂM TRÊN CÙNG MẶT TRƯỚC</b><p>4 thành ngăn kéo dùng cùng độ dày. Mặc định <b>17,5 mm</b>. Thành trước và thành sau nằm lọt giữa hai hông, không chồng lấn tại góc.</p><div style='display:grid;grid-template-columns:1fr 100px;gap:8px;align-items:center'>#{fields}</div><p style='font-size:12px;color:#aaa'>Mặc định: ray 14 mm/bên, hở trên 20 mm, 4 thành 17,5 mm, chừa sau 60 mm.</p><button onclick='save()' style='width:100%;padding:12px;background:#ff7a00;color:#fff;border:0;border-radius:8px;font-weight:bold'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let ids=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t'];let o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.save(JSON.stringify(o));}</script></body></html>"
      end

      class TwoPointTool
        def initialize(cfg); @cfg = cfg; @ip = Sketchup::InputPoint.new; reset; end
        def activate; status('AUTO: CLICK ĐIỂM 1 → RÊ CHÉO → CLICK ĐIỂM 2 | TAB: CÀI ĐẶT | ESC: THOÁT'); end
        def deactivate(view); view.invalidate if view; end
        def apply_settings(cfg); @cfg = cfg; @cfg['side_t'] = @cfg['wall_t']; @cfg['front_t'] = @cfg['wall_t']; @cfg['back_t'] = @cfg['wall_t']; reset; status('ĐÃ LƯU → AUTO: CLICK ĐIỂM 1'); end

        def onKeyDown(key, *_args)
          return Drawer.show_settings(self) && true if key == TAB_KEY
          if key == 27; Sketchup.active_model.select_tool(nil); return true; end
          false
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y); return unless @ip.valid?
          p = locked_point(@ip.position)
          @preview = @p1 ? [@p1, p] : [p]
          if @p1 && @frame
            d = measure(@p1, p); @preview_drawer = preview_box(@p1, p, d)
            status("VÙNG R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])} → NGĂN KÉO R #{Drawer.mm_text(d[:dw])} × C #{Drawer.mm_text(d[:dh])} × S #{Drawer.mm_text(d[:dd])}")
          end
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y); return unless @ip.valid?
          p = @ip.position
          if @p1.nil?
            @p1 = p; @face = @ip.face; @path = @ip.instance_path
            unless @face; UI.messagebox('Điểm 1 phải nằm trên một Face.'); reset; return; end
            @frame = build_frame(@p1, @face, @path); @container = best_container(@path)
            status('ĐÃ NHẬN ĐIỂM 1 → RÊ CHUỘT CHÉO TRÊN CHÍNH MẶT ĐÓ → CLICK ĐIỂM 2')
          else
            create(locked_point(p))
          end
          view.invalidate
        end

        def draw(view)
          return unless @preview
          view.line_width = 3; view.drawing_color = Sketchup::Color.new(255, 128, 0, 255)
          if @preview.length == 1
            p = @preview[0]; s = Drawer.mm(12)
            view.draw(GL_LINES, Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z)); return
          end
          box=@preview_drawer; return unless box; pts=box_points(box)
          view.drawing_color=Sketchup::Color.new(255,128,0,180); view.line_width=4
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j| view.draw(GL_LINES,pts[i],pts[j])}
        end

        private
        def reset; @p1=@face=@path=@container=@frame=@preview=@preview_drawer=nil; end
        def status(t); Sketchup.set_status_text('TT NGĂN KÉO AUTO | mm',SB_PROMPT); Sketchup.set_status_text(t,SB_VCB_LABEL); end
        def best_container(path); return nil unless path; path.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}.max_by{|e|b=local_entity_bounds(e);b.width.to_f*b.depth.to_f*b.height.to_f}; rescue;nil;end
        def local_entity_bounds(e);e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities.bounds : e.entities.bounds;rescue;Geom::BoundingBox.new;end
        def unit(v);q=v.clone;q.normalize!;q;end
        def build_frame(origin,face,path)
          tr=path ? path.transformation : Geom::Transformation.new; normal=unit(face.normal.transform(tr)); inward=normal.reverse
          z=Geom::Vector3d.new(0,0,1);z=z-normal*z.dot(normal)
          if z.length<0.001; edge_vec=face.edges.map{|e|e.line[1]}.find{|v|v.length>0.001};z=edge_vec ? unit(edge_vec.transform(tr)) : Geom::Vector3d.new(1,0,0);else;z=unit(z);end
          x=unit(z.cross(inward));z=unit(inward.cross(x));Geom::Transformation.axes(origin,x,inward,z)
        rescue;Geom::Transformation.new;end
        def frame_point(p);p.transform(@frame.inverse);end
        def locked_point(p);return p unless @p1&&@frame;n=unit(@frame.yaxis);delta=p-@p1;p-n*delta.dot(n);rescue;p;end
        def normalized_region(a,b);qa=frame_point(locked_point(a));qb=frame_point(locked_point(b));[[qa.x,qb.x].min,[qa.x,qb.x].max,[qa.z,qb.z].min,[qa.z,qb.z].max];end
        def depth_from_region(a,b)
          xmin,xmax,zmin,zmax=normalized_region(a,b);local=Geom::Point3d.new((xmin+xmax)*0.5,0,(zmin+zmax)*0.5);origin=local.transform(@frame);inward=unit(@frame.yaxis);start=origin+inward.clone.tap{|v|v.length=1.mm};hit=Sketchup.active_model.raytest([start,inward]);hit&&hit[0].is_a?(Geom::Point3d) ? start.distance(hit[0]).to_mm : 0.0
        rescue;0.0;end
        def measure(a,b)
          xmin,xmax,zmin,zmax=normalized_region(a,b);w=(xmax-xmin).abs.to_mm;h=(zmax-zmin).abs.to_mm;d=depth_from_region(a,b);rail=@cfg['rail_gap'].to_f;wall=@cfg['wall_t'].to_f
          {w:w,h:h,d:d,dw:w-rail*2.0,dh:h-@cfg['gap_top'].to_f-@cfg['gap_bottom'].to_f,dd:d-@cfg['depth_reserve'].to_f-@cfg['gap_front'].to_f,wall_t:wall}
        end
        def preview_box(a,b,d);return nil if d.values_at(:dw,:dh,:dd).any?{|v|v<=0};xmin,xmax,zmin,zmax=normalized_region(a,b);x=xmin+Drawer.mm(@cfg['rail_gap']);z=zmin+Drawer.mm(@cfg['gap_bottom']);{origin:Geom::Point3d.new(x,Drawer.mm(@cfg['gap_front']),z),w:Drawer.mm(d[:dw]),d:Drawer.mm(d[:dd]),h:Drawer.mm(d[:dh]),tr:@frame};end
        def box_points(b);o=b[:origin];x=b[:w];y=b[:d];z=b[:h];pts=[Geom::Point3d.new(o.x,o.y,o.z),Geom::Point3d.new(o.x+x,o.y,o.z),Geom::Point3d.new(o.x+x,o.y+y,o.z),Geom::Point3d.new(o.x,o.y+y,o.z),Geom::Point3d.new(o.x,o.y,o.z+z),Geom::Point3d.new(o.x+x,o.y,o.z+z),Geom::Point3d.new(o.x+x,o.y+y,o.z+z),Geom::Point3d.new(o.x,o.y+y,o.z+z)];pts.map{|p|p.transform(b[:tr])};end

        def create(p2)
          p2=locked_point(p2);d=measure(@p1,p2)
          if d.values_at(:dw,:dh,:dd).any?{|v|v<=0};UI.messagebox("Không đủ không gian.\n\nVùng: R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])}\nNgăn kéo: R #{Drawer.mm_text(d[:dw])} × C #{Drawer.mm_text(d[:dh])} × S #{Drawer.mm_text(d[:dd])}");return;end
          model=Sketchup.active_model;model.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            xmin,_xmax,zmin,_zmax=normalized_region(@p1,p2);x=xmin+Drawer.mm(@cfg['rail_gap']);y=Drawer.mm(@cfg['gap_front']);z=zmin+Drawer.mm(@cfg['gap_bottom']);rw=Drawer.mm(d[:dw]);rd=Drawer.mm(d[:dd]);rh=Drawer.mm(d[:dh]);wall=Drawer.mm(d[:wall_t]);bt=Drawer.mm(@cfg['bottom_t'])
            # Structural rule: the two hongs run full depth; front/back fit BETWEEN them.
            inner_w=rw-wall*2
            raise 'Chiều rộng ngăn kéo không đủ cho 2 hông 17,5 mm.' if inner_w <= 0
            front_d=wall; back_d=wall
            g=model.entities.add_group;g.name='TT - Ngăn kéo AUTO'
            add_part(g,'Hông trái',x,y,z,wall,rd,rh)
            add_part(g,'Hông phải',x+rw-wall,y,z,wall,rd,rh)
            add_part(g,'Mặt trước',x+wall,y,z,inner_w,front_d,rh)
            add_part(g,'Hậu',x+wall,y+rd-back_d,z,inner_w,back_d,rh)
            add_part(g,'Đáy',x+wall,y,z+0.mm,inner_w,rd,bt)
            g.transform!(@frame)
            g.set_attribute(DICT,'don_vi','mm');g.set_attribute(DICT,'vung_rong_mm',d[:w]);g.set_attribute(DICT,'vung_cao_mm',d[:h]);g.set_attribute(DICT,'vung_sau_mm',d[:d]);g.set_attribute(DICT,'rong_mm',d[:dw]);g.set_attribute(DICT,'cao_mm',d[:dh]);g.set_attribute(DICT,'sau_mm',d[:dd]);g.set_attribute(DICT,'ray_moi_ben_mm',@cfg['rail_gap']);g.set_attribute(DICT,'do_day_4_thanh_mm',@cfg['wall_t']);g.set_attribute(DICT,'do_day_hong_mm',@cfg['wall_t']);g.set_attribute(DICT,'chua_sau_mm',@cfg['depth_reserve'])
            model.commit_operation;reset;Sketchup.active_model.select_tool(self);status('ĐÃ TẠO NGĂN KÉO → CLICK ĐIỂM 1 TIẾP THEO')
          rescue=>e;model.abort_operation rescue nil;UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}");end
        end
        def add_part(g,name,x,y,z,w,d,h);p=g.entities.add_group;p.name=name;f=p.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z)]);f.pushpull(h) if f;end
      end
    end
  end
end