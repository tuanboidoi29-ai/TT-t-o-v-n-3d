module TranTuan
  module TaoVan
    module Drawer
      module_function

      TAB_KEY = 9
      DICT = 'TT_TaoVan_Drawer'
      ZERO_TOL_MM = 0.5

      def mm(v)
        v.to_f.mm
      end

      def mm_text(v)
        format('%.1f mm', v.to_f)
      end

      def parse_mm(v)
        Float(v.to_s.strip.downcase.gsub(',', '.').sub(/\s*mm\s*\z/, ''))
      rescue
        nil
      end

      def defaults
        m = Sketchup.active_model
        side = m.get_attribute(DICT, 'side_t', nil)
        side = 17.5 if side.nil? || side.to_f <= 0 || (side.to_f - 18.0).abs < 0.01
        cfg = {
          'rail_gap'      => m.get_attribute(DICT, 'rail_gap', 14.0),
          'gap_top'       => m.get_attribute(DICT, 'gap_top', 20.0),
          'gap_bottom'    => m.get_attribute(DICT, 'gap_bottom', 0.0),
          'gap_front'     => m.get_attribute(DICT, 'gap_front', 0.0),
          'depth_reserve' => m.get_attribute(DICT, 'depth_reserve', 60.0),
          'side_t'        => side,
          'back_t'        => m.get_attribute(DICT, 'back_t', 9.0),
          'bottom_t'      => m.get_attribute(DICT, 'bottom_t', 9.0),
          'front_t'       => m.get_attribute(DICT, 'front_t', 18.0)
        }
        m.set_attribute(DICT, 'side_t', side.to_f)
        cfg
      end

      def start
        Sketchup.active_model.select_tool(TwoPointTool.new(defaults))
      end

      def save_settings(vals)
        vals.each { |k, v| Sketchup.active_model.set_attribute(DICT, k, v.to_f) }
      end

      def show_settings(tool = nil)
        d = defaults
        @dialog ||= UI::HtmlDialog.new(
          dialog_title: 'TT - CÀI ĐẶT NGĂN KÉO AUTO',
          preferences_key: 'TT_TaoVan_Drawer_Auto_v119',
          scrollable: true,
          resizable: true,
          width: 450,
          height: 680,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save_settings') do |_ctx, json|
          begin
            data = JSON.parse(json)
            vals = {}
            data.each { |k, v| vals[k] = parse_mm(v) }
            raise 'Thông số phải là số mm không âm.' if vals.any? { |_k, v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Độ dày vật liệu phải lớn hơn 0.' if %w[side_t back_t bottom_t front_t].any? { |k| vals[k] <= 0 }
            save_settings(vals)
            @dialog.close
            if tool
              tool.apply_settings(vals)
              Sketchup.active_model.select_tool(tool)
            else
              Sketchup.active_model.select_tool(TwoPointTool.new(vals))
            end
          rescue => e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end

      def settings_html(d)
        rows = [
          ['rail_gap', 'Khoảng ray mỗi bên', d['rail_gap']],
          ['gap_top', 'Hở trên', d['gap_top']],
          ['gap_bottom', 'Hở dưới', d['gap_bottom']],
          ['gap_front', 'Hở phía trước', d['gap_front']],
          ['depth_reserve', 'Chừa phía sau', d['depth_reserve']],
          ['side_t', 'Độ dày hông', d['side_t']],
          ['back_t', 'Độ dày hậu', d['back_t']],
          ['bottom_t', 'Độ dày đáy', d['bottom_t']],
          ['front_t', 'Độ dày mặt trước', d['front_t']]
        ].map do |k, label, value|
          "<label>#{label}</label><input id='#{k}' value='#{value}' style='width:95px;background:#252930;color:white;border:1px solid #444;border-radius:6px;padding:8px;text-align:right'>"
        end.join

        "<!doctype html><html><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'><h2 style='margin:0 0 6px'>TT - CÀI ĐẶT NGĂN KÉO AUTO</h2><div style='color:#ff9b43;font-weight:bold;margin-bottom:12px'>TAB = CÀI ĐẶT | AUTO 2 ĐIỂM | ĐƠN VỊ mm</div><div style='background:#242830;padding:10px;border-radius:8px;line-height:1.5'>Mặc định: ray 14 mm mỗi bên, hở trên 20 mm, hông 17,5 mm. Sau click điểm 2, hệ thống lấy Rộng và Cao từ vùng chọn; nếu hai điểm nằm cùng mặt trước, hệ thống tự quét chiều sâu LOCAL của Group/Component lớn nhất chứa điểm 1.</div><div style='display:grid;grid-template-columns:1fr 95px;gap:8px;align-items:center;margin-top:16px'>#{rows}</div><div style='font-size:12px;color:#9da3ad;margin-top:14px'>Ví dụ vùng 300 × 300 × 300: rộng ngăn kéo = 300 - 14 - 14 = 272 mm; cao = 300 - 20 = 280 mm; sâu = 300 - 60 = 240 mm.</div><button style='margin-top:18px;width:100%;padding:12px;background:#ff7a00;color:white;border:0;border-radius:8px;font-weight:bold' onclick='save()'>LƯU & TIẾP TỤC AUTO</button><script>function save(){let ids=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','side_t','back_t','bottom_t','front_t'];let o={};ids.forEach(id=>o[id]=document.getElementById(id).value);sketchup.save_settings(JSON.stringify(o));}</script></body></html>"
      end

      class TwoPointTool
        def initialize(cfg)
          @cfg = cfg
          @ip = Sketchup::InputPoint.new
          @p1 = nil
          @container = nil
          @preview = nil
          @preview_region = nil
          @preview_drawer = nil
        end

        def activate
          status('AUTO: CLICK ĐIỂM 1 → CLICK ĐIỂM 2 | TAB: CÀI ĐẶT | ESC: THOÁT')
        end

        def deactivate(view)
          view.invalidate if view
        end

        def apply_settings(cfg)
          @cfg = cfg
          reset_points
          status('ĐÃ LƯU CÀI ĐẶT → AUTO: CLICK ĐIỂM 1')
        end

        def onKeyDown(key, *_args)
          if key == TAB_KEY
            Drawer.show_settings(self)
            return true
          elsif key == 27
            Sketchup.active_model.select_tool(nil)
            return true
          end
          false
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p = @ip.position
          @preview = @p1 ? [@p1, p] : [p]

          if @p1
            d = measure(@p1, p)
            @preview_region = region(@p1, p)
            @preview_drawer = drawer_preview(@preview_region, d)
            status("VÙNG #{Drawer.mm_text(d[:w])} × #{Drawer.mm_text(d[:d])} × #{Drawer.mm_text(d[:h])} → NGĂN KÉO #{Drawer.mm_text(d[:dw])} × #{Drawer.mm_text(d[:dd])} × #{Drawer.mm_text(d[:dh])} | RAY #{Drawer.mm_text(@cfg['rail_gap'])}/BÊN | HÔNG #{Drawer.mm_text(@cfg['side_t'])}")
          end
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          p = @ip.position
          if @p1.nil?
            @p1 = p
            @container = best_container(@ip)
            status('ĐÃ NHẬN ĐIỂM 1 → CLICK ĐIỂM 2 | TỰ QUÉT RỘNG × CAO × SÂU')
          else
            create(p)
          end
          view.invalidate
        end

        def draw(view)
          return unless @preview && !@preview.empty?
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(255, 128, 0, 255)

          if @preview.length == 1
            p = @preview[0]
            s = Drawer.mm(12)
            view.draw(GL_LINES,
                      Geom::Point3d.new(p.x - s, p.y, p.z), Geom::Point3d.new(p.x + s, p.y, p.z),
                      Geom::Point3d.new(p.x, p.y - s, p.z), Geom::Point3d.new(p.x, p.y + s, p.z))
            return
          end

          r = @preview_drawer || @preview_region
          return unless r
          pts = box_points(r[:x], r[:y], r[:z], r[:w], r[:d], r[:h], r[:tr])
          view.drawing_color = Sketchup::Color.new(255, 128, 0, 110)
          view.line_width = 4
          [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].each do |i, j|
            view.draw(GL_LINES, pts[i], pts[j])
          end
          view.line_width = 1
        end

        private

        def status(text)
          Sketchup.set_status_text('TT NGĂN KÉO AUTO | mm', SB_PROMPT)
          Sketchup.set_status_text(text, SB_VCB_LABEL)
        end

        def reset_points
          @p1 = nil
          @container = nil
          @preview = nil
          @preview_region = nil
          @preview_drawer = nil
        end

        def best_container(ip)
          path = ip.instance_path
          return nil unless path
          candidates = path.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
          candidates.max_by do |entity|
            bb = entity.bounds
            bb.width.to_f * bb.depth.to_f * bb.height.to_f
          end
        rescue
          nil
        end

        def local_bounds
          return nil unless @container && @container.valid?
          bb = @container.bounds
          return nil if bb.empty?
          bb
        rescue
          nil
        end

        def local_points(a, b)
          return [a, b, nil] unless @container && @container.valid?
          tr = @container.transformation
          [a.transform(tr.inverse), b.transform(tr.inverse), tr]
        end

        def region(a, b)
          x, y, tr = local_points(a, b)
          xmin, xmax = [x.x, y.x].minmax
          zmin, zmax = [x.z, y.z].minmax
          ymin, ymax = [x.y, y.y].minmax
          inferred = false

          # Hai điểm cùng nằm trên mặt trước: tự lấy toàn bộ chiều sâu LOCAL.
          if (ymax - ymin).abs.to_mm < ZERO_TOL_MM
            bb = local_bounds
            if bb && bb.depth.to_mm > ZERO_TOL_MM
              ymin = bb.min.y
              ymax = bb.max.y
              inferred = true
            end
          end

          { x: xmin, y: ymin, z: zmin, w: xmax - xmin, d: ymax - ymin, h: zmax - zmin, tr: tr, inferred_depth: inferred }
        end

        def measure(a, b)
          r = region(a, b)
          w = r[:w].to_mm
          d = r[:d].to_mm
          h = r[:h].to_mm
          rail = @cfg['rail_gap'].to_f
          {
            w: w,
            d: d,
            h: h,
            dw: w - (rail * 2.0),
            dd: d - @cfg['depth_reserve'].to_f - @cfg['gap_front'].to_f,
            dh: h - @cfg['gap_top'].to_f - @cfg['gap_bottom'].to_f,
            inferred_depth: r[:inferred_depth]
          }
        end

        def drawer_preview(r, d)
          return nil if d[:dw] <= 0 || d[:dd] <= 0 || d[:dh] <= 0
          rail = Drawer.mm(@cfg['rail_gap'])
          {
            x: r[:x] + rail,
            y: r[:y] + Drawer.mm(@cfg['gap_front']),
            z: r[:z] + Drawer.mm(@cfg['gap_bottom']),
            w: Drawer.mm(d[:dw]),
            d: Drawer.mm(d[:dd]),
            h: Drawer.mm(d[:dh]),
            tr: r[:tr]
          }
        end

        def create(p2)
          d = measure(@p1, p2)
          if d.values_at(:dw, :dd, :dh).any? { |value| value <= 0 }
            UI.messagebox("Không đủ không gian để tạo ngăn kéo.\n\nVùng quét: #{Drawer.mm_text(d[:w])} × #{Drawer.mm_text(d[:d])} × #{Drawer.mm_text(d[:h])}\nKích thước ngăn kéo: #{Drawer.mm_text(d[:dw])} × #{Drawer.mm_text(d[:dd])} × #{Drawer.mm_text(d[:dh])}\n\nRay: #{Drawer.mm_text(@cfg['rail_gap'])}/bên | Hông: #{Drawer.mm_text(@cfg['side_t'])} | Chừa sâu: #{Drawer.mm_text(@cfg['depth_reserve'])}")
            return
          end

          model = Sketchup.active_model
          model.start_operation('TT - Tạo ngăn kéo AUTO', true)
          begin
            r = region(@p1, p2)
            rw = Drawer.mm(d[:dw])
            rd = Drawer.mm(d[:dd])
            rh = Drawer.mm(d[:dh])
            side_t = Drawer.mm(@cfg['side_t'])
            back = Drawer.mm(@cfg['back_t'])
            bottom = Drawer.mm(@cfg['bottom_t'])
            front = Drawer.mm(@cfg['front_t'])
            x = r[:x] + Drawer.mm(@cfg['rail_gap'])
            y = r[:y] + Drawer.mm(@cfg['gap_front'])
            z = r[:z] + Drawer.mm(@cfg['gap_bottom'])

            group = model.entities.add_group
            group.name = 'TT - Ngăn kéo AUTO'
            add_part(group, 'Hông trái', x, y, z, side_t, rd, rh)
            add_part(group, 'Hông phải', x + rw - side_t, y, z, side_t, rd, rh)
            add_part(group, 'Đáy', x, y, z, rw, rd, bottom)
            add_part(group, 'Mặt trước', x, y, z, rw, front, rh)
            add_part(group, 'Hậu', x, y + rd - back, z, rw, back, rh)

            group.set_attribute(DICT, 'don_vi', 'mm')
            group.set_attribute(DICT, 'vung_rong_mm', d[:w])
            group.set_attribute(DICT, 'vung_sau_mm', d[:d])
            group.set_attribute(DICT, 'vung_cao_mm', d[:h])
            group.set_attribute(DICT, 'rong_mm', d[:dw])
            group.set_attribute(DICT, 'sau_mm', d[:dd])
            group.set_attribute(DICT, 'cao_mm', d[:dh])
            group.set_attribute(DICT, 'ray_moi_ben_mm', @cfg['rail_gap'].to_f)
            group.set_attribute(DICT, 'do_day_hong_mm', @cfg['side_t'].to_f)
            group.set_attribute(DICT, 'cho_sau_mm', @cfg['depth_reserve'].to_f)
            group.set_attribute(DICT, 'chieu_sau_tu_dong', !!d[:inferred_depth])
            group.transform!(r[:tr]) if r[:tr]

            model.commit_operation
            reset_points
            Sketchup.active_model.select_tool(self)
            status('ĐÃ TẠO → CLICK ĐIỂM 1 TIẾP THEO')
          rescue => e
            model.abort_operation rescue nil
            UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          end
        end

        def box_points(x, y, z, w, d, h, tr)
          points = [
            Geom::Point3d.new(x, y, z), Geom::Point3d.new(x + w, y, z),
            Geom::Point3d.new(x + w, y + d, z), Geom::Point3d.new(x, y + d, z),
            Geom::Point3d.new(x, y, z + h), Geom::Point3d.new(x + w, y, z + h),
            Geom::Point3d.new(x + w, y + d, z + h), Geom::Point3d.new(x, y + d, z + h)
          ]
          tr ? points.map { |p| p.transform(tr) } : points
        end

        def add_part(group, name, x, y, z, w, d, h)
          return if w <= 0 || d <= 0 || h <= 0
          part = group.entities.add_group
          part.name = name
          face = part.entities.add_face([
            Geom::Point3d.new(x, y, z),
            Geom::Point3d.new(x + w, y, z),
            Geom::Point3d.new(x + w, y + d, z),
            Geom::Point3d.new(x, y + d, z)
          ])
          face.pushpull(h) if face
        end
      end
    end
  end
end
