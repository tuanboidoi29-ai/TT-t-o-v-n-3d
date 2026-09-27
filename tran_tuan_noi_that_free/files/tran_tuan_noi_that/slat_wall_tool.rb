# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module SlatWall
    extend self
    VERSION = '1.9.156'.freeze
    KEY = 'TT_VACH_LAM'.freeze
    MAX_SLATS = 2000
    SNAP_RADIUS = 24.0
    AXIS_SWITCH_RATIO = 1.35
    ABF_CUTTING_TAG = 'ABF_cuttingLines'.freeze
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
      raise 'Hướng lam không hợp lệ.' unless %w[vertical horizontal].include?(o['orientation'])
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

      vertical = o['orientation'] == 'vertical'
      run = vertical ? usable_w : usable_h
      raise 'Rộng lam lớn hơn vùng còn lại sau khi trừ mép.' if run + 1.0e-9 < o['width']
      nominal_gap = o['gap']

      case o['spacing_mode']
      when 'count'
        count = o['count']
        used_slats = count * o['width']
        raise 'Số lượng lam quá lớn so với vùng đặt lam.' if used_slats > run + 1.0e-9
        gap = count > 1 ? (run - used_slats) / (count - 1) : 0.0
        extra = count == 1 ? (run - o['width']) / 2.0 : 0.0
      when 'auto'
        count = [(((run + nominal_gap) / (o['width'] + nominal_gap)) + 1.0e-9).floor, 1].max
        gap = count > 1 ? (run - count * o['width']) / (count - 1) : 0.0
        extra = count == 1 ? (run - o['width']) / 2.0 : 0.0
      else
        count = [(((run + nominal_gap) / (o['width'] + nominal_gap)) + 1.0e-9).floor, 1].max
        gap = nominal_gap
        used = count * o['width'] + (count - 1) * gap
        extra = [run - used, 0.0].max / 2.0
      end

      total = count * cols * rows
      raise "Quá nhiều lam (#{total}). Giảm số lượng hoặc tạo từng vùng nhỏ." if total > MAX_SLATS
      backed = o['mode'] == 'backed'
      z = backed ? o['backing'] - o['recess'] : 0.0
      panels = []
      rows.times do |row|
        cols.times do |col|
          x, y = col * pw, row * ph
          slats = count.times.map do |i|
            if vertical
              [x + o['left'] + extra + i * (o['width'] + gap), y + o['bottom'], z,
               o['width'], usable_h, o['depth']]
            else
              [x + o['left'], y + o['bottom'] + extra + i * (o['width'] + gap), z,
               usable_w, o['width'], o['depth']]
            end
          end
          panels << { x: x, y: y, width: pw, height: ph, slats: slats,
                      backing: backed ? [x, y, 0.0, pw, ph, o['backing']] : nil }
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
        </style><header><h2>TRẦN TUẤN · TẠO VÁCH LAM</h2>Hai góc chéo · SHIFT lam đơn/có lót · TAB dọc/ngang · S mở bảng</header><main>
        <section><label>Chế độ<select id="mode" onchange="visibility()"><option value="single">Vách lam đơn</option><option value="backed">Vách lam có tấm lót</option></select></label>
        <label>Hướng nan<select id="orientation"><option value="vertical">Nan dọc</option><option value="horizontal">Nan ngang</option></select></label>
        #{inputs}
        <label>Kiểu chia<select id="spacing_mode" onchange="visibility()"><option value="manual">Giữ đúng khe + căn giữa</option><option value="auto">Tự động chia đều khe</option><option value="count">Theo số lượng nan</option></select></label>
        <label class="counted">Số lượng nan / cụm<span><input id="count" type="number" min="1" max="#{MAX_SLATS}" step="1"></span></label>
        <small>Chiều dài nan bám đúng vùng kéo. Nếu vượt khổ ván, vùng tự chia thành các cụm VL. Mép trái/phải/trên/dưới áp dụng cho từng cụm. Chế độ số lượng tự tính khe để phủ đều vùng còn lại.</small></section>
        <section class="backed"><label>Độ dày tấm lót<span><input id="backing" type="number" min="0.1" step="0.1"> mm</span></label>
        <label>Hạ âm<span><input id="recess" type="number" min="0" step="0.1"> mm</span></label>
        <label>Bật CNC<input id="cnc" type="checkbox"></label><label>Tên công đoạn CNC<input id="tag" type="text" style="width:240px"></label>
        <small><b>TAM_LOT + biên dạng luôn đi cùng nhau.</b> Hình học tấm chính giữ sạch 6 Face để ABF gắn nhãn; toàn bộ đường CNC nằm trong group chuẩn <b>_ABF_cuttingLines</b> bên trong TAM_LOT. Mặt phải TAM_LOT luôn là mặt trước local +Z, cùng phía với nan. Dày lót mặc định 17,5 mm.</small></section>
        <button onclick="apply()">CẬP NHẬT PREVIEW</button>
        <p id="editBox" class="edit" style="display:none"><button onclick="sketchup.apply_edit()">ÁP DỤNG VÀO VÁCH ĐÃ CHỌN</button></p>
        <p><button onclick="sketchup.repair_abf()">SỬA TẤM LÓT ABF ĐÃ CHỌN</button></p><p id="error"></p>
        <section><canvas id="preview" width="420" height="170"></canvas><div id="info"></div><small>Click P1 → rê thấy preview → click P2, hoặc giữ chuột từ P1 rồi kéo và thả tại P2. Khi thả, plugin tạo đúng preview cuối cùng. ESC bỏ vùng đang vẽ.</small></section></main>
        <script>
        const keys=#{JSON.generate(DEFAULTS.keys)};
        function visibility(){document.querySelectorAll('.backed').forEach(e=>e.style.display=document.getElementById('mode').value==='backed'?'block':'none');document.querySelectorAll('.counted').forEach(e=>e.style.display=document.getElementById('spacing_mode').value==='count'?'flex':'none')}
        function apply(){const o={};keys.forEach(k=>{let e=document.getElementById(k);o[k]=e.type==='checkbox'?e.checked:(e.type==='number'?Number(e.value):e.value)});sketchup.update(JSON.stringify(o))}
        function showError(s){document.getElementById('error').textContent=s}
        function receive(s){keys.forEach(k=>{let e=document.getElementById(k);if(!e)return;if(e.type==='checkbox')e.checked=s.options[k];else e.value=s.options[k]});visibility();document.getElementById('editBox').style.display=s.editing?'block':'none';showError(s.error||'');const c=document.getElementById('preview'),ctx=c.getContext('2d');ctx.clearRect(0,0,c.width,c.height);const d=s.layout;if(!d)return;let scale=Math.min(392/d.width,142/d.height),ox=(420-d.width*scale)/2,oy=(170-d.height*scale)/2;d.panels.forEach(p=>{if(p.backing){ctx.fillStyle='#b1bac2';ctx.fillRect(ox+p.x*scale,oy+p.y*scale,p.width*scale,p.height*scale)}p.slats.forEach(b=>{ctx.fillStyle='#c58e57';ctx.fillRect(ox+b[0]*scale,oy+b[1]*scale,Math.max(1,b[3]*scale),Math.max(1,b[4]*scale))});ctx.strokeStyle='#5c707d';ctx.strokeRect(ox+p.x*scale,oy+p.y*scale,p.width*scale,p.height*scale)});document.getElementById('info').textContent=(s.editing?'Vách đang chọn · ':(s.sample?'Mô phỏng mẫu · ':'Vùng đang vẽ · '))+d.width.toFixed(1)+' × '+d.height.toFixed(1)+' mm · '+(d.orientation==='vertical'?'nan dọc':'nan ngang')+' · '+d.panels.length+' cụm VL · '+d.slat_count+' nan · khe '+d.gap.toFixed(2)+' mm'}
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

    def orient_outward_faces(group)
      bounds = group.definition.bounds
      center = bounds.center
      group.entities.grep(Sketchup::Face).each do |face|
        next unless face.respond_to?(:normal) && face.respond_to?(:reverse!) && face.respond_to?(:bounds)
        outward = center.vector_to(face.bounds.center)
        next if outward.length < 1.0e-9
        face.reverse! if face.normal.dot(outward) < 0
      end
      group
    rescue StandardError
      group
    end

    # TAM_LOT: local +Z luôn là MẶT PHẢI / MẶT TRƯỚC / phía đặt nan.
    def orient_backing_front(backing)
      backing.set_attribute(KEY, 'front_side', 'local_z_positive')
      backing.set_attribute(KEY, 'front_is_right_face', true)
      faces = backing.entities.grep(Sketchup::Face)
      return backing if faces.empty?

      bounds = backing.definition.bounds
      z_min = bounds.min.z.to_f
      z_max = bounds.max.z.to_f
      tolerance = [0.01.mm.to_f, (z_max - z_min).abs * 1.0e-6].max

      faces.each do |face|
        next unless face.respond_to?(:normal) && face.respond_to?(:reverse!) && face.respond_to?(:vertices)
        zs = face.vertices.map { |vertex| vertex.position.z.to_f }
        next if zs.empty?

        if zs.all? { |z| (z - z_max).abs <= tolerance }
          face.reverse! if face.normal.z.to_f < 0
          face.set_attribute(KEY, 'side', 'front') if face.respond_to?(:set_attribute)
        elsif zs.all? { |z| (z - z_min).abs <= tolerance }
          face.reverse! if face.normal.z.to_f > 0
          face.set_attribute(KEY, 'side', 'rear') if face.respond_to?(:set_attribute)
        end
      end

      orient_outward_faces(backing)

      faces.each do |face|
        next unless face.respond_to?(:normal) && face.respond_to?(:reverse!) && face.respond_to?(:vertices)
        zs = face.vertices.map { |vertex| vertex.position.z.to_f }
        if !zs.empty? && zs.all? { |z| (z - z_max).abs <= tolerance }
          face.reverse! if face.normal.z.to_f < 0
        elsif !zs.empty? && zs.all? { |z| (z - z_min).abs <= tolerance }
          face.reverse! if face.normal.z.to_f > 0
        end
      end
      backing
    rescue StandardError
      backing
    end

    def abf_cutting_group?(entity)
      entity.is_a?(Sketchup::Group) &&
        (entity.get_attribute('ABF', 'is-cutting-lines') == true ||
         entity.name.to_s == '_ABF_cuttingLines')
    end

    def abf_auxiliary_group?(entity)
      return true if abf_cutting_group?(entity)
      return false unless entity.is_a?(Sketchup::Group)
      entity.get_attribute('ABF', 'is-label') == true ||
        entity.get_attribute('ABF', 'is-edge-banding-notation') == true ||
        entity.get_attribute('ABF', 'is-intersect') == true
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
      unknown_nested = nested.reject { |entity| abf_auxiliary_group?(entity) }
      direct_cnc = backing.entities.grep(Sketchup::Edge).select do |edge|
        edge.get_attribute(KEY, 'role') == 'cnc_edge'
      end
      cnc_edges = cutting_groups.flat_map do |group|
        group.entities.grep(Sketchup::Edge).select do |edge|
          edge.get_attribute(KEY, 'role') == 'cnc_edge'
        end
      end
      profiles = cnc_edges.group_by { |edge| edge.get_attribute(KEY, 'profile', 0).to_i }
      {
        nested_count: nested.length,
        cutting_group_count: cutting_groups.length,
        unknown_nested_count: unknown_nested.length,
        direct_edge_count: direct_cnc.length,
        edge_count: cnc_edges.length,
        profile_count: profiles.keys.count { |number| number > 0 },
        complete: profiles.all? { |number, edges| number > 0 && edges.length == 4 },
        face_count: backing.entities.grep(Sketchup::Face).length
      }
    end

    def enforce_backing_integrity(backing, expected_profiles = nil)
      summary = backing_profile_summary(backing)
      raise 'TAM_LOT có group con không thuộc chuẩn ABF.' unless summary[:unknown_nested_count] == 0
      raise 'TAM_LOT có nhiều _ABF_cuttingLines.' if summary[:cutting_group_count] > 1
      raise 'Edge CNC đang nằm trực tiếp trên mặt tấm, ABF sẽ khó gắn nhãn.' unless summary[:direct_edge_count] == 0
      raise 'Hình học TAM_LOT phải giữ đúng 6 Face.' unless summary[:face_count] == 6
      raise 'Biên dạng CNC trong TAM_LOT chưa kín đủ 4 cạnh.' unless summary[:complete]

      unless expected_profiles.nil?
        expected = expected_profiles.to_i
        raise "Thiếu biên dạng CNC trong TAM_LOT (#{summary[:profile_count]}/#{expected})." unless summary[:profile_count] == expected
      end

      backing.set_attribute(KEY, 'profiles_embedded', true)
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
      orient_outward_faces(group)
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
      cnc_tag = o['cnc'] && o['mode'] == 'backed' ? ensure_tag(model, ABF_CUTTING_TAG) : nil

      plan[:panels].each_with_index do |panel, index|
        vl = parent.entities.add_group
        vl.name = "VL#{first_number + index}"
        vl.layer = parent_tag
        vl.set_attribute(KEY, 'role', 'panel')
        vl.set_attribute(KEY, 'stock_mm', [o['stock_length'],o['stock_width'],o['stock_thickness']])
        backing = panel[:backing] ? make_box(vl.entities, panel[:backing], "#{vl.name}_TAM_LOT", backmat) : nil

        panel[:slats].each_with_index do |box, slat_index|
          slat = make_box(vl.entities, box, "#{vl.name}_LAM#{slat_index + 1}", wood, slat_tag)
          slat.set_attribute(KEY, 'role', 'slat')
          slat.set_attribute(KEY, 'size_mm', [box[3],box[4],box[5]])
          next unless backing && cnc_tag
          x,y,_z,w,h,_d = box
          front_z = o['backing']
          pts = [[x,y],[x+w,y],[x+w,y+h],[x,y+h]].map { |a,b| Geom::Point3d.new(a.mm,b.mm,front_z.mm) }
          add_cnc_profile(backing, pts, slat_index + 1, cnc_tag, o['recess'])
        end

        if backing
          backing.layer = model.layers[0]
          backing.set_attribute('ABF', 'is-board', true)
          backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'do_day_mm', o['backing'])
          backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'loai', 'VAN')
          backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'chi_tiet', 'TAM_LOT_VACH_LAM')
          backing.set_attribute(KEY, 'role', 'backing')
          backing.set_attribute(KEY, 'size_mm', [panel[:width], panel[:height], o['backing']])
          backing.set_attribute(KEY, 'profile_count', cnc_tag ? panel[:slats].length : 0)
          backing.set_attribute(KEY, 'depth_mm', o['recess'])
          backing.set_attribute(KEY, 'cnc_tag', ABF_CUTTING_TAG) if cnc_tag
          backing.set_attribute(KEY, 'operation_tag', o['tag']) if cnc_tag
          expected_profiles = cnc_tag ? panel[:slats].length : 0
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

    def add_cnc_profile(backing, points, number, tag, depth)
      cutting = ensure_abf_cutting_group(backing)
      actual_tag = ensure_tag(Sketchup.active_model, ABF_CUTTING_TAG)
      cutting.layer = actual_tag
      cutting.set_attribute(KEY, 'operation_tag', tag.respond_to?(:name) ? tag.name.to_s : tag.to_s)
      edges = cutting.entities.add_edges(*(points + [points.first]))
      raise 'Không tạo đủ biên dạng CNC.' unless edges.length == 4
      edges.each do |edge|
        edge.layer = actual_tag
        edge.set_attribute(KEY, 'role', 'cnc_edge')
        edge.set_attribute(KEY, 'profile', number)
        edge.set_attribute(KEY, 'profiles', [number])
        edge.set_attribute(KEY, 'depth_mm', depth)
      end
      edges
    end

    def repair_selected_backings
      model = Sketchup.active_model
      found = []
      walk = lambda do |entities, ancestors|
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next if ancestors.include?(entity.definition)
          raise 'Group đang khóa. Mở khóa trước khi sửa.' if entity.locked?
          if entity.get_attribute(KEY, 'role') == 'backing' ||
             (entity.name.to_s.match?(/\AVL\d+_TAM_LOT\z/) && !entity.get_attribute(KEY, 'profile_count').nil?)
            found << entity
          else
            raise 'Group cha có nhiều bản sao. Make Unique group cha trước khi sửa.' if entity.definition.instances.length > 1
            walk.call(entity.definition.entities, ancestors + [entity.definition])
          end
        end
      end
      walk.call(model.selection.to_a, [])
      raise 'Chọn group vách lam hoặc tấm lót cần sửa trước.' if found.empty?
      raise 'Tấm lót đang khóa.' if found.any?(&:locked?)
      model.start_operation('TT - Sửa tấm lót nhận ABF', true)
      started = true
      found.uniq.each { |backing| repair_backing(backing, model) }
      model.commit_operation
      UI.messagebox("Đã sửa cấu trúc #{found.uniq.length} tấm lót. Chạy lại chức năng đánh nhãn ABF để kiểm tra.")
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

    def repair_backing(backing, model)
      backing.make_unique if backing.definition.instances.length > 1
      default_depth = backing.get_attribute(KEY, 'depth_mm', 0.0)
      shell_box = shell_box_mm(backing)
      records = []

      source_groups = backing.entities.grep(Sketchup::Group).select do |group|
        group.get_attribute(KEY, 'role') == 'cnc_profile' || abf_cutting_group?(group)
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

      # Direct CNC edges from 1.9.150-1.9.155 could have split the front face.
      # Rebuild the physical board shell so ABF sees a clean 6-face board again.
      rebuild_backing_shell(backing, shell_box) unless backing.entities.grep(Sketchup::Face).length == 6

      unless records.empty?
        cutting = ensure_abf_cutting_group(backing)
        tag = ensure_tag(model, ABF_CUTTING_TAG)
        cutting.layer = tag
        cutting.set_attribute('ABF', 'is-cutting-lines', true)
        records.each do |a, b, number, depth|
          edge = cutting.entities.add_line(a, b)
          edge.layer = tag
          edge.set_attribute(KEY, 'role', 'cnc_edge')
          edge.set_attribute(KEY, 'profile', number)
          edge.set_attribute(KEY, 'profiles', [number])
          edge.set_attribute(KEY, 'depth_mm', depth)
        end
      end

      backing.entities.each do |entity|
        next unless entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
        entity.layer = model.layers[0]
      end
      backing.layer = model.layers[0]
      thickness = shell_box[5].round(3)
      backing.set_attribute('ABF', 'is-board', true)
      backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'do_day_mm', thickness)
      backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'loai', 'VAN')
      backing.set_attribute('TRẦN TUẤN NỘI THẤT', 'chi_tiet', 'TAM_LOT_VACH_LAM')
      backing.set_attribute(KEY, 'role', 'backing')
      backing.set_attribute(KEY, 'cnc_tag', ABF_CUTTING_TAG)

      profile_numbers = records.map { |record| record[2].to_i }.select { |number| number > 0 }.uniq
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
      end
      def status
        mode = @options['mode'] == 'backed' ? 'CÓ TẤM LÓT' : 'LAM ĐƠN'
        direction = @options['orientation'] == 'vertical' ? 'NAN DỌC' : 'NAN NGANG'
        action = @edit_target ? 'đang sửa vách đã chọn; chỉnh thông số rồi bấm ÁP DỤNG' : (@p1 ? 'rê tới góc chéo, click hoặc thả để tạo' : 'chọn P1 ổn định rồi kéo P2')
        axis_text = @free_axis ? " · TRỤC #{@free_axis.to_s.upcase}" : ''
        Sketchup.status_text = "TT VÁCH LAM · #{mode} · #{direction}#{axis_text} · #{action} · P1 SNAP 24px · TỰ NHẬN X/Y · SHIFT đổi chế độ · TAB đổi hướng · S mở bảng · ESC hủy"
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
      def onKeyDown(key, repeat, _flags, view)
        if key == 16
          return true if @shift_down || repeat.to_i > 1
          @shift_down = true
          begin
            @options = SlatWall.validate(@options.merge('mode' => @options['mode'] == 'single' ? 'backed' : 'single'))
          rescue StandardError => e
            UI.messagebox(e.message)
            return true
          end
          SlatWall.save_settings(@options)
          rebuild if @p1 && @p2
          SlatWall.send_state
          status
          view.invalidate
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
      def free_space_pick(view, x, y)
        anchor = free_view_anchor(view)
        ray = view.pickray(x,y)
        direction = view.camera.direction
        point = Geom.intersect_line_plane(ray,[anchor,direction])
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
      def geometry_input_point?(ip)
        return false unless ip && ip.valid?
        [:vertex, :edge, :face].any? do |method|
          ip.respond_to?(method) && !ip.public_send(method).nil?
        end
      rescue StandardError
        false
      end

      def stable_geometry_input_point?(ip, view, x, y)
        return false unless geometry_input_point?(ip)
        screen = view.screen_coords(ip.position)
        Math.hypot(screen.x.to_f - x.to_f, screen.y.to_f - y.to_f) <= SNAP_RADIUS
      rescue StandardError
        false
      end

      def model_axis_for(candidate)
        delta = @p1.vector_to(candidate)
        dx = delta.x.abs
        dy = delta.y.abs
        return @free_axis if [dx, dy].max < 0.5.mm

        desired = dx >= dy ? :x : :y
        if @free_axis.nil?
          @free_axis = desired
        elsif desired != @free_axis
          current = @free_axis == :x ? dx : dy
          other = desired == :x ? dx : dy
          @free_axis = desired if other > current * AXIS_SWITCH_RATIO
        end
        @free_axis
      rescue StandardError
        @free_axis
      end

      def model_axis_basis_from(point, candidate, view)
        axis_key = model_axis_for(candidate)
        return nil unless axis_key
        u = axis_key == :x ? Geom::Vector3d.new(1,0,0) : Geom::Vector3d.new(0,1,0)
        v = Geom::Vector3d.new(0,0,1)
        normal = u.cross(v)
        normal.normalize!
        if normal.dot(view.camera.direction) > 0
          u.reverse!
          normal = u.cross(v)
          normal.normalize!
        end
        Geom::Transformation.axes(point,u,v,normal)
      rescue StandardError
        nil
      end
      def pick(view, x, y)
        if @p1 && @free_mode
          @ip.pick(view,x,y)
          point = stable_geometry_input_point?(@ip,view,x,y) ? @ip.position : free_space_pick(view,x,y)
          return nil unless point
          dynamic_basis = model_axis_basis_from(@p1,point,view)
          @basis = dynamic_basis if dynamic_basis
          return nil unless @basis

          delta = @p1.vector_to(point)
          horizontal = delta.dot(@basis.xaxis)
          vertical = delta.z
          Geom::Point3d.new(horizontal,vertical,0).transform(@basis)
        else
          @p1 && @first_ip.valid? ? @ip.pick(view,x,y,@first_ip) : @ip.pick(view,x,y)
          if @p1
            normal = @basis.zaxis
            point = stable_geometry_input_point?(@ip,view,x,y) ? @ip.position : Geom.intersect_line_plane(view.pickray(x,y), [@p1,normal])
            return nil unless point
            local = point.transform(@basis.inverse)
            Geom::Point3d.new(local.x,local.y,0).transform(@basis)
          elsif stable_geometry_input_point?(@ip,view,x,y)
            @ip.position
          else
            free_space_pick(view,x,y)
          end
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
        view.tooltip = @error || (snap ? @ip.tooltip : "P1/P2 ổn định · tự nhận X/Y#{axis}")
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
          @p1 = point
          picked_face = stable_geometry_input_point?(@ip,view,x,y) && @ip.respond_to?(:face) ? @ip.face : nil
          @free_mode = picked_face.nil?
          @free_axis = nil if @free_mode
          @first_ip.copy!(@ip) if !@free_mode && @ip.valid? && @first_ip.respond_to?(:copy!)
          @basis = basis_at(point,view)
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
          boxes = panel[:slats].map { |box| [box,false] }
          boxes.unshift([panel[:backing],true]) if panel[:backing]
          boxes.map { |box,backing| [SlatWall.box_points(box).map { |p| p.transform(@draw_transform) },backing] }
        end
        @preview_mesh = {}
        @preview_boxes.each do |points,backing|
          mesh = (@preview_mesh[backing] ||= { faces: [], edges: [] })
          mesh[:faces].concat(BOX_FACES.flat_map { |ids| ids.map { |i| points[i] } })
          mesh[:edges].concat(BOX_EDGES.flat_map { |a,b| [points[a],points[b]] })
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
          text = @error || (@plan && "#{@plan[:width].round(1)} × #{@plan[:height].round(1)} mm · #{@plan[:panels].length} cụm VL · #{@plan[:slat_count]} lam")
          view.draw_text([20,35],text.to_s,color: Sketchup::Color.new(155,80,20))
        end
      end
      def getExtents
        box = Geom::BoundingBox.new
        box.add(@p1) if @p1
        @preview_boxes.each { |points,_| points.each { |p| box.add(p) } }
        box
      end
    end
  end
end
