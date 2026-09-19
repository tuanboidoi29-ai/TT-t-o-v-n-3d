# encoding: UTF-8
require 'json'
module TranTuanNoiThat
  module DetailDimensions
    extend self
    def settings
      @front_settings ||= [120.0, 80.0, 1.0, 25.0]
    end

    def options
      @dim_options ||= {'horizontal'=>true,'depth'=>true,'height'=>true,'opening'=>true,'total'=>true,
                        'detail_color'=>'#e58b16','total_color'=>'#1976d2','opening_color'=>'#16834a'}
    end

    def validate_options(data)
      raise 'Thiếu lựa chọn DIM.' unless data.is_a?(Hash)
      keys = %w[horizontal depth height opening total]
      raise 'Lựa chọn DIM không hợp lệ.' unless keys.all? { |k| data[k] == true || data[k] == false }
      raise 'Hãy bật ít nhất một loại DIM.' unless keys.any? { |k| data[k] }
      raise 'Màu DIM phải là mã #RRGGBB.' unless %w[detail_color total_color opening_color].all? { |k| data[k].is_a?(String) && data[k].match?(/\A#[0-9a-fA-F]{6}\z/) }
      options.keys.each_with_object({}) { |k,h| h[k] = data[k] }
    end

    def color(kind)
      options[{total: 'total_color',detail: 'detail_color',opening: 'opening_color'}.fetch(kind)]
    end

    def drawing_color(kind)
      hex = color(kind)
      Sketchup::Color.new(hex[1,2].to_i(16),hex[3,2].to_i(16),hex[5,2].to_i(16))
    end

    def marks(values, minimum)
      result = []
      values.sort.each { |v| result << v if result.empty? || v - result.last >= minimum }
      result[-1] = values.max if result.size > 1
      result
    end

    # Sweep horizontal bands through rectangular boards; ignore thin depth panels
    # (backs/doors). Return bounded air gaps, never an unbounded outside interval.
    def openings(parts, tolerance)
      boards = parts.select do |lo,hi|
        size = 3.times.map { |i| hi[i]-lo[i] }
        size.all? { |n| n > tolerance } && size[1] > [size[0],size[2]].min * 1.5
      end
      levels = marks(boards.flat_map { |lo,hi| [lo[2],hi[2]] }, tolerance)
      raise 'Quá nhiều cao độ để nhận lọt lòng. Hãy chọn từng tủ.' if levels.size * boards.size > 2_000_000
      gaps = []
      levels.each_cons(2) do |bottom,top|
        next if top-bottom < tolerance
        z = (bottom+top)/2
        occupied = boards.select { |lo,hi| lo[2] < z && hi[2] > z }.map { |lo,hi| [lo[0],hi[0]] }.sort
        merged = []
        occupied.each do |a,b|
          if !merged.empty? && a <= merged.last[1] + tolerance
            merged.last[1] = [b,merged.last[1]].max
          else
            merged << [a,b]
          end
        end
        merged.each_cons(2) do |left,right|
          a,b = left[1],right[0]
          next if b-a < tolerance
          previous = gaps.reverse.find { |g| (g[0]-a).abs < tolerance && (g[1]-b).abs < tolerance && (g[3]-bottom).abs < tolerance }
          previous ? previous[3] = top : gaps << [a,b,bottom,top]
        end
      end
      gaps
    end

    def launch(*_legacy)
      model = Sketchup.active_model
      if model.active_path
        UI.messagebox('Hãy thoát chế độ sửa Group/Component trước khi DIM.')
        return
      end
      model.select_tool(Tool.new)
    end

    class Tool
      def initialize
        @state = :pick
        @specs = []
        @basis = [Geom::Vector3d.new(1,0,0),Geom::Vector3d.new(0,1,0),Geom::Vector3d.new(0,0,1)]
        @origin = Geom::Point3d.new(0,0,0)
      end

      def activate
        @model = Sketchup.active_model
        @active = true
        roots = @model.selection.to_a.select { |e| container?(e) && !e.get_attribute('TT_FRONT_DIM','source') }
        scan(roots) unless roots.empty?
        status
      rescue StandardError => e
        fail_tool(e)
      end

      def container?(e)
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end

      def local(point)
        v = point - @origin
        @basis.map { |a| v.dot(a) }
      end

      def world(coords)
        p = @origin.clone
        3.times { |i| p = p.offset(@basis[i], coords[i]) }
        p
      end

      def scan(roots)
        roots = roots.select { |e| e.valid? && !e.hidden? && e.layer.visible? }
        raise 'Không có Group/Component đang hiển thị để đo.' if roots.empty?
        @roots = roots
        if roots.size == 1
          tr = roots.first.transformation
          @origin = tr.origin
          @basis = [tr.xaxis, tr.yaxis, tr.zaxis].map(&:normalize)
          raise 'Cấu kiện bị xiên trục (shear), hãy sửa trục trước khi DIM.' if @basis.combination(2).any? { |a,b| a.dot(b).abs > 0.001 }
        end
        @parts = []
        @values = [[], [], []]
        @visited = 0
        @edge_count = 0
        @part_count = 0
        roots.each { |root| walk(root, Geom::Transformation.new, [], 0) }
        raise 'Không tìm thấy cạnh hình học đang hiển thị.' if @values[0].empty?
        @lo = @values.map(&:min)
        @hi = @values.map(&:max)
        @cursor = @lo.map { |v| v - DetailDimensions.settings[0].mm }
        previous = existing_groups.first
        if previous
          stored_options = previous.get_attribute('TT_FRONT_DIM','options')
          if stored_options
            begin
              DetailDimensions.options.replace(DetailDimensions.validate_options(JSON.parse(stored_options)))
            rescue JSON::ParserError, RuntimeError
              # Old or malformed metadata does not prevent rescanning geometry.
            end
          end
        end
        saved = previous && previous.get_attribute('TT_FRONT_DIM','cursor')
        @cursor = saved if saved.is_a?(Array) && saved.size == 3
        eye = local(@model.active_view.camera.eye)
        @front = eye[1] < (@lo[1] + @hi[1]) / 2 ? @lo[1] : @hi[1]
        @openings = DetailDimensions.openings(@parts, 1.mm)
        @state = :place
        rebuild
      end

      def walk(instance, parent, ancestors, depth)
        @visited += 1
        raise 'Cụm quá lớn (trên 5.000 cấu kiện hoặc 30 cấp). Hãy chọn từng cụm nhỏ.' if @visited > 5000 || depth > 30
        return if instance.hidden? || !instance.layer.visible? || instance.get_attribute('TT_FRONT_DIM','source')
        definition = instance.definition
        return if ancestors.include?(definition)
        transform = parent * instance.transformation
        vertices = {}
        definition.entities.each do |e|
          if container?(e)
            walk(e, transform, ancestors + [definition], depth + 1)
          elsif e.is_a?(Sketchup::Edge) && e.layer.visible? && (!e.hidden? || e.soft?)
            @edge_count += 1
            raise 'Quá 150.000 cạnh. Hãy chia nhỏ vùng DIM.' if @edge_count > 150000
            e.vertices.each { |v| vertices[v] = true }
          end
        end
        return if vertices.empty?
        @part_count += 1
        coords = vertices.keys.map { |v| local(v.position.transform(transform)) }
        @parts << [3.times.map { |i| coords.map { |p| p[i] }.min }, 3.times.map { |i| coords.map { |p| p[i] }.max }]
        3.times do |i|
          data = coords.map { |p| p[i] }
          @values[i].concat([data.min, data.max])
        end
      end

      def rebuild
        @specs = []
        return unless @lo
        gap,tier,minimum,height = DetailDimensions.settings.map(&:mm)
        tier = [tier,height*2].max
        [0,2].each do |axis|
          off = axis == 0 ? 2 : 0
          side = @cursor[off] < (@lo[off]+@hi[off])/2 ? -1 : 1
          base = @lo.dup
          base[1] = @front
          base[off] = side < 0 ? @lo[off] : @hi[off]
          distance = [(@cursor[off]-base[off]).abs,gap].max
          list = DetailDimensions.marks(@values[axis],minimum)
          list.each_cons(2).with_index do |(a,b),i|
            next if !DetailDimensions.options[axis == 0 ? 'horizontal' : 'height'] || (list.size == 2 && DetailDimensions.options['total'])
            lane = b-a < height*5 ? i % 3 : 0
            add_spec(a,b,axis,off,base,side*(distance+tier*lane),:detail)
          end
          add_spec(@lo[axis],@hi[axis],axis,off,base,side*(distance+tier*3),:total) if DetailDimensions.options['total']
        end
        base = @hi.dup
        if DetailDimensions.options['depth']
          DetailDimensions.marks(@values[1],minimum).each_cons(2).with_index do |(a,b),i|
            add_spec(a,b,1,0,base,gap+tier*(4+i%3),:detail)
          end
        end
        add_spec(@lo[1],@hi[1],1,0,base,gap+tier*7,:total) if DetailDimensions.options['total']
        @openings.each do |a,b,bottom,top|
          next if b-a < minimum || !DetailDimensions.options['opening']
          base = [a,@front,bottom]
          add_spec(a,b,0,2,base,(top-bottom)/2,:opening)
        end
        raise 'Trên 300 DIM. Tăng đoạn nhỏ nhất hoặc chọn từng tủ.' if @specs.size > 300
      end

      def add_spec(a,b,axis,off,base,distance,kind)
        return if b-a < 0.001
        p = base.dup; q = base.dup
        p[axis] = a; q[axis] = b
        vector = @basis[off].clone
        vector.length = distance.abs
        vector.reverse! if distance < 0
        @specs << [world(p),world(q),vector,kind]
      end

      def onMouseMove(flags,x,y,view)
        if @state == :place
          hit = Geom.intersect_line_plane(view.pickray(x,y),[world([@lo[0],@front,@lo[2]]),@basis[1]])
          if hit
            @cursor = local(hit)
            rebuild
          end
        end
        view.invalidate
      rescue StandardError => e
        fail_tool(e)
      end

      def onLButtonDown(flags,x,y,view)
        if @state == :place
          commit
          @state = :placed
        elsif @state == :pick
          ph = view.pick_helper
          ph.do_pick(x,y)
          entity = ph.best_picked
          scan([entity]) if container?(entity) && !entity.get_attribute('TT_FRONT_DIM','source')
        end
        status
        view.invalidate
      rescue StandardError => e
        fail_tool(e)
      end

      def onKeyDown(key,repeat,flags,view)
        configure if key == 9 && repeat <= 1
      end

      def getMenu(menu)
        menu.add_item('Cài đặt DIM (Tab)') { configure }
      end

      def configure
        return @dialog.bring_to_front if @dialog && @dialog.visible?
        @dialog = UI::HtmlDialog.new(dialog_title: 'DIM tự động mặt trước',preferences_key: 'TTFrontDim198',width: 460,height: 780,resizable: true)
        values = DetailDimensions.settings
        choices = {'horizontal'=>'DIM ngang — rộng X','depth'=>'DIM dọc — sâu Y','height'=>'DIM cao — đứng Z','opening'=>'DIM lọt lòng — rộng ngang','total'=>'DIM tổng — rộng / cao / sâu'}
        checks = choices.map { |key,title| "<label>#{title}<input type=\"checkbox\" id=\"enable_#{key}\" #{DetailDimensions.options[key] ? 'checked' : ''}></label>" }.join
        colors = {'detail_color'=>'Màu DIM chi tiết','total_color'=>'Màu DIM tổng','opening_color'=>'Màu DIM lọt lòng'}.map { |key,title| "<label>#{title}<input type=\"color\" id=\"#{key}\" value=\"#{DetailDimensions.options[key]}\"></label>" }.join
        @dialog.set_html(<<~HTML)
          <!doctype html><html lang="vi"><meta charset="utf-8"><style>
          body{font:14px Arial;margin:24px;color:#17324b;background:#f5f7fa}h2{font-size:20px}label{display:flex;justify-content:space-between;align-items:center;margin:16px 0}input{width:90px;padding:8px;border:1px solid #bbc8d4;border-radius:5px}button{width:100%;padding:12px;background:#1675bd;color:white;border:0;border-radius:6px;font-weight:bold}p{line-height:1.5}#message{color:#176c39}
          </style><h2>DIM mặt trước</h2><p>Đo ngang · đo cao · tổng rộng/cao/sâu · rộng lọt lòng</p>
          <form id="form">#{checks}<hr>#{colors}<hr>
          <label>Cách mép (mm)<input id="gap" type="number" min="1" max="10000" step="any" value="#{values[0]}" required></label>
          <label>Cách tầng DIM (mm)<input id="tier" type="number" min="1" max="10000" step="any" value="#{values[1]}" required></label>
          <label>Đoạn nhỏ nhất (mm)<input id="minimum" type="number" min="0.1" max="1000" step="any" value="#{values[2]}" required></label>
          <label>Cao chữ DIM (mm)<input id="height" type="number" min="1" max="200" step="any" value="#{values[3]}" required></label>
          <button id="update">Cập nhật</button></form><p id="message">Áp dụng cho bản xem trước hoặc bộ DIM vừa đặt.</p>
          <script>document.getElementById('form').addEventListener('submit',function(e){e.preventDefault();document.getElementById('update').disabled=true;const options={};['horizontal','depth','height','opening','total'].forEach(id=>options[id]=document.getElementById('enable_'+id).checked);['detail_color','total_color','opening_color'].forEach(id=>options[id]=document.getElementById(id).value);sketchup.update(JSON.stringify({values:['gap','tier','minimum','height'].map(id=>Number(document.getElementById(id).value)),options:options}));});function result(message){document.getElementById('message').textContent=message;document.getElementById('update').disabled=false;}</script></html>
        HTML
        @dialog.add_action_callback('update') do |_context,payload|
          before = DetailDimensions.settings.dup
          old_options = DetailDimensions.options.dup
          begin
            raise 'Hãy mở lại công cụ trong mô hình hiện tại.' unless @active && Sketchup.active_model == @model && !@model.active_path
            payload = JSON.parse(payload)
            raise 'Dữ liệu không hợp lệ.' unless payload.is_a?(Hash)
            new_options = DetailDimensions.validate_options(payload['options'])
            data = payload['values']
            limits = [[1,10000],[1,10000],[0.1,1000],[1,200]]
            raise 'Thông số không hợp lệ.' unless data.is_a?(Array) && data.size == 4 && data.each_with_index.all? { |v,i| v.is_a?(Numeric) && v.finite? && v >= limits[i][0] && v <= limits[i][1] }
            DetailDimensions.settings.replace(data)
            DetailDimensions.options.replace(new_options)
            rebuild
            if @state == :placed || (@roots && !existing_groups.empty?)
              commit
              @state = :placed
            end
            @model.active_view.invalidate
            status
            @dialog.execute_script("result(#{JSON.generate('Đã cập nhật loại DIM, màu sắc và cỡ chữ.')})")
          rescue StandardError => e
            DetailDimensions.settings.replace(before)
            DetailDimensions.options.replace(old_options)
            rebuild
            @dialog.execute_script("result(#{JSON.generate('Không cập nhật: '+e.message)})")
          end
        end
        @dialog.show
      end

      def label(a,b,kind)
        value = format('%.1f',a.distance(b).to_mm).sub(/\.0$/, '')
        kind == :opening ? "LL #{value}" : value
      end

      def existing_groups
        source = @roots.map(&:persistent_id).sort.join(',')
        @model.entities.select { |e| container?(e) && e.get_attribute('TT_FRONT_DIM','source') == source }
      end

      def commit
        raise 'Chưa có kích thước để đặt.' if @specs.empty?
        raise 'Cấu kiện đã bị xóa. Hãy chạy lại DIM.' if @roots.any? { |r| !r.valid? }
        source = @roots.map(&:persistent_id).sort.join(',')
        started = false
        begin
          @model.start_operation('TRẦN TUẤN — DIM mặt trước',true)
          started = true
          old = existing_groups
          raise 'Bộ DIM cũ đang khóa. Hãy mở khóa trước khi cập nhật.' if old.any?(&:locked?)
          group = @model.entities.add_group
          group.name = 'TT DIM — Mặt trước'
          group.set_attribute('TT_FRONT_DIM','source',source)
          group.set_attribute('TT_FRONT_DIM','settings',DetailDimensions.settings)
          group.set_attribute('TT_FRONT_DIM','cursor',@cursor)
          group.set_attribute('TT_FRONT_DIM','options',JSON.generate(DetailDimensions.options))
          @specs.each { |spec| render_dimension(group.entities,*spec) }
          @model.entities.erase_entities(old) unless old.empty?
          @model.commit_operation
          started = false
        rescue StandardError
          @model.abort_operation if started
          raise
        end
      end

      def render_dimension(entities,a,b,offset,kind)
        group = entities.add_group
        group.name = kind == :opening ? 'Rộng lọt lòng' : (kind == :total ? 'DIM tổng' : 'DIM chi tiết')
        group.layer = @model.layers.add({opening: 'TT_DIM_LOT_LONG',total: 'TT_DIM_TONG',detail: 'TT_DIM_CHI_TIET'}[kind])
        color = DetailDimensions.drawing_color(kind)
        aa = a+offset; bb = b+offset
        along = (b-a).normalize
        across = offset.normalize
        # Consistent above-line text, independent of which side receives the offset.
        across.reverse! if across.dot(@basis[2]) < -0.001 || across.dot(@basis[0]) < -0.001
        height = DetailDimensions.settings[3].mm
        en = group.entities
        normal = along.cross(across)
        width = [height*0.035,0.5.mm].max
        colored_line(en,a,aa.offset(offset.normalize,height*0.4),normal,width,color)
        colored_line(en,b,bb.offset(offset.normalize,height*0.4),normal,width,color)
        colored_line(en,aa,bb,normal,width,color)
        tick = height*0.25
        [aa,bb].each { |p| colored_line(en,p.offset(along,-tick).offset(across,-tick),p.offset(along,tick).offset(across,tick),normal,width,color) }
        text = en.add_group
        raise 'Không tạo được chữ DIM.' unless text.entities.add_3d_text(label(a,b,kind),TextAlignLeft,'Arial',false,false,height,0.1.mm,0,true,0)
        text.entities.each do |entity|
          if entity.is_a?(Sketchup::Face)
            entity.material = color
            entity.back_material = color
          elsif entity.is_a?(Sketchup::Edge)
            entity.hidden = true
          end
        end
        bounds = text.bounds
        midpoint = Geom.linear_combination(0.5,aa,0.5,bb)
        along.reverse! if along.cross(across).dot(@model.active_view.camera.eye - midpoint) < 0
        origin = midpoint.offset(along,-bounds.center.x).offset(across,height*0.25-bounds.min.y)
        text.transformation = Geom::Transformation.axes(origin,along,across,along.cross(across))
      end

      # Thin filled ribbons show their own color without changing the model's edge style.
      def colored_line(entities,a,b,normal,width,color)
        return if a.distance(b) < 0.001
        side = normal.cross(b-a).normalize
        part = entities.add_group
        face = part.entities.add_face(a.offset(side,width/2),b.offset(side,width/2),b.offset(side,-width/2),a.offset(side,-width/2))
        raise 'Không tạo được nét DIM màu.' unless face
        face.material = color
        face.back_material = color
        face.edges.each { |edge| edge.hidden = true }
      end

      def draw(view)
        return if @state == :placed
        @specs.each do |a,b,o,kind|
          aa = a+o; bb = b+o
          view.drawing_color = DetailDimensions.drawing_color(kind)
          view.line_width = 1
          view.draw(GL_LINES,[a,aa,aa,bb,bb,b])
          middle = Geom.linear_combination(0.5,aa,0.5,bb)
          px = DetailDimensions.settings[3].mm / view.pixels_to_model(1,middle)
          view.draw_text(view.screen_coords(middle),label(a,b,kind),size: [[px,6].max,120].min)
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        @specs.each { |a,b,o,_| box.add(a,b,a+o,b+o) }
        box
      end

      def status
        message = case @state
        when :pick then 'Chọn cụm tủ để DIM mặt trước | Tab: cài đặt cỡ chữ | Esc: thoát'
        when :place then "Rê ra ngoài và bấm đặt #{@specs.size} DIM | #{@openings.size} khoảng lọt lòng | Tab: cài đặt"
        else 'Đã đặt DIM | Tab: cài đặt → Cập nhật áp dụng ngay | Esc: kết thúc'
        end
        Sketchup.set_status_text(message)
      end

      def onCancel(reason,view)
        @model.select_tool(nil)
      end

      def deactivate(view)
        @active = false
        @dialog.close if @dialog
        Sketchup.set_status_text('')
        view.invalidate
      end

      def fail_tool(error)
        UI.messagebox("DIM: #{error.message}")
        @model.select_tool(nil) if @model
      end
    end
  end
end
