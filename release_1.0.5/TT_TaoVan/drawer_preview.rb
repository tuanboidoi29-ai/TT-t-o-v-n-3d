# TT - NGAN KEO AUTO - FULL 3D PREVIEW + HAU MODES
module TranTuan
  module TaoVan
    module Drawer
      class TwoPointTool
        alias_method :tt_preview_draw_original, :draw unless method_defined?(:tt_preview_draw_original)

        def draw(view)
          return tt_preview_draw_original(view) unless @p1 && @frame && @preview_drawer && @preview && @preview.length > 1
          d = measure(@p1,@preview[1]) rescue nil
          return tt_preview_draw_original(view) unless d
          return tt_preview_draw_original(view) if d.values_at(:dw,:dh,:dd).any?{|v|v.to_f<=0}
          xmin,xmax,zmin,zmax=normalized_region(@p1,@preview[1])
          t=Drawer.mm(d[:wall_t]); bt=Drawer.mm(@cfg['bottom_t']); rw=Drawer.mm(d[:dw]); rd=Drawer.mm(d[:dd]); rh=Drawer.mm(d[:dh])
          x=xmin+Drawer.mm(@cfg['rail_gap']); y=Drawer.mm(@cfg['gap_front']); y-=rd if @outward; z=zmin+Drawer.mm(@cfg['gap_bottom']); iw=rw-2.0*t
          return tt_preview_draw_original(view) if iw<=0
          parts=[[x,y,z,t,rd,rh],[x+rw-t,y,z,t,rd,rh],[x+t,y,z,iw,t,rh],[x+t,y+rd-t,z,iw,t,rh],[x+t,y,z-bt,iw,rd,bt]]
          if @back_mode != :none
            edge=Drawer.mm(@cfg['back_edge_offset']); bottom=Drawer.mm(@cfg['back_bottom_offset']); panel_t=bt
            pw=@back_mode==:phủ ? rw : [rw-2.0*edge,0].max
            ph=[rh-bottom,0].max
            px=@back_mode==:phủ ? x : x+edge
            py=@back_mode==:phủ ? y+rd : y+rd-t
            parts << [px,py,z+bottom,pw,panel_t,ph] if pw>0 && ph>0
          end
          view.line_width=3; view.drawing_color=Sketchup::Color.new(255,128,0,220)
          parts.each{|box|tt_draw_box_edges_preview(view,box)}
          view.line_width=2; view.drawing_color=Sketchup::Color.new(255,255,255,180); view.draw(GL_LINES,@p1,@preview[1])
        rescue
          tt_preview_draw_original(view)
        end

        # HAU khong con thong so day rieng: dung cung do day voi tam day.
        def add_rear(g,x,y,z,rw,rd,rh,t)
          panel_t=Drawer.mm(@cfg['bottom_t']); edge=Drawer.mm(@cfg['back_edge_offset']); bottom=Drawer.mm(@cfg['back_bottom_offset'])
          raise 'Độ dày tấm đáy phải lớn hơn 0.' if panel_t<=0
          ph=rh-bottom; raise 'Offset hậu từ đáy quá lớn.' if ph<=0
          if @back_mode==:phủ
            px=x; pw=rw; py=y+rd
          else
            px=x+edge; pw=rw-2.0*edge; py=y+rd-t
          end
          raise 'Chiều rộng hậu không đủ.' if pw<=0
          add_part(g,'Tấm hậu',px,py,z+bottom,pw,panel_t,ph)
        end

        private
        def tt_draw_box_edges_preview(view,box)
          x,y,z,w,d,h=box
          p=[Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+w,y,z),Geom::Point3d.new(x+w,y+d,z),Geom::Point3d.new(x,y+d,z),Geom::Point3d.new(x,y,z+h),Geom::Point3d.new(x+w,y,z+h),Geom::Point3d.new(x+w,y+d,z+h),Geom::Point3d.new(x,y+d,z+h)].map{|q|q.transform(@frame)}
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each{|a,b|view.draw(GL_LINES,p[a],p[b])}
        end
      end
    end
  end
end
