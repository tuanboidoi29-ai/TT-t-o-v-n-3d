# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'fileutils'

module TranTuanNoiThat
  module LibraryTool
    extend self

    VERSION = '1.9.118'.freeze
    DICT = 'TT_LIBRARY'.freeze
    SOURCE_KEY = 'library_sources_json'.freeze
    AUTO_SYNC_KEY = 'library_auto_sync'.freeze
    CACHE_ROOT = File.join(TranTuanNoiThat::ROOT, 'library_cache').freeze

    BUILTINS = {
      'hoi_dung' => {
        'name' => 'Ván hồi đứng',
        'category' => 'Tấm ván',
        'defaults' => {
          'depth' => 600.0, 'height' => 720.0, 'thickness' => 17.5
        },
        'fields' => %w[depth height thickness]
      },
      'dot_ngang' => {
        'name' => 'Đợt ngang',
        'category' => 'Tấm ván',
        'defaults' => {
          'width' => 764.0, 'depth' => 550.0, 'thickness' => 17.5
        },
        'fields' => %w[width depth thickness]
      },
      'tu_bep_duoi' => {
        'name' => 'Khung tủ bếp dưới',
        'category' => 'Tủ bếp',
        'defaults' => {
          'width' => 800.0, 'depth' => 580.0, 'height' => 820.0,
          'thickness' => 17.5, 'back' => 9.0, 'toe' => 100.0
        },
        'fields' => %w[width depth height thickness back toe]
      },
      'tu_bep_tren' => {
        'name' => 'Khung tủ bếp trên',
        'category' => 'Tủ bếp',
        'defaults' => {
          'width' => 800.0, 'depth' => 350.0, 'height' => 720.0,
          'thickness' => 17.5, 'back' => 9.0
        },
        'fields' => %w[width depth height thickness back]
      },
      'khung_tu_ao' => {
        'name' => 'Khung tủ áo',
        'category' => 'Tủ áo',
        'defaults' => {
          'width' => 1200.0, 'depth' => 600.0, 'height' => 2400.0,
          'thickness' => 17.5, 'back' => 9.0, 'shelves' => 2
        },
        'fields' => %w[width depth height thickness back shelves]
      }
    }.freeze

    FIELD_LABELS = {
      'width' => 'Rộng',
      'depth' => 'Sâu',
      'height' => 'Cao',
      'thickness' => 'Dày ván',
      'back' => 'Dày hậu',
      'toe' => 'Chân / bệ',
      'shelves' => 'Số đợt'
    }.freeze

    def show
      FileUtils.mkdir_p(CACHE_ROOT)
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        sync_ui
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TT - THƯ VIỆN NỘI THẤT',
        preferences_key: 'TranTuanNoiThat.Library.118',
        scrollable: true,
        resizable: true,
        width: 900,
        height: 720,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)

      @dialog.add_action_callback('ready') do |_ctx|
        sync_ui
        schedule_auto_sync
      end

      @dialog.add_action_callback('place_builtin') do |_ctx, template_id, json|
        begin
          params = sanitize_params(template_id.to_s, JSON.parse(json.to_s))
          Sketchup.active_model.select_tool(PlacementTool.new(template_id.to_s, params))
        rescue StandardError => error
          notify("Không thể đặt mẫu: #{error.message}", 'error')
        end
      end

      @dialog.add_action_callback('selected_params') do |_ctx|
        send_selected_params
      end

      @dialog.add_action_callback('update_selected') do |_ctx, template_id, json|
        begin
          params = sanitize_params(template_id.to_s, JSON.parse(json.to_s))
          update_selected_component(template_id.to_s, params)
        rescue StandardError => error
          notify("Không sửa được component: #{error.message}", 'error')
        end
      end

      @dialog.add_action_callback('import_local') do |_ctx|
        import_local_skp
      end

      @dialog.add_action_callback('add_source') do |_ctx, url|
        begin
          add_source(url.to_s)
          sync_ui
          notify('Đã thêm nguồn thư viện.', 'ok')
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('remove_source') do |_ctx, url|
        remove_source(url.to_s)
        sync_ui
      end

      @dialog.add_action_callback('sync_sources') do |_ctx|
        sync_sources(true)
      end

      @dialog.add_action_callback('set_auto_sync') do |_ctx, enabled|
        Sketchup.write_default(TranTuanNoiThat::NAME, AUTO_SYNC_KEY, enabled == true || enabled.to_s == 'true')
        sync_ui
      end

      @dialog.add_action_callback('place_remote') do |_ctx, item_id|
        begin
          place_remote(item_id.to_s)
        rescue StandardError => error
          notify("Không đặt được mẫu ngoài: #{error.message}", 'error')
        end
      end

      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    rescue StandardError => error
      UI.messagebox("Không mở được Thư viện Nội thất:\n#{error.message}")
    end

    def schedule_auto_sync
      return unless auto_sync?
      return if sources.empty?
      UI.start_timer(0.2, false) { sync_sources(false) }
    rescue StandardError
    end

    def auto_sync?
      value = Sketchup.read_default(TranTuanNoiThat::NAME, AUTO_SYNC_KEY, true)
      value == true || value.to_s == 'true'
    end

    def sources
      raw = Sketchup.read_default(TranTuanNoiThat::NAME, SOURCE_KEY, '[]').to_s
      list = JSON.parse(raw)
      list.is_a?(Array) ? list.map(&:to_s).uniq : []
    rescue StandardError
      []
    end

    def save_sources(list)
      Sketchup.write_default(TranTuanNoiThat::NAME, SOURCE_KEY, JSON.generate(list.map(&:to_s).uniq))
    end

    def add_source(url)
      uri = URI.parse(url.to_s.strip)
      raise 'Nguồn thư viện phải là HTTPS.' unless uri.is_a?(URI::HTTPS)
      list = sources
      list << uri.to_s unless list.include?(uri.to_s)
      save_sources(list)
      true
    rescue URI::InvalidURIError
      raise 'URL nguồn thư viện không hợp lệ.'
    end

    def remove_source(url)
      save_sources(sources.reject { |item| item == url.to_s })
      true
    end

    def builtin_payload
      BUILTINS.map do |id, spec|
        {
          id: id,
          name: spec['name'],
          category: spec['category'],
          defaults: spec['defaults'],
          fields: spec['fields'].map do |field|
            {
              key: field,
              label: FIELD_LABELS[field] || field,
              unit: field == 'shelves' ? '' : 'mm'
            }
          end
        }
      end
    end

    def sync_ui
      return unless @dialog && @dialog.visible?
      payload = {
        builtins: builtin_payload,
        sources: sources,
        auto_sync: auto_sync?,
        remote_items: Array(@remote_items).map do |item|
          {
            id: item['id'],
            name: item['name'],
            category: item['category'],
            version: item['version'],
            source_name: item['source_name']
          }
        end
      }
      @dialog.execute_script("TT.setState(#{JSON.generate(payload)});")
    rescue StandardError => error
      warn "[TT Library UI] #{error.class}: #{error.message}"
    end

    def notify(message, kind = 'ok')
      if @dialog && @dialog.visible?
        @dialog.execute_script("TT.notice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind.to_s)});")
      else
        UI.messagebox(message.to_s)
      end
    rescue StandardError
      UI.messagebox(message.to_s) rescue nil
    end

    def sanitize_params(template_id, input)
      spec = BUILTINS[template_id]
      raise 'Mẫu thư viện không hợp lệ.' unless spec
      src = input.is_a?(Hash) ? input : {}
      out = spec['defaults'].dup
      spec['fields'].each do |field|
        value = src.key?(field) ? src[field] : out[field]
        if field == 'shelves'
          value = value.to_i
          value = 0 if value < 0
          value = 20 if value > 20
        else
          value = value.to_f
          value = spec['defaults'][field].to_f unless value > 0.0
        end
        out[field] = value
      end
      validate_dimensions(template_id, out)
      out
    end

    def validate_dimensions(template_id, p)
      t = p['thickness'].to_f
      raise 'Độ dày ván phải lớn hơn 0.' unless t > 0.0
      if p['width'] && p['width'].to_f <= t * 2.0
        raise 'Chiều rộng quá nhỏ so với độ dày ván.'
      end
      if p['depth'] && p['depth'].to_f <= t
        raise 'Chiều sâu quá nhỏ.'
      end
      if p['height'] && p['height'].to_f <= t * 2.0 && !%w[hoi_dung].include?(template_id)
        raise 'Chiều cao quá nhỏ.'
      end
      true
    end

    def component_signature(template_id, params)
      values = params.keys.sort.map { |key| "#{key}=#{params[key]}" }.join('|')
      Digest::SHA256.hexdigest("#{template_id}|#{values}")[0, 10]
    end

    def definition_name(template_id, params)
      "#{BUILTINS.fetch(template_id).fetch('name')} [TT #{component_signature(template_id, params)}]"
    end

    def create_builtin_instance(template_id, params, point)
      model = Sketchup.active_model
      model.start_operation('TT - Đặt mẫu thư viện', true)
      started = true

      definition = model.definitions.add(definition_name(template_id, params))
      build_definition(definition, template_id, params)
      instance = model.active_entities.add_instance(definition, Geom::Transformation.translation(point))
      write_instance_attributes(instance, template_id, params)

      model.commit_operation
      started = false
      instance
    rescue StandardError
      model.abort_operation if started rescue nil
      raise
    end

    def update_selected_component(template_id, params)
      model = Sketchup.active_model
      instance = model.selection.to_a.find { |entity| entity.is_a?(Sketchup::ComponentInstance) }
      raise 'Hãy chọn 1 Component thuộc Thư viện TT.' unless instance
      current_id = instance.get_attribute(DICT, 'template_id', instance.definition.get_attribute(DICT, 'template_id', nil))
      raise 'Component đang chọn không thuộc Thư viện TT.' unless current_id
      raise 'Loại mẫu không khớp component đang chọn.' unless current_id.to_s == template_id.to_s

      model.start_operation('TT - Sửa component thư viện', true)
      started = true
      instance.make_unique if instance.respond_to?(:make_unique) && instance.definition.instances.length > 1
      definition = instance.definition
      definition.entities.erase_entities(definition.entities.to_a) unless definition.entities.empty?
      build_definition(definition, template_id, params)
      write_instance_attributes(instance, template_id, params)
      instance.name = BUILTINS[template_id]['name']

      model.commit_operation
      started = false
      notify('Đã cập nhật thông số component. Ctrl+Z để hoàn tác.', 'ok')
      send_selected_params
      true
    rescue StandardError
      model.abort_operation if started rescue nil
      raise
    end

    def send_selected_params
      model = Sketchup.active_model
      instance = model.selection.to_a.find { |entity| entity.is_a?(Sketchup::ComponentInstance) }
      unless instance
        notify('Hãy chọn một Component thư viện trong model.', 'warn')
        return false
      end
      template_id = instance.get_attribute(DICT, 'template_id', instance.definition.get_attribute(DICT, 'template_id', nil))
      unless BUILTINS.key?(template_id.to_s)
        notify('Component đang chọn không phải mẫu tham số của Thư viện TT.', 'warn')
        return false
      end
      params_json = instance.get_attribute(DICT, 'params_json', instance.definition.get_attribute(DICT, 'params_json', '{}'))
      params = JSON.parse(params_json.to_s)
      @dialog.execute_script("TT.loadSelected(#{JSON.generate({template_id: template_id, params: params})});") if @dialog
      true
    rescue StandardError => error
      notify(error.message, 'error')
      false
    end

    def write_instance_attributes(instance, template_id, params)
      [instance, instance.definition].each do |target|
        target.set_attribute(DICT, 'template_id', template_id)
        target.set_attribute(DICT, 'template_version', VERSION)
        target.set_attribute(DICT, 'params_json', JSON.generate(params))
        target.set_attribute(DICT, 'source', 'builtin')
        target.set_attribute('dynamic_attributes', '_name', BUILTINS[template_id]['name'])
        params.each do |key, value|
          target.set_attribute('dynamic_attributes', "tt_#{key}", value)
        end
      end
      instance.name = BUILTINS[template_id]['name']
    end

    def build_definition(definition, template_id, params)
      definition.set_attribute(DICT, 'template_id', template_id)
      definition.set_attribute(DICT, 'template_version', VERSION)
      definition.set_attribute(DICT, 'params_json', JSON.generate(params))
      entities = definition.entities

      case template_id
      when 'hoi_dung'
        add_board(entities, 'Hồi đứng', 0, 0, 0, params['thickness'], params['depth'], params['height'], params['thickness'])
      when 'dot_ngang'
        add_board(entities, 'Đợt ngang', 0, 0, 0, params['width'], params['depth'], params['thickness'], params['thickness'])
      when 'tu_bep_duoi'
        build_base_cabinet(entities, params)
      when 'tu_bep_tren'
        build_upper_cabinet(entities, params)
      when 'khung_tu_ao'
        build_wardrobe(entities, params)
      else
        raise 'Chưa hỗ trợ mẫu này.'
      end
      definition
    end

    def add_board(parent, name, x, y, z, sx, sy, sz, board_t)
      sx = sx.to_f
      sy = sy.to_f
      sz = sz.to_f
      raise "Kích thước #{name} không hợp lệ." unless sx > 0 && sy > 0 && sz > 0

      group = parent.add_group
      group.name = name
      e = group.entities
      p0 = Geom::Point3d.new(x.to_f.mm, y.to_f.mm, z.to_f.mm)
      p1 = Geom::Point3d.new((x + sx).to_f.mm, y.to_f.mm, z.to_f.mm)
      p2 = Geom::Point3d.new((x + sx).to_f.mm, (y + sy).to_f.mm, z.to_f.mm)
      p3 = Geom::Point3d.new(x.to_f.mm, (y + sy).to_f.mm, z.to_f.mm)
      face = e.add_face(p0, p1, p2, p3)
      raise "Không tạo được #{name}." unless face
      face.reverse! if face.normal.z < 0
      face.pushpull(sz.to_f.mm)

      group.set_attribute(DICT, 'role', name)
      group.set_attribute(DICT, 'board_thickness_mm', board_t.to_f)
      group.set_attribute(DICT, 'is_board', true)

      begin
        tag_name = "Ván #{format_number(board_t)}mm"
        group.layer = Sketchup.active_model.layers[tag_name] || Sketchup.active_model.layers.add(tag_name)
      rescue StandardError
      end
      group
    end

    def build_base_cabinet(e, p)
      w, d, h, t = p.values_at('width', 'depth', 'height', 'thickness').map(&:to_f)
      back = p['back'].to_f
      toe = p['toe'].to_f
      inner_w = w - 2.0 * t
      body_h = h - toe
      raise 'Thông số tủ bếp dưới không hợp lệ.' unless inner_w > 0 && body_h > t * 2

      add_board(e, 'Hồi trái', 0, 0, toe, t, d, body_h, t)
      add_board(e, 'Hồi phải', w - t, 0, toe, t, d, body_h, t)
      add_board(e, 'Đáy', t, 0, toe, inner_w, d, t, t)
      rail_depth = [80.0, d / 3.0].min
      add_board(e, 'Giằng trên trước', t, 0, h - t, inner_w, rail_depth, t, t)
      add_board(e, 'Giằng trên sau', t, d - rail_depth, h - t, inner_w, rail_depth, t, t)
      add_board(e, 'Hậu', t, d - back, toe + t, inner_w, back, h - toe - t, back) if back > 0
    end

    def build_upper_cabinet(e, p)
      w, d, h, t = p.values_at('width', 'depth', 'height', 'thickness').map(&:to_f)
      back = p['back'].to_f
      inner_w = w - 2.0 * t
      raise 'Thông số tủ bếp trên không hợp lệ.' unless inner_w > 0 && h > t * 2

      add_board(e, 'Hồi trái', 0, 0, 0, t, d, h, t)
      add_board(e, 'Hồi phải', w - t, 0, 0, t, d, h, t)
      add_board(e, 'Đáy', t, 0, 0, inner_w, d, t, t)
      add_board(e, 'Nóc', t, 0, h - t, inner_w, d, t, t)
      add_board(e, 'Hậu', t, d - back, t, inner_w, back, h - 2.0 * t, back) if back > 0
    end

    def build_wardrobe(e, p)
      w, d, h, t = p.values_at('width', 'depth', 'height', 'thickness').map(&:to_f)
      back = p['back'].to_f
      shelves = p['shelves'].to_i
      inner_w = w - 2.0 * t
      raise 'Thông số khung tủ áo không hợp lệ.' unless inner_w > 0 && h > t * 2

      add_board(e, 'Hồi trái', 0, 0, 0, t, d, h, t)
      add_board(e, 'Hồi phải', w - t, 0, 0, t, d, h, t)
      add_board(e, 'Đáy', t, 0, 0, inner_w, d, t, t)
      add_board(e, 'Nóc', t, 0, h - t, inner_w, d, t, t)
      add_board(e, 'Hậu', t, d - back, t, inner_w, back, h - 2.0 * t, back) if back > 0

      if shelves > 0
        clear_h = h - 2.0 * t
        step = clear_h / (shelves + 1).to_f
        shelves.times do |index|
          z = t + step * (index + 1)
          add_board(e, "Đợt #{index + 1}", t, 0, z, inner_w, d - back, t, t)
        end
      end
    end

    def preview_dimensions(template_id, params)
      case template_id
      when 'hoi_dung'
        [params['thickness'], params['depth'], params['height']]
      when 'dot_ngang'
        [params['width'], params['depth'], params['thickness']]
      else
        [params['width'], params['depth'], params['height']]
      end.map(&:to_f)
    end

    def import_local_skp
      path = UI.openpanel('Nạp mẫu SketchUp vào thư viện', '', 'SketchUp (*.skp)|*.skp||')
      return false unless path
      definition = Sketchup.active_model.definitions.load(path)
      raise 'Không nạp được file SKP.' unless definition
      Sketchup.active_model.select_tool(PlacementTool.new(nil, nil, definition))
      notify("Đã nạp #{File.basename(path)}. Click trong model để đặt.", 'ok')
      true
    rescue StandardError => error
      notify("Nạp SKP lỗi: #{error.message}", 'error')
      false
    end

    def sync_sources(interactive)
      list = sources
      if list.empty?
        notify('Chưa có nguồn thư viện ngoài. Hãy thêm URL manifest HTTPS.', 'warn') if interactive
        return false
      end

      items = {}
      errors = []
      list.each do |source_url|
        begin
          manifest = fetch_json(source_url)
          source_name = manifest['name'].to_s.strip
          source_name = URI.parse(source_url).host if source_name.empty?
          remote_items = manifest['items']
          raise 'Manifest không có items.' unless remote_items.is_a?(Array)

          remote_items.each do |item|
            validated = validate_remote_item(item, source_name)
            old = items[validated['id']]
            if old.nil? || version_tuple(validated['version']) > version_tuple(old['version'])
              items[validated['id']] = validated
            end
          end
        rescue StandardError => error
          errors << "#{source_url}: #{error.message}"
        end
      end

      synced = []
      items.values.each do |item|
        begin
          ensure_cached(item)
          synced << item
        rescue StandardError => error
          errors << "#{item['name']}: #{error.message}"
        end
      end

      @remote_items = synced.sort_by { |item| [item['category'].to_s, item['name'].to_s] }
      sync_ui

      if interactive
        message = "Đã đồng bộ #{@remote_items.length} mẫu ngoài."
        message += "\n#{errors.length} lỗi nguồn/tệp." unless errors.empty?
        notify(message, errors.empty? ? 'ok' : 'warn')
      end
      true
    end

    def validate_remote_item(item, source_name)
      raise 'Item nguồn không hợp lệ.' unless item.is_a?(Hash)
      id = item['id'].to_s
      name = item['name'].to_s.strip
      version = item['version'].to_s
      url = item['url'].to_s
      sha = item['sha256'].to_s.downcase
      raise 'ID mẫu không hợp lệ.' unless id.match?(/\A[a-zA-Z0-9_.-]+\z/)
      raise 'Thiếu tên mẫu.' if name.empty?
      raise 'Version mẫu phải dạng x.y.z.' unless version.match?(/\A\d+\.\d+\.\d+\z/)
      uri = URI.parse(url)
      raise 'Mẫu phải dùng URL HTTPS.' unless uri.is_a?(URI::HTTPS)
      raise 'Thiếu SHA256 mẫu.' unless sha.match?(/\A[0-9a-f]{64}\z/)
      {
        'id' => id,
        'name' => name,
        'category' => item['category'].to_s.empty? ? 'Ngoài' : item['category'].to_s,
        'version' => version,
        'url' => url,
        'sha256' => sha,
        'source_name' => source_name
      }
    rescue URI::InvalidURIError
      raise 'URL mẫu không hợp lệ.'
    end

    def version_tuple(version)
      version.to_s.split('.').map(&:to_i)
    end

    def cache_path(item)
      safe_id = item['id'].gsub(/[^a-zA-Z0-9_.-]/, '_')
      safe_version = item['version'].gsub(/[^0-9.]/, '_')
      File.join(CACHE_ROOT, "#{safe_id}_#{safe_version}.skp")
    end

    def ensure_cached(item)
      FileUtils.mkdir_p(CACHE_ROOT)
      path = cache_path(item)
      if File.file?(path) && Digest::SHA256.file(path).hexdigest == item['sha256']
        item['cache_path'] = path
        return path
      end

      bytes = fetch_bytes(item['url'])
      digest = Digest::SHA256.hexdigest(bytes)
      raise 'SHA256 không khớp, không nhận file.' unless digest == item['sha256']
      File.binwrite(path, bytes)
      item['cache_path'] = path
      path
    end

    def place_remote(item_id)
      item = Array(@remote_items).find { |entry| entry['id'].to_s == item_id.to_s }
      raise 'Chưa có mẫu này trong cache. Hãy Đồng bộ nguồn trước.' unless item
      path = ensure_cached(item)
      definition = Sketchup.active_model.definitions.load(path)
      raise 'SketchUp không đọc được SKP đã tải.' unless definition
      definition.set_attribute(DICT, 'source', item['source_name'])
      definition.set_attribute(DICT, 'remote_id', item['id'])
      definition.set_attribute(DICT, 'remote_version', item['version'])
      Sketchup.active_model.select_tool(PlacementTool.new(nil, nil, definition))
      notify("Đã nạp #{item['name']} v#{item['version']}. Click trong model để đặt.", 'ok')
      true
    end

    def fetch_json(url)
      JSON.parse(fetch_bytes(url))
    rescue JSON::ParserError
      raise 'Manifest không phải JSON hợp lệ.'
    end

    def fetch_bytes(url, redirects = 0)
      raise 'Quá nhiều lần chuyển hướng.' if redirects > 3
      uri = URI.parse(url)
      raise 'Chỉ cho phép HTTPS.' unless uri.is_a?(URI::HTTPS)
      request = Net::HTTP::Get.new(uri.request_uri)
      request['User-Agent'] = 'TranTuanNoiThat-Library/1.9.118'

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 15
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        location = response['location'].to_s
        raise 'Redirect không hợp lệ.' if location.empty?
        redirected = URI.join(uri.to_s, location).to_s
        fetch_bytes(redirected, redirects + 1)
      else
        raise "HTTP #{response.code}"
      end
    rescue URI::InvalidURIError
      raise 'URL không hợp lệ.'
    end

    def format_number(value)
      text = format('%.2f', value.to_f)
      text.sub!(/\.00\z/, '')
      text.sub!(/(\.\d)0\z/, '\\1')
      text
    end

    def dialog_html
      <<~'HTML'
        <!doctype html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            *{box-sizing:border-box}
            body{margin:0;font-family:Arial,sans-serif;background:#f3f5f7;color:#1f2937}
            .head{padding:14px 16px;background:#172033;color:#fff;position:sticky;top:0;z-index:5}
            .head h2{margin:0;font-size:19px}.head small{opacity:.8}
            .wrap{padding:14px}.tabs{display:flex;gap:7px;margin-bottom:12px}
            .tabs button{background:#dce3ed;color:#26354b}.tabs button.active{background:#176fd1;color:#fff}
            .panel{display:none}.panel.active{display:block}
            .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(205px,1fr));gap:10px}
            .card{background:#fff;border:1px solid #d8dee8;border-radius:9px;padding:12px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
            .card h3{font-size:15px;margin:0 0 5px}.cat{font-size:11px;color:#6b7280}
            .card.selected{outline:2px solid #176fd1}
            button{border:0;border-radius:6px;padding:8px 11px;font-weight:bold;cursor:pointer;background:#176fd1;color:#fff}
            button.gray{background:#64748b}.green{background:#15803d}.orange{background:#c66a12}
            .editor{margin-top:12px;background:#fff;border:1px solid #d8dee8;border-radius:9px;padding:12px}
            .grid{display:grid;grid-template-columns:150px 120px 40px;gap:7px;align-items:center}
            input{width:100%;padding:8px;border:1px solid #bdc5d0;border-radius:6px}
            .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:10px}
            .source{background:#fff;border:1px solid #d8dee8;border-radius:7px;padding:9px;margin-bottom:7px;display:flex;gap:8px;align-items:center}
            .source code{flex:1;font-size:11px;overflow-wrap:anywhere}
            .notice{display:none;margin-top:10px;padding:9px;border-radius:6px;white-space:pre-wrap;font-size:13px}
            .notice.ok{display:block;background:#e5f5eb;color:#166534}.notice.warn{display:block;background:#fff4d6;color:#7c5700}.notice.error{display:block;background:#fde8e8;color:#8c2222}
            .hint{font-size:12px;line-height:1.55;color:#657080;margin-top:9px}
            .remoteItem{display:flex;justify-content:space-between;gap:8px;align-items:center;border-bottom:1px solid #edf0f4;padding:8px 0}
          </style>
        </head>
        <body>
          <div class="head">
            <h2>THƯ VIỆN NỘI THẤT</h2>
            <small>Component tham số · SKP từ máy · đồng bộ nguồn ngoài</small>
          </div>
          <div class="wrap">
            <div class="tabs">
              <button id="tabBuiltin" class="active" onclick="openTab('builtin')">Mẫu tham số</button>
              <button id="tabRemote" onclick="openTab('remote')">Nguồn ngoài</button>
            </div>

            <div id="builtin" class="panel active">
              <div id="cards" class="cards"></div>
              <div class="editor">
                <b id="editorTitle">Chọn một mẫu</b>
                <div id="fields" class="grid" style="margin-top:10px"></div>
                <div class="row">
                  <button class="green" onclick="place()">ĐẶT COMPONENT</button>
                  <button class="gray" onclick="sketchup.selected_params()">Lấy component đang chọn</button>
                  <button class="orange" onclick="updateSelected()">Cập nhật component đang chọn</button>
                </div>
                <div class="hint">Khi bấm Đặt Component, rê chuột trong model để xem preview khung 3D rồi click để đặt. ESC kết thúc.</div>
              </div>
            </div>

            <div id="remote" class="panel">
              <div class="editor">
                <b>Nguồn thư viện HTTPS</b>
                <div class="row">
                  <input id="sourceUrl" placeholder="https://.../library.json" style="flex:1;min-width:420px">
                  <button onclick="addSource()">Thêm nguồn</button>
                  <button class="green" onclick="sketchup.sync_sources()">Đồng bộ ngay</button>
                  <button class="gray" onclick="sketchup.import_local()">Nạp SKP từ máy</button>
                </div>
                <div class="row">
                  <label><input id="autoSync" type="checkbox" style="width:auto" onchange="sketchup.set_auto_sync(this.checked)"> Tự đồng bộ khi mở Thư viện</label>
                </div>
                <div class="hint">Manifest nguồn: JSON có name và items[]. Mỗi item cần id, name, category, version x.y.z, url HTTPS tới file SKP và sha256. Nguồn cần đăng nhập/API riêng phải cung cấp adapter hoặc link tải được phép.</div>
                <div id="sources" style="margin-top:10px"></div>
              </div>
              <div class="editor">
                <b>Mẫu đã đồng bộ</b>
                <div id="remoteItems"></div>
              </div>
            </div>
            <div id="notice" class="notice"></div>
          </div>

          <script>
            const TT={state:{builtins:[],sources:[],remote_items:[],auto_sync:true},selected:null,
              setState(s){this.state=s||this.state;renderAll();},
              notice(msg,kind){const e=document.getElementById('notice');e.className='notice '+(kind||'ok');e.textContent=msg||'';},
              loadSelected(data){openTab('builtin');selectCard(data.template_id);for(const [k,v] of Object.entries(data.params||{})){const el=document.getElementById('f_'+k);if(el)el.value=v;}this.notice('Đã lấy thông số component đang chọn.','ok');}
            };
            function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}
            function openTab(id){for(const x of ['builtin','remote'])document.getElementById(x).classList.toggle('active',x===id);document.getElementById('tabBuiltin').classList.toggle('active',id==='builtin');document.getElementById('tabRemote').classList.toggle('active',id==='remote');}
            function renderAll(){renderCards();renderSources();renderRemote();document.getElementById('autoSync').checked=!!TT.state.auto_sync;if(!TT.selected&&TT.state.builtins.length)selectCard(TT.state.builtins[0].id);}
            function renderCards(){document.getElementById('cards').innerHTML=(TT.state.builtins||[]).map(x=>'<div class="card '+(TT.selected===x.id?'selected':'')+'" onclick="selectCard(\''+x.id+'\')"><h3>'+esc(x.name)+'</h3><div class="cat">'+esc(x.category)+'</div></div>').join('');}
            function selectCard(id){TT.selected=id;const x=(TT.state.builtins||[]).find(a=>a.id===id);if(!x)return;document.getElementById('editorTitle').textContent=x.name;document.getElementById('fields').innerHTML=x.fields.map(f=>'<label>'+esc(f.label)+'</label><input id="f_'+f.key+'" type="number" step="'+(f.key==='shelves'?'1':'0.5')+'" value="'+esc(x.defaults[f.key])+'"><span>'+esc(f.unit)+'</span>').join('');renderCards();}
            function values(){const x=(TT.state.builtins||[]).find(a=>a.id===TT.selected);const o={};for(const f of (x?.fields||[]))o[f.key]=Number(document.getElementById('f_'+f.key).value);return o;}
            function place(){if(TT.selected)sketchup.place_builtin(TT.selected,JSON.stringify(values()));}
            function updateSelected(){if(TT.selected)sketchup.update_selected(TT.selected,JSON.stringify(values()));}
            function addSource(){const e=document.getElementById('sourceUrl');if(e.value.trim()){sketchup.add_source(e.value.trim());e.value='';}}
            function renderSources(){document.getElementById('sources').innerHTML=(TT.state.sources||[]).map(url=>'<div class="source"><code>'+esc(url)+'</code><button class="gray" onclick="sketchup.remove_source(\''+String(url).replace(/'/g,"\\'")+'\')">Xóa</button></div>').join('');}
            function renderRemote(){document.getElementById('remoteItems').innerHTML=(TT.state.remote_items||[]).map(x=>'<div class="remoteItem"><div><b>'+esc(x.name)+'</b><br><span class="cat">'+esc(x.category)+' · v'+esc(x.version)+' · '+esc(x.source_name)+'</span></div><button onclick="sketchup.place_remote(\''+x.id+'\')">Đặt</button></div>').join('')||'<div class="hint">Chưa có mẫu ngoài trong cache.</div>';}
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body>
        </html>
      HTML
    end

    class PlacementTool
      def initialize(template_id, params, definition = nil)
        @template_id = template_id
        @params = params
        @definition = definition
        @point = nil
        @ip = Sketchup::InputPoint.new
      end

      def activate
        Sketchup.status_text = 'TT Thư viện: rê chuột xem preview · click để đặt · ESC kết thúc.'
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        if @ip.valid?
          @point = @ip.position
          view.invalidate
        end
      end

      def onLButtonDown(_flags, _x, _y, view)
        return UI.beep unless @point
        if @definition
          place_external
        else
          LibraryTool.create_builtin_instance(@template_id, @params, @point)
        end
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Không đặt được mẫu:\n#{error.message}")
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def draw(view)
        return unless @point
        corners = if @definition
          bounds_corners(@definition.bounds)
        else
          dims = LibraryTool.preview_dimensions(@template_id, @params)
          box_corners(dims[0].mm, dims[1].mm, dims[2].mm)
        end
        translated = corners.map { |p| p + Geom::Vector3d.new(@point.x, @point.y, @point.z) }
        pairs = [[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(241, 150, 170)
        view.draw(GL_LINES, pairs.flat_map { |a,b| [translated[a], translated[b]] })
      end

      def place_external
        model = Sketchup.active_model
        model.start_operation('TT - Đặt mẫu thư viện ngoài', true)
        started = true
        instance = model.active_entities.add_instance(@definition, Geom::Transformation.translation(@point))
        instance.set_attribute(DICT, 'source', @definition.get_attribute(DICT, 'source', 'external'))
        instance.set_attribute(DICT, 'remote_id', @definition.get_attribute(DICT, 'remote_id', nil))
        instance.set_attribute(DICT, 'remote_version', @definition.get_attribute(DICT, 'remote_version', nil))
        model.commit_operation
        started = false
        instance
      rescue StandardError
        model.abort_operation if started rescue nil
        raise
      end

      def bounds_corners(bounds)
        (0..7).map do |index|
          point = bounds.corner(index)
          Geom::Point3d.new(point.x - bounds.min.x, point.y - bounds.min.y, point.z - bounds.min.z)
        end
      end

      def box_corners(x, y, z)
        [
          Geom::Point3d.new(0,0,0), Geom::Point3d.new(x,0,0),
          Geom::Point3d.new(0,y,0), Geom::Point3d.new(x,y,0),
          Geom::Point3d.new(0,0,z), Geom::Point3d.new(x,0,z),
          Geom::Point3d.new(0,y,z), Geom::Point3d.new(x,y,z)
        ]
      end
    end
  end
end
