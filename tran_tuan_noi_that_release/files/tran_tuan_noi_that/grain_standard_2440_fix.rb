# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN V3.4.1
# FIXED SHEET UV 2440x1220 - KHÔNG CO GIÃN THEO KÍCH THƯỚC CHI TIẾT
# - 1 map texture = đúng 1 tấm chuẩn 2440x1220 mm.
# - Tấm đủ 2440x1220: thấy trọn 1 map chuẩn.
# - Tấm nhỏ hơn: chỉ crop một phần map, tuyệt đối không scale map theo tấm.
# - Tấm lớn hơn: texture tiếp tục/lặp cùng scale chuẩn, không phóng vân.
# - Gốc UV bám góc min của mặt theo trục vân/ngang, không căn tâm riêng từng tấm.
# - Material kế thừa chỉ gán tạm để position UV rồi trả Face về nil, vẫn đổi màu được.

module TranTuanNoiThat
  module Grain
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.4.1'.freeze

    GRAIN_REFERENCE_LENGTH_MM = 2440.0 unless const_defined?(:GRAIN_REFERENCE_LENGTH_MM, false)
    GRAIN_REFERENCE_WIDTH_MM  = 1220.0 unless const_defined?(:GRAIN_REFERENCE_WIDTH_MM, false)
    MIGRATION_KEY_V340 = 'v340_standard_2440_migrated'.freeze unless const_defined?(:MIGRATION_KEY_V340, false)

    class << self
      def ensure_v340_defaults
        Sketchup.write_default(PREF, 'board_length_mm', GRAIN_REFERENCE_LENGTH_MM)
        Sketchup.write_default(PREF, 'board_width_mm', GRAIN_REFERENCE_WIDTH_MM)
        Sketchup.write_default(PREF, MIGRATION_KEY_V340, true)
        true
      rescue StandardError => error
        puts "[TT Grain V3.4.1 migrate] #{error.class}: #{error.message}"
        false
      end

      def board_length_mm
        ensure_v340_defaults
        GRAIN_REFERENCE_LENGTH_MM
      end

      def board_width_mm
        ensure_v340_defaults
        GRAIN_REFERENCE_WIDTH_MM
      end

      def save_settings(_length, _width, thickness, mode)
        t = [[thickness.to_f, 1.0].max, 500.0].min
        m = %w[auto length width].include?(mode.to_s) ? mode.to_s : 'auto'
        Sketchup.write_default(PREF, 'board_length_mm', GRAIN_REFERENCE_LENGTH_MM)
        Sketchup.write_default(PREF, 'board_width_mm', GRAIN_REFERENCE_WIDTH_MM)
        Sketchup.write_default(PREF, 'max_thickness_mm', t)
        Sketchup.write_default(PREF, 'lock_mode', m)
        Sketchup.write_default(PREF, MIGRATION_KEY_V340, true)
        @active_tool.receive_settings(GRAIN_REFERENCE_LENGTH_MM, GRAIN_REFERENCE_WIDTH_MM, t, m) if @active_tool
        true
      end

      def open_settings(tool = nil)
        @active_tool = tool if tool
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end

        t = max_thickness_mm
        m = lock_mode
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'TRẦN TUẤN - KHỔ VÁN / HƯỚNG VÂN',
          preferences_key: 'TranTuanNoiThat.Grain.Fixed2440',
          scrollable: false, resizable: false, width: 440, height: 465,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(<<~HTML)
          <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}body{margin:0;padding:20px;background:#151515;color:#f5f5f5;font:14px Arial}h2{margin:0 0 5px;color:#ff8a22}.sub{color:#aaa;margin-bottom:14px}.card{background:#222;border:1px solid #444;border-radius:9px;padding:14px;margin-bottom:12px}.fixed{padding:13px;border:1px solid #f47b20;border-radius:8px;background:#111;color:#ff9a45;font-size:20px;font-weight:700;text-align:center}label{display:block;margin:10px 0 5px;font-weight:bold}input,select{width:100%;padding:10px;border:1px solid #555;border-radius:7px;background:#111;color:white}.save{width:100%;padding:12px;border:0;border-radius:8px;background:#f47b20;color:#fff;font-weight:bold;cursor:pointer}.note{font-size:12px;color:#bbb;line-height:1.5}</style></head><body>
          <h2>XOAY VÂN VÁN V3.4.1</h2><div class="sub">Tỷ lệ texture cố định, không co giãn theo kích thước tấm.</div>
          <div class="card"><label>KHỔ VÂN CHUẨN CỐ ĐỊNH</label><div class="fixed">2440 × 1220 mm</div><div class="note" style="margin-top:10px">1 map = 1 tấm 2440×1220. Tấm nhỏ chỉ crop; tấm lớn lặp cùng tỷ lệ.</div><label>Dày tối đa nhận ván (mm)</label><input id="t" type="number" value="#{t}"></div>
          <div class="card"><label>Luật AUTO</label><select id="m"><option value="auto">Theo khổ + cạnh hợp lý</option><option value="length">Khóa theo chiều DÀI chi tiết</option><option value="width">Khóa theo chiều RỘNG chi tiết</option></select></div>
          <button class="save" onclick="s()">LƯU THÔNG SỐ</button><div class="note" style="margin-top:12px">TAB: bảng này · TAB TAB: AUTO ↔ TỰ DO · Alt+Click: đảo 90° · Ctrl+Click: khóa.</div>
          <script>m.value=#{m.inspect};function s(){sketchup.save(2440,1220,Number(t.value),m.value)}</script></body></html>
        HTML
        @dialog.add_action_callback('save') do |_ctx, ll, ww, tt, mm|
          save_settings(ll, ww, tt, mm)
          @dialog.close
        end
        @dialog.set_on_closed { @dialog = nil }
        @dialog.show
      end

      def activate
        ensure_v340_defaults
        tool = Tool.new
        @active_tool = tool
        Sketchup.active_model.select_tool(tool)
      end
    end

    class Tool
      private

      def sync_inherited_material(target)
        release_legacy_baked_materials(target)
      end

      def release_legacy_baked_materials(target)
        es = entities(target)
        return 0 unless es
        released = 0
        es.grep(Sketchup::Face).each do |face|
          next unless face.get_attribute(FACE_DICT, 'inherited_source', false)
          old_key = face.get_attribute(FACE_DICT, 'last_material_key', '').to_s
          changed = false
          if face.material && material_key(face.material) == old_key
            face.material = nil
            changed = true
          end
          if face.back_material && material_key(face.back_material) == old_key
            face.back_material = nil
            changed = true
          end
          if changed || (face.material.nil? && face.back_material.nil?)
            begin
              face.delete_attribute(FACE_DICT, 'inherited_source')
              face.delete_attribute(FACE_DICT, 'last_material_key')
            rescue StandardError
              face.set_attribute(FACE_DICT, 'inherited_source', false)
              face.set_attribute(FACE_DICT, 'last_material_key', '')
            end
            released += 1 if changed
          else
            face.set_attribute(FACE_DICT, 'inherited_source', false)
          end
        end
        released
      rescue StandardError => error
        puts "[TT Grain V3.4.1 release] #{error.class}: #{error.message}"
        0
      end

      def detect_target_material(target, analysis, inherited_material = nil)
        release_legacy_baked_materials(target)
        candidates = []
        if analysis
          main_faces(target, analysis).each do |face|
            add_material_candidate(candidates, face.material, :target_face)
            add_material_candidate(candidates, face.back_material, :target_face_back)
          end
        end
        add_material_candidate(candidates, target.material, :target)
        es = entities(target)
        if es
          es.grep(Sketchup::Face).sort_by { |face| -face.area.to_f }.each do |face|
            add_material_candidate(candidates, face.material, :target_face)
            add_material_candidate(candidates, face.back_material, :target_face_back)
          end
        end
        add_material_candidate(candidates, inherited_material, :ancestor)
        candidates.find { |pair| textured?(pair[0]) }
      rescue StandardError => error
        puts "[TT Grain V3.4.1 detect] #{error.class}: #{error.message}"
        nil
      end

      def map_faces(target, material, analysis)
        release_legacy_baked_materials(target)
        faces = main_faces(target, analysis)
        inherited_source = [:target, :ancestor].include?(@material_source)
        count = 0
        faces.each do |face|
          front_direct = same_material?(face.material, material)
          back_direct  = same_material?(face.back_material, material)
          if front_direct
            position_face(face, material, true, analysis)
            count += 1
            next
          end
          if back_direct
            position_face(face, material, false, analysis)
            count += 1
            next
          end
          next unless inherited_source
          if face.material.nil?
            begin
              face.material = material
              position_face(face, material, true, analysis)
              count += 1
            ensure
              face.material = nil rescue nil
            end
          elsif face.back_material.nil?
            begin
              face.back_material = material
              position_face(face, material, false, analysis)
              count += 1
            ensure
              face.back_material = nil rescue nil
            end
          end
        end
        count
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

        # Quan trọng: kích thước P luôn là 2440x1220, KHÔNG lấy kích thước Face.
        ref_u = GRAIN_REFERENCE_LENGTH_MM.mm.to_f
        ref_v = GRAIN_REFERENCE_WIDTH_MM.mm.to_f
        tex_u = texture.width.to_f.abs
        tex_v = texture.height.to_f.abs
        raise 'Kích thước texture không hợp lệ.' if tex_u <= 0.0001 || tex_v <= 0.0001

        origin = fixed_uv_origin(face, grain, cross)
        p1 = origin
        p2 = origin.offset(grain, ref_u)
        p3 = origin.offset(cross, ref_v)

        # Toàn bộ ảnh texture gốc được trải đúng trên khung vật lý 2440x1220.
        q1 = Geom::Point3d.new(0, 0, 0)
        q2 = Geom::Point3d.new(tex_u, 0, 0)
        q3 = Geom::Point3d.new(0, tex_v, 0)
        face.position_material(material, [p1, q1, p2, q2, p3, q3], front)
      rescue StandardError => error
        puts "[TT Grain V3.4.1 position] #{error.class}: #{error.message}"
        raise
      end

      def save_metadata(target, material, analysis, mode)
        target.set_attribute(DICT, 'grain_axis', AXIS_NAMES[analysis[:grain_axis]])
        target.set_attribute(DICT, 'cross_axis', AXIS_NAMES[analysis[:cross_axis]])
        target.set_attribute(DICT, 'grain_sign', analysis[:grain_sign])
        target.set_attribute(DICT, 'board_length_mm', GRAIN_REFERENCE_LENGTH_MM)
        target.set_attribute(DICT, 'board_width_mm', GRAIN_REFERENCE_WIDTH_MM)
        target.set_attribute(DICT, 'sheet_length_mm', GRAIN_REFERENCE_LENGTH_MM)
        target.set_attribute(DICT, 'sheet_width_mm', GRAIN_REFERENCE_WIDTH_MM)
        target.set_attribute(DICT, 'part_grain_mm', analysis[:grain_size_mm])
        target.set_attribute(DICT, 'part_cross_mm', analysis[:cross_size_mm])
        target.set_attribute(DICT, 'fits_sheet', analysis[:fits_sheet])
        target.set_attribute(DICT, 'material_name', material.name.to_s)
        target.set_attribute(DICT, 'texture_reference_mm', '2440x1220')
        target.set_attribute(DICT, 'texture_scale_mode', 'fixed_sheet_no_stretch')
        target.set_attribute(DICT, 'texture_align', 'face_min_corner_crop_repeat')
        target.set_attribute(DICT, 'material_binding', 'inherit_safe')
        target.set_attribute(DICT, 'mode', mode)
        target.set_attribute(DICT, 'version', VERSION)
        target.set_attribute(ABF, 'grain_sensitive', true)
        target.set_attribute(ABF, 'grain_axis', AXIS_NAMES[analysis[:grain_axis]])
        target.set_attribute(ABF, 'grain_locked', locked?)
        target.set_attribute(ABF, 'allow_rotate_90', !locked?)
        target.set_attribute(ABF, 'grain_sheet_length_mm', GRAIN_REFERENCE_LENGTH_MM)
        target.set_attribute(ABF, 'grain_sheet_width_mm', GRAIN_REFERENCE_WIDTH_MM)
      end

      def draw_label(view)
        point = bounds(@target).center.transform(@target_tr)
        screen = view.screen_coords(point)
        mode = @free ? "TỰ DO #{(@free_sign < 0 ? '-' : '+')}#{AXIS_NAMES[@analysis[:grain_axis]]}" : 'AUTO'
        part = "CT #{@analysis[:grain_size_mm].round(1)}×#{@analysis[:cross_size_mm].round(1)}"
        fit = @analysis[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'
        lock = locked? ? ' · KHÓA' : ''
        text = "#{mode} · 1 MAP = 2440×1220 · #{part} · #{fit}#{lock}"
        view.draw_text(screen, text, size: 14, bold: true, color: Sketchup::Color.new(255, 120, 40))
      rescue StandardError
        nil
      end
    end
  end
end
