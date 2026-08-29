# TT - NGAN KEO AUTO - GEOMETRY DIRECTION FIX 1.3.4
# Quy uoc: thanh truoc o dau khoang, thanh sau o cuoi khoang,
# tam day nam ngang ben duoi 4 thanh; khong dao thanh sau thanh day.
module TranTuan
  module TaoVan
    module Drawer
      class TwoPointTool
        alias_method :tt_build_frame_original_134, :build_frame unless method_defined?(:tt_build_frame_original_134)

        # Tao he truc on dinh: Y = huong vao khoang, Z = phuong len tren,
        # X = phuong ngang. Khong dung canh click de dao huong thanh sau.
        def build_frame(origin, face, path)
          tr = path ? path.transformation : Geom::Transformation.new
          n = unit(face.normal.transform(tr))
          y = n.reverse
          z0 = Geom::Vector3d.new(0,0,1)
          z = z0 - y * z0.dot(y)
          if z.length < 0.001
            x0 = Geom::Vector3d.new(1,0,0)
            z = x0 - y * x0.dot(y)
          end
          z = unit(z)
          x = unit(z.cross(y))
          z = unit(y.cross(x))
          Geom::Transformation.axes(origin, x, y, z)
        rescue
          tt_build_frame_original_134(origin, face, path)
        end

        # Dam bao 4 thanh va tam day luon dung cung mot quy uoc local:
        # z=0 la mat duoi cua thanh; mat tren tam day cung cham z=0.
        alias_method :tt_create_original_134, :create unless method_defined?(:tt_create_original_134)
        def create(p2)
          d = measure(@p1,p2)
          if d.values_at(:dw,:dh,:dd).any?{|v| v.to_f <= 0}
            return UI.messagebox("Không đủ không gian. Vùng R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])}")
          end
          # Dung ham tao goc sau khi da sua he truc; ham goc da dat:
          # thanh sau = y + rd - t, day = z - bottom_t.
          tt_create_original_134(p2)
        rescue => e
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
        end
      end
    end
  end
end
