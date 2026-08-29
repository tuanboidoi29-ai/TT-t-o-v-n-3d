# TT - NGAN KEO AUTO - FULL 3D PREVIEW
# Preview mo phong dung cac thanh se tao, truoc khi click tao that.
module TranTuan
  module TaoVan
    module Drawer
      class TwoPointTool
        unless method_defined?(:tt_full_preview_draw_original)
          alias_method :tt_full_preview_draw_original, :draw
        end

        def draw(view)
          return tt_full_preview_draw_original(view) unless @p1 && @frame && @preview_drawer
          d = begin
            measure(@p1, @preview[1])
          rescue
            nil
          end
          return tt_full_preview_draw_original(view) unless d
          return tt_full_preview_draw_original(view) if d.values_at(:dw, :dh, :dd).any? { |v| v.to_f <= 0 }

          xmin, xmax, zmin, zmax = normalized_region(@p1, @preview[1])
          t  = Drawer.mm(d[:wall_t])
          bt = Drawer.mm(@cfg['bottom_t'])
          rw = Drawer.mm(d[:dw])
          rd = Drawer.mm(d[:dd])
          rh = Drawer.mm(d[:dh])
          x  = xmin + Drawer.mm(@cfg['rail_gap'])
          y  = Drawer.mm(@cfg['gap_front'])
          y -= rd if @outward
          z  = zmin + Drawer.mm(@cfg['gap_bottom'])
          iw = rw - 2.0 * t
          return tt_full_preview_draw_original(view) if iw <= 0

          # Moi chi tiet la mot khoi wireframe rieng, dung cung toa do voi luc create.
          parts = []
          parts << [x,       y,       z, t,  rd, rh] # Hong trai
          parts << [x+rw-t,  y,       z, t,  rd, rh] # Hong phai
          parts << [x+t,     y,       z, iw, t,  rh] # Thanh truoc
          parts << [x+t,     y+rd-t,  z, iw, t,  rh] # Thanh sau
          parts << [x+t,     y, z-bt, iw, rd, bt] # Day

          # Ve cac thanh chinh dam, de nhin ro khoang rong cua ngan keo.
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(255, 128, 0, 220)
          parts.each { |box| tt_draw_box_edges(view, box) }

          # Ve hau neu dang bat. Hau nam dung theo che do offset da cai dat.
          if @back_mode != :none
            edge   = Drawer.mm(@cfg['back_edge_offset'])
            bottom = Drawer.mm(@cfg['back_bottom_offset'])
            back_t = Drawer.mm(@cfg['back_t'])
            pw = [rw - 2.0 * edge, 0].max
            ph = [rh - bottom, 0].max
            if pw > 0 && ph > 0
              py = y + rd - back_t
              py += back_t if @back_mode == :phủ
              parts << [x + edge, py, z + bottom, pw, back_t, ph]
              view.line_width = 2
              view.drawing_color = Sketchup::Color.new(255, 190, 40, 220)
              tt_draw_box_edges(view, parts.last)
            end
          end

          # Diem 1/2 va duong chon van giu mau cam de nguoi dung biet dang preview.
          view.line_width = 2
          view.drawing_color = Sketchup::Color.new(255, 255, 255, 180)
          view.draw(GL_LINES, @p1, @preview[1]) if @preview && @preview.length > 1
        rescue => e
          tt_full_preview_draw_original(view)
        end

        private

        def tt_draw_box_edges(view, box)
          x, y, z, w, d, h = box
          p = [
            Geom::Point3d.new(x,y,z), Geom::Point3d.new(x+w,y,z),
            Geom::Point3d.new(x+w,y+d,z), Geom::Point3d.new(x,y+d,z),
            Geom::Point3d.new(x,y,z+h), Geom::Point3d.new(x+w,y,z+h),
            Geom::Point3d.new(x+w,y+d,z+h), Geom::Point3d.new(x,y+d,z+h)
          ].map { |q| q.transform(@frame) }
          edges = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
          edges.each { |a,b| view.draw(GL_LINES, p[a], p[b]) }
        end
      end
    end
  end
end
