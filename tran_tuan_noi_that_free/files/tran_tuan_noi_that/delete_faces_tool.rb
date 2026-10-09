# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  module DeleteFacesTool
    extend self

    GROUP_NAME = 'KHUNG'.freeze
    KEY_PRECISION = 8

    def run
      model = Sketchup.active_model
      context = model.active_entities
      selection = model.selection.to_a

      containers = selection.select do |entity|
        entity.is_a?(Sketchup::Group) ||
          entity.is_a?(Sketchup::ComponentInstance)
      end

      loose_faces = selection.grep(Sketchup::Face)

      if containers.empty? && loose_faces.empty?
        UI.messagebox(
          "XÓA FACE → GIỮ KHUNG:\n" \
          "Hãy chọn hoặc quét chọn Face / Group / Component trước."
        )
        return false
      end

      stats = {
        faces: 0,
        groups: 0,
        edges: 0
      }

      created = []
      started = false

      model.start_operation('TT - Xóa Face Giữ Khung', true)
      started = true

      # Mỗi Group/Component được thay bằng đúng 1 Group KHUNG chứa Edge.
      containers.each do |entity|
        next unless entity.valid?
        next unless context.include?(entity)

        group = convert_container_to_wire_group(
          context,
          entity,
          stats
        )
        created << group if group && group.valid?
      end

      # Các Face rời đang chọn được gom vào một Group KHUNG riêng.
      loose_faces = loose_faces.select do |face|
        face.valid? && context.include?(face)
      end

      unless loose_faces.empty?
        group = convert_loose_faces_to_wire_group(
          context,
          loose_faces,
          stats
        )
        created << group if group && group.valid?
      end

      model.selection.clear
      created.each do |group|
        model.selection.add(group) if group && group.valid?
      end

      model.commit_operation
      started = false

      Sketchup.set_status_text(
        "Đã XÓA #{stats[:faces]} FACE · tạo #{stats[:groups]} GROUP KHUNG · " \
        "#{stats[:edges]} Edge · Ctrl+Z hoàn tác.",
        SB_PROMPT
      )
      UI.beep
      true
    rescue StandardError => error
      model.abort_operation if started
      UI.messagebox(
        "XÓA FACE → GIỮ KHUNG:\n#{error.class}: #{error.message}"
      )
      false
    end

    def convert_container_to_wire_group(parent_entities, entity, stats)
      original_name = entity.respond_to?(:name) ? entity.name.to_s : ''
      original_layer = entity.layer if entity.respond_to?(:layer)
      original_transform = entity.transformation

      data = []
      seen = {}

      collect_wire_data(
        entity.definition.entities,
        Geom::Transformation.new,
        data,
        seen,
        stats
      )

      raise 'Đối tượng không có Edge để tạo khung.' if data.empty?

      # Xóa đúng đối tượng được chọn; Component khác dùng chung definition
      # không bị chỉnh sửa vì ta không đụng vào definition gốc.
      entity.erase!

      group = parent_entities.add_group
      group.transformation = original_transform
      group.name = frame_name(original_name)
      group.layer = original_layer if original_layer

      write_wire_data(group.entities, data, stats)
      stats[:groups] += 1
      group
    end

    def convert_loose_faces_to_wire_group(parent_entities, faces, stats)
      data = []
      seen = {}
      source_edges = []

      faces.each do |face|
        next unless face.valid?

        stats[:faces] += 1
        face.edges.each do |edge|
          next unless edge.valid?
          source_edges << edge
          add_edge_data(
            edge,
            Geom::Transformation.new,
            data,
            seen
          )
        end
      end

      raise 'Face được chọn không có Edge để tạo khung.' if data.empty?

      group = parent_entities.add_group
      group.name = GROUP_NAME
      write_wire_data(group.entities, data, stats)

      # Xóa Face thật.
      faces.each do |face|
        face.erase! if face.valid?
      end

      # Edge rời không còn thuộc Face nào thì bỏ khỏi context cũ,
      # vì bản sao Edge đã nằm trong GROUP KHUNG.
      source_edges.uniq.each do |edge|
        next unless edge.valid?
        next unless edge.faces.empty?
        edge.erase!
      end

      stats[:groups] += 1
      group
    end

    def collect_wire_data(entities, transform, data, seen, stats)
      entities.each do |entity|
        case entity
        when Sketchup::Edge
          add_edge_data(entity, transform, data, seen)
        when Sketchup::Face
          stats[:faces] += 1
        when Sketchup::Group, Sketchup::ComponentInstance
          child_transform = transform * entity.transformation
          collect_wire_data(
            entity.definition.entities,
            child_transform,
            data,
            seen,
            stats
          )
        end
      end
    end

    def add_edge_data(edge, transform, data, seen)
      p1 = edge.start.position.transform(transform)
      p2 = edge.end.position.transform(transform)
      return if p1.distance(p2) <= 1.0e-8

      key = edge_key(p1, p2)
      return if seen[key]
      seen[key] = true

      data << {
        p1: p1,
        p2: p2,
        soft: edge.soft?,
        smooth: edge.smooth?,
        hidden: edge.hidden?,
        layer: edge.layer
      }
    end

    def write_wire_data(entities, data, stats)
      data.each do |item|
        edge = entities.add_line(item[:p1], item[:p2])
        next unless edge

        edge.soft = item[:soft] if edge.respond_to?(:soft=)
        edge.smooth = item[:smooth] if edge.respond_to?(:smooth=)
        edge.hidden = item[:hidden] if edge.respond_to?(:hidden=)
        edge.layer = item[:layer] if item[:layer]

        stats[:edges] += 1
      end
    end

    def edge_key(p1, p2)
      a = point_key(p1)
      b = point_key(p2)
      a <= b ? "#{a}|#{b}" : "#{b}|#{a}"
    end

    def point_key(point)
      [
        point.x.to_f.round(KEY_PRECISION),
        point.y.to_f.round(KEY_PRECISION),
        point.z.to_f.round(KEY_PRECISION)
      ].join(',')
    end

    def frame_name(original_name)
      name = original_name.to_s.strip
      return GROUP_NAME if name.empty?
      return name if name.upcase.start_with?('KHUNG')
      "#{GROUP_NAME} - #{name}"
    end
  end
end
