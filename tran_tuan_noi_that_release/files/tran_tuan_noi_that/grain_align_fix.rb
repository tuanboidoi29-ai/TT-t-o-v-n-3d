# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN V3.3.0
# FIX KHỔ VÁN + CĂN VÂN GỖ ĐỀU
# - Migrate mặc định cũ 2440x1220 -> 2800x1220 một lần; không đè khổ người dùng đã tự chỉnh.
# - Luôn chuẩn hóa Dài >= Rộng khi lưu khổ.
# - Giữ nguyên scale thật của texture, không stretch theo kích thước chi tiết.
# - Căn TÂM một tile texture vào tâm mặt ván để các tấm cùng vật liệu có mật độ vân đồng đều.
# - Nhãn preview tách rõ KHỔ TẤM và KÍCH THƯỚC CHI TIẾT.

module TranTuanNoiThat
  module Grain
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.3.0'.freeze

    MIGRATION_KEY_V330 = 'v330_sheet_migrated'.freeze unless const_defined?(:MIGRATION_KEY_V330, false)

    class << self
      def ensure_v330_defaults
        return true if Sketchup.read_default(PREF, MIGRATION_KEY_V330, false) == true

        old_l = Sketchup.read_default(PREF, 'board_length_mm', 2440.0).to_f
        old_w = Sketchup.read_default(PREF, 'board_width_mm', 1220.0).to_f

        # Chỉ đổi đúng bộ mặc định cũ; khổ người dùng tự nhập được giữ nguyên.
        if (old_l - 2440.0).abs < 0.01 && (old_w - 1220.0).abs < 0.01
          Sketchup.write_default(PREF, 'board_length_mm', 2800.0)
          Sketchup.write_default(PREF, 'board_width_mm', 1220.0)
        end

        Sketchup.write_default(PREF, MIGRATION_KEY_V330, true)
        true
      rescue StandardError => error
        puts "[TT Grain V3.3.0 migrate] #{error.class}: #{error.message}"
        false
      end

      def board_length_mm
        ensure_v330_defaults
        pref_number('board_length_mm', 2800.0)
      end

      def board_width_mm
        ensure_v330_defaults
        pref_number('board_width_mm', 1220.0)
      end

      def save_settings(l, w, t, mode)
        length = [[l.to_f, 1.0].max, 10000.0].min
        width  = [[w.to_f, 1.0].max, 10000.0].min
        length, width = [length, width].max, [length, width].min
        thickness = [[t.to_f, 1.0].max, 500.0].min
        mode = %w[auto length width].include?(mode.to_s) ? mode.to_s : 'auto'

        Sketchup.write_default(PREF, 'board_length_mm', length)
        Sketchup.write_default(PREF, 'board_width_mm', width)
        Sketchup.write_default(PREF, 'max_thickness_mm', thickness)
        Sketchup.write_default(PREF, 'lock_mode', mode)
        Sketchup.write_default(PREF, MIGRATION_KEY_V330, true)

        @active_tool.receive_settings(length, width, thickness, mode) if @active_tool
        true
      end

      def activate
        ensure_v330_defaults
        tool = Tool.new
        @active_tool = tool
        Sketchup.active_model.select_tool(tool)
      end
    end

    class Tool
      private

      def texture_dimensions(material)
        texture = material && material.texture
        raise 'Vật liệu không có texture.' unless texture

        u = texture.width.to_f.abs
        v = texture.height.to_f.abs
        raise 'Kích thước texture không hợp lệ.' if u <= 0.0001 || v <= 0.0001

        [u, v]
      end

      def position_face(face, material, front, analysis)
        u_len, v_len = texture_dimensions(material)

        grain = AXES[analysis[:grain_axis]].clone
        grain.reverse! if analysis[:grain_sign].to_i < 0
        cross = AXES[analysis[:cross_axis]].clone

        grain.normalize! if grain.length > 0.0001
        cross.normalize! if cross.length > 0.0001

        # Tâm tile nằm đúng tâm mặt. Không scale texture theo chiều dài/rộng chi tiết.
        center = face.bounds.center.project_to_plane(face.plane)
        origin = center.offset(grain, -u_len * 0.5).offset(cross, -v_len * 0.5)

        p1 = origin
        p2 = origin.offset(grain, u_len)
        p3 = origin.offset(cross, v_len)

        q1 = Geom::Point3d.new(0, 0, 0)
        q2 = Geom::Point3d.new(u_len, 0, 0)
        q3 = Geom::Point3d.new(0, v_len, 0)

        face.position_material(material, [p1, q1, p2, q2, p3, q3], front)
      rescue StandardError => error
        puts "[TT Grain V3.3.0 position] #{error.class}: #{error.message}"
        raise
      end

      def save_metadata(target, material, analysis, mode)
        super
        target.set_attribute(DICT, 'sheet_length_mm', @sheet_l)
        target.set_attribute(DICT, 'sheet_width_mm', @sheet_w)
        target.set_attribute(DICT, 'texture_align', 'center_keep_scale')
        target.set_attribute(DICT, 'version', VERSION)
        target.set_attribute(ABF, 'grain_sheet_length_mm', @sheet_l)
        target.set_attribute(ABF, 'grain_sheet_width_mm', @sheet_w)
      end

      def draw_label(view)
        p = bounds(@target).center.transform(@target_tr)
        s = view.screen_coords(p)
        mode = @free ? "TỰ DO #{(@free_sign < 0 ? '-' : '+')}#{AXIS_NAMES[@analysis[:grain_axis]]}" : 'AUTO'
        sheet = "TẤM #{@sheet_l.round(0)}×#{@sheet_w.round(0)}"
        part = "CT #{@analysis[:grain_size_mm].round(1)}×#{@analysis[:cross_size_mm].round(1)}"
        fit = @analysis[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'
        lock = locked? ? ' · KHÓA' : ''
        text = "#{mode} · #{sheet} · #{part} · #{fit}#{lock}"
        view.draw_text(s, text, size: 14, bold: true, color: Sketchup::Color.new(255, 120, 40))
      rescue StandardError
        nil
      end
    end
  end
end
