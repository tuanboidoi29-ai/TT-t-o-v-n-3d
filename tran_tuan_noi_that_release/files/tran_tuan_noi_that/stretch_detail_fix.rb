# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CO GIÃN KHỐI MODE V0.8.0
# TRUE 3D DETAIL STRETCH FIX
#
# Khác với V0.7.0:
# - Không coi Group crossing P1 là cụm cứng để MOVE nguyên khối.
# - Nếu P1 cắt qua Group/Component, đi vào geometry thật của nó.
# - Chỉ các vertex nằm trong nửa không gian phía P2 mới dịch theo delta.
# - Vertex phía P1 giữ nguyên -> chi tiết được kéo dài/ngắn thật.
# - Group/Component nằm hoàn toàn phía P2 vẫn MOVE nguyên khối (đúng bản chất stretch).
# - Không dùng vùng chọn 2D/camera để chọn vertex; toàn bộ phép chọn theo Model Axis 3D.
# - Nested Group/Component crossing P1 được xử lý đệ quy, mỗi instance đúng một lần.

require 'sketchup.rb'

module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.8.0'.freeze

    class Tool
      # TRUE STRETCH TREE:
      # - fixed: không đổi
      # - selected hoàn toàn: move nguyên instance
      # - crossing: KHÔNG move parent; đi vào raw geometry + children
      def collect_entity_actions(entity, parent_to_root, root_vector, region, actions, keys)
        return unless entity.valid? && selectable?(entity)

        key = [entity_key(entity), region[:axis], region[:side_sign], region[:cut_coord].round(6)]
        return if keys[key]

        bb = instance_bounds_root(entity, parent_to_root)
        return unless bb

        relation = halfspace_relation(bb, region)
        return if relation == :fixed

        if relation == :selected
          add_move_instance(entity, parent_to_root, root_vector, actions, keys, key)
          return
        end

        # CROSSING P1: tuyệt đối không MOVE parent.
        # Tách definition dùng chung trước khi sửa geometry bên trong.
        ensure_unique(entity)

        entities = child_entities(entity)
        entity_to_root = parent_to_root * entity.transformation
        raw_edges = entities.grep(Sketchup::Edge).select(&:valid?)
        children = entities.to_a.select { |e| e.valid? && selectable?(e) }

        unless raw_edges.empty?
          collect_raw_geometry_action(
            entity,
            entities,
            raw_edges,
            entity_to_root,
            root_vector,
            region,
            actions,
            keys,
            key
          )
        end

        # Nested crossing/selected được xử lý riêng trong cùng hệ tọa độ root.
        children.each do |child|
          collect_entity_actions(
            child,
            entity_to_root,
            root_vector,
            region,
            actions,
            keys
          )
        end
      end

      # TRUE DETAIL STRETCH:
      # raw geometry crossing P1 => dịch MỌI vertex thuộc phía P2,
      # không chỉ mặt extreme. Điều này giữ đúng các lỗ/rãnh/biên phụ nằm phía kéo.
      def collect_raw_geometry_action(_entity, entities, edges, entity_to_root, root_vector, region, actions, keys, key)
        bb = raw_bounds_root(edges, entity_to_root)
        return unless bb

        relation = halfspace_relation(bb, region)
        return if relation == :fixed

        vertices = edges.flat_map(&:vertices).select(&:valid?).uniq
        return if vertices.empty?

        selected_vertices = if relation == :selected
                              vertices
                            else
                              vertices.select do |vertex|
                                root_point = vertex.position.transform(entity_to_root)
                                selected_coord?(coord(root_point, region[:axis]), region)
                              end
                            end

        return if selected_vertices.empty?

        local_vector = root_vector.transform(entity_to_root.inverse)
        actions << {
          kind: :move_vertices,
          entities: entities,
          vertices: selected_vertices,
          vector: local_vector
        }
        keys[key] = true
      end
    end
  end
end
