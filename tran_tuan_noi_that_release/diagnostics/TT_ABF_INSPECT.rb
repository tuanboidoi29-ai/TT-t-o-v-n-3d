# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module ABFInspector
    extend self

    def attributes(entity)
      dictionaries = entity.attribute_dictionaries
      return {} unless dictionaries
      dictionaries.each_with_object({}) do |dict, result|
        result[dict.name] = {}
        dict.each_pair { |key, value| result[dict.name][key.to_s] = safe_value(value) }
      end
    rescue StandardError => error
      { '_error' => error.message }
    end

    def safe_value(value)
      case value
      when NilClass, TrueClass, FalseClass, Numeric, String
        value
      when Geom::Point3d, Geom::Vector3d
        value.to_a
      else
        value.to_s
      end
    end

    def entity_info(entity, path, visited)
      base = {
        'path' => path,
        'type' => entity.typename,
        'name' => (entity.respond_to?(:name) ? entity.name.to_s : ''),
        'tag' => (entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s : ''),
        'hidden' => (entity.respond_to?(:hidden?) ? entity.hidden? : false),
        'attributes' => attributes(entity)
      }

      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        definition = entity.definition
        base['definition_name'] = definition.name.to_s
        base['definition_attributes'] = attributes(definition)
        base['bounds_mm'] = [
          entity.bounds.width.to_mm,
          entity.bounds.depth.to_mm,
          entity.bounds.height.to_mm
        ]
        base['solid_volume'] = (entity.respond_to?(:volume) ? entity.volume : nil)
        base['entity_counts'] = definition.entities.group_by(&:typename).transform_values(&:length)
        key = definition.object_id
        unless visited[key]
          visited[key] = true
          base['children'] = definition.entities.map.with_index do |child, index|
            entity_info(child, "#{path}/#{child.typename}[#{index}]", visited)
          end
          visited.delete(key)
        end
      elsif entity.is_a?(Sketchup::Edge)
        base['start_mm'] = entity.start.position.to_a.map { |v| v.to_mm }
        base['end_mm'] = entity.end.position.to_a.map { |v| v.to_mm }
        base['soft'] = entity.soft?
        base['smooth'] = entity.smooth?
        base['faces_count'] = entity.faces.length
      elsif entity.is_a?(Sketchup::Face)
        base['normal'] = entity.normal.to_a
        base['area_mm2'] = entity.area * 25.4 * 25.4
        base['edges_count'] = entity.edges.length
      end
      base
    rescue StandardError => error
      { 'path' => path, 'type' => entity.typename, '_error' => error.message }
    end

    def run
      model = Sketchup.active_model
      report = {
        'model_path' => model.path.to_s,
        'sketchup_version' => Sketchup.version,
        'model_attributes' => attributes(model),
        'layers' => model.layers.map { |layer| { 'name' => layer.name, 'visible' => layer.visible?, 'attributes' => attributes(layer) } },
        'selection' => model.selection.map.with_index { |e, i| entity_info(e, "Selection[#{i}]", {}) },
        'active_entities' => model.active_entities.map.with_index { |e, i| entity_info(e, "Model[#{i}]", {}) }
      }
      desktop = File.join(ENV['USERPROFILE'].to_s, 'Desktop')
      desktop = Dir.home unless File.directory?(desktop)
      path = File.join(desktop, 'TT_ABF_REPORT.json')
      File.open(path, 'wb') { |file| file.write(JSON.pretty_generate(report).encode('UTF-8')) }
      UI.messagebox("Đã xuất báo cáo ABF:\n#{path}\n\nHãy gửi file TT_ABF_REPORT.json cho Codex.")
      path
    rescue StandardError => error
      UI.messagebox("Không xuất được báo cáo ABF:\n#{error.message}")
      nil
    end
  end
end

TranTuanNoiThat::ABFInspector.run
