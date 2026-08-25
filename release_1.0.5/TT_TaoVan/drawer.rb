module TranTuan
  module TaoVan
    module Drawer
      module_function

      TAB_KEY = 9

      def mm(v); v.to_f.mm; end
      def mm_text(v, decimals = 1); format("%0.#{decimals}f mm", v.to_f); end
      def parse_mm(v)
        s = v.to_s.strip.downcase.gsub(',', '.')
        s = s.sub(/\s*mm\s*\z/, '')
        Float(s)
      rescue
        nil
      end

      def start
        Sketchup.active_model.select_tool(TwoPointTool.new)
      end

      class TwoPointTool
        def initialize
          @ip = Sketchup::InputPoint.new
          @p1 = @p2 = nil
          @container = nil
          @preview = nil
          @manual_mode = false
          @manual_ready = false
          @manual_origin = nil
          @manual_values = nil
          @tab_lock = false
        end

        def activate
          update_status
        end

        def deactivate(view)
          @preview = nil
          view.invalidate if view
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p = @ip.position

          if @manual_mode
            @manual_origin ||= p
            @preview = @manual_ready ? [@manual_origin, p] : [p]
            view.invalidate
            return
          end

          @preview = @p1 ? [@p1, p] : [p]
          view.invalidate
          if @p1
            h_mm = (@p1.transform(@container.transformation.inverse).z - p.transform(@container.transformation.inverse).z).abs.to_mm
            Sketchup.set_status_text("TỰ ĐỘNG 2 ĐIỂM | ĐIỂM 1: MẶT TRÊN → ĐIỂM 2: ĐÁY | CAO: #{Drawer.mm_text(h_mm)} | ĐƠN VỊ: mm | TAB = THỦ CÔNG", SB_VCB_LABEL)
          end
        end

        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(255, 128, 0, 255)

          if @manual_mode && @manual_ready && @manual_values
            ox, oy, oz = @manual_origin.to_a
            w, d, h = @manual_values[0, 3].map { |v| Drawer.mm(v) }
            draw_box(view, box_points(ox, oy, oz, w, d, h))
            return
          end

          if @preview.length == 1
            p = @preview[0]
            s = Drawer.mm(12)
            view.draw(GL_LINES,
              Geom::Point3d.new(p.x - s, p.y, p.z), Geom::Point3d.new(p.x + s, p.y, p.z),
              Geom::Point3d.new(p.x, p.y - s, p.z), Geom::Point3d.new(p.x, p.y + s, p.z))
            return
          end

          a, b = @preview
          if @container && @container.valid?
            lb = local_bounds(@container)
            tr = @container.transformation
            la = a.transform(tr.inverse)
            lbp = b.transform(tr.inverse)
            z0 = [la.z, lbp.z].min
            z1 = [la.z, lbp.z].max
            pts = box_points(lb.min.x, lb.min.y, z0, lb.width, lb.depth, z1 - z0).map { |q| q.transform(tr) }
            draw_box(view, pts)
          else
            z0 = [a.z, b.z].min
            z1 = [a.z, b.z].max
            draw_box(view, box_points([a.x, b.x].min, [a.y, b.y].min, z0, (a.x - b.x).abs, (a.y - b.y).abs, z1 - z0))
          end
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p = @ip.position

          if @manual_mode
            unless @manual_ready
              @manual_origin = p
              manual_create
              return
            end
            create_manual_from_preview
            return
          end

          if @p1.nil?
            @p1 = p
            @container = direct_container(@ip)
            unless @container
              UI.messagebox('Điểm 1 phải nằm trên Face thuộc Group/Component của khoang tủ.')
              reset
              return
            end
            set_waiting_status('TỰ ĐỘNG 2 ĐIỂM', 'ĐIỂM 1 ĐÃ NHẬN → DI CHUỘT XUỐNG MẶT ĐÁY → CLICK ĐIỂM 2')
            view.invalidate
          else
            @p2 = p
            create_from_two_points
          end
        end

        def onKeyDown(key, _repeat, _flags, view)
          if key == TAB_KEY
            return if @tab_lock
            @tab_lock = true
            @manual_mode = !@manual_mode
            clear_points_only
            update_status
            view.invalidate if view
          elsif key == 27
            Sketchup.active_model.select_tool(nil)
          end
        end

        def onKeyUp(key, _repeat, _flags, _view)
          @tab_lock = false if key == TAB_KEY
        end

        private

        def set_waiting_status(mode, detail)
          Sketchup.set_status_text("TT NGĂN KÉO | CHẾ ĐỘ CHỜ | #{mode} | ĐƠN VỊ: mm | TAB = ĐỔI CHẾ ĐỘ", SB_PROMPT)
          Sketchup.set_status_text(detail, SB_VCB_LABEL)
        end

        def update_status
          if @manual_mode
            detail = @manual_ready ? 'ĐÃ NHẬP THÔNG SỐ (mm) → DI CHUỘT XEM PREVIEW → CLICK ĐỂ TẠO' : 'CLICK VỊ TRÍ ĐẶT → NHẬP THÔNG SỐ (mm) | TAB = TỰ ĐỘNG 2 ĐIỂM'
            set_waiting_status('THỦ CÔNG', detail)
          else
            set_waiting_status('TỰ ĐỘNG 2 ĐIỂM', 'CLICK 1 = MẶT TRÊN → CLICK 2 = ĐÁY | KÍCH THƯỚC: mm | TAB = THỦ CÔNG')
          end
        end

        def box_points(x, y, z, w, d, h)
          [Geom::Point3d.new(x, y, z), Geom::Point3d.new(x + w, y, z), Geom::Point3d.new(x + w, y + d, z), Geom::Point3d.new(x, y + d, z), Geom::Point3d.new(x, y, z + h), Geom::Point3d.new(x + w, y, z + h), Geom::Point3d.new(x + w, y + d, z + h), Geom::Point3d.new(x, y + d, z + h)]
        end

        def draw_box(view, pts)
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each { |i,j| view.draw(GL_LINES, pts[i], pts[j]) }
        end

        def direct_container(ip)
          path = ip.instance_path
          return nil unless path && path.respond_to?(:to_a)
          path.to_a.reverse_each { |e| return e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          nil
        end

        # Bounding box luôn được chuẩn hóa về hệ trục LOCAL của instance.
        # Không dùng container.entities.bounds vì Sketchup::Entities không có method bounds.
        def local_bounds(container)
          tr = container.transformation
          inv = tr.inverse
          wb = container.bounds
          lb = Geom::BoundingBox.new
          8.times { |i| lb.add(wb.corner(i).transform(inv)) }
          lb
        end

        def same_container?(a, b)
          return false unless a && b && a.valid? && b.valid?
          return true if a.equal?(b)
          a.respond_to?(:persistent_id) && b.respond_to?(:persistent_id) && a.persistent_id == b.persistent_id
        end

        def create_from_two_points
          model = Sketchup.active_model
          unless @container && @container.valid?
            UI.messagebox('Không xác định được Group/Component của khoang tủ.')
            reset
            return
          end

          c2 = direct_container(@ip)
          unless same_container?(@container, c2)
            UI.messagebox('Điểm 2 phải nằm trên Face thuộc cùng Group/Component với điểm 1.')
            reset
            return
          end

          tr = @container.transformation
          inv = tr.inverse
          p1l = @p1.transform(inv)
          p2l = @p2.transform(inv)
          if p1l.z <= p2l.z
            UI.messagebox('Sai thứ tự: ĐIỂM 1 phải ở MẶT TRÊN và ĐIỂM 2 phải ở ĐÁY.')
            reset
            return
          end

          h_local = p1l.z - p2l.z
          if h_local <= Drawer.mm(1)
            UI.messagebox('Chiều cao giữa điểm 1 và điểm 2 phải lớn hơn 1 mm.')
            reset
            return
          end

          b = local_bounds(@container)
          w_local = b.width
          d_local = b.depth
          if w_local <= 0 || d_local <= 0
            UI.messagebox('Không xác định được Rộng/Sâu theo trục của Group/Component.')
            reset
            return
          end

          create_drawer_local(model, tr, b.min.x, b.min.y, p2l.z, w_local, d_local, h_local, 18.0, 9.0, 2.0, 2.0)
        rescue => e
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          reset
        end

        def manual_create
          prompts = ['Rộng phủ bì (mm)', 'Sâu phủ bì (mm)', 'Cao ngăn kéo (mm)', 'Độ dày ván (mm)', 'Khe hở trái/phải (mm)', 'Khe hở trước/sau (mm)', 'Độ dày đáy (mm)', 'Đáy cách đáy hông (mm)']
          defaults = [600, 450, 150, 18, 2, 2, 9, 0]
          values = UI.inputbox(prompts, defaults, 'TT - Tạo ngăn kéo thủ công | Đơn vị: mm')
          return unless values
          vals = values.map { |v| Drawer.parse_mm(v) }
          valid = vals.all? { |v| v.is_a?(Numeric) && v.finite? } && vals[0] > 0 && vals[1] > 0 && vals[2] > 0 && vals[3] > 0 && vals[4] >= 0 && vals[5] >= 0 && vals[6] > 0 && vals[7] >= 0
          unless valid
            UI.messagebox('Thông số không hợp lệ. Tất cả kích thước phải nhập bằng mm. Ví dụ: 600 hoặc 600 mm.')
            return
          end
          @manual_values = vals
          @manual_ready = true
          update_status
        end

        def create_manual_from_preview
          w, d, h, t, gl, gf, bt, bo = @manual_values
          create_drawer_world(Sketchup.active_model, @manual_origin.x, @manual_origin.y, @manual_origin.z, w, d, h, t, bt, gl, gf, bo)
        end

        def create_drawer_local(model, tr, ox, oy, oz, w_local, d_local, h_local, t_mm, bt_mm, gl_mm, gf_mm)
          scale_x = Geom::Vector3d.new(1, 0, 0).transform(tr).length
          scale_y = Geom::Vector3d.new(0, 1, 0).transform(tr).length
          scale_z = Geom::Vector3d.new(0, 0, 1).transform(tr).length
          w_mm = w_local.to_f * scale_x.to_f * 25.4
          d_mm = d_local.to_f * scale_y.to_f * 25.4
          h_mm = h_local.to_f * scale_z.to_f * 25.4
          iw_local = w_local - Drawer.mm(2 * gl_mm + 2 * t_mm) / scale_x
          id_local = d_local - Drawer.mm(2 * gf_mm + 2 * t_mm) / scale_y
          h_use = h_local
          unless iw_local > 0 && id_local > 0 && h_use > Drawer.mm(t_mm) / scale_z
            UI.messagebox('Kích thước khoang không đủ cho độ dày ván và khe hở đã nhập.')
            reset
            return
          end

          model.start_operation('TT - Tạo ngăn kéo tự động', true)
          outer = model.entities.add_group
          outer.name = 'TT - Ngăn kéo'
          add_part = lambda do |name, x, y, z, sx, sy, sz|
            g = outer.entities.add_group
            g.name = name
            f = g.entities.add_face([Geom::Point3d.new(x, y, z), Geom::Point3d.new(x + sx, y, z), Geom::Point3d.new(x + sx, y + sy, z), Geom::Point3d.new(x, y + sy, z)])
            f.reverse! if f.normal.z < 0
            f.pushpull(sz)
            g
          end

          t_x = Drawer.mm(t_mm) / scale_x
          t_y = Drawer.mm(t_mm) / scale_y
          bt_z = Drawer.mm(bt_mm) / scale_z
          gl_x = Drawer.mm(gl_mm) / scale_x
          gf_y = Drawer.mm(gf_mm) / scale_y
          add_part.call('Đáy', ox + t_x + gl_x, oy + t_y + gf_y, oz, iw_local, id_local, bt_z)
          add_part.call('Hông trái', ox, oy, oz, t_x, d_local, h_use)
          add_part.call('Hông phải', ox + w_local - t_x, oy, oz, t_x, d_local, h_use)
          # Quy ước: mặt trước ở MIN Y, mặt sau ở MAX Y.
          add_part.call('Mặt trước', ox + t_x, oy, oz, iw_local, t_y, h_use)
          add_part.call('Mặt sau', ox + t_x, oy + d_local - t_y, oz, iw_local, t_y, h_use)
          outer.transform!(tr)

          store_attributes(outer, w_mm, d_mm, h_mm, t_mm, bt_mm, false)
          model.commit_operation
          model.selection.clear
          model.selection.add(outer)
          Sketchup.set_status_text("Đã tạo ngăn kéo: #{Drawer.mm_text(w_mm)} × #{Drawer.mm_text(d_mm)} × #{Drawer.mm_text(h_mm)}", SB_PROMPT)
          reset
        rescue => e
          model.abort_operation rescue nil
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          reset
        end

        def create_drawer_world(model, ox, oy, oz, w_mm, d_mm, h_mm, t_mm, bt_mm, gl_mm, gf_mm, bo_mm)
          iw_mm = w_mm - 2 * t_mm - 2 * gl_mm
          id_mm = d_mm - 2 * t_mm - 2 * gf_mm
          if iw_mm <= 0 || id_mm <= 0 || h_mm <= t_mm
            UI.messagebox('Kích thước ngăn kéo không đủ. Tất cả kích thước tính bằng mm.')
            reset
            return
          end

          model.start_operation('TT - Tạo ngăn kéo thủ công', true)
          outer = model.entities.add_group
          outer.name = 'TT - Ngăn kéo'
          add_part = lambda do |name, x, y, z, sx, sy, sz|
            g = outer.entities.add_group
            g.name = name
            f = g.entities.add_face([Geom::Point3d.new(x, y, z), Geom::Point3d.new(x + sx, y, z), Geom::Point3d.new(x + sx, y + sy, z), Geom::Point3d.new(x, y + sy, z)])
            f.reverse! if f.normal.z < 0
            f.pushpull(sz)
            g
          end
          t = Drawer.mm(t_mm); bt = Drawer.mm(bt_mm); gl = Drawer.mm(gl_mm); gf = Drawer.mm(gf_mm)
          w = Drawer.mm(w_mm); d = Drawer.mm(d_mm); h = Drawer.mm(h_mm); iw = Drawer.mm(iw_mm); id = Drawer.mm(id_mm); bo = Drawer.mm(bo_mm)
          add_part.call('Đáy', ox + t + gl, oy + t + gf, oz + bo, iw, id, bt)
          add_part.call('Hông trái', ox, oy, oz, t, d, h)
          add_part.call('Hông phải', ox + w - t, oy, oz, t, d, h)
          add_part.call('Mặt trước', ox + t, oy, oz, iw, t, h)
          add_part.call('Mặt sau', ox + t, oy + d - t, oz, iw, t, h)
          store_attributes(outer, w_mm, d_mm, h_mm, t_mm, bt_mm, true)
          model.commit_operation
          model.selection.clear
          model.selection.add(outer)
          Sketchup.set_status_text("Đã tạo ngăn kéo: #{Drawer.mm_text(w_mm)} × #{Drawer.mm_text(d_mm)} × #{Drawer.mm_text(h_mm)}", SB_PROMPT)
          reset
        rescue => e
          model.abort_operation rescue nil
          UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          reset
        end

        def store_attributes(outer, w_mm, d_mm, h_mm, t_mm, bt_mm, manual)
          outer.set_attribute('TT_TaoVan', 'loai', 'ngan_keo')
          outer.set_attribute('TT_TaoVan', 'don_vi', 'mm')
          outer.set_attribute('TT_TaoVan', 'tao_bang_2_diem', !manual)
          outer.set_attribute('TT_TaoVan', 'tao_thu_cong', manual)
          outer.set_attribute('TT_TaoVan', 'rong_mm', w_mm.to_f)
          outer.set_attribute('TT_TaoVan', 'sau_mm', d_mm.to_f)
          outer.set_attribute('TT_TaoVan', 'cao_mm', h_mm.to_f)
          outer.set_attribute('TT_TaoVan', 'day_mm', t_mm.to_f)
          outer.set_attribute('TT_TaoVan', 'day_da_mm', bt_mm.to_f)
        end

        def clear_points_only
          @p1 = @p2 = nil
          @container = nil
          @preview = nil
          @manual_ready = false
          @manual_origin = nil
          @manual_values = nil
        end

        def reset
          clear_points_only
          update_status
        end
      end
    end
  end
end
