# encoding: UTF-8
module TranTuanNoiThat
  module DetailDimensions
    extend self
    # All calculations use SketchUp internal inches. Native dimensions retain model units.
    def marks(values, minimum)
      sorted = values.sort
      return [] if sorted.empty?
      result = [sorted.first]
      sorted[1..-1].each { |v| result << v if v - result.last >= minimum }
      if result.size > 1 && sorted.last - result.last < minimum
        result[-1] = sorted.last
      elsif sorted.last - result.last >= minimum
        result << sorted.last
      end
      result
    end

    def settings
      @settings ||= [120.0, 80.0, 1.0, 'Biên cấu kiện']
    end

    def configure
      result = UI.inputbox(['Khoảng cách DIM (mm)', 'Khoảng cách tầng DIM (mm)',
                            'Đoạn nhỏ nhất (mm)', 'Mốc DIM tự động'], settings,
                           ['', '', '', 'Biên cấu kiện|Đỉnh hình học'], 'Cài đặt DIM TRẦN TUẤN')
      return unless result
      unless result[0..2].all? { |v| v.to_f.finite? && v.to_f > 0 } && result[2].to_f >= 0.1
        UI.messagebox('Khoảng cách phải dương; đoạn nhỏ nhất từ 0,1 mm.')
        return
      end
      @settings = result[0..2].map(&:to_f) + [result[3]]
    end

    def launch(auto = false)
      model = Sketchup.active_model
      if model.active_path
        UI.messagebox('Hãy thoát chế độ sửa Group/Component trước khi tạo DIM.')
        return
      end
      model.select_tool(Tool.new(auto))
    end

    class Tool
      def initialize(auto)
        @auto = auto
        @points = []
        @plane = 0
        @axis = 0
        @state = :pick
        @specs = []
        @ip = Sketchup::InputPoint.new
        @last_ip = Sketchup::InputPoint.new
        @basis = [Geom::Vector3d.new(1,0,0), Geom::Vector3d.new(0,1,0), Geom::Vector3d.new(0,0,1)]
        @origin = Geom::Point3d.new(0,0,0)
      end

      def activate
        @model = Sketchup.active_model
        if @auto
          roots = @model.selection.to_a.select { |e| container?(e) }
          scan(roots) unless roots.empty?
        end
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
        @values = [[], [], []]
        @visited = 0
        @edge_count = 0
        @part_count = 0
        roots.each { |root| walk(root, Geom::Transformation.new, [], 0) }
        raise 'Không tìm thấy cạnh hình học đang hiển thị.' if @values[0].empty?
        @lo = @values.map(&:min)
        @hi = @values.map(&:max)
        @cursor = @lo.map { |v| v - DetailDimensions.settings[0].mm }
        @state = :place
        rebuild
      end

      def walk(instance, parent, ancestors, depth)
        @visited += 1
        raise 'Cụm quá lớn (trên 5.000 cấu kiện hoặc 30 cấp). Hãy chọn từng cụm nhỏ.' if @visited > 5000 || depth > 30
        return if instance.hidden? || !instance.layer.visible?
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
        3.times do |i|
          data = coords.map { |p| p[i] }
          @values[i].concat(DetailDimensions.settings[3] == 'Đỉnh hình học' ? data : [data.min, data.max])
        end
      end

      def axes
        [[0,2,1], [0,1,2], [1,2,0]][@plane]
      end

      def rebuild
        @specs = []
        return unless @state == :place
        gap, tier, minimum = DetailDimensions.settings[0..2].map(&:mm)
        if @auto
          u,v,n = axes
          baseline = @lo.dup
          baseline[n] = @hi[n]
          [u,v].each do |axis|
            offset_axis = axis == u ? v : u
            side = @cursor[offset_axis] < (@lo[offset_axis] + @hi[offset_axis]) / 2 ? -1 : 1
            baseline[offset_axis] = side < 0 ? @lo[offset_axis] : @hi[offset_axis]
            distance = [(@cursor[offset_axis] - baseline[offset_axis]).abs, gap].max
            chain(@values[axis], axis, offset_axis, baseline, side * distance, tier, minimum)
          end
          # The remaining depth receives an overall dimension, outside the selected face.
          base = @lo.dup
          base[u] = @hi[u]
          add_spec(@lo[n], @hi[n], n, u, base, gap + tier * 3, :total)
        else
          u,v,n = axes
          off = ([u,v] - [@axis]).first || v
          base = @points.first.dup
          delta = @cursor[off] - base[off]
          delta = (delta < 0 ? -gap : gap) if delta.abs < gap
          chain(@points.map { |p| p[@axis] }, @axis, off, base, delta, tier, minimum)
        end
        raise 'Trên 500 DIM. Tăng đoạn nhỏ nhất hoặc chọn ít cấu kiện hơn.' if @specs.size > 500
      end

      def chain(values, axis, off, base, distance, tier, minimum)
        list = DetailDimensions.marks(values, minimum)
        return if list.size < 2
        sign = distance < 0 ? -1 : 1
        list.each_cons(2).with_index do |(a,b),i|
          lane = (b-a < tier && i.odd?) ? tier : 0
          add_spec(a,b,axis,off,base,distance + sign * lane,list.size == 2 ? :total : :detail)
        end
        add_spec(list.first,list.last,axis,off,base,distance + sign * tier * 2,:total) if list.size > 2
      end

      def add_spec(a,b,axis,off,base,distance,kind)
        return if b-a < 0.001
        p = base.dup; q = base.dup
        p[axis] = a; q[axis] = b
        @specs << [world(p),world(q),@basis[off].clone.tap { |v| v.length = distance.abs }.tap { |v| v.reverse! if distance < 0 },kind]
      end

      def onMouseMove(flags,x,y,view)
        if @state == :pick && !@auto
          @last_ip.valid? ? @ip.pick(view,x,y,@last_ip) : @ip.pick(view,x,y)
          view.tooltip = @ip.tooltip if @ip.valid?
        elsif @state == :place
          normal = @basis[axes[2]]
          anchor = @auto ? world(@hi) : world(@points.first)
          hit = Geom.intersect_line_plane(view.pickray(x,y), [anchor,normal])
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
        elsif @auto
          ph = view.pick_helper
          ph.do_pick(x,y)
          e = ph.best_picked
          scan([e]) if container?(e)
        else
          onMouseMove(flags,x,y,view)
          return unless @ip.valid? && @ip.degrees_of_freedom < 3
          p = local(@ip.position)
          @points << p unless @points.any? { |q| world(q).distance(world(p)) < 0.1.mm }
          @last_ip.copy!(@ip)
          if @points.size > 1
            @axis = (0..2).max_by { |i| @points.map { |q| q[i] }.max - @points.map { |q| q[i] }.min }
            @plane = @axis == 1 ? 1 : 0
          end
        end
        status
        view.invalidate
      rescue StandardError => e
        fail_tool(e)
      end

      def finish_points
        return if @auto || @points.size < 2
        @state = :place
        @cursor = @points.first.map { |v| v + DetailDimensions.settings[0].mm }
        rebuild
        status
        @model.active_view.invalidate
      end

      def onKeyDown(key,repeat,flags,view)
        return if repeat > 1
        case key
        when 13 then finish_points
        when 9
          @plane = (@plane + 1) % 3
          @axis = axes[0] unless @auto || axes[0..1].include?(@axis)
          rebuild
        when 88,89,90
          unless @auto
            @axis = {88=>0,89=>1,90=>2}[key]
            @plane = @axis == 1 ? 1 : 0 unless axes[0..1].include?(@axis)
            rebuild
          end
        when 8
          unless @auto
            @state = :pick
            @points.pop
            @last_ip.clear
            @specs = []
          end
        end
        status
        view.invalidate
      rescue StandardError => e
        fail_tool(e)
      end

      def getMenu(menu)
        menu.add_item('Kết thúc chọn điểm — đặt DIM') { finish_points } unless @auto
        menu.add_item('Đổi mặt đo (Tab)') { @plane = (@plane + 1) % 3; @axis = axes[0] unless @auto; rebuild; status; @model.active_view.invalidate }
        menu.add_item('Cài đặt DIM…') do
          DetailDimensions.configure
          @auto && @roots ? scan(@roots) : rebuild
          @model.active_view.invalidate
        end
      end

      def commit
        raise 'Chưa có đoạn DIM hợp lệ. Hãy chọn các điểm khác nhau theo trục đo.' if @specs.empty?
        raise 'Cấu kiện đã thay đổi. Hãy chạy lại Auto DIM.' if @auto && @roots.any? { |r| !r.valid? }
        started = false
        begin
          @model.start_operation('TRẦN TUẤN — DIM chi tiết',true)
          started = true
          existing = {}
          @model.entities.each { |e| existing[e.get_attribute('TT_DETAIL_DIM','signature')] = true if e.is_a?(Sketchup::DimensionLinear) }
          @specs.each do |a,b,offset,kind|
            # Deduplicate only this plugin's identical projected dimensions.
            signature = [a.to_a,b.to_a,offset.to_a].flatten.map { |v| (v * 10000).round }.join(',')
            next if existing[signature]
            existing[signature] = true
            dim = @model.entities.add_dimension_linear(a,b,offset)
            dim.set_attribute('TT_DETAIL_DIM','signature',signature)
            dim.set_attribute('TT_DETAIL_DIM','mode',@auto ? 'auto' : 'points')
            dim.layer = @model.layers.add(kind == :total ? 'TT_DIM_TONG' : 'TT_DIM_CHI_TIET')
          end
          @model.commit_operation
          started = false
          @model.select_tool(nil)
        rescue StandardError
          @model.abort_operation if started
          raise
        end
      end

      def draw(view)
        @ip.draw(view) if @state == :pick && @ip.valid? && !@auto
        view.draw_points(@points.map { |p| world(p) },7,1,'orange') unless @points.empty?
        @specs.each do |a,b,o,kind|
          aa = a + o; bb = b + o
          view.drawing_color = kind == :total ? 'blue' : 'darkorange'
          view.line_width = 1
          view.draw(GL_LINES,[a,aa,aa,bb,bb,b])
          middle = Geom.linear_combination(0.5,aa,0.5,bb)
          view.draw_text(view.screen_coords(middle),format('%.1f mm',a.distance(b).to_mm))
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        @points.each { |p| box.add(world(p)) }
        @specs.each { |a,b,o,_| box.add(a,b,a+o,b+o) }
        box
      end

      def status
        plane = ['Đứng XZ','Bằng XY','Cạnh YZ'][@plane]
        text = if @state == :place
          "Rê chuột ra ngoài và bấm để đặt #{@specs.size} DIM | Tab: mặt #{plane} | X/Y/Z: trục đo | Esc: hủy"
        elsif @auto
          'Chọn Group/Component cần quét DIM (hoặc chọn sẵn nhiều cụm trước khi mở công cụ).'
        else
          "Bắt điểm: #{@points.size} điểm | Enter: kết thúc chọn, rê chuột đặt DIM | Backspace: bỏ điểm cuối"
        end
        Sketchup.set_status_text(text)
      end

      def onCancel(reason,view)
        @model.select_tool(nil)
      end

      def deactivate(view)
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
