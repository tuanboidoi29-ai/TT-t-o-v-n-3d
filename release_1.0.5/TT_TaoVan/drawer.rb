module TranTuan
  module TaoVan
    module Drawer
      module_function
      TAB_KEY = 9
      DICT = 'TT_TaoVan_Drawer'
      TOL = 0.5.mm

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
        side = 17.5 if side <= 0 || (side - 18.0).abs < 0.01
        {
          'rail_gap'=>m.get_attribute(DICT,'rail_gap',14.0).to_f,
          'gap_top'=>m.get_attribute(DICT,'gap_top',20.0).to_f,
          'gap_bottom'=>m.get_attribute(DICT,'gap_bottom',0.0).to_f,
          'gap_front'=>m.get_attribute(DICT,'gap_front',0.0).to_f,
          'depth_reserve'=>m.get_attribute(DICT,'depth_reserve',60.0).to_f,
          'side_t'=>side,
          'back_t'=>m.get_attribute(DICT,'back_t',9.0).to_f,
          'bottom_t'=>m.get_attribute(DICT,'bottom_t',9.0).to_f,
          'front_t'=>m.get_attribute(DICT,'front_t',18.0).to_f
        }.tap { |h| m.set_attribute(DICT,'side_t',side) }
      end

      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end

      def show_settings(tool=nil)
        d=defaults
        @dialog ||= UI::HtmlDialog.new(dialog_title:'TT - CÀI ĐẶT NGĂN KÉO AUTO',preferences_key:'TT_Drawer_Auto_122',scrollable:true,resizable:true,width:450,height:650,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save') do |_c,json|
          begin
            data=JSON.parse(json); vals={}; data.each{|k,v| vals[k]=parse_mm(v)}
            raise 'Thông số phải là số mm không âm.' if vals.values.any?{|v| !v.is_a?(Numeric)||!v.finite?||v<0}
            raise 'Độ dày vật liệu phải lớn hơn 0.' if %w[side_t back_t bottom_t front_t].any?{|k| vals[k]<=0}
            vals.each{|k,v| Sketchup.active_model.set_attribute(DICT,k,v.to_f)}
            @dialog.close
            tool ? (tool.apply_settings(vals); Sketchup.active_model.select_tool(tool)) : Sketchup.active_model.select_tool(TwoPointTool.new(vals))
          rescue=>e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end

      def settings_html(d)
        fields=[
          ['rail_gap','Ray mỗi bên'],['gap_top','Hở trên'],['gap_bottom','Hở dưới'],['gap_front','Hở trước'],
          ['depth_reserve','Chừa phía sau'],['side_t','Độ dày hông'],['back_t','Độ dày hậu'],['bottom_t','Độ dày đáy'],['front_t','Độ dày mặt trước']
        ].map{|k,l|"<label>#{l}</label><input id='#{k}' value='#{d[k]}' style='width:95px;padding:7px;background:#252930;color:#fff;border:1px solid #444;border-radius:6px'>"}.join
        "<!doctype html><html><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'><h2>TT - NGĂN KÉO AUTO</h2><b style='color:#ff9b43'>TAB = CÀI ĐẶT | CLICK 2 ĐIỂM TRÊN MẶT TRƯỚC</b><p>Hệ thống lấy Rộng + Cao từ 2 điểm chéo bất kỳ. Chiều sâu được quét theo phương vuông góc mặt đã chọn tới lòng tủ.</p><div style='display:grid;grid-template-columns:1fr 100px;gap:8px;align-items:center'>#{fields}</div><p style='font-size:12px;color:#aaa'>Mặc định: ray 14 mm/bên, hở trên 20 mm, hông 17,5 mm, chừa sau 60 mm.</p><button onclick='save()' style='width:100%;padding:12px;background:#ff7a00;color:#fff;border:0;border-radius:8px;font-weight:bold'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let ids=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','side_t','back_t','bottom_t','front_t'];let o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.save(JSON.stringify(o));}</script></body></html>"
      end

      class TwoPointTool
        def initialize(cfg)
          @cfg=cfg; @ip=Sketchup::InputPoint.new; reset
        end
        def activate; status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 CHÉO BẤT KỲ TRÊN MẶT TRƯỚC | TAB: CÀI ĐẶT | ESC: THOÁT'); end
        def deactivate(view); view.invalidate if view; end
        def apply_settings(cfg); @cfg=cfg; reset; status('ĐÃ LƯU → AUTO: CLICK ĐIỂM 1'); end
        def onKeyDown(key,*_args)
          return Drawer.show_settings(self) && true if key==TAB_KEY
          if key==27; Sketchup.active_model.select_tool(nil); return true; end
          false
        end
        def onMouseMove(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?
          p=@ip.position; @preview=@p1 ? [@p1,p] : [p]
          if @p1
            d=measure(@p1,p); @preview_drawer=preview_box(@p1,p,d)
            status("VÙNG R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])} → NGĂN KÉO R #{Drawer.mm_text(d[:dw])} × C #{Drawer.mm_text(d[:dh])} × S #{Drawer.mm_text(d[:dd])}")
          end
          view.invalidate
        end
        def onLButtonDown(_flags,x,y,view)
          @ip.pick(view,x,y); return unless @ip.valid?
          p=@ip.position
          if @p1.nil?
            @p1=p; @face=@ip.face; @path=@ip.instance_path; @container=best_container(@path); @frame=build_frame(@p1,@face,@path); status('ĐÃ NHẬN ĐIỂM 1 → CLICK ĐIỂM 2 CHÉO BẤT KỲ TRÊN CÙNG MẶT');
          else
            create(p)
          end
          view.invalidate
        end
        def draw(view)
          return unless @preview
          view.line_width=3; view.drawing_color=Sketchup::Color.new(255,128,0,255)
          if @preview.length==1
            p=@preview[0]; s=Drawer.mm(12); view.draw(GL_LINES,Geom::Point3d.new(p.x-s,p.y,p.z),Geom::Point3d.new(p.x+s,p.y,p.z),Geom::Point3d.new(p.x,p.y-s,p.z),Geom::Point3d.new(p.x,p.y+s,p.z)); return
          end
          box=@preview_drawer; return unless box
          pts=box_points(box); view.drawing_color=Sketchup::Color.new(255,128,0,150); view.line_width=4
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|i,j| view.draw(GL_LINES,pts[i],pts[j])}
        end
        private
        def reset
          @p1=@face=@path=@container=@frame=@preview=@preview_drawer=nil
        end
        def status(t); Sketchup.set_status_text('TT NGĂN KÉO AUTO | mm',SB_PROMPT); Sketchup.set_status_text(t,SB_VCB_LABEL); end
        def best_container(path)
          return nil unless path
          path.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}.max_by{|e| local_entity_bounds(e).width.to_f*local_entity_bounds(e).depth.to_f*local_entity_bounds(e).height.to_f}
        rescue; nil end
        def local_entity_bounds(e)
          e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities.bounds : e.entities.bounds
        rescue
          Geom::BoundingBox.new
        end
        def world_vector(v,tr); v.transform(tr); end
        def unit(v); q=v.clone; q.normalize!; q end

        def build_frame(origin,face,path)
          tr=path ? path.transformation : Geom::Transformation.new
          normal=unit(world_vector(face ? face.normal : Geom::Vector3d.new(0,-1,0),tr))
          inward=normal.reverse
          z=Geom::Vector3d.new(0,0,1)
          z=z-normal*z.dot(normal)
          if z.length < 0.001
            edge=face && face.edges.first
            z=edge ? unit(world_vector(edge.line[1],tr)) : Geom::Vector3d.new(1,0,0)
          else
            z=unit(z)
          end
          x=unit(inward.cross(z)); z=unit(x.cross(inward))
          Geom::Transformation.axes(origin,x,inward,z)
        rescue
          Geom::Transformation.new
        end

        def frame_point(p); p.transform(@frame.inverse); end

        def depth_from_ray(origin)
          inward=Geom::Vector3d.new(@frame.yaxis.x,@frame.yaxis.y,@frame.yaxis.z)
          inward.normalize!
          start=origin + inward.clone.tap{|v| v.length=1.mm}
          hit=Sketchup.active_model.raytest([start,inward])
          if hit && hit[0].is_a?(Geom::Point3d)
            return start.distance(hit[0]).to_mm
          end
          if @container && @container.valid?
            bb=local_entity_bounds(@container)
            idx=@path.to_a.index(@container)
            tr=idx ? @path.transformation(idx) : Geom::Transformation.new
            corners=(0..7).map{|i| bb.corner(i).transform(tr)}
            vals=corners.map{|q| (q-origin).dot(inward)}.select{|v| v>0}
            return vals.min.to_mm if vals.any?
          end
          0.0
        rescue
          0.0
        end

        # Normalizes the two clicks in the local face frame so the user may
        # click any diagonal direction/order without flipping the preview.
        def normalized_region(a,b)
          qa=frame_point(a); qb=frame_point(b)
          xmin=[qa.x,qb.x].min; xmax=[qa.x,qb.x].max
          zmin=[qa.z,qb.z].min; zmax=[qa.z,qb.z].max
          [xmin,xmax,zmin,zmax]
        end

        def measure(a,b)
          xmin,xmax,zmin,zmax=normalized_region(a,b)
          w=(xmax-xmin).abs.to_mm; h=(zmax-zmin).abs.to_mm; d=depth_from_ray(a)
          rail=@cfg['rail_gap'].to_f
          {w:w,h:h,d:d,dw:w-rail*2.0,dh:h-@cfg['gap_top'].to_f-@cfg['gap_bottom'].to_f,dd:d-@cfg['depth_reserve'].to_f-@cfg['gap_front'].to_f}
        end

        def preview_box(a,b,d)
          return nil if d.values_at(:dw,:dh,:dd).any?{|v|v<=0}
          xmin,xmax,zmin,zmax=normalized_region(a,b)
          x=xmin+Drawer.mm(@cfg['rail_gap'])
          z=zmin+Drawer.mm(@cfg['gap_bottom'])
          y=Drawer.mm(@cfg['gap_front'])
          {origin:Geom::Point3d.new(x,y,z),w:Drawer.mm(d[:dw]),d:Drawer.mm(d[:dd]),h:Drawer.mm(d[:dh]),tr:@frame}
        end

        def box_points(b)
          o=b[:origin]; x=b[:w]; y=b[:d]; z=b[:h]
          a=[
            Geom::Point3d.new(o.x,o.y,o.z),Geom::Point3d.new(o.x+x,o.y,o.z),
            Geom::Point3d.new(o.x+x,o.y+y,o.z),Geom::Point3d.new(o.x,o.y+y,o.z),
            Geom::Point3d.new(o.x,o.y,o.z+z),Geom::Point3d.new(o.x+x,o.y,o.z+z),
            Geom::Point3d.new(o.x+x,o.y+y,o.z+z),Geom::Point3d.new(o.x,o.y+y,o.z+z)
          ]
          a.map{|p|p.transform(b[:tr])}
        end

        def create(p2)
          d=measure(@p1,p2)
          if d.values_at(:dw,:dh,:dd).any?{|v|v<=0}
            UI.messagebox("Không đủ không gian.\n\nVùng: R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])}\nNgăn kéo: R #{Drawer.mm_text(d[:dw])} × C #{Drawer.mm_text(d[:dh])} × S #{Drawer.mm_text(d[:dd])}"); return
          end
          model=Sketchup.active_model; model.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            xmin,xmax,zmin,zmax=normalized_region(@p1,p2)
            q=frame_point(@p1)
            x=xmin+Drawer.mm(@cfg['rail_gap'])
            y=Drawer.mm(@cfg['gap_front'])
            z=zmin+Drawer.mm(@cfg['gap_bottom'])
            rw=Drawer.mm(d[:dw]); rd=Drawer.mm(d[:dd]); rh=Drawer.mm(d[:dh]); st=Drawer.mm(@cfg['side_t']); bt=Drawer.mm(@cfg['bottom_t']); back=Drawer.mm(@cfg['back_t']); ft=Drawer.mm(@cfg['front_t'])
            g=model.entities.add_group; g.name='TT - Ngăn kéo AUTO'
            add_part(g,'Hông trái',x,y,z,st,rd,rh); add_part(g,'Hông phải',x+rw-st,y,z,st,rd,rh); add_part(g,'Đáy',x,y,z,rw,rd,bt); add_part(g,'Mặt trước',x,y,z,rw,ft,rh); add_part(g,'Hậu',x,y+rd-back,z,rw,back,rh)
            g.transform!(@frame)
            g.set_attribute(DICT,'don_vi','mm'); g.set_attribute(DICT,'vung_rong_mm',d[:w]); g.set_attribute(DICT,'vung_cao_mm',d[:h]); g.set_attribute(DICT,'vung_sau_mm',d[:d]); g.set_attribute(DICT,'rong_mm',d[:dw]); g.set_attribute(DICT,'cao_mm',d[:dh]); g.set_attribute(DICT,'sau_mm',d[:dd]); g.set_attribute(DICT,'ray_moi_ben_mm',@cfg['rail_gap']); g.set_attribute(DICT,'do_day_hong_mm',@cfg['side_t']); g.set_attribute(DICT,'chua_sau_mm',@cfg['depth_reserve']); model.commit_operation; reset; Sketchup.active_model.select_tool(self); status('ĐÃ TẠO NGĂN KÉO → CLICK ĐIỂM 1 TIẾP THEO')
          rescue=>e
            model.abort_operation rescue nil; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          end
        end
        def add_part(g,name,x,y,z,w,d,h)
          p=g.entities.add_group; p.name=name; f=p.entities.add_face([Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z)]); f.pushpull(h) if f
        end
      end
    end
  end
end
