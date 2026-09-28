# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module SlatWall
    extend self
    VERSION = '1.9.166'.freeze
    KEY = 'TT_VACH_LAM'.freeze
    MAX_SLATS = 2000
    SNAP_RADIUS = 24.0
    AXIS_SWITCH_RATIO = 1.25
    ABF_CUTTING_TAG = 'ABF_cuttingLines'.freeze
    ABF_INTERSECT_NAME = '_ABF_Intersect'.freeze
    SLAT_ORIENTATIONS = %w[vertical horizontal diag_right diag_left].freeze
    DEFAULTS = {
      'mode' => 'single', 'stock_length' => 2440.0, 'stock_width' => 1220.0,
      'stock_thickness' => 17.5, 'width' => 40.0, 'depth' => 17.5,
      'orientation' => 'vertical', 'spacing_mode' => 'auto', 'gap' => 40.0, 'count' => 10,
      'left' => 0.0, 'right' => 0.0, 'top' => 0.0, 'bottom' => 0.0,
      'backing' => 17.5, 'recess' => 0.0, 'cnc' => false, 'tag' => 'ABF_HANENLAMAM'
    }.freeze

    def validate(raw)
      raw = {} unless raw.is_a?(Hash)
      o = DEFAULTS.merge(raw.select { |k, _| DEFAULTS.key?(k) })
      %w[stock_length stock_width stock_thickness width depth gap left right top bottom backing recess].each do |key|
        o[key] = Float(o[key].to_s.tr(',', '.'))
        raise 'Thông số phải là số hữu hạn.' unless o[key].finite?
        raise 'Kích thước/khoảng cách không được âm.' if o[key] < 0
      end
      count_value = Float(o['count'].to_s.tr(',', '.'))
      raise 'Số lượng lam phải là số hữu hạn.' unless count_value.finite?
      o['count'] = count_value.round
      raise 'Số lượng lam phải từ 1 đến 2000.' unless o['count'].between?(1, MAX_SLATS)
      %w[stock_length stock_width stock_thickness width depth backing].each do |key|
        raise 'Khổ ván, rộng/dày lam và dày lót phải lớn hơn 0.' unless o[key] >= 0.1
      end
      raise 'Rộng lam lớn hơn rộng khổ ván.' if o['width'] > o['stock_width']
      raise 'Chế độ không hợp lệ.' unless %w[single backed].include?(o['mode'])
      raise 'Hướng lam không hợp lệ.' unless SLAT_ORIENTATIONS.include?(o['orientation'])
      raise 'Chế độ khoảng cách không hợp lệ.' unless %w[manual auto count].include?(o['spacing_mode'])
      if o['mode'] == 'backed' && o['recess'] >= [o['backing'], o['depth']].min
        raise 'Hạ âm phải nhỏ hơn độ dày tấm lót và độ dày lam.'
      end
      o['cnc'] = o['cnc'] == true
      o['tag'] = o['tag'].to_s.strip
      o['tag'] = 'ABF_HANENLAMAM' if o['tag'].empty?
      o['tag'] = 'ABF_' + o['tag'] unless o['tag'].start_with?('ABF_')
      raise 'Tên Tag quá dài hoặc có ký tự xuống dòng.' if o['tag'].length > 100 || o['tag'].match?(/[\r\n]/)
      o
    rescue ArgumentError, TypeError
      raise 'Vui lòng nhập số hợp lệ cho các kích thước.'
    end

    def settings
      raw = JSON.parse(Sketchup.read_default(KEY, 'settings', '{}'))
      unless Sketchup.read_default(KEY, 'backing_175_v156', '') == 'done'
        raw['backing'] = 17.5
        Sketchup.write_default(KEY, 'backing_175_v156', 'done')
      end
      result = validate(raw)
      Sketchup.write_default(KEY, 'settings', JSON.generate(result))
      result
    rescue StandardError
      DEFAULTS.dup
    end

    def save_settings(options)
      Sketchup.write_default(KEY, 'settings', JSON.generate(options))
    end

    def spacing_values(run, options)
      raise 'Rộng lam lớn hơn vùng còn lại sau khi trừ mép.' if run + 1.0e-9 < options['width']
      nominal_gap = options['gap']
      case options['spacing_mode']
      when 'count'
        count = options['count']
        used_slats = count * options['width']
        raise 'Số lượng lam quá lớn so với vùng đặt lam.' if used_slats > run + 1.0e-9
        gap = count > 1 ? (run - used_slats) / (count - 1) : 0.0
        extra = count == 1 ? (run - options['width']) / 2.0 : 0.0
      when 'auto'
        count = [(((run + nominal_gap) / (options['width'] + nominal_gap)) + 1.0e-9).floor, 1].max
        gap = count > 1 ? (run - count * options['width']) / (count - 1) : 0.0
        extra = count == 1 ? (run - options['width']) / 2.0 : 0.0
      else
        count = [(((run + nominal_gap) / (options['width'] + nominal_gap)) + 1.0e-9).floor, 1].max
        gap = nominal_gap
        used = count * options['width'] + (count - 1) * gap
        extra = [run - used, 0.0].max / 2.0
      end
      [count, gap, extra]
    end

    def diagonal_run(width, height, slat_width, angle_deg)
      angle = angle_deg * Math::PI / 180.0
      nx = -Math.sin(angle)
      ny = Math.cos(angle)
      half = slat_width / 2.0
      inset_w = width - 2.0 * nx.abs * half
      inset_h = height - 2.0 * ny.abs * half
      raise 'Rộng nan quá lớn để xoay chéo trong vùng hiện tại.' if inset_w <= 0.1 || inset_h <= 0.1
      nx.abs * inset_w + ny.abs * inset_h + slat_width
    end

    def diagonal_slats(x0, y0, x1, y1, z, options, angle_deg, count, gap, extra)
      angle = angle_deg * Math::PI / 180.0
      dx = Math.cos(angle)
      dy = Math.sin(angle)
      nx = -dy
      ny = dx
      half = options['width'] / 2.0

      ix0 = x0 + nx.abs * half
      ix1 = x1 - nx.abs * half
      iy0 = y0 + ny.abs * half
      iy1 = y1 - ny.abs * half
      raise 'Vùng quá nhỏ để xoay nan chéo.' if ix1 <= ix0 || iy1 <= iy0

      projections = [[ix0,iy0],[ix1,iy0],[ix1,iy1],[ix0,iy1]].map { |x,y| x*nx + y*ny }
      cmin = projections.min
      first_c = cmin + extra
      boxes = []
      polygons = []
      lengths = []

      count.times do |i|
        c = first_c + i * (options['width'] + gap)
        t_low = -Float::INFINITY
        t_high = Float::INFINITY

        if dx.abs > 1.0e-9
          a = (ix0 - nx*c) / dx
          b = (ix1 - nx*c) / dx
          t_low = [t_low, [a,b].min].max
          t_high = [t_high, [a,b].max].min
        elsif nx*c < ix0 - 1.0e-9 || nx*c > ix1 + 1.0e-9
          next
        end

        if dy.abs > 1.0e-9
          a = (iy0 - ny*c) / dy
          b = (iy1 - ny*c) / dy
          t_low = [t_low, [a,b].min].max
          t_high = [t_high, [a,b].max].min
        elsif ny*c < iy0 - 1.0e-9 || ny*c > iy1 + 1.0e-9
          next
        end
        next unless t_high > t_low + 0.1

        ax = nx*c + dx*t_low
        ay = ny*c + dy*t_low
        bx = nx*c + dx*t_high
        by = ny*c + dy*t_high
        polygon = [
          [ax + nx*half, ay + ny*half],
          [bx + nx*half, by + ny*half],
          [bx - nx*half, by - ny*half],
          [ax - nx*half, ay - ny*half]
        ]
        length = t_high - t_low
        cx = (ax + bx) / 2.0
        cy = (ay + by) / 2.0
        boxes << [cx - length/2.0, cy - half, z, length, options['width'], options['depth']]
        polygons << polygon
        lengths << length
      end
      [boxes, polygons, lengths]
    end

    # Pure millimetre layout; shared by viewport, dialog and real geometry.
    def layout(width, height, options)
      o = validate(options)
      w, h = width.to_f, height.to_f
      raise 'Kéo hai góc chéo để tạo vùng có rộng/cao lớn hơn 0.' unless w.finite? && h.finite? && w > 0.1 && h > 0.1
      cols = (w / o['stock_width']).ceil
      rows = (h / o['stock_length']).ceil
      raise 'Vùng quá lớn: tối đa 200 tấm trong một lần tạo.' if cols * rows > 200
      pw, ph = w / cols, h / rows
      usable_w = pw - o['left'] - o['right']
      usable_h = ph - o['top'] - o['bottom']
      raise 'Khoảng cách mép làm hết vùng đặt lam.' unless usable_w > 0.1 && usable_h > 0.1

      orientation = o['orientation']
      angle_deg = orientation == 'diag_right' ? 45.0 : (orientation == 'diag_left' ? -45.0 : nil)
      run = if orientation == 'vertical'
        usable_w
      elsif orientation == 'horizontal'
        usable_h
      else
        diagonal_run(usable_w, usable_h, o['width'], angle_deg)
      end
      count, gap, extra = spacing_values(run, o)

      total = count * cols * rows
      raise "Quá nhiều lam (#{total}). Giảm số lượng hoặc tạo từng vùng nhỏ." if total > MAX_SLATS
      backed = o['mode'] == 'backed'
      # ABF convention: mặt phải/phía nan = z=0; chiều dày tấm lót đi về âm Z.
      z = backed ? -o['recess'] : 0.0
      panels = []
      rows.times do |row|
        cols.times do |col|
          x, y = col * pw, row * ph
          slat_polygons = nil
          slat_lengths = nil
          if orientation == 'vertical'
            slats = count.times.map do |i|
              [x + o['left'] + extra + i * (o['width'] + gap), y + o['bottom'], z,
               o['width'], usable_h, o['depth']]
            end
          elsif orientation == 'horizontal'
            slats = count.times.map do |i|
              [x + o['left'], y + o['bottom'] + extra + i * (o['width'] + gap), z,
               usable_w, o['width'], o['depth']]
            end
          else
            slats, slat_polygons, slat_lengths = diagonal_slats(
              x + o['left'], y + o['bottom'],
              x + pw - o['right'], y + ph - o['top'],
              z, o, angle_deg, count, gap, extra
            )
          end
          panels << { x: x, y: y, width: pw, height: ph, slats: slats,
                      slat_polygons: slat_polygons, slat_lengths: slat_lengths,
                      backing: backed ? [x, y, -o['backing'], pw, ph, o['backing']] : nil }
        end
      end
      { width: w, height: h, columns: cols, rows: rows, panels: panels,
        slat_count: total, count_per_panel: count, gap: gap, orientation: o['orientation'], options: o }
    end

    def selected_wall(model = Sketchup.active_model)
      selected = model.selection.to_a
      return nil unless selected.length == 1
      entity = selected.first
      return nil unless entity.is_a?(Sketchup::Group)
      return nil if entity.get_attribute(KEY, 'settings').to_s.empty?
      entity
    end

    def wall_settings(entity)
      validate(JSON.parse(entity.get_attribute(KEY, 'settings', '{}')))
    rescue StandardError
      settings
    end

    def activate
      model = Sketchup.active_model
      target = selected_wall(model)
      options = target ? wall_settings(target) : settings
      model.select_tool(Tool.new(options, target))
    end

    def show_settings(tool)
      if @dialog && @dialog.visible?
        @tool = tool
        send_state
        @dialog.bring_to_front
        return
      end
      @tool = tool
      @dialog = UI::HtmlDialog.new(dialog_title: 'TT - TẠO VÁCH LAM', preferences_key: KEY,
        scrollable: true, resizable: true, width: 490, height: 790, style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(settings_html)
      @dialog.add_action_callback('ready') { |_ctx| send_state }
      @dialog.add_action_callback('update') do |_ctx, json|
        begin
          o = validate(JSON.parse(json))
          save_settings(o)
          @tool.update_settings(o) if @tool
          send_state
        rescue StandardError => e
          @dialog.execute_script("showError(#{JSON.generate(e.message)});") if @dialog
        end
      end
      @dialog.add_action_callback('repair_abf') { |_ctx| repair_selected_backings }
      @dialog.add_action_callback('apply_edit') { |_ctx| @tool.apply_selected_edit if @tool }
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    end

    def send_state
      return unless @dialog && @dialog.visible? && @tool
      @dialog.execute_script("receive(#{JSON.generate(@tool.dialog_state)});")
    end

    def settings_html
      fields = [['stock_length','Dài khổ ván'],['stock_width','Rộng khổ ván'],['stock_thickness','Dày khổ ván'],
                ['width','Chiều rộng nan'],['depth','Chiều dày nan'],['gap','Khe nan / khe dự kiến'],
                ['left','Cách trái'],['right','Cách phải'],['top','Cách trên'],['bottom','Cách dưới']]
      inputs = fields.map { |key, label| "<label>#{label}<span><input id='#{key}' type='number' min='0' step='0.1'> mm</span></label>" }.join
      <<~HTML
        <!doctype html><html lang="vi"><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{font:14px Arial;margin:0;background:#f4f5f7;color:#202a34}header{padding:17px;background:#223d50;color:white}h2{font-size:18px;margin:0 0 6px}main{padding:14px}section{background:white;padding:14px;border-radius:8px;margin-bottom:12px}label{display:flex;justify-content:space-between;align-items:center;margin:8px 0;gap:10px}input[type=number]{width:105px}input,select{padding:7px;border:1px solid #bbc6cc;border-radius:4px}select{max-width:245px}button{width:100%;padding:12px;background:#c4752a;color:white;border:0;border-radius:5px;font-weight:bold;cursor:pointer}small{display:block;color:#647380;line-height:1.5}canvas{width:100%;height:170px;background:#eef1f4;border-radius:5px}#error{color:#b12828;white-space:pre-line}#info{font-size:12px;line-height:1.5;margin:8px 0}.backed,.counted{display:none}.edit button{background:#27784a}
        </style><header><h2>TRẦN TUẤN · TẠO VÁCH LAM</h2>Hai góc chéo · SHIFT xoay nan: Dọc → Ngang → Chéo phải → Chéo trái · TAB đổi nhanh Dọc/Ngang · S mở bảng</header><main>
        <section><label>Chế độ<select id="mode" onchange="visibility()"><option value="single">Vách lam đơn</option><option value="backed">Vách lam có tấm lót</option></select></label>
        <label>Hướng nan<select id="orientation"><option value="vertical">Nan dọc</option><option value="horizontal">Nan ngang</option><option value="diag_right">Chéo phải 45°</option><option value="diag_left">Chéo trái 45°</option></select></label>
        #{inputs}
        <label>Kiểu chia<select id="spacing_mode" onchange="visibility()"><option value="manual">Giữ đúng khe + căn giữa</option><option value="auto">Tự động chia đều khe</option><option value="count">Theo số lượng nan</option></select></label>
        <label class="counted">Số lượng nan / cụm<span><input id="count" type="number" min="1" max="#{MAX_SLATS}" step="1"></span></label>
        <small>Chiều dài nan bám đúng vùng kéo. Nếu vượt khổ ván, vùng tự chia thành các cụm VL. Mép trái/phải/trên/dưới áp dụng cho từng cụm. Chế độ số lượng tự tính khe để phủ đều vùng còn lại.</small></section>
        <section class="backed"><label>Độ dày tấm lót<span><input id="backing" type="number" min="0.1" step="0.1"> mm</span></label>
        <label>Hạ âm<span><input id="recess" type="number" min="0" step="0.1"> mm</span></label>
        <label>Bật CNC<input id="cnc" type="checkbox"></label><label>Tên công đoạn CNC<input id="tag" type="text" style="width:240px"></label>
        <small><b>ASPIRE:</b> Mỗi lam tạo một vùng gia công <b>TAM_LOT → _ABF_Intersect</b> gồm 1 Face + 4 Edge, gắn Tag công đoạn (mặc định ABF_HANENLAMAM). Face tấm lót được đánh dấu ABF/is-cnced-face. Không dùng _ABF_cuttingLines để mô tả rãnh lam nữa.</small></section>
        <button onclick="apply()">CẬP NHẬT PREVIEW</button>
        <p id="editBox" class="edit" style="display:none"><button onclick="sketchup.apply_edit()">ÁP DỤNG VÀO VÁCH ĐÃ CHỌN</button></p>
        <p><button onclick="sketchup.repair_abf()">SỬA TẤM LÓT ABF ĐÃ CHỌN</button></p><p id="error"></p>
        <section><canvas id="preview" width="420" height="170"></canvas><div id="info"></div><small>Click P1 → rê thấy preview → click P2, hoặc giữ chuột từ P1 rồi kéo và thả tại P2. Khi thả, plugin tạo đúng preview cuối cùng. ESC bỏ vùng đang vẽ.</small></section></main>
        <script>
        const keys=#{JSON.generate(DEFAULTS.keys)};
        function visibility(){document.querySelectorAll('.backed').forEach(e=>e.style.display=document.getElementById('mode').value==='backed'?'block':'none');document.querySelectorAll('.counted').forEach(e=>e.style.display=document.getElementById('spacing_mode').value==='count'?'flex':'none')}
        function apply(){const o={};keys.forEach(k=>{let e=document.getElementById(k);o[k]=e.type==='checkbox'?e.checked:(e.type==='number'?Number(e.value):e.value)});sketchup.update(JSON.stringify(o))}
        function showError(s){document.getElementById('error').textContent=s}
        function receive(s){keys.forEach(k=>{let e=document.getElementById(k);if(!e)return;if(e.type==='checkbox')e.checked=s.options[k];else e.value=s.options[k]});visibility();document.getElementById('editBox').style.display=s.editing?'block':'none';showError(s.error||'');const c=document.getElementById('preview'),ctx=c.getContext('2d');ctx.clearRect(0,0,c.width,c.height);const d=s.layout;if(!d)return;let scale=Math.min(392/d.width,142/d.height),ox=(420-d.width*scale)/2,oy=(170-d.height*scale)/2;d.panels.forEach(p=>{if(p.backing){ctx.fillStyle='#b1bac2';ctx.fillRect(ox+p.x*scale,oy+p.y*scale,p.width*scale,p.height*scale)}p.slats.forEach((b,i)=>{ctx.fillStyle='#c58e57';let poly=p.slat_polygons&&p.slat_polygons[i];if(poly){ctx.beginPath();poly.forEach((pt,j)=>{let X=ox+pt[0]*scale,Y=oy+pt[1]*scale;j?ctx.lineTo(X,Y):ctx.moveTo(X,Y)});ctx.closePath();ctx.fill()}else{ctx.fillRect(ox+b[0]*scale,oy+b[1]*scale,Math.max(1,b[3]*scale),Math.max(1,b[4]*scale))}});ctx.strokeStyle='#5c707d';ctx.strokeRect(ox+p.x*scale,oy+p.y*scale,p.width*scale,p.height*scale)});document.getElementById('info').textContent=(s.editing?'Vách đang chọn · ':(s.sample?'Mô phỏng mẫu · ':'Vùng đang vẽ · '))+d.width.toFixed(1)+' × '+d.height.toFixed(1)+' mm · '+({vertical:'nan dọc',horizontal:'nan ngang',diag_right:'chéo phải 45°',diag_left:'chéo trái 45°'}[d.orientation]||d.orientation)+' · '+d.panels.length+' cụm VL · '+d.slat_count+' nan · khe '+d.gap.toFixed(2)+' mm'}
        window.addEventListener('load',()=>sketchup.ready());
        </script></html>
      HTML
    end

    BOX_FACES = [[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]].freeze
    BOX_EDGES = [[0,1],[0,2],[1,3],[2,3],[4,5],[4,6],[5,7],[6,7],[0,4],[1,5],[2,6],[3,7]].freeze

    def box_points(box)
      x,y,z,w,h,d = box
      (0..7).map { |i| Geom::Point3d.new((x + ((i & 1) == 0 ? 0 : w)).mm,
        (y + ((i & 2) == 0 ? 0 : h)).mm, (z + ((i & 4) == 0 ? 0 : d)).mm) }
    end

    PRISM_FACES = [[0,1,2,3],[4,5,6,7],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]].freeze
    PRISM_EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].freeze

    def slat_prism_points(polygon, z, depth)
      base = polygon.map { |x,y| Geom::Point3d.new(x.mm,y.mm,z.mm) }
      top = polygon.map { |x,y| Geom::Point3d.new(x.mm,y.mm,(z + depth).mm) }
      base + top
    end

    def make_polygon_prism(entities, polygon, z, depth, name, material, tag = nil)
      group = entities.add_group
      group.name = name
      group.material = material
      group.layer = tag || Sketchup.active_model.layers[0]
      points = slat_prism_points(polygon, z, depth)
      PRISM_FACES.each do |indices|
        face = group.entities.add_face(indices.map { |i| points[i] })
        raise 'Không tạo được mặt kín cho nan chéo.' unless face
        face.layer = Sketchup.active_model.layers[0]
        face.edges.each { |edge| edge.layer = Sketchup.active_model.layers[0] }
      end
      orient_outward_faces(group, material)
      group
    end

    def direct_shell_faces(group)
      group.entities.grep(Sketchup::Face)
    end

    def shell_center(faces)
      bounds = Geom::BoundingBox.new
      faces.each do |face|
        face.vertices.each { |vertex| bounds.add(vertex.position) }
      end
      raise 'Khối không có Face để kiểm tra hướng.' if faces.empty?
      bounds.center
    end

    def face_outward_score(face, center)
      outward = center.vector_to(face.bounds.center)
      return 1.0 if outward.length < 1.0e-9
      face.normal.dot(outward)
    end

    def orient_outward_faces(group, material = nil)
      faces = direct_shell_faces(group)
      center = shell_center(faces)

      faces.each do |face|
        face.reverse! if face_outward_score(face, center) < 0
        if material
          face.material = material if face.respond_to?(:material=)
          face.back_material = nil if face.respond_to?(:back_material=)
        end
      end

      wrong = faces.select { |face| face_outward_score(face, center) <= 0 }
      unless wrong.empty?
        raise "Còn #{wrong.length} Face bị lộn mặt trong group #{group.name}."
      end
      group.set_attribute(KEY, 'faces_outward', true) if group.respond_to?(:set_attribute)
      group
    end

    # TAM_LOT: mọi mặt ngoài đều là mặt phải; riêng local +Z là phía nan/phía trước.
    def orient_backing_front(backing)
      faces = direct_shell_faces(backing)
      orient_outward_faces(backing, backing.material)
      bounds = Geom::BoundingBox.new
      faces.each { |face| face.vertices.each { |vertex| bounds.add(vertex.position) } }
      z_min = bounds.min.z.to_f
      z_max = bounds.max.z.to_f
      tolerance = [0.01.mm.to_f, (z_max - z_min).abs * 1.0e-6].max

      front_faces = []
      rear_faces = []
      faces.each do |face|
        zs = face.vertices.map { |vertex| vertex.position.z.to_f }
        next if zs.empty?
        if zs.all? { |z| (z - z_max).abs <= tolerance }
          face.reverse! if face.normal.z.to_f < 0
          face.set_attribute(KEY, 'side', 'front') if face.respond_to?(:set_attribute)
          front_faces << face
        elsif zs.all? { |z| (z - z_min).abs <= tolerance }
          face.reverse! if face.normal.z.to_f > 0
          face.set_attribute(KEY, 'side', 'rear') if face.respond_to?(:set_attribute)
          rear_faces << face
        end
      end

      raise 'Không xác định được mặt trước TAM_LOT.' if front_faces.empty?
      raise 'Không xác định được mặt sau TAM_LOT.' if rear_faces.empty?
      raise 'Mặt trước TAM_LOT vẫn bị lộn.' unless front_faces.all? { |face| face.normal.z.to_f > 0 }
      raise 'Mặt sau TAM_LOT vẫn bị lộn.' unless rear_faces.all? { |face| face.normal.z.to_f < 0 }

      # Kiểm tra lần cuối toàn bộ shell sau khi ép +Z/-Z.
      orient_outward_faces(backing, backing.material)
      backing.set_attribute(KEY, 'front_side', 'local_z_positive')
      backing.set_attribute(KEY, 'front_is_right_face', true)
      backing.set_attribute(KEY, 'faces_verified', true)
      backing
    end

    def abf_cutting_group?(entity)
      entity.is_a?(Sketchup::Group) &&
        (entity.get_attribute('ABF', 'is-cutting-lines') == true ||
         entity.name.to_s == '_ABF_cuttingLines')
    end

    def abf_intersect_group?(entity)
      entity.is_a?(Sketchup::Group) &&
        (entity.get_attribute('ABF', 'is-intersect') == true ||
         entity.name.to_s == ABF_INTERSECT_NAME)
    end

    def abf_auxiliary_group?(entity)
      return true if abf_cutting_group?(entity) || abf_intersect_group?(entity)
      return false unless entity.is_a?(Sketchup::Group)
      entity.get_attribute('ABF', 'is-label') == true ||
        entity.get_attribute('ABF', 'is-edge-banding-notation') == true
    end

    def backing_front_z(backing)
      faces = backing.entities.grep(Sketchup::Face)
      raise 'TAM_LOT không có Face.' if faces.empty?
      bounds = backing.definition.bounds
      z = bounds.max.z
      front = faces.select do |face|
        face.vertices.all? { |v| (v.position.z.to_f - z.to_f).abs <= 0.01.mm.to_f }
      end
      raise 'Không tìm thấy mặt phải/phía trước của TAM_LOT.' if front.empty?
      z
    end

    def backing_front_face(backing)
      z = backing_front_z(backing)
      face = backing.entities.grep(Sketchup::Face).find do |candidate|
        candidate.vertices.all? { |v| (v.position.z.to_f - z.to_f).abs <= 0.01.mm.to_f }
      end
      raise 'Không tìm thấy Face CNC của TAM_LOT.' unless face
      face
    end

    def entity_reference_id(entity, fallback = 0)
      return entity.persistent_id if entity.respond_to?(:persistent_id)
      return entity.entityID if entity.respond_to?(:entityID)
      fallback.to_i
    rescue StandardError
      fallback.to_i
    end

    def operation_setting_name(tag_name)
      text = tag_name.to_s.sub(/\AABF_/, '').tr('_', ' ').strip
      text.empty? ? 'hạ nền vách lam' : text.downcase
    end

    def add_abf_intersect_profile(backing, points, number, operation_tag_name, depth, source_entity = nil)
      model = Sketchup.active_model
      tag_name = operation_tag_name.to_s
      tag_name = 'ABF_HANENLAMAM' if tag_name.empty?
      tag_name = 'ABF_' + tag_name unless tag_name.start_with?('ABF_')
      tag = ensure_tag(model, tag_name)

      group = backing.entities.add_group
      group.name = ABF_INTERSECT_NAME
      group.layer = tag
      group.set_attribute('ABF', 'is-intersect', true)
      group.set_attribute('ABF', 'intersect-offset', 0.0)
      group.set_attribute('ABF', 'setting-name', operation_setting_name(tag_name))
      group.set_attribute('ABF', 'intersect-group-b-id', entity_reference_id(source_entity, number))
      group.set_attribute(KEY, 'role', 'cnc_profile')
      group.set_attribute(KEY, 'profile', number)
      group.set_attribute(KEY, 'depth_mm', depth)
      group.set_attribute(KEY, 'operation_tag', tag_name)

      # SketchUp thật: tạo Face trước để topology tự sinh đúng vòng 4 cạnh.
      # Chỉ fallback add_edges cho test-double / trường hợp API không trả face.edges.
      face = group.entities.add_face(points)
      raise 'Không tạo được Face biên dạng lam cho Aspire.' unless face
      face.reverse! if face.respond_to?(:normal) && face.normal.z.to_f < 0

      edges = begin
        face.edges.to_a
      rescue StandardError
        []
      end
      if edges.length != 4
        edges = group.entities.add_edges(*(points + [points.first]))
      end
      edges = edges.uniq
      raise "Biên dạng lam #{number} phải có đúng 4 Edge, hiện có #{edges.length}." unless edges.length == 4

      # Kiểm tra topology thật ngay tại lúc tạo, trước khi gán metadata ABF.
      actual_faces = group.entities.grep(Sketchup::Face)
      actual_edges = group.entities.grep(Sketchup::Edge)
      if actual_faces.length != 1 || actual_edges.length != 4
        raise "Biên dạng lam #{number} không hợp lệ: #{actual_faces.length} Face + #{actual_edges.length} Edge."
      end

      edges.each do |edge|
        edge.layer = tag
        edge.set_attribute(KEY, 'role', 'cnc_edge')
        edge.set_attribute(KEY, 'profile', number)
        edge.set_attribute(KEY, 'profiles', [number])
        edge.set_attribute(KEY, 'depth_mm', depth)
      end
      face.layer = tag
      face.set_attribute(KEY, 'role', 'cnc_face')
      face.set_attribute(KEY, 'profile', number)
      face.set_attribute(KEY, 'depth_mm', depth)

      cnc_face = backing_front_face(backing)
      cnc_face.set_attribute('ABF', 'is-cnced-face', true)
      group
    end

    def ensure_abf_cutting_group(backing)
      groups = backing.entities.grep(Sketchup::Group).select { |group| abf_cutting_group?(group) }
      group = groups.first
      if group.nil?
        group = backing.entities.add_group
        group.name = '_ABF_cuttingLines'
      end
      tag = ensure_tag(Sketchup.active_model, ABF_CUTTING_TAG)
      group.layer = tag
      group.set_attribute('ABF', 'is-cutting-lines', true)
      group.set_attribute(KEY, 'role', 'cnc_cutting_lines')
      group
    end

    def backing_profile_summary(backing)
      nested = backing.entities.select do |entity|
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end
      cutting_groups = nested.select { |entity| abf_cutting_group?(entity) }
      intersect_groups = nested.select { |entity| abf_intersect_group?(entity) }
      unknown_nested = nested.reject { |entity| abf_auxiliary_group?(entity) }
      direct_cnc = backing.entities.grep(Sketchup::Edge).select do |edge|
        edge.get_attribute(KEY, 'role') == 'cnc_edge'
      end

      profiles = intersect_groups.map do |group|
        edges = group.entities.grep(Sketchup::Edge)
        faces = group.entities.grep(Sketchup::Face)
        {
          number: group.get_attribute(KEY, 'profile', 0).to_i,
          edge_count: edges.length,
          face_count: faces.length,
          group: group
        }
      end
      {
        nested_count: nested.length,
        cutting_group_count: cutting_groups.length,
        intersect_group_count: intersect_groups.length,
        unknown_nested_count: unknown_nested.length,
        direct_edge_count: direct_cnc.length,
        edge_count: profiles.sum { |profile| profile[:edge_count] },
        profile_count: profiles.count { |profile| profile[:number] > 0 },
        complete: profiles.all? { |profile| profile[:number] > 0 && profile[:edge_count] == 4 && profile[:face_count] == 1 },
        face_count: backing.entities.grep(Sketchup::Face).length
      }
    end

    def enforce_backing_integrity(backing, expected_profiles = nil)
      summary = backing_profile_summary(backing)
      raise 'TAM_LOT có group con không thuộc chuẩn ABF.' unless summary[:unknown_nested_count] == 0
      raise 'Không được tự tạo _ABF_cuttingLines cho biên dạng lam.' unless summary[:cutting_group_count] == 0
      raise 'Edge CNC đang nằm trực tiếp trên mặt tấm.' unless summary[:direct_edge_count] == 0
      raise 'Hình học TAM_LOT phải giữ đúng 6 Face.' unless summary[:face_count] == 6
      raise 'Biên dạng lam phải là _ABF_Intersect có 1 Face + 4 Edge.' unless summary[:complete]

      face_z = backing_front_z(backing)
      intersects = backing.entities.grep(Sketchup::Group).select { |group| abf_intersect_group?(group) }
      off_face = intersects.any? do |group|
        points = group.entities.grep(Sketchup::Edge).flat_map { |edge| [edge.start.position, edge.end.position] }
        points.any? { |point| (point.z.to_f - face_z.to_f).abs > 0.01.mm.to_f }
      end
      raise 'Biên dạng lam chưa nằm đồng phẳng trên Face TAM_LOT.' if off_face

      unless expected_profiles.nil?
        expected = expected_profiles.to_i
        raise "Thiếu biên dạng lam cho Aspire (#{summary[:profile_count]}/#{expected})." unless summary[:profile_count] == expected
      end

      cnc_face = backing_front_face(backing)
      cnc_face.set_attribute('ABF', 'is-cnced-face', true) unless intersects.empty?
      backing.set_attribute(KEY, 'profiles_embedded', true)
      backing.set_attribute(KEY, 'profiles_on_face', true)
      backing.set_attribute(KEY, 'profile_face', 'front_right')
      backing.set_attribute(KEY, 'profile_type', 'ABF_Intersect')
      backing.set_attribute(KEY, 'profile_count', summary[:profile_count])
      orient_backing_front(backing)
      summary
    end

    def make_box(entities, box, name, material, tag = nil)
      group = entities.add_group
      group.name = name
      group.material = material
      group.layer = tag || Sketchup.active_model.layers[0]
      pts = box_points(box)
      BOX_FACES.each do |indices|
        face = group.entities.add_face(indices.map { |i| pts[i] })
        raise 'Không tạo được mặt kín cho tấm.' unless face
        face.layer = Sketchup.active_model.layers[0]
        face.edges.each { |e| e.layer = Sketchup.active_model.layers[0] }
      end
      orient_outward_faces(group, material)
      group
    end

    def material(model, name, rgb)
      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*rgb)
      m
    end

    def ensure_tag(model, name)
      model.layers[name] || model.layers.add(name)
    end

    def next_number(model)
      value = model.get_attribute(KEY, 'next_vl', 1).to_i
      pools = [model.entities] + model.definitions.map(&:entities)
      pools.each do |entities|
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          match = /\AVL(\d+)\z/.match(entity.name.to_s)
          value = [value, match[1].to_i + 1].max if match
        end
      end
      [value, 1].max
    end

    def wall_number(parent)
      stored = parent.get_attribute(KEY, 'first_vl', nil)
      return stored.to_i if stored && stored.to_i > 0
      numbers = parent.entities.grep(Sketchup::Group).map do |entity|
        match = /\AVL(\d+)\z/.match(entity.name.to_s)
        match && match[1].to_i
      end.compact
      numbers.min
    end

    def populate_parent(parent, model, plan, first_number)
      o = plan[:options]
      parent_tag = ensure_tag(model, 'TT_VACH_LAM')
      slat_tag = ensure_tag(model, 'TT_NAN_LAM')
      parent.name = "VACH_LAM_#{plan[:width].round}x#{plan[:height].round}"
      parent.layer = parent_tag
      parent.set_attribute(KEY, 'role', 'wall')
      parent.set_attribute(KEY, 'version', VERSION)
      parent.set_attribute(KEY, 'settings', JSON.generate(o))
      parent.set_attribute(KEY, 'size_mm', [plan[:width], plan[:height]])
      parent.set_attribute(KEY, 'first_vl', first_number)

      wood = material(model, 'TT Vách lam - Gỗ', [190,140,88])
      backmat = material(model, 'TT Vách lam - Tấm lót', [160,166,174])
      profile_enabled = o['mode'] == 'backed'
      operation_tag = profile_enabled ? ensure_tag(model, o['tag']) : nil

      plan[:panels].each_with_index do |panel, index|
        vl = parent.entities.add_group
        vl.name = "VL#{first_number + index}"
        vl.layer = parent_tag
        vl.set_attribute(KEY, 'role', 'panel')
        vl.set_attribute(KEY, 'stock_mm', [o['stock_length'],o['stock_width'],o['stock_thickness']])
        backing = panel[:backing] ? make_box(vl.entities, panel[:backing], "#{vl.name}_TAM_LOT", backmat) : nil

        panel[:slats].each_with_index do |box, slat_index|
          polygon = panel[:slat_polygons] && panel[:slat_polygons][slat_index]
          if polygon
            slat = make_polygon_prism(vl.entities, polygon, box[2], box[5], "#{vl.name}_LAM#{slat_index + 1}", wood, slat_tag)
            length = panel[:slat_lengths][slat_index]
            slat.set_attribute(KEY, 'size_mm', [o['width'], length, box[5]])
          else
            slat = make_box(vl.entities, box, "#{vl.name}_LAM#{slat_index + 1}", wood, slat_tag)
            slat.set_attribute(KEY, 'size_mm', [box[3],box[4],box[5]])
          end
          slat.set_attribute(KEY, 'role', 'slat')
          next unless backing && profile_enabled
          face_z = backing_front_z(backing)
          if polygon
            pts = polygon.map { |a,b| Geom::Point3d.new(a.mm,b.mm,face_z) }
          else
            x,y,_z,w,h,_d = box
            pts = [[x,y],[x+w,y],[x+w,y+h],[x,y+h]].map { |a,b| Geom::Point3d.new(a.mm,b.mm,face_z) }
          end
          depth = o['cnc'] ? o['recess'] : 0.0
          add_abf_intersect_profile(backing, pts, slat_index + 1, o['tag'], depth, slat)
        end

        if backing
          backing.layer = model.layers[0]
          backing.set_attribute('ABF', 'is-board', true)
          backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'do_day_mm', o['backing'])
          backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'loai', 'VAN')
          backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'chi_tiet', 'TAM_LOT_VACH_LAM')
          backing.set_attribute(KEY, 'role', 'backing')
          backing.set_attribute(KEY, 'size_mm', [panel[:width], panel[:height], o['backing']])
          backing.set_attribute(KEY, 'profile_count', profile_enabled ? panel[:slats].length : 0)
          backing.set_attribute(KEY, 'depth_mm', o['cnc'] ? o['recess'] : 0.0)
          backing.set_attribute(KEY, 'cnc_tag', o['tag']) if profile_enabled
          backing.set_attribute(KEY, 'operation_tag', o['tag']) if profile_enabled
          backing.set_attribute(KEY, 'profiles_source', 'slats')
          expected_profiles = profile_enabled ? panel[:slats].length : 0
          enforce_backing_integrity(backing, expected_profiles)
        end
      end
      parent
    end

    def create(model, plan, world_transform)
      raise 'Không có preview hợp lệ.' unless plan && plan[:panels].any?
      raise 'Đang chỉnh sửa group bị khóa.' if (model.active_path || []).any?(&:locked?)
      model.start_operation('TT - Tạo vách lam', true)
      started = true
      first_number = next_number(model)
      parent = model.active_entities.add_group
      parent.transformation = model.edit_transform.inverse * world_transform
      populate_parent(parent, model, plan, first_number)
      model.set_attribute(KEY, 'next_vl', first_number + plan[:panels].length)
      model.commit_operation
      parent
    rescue StandardError
      model.abort_operation if started
      raise
    end

    def update_existing(parent, plan)
      raise 'Vách đã chọn không hợp lệ.' unless parent && plan && plan[:panels].any?
      raise 'Vách đang khóa. Mở khóa trước khi sửa.' if parent.locked?
      model = Sketchup.active_model
      model.start_operation('TT - Cập nhật vách lam', true)
      started = true
      parent.make_unique if parent.definition.instances.length > 1
      first_number = wall_number(parent) || next_number(model)
      children = parent.entities.to_a
      parent.entities.erase_entities(children) unless children.empty?
      populate_parent(parent, model, plan, first_number)
      model.commit_operation
      parent
    rescue StandardError
      model.abort_operation if started
      raise
    end

    def add_cnc_profile(backing, points, number, tag, depth, source_entity = nil)
      tag_name = tag.respond_to?(:name) ? tag.name.to_s : tag.to_s
      add_abf_intersect_profile(backing, points, number, tag_name, depth, source_entity)
    end

    def migrate_sibling_profiles_into_backing(backing, panel, _model)
      return [] unless panel && panel.respond_to?(:entities)
      records = []
      panel.entities.grep(Sketchup::Group).each do |group|
        next if group.equal?(backing)
        role = group.get_attribute(KEY, 'role')
        name = group.name.to_s
        next unless role == 'cnc_profile' || role == 'cnc_cutting_lines' ||
                    name == '_ABF_cuttingLines' || name.match?(/LAM_PROFILE/i)
        group.entities.grep(Sketchup::Edge).each do |edge|
          number = edge.get_attribute(KEY, 'profile', 0).to_i
          depth = edge.get_attribute(KEY, 'depth_mm', backing.get_attribute(KEY, 'depth_mm', 0.0))
          records << [edge.start.position, edge.end.position, number, depth]
        end
        panel.entities.erase_entities(group) if group.valid?
      end
      records
    end

    def normalize_panel_slats_to_front(panel, old_front_mm)
      return if panel.nil? || old_front_mm.abs < 0.001
      shift = Geom::Transformation.translation(Geom::Vector3d.new(0,0,(-old_front_mm).mm))
      panel.entities.grep(Sketchup::Group).each do |group|
        next unless group.get_attribute(KEY, 'role') == 'slat' || group.name.to_s.match?(/_LAM\d+\z/)
        group.transform!(shift)
      end
    end

    def rebuild_profiles_from_panel_slats(backing, panel, model)
      return 0 unless panel && panel.respond_to?(:entities)
      slats = panel.entities.grep(Sketchup::Group).select do |group|
        group.get_attribute(KEY, 'role') == 'slat' || group.name.to_s.match?(/_LAM\d+\z/)
      end
      return 0 if slats.empty?

      legacy = backing.entities.grep(Sketchup::Group).select do |group|
        abf_cutting_group?(group) || abf_intersect_group?(group) ||
          group.get_attribute(KEY, 'role') == 'cnc_profile'
      end
      backing.entities.erase_entities(legacy) unless legacy.empty?

      face_z = backing_front_z(backing)
      tag_name = backing.get_attribute(KEY, 'operation_tag', 'ABF_HANENLAMAM')
      depth = backing.get_attribute(KEY, 'depth_mm', 0.0)

      slats.each_with_index do |slat,index|
        b = slat.definition.bounds
        pts = [
          Geom::Point3d.new(b.min.x,b.min.y,face_z),
          Geom::Point3d.new(b.max.x,b.min.y,face_z),
          Geom::Point3d.new(b.max.x,b.max.y,face_z),
          Geom::Point3d.new(b.min.x,b.max.y,face_z)
        ]
        add_abf_intersect_profile(backing, pts, index + 1, tag_name, depth, slat)
      end
      backing.set_attribute(KEY, 'profiles_source', 'slats')
      slats.length
    end

    def repair_selected_backings
      model = Sketchup.active_model
      found = []
      walk = lambda do |entities, ancestors, panel|
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next if ancestors.include?(entity.definition)
          raise 'Group đang khóa. Mở khóa trước khi sửa.' if entity.locked?
          current_panel = entity.get_attribute(KEY, 'role') == 'panel' || entity.name.to_s.match?(/\AVL\d+\z/) ? entity : panel
          if entity.get_attribute(KEY, 'role') == 'backing' ||
             entity.name.to_s.match?(/\AVL\d+_TAM_LOT\z/)
            found << [entity, current_panel]
          else
            raise 'Group cha có nhiều bản sao. Make Unique group cha trước khi sửa.' if entity.definition.instances.length > 1
            walk.call(entity.definition.entities, ancestors + [entity.definition], current_panel)
          end
        end
      end
      walk.call(model.selection.to_a, [], nil)
      raise 'Chọn group vách lam hoặc tấm lót cần sửa trước.' if found.empty?
      raise 'Tấm lót đang khóa.' if found.any? { |pair| pair[0].locked? }
      model.start_operation('TT - Sửa tấm lót nhận ABF', true)
      started = true
      found.uniq.each do |backing, panel|
        repair_backing(backing, model, panel)
      end
      model.commit_operation
      UI.messagebox("Đã đưa biên dạng lam vào trong TAM_LOT cho #{found.uniq.length} tấm lót.")
    rescue StandardError => e
      model.abort_operation if started
      UI.messagebox(e.message)
    end

    def shell_box_mm(backing)
      points = backing.entities.grep(Sketchup::Face).flat_map do |face|
        face.vertices.map(&:position)
      end
      raise 'TAM_LOT không có hình học tấm.' if points.empty?
      xs = points.map { |p| p.x.to_f }
      ys = points.map { |p| p.y.to_f }
      zs = points.map { |p| p.z.to_f }
      [xs.min * 25.4, ys.min * 25.4, zs.min * 25.4,
       (xs.max - xs.min) * 25.4, (ys.max - ys.min) * 25.4, (zs.max - zs.min) * 25.4]
    end

    def rebuild_backing_shell(backing, box)
      shell = backing.entities.select do |entity|
        entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
      end
      shell.each { |entity| backing.entities.erase_entities(entity) if entity.valid? }
      pts = box_points(box)
      BOX_FACES.each do |indices|
        face = backing.entities.add_face(indices.map { |i| pts[i] })
        raise 'Không dựng lại được mặt tấm lót.' unless face
        face.layer = Sketchup.active_model.layers[0]
        face.edges.each { |edge| edge.layer = Sketchup.active_model.layers[0] }
      end
      orient_backing_front(backing)
    end

    def repair_backing(backing, model, panel = nil)
      backing.make_unique if backing.definition.instances.length > 1
      migrate_sibling_profiles_into_backing(backing, panel, model) if panel
      default_depth = backing.get_attribute(KEY, 'depth_mm', 0.0)
      shell_box = shell_box_mm(backing)
      old_front_mm = shell_box[2] + shell_box[5]
      thickness_mm = shell_box[5]
      normalized_box = [shell_box[0], shell_box[1], -thickness_mm, shell_box[3], shell_box[4], thickness_mm]
      records = []

      source_groups = backing.entities.grep(Sketchup::Group).select do |group|
        group.get_attribute(KEY, 'role') == 'cnc_profile' ||
          abf_cutting_group?(group) || abf_intersect_group?(group)
      end
      source_groups.each do |group|
        group_profile = group.get_attribute(KEY, 'profile', 0).to_i
        group_depth = group.get_attribute(KEY, 'depth_mm', default_depth)
        group.entities.grep(Sketchup::Edge).each do |edge|
          number = edge.get_attribute(KEY, 'profile', group_profile).to_i
          depth = edge.get_attribute(KEY, 'depth_mm', group_depth)
          records << [edge.start.position, edge.end.position, number, depth]
        end
      end

      direct_profiles = backing.entities.grep(Sketchup::Edge).select do |edge|
        edge.get_attribute(KEY, 'role') == 'cnc_edge' ||
          !Array(edge.get_attribute(KEY, 'profiles', [])).empty?
      end
      direct_profiles.each do |edge|
        numbers = Array(edge.get_attribute(KEY, 'profiles', []))
        number = edge.get_attribute(KEY, 'profile', numbers.first || 0).to_i
        depth = edge.get_attribute(KEY, 'depth_mm', default_depth)
        records << [edge.start.position, edge.end.position, number, depth]
      end

      source_groups.each { |group| backing.entities.erase_entities(group) if group.valid? }
      direct_profiles.each { |edge| backing.entities.erase_entities(edge) if edge.valid? }

      # Chuẩn hóa mọi tấm cũ về quy ước ABF: mặt phải z=0, dày đi về -Z.
      # Đồng thời dựng lại shell sạch 6 Face nếu các bản cũ từng chia mặt.
      rebuild_backing_shell(backing, normalized_box)
      normalize_panel_slats_to_front(panel, old_front_mm) if panel

      face_z = backing_front_z(backing)
      records = records.map do |a,b,number,depth|
        [Geom::Point3d.new(a.x,a.y,face_z), Geom::Point3d.new(b.x,b.y,face_z), number, depth]
      end

      unless records.empty? || panel
        tag_name = backing.get_attribute(KEY, 'operation_tag', 'ABF_HANENLAMAM')
        face_z = backing_front_z(backing)
        records.group_by { |record| record[2].to_i }.each do |number, profile_records|
          next if number <= 0
          points = profile_records.flat_map { |a,b,_n,_d| [a,b] }
          unique = []
          points.each do |point|
            p = Geom::Point3d.new(point.x, point.y, face_z)
            unique << p unless unique.any? { |q| q.distance(p) < 0.01.mm }
          end
          next unless unique.length == 4
          cx = unique.sum { |p| p.x.to_f } / 4.0
          cy = unique.sum { |p| p.y.to_f } / 4.0
          ordered = unique.sort_by { |p| Math.atan2(p.y.to_f - cy, p.x.to_f - cx) }
          depth = profile_records.first[3]
          add_abf_intersect_profile(backing, ordered, number, tag_name, depth, nil)
        end
      end

      backing.entities.each do |entity|
        next unless entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
        entity.layer = model.layers[0]
      end
      backing.layer = model.layers[0]
      thickness = thickness_mm.round(3)
      backing.set_attribute('ABF', 'is-board', true)
      backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'do_day_mm', thickness)
      backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'loai', 'VAN')
      backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'chi_tiet', 'TAM_LOT_VACH_LAM')
      backing.set_attribute(KEY, 'role', 'backing')
      backing.set_attribute(KEY, 'cnc_tag', ABF_CUTTING_TAG)

      profile_numbers = records.map { |record| record[2].to_i }.select { |number| number > 0 }.uniq
      if panel
        rebuilt = rebuild_profiles_from_panel_slats(backing, panel, model)
        profile_numbers = (1..rebuilt).to_a if rebuilt > 0
      end
      backing.set_attribute(KEY, 'profile_count', profile_numbers.length)
      enforce_backing_integrity(backing, profile_numbers.length)
      true
    end

    class Tool
      def initialize(options, edit_target = nil)
        @options = options
        @edit_target = edit_target
        @ip = Sketchup::InputPoint.new
        @first_ip = Sketchup::InputPoint.new
        @shift_down = false
        @tab_down = false
        reset
      end
      def activate
        status
        SlatWall.show_settings(self)
      end
      def deactivate(view)
        @shift_down = false
        if SlatWall.instance_variable_get(:@tool).equal?(self)
          SlatWall.instance_variable_set(:@tool, nil)
          dialog = SlatWall.instance_variable_get(:@dialog)
          dialog.close if dialog
        end
        view.invalidate
      end
      def reset
        @first_ip.clear
        @p1 = @p2 = @basis = @plan = @draw_transform = nil
        @preview_boxes = []
        @preview_mesh = {}
        @error = nil
        @drag_start = nil
        @hover = nil
        @free_mode = false
        @free_axis = nil
        @p1_locked = false
        @raw_p2 = nil
        @p1_plane_normal = nil
        @plane_mode = :auto
      end
      def status
        mode = @options['mode'] == 'backed' ? 'CÓ TẤM LÓT' : 'LAM ĐƠN'
        direction = {
          'vertical'=>'NAN DỌC','horizontal'=>'NAN NGANG',
          'diag_right'=>'NAN CHÉO PHẢI 45°','diag_left'=>'NAN CHÉO TRÁI 45°'
        }[@options['orientation']] || @options['orientation'].to_s
        action = @edit_target ? 'đang sửa vách đã chọn; chỉnh thông số rồi bấm ÁP DỤNG' : (@p1 ? 'P1 ĐÃ CỐ ĐỊNH · bắt góc chéo P2 bất kỳ' : 'chọn P1')
        axis_text = @free_axis ? " · TỰ NHẬN TRỤC #{@free_axis.to_s.upcase}" : ''
        Sketchup.status_text = "TT VÁCH LAM · #{mode} · #{direction}#{axis_text} · #{action} · SHIFT XOAY NAN · TAB DỌC/NGANG · SNAP ENDPOINT 24px · ESC hủy"
      end
      def dialog_state
        if @edit_target
          size = Array(@edit_target.get_attribute(KEY, 'size_mm', []))
          plan = size.length == 2 ? SlatWall.layout(size[0], size[1], @options) : nil
          { options: @options, layout: plan, sample: false, editing: true, error: @error }
        else
          sample = @plan.nil?
          plan = @plan || SlatWall.layout(@options['stock_width'], @options['stock_length'], @options)
          { options: @options, layout: plan, sample: sample, editing: false, error: @error }
        end
      rescue StandardError => e
        { options: @options, layout: nil, sample: true, editing: !@edit_target.nil?, error: e.message }
      end
      def update_settings(options)
        @options = options
        rebuild if @p1 && @p2
        status
        Sketchup.active_model.active_view.invalidate
      end
      def apply_selected_edit
        raise 'Không có vách lam được chọn để cập nhật.' unless @edit_target
        size = Array(@edit_target.get_attribute(KEY, 'size_mm', []))
        raise 'Vách cũ thiếu kích thước gốc.' unless size.length == 2
        plan = SlatWall.layout(size[0], size[1], @options)
        SlatWall.update_existing(@edit_target, plan)
        @error = nil
        SlatWall.save_settings(@options)
        SlatWall.send_state
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add(@edit_target)
        Sketchup.active_model.active_view.invalidate
        UI.messagebox('Đã cập nhật vách lam trong một thao tác Undo.')
        true
      rescue StandardError => e
        @error = e.message
        SlatWall.send_state
        UI.messagebox("Không cập nhật được vách lam: #{e.message}")
        false
      end
      def cycle_slat_orientation(view)
        current = SLAT_ORIENTATIONS.index(@options['orientation']) || 0
        next_orientation = SLAT_ORIENTATIONS[(current + 1) % SLAT_ORIENTATIONS.length]
        @options = SlatWall.validate(@options.merge('orientation' => next_orientation))
        SlatWall.save_settings(@options)
        rebuild if @p1 && @p2
        SlatWall.send_state
        status
        view.invalidate
      rescue StandardError => e
        @error = e.message
        view.invalidate
      end

      def onKeyDown(key, repeat, _flags, view)
        if key == 16
          return true if @shift_down || repeat.to_i > 1
          @shift_down = true
          cycle_slat_orientation(view)
          true
        elsif key == 9
          return true if @tab_down || repeat.to_i > 1
          @tab_down = true
          @options = SlatWall.validate(@options.merge('orientation' => @options['orientation'] == 'vertical' ? 'horizontal' : 'vertical'))
          SlatWall.save_settings(@options)
          rebuild if @p1 && @p2
          SlatWall.send_state
          status
          view.invalidate
          true
        elsif key == 83
          SlatWall.show_settings(self)
          true
        else
          false
        end
      end
      def onKeyUp(key, _repeat, _flags, _view)
        @shift_down = false if key == 16
        @tab_down = false if key == 9
      end
      def onCancel(_reason, view)
        if @p1
          reset
          SlatWall.send_state
          status
          view.invalidate
        else
          Sketchup.active_model.select_tool(nil)
        end
      end
      def free_view_anchor(view)
        camera = view.camera
        return camera.target if camera.respond_to?(:target) && camera.target
        model = Sketchup.active_model
        bounds = model.bounds if model.respond_to?(:bounds)
        return bounds.center if bounds && bounds.respond_to?(:valid?) && bounds.valid?
        Geom::Point3d.new(0,0,0)
      rescue StandardError
        Geom::Point3d.new(0,0,0)
      end
      def free_wall_normal(view)
        direction = view.camera.direction
        normal = Geom::Vector3d.new(-direction.x,-direction.y,0)
        if normal.length < 1.0e-8
          camera_up = view.camera.respond_to?(:up) ? view.camera.up : Geom::Vector3d.new(0,1,0)
          normal = Geom::Vector3d.new(camera_up.x,camera_up.y,0)
          normal = Geom::Vector3d.new(0,-1,0) if normal.length < 1.0e-8
        end
        normal.normalize!
        normal
      end
      def free_space_pick(view, x, y, anchor = nil, locked_normal = nil)
        anchor ||= free_view_anchor(view)
        ray = view.pickray(x,y)
        normal = locked_normal || view.camera.direction
        point = Geom.intersect_line_plane(ray,[anchor,normal])
        point ||= Geom.intersect_line_plane(ray,[anchor,free_wall_normal(view)])
        point
      rescue StandardError
        nil
      end
      def free_basis_from(point, candidate, view)
        delta = point.vector_to(candidate)
        horizontal = Geom::Vector3d.new(delta.x, delta.y, 0)
        return nil if horizontal.length < 1.0e-8
        u = horizontal.normalize
        v = Geom::Vector3d.new(0,0,1)
        normal = u.cross(v)
        return nil if normal.length < 1.0e-8
        normal.normalize!
        # Local +Z is the face carrying slats / front of backing.
        # Keep it toward the viewer without creating a mirrored transformation.
        if normal.dot(view.camera.direction) > 0
          u.reverse!
          normal = u.cross(v)
          normal.normalize!
        end
        Geom::Transformation.axes(point,u,v,normal)
      rescue StandardError
        nil
      end
      def basis_at(point, view)
        normal = nil
        if @ip.valid? && @ip.respond_to?(:face) && @ip.face
          f = @ip.face
          tr = @ip.transformation
          vertices = f.outer_loop.vertices
          a = vertices[0].position.transform(tr)
          b = vertices[1].position.transform(tr)
          vertices.drop(2).each do |vertex|
            c = vertex.position.transform(tr)
            cross = a.vector_to(b).cross(a.vector_to(c))
            if cross.length > 1.0e-8
              normal = cross.normalize
              break
            end
          end
        end
        normal = free_wall_normal(view) unless normal
        normal.reverse! if normal.dot(view.camera.direction) > 0
        up = Geom::Vector3d.new(0,0,1)
        up = Geom::Vector3d.new(0,1,0) if up.cross(normal).length < 0.001
        u = up.cross(normal).normalize
        v = normal.cross(u).normalize
        Geom::Transformation.axes(point,u,v,normal)
      end
      def inputpoint_transform(ip)
        tr = ip.respond_to?(:transformation) ? ip.transformation : nil
        tr || Geom::Transformation.new
      rescue StandardError
        Geom::Transformation.new
      end

      def endpoint_snap_point(ip, view, x, y)
        return nil unless ip && ip.valid?
        tr = inputpoint_transform(ip)
        candidates = []

        if ip.respond_to?(:vertex) && (vertex = ip.vertex)
          begin
            candidates << vertex.position.transform(tr)
          rescue StandardError
            candidates << ip.position if ip.respond_to?(:position)
          end
        end

        if ip.respond_to?(:edge) && (edge = ip.edge)
          begin
            candidates << edge.start.position.transform(tr)
            candidates << edge.end.position.transform(tr)
          rescue StandardError
            # Ignore malformed edge candidates.
          end
        end

        candidates.compact!
        return nil if candidates.empty?
        candidates.uniq! { |point| [point.x.to_f.round(8), point.y.to_f.round(8), point.z.to_f.round(8)] }

        best = candidates.min_by do |point|
          screen = view.screen_coords(point)
          Math.hypot(screen.x.to_f - x.to_f, screen.y.to_f - y.to_f)
        end
        return nil unless best
        screen = view.screen_coords(best)
        distance = Math.hypot(screen.x.to_f - x.to_f, screen.y.to_f - y.to_f)
        distance <= SNAP_RADIUS ? best : nil
      rescue StandardError
        nil
      end

      def stable_geometry_input_point?(ip, view, x, y)
        !endpoint_snap_point(ip, view, x, y).nil?
      end

      def plane_mode_label(mode = @plane_mode)
        {
          auto: 'TỰ ĐỘNG',
          xz: 'NGANG XZ',
          yz: 'DỌC YZ',
          diag_right: 'CHÉO PHẢI 45°',
          diag_left: 'CHÉO TRÁI 45°',
          xy: 'TRÊN/DƯỚI XY'
        }[mode] || mode.to_s.upcase
      end

      def cycle_plane_mode(view)
        index = PLANE_MODES.index(@plane_mode) || 0
        @plane_mode = PLANE_MODES[(index + 1) % PLANE_MODES.length]
        @free_axis = nil if @plane_mode == :auto

        if @p1 && @raw_p2
          @basis = construction_basis_from(@p1, @raw_p2, view)
          if @basis
            projected = orthogonal_project_to_construction_plane(@raw_p2)
            local = projected.transform(@basis.inverse)
            @p2 = Geom::Point3d.new(local.x, local.y, 0).transform(@basis)
            rebuild
          end
        end
        status
        SlatWall.send_state
        view.invalidate
      rescue StandardError => e
        @error = e.message
        view.invalidate
      end

      def fixed_plane_axes(mode)
        z = Geom::Vector3d.new(0,0,1)
        case mode
        when :xz
          [Geom::Vector3d.new(1,0,0), z]
        when :yz
          [Geom::Vector3d.new(0,1,0), z]
        when :diag_right
          [Geom::Vector3d.new(1,1,0).normalize, z]
        when :diag_left
          [Geom::Vector3d.new(1,-1,0).normalize, z]
        when :xy
          [Geom::Vector3d.new(1,0,0), Geom::Vector3d.new(0,1,0)]
        else
          nil
        end
      end

      def model_axis_for(candidate)
        return @free_axis unless @p1
        delta = @p1.vector_to(candidate)
        dx = delta.x.abs
        dy = delta.y.abs
        return @free_axis if [dx, dy].max < 0.5.mm

        if @free_axis.nil?
          @free_axis = dx >= dy ? :x : :y
        elsif @free_axis == :x
          @free_axis = :y if dy > dx * AXIS_SWITCH_RATIO
        else
          @free_axis = :x if dx > dy * AXIS_SWITCH_RATIO
        end
        @free_axis
      rescue StandardError
        @free_axis
      end

      def lock_first_point(point, view = nil)
        @p1 = Geom::Point3d.new(point.x, point.y, point.z)
        @p1_locked = true
        @p1_plane_normal = if view && view.respond_to?(:camera)
          direction = view.camera.direction
          Geom::Vector3d.new(direction.x, direction.y, direction.z).normalize
        end
        @p2 = nil
        @raw_p2 = nil
        @basis = nil
        @free_axis = nil
        @free_mode = true
        @first_ip.clear if @first_ip.respond_to?(:clear)
        @p1
      end

      def construction_basis_from(point, candidate, _view)
        if @plane_mode && @plane_mode != :auto
          axes = fixed_plane_axes(@plane_mode)
          return nil unless axes
          u, v = axes
          normal = u.cross(v)
          return nil if normal.length < 1.0e-8
          normal.normalize!
          return Geom::Transformation.axes(point,u,v,normal)
        end

        axis_key = model_axis_for(candidate)
        return nil unless axis_key
        u = axis_key == :x ? Geom::Vector3d.new(1,0,0) : Geom::Vector3d.new(0,1,0)
        v = Geom::Vector3d.new(0,0,1)
        normal = u.cross(v)
        normal.normalize!
        Geom::Transformation.axes(point,u,v,normal)
      rescue StandardError
        nil
      end

      def model_axis_basis_from(point, candidate, view)
        construction_basis_from(point, candidate, view)
      end

      def axis_construction_plane
        return nil unless @p1
        if @plane_mode && @plane_mode != :auto
          axes = fixed_plane_axes(@plane_mode)
          return nil unless axes
          normal = axes[0].cross(axes[1])
          return nil if normal.length < 1.0e-8
          normal.normalize!
          return [@p1, normal]
        end
        return nil unless @free_axis
        normal = @free_axis == :x ? Geom::Vector3d.new(0,1,0) : Geom::Vector3d.new(1,0,0)
        [@p1, normal]
      end

      def orthogonal_project_to_construction_plane(point)
        plane = axis_construction_plane
        return point unless plane
        origin, normal = plane
        vector = origin.vector_to(point)
        distance = vector.dot(normal)
        point.offset(normal, -distance)
      rescue StandardError
        point
      end

      def project_p2_to_detected_plane(view, x, y, raw)
        plane = axis_construction_plane
        return raw unless plane
        projected = Geom.intersect_line_plane(view.pickray(x,y), plane)
        return projected if projected
        orthogonal_project_to_construction_plane(raw)
      rescue StandardError
        raw
      end
      def pick(view, x, y)
        if @p1_locked && @p1
          # P1 đã khóa: tuyệt đối không pick lại P1 và không dùng @first_ip làm inference reference.
          @ip.pick(view,x,y)
          raw = endpoint_snap_point(@ip,view,x,y)
          raw ||= free_space_pick(view,x,y,@p1,@p1_plane_normal)
          return nil unless raw
          @raw_p2 = Geom::Point3d.new(raw.x, raw.y, raw.z)

          dynamic_basis = construction_basis_from(@p1,@raw_p2,view)
          @basis = dynamic_basis if dynamic_basis
          return nil unless @basis

          @raw_p2 = project_p2_to_detected_plane(view,x,y,@raw_p2)
          delta = @p1.vector_to(@raw_p2)
          horizontal = delta.dot(@basis.xaxis)
          vertical = delta.z
          Geom::Point3d.new(horizontal,vertical,0).transform(@basis)
        else
          @ip.pick(view,x,y)
          endpoint_snap_point(@ip,view,x,y) || free_space_pick(view,x,y)
        end
      end
      def onMouseMove(_flags,x,y,view)
        @hover = pick(view,x,y)
        if @p1 && @hover
          @p2 = @hover
          rebuild
        end
        snap = stable_geometry_input_point?(@ip,view,x,y)
        axis = @free_axis ? " · TRỤC #{@free_axis.to_s.upcase}" : ''
        if @p1_locked
          view.tooltip = @error || (snap ? "P1 cố định → P2 Endpoint#{axis}" : "P1 cố định → P2 tự do#{axis}")
        else
          view.tooltip = @error || (snap ? 'Chọn P1 Endpoint' : 'Chọn P1 tự do')
        end
        view.invalidate
      rescue StandardError => e
        @error = e.message
        @plan = nil
        @preview_boxes = []
        @preview_mesh = {}
        view.invalidate
      end
      def onLButtonDown(_flags,x,y,view)
        point = pick(view,x,y)
        return UI.beep unless point
        if @p1
          @p2 = point
          rebuild
          commit(view)
        else
          lock_first_point(point, view)
          @drag_start = [x,y]
          status
        end
      rescue StandardError => e
        UI.messagebox("Tạo vách lam: #{e.message}")
      end
      def onLButtonUp(_flags,x,y,view)
        return unless @p1 && @drag_start
        start = @drag_start
        @drag_start = nil
        return if Math.hypot(x-start[0],y-start[1]) < 6

        # If mouse-move already produced a valid preview, create exactly that preview.
        # Do not pick again on button-up because SketchUp inference can change at release time.
        unless @plan && @p2
          candidate = pick(view,x,y)
          candidate ||= @hover
          @p2 = candidate if candidate
          rebuild if @p2
        end
        if @plan && @p2
          commit(view)
        else
          UI.beep
          @error ||= 'Không lấy được P2. Rê chuột để thấy preview rồi thả chuột.'
          view.invalidate
        end
      rescue StandardError => e
        UI.messagebox("Tạo vách lam: #{e.message}")
      end
      def rebuild
        local = @p2.transform(@basis.inverse)
        w,h = local.x.abs.to_f * 25.4, local.y.abs.to_f * 25.4
        @plan = SlatWall.layout(w,h,@options)
        @draw_transform = @basis * Geom::Transformation.translation(Geom::Vector3d.new([local.x,0].min,[local.y,0].min,0))
        @preview_boxes = @plan[:panels].flat_map do |panel|
          items = panel[:slats].each_with_index.map do |box,index|
            polygon = panel[:slat_polygons] && panel[:slat_polygons][index]
            points = if polygon
              SlatWall.slat_prism_points(polygon, box[2], box[5])
            else
              SlatWall.box_points(box)
            end
            [points.map { |p| p.transform(@draw_transform) }, false, !!polygon]
          end
          if panel[:backing]
            items.unshift([SlatWall.box_points(panel[:backing]).map { |p| p.transform(@draw_transform) }, true, false])
          end
          items
        end
        @preview_mesh = {}
        @preview_boxes.each do |points,backing,polygonal|
          mesh = (@preview_mesh[backing] ||= { faces: [], edges: [] })
          faces = polygonal ? PRISM_FACES : BOX_FACES
          edges = polygonal ? PRISM_EDGES : BOX_EDGES
          mesh[:faces].concat(faces.flat_map { |ids| ids.map { |i| points[i] } })
          mesh[:edges].concat(edges.flat_map { |a,b| [points[a],points[b]] })
        end
        @error = nil
      rescue StandardError => e
        @plan = nil
        @preview_boxes = []
        @preview_mesh = {}
        @error = e.message
      end
      def commit(view)
        unless @plan
          UI.messagebox(@error || 'Chưa có vùng tạo hợp lệ.')
          return
        end
        result = SlatWall.create(Sketchup.active_model,@plan,@draw_transform)
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add(result)
        reset
        SlatWall.send_state
        status
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Không tạo được vách lam: #{e.message}")
      end
      def draw(view)
        @ip.draw(view) if @ip.valid?
        view.draw_points([@p1],9,3,Sketchup::Color.new(255,110,20)) if @p1
        view.draw_points([@hover],8,3,Sketchup::Color.new(255,150,40)) if @hover
        @preview_mesh.each do |backing,mesh|
          view.drawing_color = backing ? Sketchup::Color.new(125,160,190,90) : Sketchup::Color.new(221,163,108,155)
          view.draw(GL_QUADS,mesh[:faces])
          view.drawing_color = backing ? Sketchup::Color.new(90,120,145) : Sketchup::Color.new(156,91,40)
          view.line_width = 1
          view.draw(GL_LINES,mesh[:edges])
        end
        if @p1
          axis = @free_axis ? " · TRỤC #{@free_axis.to_s.upcase}" : ''
          orient = {
            'vertical'=>'DỌC','horizontal'=>'NGANG','diag_right'=>'CHÉO PHẢI','diag_left'=>'CHÉO TRÁI'
          }[@options['orientation']]
          text = @error || (@plan && "P1 CỐ ĐỊNH · NAN #{orient}#{axis} · #{@plan[:width].round(1)} × #{@plan[:height].round(1)} mm · #{@plan[:panels].length} cụm VL · #{@plan[:slat_count]} lam")
          view.draw_text([20,35],text.to_s,color: Sketchup::Color.new(155,80,20))
        end
      end
      def getExtents
        box = Geom::BoundingBox.new
        box.add(@p1) if @p1
        @preview_boxes.each { |points,_,_| points.each { |p| box.add(p) } }
        box
      end
    end
  end
end
