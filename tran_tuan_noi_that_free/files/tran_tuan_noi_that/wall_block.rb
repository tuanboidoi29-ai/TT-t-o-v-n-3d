# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  module VeTuongKhoi

    PLUGIN_DIR = File.dirname(__FILE__).freeze
    TAG_NAME   = 'TT_TUONG'.freeze

    DEFAULT_THICKNESS_MM = 110.0
    DEFAULT_HEIGHT_MM    = 2800.0
    SNAP_ANGLE_DEG       = 12.0

    @thickness_mm = DEFAULT_THICKNESS_MM
    @height_mm    = DEFAULT_HEIGHT_MM

    class WallTool
      MODES = [:center, :left, :right].freeze
      MODE_NAMES = {
        :center => 'GIỮA',
        :left   => 'TRÁI',
        :right  => 'PHẢI'
      }.freeze

      def initialize(thickness_mm, height_mm)
        @thickness = thickness_mm.to_f.mm
        @height    = height_mm.to_f.mm
        @mode_index = 0

        @ip  = Sketchup::InputPoint.new
        @ip2 = Sketchup::InputPoint.new

        @p1 = nil
        @preview_p2 = nil

        @last_segment_dir = nil
        @current_dir = nil
      end

      def enableVCB?
        true
      end

      def activate
        update_status
      end

      def deactivate(view)
        view.invalidate if view
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def onCancel(reason, view)
        if @p1
          @p1 = nil
          @preview_p2 = nil
          @current_dir = nil
          @last_segment_dir = nil
          Sketchup.set_status_text(
            'Đã kết thúc chuỗi tường. Click P1 để bắt đầu chuỗi mới.',
            SB_PROMPT
          )
          view.invalidate
        else
          Sketchup.active_model.select_tool(nil)
        end
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 9 # TAB
          @mode_index = (@mode_index + 1) % MODES.length
          update_status
          view.invalidate
          return true
        end
        false
      end

      def onMouseMove(flags, x, y, view)
        if @p1.nil?
          @ip.pick(view, x, y)
          view.tooltip = @ip.tooltip if @ip.valid?
          view.invalidate
          return
        end

        @ip2.pick(view, x, y, @ip)
        return unless @ip2.valid?

        raw = @ip2.position
        raw = Geom::Point3d.new(raw.x, raw.y, @p1.z)

        @preview_p2, @current_dir = orthogonal_point(@p1, raw, @last_segment_dir)

        if @preview_p2
          len = @p1.distance(@preview_p2)
          Sketchup.set_status_text(
            "Dài #{Sketchup.format_length(len)} | Góc #{angle_label} | TAB: #{MODE_NAMES[current_mode]}",
            SB_VCB_LABEL
          )
        end

        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        if @p1.nil?
          @ip.pick(view, x, y)
          return unless @ip.valid?

          p = @ip.position
          @p1 = Geom::Point3d.new(p.x, p.y, p.z)
          @preview_p2 = nil
          @current_dir = nil

          Sketchup.set_status_text(
            'P1 đã khóa. Rê chuột đến P2. Khi gần 0°/90° công cụ sẽ tự khóa vuông góc.',
            SB_PROMPT
          )
          view.invalidate
          return
        end

        @ip2.pick(view, x, y, @ip)
        return unless @ip2.valid?

        raw = @ip2.position
        raw = Geom::Point3d.new(raw.x, raw.y, @p1.z)

        p2, dir = orthogonal_point(@p1, raw, @last_segment_dir)
        return unless p2
        return if @p1.distance(p2) < 1.mm

        create_wall(@p1, p2)

        @last_segment_dir = dir
        @p1 = p2
        @preview_p2 = nil
        @current_dir = nil
        @ip = Sketchup::InputPoint.new(@p1)

        update_status(true)
        view.invalidate
      end

      def onUserText(text, view)
        return if @p1.nil?

        begin
          length = Sketchup.parse_length(text.to_s.strip)
        rescue
          length = nil
        end

        unless length && length > 0 && @current_dir
          UI.beep
          Sketchup.set_status_text(
            'Nhập chiều dài hợp lệ, ví dụ 1200 hoặc 1200mm.',
            SB_PROMPT
          )
          return
        end

        p2 = @p1.offset(@current_dir, length)
        create_wall(@p1, p2)

        @last_segment_dir = @current_dir
        @p1 = p2
        @preview_p2 = nil
        @ip = Sketchup::InputPoint.new(@p1)

        update_status(true)
        view.invalidate
      end

      def draw(view)
        if @p1.nil?
          @ip.draw(view) if @ip.valid?
          return
        end

        view.draw_points(
          [@p1], 10, 3,
          Sketchup::Color.new(255, 80, 80)
        )

        return unless @preview_p2

        pts = wall_corners(@p1, @preview_p2)
        return unless pts

        b0,b1,b2,b3 = pts
        z = Geom::Vector3d.new(0,0,@height)
        t0,t1,t2,t3 = [b0,b1,b2,b3].map { |p| p.offset(z) }

        begin
          view.drawing_color = Sketchup::Color.new(255,175,190,120)
        rescue
          view.drawing_color = Sketchup::Color.new(255,175,190)
        end

        view.draw(GL_QUADS,
          b0,b1,b2,b3,
          t0,t3,t2,t1,
          b0,b1,t1,t0,
          b1,b2,t2,t1,
          b2,b3,t3,t2,
          b3,b0,t0,t3
        )

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(205,55,80)

        view.draw(GL_LINE_LOOP, [b0,b1,b2,b3])
        view.draw(GL_LINE_LOOP, [t0,t1,t2,t3])
        view.draw(GL_LINES, [b0,t0,b1,t1,b2,t2,b3,t3])

        mid = Geom.linear_combination(0.5,@p1,0.5,@preview_p2)
        view.draw_text(
          mid,
          "#{Sketchup.format_length(@p1.distance(@preview_p2))} | #{angle_label}"
        )
      end

      private

      def current_mode
        MODES[@mode_index]
      end

      def angle_label
        return '' unless @current_dir
        x = @current_dir.x.abs
        y = @current_dir.y.abs

        if x > 0.999
          'NGANG X'
        elsif y > 0.999
          'NGANG Y'
        elsif @last_segment_dir &&
              @current_dir.perpendicular?(@last_segment_dir)
          'VUÔNG 90°'
        else
          'TỰ DO'
        end
      end

      # Tự khóa:
      # - Nếu đang nối chuỗi: gần hướng thẳng hoặc vuông góc với đoạn trước -> khóa đúng 0/90.
      # - Nếu là đoạn đầu: gần X/Y model axis -> khóa đúng trục.
      def orthogonal_point(p1, raw, previous_dir)
        dx = raw.x - p1.x
        dy = raw.y - p1.y
        len = Math.sqrt(dx*dx + dy*dy)
        return [nil,nil] if len < 0.001

        raw_dir = Geom::Vector3d.new(dx/len, dy/len, 0)

        candidates = []

        if previous_dir && previous_dir.valid?
          u = previous_dir.clone
          u.length = 1.0
          v = Geom::Vector3d.new(-u.y, u.x, 0)

          candidates << u
          candidates << u.reverse
          candidates << v
          candidates << v.reverse
        else
          candidates << Geom::Vector3d.new(1,0,0)
          candidates << Geom::Vector3d.new(-1,0,0)
          candidates << Geom::Vector3d.new(0,1,0)
          candidates << Geom::Vector3d.new(0,-1,0)
        end

        best = nil
        best_angle = 1.0e9

        candidates.each do |c|
          a = raw_dir.angle_between(c)
          if a < best_angle
            best_angle = a
            best = c
          end
        end

        snap = SNAP_ANGLE_DEG.degrees

        if best && best_angle <= snap
          # Chiếu vector chuột lên hướng khóa để chiều dài không nhảy lung tung.
          vx = raw.x - p1.x
          vy = raw.y - p1.y
          projection = vx*best.x + vy*best.y

          if projection < 0
            best = best.reverse
            projection = -projection
          end

          dir = best.clone
          dir.length = 1.0
          p2 = p1.offset(dir, projection)
          return [p2, dir]
        end

        [raw, raw_dir]
      end

      def update_status(continued=false)
        msg =
          if @p1
            if continued
              'Đã tạo tường. Vẽ tiếp từ điểm cuối; rê gần vuông góc để tự khóa 90°.'
            else
              'Chọn P2. TAB đổi GIỮA/TRÁI/PHẢI.'
            end
          else
            'Click P1 để bắt đầu vẽ tường.'
          end

        Sketchup.set_status_text(msg, SB_PROMPT)
        Sketchup.set_status_text(
          "Dày #{@thickness.to_mm.round(2)} mm | Cao #{@height.to_mm.round(2)} mm | #{MODE_NAMES[current_mode]}",
          SB_VCB_LABEL
        )
      end

      def wall_corners(p1,p2)
        dx = p2.x-p1.x
        dy = p2.y-p1.y
        len = Math.sqrt(dx*dx + dy*dy)
        return nil if len < 0.001

        nx = -dy/len
        ny =  dx/len

        case current_mode
        when :center
          a = -@thickness/2.0
          b =  @thickness/2.0
        when :left
          a = 0.0
          b = @thickness
        when :right
          a = -@thickness
          b = 0.0
        end

        [
          Geom::Point3d.new(p1.x+nx*a,p1.y+ny*a,p1.z),
          Geom::Point3d.new(p2.x+nx*a,p2.y+ny*a,p2.z),
          Geom::Point3d.new(p2.x+nx*b,p2.y+ny*b,p2.z),
          Geom::Point3d.new(p1.x+nx*b,p1.y+ny*b,p1.z)
        ]
      end

      def bbox_overlap?(a,b,tol=1.mm)
        !(a.max.x < b.min.x-tol ||
          a.min.x > b.max.x+tol ||
          a.max.y < b.min.y-tol ||
          a.min.y > b.max.y+tol ||
          a.max.z < b.min.z-tol ||
          a.min.z > b.max.z+tol)
      end

      def create_raw_wall(model,p1,p2)
        group = model.active_entities.add_group
        face = group.entities.add_face(wall_corners(p1,p2))
        raise 'Không tạo được mặt đáy tường.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(@height)

        group.name = "TT Tường #{@thickness.to_mm.round}x#{@height.to_mm.round}"
        tag = model.layers[TAG_NAME] || model.layers.add(TAG_NAME)
        group.layer = tag
        group
      end

      # Hợp nhất với các group TT_TUONG đang giao nhau.
      # SketchUp Pro: dùng Solid Boolean Union -> góc giao sạch, vuông, không đường chéo.
      # Nếu bản SketchUp không có boolean API, vẫn giữ hình học chồng kín đúng vuông.
      def merge_intersections(model,new_group)
        return new_group unless new_group && new_group.valid?

        candidates = model.active_entities.grep(Sketchup::Group).select do |g|
          next false unless g.valid?
          next false if g == new_group
          next false unless g.layer && g.layer.name == TAG_NAME
          bbox_overlap?(g.bounds,new_group.bounds)
        end

        merged = new_group

        candidates.each do |old|
          break unless merged && merged.valid?
          next unless old.valid?

          begin
            can_boolean =
              merged.respond_to?(:union) &&
              merged.respond_to?(:manifold?) &&
              old.respond_to?(:manifold?) &&
              merged.manifold? &&
              old.manifold?

            if can_boolean
              result = old.union(merged)

              if result && result.valid?
                result.name = 'TT Tường liên kết'
                tag = model.layers[TAG_NAME] || model.layers.add(TAG_NAME)
                result.layer = tag
                merged = result
              end
            end
          rescue => e
            puts "TT Wall Union fallback: #{e.message}"
          end
        end

        merged
      end

      def create_wall(p1,p2)
        model = Sketchup.active_model
        model.start_operation('TT - Vẽ Tường Vuông Góc', true)

        begin
          wall = create_raw_wall(model,p1,p2)
          merge_intersections(model,wall)
          model.commit_operation
        rescue => e
          model.abort_operation
          UI.messagebox(
            "TT - Vẽ Tường Khối\n\nLỗi: #{e.message}"
          )
          puts e.message
          puts e.backtrace.join("\n")
        end
      end
    end


    # ============================================================
    # GỘP CÁC GROUP ĐANG CHỌN THÀNH 1 KHỐI
    # - Ưu tiên Solid Boolean Union nếu SketchUp hỗ trợ.
    # - Nếu Union không thực hiện được, vẫn gom toàn bộ hình học
    #   vào 1 Group duy nhất, không để nhiều Group rời bên ngoài.
    # - Toàn bộ thao tác chỉ tạo 1 bước Undo.
    # ============================================================

    def self.merge_selected_groups
      model = Sketchup.active_model
      selection = model.selection

      groups = selection.grep(Sketchup::Group).select(&:valid?)

      if groups.length < 2
        UI.messagebox(
          "TT - Gộp Group\n\n" \
          "Hãy chọn ít nhất 2 Group cần gộp rồi bấm lại nút GỘP."
        )
        return
      end

      model.start_operation('TT - Gộp Group thành 1 khối', true)

      begin
        original_layers = groups.map { |g| g.layer if g.respond_to?(:layer) }.compact
        common_layer = original_layers.uniq.length == 1 ? original_layers.first : nil

        # Danh sách còn tồn tại để xử lý.
        queue = groups.dup
        result = queue.shift
        union_failed = []

        # Ưu tiên Boolean Union: cho ra 1 Solid sạch khi các Group là solid hợp lệ.
        queue.each do |g|
          next unless g && g.valid?
          break unless result && result.valid?

          merged = nil

          begin
            can_union =
              result.respond_to?(:union) &&
              result.respond_to?(:manifold?) &&
              g.respond_to?(:manifold?) &&
              result.manifold? &&
              g.manifold?

            merged = result.union(g) if can_union
          rescue => e
            puts "TT Merge Union fallback: #{e.message}"
            merged = nil
          end

          if merged && merged.valid?
            result = merged
          else
            union_failed << g
          end
        end

        # Nếu Union toàn bộ thành công.
        if union_failed.empty? && result && result.valid?
          result.name = 'TT - Khối đã gộp'
          result.layer = common_layer if common_layer

          selection.clear
          selection.add(result)

          model.commit_operation
          Sketchup.set_status_text(
            'Đã gộp các Group thành 1 khối Solid.',
            SB_PROMPT
          )
          return
        end

        # --------------------------------------------------------
        # FALLBACK:
        # Gom các Group còn lại vào đúng 1 Group ngoài.
        # Hình học của từng Group được đưa vào Group mới và explode
        # 1 cấp để không còn các Group nguồn rời bên ngoài.
        # --------------------------------------------------------

        sources = []
        sources << result if result && result.valid?
        union_failed.each { |g| sources << g if g && g.valid? }
        sources.uniq!

        active_entities = model.active_entities
        merged_group = active_entities.add_group
        merged_group.name = 'TT - Khối đã gộp'

        # Group mới mặc định có transform identity trong active context,
        # do đó dùng trực tiếp transform của từng source để giữ nguyên vị trí.
        sources.each do |g|
          next unless g.valid?

          definition = g.entities.parent
          tr = g.transformation

          temp_instance = merged_group.entities.add_instance(definition, tr)
          temp_instance.explode if temp_instance && temp_instance.valid?
        end

        # Chỉ xóa nguồn sau khi đã sao chép thành công.
        sources.each do |g|
          g.erase! if g && g.valid?
        end

        merged_group.layer = common_layer if common_layer

        selection.clear
        selection.add(merged_group)

        model.commit_operation

        Sketchup.set_status_text(
          'Đã gom các Group thành 1 Group duy nhất. ' \
          'Nếu nguồn không phải Solid giao nhau thì phần hình học bên trong vẫn được giữ.',
          SB_PROMPT
        )

      rescue => e
        model.abort_operation
        UI.messagebox(
          "TT - Gộp Group\n\nLỗi: #{e.message}"
        )
        puts e.message
        puts e.backtrace.join("\n")
      end
    end

    def self.start_tool
      result = UI.inputbox(
        ['Độ dày tường (mm):','Chiều cao tường (mm):'],
        [@thickness_mm,@height_mm],
        'TT - Vẽ Tường Khối'
      )
      return unless result

      t = result[0].to_f
      h = result[1].to_f

      if !t.finite? || !h.finite? || t <= 0 || h <= 0
        UI.messagebox('Độ dày và chiều cao phải lớn hơn 0.')
        return
      end

      @thickness_mm = t
      @height_mm = h

      Sketchup.active_model.select_tool(
        WallTool.new(t,h)
      )
    end

  end
end
