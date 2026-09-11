# encoding: UTF-8
module TranTuanNoiThat
  module Drawer
    extend self

    DEFAULTS = {
      'side_height' => 150.0, 'rail_gap' => 13.0,
      'bottom_clearance' => 10.0, 'back_clearance' => 30.0,
      'quantity' => 3, 'orientation' => 'vertical',
      'front_gap' => 10.0, 'bottom_mode' => 'cover',
      'bottom_offset' => 5.0, 'bottom_thickness' => 9.0,
      'side_thickness' => 17.5, 'bottom_shift' => 10.0,
      'mark_contact' => false,
      'reverse_depth' => false,
      'fallback_depth' => 500.0
    }.freeze

    def activate
      Sketchup.active_model.select_tool(Tool.new(settings))
    end

    def settings
      DEFAULTS.each_with_object({}) do |(key, value), data|
        data[key] = TranTuanNoiThat.setting("drawer_#{key}", value)
      end
    end

    def save_settings(data)
      DEFAULTS.each_key { |key| TranTuanNoiThat.save_setting("drawer_#{key}", data[key]) }
    end

    def show_settings(tool)
      @tool = tool
      @dialog.close if @dialog && @dialog.visible?
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - CÀI ĐẶT NGĂN KÉO',
        preferences_key: 'TranTuanNoiThat.Drawer', scrollable: true,
        resizable: true, width: 500, height: 720,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(settings_html(tool.options))
      @dialog.add_action_callback('apply') do |_context, json|
        begin
          values = normalize(JSON.parse(json))
          save_settings(values)
          @tool.update_options(values) if @tool
          @dialog.execute_script("notice('Đã cập nhật preview.', false)")
        rescue StandardError => error
          @dialog.execute_script("notice(#{JSON.generate(error.message)}, true)")
        end
      end
      @dialog.show
    end

    def normalize(raw)
      data = {}
      DEFAULTS.each do |key, default|
        data[key] = if default == true || default == false
                      raw[key] == true || raw[key].to_s == 'true'
                    elsif default.is_a?(String)
                      raw[key].to_s
                    else
                      raw[key].to_f
                    end
      end
      data['quantity'] = [[raw['quantity'].to_i, 1].max, 50].min
      data['orientation'] = raw['orientation'].to_s == 'horizontal' ? 'horizontal' : 'vertical'
      data['bottom_mode'] = raw['bottom_mode'].to_s == 'custom' ? 'custom' : 'cover'
      numeric = DEFAULTS.keys - %w[quantity orientation bottom_mode mark_contact reverse_depth]
      raise 'Các thông số kích thước không được âm.' if numeric.any? { |key| data[key].to_f < 0 }
      raise 'Độ dày tấm phải lớn hơn 0.' unless data['bottom_thickness'] > 0 && data['side_thickness'] > 0
      raise 'Chiều cao thanh phải lớn hơn 0.' unless data['side_height'] > 0
      data
    end

    def settings_html(values)
      json = JSON.generate(values)
      <<~HTML
        <!doctype html><html><head><meta charset="UTF-8"><style>
        *{box-sizing:border-box}body{margin:0;background:#171717;color:#eee;font:14px Arial;padding:20px}h2{margin:0;color:#ff8a22}.sub{color:#999;margin:5px 0 16px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:11px}.field label{display:block;margin-bottom:5px;color:#ddd}.field input,.field select{width:100%;padding:9px;border:1px solid #444;border-radius:6px;background:#252525;color:#fff}.wide{grid-column:1/-1}.modes{display:flex;gap:16px;padding:8px;background:#222;border-radius:7px}button{width:100%;padding:12px;margin-top:18px;border:0;border-radius:7px;background:#f47b20;color:white;font-weight:bold;font-size:15px}#msg{height:20px;margin-top:9px;color:#67d78a}.note{color:#aaa;font-size:12px;margin-top:12px;line-height:1.4}
        </style></head><body><h2>CÀI ĐẶT NGĂN KÉO</h2><div class="sub">TAB mở bảng này • thay đổi sẽ cập nhật preview</div><div class="grid">
        <div class="field"><label>Chiều cao thanh (mm)</label><input id="side_height" type="number" step="0.1"></div>
        <div class="field"><label>Hở ray mỗi bên (mm)</label><input id="rail_gap" type="number" step="0.1"></div>
        <div class="field"><label>Cách đáy view (mm)</label><input id="bottom_clearance" type="number" step="0.1"></div>
        <div class="field"><label>Cách hậu (mm)</label><input id="back_clearance" type="number" step="0.1"></div>
        <div class="field"><label>Số lượng ngăn kéo</label><input id="quantity" type="number" min="1" max="50" step="1"></div>
        <div class="field"><label>Hở thanh trước (mm)</label><input id="front_gap" type="number" step="0.1"></div>
        <div class="field"><label>Dày tấm đáy (mm)</label><input id="bottom_thickness" type="number" step="0.1"></div>
        <div class="field"><label>Dày thanh (mm)</label><input id="side_thickness" type="number" step="0.1"></div>
        <div class="field"><label>Offset đáy 4 cạnh (mm)</label><input id="bottom_offset" type="number" step="0.1"></div>
        <div class="field"><label>Tịnh tiến tấm đáy (mm)</label><input id="bottom_shift" type="number" step="0.1"></div>
        <div class="field wide"><label>Chiều sâu dự phòng khi không dò thấy hậu (mm)</label><input id="fallback_depth" type="number" step="0.1"></div>
        <div class="field wide"><label>Hướng tạo</label><div class="modes"><label><input type="radio" name="orientation" value="vertical"> Dọc</label><label><input type="radio" name="orientation" value="horizontal"> Ngang</label></div></div>
        <div class="field wide"><label>Hướng chiều sâu</label><div class="modes"><label><input id="reverse_depth" type="checkbox"> Đảo hướng ngăn kéo trước/sau</label></div></div>
        <div class="field wide"><label>Chế độ tấm đáy</label><div class="modes"><label><input type="radio" name="bottom_mode" value="cover"> Phủ 4 cạnh ngoài</label><label><input type="radio" name="bottom_mode" value="custom"> Tùy chỉnh offset</label></div></div>
        <div class="field wide"><label>Đánh dấu tiếp diện</label><div class="modes"><label><input id="mark_contact" type="checkbox"> Đánh dấu biên thanh giao nhau với tấm đáy</label></div></div>
        </div><button onclick="applyNow()">ÁP DỤNG - CẬP NHẬT PREVIEW</button><div id="msg"></div><div class="note">Tịnh tiến chỉ nâng tấm đáy; 4 thanh giữ nguyên. Click trong model sau khi chỉnh xong để tạo thật.</div>
        <script>
        const initial=#{json};
        Object.keys(initial).forEach(k=>{const el=document.getElementById(k);if(el)el.value=initial[k]});
        document.querySelector(`input[name=orientation][value="${initial.orientation}"]`).checked=true;
        document.querySelector(`input[name=bottom_mode][value="${initial.bottom_mode}"]`).checked=true;
        document.getElementById('mark_contact').checked=initial.mark_contact===true||initial.mark_contact==='true';
        document.getElementById('reverse_depth').checked=initial.reverse_depth===true||initial.reverse_depth==='true';
        function value(id){return document.getElementById(id).value}
        function applyNow(){const data={};['side_height','rail_gap','bottom_clearance','back_clearance','quantity','front_gap','bottom_thickness','side_thickness','bottom_offset','bottom_shift','fallback_depth'].forEach(k=>data[k]=value(k));data.orientation=document.querySelector('input[name=orientation]:checked').value;data.bottom_mode=document.querySelector('input[name=bottom_mode]:checked').value;data.mark_contact=document.getElementById('mark_contact').checked;data.reverse_depth=document.getElementById('reverse_depth').checked;sketchup.apply(JSON.stringify(data))}
        function syncContact(){const custom=document.querySelector('input[name=bottom_mode]:checked').value==='custom';const mark=document.getElementById('mark_contact');mark.disabled=!custom;if(!custom)mark.checked=false;applyNow()}
        document.querySelectorAll('input[name=bottom_mode]').forEach(el=>el.addEventListener('change',syncContact));
        document.getElementById('mark_contact').addEventListener('change',applyNow);
        document.getElementById('reverse_depth').addEventListener('change',applyNow);
        document.getElementById('mark_contact').disabled=initial.bottom_mode!=='custom';
        if(initial.bottom_mode!=='custom')document.getElementById('mark_contact').checked=false;
        function notice(text,bad){const e=document.getElementById('msg');e.textContent=text;e.style.color=bad?'#ff6767':'#67d78a'}
        </script></body></html>
      HTML
    end

    class Tool
      TAB = 9
      BOTTOM_COLOR = Sketchup::Color.new(145, 215, 255, 105)
      RAIL_COLOR = Sketchup::Color.new(255, 145, 45, 90)
      EDGE_COLOR = Sketchup::Color.new(225, 88, 0, 255)
      CONTACT_COLOR = Sketchup::Color.new(0, 255, 135, 255)

      attr_reader :options

      def initialize(options)
        @options = Drawer.normalize(options)
        @ip = Sketchup::InputPoint.new
        @ip1 = Sketchup::InputPoint.new
        reset
      end

      def activate; status; end
      def deactivate(view); view.invalidate; end
      def resume(view); status; view.invalidate; end

      def reset
        @state = 0
        @p1 = @p2 = nil
        @depth_axis = Y_AXIS
        @depth_length = @options['fallback_depth'].mm
        status
      end

      def update_options(values)
        old_reverse = @options['reverse_depth']
        @options = Drawer.normalize(values)
        if @state == 2 && old_reverse != @options['reverse_depth']
          @depth_axis = @depth_axis.reverse
        end
        @depth_length = @options['fallback_depth'].mm if @state < 2 || !@rear_detected
        Sketchup.active_model.active_view.invalidate
        status
      end

      def onMouseMove(_flags, x, y, view)
        if @state.zero?
          @ip.pick(view, x, y)
        elsif @state == 1
          @ip.pick(view, x, y, @ip1)
          @p2 = @ip.position if @ip.valid?
          analyze_depth(view) if valid_front?
        end
        view.tooltip = @ip.tooltip if @ip.valid?
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        if @state.zero?
          @ip.pick(view, x, y)
          return UI.beep unless @ip.valid?
          @ip1.copy!(@ip)
          @p1 = @ip.position
          @state = 1
        elsif @state == 1
          @ip.pick(view, x, y, @ip1)
          @p2 = @ip.position if @ip.valid?
          return UI.beep unless valid_front?
          analyze_depth(view)
          @state = 2
        else
          return UI.beep if preview_parts.empty?
          create_drawers
          reset
        end
        status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless key == TAB && @state == 2
        Drawer.show_settings(self)
        view.invalidate
      end

      def onCancel(_reason, view)
        @state.zero? ? Sketchup.active_model.select_tool(nil) : reset
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.display?
        @ip1.draw(view) if @state > 0 && @ip1.display?
        return unless valid_front?
        parts = preview_parts
        parts.each do |part|
          points = box_points(*part[:box])
          view.drawing_color = part[:bottom] ? BOTTOM_COLOR : RAIL_COLOR
          box_faces(points).each { |face| view.draw(GL_QUADS, face) }
          view.drawing_color = EDGE_COLOR
          view.line_width = 1
          view.draw(GL_LINES, box_lines(points))
        end
        if @options['bottom_mode'] == 'custom' && @options['mark_contact']
          surfaces = contact_surfaces(parts)
          unless surfaces.empty?
            view.drawing_color = CONTACT_COLOR
            surfaces.each { |surface| view.draw(GL_QUADS, surface) }
            view.line_width = 3
            surfaces.each { |surface| view.draw(GL_LINE_LOOP, surface) }
          end
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        preview_parts.each { |part| box_points(*part[:box]).each { |point| box.add(point) } }
        box
      end

      private

      def valid_front?
        return false unless @p1 && @p2
        dx = (@p2.x - @p1.x).abs
        dz = (@p2.z - @p1.z).abs
        dx > 1.mm && dz > 1.mm
      end

      def analyze_depth(view)
        @depth_axis = Y_AXIS
        @rear_detected = false
        mid = Geom::Point3d.new((@p1.x + @p2.x) * 0.5, @p1.y, (@p1.z + @p2.z) * 0.5)
        candidates = [Y_AXIS, Y_AXIS.reverse].filter_map do |axis|
          hit = Sketchup.active_model.raytest([mid.offset(axis, 2.mm), axis], true)
          next unless hit && hit[0]
          distance = mid.distance(hit[0])
          next unless distance > 30.mm && distance < 3000.mm
          [distance, axis]
        end
        if candidates.any?
          distance, axis = candidates.min_by(&:first)
          @depth_length = distance
          @depth_axis = axis
          @rear_detected = true
        else
          @depth_length = @options['fallback_depth'].mm
          @depth_axis = view.camera.direction.dot(Y_AXIS) > 0 ? Y_AXIS : Y_AXIS.reverse
        end
        @depth_axis = @depth_axis.reverse if @options['reverse_depth']
      rescue StandardError
        @depth_length = @options['fallback_depth'].mm
        @depth_axis = @options['reverse_depth'] ? Y_AXIS.reverse : Y_AXIS
        @rear_detected = false
      end

      def preview_parts
        return [] unless valid_front?
        quantity = @options['quantity'].to_i
        x_min, x_max = [@p1.x, @p2.x].minmax
        z_min, z_max = [@p1.z, @p2.z].minmax
        front_y = @p1.y
        back_y = front_y + @depth_axis.y * [@depth_length - @options['back_clearance'].mm, 1.mm].max
        y_min, y_max = [front_y, back_y].minmax
        parts = []

        quantity.times do |index|
          if @options['orientation'] == 'horizontal'
            slot = (x_max - x_min) / quantity
            sx0 = x_min + slot * index
            sx1 = x_min + slot * (index + 1)
            sz0, sz1 = z_min, z_max
          else
            slot = (z_max - z_min) / quantity
            sx0, sx1 = x_min, x_max
            sz0 = z_min + slot * index
            sz1 = z_min + slot * (index + 1)
          end
          parts.concat(parts_for_drawer(index, sx0, sx1, y_min, y_max, sz0, sz1))
        end
        parts
      rescue StandardError
        []
      end

      def parts_for_drawer(index, sx0, sx1, y0, y1, z0, z1)
        gap = @options['rail_gap'].mm
        thick = @options['side_thickness'].mm
        bottom_t = @options['bottom_thickness'].mm
        base_z = z0 + @options['bottom_clearance'].mm
        rail_z = base_z + bottom_t
        max_h = [z1 - rail_z, 1.mm].max
        side_h = [@options['side_height'].mm, max_h].min
        front_h = [[side_h - @options['front_gap'].mm, 1.mm].max, side_h].min
        x0, x1 = sx0 + gap, sx1 - gap
        return [] if x1 - x0 <= thick * 2 || y1 - y0 <= thick * 2

        tag = @options['quantity'].to_i == 1 ? '' : format('_%02d', index + 1)
        parts = [
          { name: "THANH_TRAI#{tag}", box: [x0, y0, rail_z, thick, y1-y0, side_h] },
          { name: "THANH_PHAI#{tag}", box: [x1-thick, y0, rail_z, thick, y1-y0, side_h] },
          { name: "THANH_TRUOC#{tag}", box: [x0+thick, y0, rail_z, x1-x0-thick*2, thick, front_h] },
          { name: "THANH_SAU#{tag}", box: [x0+thick, y1-thick, rail_z, x1-x0-thick*2, thick, side_h] }
        ]
        cover_bottom = @options['bottom_mode'] == 'cover'
        inset = cover_bottom ? 0 : @options['bottom_offset'].mm
        bx0, bx1 = x0 + inset, x1 - inset
        by0, by1 = y0 + inset, y1 - inset
        # Chế độ phủ: mặt trên đáy chạm đúng mặt dưới 4 thanh và bốn cạnh
        # trùng với mép ngoài của hệ thanh. Tịnh tiến chỉ áp dụng cho tùy chỉnh.
        bottom_z = cover_bottom ? rail_z - bottom_t : base_z + @options['bottom_shift'].mm
        parts << { name: "TAM_DAY#{tag}", box: [bx0, by0, bottom_z, bx1-bx0, by1-by0, bottom_t], bottom: true }
        parts
      end

      def box_points(x, y, z, width, depth, height)
        p0 = Geom::Point3d.new(x, y, z)
        p1 = Geom::Point3d.new(x + width, y, z)
        p2 = Geom::Point3d.new(x + width, y + depth, z)
        p3 = Geom::Point3d.new(x, y + depth, z)
        [p0,p1,p2,p3,p0.offset(Z_AXIS,height),p1.offset(Z_AXIS,height),p2.offset(Z_AXIS,height),p3.offset(Z_AXIS,height)]
      end

      def box_faces(p)
        [[p[0],p[1],p[2],p[3]],[p[4],p[7],p[6],p[5]],[p[0],p[4],p[5],p[1]],[p[1],p[5],p[6],p[2]],[p[2],p[6],p[7],p[3]],[p[3],p[7],p[4],p[0]]]
      end

      def box_lines(p)
        [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].flat_map { |a,b| [p[a],p[b]] }
      end

      def contact_surfaces(parts)
        bottoms = parts.select { |part| part[:bottom] }
        rails = parts.reject { |part| part[:bottom] }
        surfaces = []
        tolerance = 0.2.mm

        bottoms.each do |bottom|
          bx, by, bz, bw, bd, bh = bottom[:box]
          rails.each do |rail|
            rx, ry, rz, rw, rd, rh = rail[:box]
            x0 = [bx, rx].max; x1 = [bx + bw, rx + rw].min
            y0 = [by, ry].max; y1 = [by + bd, ry + rd].min
            next unless x1 - x0 > tolerance && y1 - y0 > tolerance
            next unless bz <= rz + rh + tolerance && bz + bh >= rz - tolerance

            z0 = bz
            z1 = bz + bh
            name = rail[:name]
            if name.start_with?('THANH_TRAI')
              x = rx + rw
              surfaces << [Geom::Point3d.new(x,y0,z0), Geom::Point3d.new(x,y1,z0), Geom::Point3d.new(x,y1,z1), Geom::Point3d.new(x,y0,z1)]
            elsif name.start_with?('THANH_PHAI')
              x = rx
              surfaces << [Geom::Point3d.new(x,y0,z0), Geom::Point3d.new(x,y0,z1), Geom::Point3d.new(x,y1,z1), Geom::Point3d.new(x,y1,z0)]
            elsif name.start_with?('THANH_TRUOC')
              y = ry + rd
              surfaces << [Geom::Point3d.new(x0,y,z0), Geom::Point3d.new(x0,y,z1), Geom::Point3d.new(x1,y,z1), Geom::Point3d.new(x1,y,z0)]
            elsif name.start_with?('THANH_SAU')
              y = ry
              surfaces << [Geom::Point3d.new(x0,y,z0), Geom::Point3d.new(x1,y,z0), Geom::Point3d.new(x1,y,z1), Geom::Point3d.new(x0,y,z1)]
            end
          end
        end
        surfaces
      end

      def add_panel(parent, part)
        x, y, z, width, depth, height = part[:box]
        child = parent.entities.add_group
        points = box_points(x, y, z, width, depth, height)
        face = child.entities.add_face(points[0], points[1], points[2], points[3])
        raise "Không tạo được #{part[:name]}." unless face && face.valid?
        face.reverse! if face.normal.dot(Z_AXIS) < 0
        face.pushpull(height)
        child.name = part[:name]
        child.set_attribute('TRẦN TUẤN NỘI THẤT', 'chi_tiet', part[:name])
        child
      end

      def create_drawers
        model = Sketchup.active_model
        model.start_operation('TRẦN TUẤN - Vẽ Ngăn Kéo', true)
        parts = preview_parts
        quantity = @options['quantity'].to_i
        quantity.times do |index|
          parent = model.active_entities.add_group
          suffix = quantity == 1 ? '' : format('_%02d', index + 1)
          parent.name = "NGAN_KEO#{suffix}"
          selected = parts.select { |part| part[:name].end_with?(suffix) }
          selected.each { |part| add_panel(parent, part) }
          parent.set_attribute('TRẦN TUẤN NỘI THẤT', 'stt', index + 1) if quantity > 1
          parent.set_attribute('TRẦN TUẤN NỘI THẤT', 'loai', 'NGAN_KEO')
        end
        model.commit_operation
      rescue StandardError => error
        model.abort_operation if model
        UI.messagebox("Lỗi tạo ngăn kéo:\n#{error.message}")
      end

      def status
        Sketchup.status_text = case @state
        when 0 then 'VẼ NGĂN KÉO: Click P1 tại góc dưới mặt trước.'
        when 1 then 'Click P2 tại góc đối diện để khóa vùng và xem preview.'
        else 'TAB mở cài đặt | Click tạo ngăn kéo | ESC vẽ lại.'
        end
      end
    end
  end
end
