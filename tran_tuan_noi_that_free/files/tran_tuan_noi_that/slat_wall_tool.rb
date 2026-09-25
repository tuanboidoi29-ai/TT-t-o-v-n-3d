# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module SlatWall
    extend self
    VERSION = '1.9.147'.freeze
    KEY = 'TT_VACH_LAM'.freeze
    MAX_SLATS = 2000
    DEFAULTS = {
      'mode' => 'single', 'stock_length' => 2440.0, 'stock_width' => 1220.0,
      'stock_thickness' => 17.5, 'width' => 40.0, 'depth' => 17.5,
      'spacing_mode' => 'auto', 'gap' => 40.0,
      'left' => 0.0, 'right' => 0.0, 'top' => 0.0, 'bottom' => 0.0,
      'backing' => 9.0, 'recess' => 0.0, 'cnc' => false, 'tag' => 'ABF_HANENLAMAM'
    }.freeze

    def validate(raw)
      o = DEFAULTS.merge(raw.select { |k, _| DEFAULTS.key?(k) })
      %w[stock_length stock_width stock_thickness width depth gap left right top bottom backing recess].each do |key|
        o[key] = Float(o[key].to_s.tr(',', '.'))
        raise 'Thông số phải là số hữu hạn.' unless o[key].finite?
        raise 'Kích thước/khoảng cách không được âm.' if o[key] < 0
      end
      %w[stock_length stock_width stock_thickness width depth backing].each do |key|
        raise 'Khổ ván, rộng/dày lam và dày lót phải lớn hơn 0.' unless o[key] >= 0.1
      end
      raise 'Rộng lam lớn hơn rộng khổ ván.' if o['width'] > o['stock_width']
      raise 'Chế độ không hợp lệ.' unless %w[single backed].include?(o['mode'])
      raise 'Chế độ khoảng cách không hợp lệ.' unless %w[manual auto].include?(o['spacing_mode'])
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
      validate(raw)
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
      raise 'Khoảng cách mép làm hết vùng đặt lam.' unless usable_h > 0.1 && usable_w >= o['width']
      nominal_gap = o['gap']
      count = [( (usable_w + nominal_gap) / (o['width'] + nominal_gap) + 1.0e-9).floor, 1].max
      gap = count > 1 && o['spacing_mode'] == 'auto' ? (usable_w - count * o['width']) / (count - 1) : nominal_gap
      used = count * o['width'] + (count - 1) * gap
      extra = [usable_w - used, 0.0].max / 2.0
      raise "Quá nhiều lam (#{count * cols * rows}). Tăng rộng/khe lam hoặc tạo từng vùng nhỏ." if count * cols * rows > MAX_SLATS
      backed = o['mode'] == 'backed'
      z = backed ? o['backing'] - o['recess'] : 0.0
      panels = []
      rows.times do |row|
        cols.times do |col|
          x, y = col * pw, row * ph
          slats = count.times.map do |i|
            [x + o['left'] + extra + i * (o['width'] + gap), y + o['bottom'], z,
             o['width'], usable_h, o['depth']]
          end
          panels << { x: x, y: y, width: pw, height: ph, slats: slats,
                      backing: backed ? [x, y, 0.0, pw, ph, o['backing']] : nil }
        end
      end
      { width: w, height: h, columns: cols, rows: rows, panels: panels,
        slat_count: count * cols * rows, gap: gap, options: o }
    end

    def activate
      Sketchup.active_model.select_tool(Tool.new(settings))
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
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    end

    def send_state
      return unless @dialog && @dialog.visible? && @tool
      @dialog.execute_script("receive(#{JSON.generate(@tool.dialog_state)});")
    end

    def settings_html
      fields = [['stock_length','Dài khổ ván'],['stock_width','Rộng khổ ván'],['stock_thickness','Dày khổ ván'],
                ['width','Chiều rộng lam'],['depth','Chiều dày lam'],['gap','Khe lam / khe dự kiến'],
                ['left','Cách trái'],['right','Cách phải'],['top','Cách trên'],['bottom','Cách dưới']]
      inputs = fields.map { |key, label| "<label>#{label}<span><input id='#{key}' type='number' min='0' step='0.1'> mm</span></label>" }.join
      <<~HTML
        <!doctype html><html lang="vi"><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{font:14px Arial;margin:0;background:#f4f5f7;color:#202a34}header{padding:17px;background:#223d50;color:white}h2{font-size:18px;margin:0 0 6px}main{padding:14px}section{background:white;padding:14px;border-radius:8px;margin-bottom:12px}label{display:flex;justify-content:space-between;align-items:center;margin:8px 0;gap:10px}input[type=number]{width:105px}input,select{padding:7px;border:1px solid #bbc6cc;border-radius:4px}select{max-width:245px}button{width:100%;padding:12px;background:#c4752a;color:white;border:0;border-radius:5px;font-weight:bold;cursor:pointer}small{display:block;color:#647380;line-height:1.5}canvas{width:100%;height:170px;background:#eef1f4;border-radius:5px}#error{color:#b12828;white-space:pre-line}#info{font-size:12px;line-height:1.5;margin:8px 0}.backed{display:none}
        </style><header><h2>TRẦN TUẤN · VÁCH LAM</h2>Hai góc chéo · SHIFT đổi chế độ · TAB cài đặt</header><main>
        <section><label>Chế độ<select id="mode" onchange="visibility()"><option value="single">Vách lam đơn</option><option value="backed">Vách lam có tấm lót</option></select></label>
        #{inputs}
        <label>Khoảng cách<select id="spacing_mode"><option value="manual">Nhập số — giữ đúng khe</option><option value="auto">Tự động — chia đều khe</option></select></label>
        <small>Chiều cao theo vùng kéo. Vượt khổ ván sẽ chia đều thành các cụm VL. Khoảng cách mép áp dụng cho từng cụm. Tự động dùng khe dự kiến để chọn số lam rồi chia đều; nhập số giữ đúng khe và căn giữa phần dư.</small></section>
        <section class="backed"><label>Độ dày tấm lót<span><input id="backing" type="number" min="0.1" step="0.1"> mm</span></label>
        <label>Hạ âm<span><input id="recess" type="number" min="0" step="0.1"> mm</span></label>
        <label>Bật CNC<input id="cnc" type="checkbox"></label><label>Tag tấm lót / CNC<input id="tag" type="text" style="width:240px"></label>
        <small>Hạ âm 0: lam tiếp giáp mặt trước tấm lót. CNC tạo đường biên kín thật trên mặt lót, tương ứng từng lam; lưu độ sâu hạ âm cho mỗi biên dạng.</small></section>
        <button onclick="apply()">CẬP NHẬT PREVIEW</button><p id="error"></p>
        <section><canvas id="preview" width="420" height="170"></canvas><div id="info"></div><small>Hình mô phỏng nhìn chính diện. Click góc thứ hai hoặc thả sau khi kéo để tạo thật. ESC bỏ vùng đang vẽ.</small></section></main>
        <script>
        const keys=#{JSON.generate(DEFAULTS.keys)};
        function visibility(){document.querySelectorAll('.backed').forEach(e=>e.style.display=document.getElementById('mode').value==='backed'?'block':'none')}
        function apply(){const o={};keys.forEach(k=>{let e=document.getElementById(k);o[k]=e.type==='checkbox'?e.checked:(e.type==='number'?Number(e.value):e.value)});sketchup.update(JSON.stringify(o))}
        function showError(s){document.getElementById('error').textContent=s}
        function receive(s){keys.forEach(k=>{let e=document.getElementById(k);if(e.type==='checkbox')e.checked=s.options[k];else e.value=s.options[k]});visibility();showError(s.error||'');const c=document.getElementById('preview'),ctx=c.getContext('2d');ctx.clearRect(0,0,c.width,c.height);const d=s.layout;if(!d)return;let scale=Math.min(392/d.width,142/d.height),ox=(420-d.width*scale)/2,oy=(170-d.height*scale)/2;d.panels.forEach(p=>{if(p.backing){ctx.fillStyle='#b1bac2';ctx.fillRect(ox+p.x*scale,oy+p.y*scale,p.width*scale,p.height*scale)}p.slats.forEach(b=>{ctx.fillStyle='#c58e57';ctx.fillRect(ox+b[0]*scale,oy+b[1]*scale,Math.max(1,b[3]*scale),b[4]*scale)});ctx.strokeStyle='#5c707d';ctx.strokeRect(ox+p.x*scale,oy+p.y*scale,p.width*scale,p.height*scale)});document.getElementById('info').textContent=(s.sample?'Mô phỏng mẫu · ':'Vùng đang vẽ · ')+d.width.toFixed(1)+' × '+d.height.toFixed(1)+' mm · '+d.panels.length+' cụm VL · '+d.slat_count+' lam · khe '+d.gap.toFixed(2)+' mm'}
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

    def make_box(entities, box, name, material, tag = nil)
      group = entities.add_group
      group.name = name
      group.material = material
      group.layer = tag if tag
      pts = box_points(box)
      BOX_FACES.each do |indices|
        face = group.entities.add_face(indices.map { |i| pts[i] })
        raise 'Không tạo được mặt kín cho tấm.' unless face
      end
      group
    end

    def material(model, name, rgb)
      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*rgb)
      m
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

    def create(model, plan, world_transform)
      raise 'Không có preview hợp lệ.' unless plan && plan[:panels].any?
      raise 'Đang chỉnh sửa group bị khóa.' if (model.active_path || []).any?(&:locked?)
      model.start_operation('TT - Tạo vách lam', true)
      started = true
      o = plan[:options]
      n = next_number(model)
      parent = model.active_entities.add_group
      parent.name = "Vách lam #{o['mode'] == 'backed' ? 'có tấm lót' : 'đơn'}"
      parent.transformation = model.edit_transform.inverse * world_transform
      parent.set_attribute(KEY, 'settings', JSON.generate(o))
      parent.set_attribute(KEY, 'size_mm', [plan[:width], plan[:height]])
      wood = material(model, 'TT Vách lam - Gỗ', [190,140,88])
      backmat = material(model, 'TT Vách lam - Tấm lót', [160,166,174])
      cnc_tag = o['cnc'] && o['mode'] == 'backed' ? (model.layers[o['tag']] || model.layers.add(o['tag'])) : nil
      plan[:panels].each_with_index do |panel, index|
        vl = parent.entities.add_group
        vl.name = "VL#{n + index}"
        vl.set_attribute(KEY, 'stock_mm', [o['stock_length'],o['stock_width'],o['stock_thickness']])
        backing = panel[:backing] ? make_box(vl.entities, panel[:backing], "#{vl.name}_TAM_LOT", backmat, cnc_tag) : nil
        panel[:slats].each_with_index do |box, slat_index|
          slat = make_box(vl.entities, box, "#{vl.name}_LAM#{slat_index + 1}", wood)
          slat.set_attribute(KEY, 'size_mm', [box[3],box[4],box[5]])
          next unless backing && cnc_tag
          x,y,_z,w,h,_d = box
          front_z = o['backing']
          pts = [[x,y],[x+w,y],[x+w,y+h],[x,y+h]].map { |a,b| Geom::Point3d.new(a.mm,b.mm,front_z.mm) }
          edges = backing.entities.add_edges(*(pts + [pts.first]))
          raise 'Không tạo đủ biên dạng CNC.' if edges.empty?
          edges.each do |edge|
            edge.layer = cnc_tag
            ids = edge.get_attribute(KEY, 'profiles', [])
            edge.set_attribute(KEY, 'profiles', (ids + [slat_index + 1]).uniq)
            edge.set_attribute(KEY, 'depth_mm', o['recess'])
          end
        end
        if backing
          backing.set_attribute(KEY, 'profile_count', cnc_tag ? panel[:slats].length : 0)
          backing.set_attribute(KEY, 'depth_mm', o['recess'])
          backing.set_attribute(KEY, 'cnc_tag', o['tag']) if cnc_tag
        end
      end
      model.set_attribute(KEY, 'next_vl', n + plan[:panels].length)
      model.commit_operation
      parent
    rescue StandardError
      model.abort_operation if started
      raise
    end

    class Tool
      def initialize(options)
        @options = options
        @ip = Sketchup::InputPoint.new
        @first_ip = Sketchup::InputPoint.new
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
      end
      def status
        mode = @options['mode'] == 'backed' ? 'CÓ TẤM LÓT' : 'LAM ĐƠN'
        Sketchup.status_text = "TT VÁCH LAM · #{mode} · #{@p1 ? 'rê tới góc chéo, click hoặc thả để tạo' : 'chọn góc đầu hoặc kéo trong không gian'} · SHIFT đổi chế độ · TAB cài đặt · ESC hủy"
      end
      def dialog_state
        sample = @plan.nil?
        plan = @plan || SlatWall.layout(@options['stock_width'], @options['stock_length'], @options)
        { options: @options, layout: plan, sample: sample, error: @error }
      rescue StandardError => e
        { options: @options, layout: nil, sample: true, error: e.message }
      end
      def update_settings(options)
        @options = options
        rebuild if @p1 && @p2
        status
        Sketchup.active_model.active_view.invalidate
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
          SlatWall.show_settings(self)
          true
        else
          false
        end
      end
      def onKeyUp(key, _repeat, _flags, _view)
        @shift_down = false if key == 16
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
      def basis_at(point, view)
        normal = nil
        if @ip.valid? && @ip.face
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
        unless normal
          direction = view.camera.direction
          normal = Geom::Vector3d.new(-direction.x,-direction.y,0)
          normal = Geom::Vector3d.new(0,0,direction.z > 0 ? -1 : 1) if normal.length < 1.0e-8
          normal.normalize!
        end
        normal.reverse! if normal.dot(view.camera.direction) > 0
        up = Geom::Vector3d.new(0,0,1)
        up = Geom::Vector3d.new(0,1,0) if up.cross(normal).length < 0.001
        u = up.cross(normal).normalize
        v = normal.cross(u).normalize
        Geom::Transformation.axes(point,u,v,normal)
      end
      def pick(view, x, y)
        @p1 && @first_ip.valid? ? @ip.pick(view,x,y,@first_ip) : @ip.pick(view,x,y)
        if @p1
          normal = @basis.zaxis
          point = @ip.valid? ? @ip.position : Geom.intersect_line_plane(view.pickray(x,y), [@p1,normal])
          return nil unless point
          local = point.transform(@basis.inverse)
          Geom::Point3d.new(local.x,local.y,0).transform(@basis)
        elsif @ip.valid?
          @ip.position
        else
          origin = Geom::Point3d.new(0,0,0)
          plane = basis_at(origin,view)
          Geom.intersect_line_plane(view.pickray(x,y),[origin,plane.zaxis]) ||
            Geom.intersect_line_plane(view.pickray(x,y),[origin,view.camera.direction])
        end
      end
      def onMouseMove(_flags,x,y,view)
        @hover = pick(view,x,y)
        if @p1 && @hover
          @p2 = @hover
          rebuild
        end
        view.tooltip = @error || (@ip.valid? ? @ip.tooltip : 'Vẽ tự do trong không gian')
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
          @first_ip.copy!(@ip) if @ip.valid?
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
        @p2 = pick(view,x,y)
        rebuild if @p2
        commit(view)
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
