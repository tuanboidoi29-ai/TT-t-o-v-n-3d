# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN V3.4.0
# CHUẨN TỶ LỆ VÂN 2440x1220 + KHÔNG KHÓA MÀU VÀO FACE
# - Tỷ lệ texture luôn tham chiếu 1 tấm chuẩn 2440x1220 mm, tấm lớn/nhỏ không phóng/thu vân.
# - Khổ AUTO của Grain reset về 2440x1220; chiều dày và luật AUTO vẫn tùy chỉnh.
# - Material kế thừa từ Group/Component chỉ gán tạm để position UV rồi trả Face về nil.
# - Tự gỡ các material từng bị bake xuống Face bởi V3.2.1 nếu vẫn đúng material cũ.
# - Khi đổi material ở Group/Component, màu mới hiển thị bình thường, không bị texture cũ đè.

module TranTuanNoiThat
  module Grain
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.4.0'.freeze

    GRAIN_REFERENCE_LENGTH_MM = 2440.0 unless const_defined?(:GRAIN_REFERENCE_LENGTH_MM, false)
    GRAIN_REFERENCE_WIDTH_MM  = 1220.0 unless const_defined?(:GRAIN_REFERENCE_WIDTH_MM, false)
    MIGRATION_KEY_V340 = 'v340_standard_2440_migrated'.freeze unless const_defined?(:MIGRATION_KEY_V340, false)

    class << self
      def ensure_v340_defaults
        return true if Sketchup.read_default(PREF, MIGRATION_KEY_V340, false) == true

        Sketchup.write_default(PREF, 'board_length_mm', GRAIN_REFERENCE_LENGTH_MM)
        Sketchup.write_default(PREF, 'board_width_mm', GRAIN_REFERENCE_WIDTH_MM)
        Sketchup.write_default(PREF, MIGRATION_KEY_V340, true)
        true
      rescue StandardError => error
        puts "[TT Grain V3.4.0 migrate] #{error.class}: #{error.message}"
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

        if @active_tool
          @active_tool.receive_settings(
            GRAIN_REFERENCE_LENGTH_MM,
            GRAIN_REFERENCE_WIDTH_MM,
            t,
            m
          )
        end
        true
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
            # Material trên Face đã được người dùng đổi riêng: không can thiệp.
            face.set_attribute(FACE_DICT, 'inherited_source', false)
          end
        end
        released
      rescue StandardError => error
        puts "[TT Grain V3.4.0 release] #{error.class}: #{error.message}"
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
        puts "[TT Grain V3.4.0 detect] #{error.class}: #{error.message}"
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

          # Material kế thừa: chỉ gán tạm để SketchUp cho phép position_material.
          # Sau khi UV đã ghi, trả material của Face về nil để Group/Component vẫn đổi màu được.
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

      def position_face(face, material, front, analysis)
        texture = material && material.texture
        raise 'Vật liệu không có texture.' unless texture

        grain = AXES[analysis[:grain_axis]].clone
        grain.reverse! if analysis[:grain_sign].to_i < 0
        cross = AXES[analysis[:cross_axis]].clone
        grain.normalize! if grain.length > 0.0001
        cross.normalize! if cross.length > 0.0001

        ref_u = GRAIN_REFERENCE_LENGTH_MM.mm.to_f
        ref_v = GRAIN_REFERENCE_WIDTH_MM.mm.to_f
        tex_u = texture.width.to_f.abs
        tex_v = texture.height.to_f.abs
        raise 'Kích thước texture không hợp lệ.' if tex_u <= 0.0001 || tex_v <= 0.0001

        center = face.bounds.center.project_to_plane(face.plane)
        origin = center.offset(grain, -ref_u * 0.5).offset(cross, -ref_v * 0.5)

        p1 = origin
        p2 = origin.offset(grain, ref_u)
        p3 = origin.offset(cross, ref_v)

        q1 = Geom::Point3d.new(0, 0, 0)
        q2 = Geom::Point3d.new(tex_u, 0, 0)
        q3 = Geom::Point3d.new(0, tex_v, 0)

        face.position_material(material, [p1, q1, p2, q2, p3, q3], front)
      rescue StandardError => error
        puts "[TT Grain V3.4.0 position] #{error.class}: #{error.message}"
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
        target.set_attribute(DICT, 'texture_align', 'center_fixed_2440x1220')
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
        text = "#{mode} · CHUẨN VÂN 2440×1220 · #{part} · #{fit}#{lock}"
        view.draw_text(
          screen,
          text,
          size: 14,
          bold: true,
          color: Sketchup::Color.new(255, 120, 40)
        )
      rescue StandardError
        nil
      end
    end
  end
end
