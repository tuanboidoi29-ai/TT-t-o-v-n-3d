# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  module MaterialReset
    extend self

    DICT = 'TT_XOA_VAT_LIEU'.freeze

    def run
      model = Sketchup.active_model
      selection = model.selection.to_a

      if selection.empty?
        UI.messagebox(
          "XÓA VẬT LIỆU → MẶC ĐỊNH:\n" \
          "Hãy chọn Face / Group / Component cần xóa vật liệu trước."
        )
        return false
      end

      targets = selection.select do |entity|
        entity.is_a?(Sketchup::Face) ||
          entity.is_a?(Sketchup::Group) ||
          entity.is_a?(Sketchup::ComponentInstance)
      end

      if targets.empty?
        UI.messagebox(
          "Không có Face / Group / Component hợp lệ trong vùng chọn."
        )
        return false
      end

      stats = {
        faces: 0,
        containers: 0,
        components_unique: 0
      }

      started = false
      model.start_operation('TT - Xóa vật liệu về mặc định', true)
      started = true

      visited_definitions = {}

      targets.each do |entity|
        reset_entity(entity, stats, visited_definitions)
      end

      model.commit_operation
      started = false

      Sketchup.set_status_text(
        "Đã xóa vật liệu về MẶC ĐỊNH · " \
        "#{stats[:faces]} Face · #{stats[:containers]} Group/Component · Ctrl+Z hoàn tác.",
        SB_PROMPT
      )
      UI.beep
      true
    rescue StandardError => error
      model.abort_operation if started
      UI.messagebox("XÓA VẬT LIỆU:\n#{error.class}: #{error.message}")
      false
    end

    def reset_entity(entity, stats, visited_definitions)
      return unless entity && entity.valid?

      case entity
      when Sketchup::Face
        clear_face(entity, stats)
      when Sketchup::Group
        clear_container_material(entity, stats)
        reset_entities(entity.entities, stats, visited_definitions)
      when Sketchup::ComponentInstance
        make_component_unique(entity, stats)
        clear_container_material(entity, stats)

        definition = entity.definition
        key = definition.object_id
        return if visited_definitions[key]

        visited_definitions[key] = true
        reset_entities(definition.entities, stats, visited_definitions)
      end
    end

    def reset_entities(entities, stats, visited_definitions)
      entities.each do |entity|
        case entity
        when Sketchup::Face
          clear_face(entity, stats)
        when Sketchup::Group
          clear_container_material(entity, stats)
          reset_entities(entity.entities, stats, visited_definitions)
        when Sketchup::ComponentInstance
          make_component_unique(entity, stats)
          clear_container_material(entity, stats)

          definition = entity.definition
          key = definition.object_id
          next if visited_definitions[key]

          visited_definitions[key] = true
          reset_entities(definition.entities, stats, visited_definitions)
        end
      end
    end

    def clear_face(face, stats)
      changed = false

      if face.material
        face.material = nil
        changed = true
      end

      if face.back_material
        face.back_material = nil
        changed = true
      end

      stats[:faces] += 1 if changed
    end

    def clear_container_material(entity, stats)
      return unless entity.respond_to?(:material)
      return unless entity.material

      entity.material = nil
      stats[:containers] += 1
    end

    def make_component_unique(instance, stats)
      return unless instance.is_a?(Sketchup::ComponentInstance)

      definition = instance.definition
      return unless definition
      return unless definition.instances.length > 1

      instance.make_unique
      stats[:components_unique] += 1
    end
  end
end
