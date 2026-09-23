# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - TẠO CÁNH CHUẨN
# SketchUp 2021+
#
# Cơ chế:
# - Click P1 -> P2 chéo trên Face bất kỳ; không khóa hướng bắt điểm/trục.
# - P1/P2 bắt điểm tự do, không khóa hướng X/Y/Z; vẫn dùng Endpoint/Edge/Inference tự nhiên.
# - Trong lúc rê P2 có preview 3D tấm cánh theo chuột.
# - Sau P2 chỉ hiện 1 điểm TÂM ở giữa tấm.
# - Bấm TÂM hoặc phím / để +1 cánh trực tiếp; click vùng preview còn lại để tạo.
# - TAB mở thông số; SHIFT đổi Dọc/Ngang; CTRL đổi Lọt/Phủ.
# - Chia 1..8 cánh theo Dọc hoặc Ngang.
# - Tạo xong tự quay về P1 để làm khoang kế tiếp.
# - Một lần tạo = một Undo.

require 'sketchup.rb'
require 'json'
require 'fileutils'

module TranTuanNoiThat
  module DoorStandard
    extend self

    VERSION = '1.9.141'.freeze
    DICT = 'TT_DOOR_STANDARD'.freeze
    SETTINGS_KEY = 'door_standard_settings_v1'.freeze
    PRESETS_KEY = 'door_standard_presets_v1'.freeze
    PRESET_DIR = File.join(TranTuanNoiThat::ROOT, 'data', 'door_standard').freeze
    PRESET_FILE = File.join(PRESET_DIR, 'door_presets.json').freeze

    DEFAULTS = {
      'fit_mode' => 'Lọt lòng',
      'split_direction' => 'Dọc',
      'door_count' => 1,
      'thickness' => 17.5,
      'gap_left' => 2.0,
      'gap_right' => 2.0,
      'gap_top' => 2.0,
      'gap_bottom' => 2.0,
      'gap_middle' => 2.0,
      'gap_vertical' => 2.0,
      'gap_horizontal' => 2.0,
      'over_left' => 0.0,
      'over_right' => 0.0,
      'over_top' => 0.0,
      'over_bottom' => 0.0,
      'offset' => 0.0,
      'name_prefix' => 'Cánh',
      'tag_name' => 'Cánh tủ',
      'preview_alpha' => 88
    }.freeze

    def settings
      raw = Sketchup.read_default(TranTuanNoiThat::NAME, SETTINGS_KEY, '{}').to_s
      parsed = JSON.parse(raw)
      validate(DEFAULTS.merge(parsed.is_a?(Hash) ? parsed : {}))
    rescue StandardError
      DEFAULTS.dup
    end

    def save_settings(value)
      clean = validate(value)
      Sketchup.write_default(TranTuanNoiThat::NAME, SETTINGS_KEY, JSON.generate(clean))
      clean
    end

    def validate(raw)
      source = DEFAULTS.merge(raw || {})
      result = {}

      fit = source['fit_mode'].to_s
      raise 'Lắp đặt chỉ nhận Lọt lòng hoặc Phủ ngoài.' unless ['Lọt lòng', 'Phủ ngoài'].include?(fit)
      result['fit_mode'] = fit

      direction = source['split_direction'].to_s
      raise 'Hướng chia chỉ nhận Dọc hoặc Ngang.' unless ['Dọc', 'Ngang'].include?(direction)
      result['split_direction'] = direction

      count = source['door_count'].to_i
      raise 'Số cánh phải từ 1 đến 64.' unless count.between?(1, 64)
      result['door_count'] = count

      # Tương thích mẫu cũ: gap_middle được dùng làm giá trị mặc định cho cả hai hướng.
      legacy_gap = source['gap_middle']
      source['gap_vertical'] = legacy_gap if source['gap_vertical'].nil?
      source['gap_horizontal'] = legacy_gap if source['gap_horizontal'].nil?

      %w[
        thickness gap_left gap_right gap_top gap_bottom
        gap_vertical gap_horizontal
        over_left over_right over_top over_bottom
      ].each do |key|
        value = Float(source[key].to_s.tr(',', '.'))
        raise "#{key} phải >= 0." if value < 0.0
        raise "#{key} quá lớn." if value > 10_000.0
        result[key] = value
      end
      result['gap_middle'] = legacy_gap.nil? ? result['gap_vertical'] : Float(legacy_gap.to_s.tr(',', '.'))

      offset = Float(source['offset'].to_s.tr(',', '.'))
      raise 'Offset quá lớn.' if offset.abs > 10_000.0
      result['offset'] = offset

      raise 'Dày cánh phải > 0.' unless result['thickness'] > 0.0

      prefix = source['name_prefix'].to_s.strip
      prefix = 'Cánh' if prefix.empty?
      raise 'Tên cánh tối đa 60 ký tự.' if prefix.length > 60
      result['name_prefix'] = prefix

      tag_name = source['tag_name'].to_s.strip
      tag_name = 'Cánh tủ' if tag_name.empty?
      raise 'Tên Tag/Layer tối đa 60 ký tự.' if tag_name.length > 60
      result['tag_name'] = tag_name

      alpha = source['preview_alpha'].to_i
      alpha = 20 if alpha < 20
      alpha = 180 if alpha > 180
      result['preview_alpha'] = alpha

      result
    rescue ArgumentError, TypeError
      raise 'Thông số cánh không hợp lệ.'
    end

    def presets
      FileUtils.mkdir_p(PRESET_DIR)

      if File.file?(PRESET_FILE)
        value = JSON.parse(File.read(PRESET_FILE, encoding: 'UTF-8'))
        return value if value.is_a?(Hash)
      end

      # Tự chuyển các mẫu cũ từng lưu trong SketchUp Preferences sang file JSON thật.
      raw = Sketchup.read_default(TranTuanNoiThat::NAME, PRESETS_KEY, '{}').to_s
      legacy = JSON.parse(raw)
      if legacy.is_a?(Hash) && !legacy.empty?
        save_presets(legacy)
        return legacy
      end

      {}
    rescue StandardError => error
      puts "[TT DoorStandard presets] #{error.class}: #{error.message}"
      {}
    end

    def save_presets(value)
      clean = value.is_a?(Hash) ? value : {}
      FileUtils.mkdir_p(PRESET_DIR)

      temp = PRESET_FILE + '.tmp'
      File.write(temp, JSON.pretty_generate(clean), encoding: 'UTF-8')
      FileUtils.mv(temp, PRESET_FILE)

      # Giữ thêm một bản trong Preferences để tương thích ngược.
      Sketchup.write_default(
        TranTuanNoiThat::NAME,
        PRESETS_KEY,
        JSON.generate(clean)
      )
      clean
    rescue StandardError => error
      FileUtils.rm_f(temp) if defined?(temp) && temp
      raise "Không lưu được mẫu cánh: #{error.message}"
    end

    def normalize_preset_segments(raw)
      values = Array(raw).map do |pair|
        next unless pair.is_a?(Array) && pair.length == 2
        a = Float(pair[0]) rescue nil
        b = Float(pair[1]) rescue nil
        next unless a && b && b > a
        [[a, 0.0].max, [b, 1.0].min]
      end.compact
      values.sort_by!(&:first)
      return [] if values.empty? || values.length > 64
      return [] if values.first.first > 0.0001 || values.last.last < 0.9999

      previous_end = 0.0
      values.each do |pair|
        return [] if (pair[0] - previous_end).abs > 0.0002
        previous_end = pair[1]
      end
      values
    rescue StandardError
      []
    end

    def preset_tag_owner(list, tag_name, except_name = nil)
      wanted = tag_name.to_s.strip.downcase
      return nil if wanted.empty?

      list.each do |name, value|
        next if except_name && name.to_s == except_name.to_s
        next unless value.is_a?(Hash)
        saved_tag = value['tag_name'].to_s.strip
        return name.to_s if !saved_tag.empty? && saved_tag.downcase == wanted
      end
      nil
    end

    def normalize_preset_tag(list, preset_name, clean, previous_name = nil)
      tag = clean['tag_name'].to_s.strip

      # Mẫu mới không dùng chung Tag mặc định "Cánh tủ".
      if tag.empty? || tag.casecmp('Cánh tủ').zero?
        tag = "Cánh - #{preset_name}"
      end

      owner = preset_tag_owner(list, tag, previous_name || preset_name)
      if owner
        raise "Tag/Layer '#{tag}' đang thuộc mẫu '#{owner}'. Hãy đặt Tag/Layer riêng cho từng mẫu."
      end

      clean['tag_name'] = tag
      clean
    end

    def save_preset(name, options, segments = nil, previous_name = nil)
      preset_name = name.to_s.strip
      old_name = previous_name.to_s.strip

      raise 'Hãy nhập tên mẫu cánh.' if preset_name.empty?
      raise 'Tên mẫu tối đa 60 ký tự.' if preset_name.length > 60

      list = presets
      clean = validate(options)
      clean = normalize_preset_tag(list, preset_name, clean, old_name.empty? ? nil : old_name)

      pattern = normalize_preset_segments(segments)
      clean['_segments'] = pattern unless pattern.empty?

      if !old_name.empty? && old_name != preset_name
        raise "Không tìm thấy mẫu đang chỉnh sửa: #{old_name}" unless list.key?(old_name)
        if list.key?(preset_name)
          raise "Tên mẫu '#{preset_name}' đã tồn tại. Hãy chọn tên khác."
        end
        list.delete(old_name)
      end

      list[preset_name] = clean
      save_presets(list)
      preset_name
    end

    def load_preset(name)
      preset_name = name.to_s
      value = presets[preset_name]
      raise 'Không tìm thấy mẫu cánh.' unless value.is_a?(Hash)

      clean = validate(value)
      pattern = normalize_preset_segments(value['_segments'])
      [clean, pattern]
    end

    def delete_preset(name)
      preset_name = name.to_s
      list = presets
      list.delete(preset_name)
      save_presets(list)
      @current_preset_name = nil if @current_preset_name.to_s == preset_name
      true
    end

    def activate
      tool = Tool.new(settings)
      @active_tool = tool
      Sketchup.active_model.select_tool(tool)
      tool
    end

    def show_settings(tool = nil)
      @active_tool = tool if tool
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        send_settings
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - TẠO CÁNH CHUẨN',
        preferences_key: 'TranTuanNoiThat.DoorStandard.141',
        scrollable: true,
        resizable: true,
        width: 470,
        height: 790,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(settings_html)
      @dialog.add_action_callback('ready') { |_ctx| send_settings }
      @dialog.add_action_callback('apply') do |_ctx, payload|
        begin
          data = JSON.parse(payload.to_s)
          clean = save_settings(data)
          @active_tool.update_settings(clean) if @active_tool && @active_tool.respond_to?(:update_settings)
          send_settings
          @dialog.execute_script("TT.notice('Đã áp dụng thông số vào preview hiện tại.', false);")
        rescue StandardError => error
          @dialog.execute_script("TT.notice(#{JSON.generate(error.message)}, true);")
        end
      end
      @dialog.add_action_callback('reset') do |_ctx|
        @current_preset_name = nil
        clean = save_settings(DEFAULTS)
        @active_tool.update_settings(clean) if @active_tool && @active_tool.respond_to?(:update_settings)
        send_settings
      end

      @dialog.add_action_callback('save_preset') do |_ctx, name, payload|
        begin
          data = JSON.parse(payload.to_s)
          pattern = if @active_tool && @active_tool.respond_to?(:preset_segments)
            @active_tool.preset_segments
          else
            nil
          end

          preset_name = save_preset(name, data, pattern, nil)
          clean, saved_pattern = load_preset(preset_name)
          @current_preset_name = preset_name
          save_settings(clean)

          if @active_tool && @active_tool.respond_to?(:update_preset)
            @active_tool.update_preset(clean, saved_pattern)
          elsif @active_tool && @active_tool.respond_to?(:update_settings)
            @active_tool.update_settings(clean)
          end

          send_settings
          @dialog.execute_script("TT.notice(#{JSON.generate("ĐÃ LƯU MẪU MỚI: #{preset_name} · Tag riêng: #{clean['tag_name']}")}, false);")
        rescue StandardError => error
          @dialog.execute_script("TT.notice(#{JSON.generate(error.message)}, true);")
        end
      end

      @dialog.add_action_callback('update_preset') do |_ctx, current_name, new_name, payload|
        begin
          current = current_name.to_s.strip
          raise 'Hãy nạp/chọn mẫu cần chỉnh sửa trước.' if current.empty?

          data = JSON.parse(payload.to_s)
          pattern = if @active_tool && @active_tool.respond_to?(:preset_segments)
            @active_tool.preset_segments
          else
            nil
          end

          preset_name = save_preset(new_name, data, pattern, current)
          clean, saved_pattern = load_preset(preset_name)
          @current_preset_name = preset_name
          save_settings(clean)

          if @active_tool && @active_tool.respond_to?(:update_preset)
            @active_tool.update_preset(clean, saved_pattern)
          elsif @active_tool && @active_tool.respond_to?(:update_settings)
            @active_tool.update_settings(clean)
          end

          send_settings
          @dialog.execute_script("TT.notice(#{JSON.generate("ĐÃ LƯU LẠI MẪU: #{preset_name} · Tag riêng: #{clean['tag_name']}")}, false);")
        rescue StandardError => error
          @dialog.execute_script("TT.notice(#{JSON.generate(error.message)}, true);")
        end
      end

      @dialog.add_action_callback('load_preset') do |_ctx, name|
        begin
          clean, pattern = load_preset(name)
          @current_preset_name = name.to_s
          save_settings(clean)
          if @active_tool && @active_tool.respond_to?(:update_preset)
            @active_tool.update_preset(clean, pattern)
          elsif @active_tool && @active_tool.respond_to?(:update_settings)
            @active_tool.update_settings(clean)
          end
          send_settings
          @dialog.execute_script("TT.notice(#{JSON.generate("Đã nạp mẫu + kiểu chia: #{name}")}, false);")
        rescue StandardError => error
          @dialog.execute_script("TT.notice(#{JSON.generate(error.message)}, true);")
        end
      end

      @dialog.add_action_callback('delete_preset') do |_ctx, name|
        delete_preset(name)
        send_settings
        @dialog.execute_script("TT.notice('Đã xóa mẫu cánh.', false);")
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    rescue StandardError => error
      UI.messagebox("Không mở được thông số Tạo Cánh Chuẩn:\n#{error.message}")
    end

    def send_settings
      return unless @dialog && @dialog.visible?
      preset_data = presets
      payload = {
        'settings' => settings,
        'presets' => preset_data.keys.sort,
        'preset_tags' => preset_data.each_with_object({}) do |(name, value), memo|
          memo[name.to_s] = value.is_a?(Hash) ? value['tag_name'].to_s : ''
        end,
        'current_preset' => @current_preset_name.to_s,
        'preset_file' => PRESET_FILE
      }
      @dialog.execute_script("TT.load(#{JSON.generate(payload)});")
    rescue StandardError
    end

    def settings_html
      <<~'HTML'
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8">
          <style>
            *{box-sizing:border-box}
            body{margin:0;background:#f3f6f9;color:#172033;font:13px Arial,sans-serif}
            .head{padding:14px 16px;background:#172033;color:white;position:sticky;top:0;z-index:2}
            .head h2{margin:0;font-size:18px}.head small{opacity:.78}
            .wrap{padding:12px}.card{background:#fff;border:1px solid #d7dfe8;border-radius:10px;padding:12px;margin-bottom:10px}
            .grid{display:grid;grid-template-columns:1fr 130px 34px;gap:7px;align-items:center}
            label{font-weight:bold} input,select{width:100%;padding:8px;border:1px solid #b9c4d1;border-radius:6px}
            .row{display:flex;gap:8px;flex-wrap:wrap}.row button{flex:1}
            button{border:0;border-radius:7px;padding:9px 12px;background:#176fd1;color:#fff;font-weight:bold;cursor:pointer}
            button.gray{background:#667085}.hint{font-size:12px;color:#667085;line-height:1.55}
            #notice{display:none;margin-top:9px;padding:9px;border-radius:6px}
            #notice.ok{display:block;background:#e7f7ed;color:#166534}
            #notice.err{display:block;background:#fde8e8;color:#9b1c1c}
          </style>
        </head>
        <body>
          <div class="head"><h2>TẠO CÁNH CHUẨN</h2><small>P1–P2 tự do · preview 3D · TÂM / +1 cánh</small></div>
          <div class="wrap">
            <div class="card">
              <div class="grid">
                <label>Lắp đặt</label><select id="fit"><option>Lọt lòng</option><option>Phủ ngoài</option></select><span></span>
                <label>Hướng chia</label><select id="dir"><option>Dọc</option><option>Ngang</option></select><span></span>
                <label>Số cánh</label><input id="count" type="number" min="1" max="64" step="1"><span>cánh</span>
                <label>Dày cánh</label><input id="thickness" type="number" step="0.5"><span>mm</span>
                <label>Độ rộng khe dọc</label><input id="gap_vertical" type="number" step="0.5"><span>mm</span>
                <label>Độ rộng khe ngang (B)</label><input id="gap_horizontal" type="number" step="0.5"><span>mm</span>
                <label>Nhô (+) / lùi (-)</label><input id="offset" type="number" step="0.5"><span>mm</span>
                <label>Tên cánh</label><input id="name_prefix"><span></span>
                <label>Tag / Layer</label><input id="tag_name"><span></span>
              </div>
            </div>

            <div class="card">
              <b>Hở lọt lòng</b>
              <div class="grid" style="margin-top:9px">
                <label>Trái</label><input id="gap_left" type="number" step="0.5"><span>mm</span>
                <label>Phải</label><input id="gap_right" type="number" step="0.5"><span>mm</span>
                <label>Trên</label><input id="gap_top" type="number" step="0.5"><span>mm</span>
                <label>Dưới</label><input id="gap_bottom" type="number" step="0.5"><span>mm</span>
              </div>
            </div>

            <div class="card">
              <b>Phủ ngoài</b>
              <div class="grid" style="margin-top:9px">
                <label>Phủ trái</label><input id="over_left" type="number" step="0.5"><span>mm</span>
                <label>Phủ phải</label><input id="over_right" type="number" step="0.5"><span>mm</span>
                <label>Phủ trên</label><input id="over_top" type="number" step="0.5"><span>mm</span>
                <label>Phủ dưới</label><input id="over_bottom" type="number" step="0.5"><span>mm</span>
              </div>
            </div>

            <div class="card">
              <b>MẪU CÁNH ĐÃ LƯU</b>
              <div class="grid" style="margin-top:9px">
                <label>Chọn mẫu</label><select id="preset_select"></select><span></span>
                <label>Tên mẫu / tên mới</label><input id="preset_name" placeholder="VD: Cánh bếp dưới"><span></span>
              </div>
              <div class="hint" id="current_preset_info" style="margin-top:7px"><b>Mẫu đang chỉnh sửa:</b> Chưa chọn</div>
              <div class="hint" id="preset_tag_info" style="margin-top:5px">Mỗi mẫu dùng Tag/Layer riêng.</div>
              <div class="hint" id="preset_info" style="margin-top:5px">Mẫu được lưu trong door_presets.json.</div>
              <div class="row" style="margin-top:9px">
                <button onclick="savePreset()">LƯU MẪU MỚI</button>
                <button onclick="updatePreset()">LƯU LẠI MẪU ĐANG CHỌN</button>
              </div>
              <div class="row" style="margin-top:7px">
                <button class="gray" onclick="loadPreset()">NẠP MẪU</button>
                <button class="gray" onclick="deletePreset()">XÓA MẪU</button>
              </div>
            </div>

            <div class="card">
              <div class="row"><button onclick="apply()">ÁP DỤNG</button><button class="gray" onclick="sketchup.reset()">MẶC ĐỊNH</button></div>
              <div class="hint" style="margin-top:10px">
                Click <b>P1 → P2 chéo</b> trên <b>bất kỳ Face nào</b> để xác định khoang. P1/P2 <b>không khóa hướng</b>,
                vẫn bắt Endpoint / Edge / Inference tự nhiên. Sau P2 tự hiện
                Sau P2 chỉ hiện <b>TÂM</b> của khoang con đang rê. Bấm <b>TÂM</b>, phím <b>/</b> để chia đôi khoang đó;
                rê sang khoang con khác để TÂM tự chuyển, chia tự do. Click phần còn lại của preview để tạo cánh. <b>TAB</b> mở bảng này · <b>SHIFT</b> đổi CÁNH DỌC/CÁNH NGANG ·
                <b>CTRL</b> đổi CÁNH LỌT/CÁNH PHỦ. Khi chia Ngang, preview dùng riêng <b>Khe ngang</b>; chia Dọc dùng <b>Khe dọc</b>.
              </div>
              <div id="notice"></div>
            </div>
          </div>
          <script>
            const ids=['fit','dir','count','thickness','gap_vertical','gap_horizontal','offset','name_prefix','tag_name',
              'gap_left','gap_right','gap_top','gap_bottom','over_left','over_right','over_top','over_bottom'];
            const TT={
              currentPreset:'',
              presetTags:{},
              load(payload){
                const s=payload.settings||{};
                fit.value=s.fit_mode||'Lọt lòng';dir.value=s.split_direction||'Dọc';count.value=s.door_count||1;
                thickness.value=s.thickness||17.5;
                gap_vertical.value=(s.gap_vertical!=null?s.gap_vertical:(s.gap_middle!=null?s.gap_middle:2));
                gap_horizontal.value=(s.gap_horizontal!=null?s.gap_horizontal:(s.gap_middle!=null?s.gap_middle:2));
                offset.value=s.offset||0;
                name_prefix.value=s.name_prefix||'Cánh';tag_name.value=s.tag_name||'Cánh tủ';
                gap_left.value=s.gap_left||0;gap_right.value=s.gap_right||0;gap_top.value=s.gap_top||0;gap_bottom.value=s.gap_bottom||0;
                over_left.value=s.over_left||0;over_right.value=s.over_right||0;over_top.value=s.over_top||0;over_bottom.value=s.over_bottom||0;
                const names=payload.presets||[];
                TT.currentPreset=payload.current_preset||'';
                TT.presetTags=payload.preset_tags||{};
                preset_select.innerHTML='<option value="">-- Chọn mẫu --</option>'+names.map(n=>'<option value="'+esc(n)+'">'+esc(n)+'</option>').join('');
                preset_select.value=TT.currentPreset||'';
                if(TT.currentPreset){
                  preset_name.value=TT.currentPreset;
                }
                if(document.getElementById('current_preset_info')){
                  current_preset_info.innerHTML='<b>Mẫu đang chỉnh sửa:</b> '+(TT.currentPreset?esc(TT.currentPreset):'Chưa chọn');
                }
                if(document.getElementById('preset_tag_info')){
                  const tag=TT.currentPreset?(TT.presetTags[TT.currentPreset]||''):'';
                  preset_tag_info.textContent=tag?('Tag/Layer riêng của mẫu: '+tag):'Mỗi mẫu dùng Tag/Layer riêng.';
                }
                if(document.getElementById('preset_info')){
                  preset_info.textContent='Đã lưu '+names.length+' mẫu · dữ liệu: door_presets.json';
                }
              },
              notice(text,error){
                const e=document.getElementById('notice');e.className=error?'err':'ok';e.textContent=text;
              }
            };
            function esc(v){return String(v||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
            function collect(){
              return {
                fit_mode:fit.value,split_direction:dir.value,door_count:Number(count.value),
                thickness:Number(thickness.value),
                gap_vertical:Number(gap_vertical.value),
                gap_horizontal:Number(gap_horizontal.value),
                gap_middle:Number(gap_vertical.value),
                offset:Number(offset.value),
                name_prefix:name_prefix.value,tag_name:tag_name.value,
                gap_left:Number(gap_left.value),gap_right:Number(gap_right.value),
                gap_top:Number(gap_top.value),gap_bottom:Number(gap_bottom.value),
                over_left:Number(over_left.value),over_right:Number(over_right.value),
                over_top:Number(over_top.value),over_bottom:Number(over_bottom.value)
              };
            }
            function apply(){
              sketchup.apply(JSON.stringify(collect()));
            }
            function savePreset(){
              const name=preset_name.value.trim();
              if(!name){TT.notice('Hãy nhập TÊN MẪU trước khi lưu.',true);preset_name.focus();return;}

              // Mẫu mới không dùng chung Tag mặc định.
              if(!tag_name.value.trim() || tag_name.value.trim().toLowerCase()==='cánh tủ'){
                tag_name.value='Cánh - '+name;
              }
              sketchup.save_preset(name,JSON.stringify(collect()));
            }
            function updatePreset(){
              if(!TT.currentPreset){
                TT.notice('Hãy NẠP một mẫu trước khi LƯU LẠI.',true);
                return;
              }
              const name=preset_name.value.trim()||TT.currentPreset;
              sketchup.update_preset(TT.currentPreset,name,JSON.stringify(collect()));
            }
            function loadPreset(){
              if(!preset_select.value){TT.notice('Hãy chọn mẫu cần nạp.',true);return;}
              sketchup.load_preset(preset_select.value);
            }
            function deletePreset(){
              const name=preset_select.value||TT.currentPreset;
              if(!name){TT.notice('Hãy chọn mẫu cần xóa.',true);return;}
              sketchup.delete_preset(name);
            }
            preset_select.addEventListener('change',function(){
              const name=preset_select.value;
              if(name){
                preset_name.value=name;
                preset_tag_info.textContent='Tag/Layer riêng của mẫu: '+(TT.presetTags[name]||'');
              }
            });
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body></html>
      HTML
    end

    class Tool
      SNAP_RADIUS = 24.0

      def initialize(options)
        @model = Sketchup.active_model
        @options = DoorStandard.validate(options)
        @state = :pick_p1
        @ip = Sketchup::InputPoint.new

        @p1 = nil
        @p2 = nil
        @hover_point = nil

        @face = nil
        @face_transform = Geom::Transformation.new
        @origin = nil
        @normal = nil
        @u = nil
        @v = nil

        @region = nil
        @doors = []
        @segments = equal_segments(@options['door_count'])
        @active_segment_index = 0
        @split_ratio = nil
        @split_point = nil
        @direction_lock = nil
        @split_committed = false
        @last_ready_mouse = nil
        @snap_label = nil
        @flip = false
        @hover_handle = nil
      end

      def activate
        update_status
        @model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def update_settings(options)
        old_count = @options['door_count'].to_i
        @options = DoorStandard.validate(options)

        if @options['door_count'].to_i != old_count
          @segments = equal_segments(@options['door_count'])
          @active_segment_index = 0
          @split_ratio = nil
          @split_point = nil
          @split_committed = @options['door_count'].to_i > 1
          @direction_lock = @options['split_direction'] if @split_committed
        end

        rebuild_preview if @region
        @model.active_view.invalidate
        true
      rescue StandardError => error
        UI.messagebox(error.message)
        false
      end

      def preset_segments
        Array(@segments).map { |pair| Array(pair).map(&:to_f) }
      end

      def update_preset(options, segments = nil)
        @options = DoorStandard.validate(options)
        @segments = normalize_segments(segments)
        @segments = equal_segments(@options['door_count']) if @segments.empty?
        @options = @options.merge('door_count' => @segments.length)
        @active_segment_index = 0
        @split_ratio = nil
        @split_point = nil
        @split_committed = @segments.length > 1
        @direction_lock = @options['split_direction'] if @split_committed
        rebuild_preview if @region
        @model.active_view.invalidate
        true
      rescue StandardError => error
        UI.messagebox(error.message)
        false
      end

      def onCancel(_reason, view)
        case @state
        when :ready
          @state = :pick_p2
          @p2 = nil
          @region = nil
          @doors = []
          @hover_handle = nil
          @split_ratio = nil
        when :pick_p2
          reset_all
        else
          @model.select_tool(nil)
          return
        end

        update_status
        view.invalidate
      end

      def onKeyDown(key, repeat, _flags, view)
        if key == 9
          DoorStandard.show_settings(self)
          return
        end

        # "/" chốt đường chia tự do tại vị trí TÂM động.
        if [47, 111, 191].include?(key) && @state == :ready
          split_active_segment
          view.invalidate
          return
        end

        # 2 / 3 / 4: chia nhanh TOÀN KHOANG thành số cánh tương ứng.
        quick_count = {
          50 => 2, 98 => 2,
          51 => 3, 99 => 3,
          52 => 4, 100 => 4
        }[key]
        if quick_count && @state == :ready
          set_equal_door_count(quick_count)
          view.invalidate
          return
        end

        # ENTER: tạo ngay preview hiện tại.
        if key == 13 && @state == :ready
          create_doors
          reset_all
          update_status
          view.invalidate
          return
        end

        # SHIFT: đổi Dọc/Ngang và khóa hướng do người dùng chọn.
        if key == 16 && @state == :ready
          return if repeat.to_i > 1
          direction = @options['split_direction'] == 'Dọc' ? 'Ngang' : 'Dọc'
          set_split_direction(direction, true)
          update_split_cursor(view, @last_ready_mouse[0], @last_ready_mouse[1]) if @last_ready_mouse
          Sketchup.status_text =
            "SHIFT · #{direction == 'Dọc' ? 'CÁNH DỌC' : 'CÁNH NGANG'} · đã khóa hướng chia."
          view.invalidate
          return
        end

        if key == 17
          return if repeat.to_i > 1
          @options = @options.merge(
            'fit_mode' => (@options['fit_mode'] == 'Lọt lòng' ? 'Phủ ngoài' : 'Lọt lòng')
          )
          DoorStandard.save_settings(@options)
          rebuild_preview if @region
          DoorStandard.send_settings
          Sketchup.status_text =
            "CTRL · #{@options['fit_mode'] == 'Lọt lòng' ? 'CÁNH LỌT' : 'CÁNH PHỦ'}"
          view.invalidate
          return
        end
      rescue StandardError => error
        puts "[TT DoorStandard key] #{error.class}: #{error.message}"
      end

      def onMouseMove(_flags, x, y, view)
        clear_inference_lock(view) if [:pick_p1, :pick_p2].include?(@state)

        case @state
        when :pick_p1
          @hover_point = pick_first_point(view, x, y)
          view.tooltip = @snap_label || @ip.tooltip if @ip.valid?

        when :pick_p2
          @hover_point = pick_second_point(view, x, y)
          if @hover_point
            build_region_from_points(@p1, @hover_point)
            rebuild_preview if @region
          else
            @region = nil
            @doors = []
          end
          view.tooltip = @snap_label || @ip.tooltip if @ip.valid?

        when :ready
          auto_detect_split_direction(x, y) unless @direction_lock
          @last_ready_mouse = [x, y]
          update_split_cursor(view, x, y)
          @hover_handle = :center
        end

        update_status
        view.invalidate
      rescue StandardError => error
        puts "[TT DoorStandard move] #{error.class}: #{error.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        unlock_direction_lock(view) if [:pick_p1, :pick_p2].include?(@state)

        case @state
        when :pick_p1
          point = pick_first_point(view, x, y)
          unless point && @face
            UI.beep
            return
          end

          @p1 = point
          @state = :pick_p2
          @region = nil
          @doors = []
          @segments = equal_segments(@options['door_count'])
          @active_segment_index = 0
          @split_ratio = nil

        when :pick_p2
          point = pick_second_point(view, x, y)
          unless point
            UI.beep
            return
          end

          build_region_from_points(@p1, point)
          unless valid_region?
            UI.beep
            Sketchup.status_text = 'P2 quá gần P1. Hãy chọn điểm chéo đối diện của khoang.'
            return
          end

          @p2 = point
          rebuild_preview
          if @doors.empty?
            UI.beep
            return
          end

          @state = :ready
          update_split_cursor(view, x, y)
          @hover_handle = nearest_handle(view, x, y)

        when :ready
          auto_detect_split_direction(x, y) unless @direction_lock
          @last_ready_mouse = [x, y]
          if update_split_cursor(view, x, y)
            # Chuột là công cụ CHIA: click chốt ngay TÂM hiện tại.
            split_active_segment
          else
            UI.beep
          end
        end

        update_status
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Không tạo được cánh:\n#{error.message}")
      end

      def draw(view)
        if @state == :pick_p1
          draw_hover_point(view) if @hover_point
          return
        end

        draw_p1(view)
        draw_hover_p2(view) if @state == :pick_p2 && @hover_point
        draw_p2(view) if @state == :ready && @p2

        if @state == :pick_p2 && @region
          draw_region_frame(view)
          draw_preview_doors(view)
          draw_center_handle(view, false)
        elsif @state == :ready && @region
          draw_region_frame(view)
          draw_preview_doors(view)
          draw_committed_split_lines(view)
          draw_center_handle(view, true)
          draw_info(view)
        end
      rescue StandardError => error
        puts "[TT DoorStandard draw] #{error.class}: #{error.message}"
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@p1) if @p1
        bb.add(@p2) if @p2
        @doors.each do |door|
          door[:corners].each { |point| bb.add(point) }
        end
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      private

      def clear_inference_lock(view)
        # P1/P2 không khóa trục. InputPoint vẫn tự nhận Endpoint/Edge/Inference.
        view.lock_inference if view.respond_to?(:lock_inference)
        true
      rescue StandardError
        false
      end

      def set_split_direction(direction, lock = false)
        return false unless ['Dọc', 'Ngang'].include?(direction)

        changed = @options['split_direction'] != direction
        @options = @options.merge('split_direction' => direction)
        @direction_lock = direction if lock

        if changed
          # Nếu đã chốt chia: GIỮ NGUYÊN tỷ lệ/mốc @segments.
          # Chỉ đổi trục biểu diễn khi người dùng SHIFT chủ động.
          unless @split_committed
            count = [@segments.to_a.length, 1].max
            @segments = equal_segments(count)
          end

          @active_segment_index = 0
          @split_ratio = nil
          @split_point = nil
          rebuild_preview if @region
        end

        DoorStandard.save_settings(@options)
        DoorStandard.send_settings
        true
      end

      def auto_detect_split_direction(x, y)
        return false if @direction_lock || @split_committed

        if @last_ready_mouse
          dx = x.to_f - @last_ready_mouse[0].to_f
          dy = y.to_f - @last_ready_mouse[1].to_f
          if [dx.abs, dy.abs].max >= 4.0
            direction = dx.abs >= dy.abs ? 'Dọc' : 'Ngang'
            set_split_direction(direction, false)
          end
        end
        true
      rescue StandardError
        false
      end

      def reset_all
        @state = :pick_p1
        @p1 = nil
        @p2 = nil
        @hover_point = nil
        @face = nil
        @face_transform = Geom::Transformation.new
        @origin = nil
        @normal = nil
        @u = nil
        @v = nil
        @region = nil
        @doors = []
        @segments = equal_segments(@options['door_count'])
        @active_segment_index = 0
        @split_ratio = nil
        @split_point = nil
        @direction_lock = nil
        @split_committed = false
        @last_ready_mouse = nil
        @snap_label = nil
        @hover_handle = nil
      end

      def pick_first_point(view, x, y)
        @ip.pick(view, x, y)
        return nil unless @ip.valid?

        helper = view.pick_helper
        helper.do_pick(x, y)
        path = helper.path_at(0)
        return nil unless path

        face = path.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
        return nil unless face

        transform = if helper.respond_to?(:transformation_at)
          helper.transformation_at(0)
        else
          Geom::Transformation.new
        end

        point = nearest_face_snap_point(
          view, face, transform, x, y, @ip.position
        )
        setup_plane(face, transform, point, view)
        point
      rescue StandardError
        nil
      end

      def nearest_face_snap_point(view, face, transform, x, y, fallback)
        candidates = []

        face.outer_loop.vertices.each do |vertex|
          candidates << ['Endpoint', vertex.position.transform(transform)]
        end

        face.outer_loop.edges.each do |edge|
          a = edge.start.position.transform(transform)
          b = edge.end.position.transform(transform)
          midpoint = Geom::Point3d.linear_combination(0.5, a, 0.5, b)
          candidates << ['Midpoint', midpoint]
        end

        vertices = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
        if vertices.length >= 3
          candidates << ['Tâm Face', average_point(vertices)]
        end

        best = nil
        best_distance = SNAP_RADIUS + 1.0
        candidates.each do |label, point|
          screen = view.screen_coords(point)
          dx = screen.x.to_f - x.to_f
          dy = screen.y.to_f - y.to_f
          distance = Math.sqrt(dx * dx + dy * dy)
          if distance <= SNAP_RADIUS && distance < best_distance
            best = [label, point]
            best_distance = distance
          end
        end

        if best
          @snap_label = "Bắt gần nhất · #{best[0]}"
          best[1]
        else
          @snap_label = nil
          fallback
        end
      rescue StandardError
        @snap_label = nil
        fallback
      end

      def setup_plane(face, transform, origin, view)
        normal = face.normal.transform(transform)
        raise 'Không nhận được pháp tuyến Face.' if normal.length < 0.000001
        normal.normalize!

        # Phía mặt cánh ưu tiên hướng về camera.
        normal.reverse! if normal.dot(view.camera.direction) > 0.0

        vertical = project_vector_to_plane(Z_AXIS, normal)
        if vertical.length < 0.1
          vertical = project_vector_to_plane(Y_AXIS, normal)
          vertical = project_vector_to_plane(X_AXIS, normal) if vertical.length < 0.1
        end
        raise 'Không dựng được trục đứng của khoang.' if vertical.length < 0.000001
        vertical.normalize!
        vertical.reverse! if vertical.dot(Z_AXIS) < -0.01

        horizontal = vertical.cross(normal)
        raise 'Không dựng được trục ngang của khoang.' if horizontal.length < 0.000001
        horizontal.normalize!

        center_screen = view.screen_coords(origin)
        horizontal_screen = view.screen_coords(origin.offset(horizontal, 100.mm))
        horizontal.reverse! if horizontal_screen.x < center_screen.x

        vertical = normal.cross(horizontal)
        vertical.normalize!
        vertical.reverse! if vertical.dot(Z_AXIS) < -0.01

        @face = face
        @face_transform = transform
        @origin = origin
        @normal = normal
        @u = horizontal
        @v = vertical
      end

      def pick_second_point(view, x, y)
        return nil unless @origin && @normal

        @ip.pick(view, x, y)
        fallback = nil

        if @ip.valid?
          picked = @ip.position
          distance = point_plane_distance(picked, @origin, @normal)
          fallback = project_point_to_plane(picked, @origin, @normal) if distance.abs <= 5.mm
        end

        unless fallback
          ray = view.pickray(x, y)
          return nil unless ray && ray.length == 2
          fallback = Geom.intersect_line_plane(ray, [@origin, @normal])
        end
        return nil unless fallback

        snapped = nearest_face_snap_point(
          view, @face, @face_transform, x, y, fallback
        )
        project_point_to_plane(snapped, @origin, @normal)
      rescue StandardError
        nil
      end

      def point_plane_distance(point, origin, normal)
        vector_between(origin, point).dot(normal)
      end

      def project_point_to_plane(point, origin, normal)
        distance = point_plane_distance(point, origin, normal)
        return point if distance.abs < 0.000001

        move = normal.clone
        move.length = distance.abs
        move.reverse! if distance > 0.0
        point.offset(move)
      rescue StandardError
        point
      end

      def build_region_from_points(p1, p2)
        return @region = nil unless p1 && p2 && @origin && @u && @v

        a = vector_between(@origin, p1)
        b = vector_between(@origin, p2)
        ua = a.dot(@u)
        va = a.dot(@v)
        ub = b.dot(@u)
        vb = b.dot(@v)

        u0, u1 = [ua, ub].minmax
        v0, v1 = [va, vb].minmax

        @region = {
          face: @face,
          origin: @origin,
          normal: @normal,
          u: @u,
          v: @v,
          u0: u0,
          u1: u1,
          v0: v0,
          v1: v1,
          width: u1 - u0,
          height: v1 - v0
        }
      end

      def valid_region?
        @region &&
          @region[:width] >= 20.mm &&
          @region[:height] >= 20.mm
      end

      def adjusted_bounds
        r = @region

        if @options['fit_mode'] == 'Phủ ngoài'
          [
            r[:u0] - @options['over_left'].mm,
            r[:u1] + @options['over_right'].mm,
            r[:v0] - @options['over_bottom'].mm,
            r[:v1] + @options['over_top'].mm
          ]
        else
          [
            r[:u0] + @options['gap_left'].mm,
            r[:u1] - @options['gap_right'].mm,
            r[:v0] + @options['gap_bottom'].mm,
            r[:v1] - @options['gap_top'].mm
          ]
        end
      end

      def equal_segments(count)
        n = [[count.to_i, 1].max, 64].min
        step = 1.0 / n.to_f
        Array.new(n) { |index| [index * step, (index + 1) * step] }
      end

      def normalize_segments(raw)
        values = Array(raw).map do |pair|
          next unless pair.is_a?(Array) && pair.length == 2
          a = Float(pair[0]) rescue nil
          b = Float(pair[1]) rescue nil
          next unless a && b && b > a
          [[a, 0.0].max, [b, 1.0].min]
        end.compact
        values.sort_by!(&:first)
        return [] if values.empty?
        return [] if values.first.first > 0.0001 || values.last.last < 0.9999
        values
      rescue StandardError
        []
      end

      def set_equal_door_count(count)
        n = count.to_i
        return false unless n.between?(2, 4)

        @segments = equal_segments(n)
        @active_segment_index = 0
        @split_ratio = nil
        @split_point = nil
        @options = @options.merge('door_count' => n)
        @split_committed = true
        @direction_lock ||= @options['split_direction']
        DoorStandard.save_settings(@options)
        rebuild_preview
        DoorStandard.send_settings

        Sketchup.status_text =
          "CHIA NHANH #{n} CÁNH · rê chuột để chia tự do thêm · ENTER tạo ngay."
        true
      rescue StandardError => error
        UI.beep
        Sketchup.status_text = "Không chia nhanh được: #{error.message}"
        false
      end

      def split_active_segment
        unless valid_region?
          UI.beep
          Sketchup.status_text = 'Hãy khóa P1-P2 trước khi chia cánh.'
          return false
        end

        @segments = equal_segments(@options['door_count']) if @segments.nil? || @segments.empty?
        index = [[@active_segment_index.to_i, 0].max, @segments.length - 1].min
        segment = @segments[index]
        a = segment[0].to_f
        b = segment[1].to_f

        axis_span = if @options['split_direction'] == 'Dọc'
          adjusted_bounds[1] - adjusted_bounds[0]
        else
          adjusted_bounds[3] - adjusted_bounds[2]
        end

        # Mỗi phần sau khi chia phải đủ chỗ cho ván + khe.
        active_gap = @options['split_direction'] == 'Dọc' ?
          @options['gap_vertical'] :
          @options['gap_horizontal']
        minimum = [active_gap.mm + 20.mm, 30.mm].max
        min_ratio = minimum / axis_span.to_f
        if (b - a) <= min_ratio * 2.0
          UI.beep
          Sketchup.status_text = 'Khoang con quá nhỏ để chia tiếp.'
          return false
        end

        split = @split_ratio.to_f
        split = (a + b) * 0.5 unless split > a && split < b
        split = [split, a + min_ratio].max
        split = [split, b - min_ratio].min

        @segments[index, 1] = [[a, split], [split, b]]
        @active_segment_index = index
        @split_ratio = nil
        @split_point = nil
        @options = @options.merge('door_count' => @segments.length)
        @split_committed = true
        @direction_lock ||= @options['split_direction']
        DoorStandard.save_settings(@options)
        rebuild_preview
        DoorStandard.send_settings

        Sketchup.status_text =
          "ĐÃ KHÓA #{@segments.length} CÁNH · đường chia cũ giữ nguyên · rê chuột chỉ đặt TÂM mới · / hoặc TÂM chia tiếp · ENTER tạo."
        true
      rescue StandardError => error
        UI.beep
        Sketchup.status_text = "Không chia được cánh: #{error.message}"
        false
      end

      def rebuild_preview
        @doors = []
        return unless valid_region?

        u0, u1, v0, v1 = adjusted_bounds
        raise 'Khoang quá nhỏ sau khi trừ khe hở/phủ.' unless u1 > u0 && v1 > v0

        gap = if @options['split_direction'] == 'Dọc'
          @options['gap_vertical'].mm
        else
          @options['gap_horizontal'].mm
        end

        # Mặt trước luôn là phía ngoài; chiều dày luôn đẩy vào trong tủ.
        normal = @region[:normal].reverse
        @segments = equal_segments(@options['door_count']) if @segments.nil? || @segments.empty?
        @active_segment_index = [@active_segment_index.to_i, @segments.length - 1].min
        @options = @options.merge('door_count' => @segments.length)

        offset_vector = if @options['offset'].abs > 0.0001
          vector = @region[:normal].clone
          vector.length = @options['offset'].mm.abs
          vector.reverse! if @options['offset'] < 0.0
          vector
        else
          Geom::Vector3d.new(0, 0, 0)
        end

        thickness_vector = normal.clone
        thickness_vector.length = @options['thickness'].mm

        if @options['split_direction'] == 'Dọc'
          span = u1 - u0
          @segments.each_with_index do |segment, index|
            a = u0 + span * segment[0]
            b = u0 + span * segment[1]
            a += gap * 0.5 if segment[0] > 0.000001
            b -= gap * 0.5 if segment[1] < 0.999999
            raise 'Khe giữa quá lớn so với một khoang con.' unless b > a
            @doors << build_box(a, b, v0, v1, offset_vector, thickness_vector, index)
          end
        else
          span = v1 - v0
          @segments.each_with_index do |segment, index|
            a = v0 + span * segment[0]
            b = v0 + span * segment[1]
            a += gap * 0.5 if segment[0] > 0.000001
            b -= gap * 0.5 if segment[1] < 0.999999
            raise 'Khe giữa quá lớn so với một khoang con.' unless b > a
            @doors << build_box(u0, u1, a, b, offset_vector, thickness_vector, index)
          end
        end
      rescue StandardError => error
        @doors = []
        Sketchup.status_text = "Tạo Cánh: #{error.message}"
      end

      def point_on_plane(u_value, v_value)
        point = @region[:origin].offset(@region[:u], u_value)
        point.offset(@region[:v], v_value)
      end

      def build_box(u0, u1, v0, v1, offset_vector, thickness_vector, index)
        front = [
          point_on_plane(u0, v0),
          point_on_plane(u1, v0),
          point_on_plane(u1, v1),
          point_on_plane(u0, v1)
        ]

        if offset_vector.length > 0.0
          front = front.map { |point| point.offset(offset_vector) }
        end

        back = front.map { |point| point.offset(thickness_vector) }

        {
          index: index,
          front: front,
          back: back,
          corners: front + back,
          width: (u1 - u0).abs,
          height: (v1 - v0).abs
        }
      end

      def active_segment_bounds
        return nil unless valid_region?

        u0, u1, v0, v1 = adjusted_bounds
        @segments = equal_segments(@options['door_count']) if @segments.nil? || @segments.empty?
        index = [[@active_segment_index.to_i, 0].max, @segments.length - 1].min
        segment = @segments[index]

        if @options['split_direction'] == 'Dọc'
          span = u1 - u0
          [u0 + span * segment[0], u0 + span * segment[1], v0, v1]
        else
          span = v1 - v0
          [u0, u1, v0 + span * segment[0], v0 + span * segment[1]]
        end
      end

      def handle_points
        return {} unless valid_region?

        if @split_point
          return { center: @split_point }
        end

        bounds = active_segment_bounds
        return {} unless bounds

        u0, u1, v0, v1 = bounds
        segment = @segments[[@active_segment_index.to_i, @segments.length - 1].min]
        ratio = @split_ratio
        ratio = (segment[0] + segment[1]) * 0.5 unless ratio && ratio > segment[0] && ratio < segment[1]

        point = if @options['split_direction'] == 'Dọc'
          point_on_plane(
            adjusted_bounds[0] + (adjusted_bounds[1] - adjusted_bounds[0]) * ratio,
            (v0 + v1) * 0.5
          )
        else
          point_on_plane(
            (u0 + u1) * 0.5,
            adjusted_bounds[2] + (adjusted_bounds[3] - adjusted_bounds[2]) * ratio
          )
        end

        { center: point }
      rescue StandardError
        {}
      end

      def point_on_region_from_mouse(view, x, y)
        ray = view.pickray(x, y)
        return nil unless ray && ray.length == 2
        Geom.intersect_line_plane(ray, [@region[:origin], @region[:normal]])
      rescue StandardError
        nil
      end

      def update_split_cursor(view, x, y)
        return false unless valid_region?

        point = point_on_region_from_mouse(view, x, y)
        return false unless point

        u0, u1, v0, v1 = adjusted_bounds
        vector = vector_between(@region[:origin], point)
        u_value = vector.dot(@region[:u])
        v_value = vector.dot(@region[:v])

        return false unless u_value >= u0 && u_value <= u1 &&
          v_value >= v0 && v_value <= v1

        ratio = if @options['split_direction'] == 'Dọc'
          (u_value - u0) / (u1 - u0)
        else
          (v_value - v0) / (v1 - v0)
        end

        index = nil
        @segments.each_with_index do |segment, i|
          if ratio >= segment[0] - 0.000001 && ratio <= segment[1] + 0.000001
            index = i
            break
          end
        end
        return false if index.nil?

        @active_segment_index = index
        segment = @segments[index]
        free_ratio = [[ratio, segment[0]].max, segment[1]].min

        snapped = nearest_split_snap(view, x, y, index, free_ratio)
        @split_ratio = snapped ? snapped[:ratio] : free_ratio
        @snap_label = snapped ? snapped[:label] : nil

        # TÂM hiển thị đúng tại vị trí chuột (hoặc điểm snap gần nhất).
        @split_point = split_point_for_ratio(@split_ratio, point)
        true
      rescue StandardError
        false
      end

      def nearest_split_snap(view, x, y, index, free_ratio)
        segment = @segments[index]
        a = segment[0].to_f
        b = segment[1].to_f

        candidates = [
          ['Tâm ván', (a + b) * 0.5],
          ['1/4 ván', a + (b - a) * 0.25],
          ['3/4 ván', a + (b - a) * 0.75]
        ]

        @segments.each_with_index do |other, i|
          candidates << ["Tâm cánh #{i + 1}", (other[0].to_f + other[1].to_f) * 0.5]
        end

        best = nil
        best_distance = SNAP_RADIUS + 1.0
        mouse_plane = point_on_region_from_mouse(view, x, y)

        candidates.each do |label, ratio|
          next unless ratio > a + 0.000001 && ratio < b - 0.000001
          point = split_point_for_ratio(ratio, mouse_plane)
          screen = view.screen_coords(point)
          dx = screen.x.to_f - x.to_f
          dy = screen.y.to_f - y.to_f
          distance = Math.sqrt(dx * dx + dy * dy)

          if distance <= SNAP_RADIUS && distance < best_distance
            best = { label: "Bắt gần nhất · #{label}", ratio: ratio }
            best_distance = distance
          end
        end

        best
      rescue StandardError
        nil
      end

      def split_point_for_ratio(ratio, mouse_point = nil)
        u0, u1, v0, v1 = adjusted_bounds
        mouse_point ||= point_on_plane((u0 + u1) * 0.5, (v0 + v1) * 0.5)
        vector = vector_between(@region[:origin], mouse_point)
        mouse_u = [[vector.dot(@region[:u]), u0].max, u1].min
        mouse_v = [[vector.dot(@region[:v]), v0].max, v1].min

        if @options['split_direction'] == 'Dọc'
          split_u = u0 + (u1 - u0) * ratio
          point_on_plane(split_u, mouse_v)
        else
          split_v = v0 + (v1 - v0) * ratio
          point_on_plane(mouse_u, split_v)
        end
      end

      def segment_index_at_mouse(view, x, y)
        return nil unless valid_region?

        point = point_on_region_from_mouse(view, x, y)
        return nil unless point

        u0, u1, v0, v1 = adjusted_bounds
        vector = vector_between(@region[:origin], point)
        u_value = vector.dot(@region[:u])
        v_value = vector.dot(@region[:v])
        return nil unless u_value >= u0 && u_value <= u1 && v_value >= v0 && v_value <= v1

        ratio = if @options['split_direction'] == 'Dọc'
          (u_value - u0) / (u1 - u0)
        else
          (v_value - v0) / (v1 - v0)
        end

        @segments.each_with_index do |segment, index|
          return index if ratio >= segment[0] - 0.000001 && ratio <= segment[1] + 0.000001
        end
        nil
      rescue StandardError
        nil
      end

      def nearest_handle(view, x, y)
        best = nil
        best_distance = SNAP_RADIUS + 1.0

        handle_points.each do |key, point|
          screen = view.screen_coords(point)
          dx = screen.x.to_f - x.to_f
          dy = screen.y.to_f - y.to_f
          distance = Math.sqrt(dx * dx + dy * dy)

          if distance <= SNAP_RADIUS && distance < best_distance
            best = key
            best_distance = distance
          end
        end

        best
      rescue StandardError
        nil
      end

      def point_inside_region_screen?(view, x, y)
        return false unless valid_region?

        point = point_on_region_from_mouse(view, x, y)
        return false unless point

        u0, u1, v0, v1 = adjusted_bounds
        vector = vector_between(@region[:origin], point)
        u_value = vector.dot(@region[:u])
        v_value = vector.dot(@region[:v])

        u_value >= u0 && u_value <= u1 &&
          v_value >= v0 && v_value <= v1
      rescue StandardError
        false
      end

      def draw_hover_point(view)
        view.draw_points(
          @hover_point,
          12,
          2,
          Sketchup::Color.new(37, 99, 235)
        )
      end

      def draw_p1(view)
        return unless @p1

        view.draw_points(
          @p1,
          14,
          2,
          Sketchup::Color.new(37, 99, 235)
        )
        screen = view.screen_coords(@p1)
        view.draw_text(
          [screen.x + 8, screen.y - 10],
          'P1',
          color: Sketchup::Color.new(24, 62, 104)
        )
      end

      def draw_hover_p2(view)
        view.draw_points(
          @hover_point,
          14,
          2,
          Sketchup::Color.new(245, 158, 11)
        )
        screen = view.screen_coords(@hover_point)
        view.draw_text(
          [screen.x + 8, screen.y - 10],
          'P2',
          color: Sketchup::Color.new(180, 83, 9)
        )
      end

      def draw_p2(view)
        view.draw_points(
          @p2,
          14,
          2,
          Sketchup::Color.new(245, 158, 11)
        )
        screen = view.screen_coords(@p2)
        view.draw_text(
          [screen.x + 8, screen.y - 10],
          'P2',
          color: Sketchup::Color.new(180, 83, 9)
        )
      end

      def draw_region_frame(view)
        return unless valid_region?

        u0, u1, v0, v1 = adjusted_bounds
        corners = [
          point_on_plane(u0, v0),
          point_on_plane(u1, v0),
          point_on_plane(u1, v1),
          point_on_plane(u0, v1)
        ]

        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(37, 99, 235)
        view.draw(GL_LINE_LOOP, corners)
      end

      def draw_preview_doors(view)
        @doors.each { |door| draw_door(view, door) }
      end

      def draw_door(view, door)
        alpha = @options['preview_alpha']
        front = door[:front]
        back = door[:back]

        view.drawing_color = Sketchup::Color.new(255, 191, 128, alpha)
        view.draw(GL_QUADS, front)

        view.drawing_color = Sketchup::Color.new(
          245, 153, 76, [alpha + 30, 210].min
        )
        view.draw(GL_QUADS, back)

        sides = [
          [front[0], front[1], back[1], back[0]],
          [front[1], front[2], back[2], back[1]],
          [front[2], front[3], back[3], back[2]],
          [front[3], front[0], back[0], back[3]]
        ]

        view.drawing_color = Sketchup::Color.new(
          241, 168, 96, [alpha + 15, 210].min
        )
        sides.each { |quad| view.draw(GL_QUADS, quad) }

        edges = [
          [front[0],front[1]],[front[1],front[2]],[front[2],front[3]],[front[3],front[0]],
          [back[0],back[1]],[back[1],back[2]],[back[2],back[3]],[back[3],back[0]],
          [front[0],back[0]],[front[1],back[1]],[front[2],back[2]],[front[3],back[3]]
        ]

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(198, 103, 32)
        view.draw(GL_LINES, edges.flatten(1))
      end

      def draw_committed_split_lines(view)
        return unless @split_committed
        return unless valid_region?
        return if @segments.nil? || @segments.length < 2

        u0, u1, v0, v1 = adjusted_bounds
        ratios = @segments[0...-1].map { |segment| segment[1].to_f }.uniq

        lines = []
        ratios.each do |ratio|
          if @options['split_direction'] == 'Dọc'
            split_u = u0 + (u1 - u0) * ratio
            lines << point_on_plane(split_u, v0)
            lines << point_on_plane(split_u, v1)
          else
            split_v = v0 + (v1 - v0) * ratio
            lines << point_on_plane(u0, split_v)
            lines << point_on_plane(u1, split_v)
          end
        end

        return if lines.empty?

        view.line_width = 4
        view.drawing_color = Sketchup::Color.new(37, 99, 235)
        view.draw(GL_LINES, lines)
      rescue StandardError => error
        puts "[TT DoorStandard committed splits] #{error.class}: #{error.message}"
      end

      def draw_center_handle(view, interactive)
        point = handle_points[:center]
        return unless point

        hovered = interactive && @hover_handle == :center
        color = hovered ?
          Sketchup::Color.new(22, 163, 74) :
          Sketchup::Color.new(234, 88, 12)

        bounds = active_segment_bounds
        if bounds
          u0, u1, v0, v1 = bounds
          segment = @segments[[@active_segment_index.to_i, @segments.length - 1].min]
          ratio = @split_ratio
          ratio = (segment[0] + segment[1]) * 0.5 unless ratio && ratio > segment[0] && ratio < segment[1]

          all_u0, all_u1, all_v0, all_v1 = adjusted_bounds
          guide = if @options['split_direction'] == 'Dọc'
            split_u = all_u0 + (all_u1 - all_u0) * ratio
            [point_on_plane(split_u, v0), point_on_plane(split_u, v1)]
          else
            split_v = all_v0 + (all_v1 - all_v0) * ratio
            [point_on_plane(u0, split_v), point_on_plane(u1, split_v)]
          end
          view.line_width = 2
          view.drawing_color = color
          view.draw(GL_LINES, guide)
        end

        view.draw_points(
          point,
          hovered ? 20 : 16,
          2,
          color
        )

        direction = @options['split_direction'] == 'Dọc' ? 'DỌC' : 'NGANG'
        label = "TÂM ĐỘNG · CHIA #{direction}"

        screen = view.screen_coords(point)
        view.draw_text(
          [screen.x + 10, screen.y - 12],
          label,
          color: color
        )
      end

      def draw_info(view)
        center = handle_points[:center]
        return unless center

        screen = view.screen_coords(center)
        text =
          "#{@segments.length} CÁNH · "           "#{format_mm(@region[:width])} × #{format_mm(@region[:height])} mm · "           "#{@options['split_direction']} · CHIA TỰ DO"

        view.draw_text(
          [screen.x + 18, screen.y + 22],
          text,
          color: Sketchup::Color.new(24, 62, 104)
        )
      rescue StandardError
      end

      def create_doors
        raise 'Chưa xác định khoang P1-P2.' unless valid_region?
        raise 'Preview cánh chưa hợp lệ.' if @doors.empty?

        model = @model
        model.start_operation('TT - Tạo Cánh Chuẩn', true)
        started = true

        root = model.active_entities.add_group
        root.name = "Cánh tủ #{@doors.length} cánh"
        root.set_attribute(DICT, 'version', VERSION)
        root.set_attribute(DICT, 'settings_json', JSON.generate(@options))
        root.set_attribute(DICT, 'split_segments_json', JSON.generate(@segments))

        source_pid = begin
          @face.respond_to?(:persistent_id) ? @face.persistent_id : 0
        rescue StandardError
          0
        end
        root.set_attribute(DICT, 'source_face_pid', source_pid)

        inverse_edit = model.edit_transform.inverse
        tag_name = @options['tag_name'].to_s.strip
        tag_name = "Cánh #{format('%.1f', @options['thickness']).sub('.0','')}mm" if tag_name.empty?
        board_tag = model.layers[tag_name] || model.layers.add(tag_name)
        root.layer = board_tag

        @doors.each_with_index do |door, index|
          child = root.entities.add_group
          child.name = format('%s %02d', @options['name_prefix'], index + 1)
          child.layer = board_tag
          child.set_attribute(DICT, 'is_door', true)
          child.set_attribute(DICT, 'index', index + 1)
          child.set_attribute(DICT, 'width_mm', door[:width].to_mm)
          child.set_attribute(DICT, 'height_mm', door[:height].to_mm)
          child.set_attribute(DICT, 'thickness_mm', @options['thickness'])

          front = door[:front].map { |point| point.transform(inverse_edit) }
          back = door[:back].map { |point| point.transform(inverse_edit) }
          entities = child.entities

          outward_local = @region[:normal].transform(inverse_edit)
          outward_local.normalize! if outward_local.length > 0.000001
          inward_local = outward_local.reverse

          front_face = entities.add_face(front)
          back_face  = entities.add_face(back.reverse)

          if front_face && front_face.normal.dot(outward_local) < 0.0
            front_face.reverse!
          end
          if back_face && back_face.normal.dot(inward_local) < 0.0
            back_face.reverse!
          end

          faces = [front_face, back_face]
          faces << entities.add_face(front[0], front[1], back[1], back[0])
          faces << entities.add_face(front[1], front[2], back[2], back[1])
          faces << entities.add_face(front[2], front[3], back[3], back[2])
          faces << entities.add_face(front[3], front[0], back[0], back[3])

          raise 'Không tạo được hình học cánh.' if faces.compact.length < 6
        end

        model.selection.clear
        model.selection.add(root)
        model.commit_operation
        started = false

        Sketchup.status_text =
          "Đã tạo #{@doors.length} cánh · tiếp tục bắt P1-P2 khoang kế tiếp."
        root
      rescue StandardError
        model.abort_operation if started rescue nil
        raise
      end

      def average_point(points)
        sx = points.inject(0.0) { |sum, point| sum + point.x }
        sy = points.inject(0.0) { |sum, point| sum + point.y }
        sz = points.inject(0.0) { |sum, point| sum + point.z }

        Geom::Point3d.new(
          sx / points.length,
          sy / points.length,
          sz / points.length
        )
      end

      def vector_between(a, b)
        Geom::Vector3d.new(
          b.x - a.x,
          b.y - a.y,
          b.z - a.z
        )
      end

      def project_vector_to_plane(vector, normal)
        dot = vector.dot(normal)
        Geom::Vector3d.new(
          vector.x - normal.x * dot,
          vector.y - normal.y * dot,
          vector.z - normal.z * dot
        )
      end

      def format_mm(length)
        format('%.1f', length.to_mm).sub(/\.0\z/, '')
      end

      def update_status
        Sketchup.status_text = case @state
        when :pick_p1
          'TẠO CÁNH · Click P1 trên Face bất kỳ · P1/P2 bắt điểm tự do, không khóa trục · TAB cài đặt.'
        when :pick_p2
          'Rê P2 chéo tự do trên mặt · tự bắt Endpoint/Edge/Inference · preview ván 3D theo chuột · click P2.'
        when :ready
          "P1-P2 · TÂM chạy theo chuột · / hoặc TÂM = chia tự do · 2/3/4 = chia nhanh · SHIFT Dọc/Ngang · CTRL Phủ/Lọt · ENTER = TẠO · TAB."
        end
      end
    end
  end

  # Tương thích nóng cho UI::Command cũ trong phiên SketchUp đang mở.
  # Source Vẽ Cánh Tủ cũ đã bị gỡ; lệnh cũ nếu còn trên toolbar sẽ gọi tool mới.
  remove_const(:CabinetDoor) if const_defined?(:CabinetDoor, false)
  module CabinetDoor
    extend self

    def show_gallery
      TranTuanNoiThat::DoorStandard.activate
    end

    def show(tool = nil)
      if tool
        TranTuanNoiThat::DoorStandard.show_settings(tool)
      else
        TranTuanNoiThat::DoorStandard.activate
      end
    end
  end
end
