# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN V3.5.0
# PRODUCTION SAFE GRAIN / PREVIEW BEFORE APPLY / TRUE 1-TILE UV
#
# Quy tắc chính:
# - UV đúng SketchUp: 1 texture tile = U/V từ 0.0 -> 1.0.
# - Khổ vật liệu quyết định kích thước vật lý của 1 tile (mặc định 2440x1220 mm).
# - Tấm nhỏ chỉ crop; tấm lớn lặp; tuyệt đối không scale theo kích thước chi tiết.
# - Chỉ map 2 mặt chính lớn nhất theo chiều dày.
# - A hoặc SHIFT: quét preview; ENTER mới áp dụng.
# - Xanh: hợp lệ; Vàng: nghi ngờ/đã khóa; Đỏ: vượt khổ/không texture/lỗi.
# - Quét selection hoặc toàn active context, đệ quy Group/Component.
# - Khóa sản xuất: TT_GRAIN/TT_ABF_GRAIN grain_locked=true => AUTO bỏ qua.
# - Không explode/regroup/thêm-xóa geometry/đổi transform; có guard trước/sau.

module TranTuanNoiThat
  module Grain
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.5.0'.freeze

    A_KEY = 65 unless const_defined?(:A_KEY, false)
    SHIFT_KEY = 16 unless const_defined?(:SHIFT_KEY, false)
    MATERIAL_PROFILE_KEY = 'material_profiles_v350'.freeze unless const_defined?(:MATERIAL_PROFILE_KEY, false)
    DEFAULT_SHEET_L = 2440.0 unless const_defined?(:DEFAULT_SHEET_L, false)
    DEFAULT_SHEET_W = 1220.0 unless const_defined?(:DEFAULT_SHEET_W, false)
    MIN_PLANE_MM = 1.0 unless const_defined?(:MIN_PLANE_MM, false)

    class StructureGuardError < StandardError; end unless const_defined?(:StructureGuardError, false)

    class << self
      def material_profile_id(material)
        name = material ? material.name.to_s.strip : ''
        name = '__DEFAULT__' if name.empty?
        name
      rescue StandardError
        '__DEFAULT__'
      end

      def material_profiles
        raw = Sketchup.read_default(PREF, MATERIAL_PROFILE_KEY, '{}').to_s
        data = JSON.parse(raw)
        data.is_a?(Hash) ? data : {}
      rescue StandardError
        {}
      end

      def write_material_profiles(data)
        Sketchup.write_default(PREF, MATERIAL_PROFILE_KEY, JSON.generate(data))
        true
      rescue StandardError => error
        puts "[TT Grain V3.5.0 profile write] #{error.class}: #{error.message}"
        false
      end

      def sheet_for_material(material)
        key = material_profile_id(material)
        profile = material_profiles[key]
        if profile.is_a?(Hash)
          l = profile['length_mm'].to_f
          w = profile['width_mm'].to_f
          if l > 0.0 && w > 0.0
            return [[l, w].max, [l, w].min]
          end
        end
        [DEFAULT_SHEET_L, DEFAULT_SHEET_W]
      rescue StandardError
        [DEFAULT_SHEET_L, DEFAULT_SHEET_W]
      end

      def save_material_sheet(material, length_mm, width_mm)
        l = [[length_mm.to_f, 1.0].max, 10000.0].min
        w = [[width_mm.to_f, 1.0].max, 10000.0].min
        l, w = [l, w].max, [l, w].min
        data = material_profiles
        data[material_profile_id(material)] = {
          'length_mm' => l,
          'width_mm' => w,
          'material_name' => (material ? material.name.to_s : 'Mặc định')
        }
        write_material_profiles(data)
        [l, w]
      end

      def board_length_mm
        DEFAULT_SHEET_L
      end

      def board_width_mm
        DEFAULT_SHEET_W
      end

      def open_settings(tool = nil)
        @active_tool = tool if tool
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end

        material = if @active_tool && @active_tool.respond_to?(:current_material_for_settings)
                     @active_tool.current_material_for_settings
                   end
        l, w = sheet_for_material(material)
        t = max_thickness_mm
        m = lock_mode
        material_name = material ? material.name.to_s : 'MẶC ĐỊNH / CHƯA CHỌN VẬT LIỆU'

        @dialog = UI::HtmlDialog.new(
          dialog_title: 'TRẦN TUẤN - KHỔ VÁN / HƯỚNG VÂN',
          preferences_key: 'TranTuanNoiThat.Grain.V350',
          scrollable: false,
          resizable: false,
          width: 460,
          height: 560,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(<<~HTML)
          <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}body{margin:0;padding:20px;background:#151515;color:#f5f5f5;font:14px Arial}h2{margin:0 0 5px;color:#ff8a22}.sub{color:#aaa;margin-bottom:14px}.card{background:#222;border:1px solid #444;border-radius:9px;padding:14px;margin-bottom:12px}label{display:block;margin:9px 0 5px;font-weight:bold}input,select{width:100%;padding:10px;border:1px solid #555;border-radius:7px;background:#111;color:white}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.preset{background:#343434;color:#fff;border:0;padding:9px;border-radius:6px;cursor:pointer}.save{width:100%;padding:12px;border:0;border-radius:8px;background:#f47b20;color:#fff;font-weight:bold;cursor:pointer}.note{font-size:12px;color:#bbb;line-height:1.5}.mat{color:#ffad67;font-weight:bold;word-break:break-word}</style></head><body>
          <h2>XOAY VÂN VÁN V3.5.0</h2><div class="sub">1 map texture = 1 khổ tấm vật liệu. Không co giãn theo chi tiết.</div>
          <div class="card"><label>Vật liệu đang cấu hình</label><div class="mat">#{material_name}</div><label>Chiều dài / hướng vân (mm)</label><input id="l" type="number" value="#{l}"><label>Chiều rộng (mm)</label><input id="w" type="number" value="#{w}"><div class="row" style="margin-top:9px"><button class="preset" onclick="p(2440,1220)">2440×1220</button><button class="preset" onclick="p(2800,1220)">2800×1220</button></div><label>Dày tối đa nhận ván (mm)</label><input id="t" type="number" value="#{t}"></div>
          <div class="card"><label>Luật AUTO mặc định</label><select id="m"><option value="auto">Theo tên chi tiết + khổ vật liệu</option><option value="length">Khóa theo chiều DÀI</option><option value="width">Khóa theo chiều RỘNG</option></select></div>
          <button class="save" onclick="s()">LƯU CHO VẬT LIỆU NÀY</button><div class="note" style="margin-top:12px">A hoặc SHIFT: quét preview · ENTER: áp dụng · TAB: bảng này · Ctrl+Click: khóa/mở khóa sản xuất.</div>
          <script>m.value=#{m.inspect};function p(a,b){l.value=a;w.value=b}function s(){sketchup.save(Number(l.value),Number(w.value),Number(t.value),m.value)}</script></body></html>
        HTML
        @dialog.add_action_callback('save') do |_ctx, ll, ww, tt, mm|
          length, width = save_material_sheet(material, ll, ww)
          thickness = [[tt.to_f, 1.0].max, 500.0].min
          mode = %w[auto length width].include?(mm.to_s) ? mm.to_s : 'auto'
          Sketchup.write_default(PREF, 'max_thickness_mm', thickness)
          Sketchup.write_default(PREF, 'lock_mode', mode)
          if @active_tool
            @active_tool.receive_settings(length, width, thickness, mode)
            @active_tool.refresh_material_profile if @active_tool.respond_to?(:refresh_material_profile)
          end
          @dialog.close
        end
        @dialog.set_on_closed { @dialog = nil }
        @dialog.show
      end
    end

    class Tool
      alias_method :tt_v350_key_base, :onKeyDown unless method_defined?(:tt_v350_key_base)
      alias_method :tt_v350_pick_base, :pick unless method_defined?(:tt_v350_pick_base)

      def current_material_for_settings
        @material
      end

      def refresh_material_profile
        return unless @material
        @sheet_l, @sheet_w = Grain.sheet_for_material(@material)
        analyze_current
        @view.invalidate if @view
      rescue StandardError
        nil
      end

      def onKeyDown(key, repeat, flags, view)
        if @scan && key == ENTER_KEY
          apply_scan(false)
          return
        end

        if key == A_KEY || key == SHIFT_KEY
          start_scan_preview(view)
          return
        end

        tt_v350_key_base(key, repeat, flags, view)
      rescue StandardError => error
        puts "[TT Grain V3.5.0 key] #{error.class}: #{error.message}"
        UI.beep
      end

      private

      def pick(view, x, y)
        tt_v350_pick_base(view, x, y)
        if @target && @material
          @sheet_l, @sheet_w = Grain.sheet_for_material(@material)
        end
      end

      def normalize_part_name(target)
        name = ((target.name.to_s rescue '') + ' ' + (definition(target).name.to_s rescue '')).upcase
        name = name.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '') rescue name
        name.tr('Đ', 'D')
      end

      def part_rule(target)
        name = normalize_part_name(target)
        return :vertical if name =~ /(ABF[_\- ]*HOI|ABF[_\- ]*CANH|\bHOI\b|\bCANH\b|DOOR|PANEL DUNG|VACH)/
        return :horizontal if name =~ /(ABF[_\- ]*DOT|ABF[_\- ]*KE|\bDOT\b|\bKE\b|SHELF)/
        return :length if name =~ /(ABF[_\- ]*DAY|ABF[_\- ]*NOC|\bDAY\b|\bNOC\b|BOTTOM|TOP)/
        nil
      end

      def part_name_rule(target, analysis, tr)
        rule = part_rule(target)
        return super unless rule

        case rule
        when :vertical
          axis = analysis[:plane_axes].max_by do |index|
            vector = AXES[index].clone.transform(tr)
            vector.normalize! if vector.length > 0.0001
            vector.dot(Z_AXIS).abs
          end
          force_axis(analysis, axis, 1)
        when :horizontal, :length
          axis = analysis[:plane_axes].max_by { |index| analysis[:sizes_mm][index] }
          force_axis(analysis, axis, 1)
        else
          analysis
        end
      rescue StandardError
        analysis
      end

      def main_faces(target, analysis)
        es = entities(target)
        return [] unless es
        axis = AXES[analysis[:thickness_axis]]
        aligned = es.grep(Sketchup::Face).select do |face|
          normal = face.normal.clone
          next false if normal.length < 0.0001
          normal.normalize!
          normal.dot(axis).abs >= 0.985
        end
        return [] if aligned.empty?

        positive = aligned.select { |face| face.normal.dot(axis) >= 0.0 }.max_by { |face| face.area.to_f }
        negative = aligned.select { |face| face.normal.dot(axis) < 0.0 }.max_by { |face| face.area.to_f }
        faces = [positive, negative].compact.uniq
        if faces.length < 2
          aligned.sort_by { |face| -face.area.to_f }.each do |face|
            faces << face unless faces.include?(face)
            break if faces.length >= 2
          end
        end
        faces.first(2)
      end

      def structure_signature(target)
        es = entities(target)
        return nil unless es
        rows = []
        es.each do |entity|
          id = begin
            entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
          rescue StandardError
            entity.object_id
          end
          if entity.is_a?(Sketchup::Face)
            vertices = entity.vertices.map do |vertex|
              p = vertex.position
              [p.x.to_f.round(8), p.y.to_f.round(8), p.z.to_f.round(8)]
            end.sort
            rows << ['F', id, vertices]
          elsif entity.is_a?(Sketchup::Edge)
            a = entity.start.position
            b = entity.end.position
            rows << ['E', id,
                     [a.x.to_f.round(8), a.y.to_f.round(8), a.z.to_f.round(8)],
                     [b.x.to_f.round(8), b.y.to_f.round(8), b.z.to_f.round(8)]]
          elsif container?(entity)
            rows << ['C', id, entity.transformation.to_a.map { |v| v.to_f.round(10) }]
          else
            rows << [entity.class.name.to_s, id]
          end
        end
        transform = target.transformation.to_a.map { |v| v.to_f.round(10) }
        Digest::SHA256.hexdigest(JSON.generate([transform, rows.sort_by { |row| row[1].to_s }]))
      end

      def axis_scale(tr, axis_index)
        return 1.0 unless tr
        vector = AXES[axis_index].clone.transform(tr)
        value = vector.length.to_f
        value > 0.000001 ? value : 1.0
      rescue StandardError
        1.0
      end

      def fixed_uv_origin(face, grain, cross)
        points = face.vertices.map(&:position)
        raise 'Mặt ván không có đỉnh hợp lệ.' if points.empty?
        anchor = points.first
        min_g = 0.0
        min_c = 0.0
        points.each do |point|
          vector = point - anchor
          dg = vector.dot(grain)
          dc = vector.dot(cross)
          min_g = dg if dg < min_g
          min_c = dc if dc < min_c
        end
        anchor.offset(grain, min_g).offset(cross, min_c).project_to_plane(face.plane)
      end

      def position_face(face, material, front, analysis)
        texture = material && material.texture
        raise 'Vật liệu không có texture.' unless texture

        grain = AXES[analysis[:grain_axis]].clone
        grain.reverse! if analysis[:grain_sign].to_i < 0
        cross = AXES[analysis[:cross_axis]].clone
        grain.normalize! if grain.length > 0.0001
        cross.normalize! if cross.length > 0.0001

        sheet_l, sheet_w = Grain.sheet_for_material(material)
        grain_scale = axis_scale(@target_tr, analysis[:grain_axis])
        cross_scale = axis_scale(@target_tr, analysis[:cross_axis])
        ref_u = sheet_l.mm.to_f / grain_scale
        ref_v = sheet_w.mm.to_f / cross_scale

        origin = fixed_uv_origin(face, grain, cross)
        p1 = origin
        p2 = origin.offset(grain, ref_u)
        p3 = origin.offset(cross, ref_v)

        # SketchUp UV: một tile đầy đủ luôn là 0..1, KHÔNG dùng texture.width/height làm UV.
        q1 = Geom::Point3d.new(0.0, 0.0, 0.0)
        q2 = Geom::Point3d.new(1.0, 0.0, 0.0)
        q3 = Geom::Point3d.new(0.0, 1.0, 0.0)
        result = face.position_material(material, [p1, q1, p2, q2, p3, q3], front)
        raise 'SketchUp không nhận mapping texture.' unless result
        result
      end

      def save_metadata(target, material, analysis, mode)
        sheet_l, sheet_w = Grain.sheet_for_material(material)
        target.set_attribute(DICT, 'grain_axis', AXIS_NAMES[analysis[:grain_axis]])
        target.set_attribute(DICT, 'cross_axis', AXIS_NAMES[analysis[:cross_axis]])
        target.set_attribute(DICT, 'grain_sign', analysis[:grain_sign])
        target.set_attribute(DICT, 'board_length_mm', sheet_l)
        target.set_attribute(DICT, 'board_width_mm', sheet_w)
        target.set_attribute(DICT, 'sheet_length_mm', sheet_l)
        target.set_attribute(DICT, 'sheet_width_mm', sheet_w)
        target.set_attribute(DICT, 'part_grain_mm', analysis[:grain_size_mm])
        target.set_attribute(DICT, 'part_cross_mm', analysis[:cross_size_mm])
        target.set_attribute(DICT, 'fits_sheet', analysis[:fits_sheet])
        target.set_attribute(DICT, 'material_name', material.name.to_s)
        target.set_attribute(DICT, 'texture_uv_tile', '0_to_1')
        target.set_attribute(DICT, 'texture_scale_mode', 'material_sheet_no_stretch')
        target.set_attribute(DICT, 'texture_align', 'main_faces_only')
        target.set_attribute(DICT, 'material_binding', 'editable')
        target.set_attribute(DICT, 'part_rule', part_rule(target).to_s)
        target.set_attribute(DICT, 'mode', mode)
        target.set_attribute(DICT, 'version', VERSION)

        target.set_attribute(ABF, 'grain_sensitive', true)
        target.set_attribute(ABF, 'grain_axis', AXIS_NAMES[analysis[:grain_axis]])
        target.set_attribute(ABF, 'grain_locked', locked?)
        target.set_attribute(ABF, 'allow_rotate_90', !locked?)
        target.set_attribute(ABF, 'grain_sheet_length_mm', sheet_l)
        target.set_attribute(ABF, 'grain_sheet_width_mm', sheet_w)
      end

      def locked_target?(target)
        target.get_attribute(DICT, 'locked', false) == true ||
          target.get_attribute(ABF, 'grain_locked', false) == true
      rescue StandardError
        false
      end

      def analyze_for_sheet(target, tr, sheet_l, sheet_w)
        old_l, old_w = @sheet_l, @sheet_w
        @sheet_l, @sheet_w = sheet_l.to_f, sheet_w.to_f
        analysis = analyze(target, tr)
        analysis = part_name_rule(target, analysis, tr) if analysis && @lock_mode == 'auto'
        analysis
      ensure
        @sheet_l, @sheet_w = old_l, old_w
      end

      def scan_entity(entity, parent_tr, out, inherited_material = nil)
        return unless valid_target?(entity)

        tr = parent_tr * entity.transformation
        provisional = analyze(entity, tr)
        visible_inherited = entity.material || inherited_material

        if provisional && provisional[:sizes_mm].min <= @max_t && provisional[:sizes_mm].sort[1] >= MIN_PLANE_MM
          detected = detect_target_material(entity, provisional, visible_inherited)
          material = detected ? detected[0] : nil
          source = detected ? detected[1] : nil
          sheet_l, sheet_w = Grain.sheet_for_material(material)
          analysis = analyze_for_sheet(entity, tr, sheet_l, sheet_w)
          item = {
            target: entity,
            tr: tr,
            analysis: analysis,
            material: material,
            material_source: source,
            sheet_l: sheet_l,
            sheet_w: sheet_w,
            locked: locked_target?(entity),
            rule: part_rule(entity)
          }
          classify_scan_item!(item)
          out << item
        end

        es = entities(entity)
        return unless es
        es.each do |child|
          scan_entity(child, tr, out, visible_inherited) if container?(child)
        end
      rescue StandardError => error
        puts "[TT Grain V3.5.0 scan] #{error.class}: #{error.message}"
      end

      def classify_scan_item!(item)
        analysis = item[:analysis]
        material = item[:material]
        if item[:locked]
          item[:status] = :yellow
          item[:reason] = 'ĐÃ KHÓA'
        elsif analysis.nil?
          item[:status] = :red
          item[:reason] = 'KHÔNG NHẬN KÍCH THƯỚC'
        elsif material.nil? || !textured?(material)
          item[:status] = :red
          item[:reason] = 'KHÔNG TEXTURE'
        elsif main_faces(item[:target], analysis).length < 2
          item[:status] = :yellow
          item[:reason] = 'MẶT CHÍNH NGHI NGỜ'
        elsif !analysis[:fits_sheet]
          item[:status] = :red
          item[:reason] = 'VƯỢT KHỔ'
        else
          plane = analysis[:plane_axes].map { |axis| analysis[:sizes_mm][axis].to_f }.sort
          near_square = plane[0] > 0.0 && (plane[1] / plane[0]) < 1.08
          if item[:rule].nil? && near_square
            item[:status] = :yellow
            item[:reason] = 'HƯỚNG VÂN NGHI NGỜ'
          else
            item[:status] = :green
            item[:reason] = 'SẴN SÀNG'
          end
        end
        item[:ok] = item[:status] != :red
        item
      rescue StandardError
        item[:status] = :red
        item[:reason] = 'LỖI PHÂN TÍCH'
        item[:ok] = false
        item
      end

      def build_scan
        roots = @model.selection.to_a.select { |entity| container?(entity) && entity.valid? }
        roots = @model.active_entities.to_a.select { |entity| container?(entity) && entity.valid? } if roots.empty?
        out = []
        roots.each { |entity| scan_entity(entity, Geom::Transformation.new, out, nil) }
        out.uniq { |item| item[:target].persistent_id rescue item[:target].entityID }
      end

      def start_scan_preview(view)
        @scan = build_scan
        if @scan.empty?
          @scan = nil
          UI.beep
          Sketchup.set_status_text('Không tìm thấy tấm ván hợp lệ để quét.', SB_PROMPT)
          return false
        end
        counts = @scan.group_by { |item| item[:status] }.transform_values(&:length)
        Sketchup.set_status_text(
          "PREVIEW #{@scan.length} tấm · XANH #{counts[:green].to_i} · VÀNG #{counts[:yellow].to_i} · ĐỎ #{counts[:red].to_i} · ENTER áp dụng · ESC hủy",
          SB_PROMPT
        )
        view.invalidate
        true
      end

      def apply_one_without_operation(item)
        target = item[:target]
        return :locked if locked_target?(target)
        return :skip if item[:status] == :red

        target.make_unique if target.is_a?(Sketchup::ComponentInstance)
        before = structure_signature(target)

        @target = target
        @target_tr = item[:tr]
        @material = item[:material]
        @material_source = item[:material_source]
        @analysis = item[:analysis]
        @sheet_l, @sheet_w = item[:sheet_l], item[:sheet_w]

        count = map_faces(target, @material, @analysis)
        raise 'Không map được 2 mặt chính.' if count <= 0

        after = structure_signature(target)
        raise StructureGuardError, "Cấu trúc #{target.name} bị thay đổi bất thường." unless before == after

        save_metadata(target, @material, @analysis, 'batch_preview_confirmed')
        :applied
      end

      def apply_scan(_include_warning = false)
        list = @scan || []
        @scan = nil
        return UI.beep if list.empty?

        counts = { applied: 0, locked: 0, skipped: 0, errors: 0 }
        @model.start_operation('TRẦN TUẤN - Căn Vân Hàng Loạt', true)
        begin
          list.each do |item|
            begin
              result = apply_one_without_operation(item)
              case result
              when :applied then counts[:applied] += 1
              when :locked then counts[:locked] += 1
              else counts[:skipped] += 1
              end
            rescue StructureGuardError
              raise
            rescue StandardError => error
              counts[:errors] += 1
              puts "[TT Grain V3.5.0 apply] #{error.class}: #{error.message}"
            end
          end
          @model.commit_operation
        rescue StructureGuardError => error
          @model.abort_operation
          UI.messagebox("ĐÃ HỦY TOÀN BỘ THAO TÁC để bảo vệ Group/Component.\n#{error.message}")
          @view.invalidate if @view
          return false
        rescue StandardError => error
          @model.abort_operation
          UI.messagebox("Không thể áp dụng vân:\n#{error.message}")
          @view.invalidate if @view
          return false
        end

        message = "Đã căn: #{counts[:applied]} · Đã khóa: #{counts[:locked]} · Bỏ qua: #{counts[:skipped]} · Lỗi: #{counts[:errors]}"
        Sketchup.set_status_text(message, SB_PROMPT)
        UI.messagebox(message)
        @view.invalidate if @view
        true
      end

      def apply_target(target, tr, material, analysis, mode)
        @model.start_operation('TRẦN TUẤN - Xoay Vân Ván', true)
        begin
          target.make_unique if target.is_a?(Sketchup::ComponentInstance)
          before = structure_signature(target)
          @target = target
          @target_tr = tr
          @material = material
          @analysis = analysis
          @sheet_l, @sheet_w = Grain.sheet_for_material(material)
          count = map_faces(target, material, analysis)
          raise 'Không tìm thấy 2 mặt chính dùng texture.' if count <= 0
          after = structure_signature(target)
          raise StructureGuardError, 'Phát hiện thay đổi hình học/transform ngoài ý muốn.' unless before == after
          save_metadata(target, material, analysis, mode)
          @model.commit_operation
          Sketchup.set_status_text("Đã căn vân #{count} mặt chính.", SB_PROMPT)
          true
        rescue StandardError
          @model.abort_operation
          raise
        end
      end

      def draw_scan(view)
        (@scan || []).each do |item|
          b = bounds(item[:target])
          next unless b
          pts = (0..7).map { |n| b.corner(n).transform(item[:tr]) }
          color = case item[:status]
                  when :green then Sketchup::Color.new(40, 205, 90)
                  when :yellow then Sketchup::Color.new(245, 190, 35)
                  else Sketchup::Color.new(225, 55, 55)
                  end
          view.drawing_color = color
          view.line_width = item[:status] == :red ? 4 : 3
          pairs = [[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
          view.draw(GL_LINES, pairs.flat_map { |x, y| [pts[x], pts[y]] })
        end
      end

      def draw_label(view)
        point = bounds(@target).center.transform(@target_tr)
        screen = view.screen_coords(point)
        mode = @free ? "TỰ DO #{(@free_sign < 0 ? '-' : '+')}#{AXIS_NAMES[@analysis[:grain_axis]]}" : 'AUTO'
        sheet_l, sheet_w = Grain.sheet_for_material(@material)
        part = "CT #{@analysis[:grain_size_mm].round(1)}×#{@analysis[:cross_size_mm].round(1)}"
        fit = @analysis[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'
        rule = part_rule(@target)
        rule_text = rule ? " · RULE #{rule.to_s.upcase}" : ''
        lock = locked? ? ' · KHÓA' : ''
        text = "#{mode} · 1 MAP=#{sheet_l.round(0)}×#{sheet_w.round(0)} · #{part} · #{fit}#{rule_text}#{lock}"
        view.draw_text(screen, text, size: 14, bold: true, color: Sketchup::Color.new(255, 120, 40))
      rescue StandardError
        nil
      end

      def update_status
        if @scan
          Sketchup.set_status_text('PREVIEW VÂN · Xanh đúng · Vàng nghi ngờ/khóa · Đỏ lỗi/vượt khổ · ENTER áp dụng · ESC hủy', SB_PROMPT)
        elsif @target && @analysis
          Sketchup.set_status_text('XOAY VÂN | Click áp dụng 1 tấm · A/SHIFT quét cụm · ENTER xác nhận · Ctrl+Click khóa · TAB vật liệu/khổ', SB_PROMPT)
        else
          Sketchup.set_status_text('XOAY VÂN | Rê vào tấm · A/SHIFT quét selection hoặc toàn context · TAB cài khổ theo vật liệu', SB_PROMPT)
        end
      end
    end
  end
end
