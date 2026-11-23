# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XUẤT BẢN VẼ LẮP ĐẶT
require 'sketchup.rb'
require 'json'
require 'net/http'
require 'uri'
require 'securerandom'
require 'time'
require 'fileutils'
require 'base64'

module TranTuanNoiThat
  module ModelExport
    extend self

    API_URL = 'https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-model-api'.freeze
    WEB_URL = 'https://tt-kiem-tra-tam-web.vercel.app/'.freeze
    DICT = 'TT_ModelExport'.freeze
    MAX_TRIANGLES_TOTAL = 120000
    MAX_TRIANGLES_PER_OBJECT = 30000
    MAX_TEXTURE_ASSETS = 20
    MAX_TEXTURE_BYTES = 900_000
    MAX_TEXTURE_TOTAL_BYTES = 8_000_000

    def model
      Sketchup.active_model
    end

    def model_uid
      m = model
      value = m.get_attribute(DICT, 'model_uid').to_s
      if value.empty?
        value = SecureRandom.uuid
        m.set_attribute(DICT, 'model_uid', value)
      end
      value
    end

    def entity_uid(entity)
      value = entity.get_attribute(DICT, 'uid').to_s
      if value.empty?
        value = SecureRandom.uuid
        entity.set_attribute(DICT, 'uid', value)
      end
      value
    end

    def visible_entity?(entity)
      return false if entity.respond_to?(:hidden?) && entity.hidden?
      return false if entity.respond_to?(:layer) && entity.layer && entity.layer.respond_to?(:visible?) && !entity.layer.visible?
      true
    rescue StandardError
      true
    end

    def top_level_objects
      m = model
      return [] unless m
      m.entities.to_a.select do |entity|
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
          entity.valid? && visible_entity?(entity)
      end
    end

    def entity_identifier(entity)
      entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
    rescue StandardError
      entity.entityID rescue nil
    end

    def scan_roots
      m = model
      selection = m.selection.to_a
      selected_instances = selection.select do |entity|
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid? && visible_entity?(entity)
      end
      if selection.any?
        raise 'Vùng chọn hiện tại không có Group/Component hợp lệ. Hãy chọn Group hoặc Component cần xuất.' if selected_instances.empty?
        selected_ids = selected_instances.map { |entity| entity_identifier(entity) }
        selected_instances.reject do |entity|
          parent = entity.parent
          parent.respond_to?(:instances) && parent.instances.any? { |ancestor| selected_ids.include?(entity_identifier(ancestor)) }
        end
      else
        top_level_objects
      end
    end

    def rgb_hex(material, fallback = '#F2F2F2')
      return fallback unless material && material.respond_to?(:color) && material.color
      c = material.color
      format('#%02X%02X%02X', c.red.to_i, c.green.to_i, c.blue.to_i)
    rescue StandardError
      fallback
    end

    def default_face_color(option, fallback)
      value = model.rendering_options[option] rescue nil
      return fallback unless value && value.respond_to?(:red)
      format('#%02X%02X%02X', value.red.to_i, value.green.to_i, value.blue.to_i)
    rescue StandardError
      fallback
    end

    def material_name(entity)
      material = entity.material
      if !material && entity.respond_to?(:definition)
        entity.definition.entities.each do |child|
          next unless child.is_a?(Sketchup::Face)
          material = child.material || child.back_material
          break if material
        end
      end
      material ? material.display_name.to_s : ''
    rescue StandardError
      ''
    end

    def entity_name(entity)
      value = entity.name.to_s.strip
      value = entity.definition.name.to_s.strip if value.empty? && entity.respond_to?(:definition)
      value.empty? ? (entity.is_a?(Sketchup::Group) ? 'Group' : 'Component') : value
    rescue StandardError
      'Đối tượng SketchUp'
    end

    def bounds_corners(entity, transform = Geom::Transformation.new)
      b = entity.bounds
      8.times.map do |i|
        p = transform * b.corner(i)
        [(p.x.to_f * 25.4).round(2), (p.y.to_f * 25.4).round(2), (p.z.to_f * 25.4).round(2)]
      end
    end

    def bounds_dimensions(entity)
      b = entity.bounds
      [(b.width.to_f * 25.4).round(1), (b.depth.to_f * 25.4).round(1), (b.height.to_f * 25.4).round(1)]
    end

    # Vật liệu gán ở Group/Component không nằm trên Face; phải lấy ảnh từ Material.texture
    # và chuẩn hóa UV theo kích thước texture để giữ đúng vân gỗ khi xuất ra Web.
    def texture_mapping_for_face(face, material, front, texture_assets, inherited_material = false, texture_owner = nil)
      return [nil, nil, nil] unless material && material.respond_to?(:texture) && material.texture
      key = material.object_id.to_s
      writer = Sketchup.create_texture_writer
      if inherited_material && texture_owner
        # Nạp Group/Component sở hữu vật liệu để SketchUp giải đúng texture kế thừa.
        writer.load(texture_owner)
        uv_helper = face.get_UVHelper(front, !front, writer)
        write_texture = proc { |file| writer.write(texture_owner, file) == 0 }
      else
        writer.load(face, front)
        uv_helper = face.get_UVHelper(front, !front, writer)
        write_texture = proc { |file| writer.write(face, front, file) == 0 }
      end

      unless texture_assets.key?(key)
        current_bytes = texture_assets.values.inject(0) { |sum, item| sum + item['bytes'].to_i }
        if texture_assets.length < MAX_TEXTURE_ASSETS && current_bytes < MAX_TEXTURE_TOTAL_BYTES
          path = File.join(Sketchup.temp_dir, "tt_model_texture_#{SecureRandom.hex(8)}.png")
          written = write_texture.call(path)
          if written && File.file?(path)
            bytes = File.binread(path)
            if bytes.bytesize <= MAX_TEXTURE_BYTES && current_bytes + bytes.bytesize <= MAX_TEXTURE_TOTAL_BYTES
              texture_assets[key] = {
                'id' => "tt_tex_#{texture_assets.length + 1}",
                'data' => 'data:image/png;base64,' + Base64.strict_encode64(bytes),
                'bytes' => bytes.bytesize
              }
            end
          end
        end
      end
      entry = texture_assets[key]
      [entry && entry['id'], uv_helper, nil]
    rescue StandardError
      [nil, nil, nil]
    ensure
      File.delete(path) if path && File.file?(path)
    end

    def uv_for_point(helper, point, front, scale = nil)
      return nil unless helper
      uvq = front ? helper.get_front_UVQ(point) : helper.get_back_UVQ(point)
      q = uvq.z.to_f
      return nil if q.abs < 0.0000001
      u = uvq.x.to_f / q
      v = uvq.y.to_f / q
      u *= scale[0] if scale
      v *= scale[1] if scale
      [u, v]
    rescue StandardError
      nil
    end

    def material_profile(entity, inherited_material = nil, depth = 0, counts = nil)
      counts ||= { 'textured' => 0, 'colored' => 0, 'unassigned' => 0, 'names' => [] }
      return counts if depth > 40
      current_material = entity.material || inherited_material
      entity.definition.entities.each do |child|
        if child.is_a?(Sketchup::Face)
          [child.material || current_material, child.back_material || current_material].each do |mat|
            if mat
              name = mat.display_name.to_s
              counts['names'] << name unless counts['names'].include?(name)
              if mat.respond_to?(:texture) && mat.texture
                counts['textured'] += 1
              else
                counts['colored'] += 1
              end
            else
              counts['unassigned'] += 1
            end
          end
        elsif child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          next unless child.valid? && visible_entity?(child)
          material_profile(child, child.material || current_material, depth + 1, counts)
        end
      end
      counts
    rescue StandardError
      counts || { 'textured' => 0, 'colored' => 0, 'unassigned' => 0, 'names' => [] }
    end

    def material_profile_label(profile)
      textured = profile['textured'].to_i
      colored = profile['colored'].to_i
      unassigned = profile['unassigned'].to_i
      return 'CHƯA GÁN VẬT LIỆU' if textured + colored == 0
      return 'VẬT LIỆU CÓ VÂN / TEXTURE' if textured > 0 && colored == 0 && unassigned == 0
      return 'CÓ MÀU ĐƠN SẮC' if textured == 0 && colored > 0 && unassigned == 0
      'HỖN HỢP: CÓ VÂN, MÀU VÀ/HOẶC MẶT CHƯA GÁN'
    end

    def mesh_triangles(instance, parent_transform, output, limit, inherited_material = nil, inherited_tag = nil, texture_assets = {}, inherited_material_source = nil)
      return output if output.length >= limit
      transform = parent_transform * instance.transformation
      inherited = instance.material || inherited_material
      inherited_source = instance.material ? instance : inherited_material_source
      default_layer = model.layers[0]
      instance_layer = instance.layer
      current_tag = (instance_layer && instance_layer != default_layer) ? instance_layer.name.to_s : inherited_tag
      instance.definition.entities.each do |child|
        break if output.length >= limit
        next unless visible_entity?(child)
        if child.is_a?(Sketchup::Face)
          begin
            mesh = child.mesh(0)
            points = mesh.points
            front_material = child.material || inherited
            back_material = child.back_material || inherited
            front_color = rgb_hex(front_material, default_face_color('FaceFrontColor', '#F2F2F2'))
            back_color = rgb_hex(back_material, default_face_color('FaceBackColor', '#B8C7D9'))
            front_inherited = child.material.nil? && !inherited.nil?
            back_inherited = child.back_material.nil? && !inherited.nil?
            front_texture_id, front_uv_helper, front_uv_scale = texture_mapping_for_face(child, front_material, true, texture_assets, front_inherited, inherited_source)
            back_texture_id, back_uv_helper, back_uv_scale = texture_mapping_for_face(child, back_material, false, texture_assets, back_inherited, inherited_source)
            face_layer = child.layer
            face_tag = (face_layer && face_layer != default_layer) ? face_layer.name.to_s : current_tag.to_s
            mesh.polygons.each do |polygon|
              break if output.length >= limit
              indices = polygon.map { |index| index.abs - 1 }.select { |index| index >= 0 && index < points.length }
              next if indices.length < 3
              base = transform * points[indices[0]]
              (1...(indices.length - 1)).each do |i|
                break if output.length >= limit
                p2 = transform * points[indices[i]]
                p3 = transform * points[indices[i + 1]]
                point_a = points[indices[0]]
                point_b = points[indices[i]]
                point_c = points[indices[i + 1]]
                front_uv = [uv_for_point(front_uv_helper, point_a, true, front_uv_scale), uv_for_point(front_uv_helper, point_b, true, front_uv_scale), uv_for_point(front_uv_helper, point_c, true, front_uv_scale)]
                back_uv = [uv_for_point(back_uv_helper, point_a, false, back_uv_scale), uv_for_point(back_uv_helper, point_b, false, back_uv_scale), uv_for_point(back_uv_helper, point_c, false, back_uv_scale)]
                output << {
                  'v' => [
                    [(base.x.to_f * 25.4).round(2), (base.y.to_f * 25.4).round(2), (base.z.to_f * 25.4).round(2)],
                    [(p2.x.to_f * 25.4).round(2), (p2.y.to_f * 25.4).round(2), (p2.z.to_f * 25.4).round(2)],
                    [(p3.x.to_f * 25.4).round(2), (p3.y.to_f * 25.4).round(2), (p3.z.to_f * 25.4).round(2)]
                  ],
                  'c' => front_color,
                  'bc' => back_color,
                  'uv' => (front_uv.all? ? front_uv : nil),
                  'buv' => (back_uv.all? ? back_uv : nil),
                  'tex' => front_texture_id,
                  'btex' => back_texture_id,
                  'tag' => face_tag
                }
              end
            end
          rescue StandardError
            next
          end
        elsif child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          mesh_triangles(child, transform, output, limit, inherited, current_tag, texture_assets, inherited_source)
        end
      end
      output
    rescue StandardError
      output
    end

    def scan_model(include_mesh = true)
      m = model
      raise 'Không có model SketchUp đang mở.' unless m
      roots = scan_roots
      raise 'Không tìm thấy Group/Component đang hiển thị trong model.' if roots.empty?
      root_transform = m.selection.empty? ? Geom::Transformation.new : m.edit_transform

      m.start_operation('Quét sâu dữ liệu Model', true)
      begin
        model_uid
        roots.each { |entity| assign_nested_uids(entity, 0) }
        m.commit_operation
      rescue StandardError
        m.abort_operation rescue nil
        raise
      end

      remaining = MAX_TRIANGLES_TOTAL
      texture_assets = {}
      records = []
      group_tree = []
      roots.each do |root|
        cap = [remaining, MAX_TRIANGLES_PER_OBJECT].min
        triangles = include_mesh && cap > 0 ? mesh_triangles(root, root_transform, [], cap, nil, nil, texture_assets) : []
        remaining -= triangles.length
        root_record, tree_node, descendants = scan_instance_tree(root, nil, entity_name(root), 0, root_transform, triangles)
        records.concat([root_record] + descendants)
        group_tree << tree_node
      end

      board_records = records.select { |r| r['is_board'] }
      {
        'model_uid' => model_uid,
        'model_name' => model_title,
        'scanned_at' => Time.now.utc.iso8601,
        'object_count' => records.length,
        'root_count' => roots.length,
        'board_count' => board_records.length,
        'triangle_count' => records.inject(0) { |sum, item| sum + item['triangle_count'].to_i },
        'objects' => records.map { |r| r.reject { |k, _| k == 'triangles' } },
        'model3d' => records,
        'textures' => texture_assets.values.each_with_object({}) { |item, hash| hash[item['id']] = item['data'] },
        'group_tree' => group_tree,
        'panels' => board_records.map { |r| panel_payload(r) }
      }
    end

    def assign_nested_uids(entity, depth)
      return if depth > 40
      entity_uid(entity)
      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.entities.each do |child|
          next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          next unless child.valid? && visible_entity?(child)
          assign_nested_uids(child, depth + 1)
        end
      end
    end

    def scan_instance_tree(entity, parent_uid, parent_path, depth, parent_transform, root_triangles = [], inherited_material = nil)
      base_uid = entity_uid(entity)
      uid = parent_uid ? "#{parent_uid}:#{base_uid}" : base_uid
      world_transform = parent_transform * entity.transformation
      effective_material = entity.material || inherited_material
      profile = material_profile(entity, effective_material)
      profile_label = material_profile_label(profile)
      child_instances = entity.definition.entities.to_a.select do |child|
        (child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)) &&
          child.valid? && visible_entity?(child)
      end
      record = {
        'uid' => uid,
        'parent_uid' => parent_uid,
        'depth' => depth,
        'path' => parent_path,
        'name' => entity_name(entity),
        'type' => entity.is_a?(Sketchup::Group) ? 'Group' : 'Component',
        'tag' => (entity.layer.name.to_s rescue ''),
        'material' => (profile['names'].join(', ').empty? ? material_name(entity) : profile['names'].join(', ')),
        'material_status' => profile_label,
        'material_textures' => profile['textured'],
        'material_colors' => profile['colored'],
        'material_unassigned' => profile['unassigned'],
        'material_names' => profile['names'],
        'dimensions' => bounds_dimensions(entity),
        'corners' => bounds_corners(entity, parent_transform),
        'persistent_id' => (entity.persistent_id rescue nil),
        'child_count' => child_instances.length,
        'is_board' => child_instances.empty?,
        'triangles' => depth.zero? ? root_triangles : [],
        'triangle_count' => depth.zero? ? root_triangles.length : 0
      }
      node = {
        'uid' => uid, 'name' => entity_name(entity), 'path' => parent_path,
        'type' => record['type'], 'dimensions' => record['dimensions'],
        'tag' => record['tag'], 'material' => record['material'],
        'material_status' => record['material_status'],
        'material_textures' => record['material_textures'],
        'material_colors' => record['material_colors'],
        'material_unassigned' => record['material_unassigned'],
        'material_names' => record['material_names'],
        'boards' => [], 'children' => [], 'board_count' => 0
      }
      descendants = []
      child_instances.each do |child|
        child_path = parent_path + ' / ' + entity_name(child)
        child_record, child_node, nested_records = scan_instance_tree(child, uid, child_path, depth + 1, world_transform, [], effective_material)
        descendants << child_record
        descendants.concat(nested_records)
        if child_node['boards'].empty? && child_node['children'].empty?
          node['boards'] << panel_payload(child_record) if child_record['is_board']
        else
          node['children'] << child_node
        end
        node['board_count'] += child_node['board_count'].to_i
        node['board_count'] += 1 if child_record['is_board']
      end
      node['board_count'] = node['boards'].length + node['children'].inject(0) { |sum, c| sum + c['board_count'].to_i }
      [record, node, descendants]
    end

    def panel_payload(record)
      {
        'uid' => record['uid'], 'code' => record['uid'], 'name' => record['name'],
        'type' => record['type'], 'dimensions' => record['dimensions'],
        'tag' => record['tag'], 'material' => record['material'], 'material_status' => record['material_status'],
        'material_textures' => record['material_textures'], 'material_colors' => record['material_colors'],
        'material_unassigned' => record['material_unassigned'], 'material_names' => record['material_names'],
        'path' => record['path']
      }
    end

    def model_title
      m = model
      path = m && m.path.to_s
      return File.basename(path, File.extname(path)) unless path.empty?
      m && m.title.to_s.empty? ? 'SketchUp Model' : m.title.to_s
    rescue StandardError
      'SketchUp Model'
    end

    def share_settings
      m = model
      {
        'share_id' => m.get_attribute(DICT, 'share_id').to_s,
        'write_key' => m.get_attribute(DICT, 'write_key').to_s,
        'project_login' => m.get_attribute(DICT, 'project_login').to_s
      }
    end

    def persist_share_settings(share_id, write_key, login)
      m = model
      m.start_operation('Lưu cấu hình đồng bộ Model', true)
      begin
        m.set_attribute(DICT, 'share_id', share_id)
        m.set_attribute(DICT, 'write_key', write_key)
        m.set_attribute(DICT, 'project_login', login)
        m.commit_operation
      rescue StandardError
        m.abort_operation rescue nil
        raise
      end
    end

    def sync_to_web(project_name)
      m = model
      raise 'Không có model SketchUp đang mở.' unless m
      login = project_name.to_s.strip
      raise 'Tên dự án hoặc mã dự án phải có ít nhất 3 ký tự.' if login.length < 3

      settings = share_settings
      share_id = settings['share_id']
      write_key = settings['write_key']
      share_id = SecureRandom.hex(12) if share_id.empty?
      write_key = SecureRandom.hex(32) if write_key.empty?
      persist_share_settings(share_id, write_key, login)

      scanned = scan_model
      payload = {
        'model_uid' => scanned['model_uid'],
        'model_name' => scanned['model_name'],
        'objects' => scanned['objects'],
        'model3d' => scanned['model3d'],
        'textures' => scanned['textures'],
        'group_tree' => scanned['group_tree'],
        'panels' => scanned['panels'],
        'labels' => []
      }
      body = {
        'action' => 'sync',
        'share_id' => share_id,
        'write_key' => write_key,
        'project_login' => login,
        'model_uid' => scanned['model_uid'],
        'model_name' => scanned['model_name'],
        'payload' => payload
      }
      response = post_json(API_URL, body)
      raise api_error(response) unless response['ok'] && response['saved']

      {
        'share_id' => share_id,
        'model_name' => scanned['model_name'],
        'object_count' => scanned['object_count'],
        'board_count' => scanned['board_count'],
        'triangle_count' => scanned['triangle_count'],
        'revision' => (response.dig('model', 'revision') rescue nil),
        'url' => WEB_URL + '?id=' + URI.encode_www_form_component(share_id)
      }
    end

    def post_json(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 20
      http.read_timeout = 90
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = JSON.generate(body)
      response = http.request(request)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise 'Máy chủ trả về dữ liệu không hợp lệ.'
    rescue StandardError => e
      raise "Không kết nối được máy chủ đồng bộ: #{e.class}: #{e.message}"
    end

    def api_error(response)
      code = response['error'].to_s
      detail = response['detail'].to_s
      messages = {
        'invalid_write_key' => 'Khóa ghi dữ liệu không hợp lệ.',
        'forbidden' => 'Khóa đồng bộ không khớp với model đã lưu.',
        'project_login_exists' => 'Tên dự án này đã được sử dụng cho một model khác. Hãy dùng mã dự án hoặc tên khác.',
        'project_login_too_short' => 'Tên dự án hoặc mã dự án phải có ít nhất 3 ký tự.',
        'invalid_share_id' => 'Mã chia sẻ model không hợp lệ.'
      }
      messages[code] || (detail.empty? ? "Máy chủ từ chối đồng bộ (#{code})." : detail)
    end

    def export_json
      data = scan_model
      path = UI.savepanel('Xuất bản vẽ lắp đặt', '', 'model_kiem_tra.json')
      return false unless path
      File.write(path, JSON.pretty_generate(data), mode: 'w:UTF-8')
      UI.messagebox("Đã xuất #{data['object_count']} đối tượng ra tệp JSON.")
      true
    rescue StandardError => e
      UI.messagebox("Không xuất được dữ liệu Model:\n#{e.class}: #{e.message}")
      false
    end


    # Quản lý Tags/Layers trực tiếp trong model, không xóa hoặc sửa hình học.
    def tag_inventory
      m = model
      return [] unless m
      m.layers.to_a.sort_by { |tag| tag.name.to_s.downcase }.map do |tag|
        { 'name' => tag.name.to_s, 'visible' => !!tag.visible?, 'active' => (m.active_layer == tag),
          'entity_count' => count_entities_on_tag(m.entities, tag, 0) }
      end
    end

    def count_entities_on_tag(entities, tag, depth)
      return 0 if depth > 30
      entities.to_a.inject(0) do |sum, entity|
        count = (entity.respond_to?(:layer) && entity.layer == tag) ? 1 : 0
        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          count += count_entities_on_tag(entity.definition.entities, tag, depth + 1)
        end
        sum + count
      end
    rescue StandardError
      0
    end

    def set_tag_visibility(name, visible)
      m = model
      tag = m.layers.to_a.find { |item| item.name.to_s == name.to_s }
      raise 'Không tìm thấy Tag/Layer được chọn.' unless tag
      raise 'Không thể ẩn Tag/Layer đang được đặt làm hiện hành.' if !visible && m.active_layer == tag
      m.start_operation(visible ? 'Hiện Tag/Layer' : 'Ẩn Tag/Layer', true)
      begin
        tag.visible = !!visible
        m.commit_operation
      rescue StandardError
        m.abort_operation rescue nil
        raise
      end
      tag_inventory
    end

    def set_all_tags_visibility(visible)
      m = model
      m.start_operation(visible ? 'Hiện tất cả Tags' : 'Ẩn tất cả Tags', true)
      begin
        m.layers.each { |tag| tag.visible = !!visible if visible || m.active_layer != tag }
        m.commit_operation
      rescue StandardError
        m.abort_operation rescue nil
        raise
      end
      tag_inventory
    end

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return true
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'XUẤT BẢN VẼ LẮP ĐẶT',
        preferences_key: 'TranTuanNoiThat.ModelExport',
        scrollable: true, resizable: true,
        width: 1040, height: 760, min_width: 760, min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      @dialog.add_action_callback('model_scan') do |_context|
        begin
          result = scan_model(false)
          # Không gửi lưới tam giác 3D lớn vào HtmlDialog khi chỉ cần danh sách đối tượng.
          # Dữ liệu mesh đầy đủ vẫn được tạo khi Đồng bộ Web hoặc Xuất JSON.
          display_result = result.reject { |key, _| ['model3d', 'panels', 'group_tree'].include?(key) }
          @dialog.execute_script("window.TTModelExport.receiveScan(#{JSON.generate(display_result).gsub('</', '<\\/')})")
        rescue StandardError => e
          @dialog.execute_script("window.TTModelExport.showError(#{e.message.to_s.to_json})")
        end
      end

      @dialog.add_action_callback('model_sync') do |_context, login|
        begin
          result = sync_to_web(login)
          @dialog.execute_script("window.TTModelExport.synced(true, #{JSON.generate(result).gsub('</', '<\\/')})")
        rescue StandardError => e
          @dialog.execute_script("window.TTModelExport.synced(false, #{e.message.to_s.to_json})")
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
      true
    rescue StandardError => e
      UI.messagebox("Không mở được chức năng Xuất bản vẽ lắp đặt:\n#{e.class}: #{e.message}")
      false
    end

    def close
      @dialog.close if @dialog
      @dialog = nil
    rescue StandardError
      nil
    end

    def html
      <<~HTML
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <style>
      *{box-sizing:border-box}body{margin:0;background:#f3f6fa;color:#202a36;font:14px Segoe UI,Arial}header{padding:18px 22px;background:#fff;border-bottom:1px solid #dce3eb;display:flex;justify-content:space-between;align-items:center;gap:12px}h1{font-size:20px;margin:0}.muted{color:#718096;font-size:12px}.wrap{padding:16px;max-width:1300px;margin:auto}.panel{background:#fff;border:1px solid #dfe5ed;border-radius:11px;padding:14px;margin-bottom:12px}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.field{display:block;font-size:12px;color:#59677a;margin-bottom:5px}input{width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:7px;font:inherit}.btn{border:0;border-radius:7px;padding:10px 14px;background:#24384f;color:#fff;cursor:pointer;font-weight:700}.green{background:#137b50}.blue{background:#245fc4}.light{background:#e9eef5;color:#25364b}.btn:disabled{opacity:.55;cursor:wait}.stats{display:flex;gap:8px;flex-wrap:wrap}.stat{background:#f2f5f9;border-radius:8px;padding:8px 12px}.stat b{display:block;font-size:19px}.tablewrap{overflow:auto;max-height:340px}table{width:100%;border-collapse:collapse;font-size:12px}th,td{padding:9px;border-bottom:1px solid #e7ecf2;text-align:left;white-space:nowrap}th{background:#f7f9fc;position:sticky;top:0}.link{overflow-wrap:anywhere;color:#1458ad}.notice{padding:10px;border-radius:8px;background:#eef5ff;color:#31517b;font-size:12px;line-height:1.5}.status{margin-top:9px;font-size:12px;white-space:pre-wrap}.ok{color:#087344}.bad{color:#b42318}@media(max-width:720px){.grid{grid-template-columns:1fr}header{align-items:flex-start;flex-direction:column}}
      </style></head><body>
      <header><div><h1>XUẤT BẢN VẼ LẮP ĐẶT</h1><div class="muted">Tự quét model hoặc chỉ xuất Group / Component đang chọn · Đồng bộ lên Web</div></div></header>
      <main class="wrap">
        <section class="panel">
          <div class="row" style="justify-content:space-between"><div><b>1. QUÉT MODEL / VÙNG ĐANG CHỌN</b><div class="muted">Tự quét khi mở chức năng. Không chọn gì: xuất toàn bộ model đang hiển thị. Có chọn Group / Component: chỉ xuất phần được chọn.</div></div><button id="scanBtn" class="btn green" onclick="scan()">QUÉT LẠI MODEL</button></div>
          <div id="stats" class="stats" style="margin-top:12px"><div class="stat"><b id="count">0</b><span class="muted">Đối tượng</span></div><div class="stat"><b id="triangles">0</b><span class="muted">Mặt tam giác 3D</span></div></div>
          <div class="tablewrap" style="margin-top:12px"><table><thead><tr><th>TÊN ĐỐI TƯỢNG</th><th>LOẠI</th><th>KÍCH THƯỚC (mm)</th><th>TAG</th><th>VẬT LIỆU</th><th>MÃ ĐỊNH DANH</th></tr></thead><tbody id="objects"><tr><td colspan="6" class="muted">Bấm QUÉT MODEL để đọc dữ liệu.</td></tr></tbody></table></div>
        </section>
        <section class="panel">
          <b>2. ĐỒNG BỘ MODEL LÊN WEB</b>
          <p class="muted">Chỉ cần nhập TÊN DỰ ÁN hoặc MÃ DỰ ÁN. Mỗi lần đồng bộ đều tự lưu một phiên bản vào lịch sử hệ thống.</p>
          <div><label class="field">TÊN DỰ ÁN / HOẶC MÃ DỰ ÁN</label><input id="login" autocomplete="off" placeholder="VD: TUAN-NOI-THAT-01 hoặc mã dự án"></div>
          <div class="row" style="margin-top:12px"><button id="syncBtn" class="btn green" onclick="sync()">ĐỒNG BỘ MODEL & TẠO LINK</button><span class="muted">Model sẽ được cập nhật theo lần đồng bộ mới nhất.</span></div>
          <div id="result" class="status"></div>
          <div id="linkBox" class="notice" style="display:none;margin-top:10px"><b>LINK XEM MODEL</b><div id="webLink" class="link"></div><div class="row" style="margin-top:8px"><button class="btn light" onclick="copyLink()">Sao chép link</button></div></div>
        </section>
        <section class="notice">Lưu ý: Sau khi đồng bộ, hãy lưu file SKP để giữ mã dự án và mã định danh đối tượng. Trình xem Web hiển thị hình học 3D đã quét, danh sách đối tượng và QR riêng từng đối tượng. Cần Internet khi đồng bộ và khi mở Web.</section>
      </main>
      <script>
      var lastLink='';
      window.addEventListener('load',function(){scan()});

      function scan(){document.getElementById('scanBtn').disabled=true;document.getElementById('objects').innerHTML='<tr><td colspan="6">Đang quét model...</td></tr>';sketchup.model_scan()}
      function receiveScan(d){document.getElementById('scanBtn').disabled=false;document.getElementById('count').textContent=d.object_count||0;document.getElementById('triangles').textContent=d.triangle_count||0;var rows=d.objects||[];document.getElementById('objects').innerHTML=rows.map(function(o){return '<tr><td>'+esc(o.name)+'</td><td>'+esc(o.type)+'</td><td>'+esc((o.dimensions||[]).join(' × '))+'</td><td>'+esc(o.tag)+'</td><td>'+esc(o.material)+'</td><td>'+esc(o.uid)+'</td></tr>'}).join('')||'<tr><td colspan="6">Không có đối tượng.</td></tr>';document.getElementById('result').textContent='Đã quét '+(d.object_count||0)+' đối tượng.';document.getElementById('result').className='status ok'}
      function showError(s){document.getElementById('scanBtn').disabled=false;document.getElementById('result').textContent=s;document.getElementById('result').className='status bad'}
      function sync(){var login=document.getElementById('login').value.trim();if(!login)return showError('Nhập Tên dự án hoặc Mã dự án.');document.getElementById('syncBtn').disabled=true;document.getElementById('result').textContent='Đang quét sâu Group lồng nhau và đồng bộ lên Web...';document.getElementById('result').className='status';sketchup.model_sync(login)}
      function synced(ok,d){document.getElementById('syncBtn').disabled=false;if(!ok){showError(d);return}lastLink=d.url;document.getElementById('linkBox').style.display='block';document.getElementById('webLink').textContent=d.url;document.getElementById('result').textContent='Đã đồng bộ '+d.object_count+' Group/Component · '+d.board_count+' ván · '+d.triangle_count+' tam giác · Revision '+d.revision+' (đã lưu lịch sử)';document.getElementById('result').className='status ok'}
      function copyLink(){if(!lastLink)return;var t=document.createElement('textarea');t.value=lastLink;document.body.appendChild(t);t.select();document.execCommand('copy');t.remove();document.getElementById('result').textContent='Đã sao chép link.'}
      function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
      window.TTModelExport={receiveScan:receiveScan,showError:showError,synced:synced};
      </script></body></html>
      HTML
    end
  end
end
