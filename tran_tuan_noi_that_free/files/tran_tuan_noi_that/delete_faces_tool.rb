# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  module DeleteFacesTool
    extend self

    def run
      model = Sketchup.active_model
      selection = model.selection.to_a

      targets = selection.select do |entity|
        entity.is_a?(Sketchup::Face) ||
          entity.is_a?(Sketchup::Group) ||
          entity.is_a?(Sketchup::ComponentInstance)
      end

      if targets.empty?
        UI.messagebox(
          "XÓA FACE → GIỮ KHUNG:\n" \
          "Hãy chọn hoặc quét chọn Face / Group / Component trước."
        )
        return false
      end

      stats = {
        faces: 0,
        containers: 0,
        unique: 0
      }

      started = false
      model.start_operation('TT - Xóa Face Giữ Khung', true)
      started = true

      visited = {}

      targets.each do |entity|
        next unless entity.valid?
        process_entity(entity, stats, visited)
      end

      model.commit_operation
      started = false

      Sketchup.set_status_text(
        "Đã XÓA #{stats[:faces]} FACE · giữ Edge/khung · " \
        "#{stats[:containers]} đối tượng · Ctrl+Z hoàn tác.",
        SB_PROMPT
      )
      UI.beep
      true
    rescue StandardError => error
      model.abort_operation if started
      UI.messagebox("XÓA FACE → GIỮ KHUNG:\n#{error.class}: #{error.message}")
      false
    end

    def process_entity(entity, stats, visited)
      return unless entity && entity.valid?

      case entity
      when Sketchup::Face
        erase_face_only(entity, stats)
      when Sketchup::Group, Sketchup::ComponentInstance
        prepare_unique(entity, stats)

        definition = entity.definition
        key = definition.object_id
        return if visited[key]

        visited[key] = true
        stats[:containers] += 1
        process_entities(definition.entities, stats, visited)
      end
    end

    def process_entities(entities, stats, visited)
      # Xử lý container con trước để Component dùng chung được Make Unique
      # trước khi xóa mặt trong definition của nó.
      containers = entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) ||
          entity.is_a?(Sketchup::ComponentInstance)
      end

      containers.each do |container|
        next unless container.valid?
        process_entity(container, stats, visited)
      end

      # Chụp danh sách Face trước khi erase để không sửa collection khi đang lặp.
      faces = entities.grep(Sketchup::Face).to_a
      faces.each do |face|
        next unless face.valid?
        erase_face_only(face, stats)
      end
    end

    def erase_face_only(face, stats)
      return unless face && face.valid?

      # Chỉ erase Face. Boundary Edge không bị gọi erase nên khung dây được giữ.
      face.erase!
      stats[:faces] += 1
    end

    def prepare_unique(entity, stats)
      return unless entity.respond_to?(:definition)
      definition = entity.definition
      return unless definition
      return unless definition.instances.length > 1
      return unless entity.respond_to?(:make_unique)

      entity.make_unique
      stats[:unique] += 1
    rescue StandardError => error
      puts "[TT DeleteFaces unique] #{error.class}: #{error.message}"
    end
  end
end
