# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN V3.2.1
# FIX NHẬN DIỆN MAP MÀU / TEXTURE MATERIAL
# - Ưu tiên material có texture ở Face trước/sau.
# - Nhận texture gán ở Group/Component hiện tại và các cấp cha trong pick path.
# - Quét batch truyền material kế thừa xuống Group/Component con.
# - Khi texture kế thừa, cho phép bake material vào đúng mặt chính trước khi position_material.

module TranTuanNoiThat
  module Grain
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.2.1'.freeze

    class Tool
      private

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
        @material = effective_material(@face, @path, @target)
      end

      def effective_material(face, path, target = nil)
        candidates = []
        add_material_candidate(candidates, face.material, :face_front) if face
        add_material_candidate(candidates, face.back_material, :face_back) if face

        path.to_a.select { |e| container?(e) }.reverse_each do |entity|
          source = entity.equal?(target) ? :target : :ancestor
          add_material_candidate(candidates, entity.material, source)
        end

        if target && valid_target?(target)
          analysis = analyze(target, @target_tr)
          if analysis
            main_faces(target, analysis).each do |item|
              add_material_candidate(candidates, item.material, :target_face)
              add_material_candidate(candidates, item.back_material, :target_face_back)
            end
          end

          es = entities(target)
          if es
            es.grep(Sketchup::Face).sort_by { |item| -item.area.to_f }.each do |item|
              add_material_candidate(candidates, item.material, :target_face)
              add_material_candidate(candidates, item.back_material, :target_face_back)
            end
          end
        end

        chosen = candidates.find { |pair| textured?(pair[0]) }
        chosen ||= candidates.first
        @material_source = chosen ? chosen[1] : nil
        chosen ? chosen[0] : nil
      rescue StandardError => error
        puts "[TT Grain material V3.2.1] #{error.class}: #{error.message}"
        @material_source = nil
        nil
      end

      def add_material_candidate(list, material, source)
        return unless material
        key = begin
          material.respond_to?(:persistent_id) ? material.persistent_id : material.object_id
        rescue StandardError
          material.object_id
        end
        return if list.any? do |pair|
          other = pair[0]
          other_key = begin
            other.respond_to?(:persistent_id) ? other.persistent_id : other.object_id
          rescue StandardError
            other.object_id
          end
          other_key == key
        end
        list << [material, source]
      end

      def detect_target_material(target, analysis, inherited_material = nil)
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
      rescue StandardError
        nil
      end

      def map_faces(target, material, analysis)
        faces = main_faces(target, analysis)
        count = 0

        faces.each do |face|
          front_material = face.material
          back_material = face.back_material
          target_material = target.material

          front = same_material?(front_material, material)
          back = same_material?(back_material, material)

          unless front || back
            inherited_source = [:target, :ancestor].include?(@material_source)

            if inherited_source
              if front_material.nil? &&
                 (target_material.nil? || same_material?(target_material, material) || @material_source == :ancestor)
                front = true
              elsif back_material.nil? &&
                    (target_material.nil? || same_material?(target_material, material) || @material_source == :ancestor)
                back = true
              end
            end
          end

          next unless front || back
          use_front = front

          if use_front && face.material.nil?
            face.material = material
            mark_inherited(face, material)
          elsif !use_front && face.back_material.nil?
            face.back_material = material
            mark_inherited(face, material)
          end

          position_face(face, material, use_front, analysis)
          count += 1
        end

        count
      end

      def build_scan
        roots = @model.selection.to_a.select { |e| container?(e) }
        roots = @model.active_entities.to_a.select { |e| container?(e) } if roots.empty?

        out = []
        roots.each do |entity|
          scan_entity(entity, Geom::Transformation.new, out, nil)
        end

        out.uniq do |item|
          item[:target].persistent_id rescue item[:target].entityID
        end
      end

      def scan_entity(entity, parent_tr, out, inherited_material = nil)
        return unless valid_target?(entity)

        tr = parent_tr * entity.transformation
        analysis = analyze(entity, tr)
        visible_inherited = entity.material || inherited_material

        if analysis && analysis[:sizes_mm].min <= @max_t && analysis[:sizes_mm].sort[1] >= 1.0
          detected = detect_target_material(entity, analysis, visible_inherited)
          material = detected ? detected[0] : nil
          source = detected ? detected[1] : nil
          out << {
            target: entity,
            tr: tr,
            analysis: analysis,
            material: material,
            material_source: source,
            ok: !!(material && textured?(material))
          }
        end

        es = entities(entity)
        return unless es
        es.each do |child|
          scan_entity(child, tr, out, visible_inherited) if container?(child)
        end
      rescue StandardError => error
        puts "[TT Grain scan material V3.2.1] #{error.class}: #{error.message}"
      end

      def apply_scan(include_warning)
        list = @scan || []
        @scan = nil
        ok = list.select do |item|
          item[:ok] && (item[:analysis][:fits_sheet] || include_warning)
        end
        return UI.beep if ok.empty?

        applied = 0
        ok.each do |item|
          begin
            @target = item[:target]
            @target_tr = item[:tr]
            @material = item[:material]
            @material_source = item[:material_source]
            @analysis = item[:analysis]
            next if locked?
            apply_target(@target, @target_tr, @material, @analysis, 'batch')
            applied += 1
          rescue StandardError => error
            puts "[TT Grain batch V3.2.1] #{error.class}: #{error.message}"
          end
        end

        Sketchup.set_status_text("Đã áp dụng vân cho #{applied} tấm.", SB_PROMPT)
        @view.invalidate
      end

      def clear_pick
        @target = nil
        @face = nil
        @path = nil
        @material = nil
        @material_source = nil
        @analysis = nil
        @free_axis = nil
        @free_sign = 1
      end
    end
  end
end
