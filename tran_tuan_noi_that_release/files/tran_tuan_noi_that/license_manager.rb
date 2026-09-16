# encoding: UTF-8
require 'json'
require 'net/http'
require 'uri'
require 'digest'
require 'open3'

module TranTuanNoiThat
  module License
    extend self

    VERSION = '1.0.1'.freeze
    ENDPOINT = 'https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-license-check'.freeze
    CACHE_KEY = 'license_cache_v2'.freeze
    CACHE_TIME_KEY = 'license_cache_time_v2'.freeze
    MACHINE_KEY = 'license_machine_code_v1'.freeze
    DEFAULT_GRACE_HOURS = 72

    FEATURE_NAMES = {
      board: 'Vẽ Ván',
      box: 'Tạo Khối BOX',
      drawer: 'Vẽ Ngăn Kéo',
      round: 'Bo Cong Khối',
      stretch_mode: 'Co Giãn Khối MODE',
      grain: 'Xoay Vân Ván',
      layout_stats: 'Xuất Layout + Thống Kê Ván',
      render_ai: 'TT Render AI'
    }.freeze

    def machine_code
      cached = TranTuanNoiThat.setting(MACHINE_KEY, '').to_s.strip.upcase
      return cached if cached.match?(/\ATT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/)

      raw = windows_machine_guid
      raw = [ENV['COMPUTERNAME'], ENV['USERNAME'], RUBY_PLATFORM].compact.join('|') if raw.to_s.empty?
      digest = Digest::SHA256.hexdigest("TRANTUAN|#{raw}").upcase
      code = "TT-#{digest[0,4]}-#{digest[4,4]}-#{digest[8,4]}"
      TranTuanNoiThat.save_setting(MACHINE_KEY, code)
      code
    rescue StandardError
      'TT-0000-0000-0000'
    end

    def windows_machine_guid
      return '' unless RUBY_PLATFORM =~ /mswin|mingw/i
      stdout, = Open3.capture3('reg query "HKLM\\SOFTWARE\\Microsoft\\Cryptography" /v MachineGuid')
      line = stdout.to_s.lines.find { |item| item =~ /MachineGuid/i }
      return '' unless line
      parts = line.strip.split(/\s+/)
      parts.last.to_s.strip
    rescue StandardError
      ''
    end

    def normalize_payload(payload)
      data = payload.is_a?(Hash) ? payload.dup : {}
      features = data['features'].is_a?(Hash) ? data['features'].dup : {}

      if features.empty? && data['feature_list'].is_a?(Array)
        data['feature_list'].each do |item|
          next unless item.is_a?(Hash)
          slug = item['slug'].to_s
          next if slug.empty?
          features[slug] = item
        end
      end

      data['features'] = features
      data['feature_count'] = features.length if data['feature_count'].to_i <= 0 && !features.empty?
      data
    rescue StandardError
      payload.is_a?(Hash) ? payload : {}
    end

    def cache
      raw = TranTuanNoiThat.setting(CACHE_KEY, '').to_s
      return {} if raw.empty?
      normalize_payload(JSON.parse(raw))
    rescue StandardError
      {}
    end

    def cache_time
      TranTuanNoiThat.setting(CACHE_TIME_KEY, 0).to_i
    rescue StandardError
      0
    end

    def save_cache(payload)
      payload = normalize_payload(payload)
      TranTuanNoiThat.save_setting(CACHE_KEY, JSON.generate(payload))
      TranTuanNoiThat.save_setting(CACHE_TIME_KEY, Time.now.to_i)
      payload
    rescue StandardError
      payload
    end

    def stale?(payload = cache)
      grace = payload['offline_grace_hours'].to_i
      grace = DEFAULT_GRACE_HOURS if grace <= 0
      Time.now.to_i - cache_time > grace * 3600
    rescue StandardError
      true
    end

    def enforcement?(payload = cache)
      payload['commercial_enforcement'] == true
    end

    def feature_info(feature, payload = cache)
      key = feature.to_s
      payload = normalize_payload(payload)
      features = payload['features'].is_a?(Hash) ? payload['features'] : {}
      features[key].is_a?(Hash) ? features[key] : {}
    end

    def cached_allowed?(feature)
      payload = cache
      return true unless enforcement?(payload)
      return false if stale?(payload)
      feature_info(feature, payload)['allowed'] == true
    rescue StandardError
      false
    end

    def allowed?(feature, interactive = true)
      feature = feature.to_sym
      payload = cache

      unless enforcement?(payload)
        background_sync if stale?(payload) || payload.empty?
        return true
      end

      info = feature_info(feature, payload)
      return true if !stale?(payload) && info['allowed'] == true

      fresh = sync_now(feature)
      return true if fresh && feature_info(feature, fresh)['allowed'] == true

      show_dialog(feature) if interactive
      false
    rescue StandardError => error
      puts "[TT License] #{error.class}: #{error.message}"
      show_dialog(feature) if interactive
      false
    end

    def sync_now(feature = nil)
      payload = request_status(feature)
      return nil unless payload.is_a?(Hash) && payload['ok'] == true
      payload = save_cache(payload)
      refresh_dialog
      payload
    rescue StandardError => error
      puts "[TT License sync] #{error.class}: #{error.message}"
      nil
    end

    def background_sync
      return true if @syncing
      @syncing = true
      @pending_sync_payload = :waiting
      @pending_sync_error = nil
      code = machine_code
      version = TranTuanNoiThat.current_version.to_s

      Thread.new do
        begin
          @pending_sync_payload = request_status_raw(code, version, nil)
        rescue StandardError => error
          @pending_sync_error = error
          @pending_sync_payload = nil
        end
      end

      @sync_poll_timer = UI.start_timer(0.20, true) do
        next if @pending_sync_payload == :waiting
        UI.stop_timer(@sync_poll_timer) if @sync_poll_timer
        payload = @pending_sync_payload
        error = @pending_sync_error
        @pending_sync_payload = nil
        @pending_sync_error = nil
        @syncing = false
        save_cache(payload) if payload.is_a?(Hash) && payload['ok'] == true
        puts "[TT License background] #{error.class}: #{error.message}" if error
        refresh_dialog
      end
      true
    rescue StandardError => error
      @syncing = false
      puts "[TT License background start] #{error.class}: #{error.message}"
      false
    end

    def request_status(feature = nil)
      request_status_raw(machine_code, TranTuanNoiThat.current_version.to_s, feature)
    end

    def request_status_raw(code, version, feature)
      uri = URI.parse(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 4
      http.read_timeout = 6
      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req['Cache-Control'] = 'no-cache, no-store'
      req['Pragma'] = 'no-cache'
      req['X-TT-Request'] = "#{Time.now.to_i}-#{rand(1_000_000)}"
      req.body = JSON.generate({
        machine_code: code,
        plugin_version: version,
        feature: feature && feature.to_s
      })
      response = http.request(req)
      return nil unless response.is_a?(Net::HTTPSuccess)
      normalize_payload(JSON.parse(response.body.to_s))
    end

    def show_dialog(feature = nil)
      @requested_feature = feature && feature.to_sym
      if @dialog && @dialog.visible?
        refresh_dialog
        background_sync if cache.empty? || stale?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - BẢN QUYỀN',
        preferences_key: 'TranTuanNoiThat.LicenseV2',
        scrollable: true,
        resizable: true,
        width: 580,
        height: 700,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('ready') do |_ctx|
        refresh_dialog
        background_sync if cache.empty? || stale?
      end
      @dialog.add_action_callback('check') do |_ctx|
        payload = sync_now(@requested_feature)
        UI.beep unless payload
      end
      @dialog.show
    end

    def refresh_dialog
      return unless @dialog && @dialog.visible?
      payload = normalize_payload(cache)
      feature = @requested_feature
      info = feature ? feature_info(feature, payload) : {}
      features = payload['features'].is_a?(Hash) ? payload['features'] : {}
      data = {
        machine_code: machine_code,
        version: VERSION,
        plugin_version: TranTuanNoiThat.current_version,
        api_version: payload['api_version'],
        enforcement: enforcement?(payload),
        machine_status: payload['machine_status'] || 'chưa đồng bộ',
        machine_role: payload['machine_role'] || 'customer',
        owner: payload['owner'] == true,
        feature_count: payload['feature_count'].to_i > 0 ? payload['feature_count'].to_i : features.length,
        requested_feature: feature && feature.to_s,
        requested_name: feature ? (FEATURE_NAMES[feature] || feature.to_s) : '',
        requested_allowed: info['allowed'] == true,
        requested_purchased: info['purchased'] == true,
        requested_price: info['price_vnd'],
        features: features,
        feature_list: payload['feature_list'].is_a?(Array) ? payload['feature_list'] : [],
        synced_at: cache_time > 0 ? Time.at(cache_time).strftime('%d/%m/%Y %H:%M:%S') : 'chưa có'
      }
      @dialog.execute_script("window.renderLicense(#{JSON.generate(data)})")
    rescue StandardError => error
      puts "[TT License UI] #{error.class}: #{error.message}"
    end

    def dialog_html
      <<~HTML
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;background:#111827;color:#e5e7eb;font:14px Arial}.head{padding:18px 22px;background:linear-gradient(135deg,#f97316,#c2410c)}h1{margin:0;font-size:21px}.sub{margin-top:5px;font-size:12px;opacity:.9}.body{padding:18px}.box{background:#1f2937;border:1px solid #374151;border-radius:12px;padding:14px;margin-bottom:12px}.label{font-size:11px;color:#9ca3af;margin-bottom:5px}.code{font:700 21px Consolas,monospace;letter-spacing:1px;color:#fb923c}.row{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}button{border:0;border-radius:8px;padding:10px 13px;font-weight:700;cursor:pointer}.orange{background:#f97316;color:#fff}.dark{background:#374151;color:#fff}.ok{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}.muted{color:#9ca3af}.owner{display:inline-block;background:#065f46;color:#d1fae5;border:1px solid #10b981;border-radius:999px;padding:4px 9px;font-weight:700;margin-left:7px}.feature{display:flex;justify-content:space-between;gap:8px;padding:9px 0;border-bottom:1px solid #374151}.feature:last-child{border-bottom:0}.price{color:#fbbf24}.note{font-size:12px;color:#9ca3af;line-height:1.5}.empty{padding:12px 0;color:#fbbf24}</style></head><body>
        <div class="head"><h1>TRẦN TUẤN · KÍCH HOẠT BẢN QUYỀN</h1><div class="sub">Chỉ sử dụng MÃ MÁY · không cần tài khoản/mật khẩu</div></div>
        <div class="body">
          <div class="box"><div class="label">MÃ MÁY</div><div id="machineCode" class="code">-</div><div class="row"><button class="dark" onclick="copyCode(this)">SAO CHÉP MÃ</button><button class="orange" onclick="sketchup.check()">KIỂM TRA KÍCH HOẠT</button></div></div>
          <div id="requestedBox" class="box" style="display:none"></div>
          <div class="box"><div><b>Trạng thái máy:</b> <span id="machineStatus">-</span><span id="ownerBadge"></span></div><div style="margin-top:6px"><b>Đồng bộ:</b> <span id="syncTime">-</span></div><div style="margin-top:6px"><b>Quyền:</b> <span id="rightsCount">0/0</span></div><div style="margin-top:6px"><b>Chế độ thương mại:</b> <span id="commercialMode">-</span></div></div>
          <div class="box"><b>QUYỀN CHỨC NĂNG</b><div id="featureList" style="margin-top:8px"></div></div>
          <div class="note">Khi chức năng chưa được mua, hãy gửi Mã máy cho TRẦN TUẤN để thanh toán/kích hoạt. Sau khi được cấp quyền, bấm KIỂM TRA KÍCH HOẠT và dùng ngay, không cần cài lại RBZ.</div>
        </div>
        <script>
        const el=id=>document.getElementById(id);
        const money=v=>v==null?'Liên hệ':Number(v).toLocaleString('vi-VN')+' đ';
        function copyCode(btn){const t=document.createElement('textarea');t.value=el('machineCode').textContent;t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();try{document.execCommand('copy');btn.textContent='ĐÃ SAO CHÉP';setTimeout(()=>btn.textContent='SAO CHÉP MÃ',1200);}catch(e){}document.body.removeChild(t);}
        function statusText(v){if(v==='active')return 'ACTIVE · ĐÃ KÍCH HOẠT';if(v==='pending')return 'CHỜ KÍCH HOẠT';if(v==='blocked')return 'ĐÃ KHÓA';return String(v||'CHƯA ĐỒNG BỘ').toUpperCase();}
        window.renderLicense=d=>{
          el('machineCode').textContent=d.machine_code||'-';
          el('machineStatus').textContent=statusText(d.machine_status);
          el('machineStatus').className=d.machine_status==='active'?'ok':(d.machine_status==='blocked'?'bad':'muted');
          el('syncTime').textContent=d.synced_at||'-';
          el('commercialMode').textContent=d.enforcement?'ĐANG BẬT':'CHƯA BẬT';
          el('commercialMode').className=d.enforcement?'ok':'muted';
          el('ownerBadge').innerHTML=d.owner?'<span class="owner">OWNER</span>':'';

          const r=el('requestedBox');
          if(d.requested_feature){r.style.display='block';r.innerHTML='<b>'+d.requested_name+'</b><div style="margin-top:7px" class="'+(d.requested_allowed?'ok':'bad')+'">'+(d.requested_allowed?'ĐÃ KÍCH HOẠT':'CHƯA ĐƯỢC KÍCH HOẠT')+'</div><div class="price" style="margin-top:5px">Giá: '+money(d.requested_price)+'</div>';}else{r.style.display='none';}

          let items=[];
          if(d.features&&typeof d.features==='object'&&!Array.isArray(d.features)){items=Object.keys(d.features).map(k=>Object.assign({slug:k},d.features[k]||{}));}
          if(items.length===0&&Array.isArray(d.feature_list)){items=d.feature_list;}
          const f=el('featureList');f.innerHTML='';
          if(items.length===0){f.innerHTML='<div class="empty">Chưa tải được danh sách quyền. Hãy bấm KIỂM TRA KÍCH HOẠT.</div>';}
          let opened=0;
          items.forEach(x=>{if(x.allowed)opened++;const e=document.createElement('div');e.className='feature';e.innerHTML='<span>'+String(x.name||x.slug||'Chức năng')+'</span><span class="'+(x.allowed?'ok':'bad')+'">'+(x.allowed?'ĐÃ MỞ':'KHÓA')+(d.owner?'':' · '+money(x.price_vnd))+'</span>';f.appendChild(e);});
          el('rightsCount').textContent=opened+'/'+items.length;
        };
        document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
        </script></body></html>
      HTML
    end
  end
end
