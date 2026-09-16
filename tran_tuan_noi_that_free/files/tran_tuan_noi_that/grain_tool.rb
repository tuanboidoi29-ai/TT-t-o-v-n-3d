# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN
# Tích hợp từ TT Grain PRO V3.2.0 SAFE GROUP / FLEX MATERIAL.
# Không explode/regroup, không đổi transform; Component chỉ make_unique khi áp dụng.

module TranTuanNoiThat
  module Grain
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.2.0'.freeze
    PREF = 'TranTuanNoiThat_Grain'.freeze
    DICT = 'TT_GRAIN'.freeze
    ABF  = 'TT_ABF_GRAIN'.freeze
    FACE_DICT = 'TT_GRAIN_FACE'.freeze
    TAB_KEY = 9
    ENTER_KEY = 13
    ALT_MASK = 8
    CTRL_MASK = defined?(COPY_MODIFIER_MASK) ? COPY_MODIFIER_MASK : 2
    AXES = [X_AXIS, Y_AXIS, Z_AXIS].freeze
    AXIS_NAMES = %w[X Y Z].freeze

    @dialog = nil
    @active_tool = nil

    def pref_number(key, fallback)
      v = Sketchup.read_default(PREF, key, fallback).to_f
      v > 0 ? v : fallback
    end

    def board_length_mm; pref_number('board_length_mm', 2440.0); end
    def board_width_mm; pref_number('board_width_mm', 1220.0); end
    def max_thickness_mm; pref_number('max_thickness_mm', 80.0); end
    def lock_mode
      v = Sketchup.read_default(PREF, 'lock_mode', 'auto').to_s
      %w[auto length width].include?(v) ? v : 'auto'
    end

    def save_settings(l, w, t, mode)
      l = [[l.to_f, 1.0].max, 10000.0].min
      w = [[w.to_f, 1.0].max, 10000.0].min
      t = [[t.to_f, 1.0].max, 500.0].min
      mode = %w[auto length width].include?(mode.to_s) ? mode.to_s : 'auto'
      Sketchup.write_default(PREF, 'board_length_mm', l)
      Sketchup.write_default(PREF, 'board_width_mm', w)
      Sketchup.write_default(PREF, 'max_thickness_mm', t)
      Sketchup.write_default(PREF, 'lock_mode', mode)
      @active_tool.receive_settings(l, w, t, mode) if @active_tool
    end

    def open_settings(tool = nil)
      @active_tool = tool if tool
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - KHỔ VÁN / HƯỚNG VÂN',
        preferences_key: 'TranTuanNoiThat.Grain',
        scrollable: false, resizable: false, width: 440, height: 520,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      l, w, t, m = board_length_mm, board_width_mm, max_thickness_mm, lock_mode
      @dialog.set_html(<<~HTML)
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;padding:20px;background:#151515;color:#f5f5f5;font:14px Arial}h2{margin:0 0 5px;color:#ff8a22}.sub{color:#aaa;margin-bottom:16px}.card{background:#222;border:1px solid #444;border-radius:9px;padding:14px;margin-bottom:12px}label{display:block;margin:10px 0 5px;font-weight:bold}input,select{width:100%;padding:10px;border:1px solid #555;border-radius:7px;background:#111;color:white}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.preset{background:#343434;color:#fff;border:0;padding:9px;border-radius:6px;cursor:pointer}.save{width:100%;padding:12px;border:0;border-radius:8px;background:#f47b20;color:#fff;font-weight:bold;cursor:pointer}.note{font-size:12px;color:#bbb;line-height:1.5}</style></head><body>
        <h2>XOAY VÂN VÁN</h2><div class="sub">Khổ tấm gốc dùng để AUTO nhận hướng vân.</div>
        <div class="card"><label>Chiều dài / hướng vân (mm)</label><input id="l" type="number" value="#{l}"><label>Chiều rộng (mm)</label><input id="w" type="number" value="#{w}"><label>Dày tối đa nhận ván (mm)</label><input id="t" type="number" value="#{t}"><div class="row" style="margin-top:10px"><button class="preset" onclick="p(2440,1220)">2440×1220</button><button class="preset" onclick="p(2800,1220)">2800×1220</button></div></div>
        <div class="card"><label>Luật AUTO</label><select id="m"><option value="auto">Theo khổ + cạnh hợp lý</option><option value="length">Khóa theo chiều DÀI chi tiết</option><option value="width">Khóa theo chiều RỘNG chi tiết</option></select></div>
        <button class="save" onclick="s()">LƯU THÔNG SỐ</button><div class="note" style="margin-top:12px">TAB: mở bảng này · TAB TAB: AUTO ↔ TỰ DO 4 HƯỚNG · Alt+Click: đảo 90° · Ctrl+Click: khóa/mở khóa.</div>
        <script>m.value=#{m.inspect};function p(a,b){l.value=a;w.value=b}function s(){sketchup.save(Number(l.value),Number(w.value),Number(t.value),m.value)}</script></body></html>
      HTML
      @dialog.add_action_callback('save') do |_ctx, ll, ww, tt, mm|
        save_settings(ll, ww, tt, mm)
        @dialog.close
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    end

    def activate
      tool = Tool.new
      @active_tool = tool
      Sketchup.active_model.select_tool(tool)
    end

    class Tool
      def initialize
        @model = Sketchup.active_model
        @view = @model.active_view
        @target = nil
        @target_tr = Geom::Transformation.new
        @face = nil
        @path = nil
        @material = nil
        @analysis = nil
        @free = false
        @free_axis = nil
        @free_sign = 1
        @last_tab = 0.0
        @tab_serial = 0
        @scan = nil
        receive_settings(Grain.board_length_mm, Grain.board_width_mm, Grain.max_thickness_mm, Grain.lock_mode)
      end

      def activate
        Grain.instance_variable_set(:@active_tool, self)
        Sketchup.vcb_label = 'Khổ / Vân'
        update_status
      end

      def deactivate(view); view.invalidate if view; end
      def resume(view); Grain.instance_variable_set(:@active_tool, self); update_status; view.invalidate; end

      def receive_settings(l, w, t, mode)
        @sheet_l, @sheet_w, @max_t = l.to_f, w.to_f, t.to_f
        @lock_mode = %w[auto length width].include?(mode.to_s) ? mode.to_s : 'auto'
        analyze_current
        @view.invalidate if @view
      end

      def onCancel(_reason, view)
        if @scan
          @scan = nil
          view.invalidate
        else
          @model.select_tool(nil)
        end
      end

      def onKeyDown(key, _repeat, flags, view)
        if @scan && key == ENTER_KEY
          apply_scan((flags & ALT_MASK) != 0)
          return
        end
        return unless key == TAB_KEY
        now = Time.now.to_f
        if @last_tab > 0 && now - @last_tab <= 0.36
          @tab_serial += 1
          @last_tab = 0
          @free = !@free
          @free_axis = nil
          analyze_current
          update_status
          view.invalidate
          return
        end
        @last_tab = now
        @tab_serial += 1
        serial = @tab_serial
        UI.start_timer(0.36, false) do
          if @tab_serial == serial && @last_tab > 0
            @last_tab = 0
            Grain.open_settings(self)
          end
        end
      rescue StandardError => e
        puts "[TT Grain key] #{e.class}: #{e.message}"
      end

      def onMouseMove(_flags, x, y, view)
        return if @scan
        pick(view, x, y)
        analyze_current
        choose_free(x, y, view) if @free
        update_status
        view.invalidate
      rescue StandardError => e
        clear_pick
        Sketchup.set_status_text("XOAY VÂN: #{e.message}", SB_PROMPT)
      end

      def onLButtonDown(flags, x, y, view)
        return if @scan
        pick(view, x, y)
        analyze_current
        return UI.beep unless @target && @analysis && @material
        return UI.beep unless textured?(@material)
        if (flags & CTRL_MASK) != 0
          toggle_lock
          return
        end
        if locked?
          UI.beep
          Sketchup.set_status_text('Vân đang KHÓA. Ctrl+Click để mở khóa.', SB_PROMPT)
          return
        end
        a = @analysis.dup
        a = swapped(a) if (flags & ALT_MASK) != 0 && !@free
        if @free && @free_axis
          a = force_axis(a, @free_axis, @free_sign)
        end
        apply_target(@target, @target_tr, @material, a, @free ? 'free' : ((flags & ALT_MASK) != 0 ? 'manual_swap' : 'auto'))
        @analysis = a
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Xoay Vân Ván:\n#{e.message}")
      end

      def onRButtonDown(_flags, _x, _y, view)
        @scan = build_scan
        if @scan.empty?
          @scan = nil
          UI.beep
          Sketchup.set_status_text('Không tìm thấy tấm có texture để quét.', SB_PROMPT)
        else
          Sketchup.set_status_text("PREVIEW #{@scan.length} tấm · ENTER áp dụng · ESC hủy", SB_PROMPT)
        end
        view.invalidate
        true
      end

      def getMenu(_menu); nil; end

      def draw(view)
        if @scan
          draw_scan(view)
          return
        end
        return unless @target && @analysis
        draw_target_box(view)
        draw_grain_arrow(view, @analysis)
        draw_free_arrows(view) if @free
        draw_label(view)
      rescue StandardError => e
        puts "[TT Grain draw] #{e.class}: #{e.message}"
      end

      private

      def container?(e); e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance); end
      def definition(e); e.respond_to?(:definition) ? e.definition : nil; end
      def entities(e); d = definition(e); d ? d.entities : nil; end
      def bounds(e); d = definition(e); d ? d.bounds : nil; end
      def valid_target?(e); e && e.valid? && container?(e); rescue false; end

      def pick(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        found = nil
        ph.count.times do |i|
          path = ph.path_at(i)
          next unless path
          face = path.reverse.find { |e| e.is_a?(Sketchup::Face) }
          next unless face
          found = [path, face]
          break
        end
        return clear_pick unless found
        @path, @face = found
        @target, @target_tr = board_from_path(@path)
        return clear_pick unless @target
        sync_inherited_material(@target)
        @material = effective_material(@face, @path)
      end

      def board_from_path(path)
        list = []
        tr = Geom::Transformation.new
        path.each do |e|
          next unless container?(e)
          tr = tr * e.transformation
          list << [e, tr.clone]
        end
        list.reverse_each do |e, etr|
          a = analyze(e, etr)
          next unless a
          sizes = a[:sizes_mm].sort
          return [e, etr] if sizes[0] >= 0.1 && sizes[0] <= @max_t && sizes[1] >= 1.0 && sizes[2] >= 1.0
        end
        list.last || [nil, Geom::Transformation.new]
      end

      def effective_material(face, path)
        return face.material if face && face.material
        return face.back_material if face && face.back_material
        path.select { |e| container?(e) }.reverse_each { |e| return e.material if e.material }
        nil
      end

      def textured?(m); m && m.texture; rescue false; end

      def analyze_current
        @analysis = analyze(@target, @target_tr)
        return unless @analysis
        if @free && @free_axis
          @analysis = force_axis(@analysis, @free_axis, @free_sign)
        elsif @lock_mode == 'auto'
          @analysis = part_name_rule(@target, @analysis, @target_tr)
        end
      end

      def analyze(target, tr)
        return nil unless valid_target?(target)
        b = bounds(target)
        return nil unless b && b.valid?
        scales = [tr.xaxis.length, tr.yaxis.length, tr.zaxis.length]
        local = [b.width.to_f, b.height.to_f, b.depth.to_f]
        sizes = local.each_with_index.map { |v, i| v * scales[i] * 25.4 }
        indexed = sizes.each_with_index.sort_by(&:first)
        thickness_axis = indexed[0][1]
        plane = [0, 1, 2] - [thickness_axis]
        a, c = plane
        choice = choose(a, sizes[a], c, sizes[c])
        {bounds:b, local_sizes:local, sizes_mm:sizes, thickness_axis:thickness_axis, plane_axes:plane,
         grain_axis:choice[0], cross_axis:choice[1], grain_size_mm:choice[2], cross_size_mm:choice[3], fits_sheet:choice[4], grain_sign:1}
      rescue StandardError
        nil
      end

      def choose(a, sa, b, sb)
        if @lock_mode == 'length'
          return sa >= sb ? [a,b,sa,sb,sa<=@sheet_l+0.5 && sb<=@sheet_w+0.5] : [b,a,sb,sa,sb<=@sheet_l+0.5 && sa<=@sheet_w+0.5]
        elsif @lock_mode == 'width'
          return sa <= sb ? [a,b,sa,sb,sa<=@sheet_l+0.5 && sb<=@sheet_w+0.5] : [b,a,sb,sa,sb<=@sheet_l+0.5 && sa<=@sheet_w+0.5]
        end
        fit_a = sa <= @sheet_l+0.5 && sb <= @sheet_w+0.5
        fit_b = sb <= @sheet_l+0.5 && sa <= @sheet_w+0.5
        return [a,b,sa,sb,true] if fit_a && !fit_b
        return [b,a,sb,sa,true] if fit_b && !fit_a
        return sa >= sb ? [a,b,sa,sb,fit_a] : [b,a,sb,sa,fit_b] if fit_a || fit_b
        oa = [sa-@sheet_l,0].max + [sb-@sheet_w,0].max
        ob = [sb-@sheet_l,0].max + [sa-@sheet_w,0].max
        oa <= ob ? [a,b,sa,sb,false] : [b,a,sb,sa,false]
      end

      def part_name_rule(target, a, tr)
        name = ((target.name.to_s rescue '') + ' ' + (definition(target).name.to_s rescue '')).downcase
        name = name.unicode_normalize(:nfkd).gsub(/\p{Mn}/,'') rescue name
        name = name.tr('đ','d')
        if name =~ /(canh|door|hoi|side|vach|panel dung|mat canh)/
          axis = a[:plane_axes].max_by do |i|
            v = AXES[i].clone.transform(tr); v.normalize! if v.length > 0.001; v.dot(Z_AXIS).abs
          end
          return force_axis(a, axis, 1) if axis
        end
        if name =~ /(dot|ke|shelf|noc|day|top|bottom|tang)/
          axis = a[:plane_axes].max_by { |i| a[:sizes_mm][i] }
          return force_axis(a, axis, 1)
        end
        a
      end

      def force_axis(a, axis, sign)
        r = a.dup
        cross = (a[:plane_axes] - [axis]).first
        return r unless cross
        r[:grain_axis], r[:cross_axis], r[:grain_sign] = axis, cross, sign.to_i < 0 ? -1 : 1
        r[:grain_size_mm], r[:cross_size_mm] = r[:sizes_mm][axis], r[:sizes_mm][cross]
        r[:fits_sheet] = r[:grain_size_mm] <= @sheet_l+0.5 && r[:cross_size_mm] <= @sheet_w+0.5
        r
      end

      def swapped(a); force_axis(a, a[:cross_axis], 1); end

      def choose_free(mx, my, view)
        return unless @analysis && @target
        b = bounds(@target); c = b.center
        cw = c.transform(@target_tr)
        best = nil
        @analysis[:plane_axes].each do |axis|
          extent = @analysis[:local_sizes][axis] * 0.38
          [1,-1].each do |sign|
            p = c.offset(AXES[axis], extent * sign).transform(@target_tr)
            s = view.screen_coords(p)
            d = Math.hypot(s.x-mx, s.y-my)
            item = [d,axis,sign]
            best = item if best.nil? || d < best[0]
          end
        end
        if best && best[0] < 90
          @free_axis, @free_sign = best[1], best[2]
          @analysis = force_axis(@analysis, @free_axis, @free_sign)
        end
      end

      def locked?; @target.get_attribute(DICT,'locked',false) == true; rescue false; end
      def toggle_lock
        v = !locked?
        @model.start_operation(v ? 'TT - Khóa vân' : 'TT - Mở khóa vân', true)
        @target.set_attribute(DICT,'locked',v)
        @target.set_attribute(ABF,'grain_locked',v)
        @target.set_attribute(ABF,'allow_rotate_90',!v)
        @model.commit_operation
        update_status
      rescue StandardError
        @model.abort_operation
        raise
      end

      def apply_target(target, tr, material, a, mode)
        @model.start_operation('TRẦN TUẤN - Xoay Vân Ván', true)
        target.make_unique if target.is_a?(Sketchup::ComponentInstance)
        before = signature(target)
        count = map_faces(target, material, a)
        raise 'Không tìm thấy mặt chính dùng vật liệu có texture.' if count <= 0
        raise 'Cấu trúc Group/Component thay đổi bất thường.' unless before == signature(target)
        save_metadata(target, material, a, mode)
        @model.commit_operation
        Sketchup.set_status_text("Đã xoay/căn vân #{count} mặt · #{a[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'}", SB_PROMPT)
      rescue StandardError
        @model.abort_operation
        raise
      end

      def signature(target)
        es = entities(target)
        [es.grep(Sketchup::Face).length, es.grep(Sketchup::Edge).length,
         es.grep(Sketchup::Group).length, es.grep(Sketchup::ComponentInstance).length,
         target.transformation.to_a.map { |x| x.to_f.round(10) }]
      end

      def main_faces(target, a)
        es = entities(target); axis = AXES[a[:thickness_axis]]
        es.grep(Sketchup::Face).select do |f|
          n=f.normal.clone; next false if n.length < 0.001; n.normalize!; n.dot(axis).abs >= 0.98
        end.sort_by { |f| -f.area.to_f }
      end

      def map_faces(target, material, a)
        faces = main_faces(target,a)
        count = 0
        faces.each do |face|
          front = same_material?(face.material || target.material, material)
          back  = same_material?(face.back_material || target.material, material)
          next unless front || back
          use_front = front
          if use_front && face.material.nil?
            face.material = material
            mark_inherited(face, material)
          elsif !use_front && face.back_material.nil?
            face.back_material = material
            mark_inherited(face, material)
          end
          position_face(face, material, use_front, a)
          count += 1
        end
        count
      end

      def position_face(face, material, front, a)
        g = AXES[a[:grain_axis]].clone
        g.reverse! if a[:grain_sign].to_i < 0
        c = AXES[a[:cross_axis]].clone
        b = face.bounds
        center = b.center
        plane = face.plane
        origin = center.project_to_plane(plane)
        u_len = [material.texture.width.to_f, 1.0].max
        v_len = [material.texture.height.to_f, 1.0].max
        p1 = origin
        p2 = p1.offset(g, u_len)
        p3 = p1.offset(c, v_len)
        q1 = Geom::Point3d.new(0,0,0)
        q2 = Geom::Point3d.new(u_len,0,0)
        q3 = Geom::Point3d.new(0,v_len,0)
        face.position_material(material, [p1,q1,p2,q2,p3,q3], front)
      end

      def same_material?(a,b)
        return false unless a && b
        return true if a.equal?(b)
        (a.persistent_id rescue nil) == (b.persistent_id rescue :x) || a.name.to_s == b.name.to_s
      end

      def material_key(m); "#{m.name}:#{m.persistent_id rescue 0}"; end
      def mark_inherited(face, material)
        face.set_attribute(FACE_DICT,'inherited_source',true)
        face.set_attribute(FACE_DICT,'last_material_key',material_key(material))
      end

      def sync_inherited_material(target)
        tm = target.material
        return unless tm
        entities(target).grep(Sketchup::Face).each do |f|
          next unless f.get_attribute(FACE_DICT,'inherited_source',false)
          old = f.get_attribute(FACE_DICT,'last_material_key','').to_s
          if f.material && material_key(f.material) != old
            f.set_attribute(FACE_DICT,'inherited_source',false)
            next
          end
          f.material = tm
          f.set_attribute(FACE_DICT,'last_material_key',material_key(tm))
        end
      rescue StandardError
        nil
      end

      def save_metadata(target, material, a, mode)
        target.set_attribute(DICT,'grain_axis',AXIS_NAMES[a[:grain_axis]])
        target.set_attribute(DICT,'cross_axis',AXIS_NAMES[a[:cross_axis]])
        target.set_attribute(DICT,'grain_sign',a[:grain_sign])
        target.set_attribute(DICT,'board_length_mm',@sheet_l)
        target.set_attribute(DICT,'board_width_mm',@sheet_w)
        target.set_attribute(DICT,'part_grain_mm',a[:grain_size_mm])
        target.set_attribute(DICT,'part_cross_mm',a[:cross_size_mm])
        target.set_attribute(DICT,'fits_sheet',a[:fits_sheet])
        target.set_attribute(DICT,'material_name',material.name.to_s)
        target.set_attribute(DICT,'mode',mode)
        target.set_attribute(DICT,'version',VERSION)
        target.set_attribute(ABF,'grain_sensitive',true)
        target.set_attribute(ABF,'grain_axis',AXIS_NAMES[a[:grain_axis]])
        target.set_attribute(ABF,'grain_locked',locked?)
        target.set_attribute(ABF,'allow_rotate_90',!locked?)
      end

      def build_scan
        roots = @model.selection.to_a.select { |e| container?(e) }
        roots = @model.active_entities.to_a.select { |e| container?(e) } if roots.empty?
        out=[]
        roots.each { |e| scan_entity(e, Geom::Transformation.new, out) }
        out.uniq { |i| i[:target].persistent_id rescue i[:target].entityID }
      end

      def scan_entity(e, parent_tr, out)
        return unless valid_target?(e)
        tr = parent_tr * e.transformation
        a = analyze(e,tr)
        if a && a[:sizes_mm].min <= @max_t && a[:sizes_mm].sort[1] >= 1.0
          m = e.material || entities(e).grep(Sketchup::Face).map { |f| f.material || f.back_material }.compact.find { |x| textured?(x) }
          out << {target:e,tr:tr,analysis:a,material:m,ok:!!(m && textured?(m))}
        end
        entities(e).each { |c| scan_entity(c,tr,out) if container?(c) }
      end

      def apply_scan(include_warning)
        list=@scan || []; @scan=nil
        ok=list.select { |i| i[:ok] && (i[:analysis][:fits_sheet] || include_warning) }
        return UI.beep if ok.empty?
        ok.each do |i|
          begin
            @target=i[:target]; @target_tr=i[:tr]; @material=i[:material]; @analysis=i[:analysis]
            apply_target(@target,@target_tr,@material,@analysis,'batch') unless locked?
          rescue StandardError => e
            puts "[TT Grain batch] #{e.class}: #{e.message}"
          end
        end
        Sketchup.set_status_text("Đã áp dụng vân cho #{ok.length} tấm.",SB_PROMPT)
        @view.invalidate
      end

      def draw_scan(view)
        (@scan || []).each do |i|
          b=bounds(i[:target]); next unless b
          pts=(0..7).map { |n| b.corner(n).transform(i[:tr]) }
          view.drawing_color = i[:ok] ? Sketchup::Color.new(40,200,90) : Sketchup::Color.new(230,170,40)
          view.line_width=2
          pairs=[[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
          view.draw(GL_LINES,pairs.flat_map{|x,y|[pts[x],pts[y]]})
        end
      end

      def draw_target_box(view)
        b=bounds(@target); pts=(0..7).map{|n|b.corner(n).transform(@target_tr)}
        view.drawing_color=Sketchup::Color.new(255,135,35); view.line_width=3
        pairs=[[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
        view.draw(GL_LINES,pairs.flat_map{|x,y|[pts[x],pts[y]]})
      end

      def draw_grain_arrow(view,a)
        b=bounds(@target); c=b.center; axis=AXES[a[:grain_axis]]; len=a[:local_sizes][a[:grain_axis]]*0.36
        s=a[:grain_sign].to_i<0 ? -1 : 1
        p1=c.offset(axis,-len*s).transform(@target_tr); p2=c.offset(axis,len*s).transform(@target_tr)
        view.drawing_color=Sketchup::Color.new(255,95,20); view.line_width=6; view.draw(GL_LINES,[p1,p2]); view.draw_points([p2],12,1,Sketchup::Color.new(255,95,20))
      end

      def draw_free_arrows(view)
        b=bounds(@target); c=b.center; cw=c.transform(@target_tr)
        @analysis[:plane_axes].each do |axis|
          half=@analysis[:local_sizes][axis]*0.38
          [1,-1].each do |sign|
            p=c.offset(AXES[axis],half*sign).transform(@target_tr)
            sel=(axis==@free_axis && sign==@free_sign)
            col=sel ? Sketchup::Color.new(50,220,100) : Sketchup::Color.new(145,145,145)
            view.drawing_color=col; view.line_width=sel ? 7 : 3; view.draw(GL_LINES,[cw,p]); view.draw_points([p],sel ? 13 : 8,1,col)
          end
        end
      end

      def draw_label(view)
        p=bounds(@target).center.transform(@target_tr); s=view.screen_coords(p)
        mode=@free ? "TỰ DO #{(@free_sign<0 ? '-' : '+')}#{AXIS_NAMES[@analysis[:grain_axis]]}" : 'AUTO'
        text="#{mode} · VÂN #{@analysis[:grain_size_mm].round(1)}mm · NGANG #{@analysis[:cross_size_mm].round(1)}mm · #{@analysis[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'}#{locked? ? ' · KHÓA' : ''}"
        view.draw_text(s,text,size:14,bold:true,color:Sketchup::Color.new(255,120,40))
      rescue StandardError
        nil
      end

      def update_status
        if @target && @analysis
          Sketchup.set_status_text("XOAY VÂN | #{@free ? 'TỰ DO 4 HƯỚNG' : 'AUTO'} | Click áp dụng · Alt+Click đảo 90° · Ctrl+Click khóa · TAB khổ · TAB TAB đổi mode · Chuột phải quét",SB_PROMPT)
        else
          Sketchup.set_status_text('XOAY VÂN VÁN | Rê vào tấm · TAB khai báo khổ · TAB TAB AUTO/TỰ DO · Chuột phải quét',SB_PROMPT)
        end
      end

      def clear_pick
        @target=nil; @face=nil; @path=nil; @material=nil; @analysis=nil; @free_axis=nil; @free_sign=1
      end
    end
  end
end
