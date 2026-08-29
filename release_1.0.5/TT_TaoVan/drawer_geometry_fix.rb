# TT - NGAN KEO AUTO - GEOMETRY DIRECTION FIX 1.3.5
# Quy uoc: thanh truoc o dau khoang, thanh sau o cuoi khoang,
# tam day nam ngang ben duoi 4 thanh.
# HAU LOT/PHU KHONG TAO THEM MOT TAM DUNG RIENG.
module TranTuan
  module TaoVan
    module Drawer
      class TwoPointTool
        alias_method :tt_build_frame_original_135, :build_frame unless method_defined?(:tt_build_frame_original_135)
        alias_method :tt_create_original_135, :create unless method_defined?(:tt_create_original_135)

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
          tt_build_frame_original_135(origin, face, path)
        end

        # Khong tao them mot tam dung khi bat HAU.
        # HAU LOT/PHU chi la che do tinh/ghi nhan; tam day van la tam day.
        def add_rear(*_args)
          nil
        end

        def create(p2)
          d = measure(@p1,p2)
          if d.values_at(:dw,:dh,:dd).any?{|v| v.to_f <= 0}
            return UI.messagebox("Không đủ không gian. Vùng R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])}")
          end
          tt_create_original_135(p2)
        rescue => e
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
        end
      end
    end
  end
end
