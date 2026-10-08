# encoding: UTF-8
module TranTuanNoiThat
  module WineRack
    extend self

    EPS_MM = 1.0e-6

    # Convex polygon clipping in millimetres.
    def clip(poly, n, c)
      out = []
      poly.each_with_index do |a, i|
        b = poly[(i + 1) % poly.length]
        da = a[0] * n[0] + a[1] * n[1] - c
        db = b[0] * n[0] + b[1] * n[1] - c

        out << a if da <= 1.0e-7

        if (da < 0 && db > 0) || (da > 0 && db < 0)
          f = da / (da - db)
          out << [
            a[0] + f * (b[0] - a[0]),
            a[1] + f * (b[1] - a[1])
          ]
        end
      end

      out = out.each_with_object([]) do |point, result|
        if result.empty? ||
           Math.hypot(point[0] - result[-1][0], point[1] - result[-1][1]) > EPS_MM
          result << point
        end
      end

      if out.length > 1 &&
         Math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) < EPS_MM
        out.pop
      end

      out
    end

    def area(poly)
      return 0.0 if poly.length < 3
      poly.each_with_index.sum do |a, i|
        b = poly[(i + 1) % poly.length]
        a[0] * b[1] - a[1] * b[0]
      end.abs / 2.0
    end

    def signed_area(poly)
      return 0.0 if poly.length < 3
      poly.each_with_index.sum do |a, i|
        b = poly[(i + 1) % poly.length]
        a[0] * b[1] - a[1] * b[0]
      end / 2.0
    end

    def cross2(ax, ay, bx, by)
      ax * by - ay * bx
    end

    def convex_intersection(subject, clipper)
      return [] if subject.length < 3 || clipper.length < 3

      clip = signed_area(clipper) >= 0 ? clipper : clipper.reverse
      output = subject.dup

      clip.each_with_index do |cp1, i|
        cp2 = clip[(i + 1) % clip.length]
        input = output
        output = []
        break if input.empty?

        edge_x = cp2[0] - cp1[0]
        edge_y = cp2[1] - cp1[1]

        inside = lambda do |p|
          cross2(edge_x, edge_y, p[0] - cp1[0], p[1] - cp1[1]) >= -1.0e-7
        end

        intersect = lambda do |s, e|
          rx = e[0] - s[0]
          ry = e[1] - s[1]
          den = cross2(rx, ry, edge_x, edge_y)
          return e if den.abs < 1.0e-12

          qx = cp1[0] - s[0]
          qy = cp1[1] - s[1]
          t = cross2(qx, qy, edge_x, edge_y) / den
          [s[0] + t * rx, s[1] + t * ry]
        end

        s = input[-1]
        input.each do |e|
          s_in = inside.call(s)
          e_in = inside.call(e)

          if e_in
            output << intersect.call(s, e) unless s_in
            output << e
          elsif s_in
            output << intersect.call(s, e)
          end

          s = e
        end
      end

      output
    end

    def polygon_center(poly)
      return [0.0, 0.0] if poly.empty?
      [
        poly.sum { |p| p[0] } / poly.length.to_f,
        poly.sum { |p| p[1] } / poly.length.to_f
      ]
    end

    # Nới footprint dao cực nhỏ để boolean không bị mặt đồng phẳng.
    # Phần nới nằm ngoài thanh nên không làm rãnh thực tế rộng thêm đáng kể.
    def expand_from_center(poly, epsilon = 0.10)
      center = polygon_center(poly)
      poly.map do |p|
        dx = p[0] - center[0]
        dy = p[1] - center[1]
        len = Math.hypot(dx, dy)
        next p.dup if len < 1.0e-9
        scale = (len + epsilon) / len
        [center[0] + dx * scale, center[1] + dy * scale]
      end
    end

    def rect(x, y, w, h)
      [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
    end

    # Đưa các đầu nan về đúng tọa độ tiếp xúc chung.
    # Việc canonicalize này tránh khe hở cực nhỏ giữa nan-nan và nan-khung.
    def canonical_point(point, x0, y0, x1, y1)
      x = point[0].to_f
      y = point[1].to_f

      x = x0 if (x - x0).abs <= 1.0e-5
      x = x1 if (x - x1).abs <= 1.0e-5
      y = y0 if (y - y0).abs <= 1.0e-5
      y = y1 if (y - y1).abs <= 1.0e-5

      [x.round(6), y.round(6)]
    end

    def canonical_poly(poly, x0, y0, x1, y1)
      clean = poly.map { |point| canonical_point(point, x0, y0, x1, y1) }

      clean = clean.each_with_object([]) do |point, result|
        if result.empty? ||
           Math.hypot(point[0] - result[-1][0], point[1] - result[-1][1]) > EPS_MM
          result << point
        end
      end

      if clean.length > 1 &&
         Math.hypot(clean[0][0] - clean[-1][0], clean[0][1] - clean[-1][1]) < EPS_MM
        clean.pop
      end

      clean
    end

    # frame = true  -> có 4 tấm khung viền.
    # frame = false -> nan được cắt đúng tới biên P1/P2.
    def layout(w, h, t, target, kind, frame = true)
      raise 'Độ dày ván phải lớn hơn 0.' unless t.finite? && t > 0
      raise 'Kích thước ô phải lớn hơn độ dày ván.' unless target.finite? && target > t

      border = frame ? t : 0.0
      x0 = border
      y0 = border
      x1 = w - border
      y1 = h - border
      iw = x1 - x0
      ih = y1 - y0

      raise 'Vùng quá nhỏ so với độ dày ván.' unless iw > t + 1.0 && ih > t + 1.0

      polys = []
      meta = {
        kind: kind,
        frame: frame,
        frame_count: frame ? 4 : 0,
        family_a: [],
        family_b: [],
        intersections: []
      }

      if frame
        # Khung ngoài ghép góc 45° như cách dựng thủ công.
        polys << [[0, 0], [w, 0], [w - t, t], [t, t]]
        polys << [[t, h - t], [w - t, h - t], [w, h], [0, h]]
        polys << [[0, 0], [t, t], [t, h - t], [0, h]]
        polys << [[w, 0], [w, h], [w - t, h - t], [w - t, t]]
      end

      base = rect(x0, y0, iw, ih)

      if kind == 'Vuông'
        cols = [((iw + t) / (target + t)).ceil, 1].max
        rows = [((ih + t) / (target + t)).ceil, 1].max
        raise 'Quá nhiều ô; tăng kích thước ô mong muốn.' if cols * rows > 200

        cw = (iw - (cols - 1) * t) / cols
        ch = (ih - (rows - 1) * t) / rows
        raise 'Ô quá nhỏ.' unless cw > 1.0 && ch > 1.0

        # Nan đứng chạy liên tục và chạm chính xác khung trên/dưới.
        (1...cols).each do |i|
          x = x0 + i * cw + (i - 1) * t
          polys << rect(x, y0, t, ih)
        end

        # Nan ngang được chia theo từng khoang, đầu nan kết thúc đúng tại
        # cạnh nan đứng hoặc cạnh khung, nên toàn bộ giao nhau là tiếp điểm.
        cols.times do |i|
          cell_x = x0 + i * (cw + t)
          (1...rows).each do |j|
            y = y0 + j * ch + (j - 1) * t
            polys << rect(cell_x, y, cw, t)
          end
        end

        frame_note = frame ? 'KHUNG BẬT' : 'KHUNG TẮT'
        note = "#{cols} cột × #{rows} hàng · Lọt lòng #{cw.round(1)} × #{ch.round(1)} mm · #{frame_note}"
      else
        # Ô chéo dựng theo tâm khung:
        # - 2 họ nan liên tục ±45°
        # - đối xứng qua tâm
        # - clip đúng theo biên trong khung
        # - xác định toàn bộ giao điểm để tạo khấu âm dương 1/2 chiều sâu
        inv = 1.0 / Math.sqrt(2)
        normals = [
          [ inv,  inv],
          [-inv,  inv]
        ]

        cx = x0 + iw / 2.0
        cy = y0 + ih / 2.0
        pitch = target + t
        raise 'Ô quá nhỏ.' unless pitch > t + 1.0

        families = [[], []]

        normals.each_with_index do |normal, family_index|
          center_c = cx * normal[0] + cy * normal[1]
          offsets = base.map do |point|
            point[0] * normal[0] + point[1] * normal[1] - center_c
          end

          lo, hi = offsets.minmax
          k_min = (lo / pitch).floor - 1
          k_max = (hi / pitch).ceil + 1

          (k_min..k_max).each do |k|
            c_line = center_c + k * pitch

            poly = clip(
              clip(base, normal, c_line + t / 2.0),
              normal.map { |value| -value },
              -c_line + t / 2.0
            )

            next unless area(poly) > 0.01
            families[family_index] << poly
          end

          if families[family_index].length > 40
            raise 'Quá nhiều nan chéo; tăng kích thước ô.'
          end
        end

        frame_count = polys.length
        meta[:family_a] = (frame_count...(frame_count + families[0].length)).to_a
        polys.concat(families[0])

        family_b_start = polys.length
        meta[:family_b] = (family_b_start...(family_b_start + families[1].length)).to_a
        polys.concat(families[1])

        # Giao điểm thật = phần diện tích chồng giữa một nan họ A và một nan họ B.
        families[0].each_with_index do |poly_a, ia|
          families[1].each_with_index do |poly_b, ib|
            overlap = convex_intersection(poly_a, poly_b)
            next unless area(overlap) > 0.01

            overlap = canonical_poly(overlap, x0, y0, x1, y1)
            next unless area(overlap) > 0.01

            meta[:intersections] << {
              a_index: meta[:family_a][ia],
              b_index: meta[:family_b][ib],
              polygon: overlap,
              center: polygon_center(overlap)
            }
          end
        end

        clear_diamond = [pitch - t, 1.0].max
        frame_note = frame ? 'KHUNG BẬT' : 'KHUNG TẮT'
        note = "Ô chéo 45° · #{families[0].length} + #{families[1].length} nan · #{meta[:intersections].length} giao điểm khấu 1/2 · lọt lòng ≈ #{clear_diamond.round(1)} mm · #{frame_note}"
      end

      # Chuẩn hóa toàn bộ tọa độ giao nhau và tiếp xúc khung.
      polys = polys.map do |poly|
        canonical_poly(poly, x0, y0, x1, y1)
      end.select { |poly| area(poly) > 0.01 }

      raise 'Quá nhiều chi tiết; tăng kích thước ô.' if polys.length > 250

      [polys, note, meta]
    end

    def activate
      Sketchup.active_model.select_tool(Tool.new(17.5.mm))
    end

    class Tool < Board::Tool
      def initialize(thickness)
        super

        @wine_kind = TranTuanNoiThat.setting('wine_kind', 'Vuông')
        @wine_kind = 'Vuông' unless ['Vuông', 'Chéo'].include?(@wine_kind)

        @wine_t = TranTuanNoiThat.setting('wine_thickness', 17.5).to_f
        @wine_depth = TranTuanNoiThat.setting('wine_depth', 300).to_f
        @wine_cell = TranTuanNoiThat.setting('wine_cell', 100).to_f

        stored_frame = TranTuanNoiThat.setting('wine_frame', true)
        @wine_frame = !(
          stored_frame == false ||
          stored_frame.to_s.downcase == 'false' ||
          stored_frame.to_s == '0'
        )

        @wine_polys = []
      end

      def update(view, x, y)
        super
        @wine_polys = []
        @wine_meta = nil
        @wine_note = ''

        return unless @loops && @loops.first && @loops.first.length == 4 && @p1

        p, a, _q, b = @loops.first
        u = a - p
        v = b - p

        return if u.length < 0.1.mm || v.length < 0.1.mm

        @wine_polys, @wine_note, @wine_meta = WineRack.layout(
          u.length.to_mm,
          v.length.to_mm,
          @wine_t,
          @wine_cell,
          @wine_kind,
          @wine_frame
        )

        @wine_origin = p
        @wine_u = u.normalize
        @wine_v = v.normalize
      rescue StandardError => error
        @wine_polys = []
        @wine_note = error.message
      end

      def world(point, back = false)
        pt = @wine_origin
          .offset(@wine_u, point[0].mm)
          .offset(@wine_v, point[1].mm)

        back ? pt.offset(displacement, @wine_depth.mm) : pt
      end

      def world_depth(point, depth_mm)
        @wine_origin
          .offset(@wine_u, point[0].mm)
          .offset(@wine_v, point[1].mm)
          .offset(displacement, depth_mm.mm)
      end

      def onKeyDown(key, repeat, flags, view)
        # SHIFT = bật/tắt khung viền. Không còn dùng SHIFT khóa hướng P1-P2.
        if key == 16
          return true if @held[key]

          @held[key] = true
          @wine_frame = !@wine_frame
          TranTuanNoiThat.save_setting('wine_frame', @wine_frame)

          update(view, *@mouse) if @mouse
          status
          view.invalidate
          return true
        end

        if key == 9
          return true if @held[key]

          @held[key] = true

          values = UI.inputbox(
            [
              'Kiểu ô',
              'Dày ván (mm)',
              'Chiều sâu (mm)',
              'Lọt lòng ô tối đa mong muốn (mm)'
            ],
            [
              @wine_kind,
              @wine_t,
              @wine_depth,
              @wine_cell
            ],
            [
              'Vuông|Chéo',
              '',
              '',
              ''
            ],
            'Vẽ Ô Rượu'
          )

          if values
            kind, t, d, c = values
            t = Float(t)
            d = Float(d)
            c = Float(c)

            unless [t, d, c].all? { |value| value.finite? && value > 0 } &&
                   t >= 1 &&
                   c > t
              raise 'Độ dày, chiều sâu và kích thước ô phải dương.'
            end

            @wine_kind = kind
            @wine_t = t
            @wine_depth = d
            @wine_cell = c

            {
              'kind' => kind,
              'thickness' => t,
              'depth' => d,
              'cell' => c
            }.each do |name, value|
              TranTuanNoiThat.save_setting("wine_#{name}", value)
            end

            update(view, *@mouse) if @mouse
          end

          @held.delete(9)
          status
          view.invalidate
          return true
        end

        # CTRL / F / mũi tên vẫn giữ cơ chế gốc.
        return super if [17, 70, 37, 38, 39, 40].include?(key)

        false
      rescue StandardError => error
        @held.delete(9)
        @held.delete(16)
        UI.messagebox(error.message)
        true
      end

      def onKeyUp(key, repeat, flags, view)
        if key == 16
          @held.delete(16)
          return true
        end

        super
      end

      def onMouseMove(flags, x, y, view)
        super
        status
      end

      def getExtents
        box = Geom::BoundingBox.new

        if @p1 && @wine_polys
          @wine_polys.each do |poly|
            poly.each do |point|
              box.add(world(point), world(point, true))
            end
          end
        end

        box
      end

      def enableVCB?
        false
      end

      def draw(view)
        @ip.draw(view) if @ip.display?
        return if !@wine_polys || @wine_polys.empty? || !@p1

        view.drawing_color = Sketchup::Color.new(255, 180, 195, 100)

        @wine_polys.each do |poly|
          front = poly.map { |point| world(point) }
          back = poly.map { |point| world(point, true) }

          [front, back].each do |points|
            view.draw(
              GL_TRIANGLES,
              (1...points.length - 1).flat_map do |i|
                [points[0], points[i], points[i + 1]]
              end
            )
          end

          view.draw(
            GL_QUADS,
            front.each_index.flat_map do |i|
              j = (i + 1) % front.length
              [front[i], front[j], back[j], back[i]]
            end
          )

          view.drawing_color = Sketchup::Color.new(160, 80, 95)
          view.draw(GL_LINE_LOOP, front)
          view.draw(GL_LINE_LOOP, back)
          view.drawing_color = Sketchup::Color.new(255, 180, 195, 100)
        end

        if @wine_kind == 'Chéo' && @wine_meta && @wine_meta[:intersections]
          points = @wine_meta[:intersections].map { |hit| world(hit[:center]) }
          unless points.empty?
            view.draw_points(
              points,
              8,
              3,
              Sketchup::Color.new(230, 70, 35)
            )
          end
        end
      end

      def build_half_lap_cutter(parent_entities, footprint, from_front)
        cutter = parent_entities.add_group
        epsilon_depth = 0.20
        half_depth = @wine_depth / 2.0

        if from_front
          start_depth = -epsilon_depth
          direction = displacement.clone
          length = half_depth + epsilon_depth * 2.0
        else
          start_depth = @wine_depth + epsilon_depth
          direction = displacement.clone.reverse
          length = half_depth + epsilon_depth * 2.0
        end

        cutter_poly = WineRack.expand_from_center(footprint, 0.10)
        face = cutter.entities.add_face(
          cutter_poly.map { |point| world_depth(point, start_depth) }
        )
        raise 'Không dựng được dao khấu giao điểm.' unless face

        face.reverse! if face.normal.dot(direction) < 0
        face.pushpull(length.mm)

        raise 'Dao khấu giao điểm chưa kín.' unless cutter.manifold?
        cutter
      end

      def apply_half_lap(parent_entities, groups)
        return groups unless @wine_kind == 'Chéo'
        return groups unless @wine_meta && @wine_meta[:intersections]

        hits = @wine_meta[:intersections]
        return groups if hits.empty?

        # Họ A khấu từ trước, họ B khấu từ sau.
        [
          [:a_index, true],
          [:b_index, false]
        ].each do |index_key, from_front|
          by_group = hits.group_by { |hit| hit[index_key] }

          by_group.each do |group_index, group_hits|
            target = groups[group_index]
            next unless target && target.valid?

            name = target.name
            material = target.material

            group_hits.each do |hit|
              cutter = build_half_lap_cutter(
                parent_entities,
                hit[:polygon],
                from_front
              )

              result = cutter.trim(target)
              cutter.erase! if cutter.valid?

              unless result && result.valid? && result.manifold?
                raise 'Không khấu được giao điểm nan. Đã hủy toàn bộ ô rượu.'
              end

              result.name = name
              result.material = material if material
              target = result
            end

            target.set_attribute(
              'TRẦN TUẤN NỘI THẤT',
              'khau_am_duong',
              from_front ? 'MAT_TRUOC_1_2' : 'MAT_SAU_1_2'
            )
            groups[group_index] = target
          end
        end

        groups
      end

      def create_board
        return false unless same_context? && @wine_polys && !@wine_polys.empty?

        @model.start_operation('TT - Vẽ Ô Rượu', true)

        parent = @context.add_group
        parent.name = "Ô Rượu #{@wine_kind}"

        parent.set_attribute(
          'TRẦN TUẤN NỘI THẤT',
          'khung_vien',
          @wine_frame ? 'BAT' : 'TAT'
        )

        groups = []

        @wine_polys.each_with_index do |poly, index|
          group = parent.entities.add_group
          group.name = format('VAN_RUOU_%03d', index + 1)

          face = group.entities.add_face(poly.map { |point| world(point) })
          raise 'Không tạo được mặt nan.' unless face

          face.reverse! if face.normal.dot(displacement) < 0
          face.pushpull(@wine_depth.mm)

          raise 'Nan chưa kín; đã hủy.' unless group.manifold?
          groups << group
        end

        groups = apply_half_lap(parent.entities, groups)

        groups.compact.each do |group|
          next unless group.valid?
          group.set_attribute(
            'TRẦN TUẤN NỘI THẤT',
            'do_day_mm',
            @wine_t
          )
        end

        if @wine_kind == 'Chéo' && @wine_meta
          parent.set_attribute(
            'TRẦN TUẤN NỘI THẤT',
            'so_giao_diem_khau',
            @wine_meta[:intersections].length
          )
          parent.set_attribute(
            'TRẦN TUẤN NỘI THẤT',
            'kieu_khau',
            'AM_DUONG_1_2_CHIEU_SAU'
          )
        end

        parent.transformation = @edit.inverse

        @model.commit_operation
        @model.selection.clear
        @model.selection.add(parent)
        @wine_polys = []
        @wine_meta = nil

        true
      rescue StandardError => error
        @model.abort_operation
        UI.messagebox(error.message)
        false
      end

      def status_text
        frame_text = @wine_frame ? 'KHUNG: BẬT' : 'KHUNG: TẮT'

        "VẼ Ô RƯỢU #{@wine_kind} · P1 → P2 → click tạo · "         "SHIFT #{frame_text} · TAB cài đặt · CTRL đảo sâu · #{@wine_note}"
      end
    end
  end
end
