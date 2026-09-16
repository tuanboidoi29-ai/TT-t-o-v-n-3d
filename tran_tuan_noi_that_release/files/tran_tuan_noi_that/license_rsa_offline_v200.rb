# encoding: UTF-8
# TRẦN TUẤN - LICENSE RSA OFFLINE V2.0.0
# Một cơ chế duy nhất: kích hoạt thủ công theo MÃ MÁY bằng chữ ký số RSA-3072 / SHA-256.
# PRIVATE KEY tuyệt đối KHÔNG nằm trong RBZ. Plugin chỉ chứa PUBLIC KEY để xác minh.

require 'openssl'
require 'base64'
require 'json'
require 'digest'
require 'open3'
require 'fileutils'
require 'time'

module TranTuanNoiThat
  module License
    extend self

    VERSION = '2.0.0'.freeze
    MACHINE_KEY = 'license_machine_code_v1'.freeze
    LICENSE_SCHEMA = 'TT_OFFLINE_RSA_V2'.freeze
    LICENSE_PREFIX = 'TTRSA2'.freeze
    RSA_ALGORITHM = 'RS256'.freeze
    RSA_KEY_ID = 'tt-offline-rsa-20260917'.freeze
    RSA_PUBLIC_FINGERPRINT = '33c04cf83b7d0a85e842d210854ffef499001a90c7ecd93681bc5f58e263ddc6'.freeze
    CLOCK_SKEW_SECONDS = 300

    ZALO = '033816946'.freeze
    BANK_NAME = 'KienlongBank'.freeze
    BANK_ACCOUNT = '0338162946'.freeze
    BANK_OWNER = 'TRẦN ĐÌNH TUẤN'.freeze

    PLANS = {
      '90d' => { 'label' => '90 ngày', 'days' => 90, 'price_vnd' => 50_000 },
      '180d' => { 'label' => '180 ngày', 'days' => 180, 'price_vnd' => 100_000 },
      '360d' => { 'label' => '360 ngày', 'days' => 360, 'price_vnd' => 120_000 },
      'lifetime' => { 'label' => 'Vĩnh viễn', 'days' => nil, 'price_vnd' => 200_000 }
    }.freeze

    RSA_PUBLIC_KEY_PEM = <<~PEM.freeze
      -----BEGIN PUBLIC KEY-----
      MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAoO4DR/Ec+sr1+S5gJp6H
      wB+dDPQKGmKSj2aGs/950NxXA3LR8hEnaOHFgMpqpKGmd8j5nT3MkncCc7PUmisC
      OHbdxmCNCI2VHeA1qeTC3hXG/0A84N2HW66jUPl9cx8vrujy+ilFIqu/0TAtpnc2
      0jCedRQNVQjpnGi1lw1yQIXo4Q+SdHMv4YyDNlz98eOcdhmqmPjt+ErM40COm+QW
      gnJdLLD1bAihsvU9oO4qeeY8zldqdL4b0hIW+5BAzE+F0tq0XEzz0yPibs1m8PT3
      GCFsFVR4lVqzUBwi7RUG4J2aNQ3dxCWK368tchSxvAy1881DExmRCkQtUpaUzrpz
      BH6GCOhYqK9T7ARQI7jarJlWiolOqC+pKzrGSXe/JJ0d+plXAVpq1o0dzTw2KsBO
      ILY4u7vf1FijBk4BImzyuW5y7W3sSZNpVH9Voc+wc0TUBEMowPSw/vIx5F/rLiGL
      cxxCIDVX/QZv5txvsEBHWa+Pa0nqjZ4YHiEV95F/F8EBAgMBAAE=
      -----END PUBLIC KEY-----
    PEM

    LEGACY_COMMERCIAL_FILES = %w[
      license_manager.rb
      license_payment_v110.rb
      license_owner_admin_v120.rb
      license_owner_admin_v121_fix.rb
      license_ui_v122_fix.rb
      license_owner_admin_v123_fix.rb
      license_commercial_v130_qr.rb
      license_commercial_v140_auto.rb
      license_rsa_v150.rb
    ].freeze

    def machine_code
      raw = windows_machine_guid.to_s.strip
      if raw.empty?
        cached = TranTuanNoiThat.setting(MACHINE_KEY, '').to_s.strip.upcase
        return cached if cached.match?(/\ATT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
        raw = [ENV['COMPUTERNAME'], ENV['USERNAME'], RUBY_PLATFORM].compact.join('|')
      end

      digest = Digest::SHA256.hexdigest("TRANTUAN|#{raw}").upcase
      code = "TT-#{digest[0, 4]}-#{digest[4, 4]}-#{digest[8, 4]}"
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
      line.strip.split(/\s+/).last.to_s.strip
    rescue StandardError
      ''
    end

    def cleanup_legacy_commercial_artifacts
      begin
        root = defined?(TranTuanNoiThat::ROOT) ? TranTuanNoiThat::ROOT.to_s : ''
        LEGACY_COMMERCIAL_FILES.each do |name|
          path = File.join(root, name)
          File.delete(path) if !root.empty? && File.file?(path)
        end
      rescue StandardError => error
        puts "[TT RSA cleanup files] #{error.class}: #{error.message}"
      end

      begin
        %w[license_cache_v3.json license_rsa_v1.json].each do |name|
          path = File.join(license_dir, name)
          File.delete(path) if File.file?(path)
        end
      rescue StandardError => error
        puts "[TT RSA cleanup cache] #{error.class}: #{error.message}"
      end
      true
    end

    def license_dir
      base = ENV['APPDATA'].to_s
      base = ENV['LOCALAPPDATA'].to_s if base.empty?
      base = Dir.home.to_s if base.empty?
      File.join(base, 'TranTuanNoiThat', 'license')
    end

    def license_file
      File.join(license_dir, 'rsa_offline_activation_v2.json')
    end

    def public_key
      @public_key ||= OpenSSL::PKey::RSA.new(RSA_PUBLIC_KEY_PEM)
    end

    def b64url_decode(text)
      value = text.to_s.tr('-_', '+/')
      value += '=' * ((4 - value.length % 4) % 4)
      Base64.strict_decode64(value)
    end

    def clean_activation_code(text)
      text.to_s.gsub(/\s+/, '')
    end

    def parse_activation_code(code, public_key_pem = RSA_PUBLIC_KEY_PEM, expected_machine = machine_code, now = Time.now)
      clean = clean_activation_code(code)
      parts = clean.split('.')
      raise 'Mã kích hoạt sai định dạng.' unless parts.length == 3 && parts[0] == LICENSE_PREFIX

      raw = b64url_decode(parts[1])
      signature = b64url_decode(parts[2])
      raise 'Mã kích hoạt thiếu dữ liệu.' if raw.empty? || signature.empty?
      verifier = OpenSSL::PKey::RSA.new(public_key_pem.to_s)
      raise 'Chữ ký RSA không hợp lệ.' unless verifier.verify(OpenSSL::Digest::SHA256.new, signature, raw)

      text = raw.dup.force_encoding('UTF-8')
      raise 'Payload bản quyền không phải UTF-8.' unless text.valid_encoding?
      data = JSON.parse(text)
      raise 'Sai schema bản quyền.' unless data['schema'].to_s == LICENSE_SCHEMA
      raise 'Sai thuật toán chữ ký.' unless data['alg'].to_s == RSA_ALGORITHM
      raise 'Sai khóa ký bản quyền.' unless data['key_id'].to_s == RSA_KEY_ID
      raise 'License không thuộc Mã máy này.' unless data['machine_code'].to_s.upcase == expected_machine.to_s.upcase

      plan = data['plan'].to_s
      raise 'Gói bản quyền không hợp lệ.' unless PLANS.key?(plan)

      issued_at = Time.iso8601(data['issued_at'].to_s)
      raise 'Thời gian phát hành không hợp lệ.' if issued_at > now + CLOCK_SKEW_SECONDS

      if plan == 'lifetime'
        expires_at = nil
      else
        expires_text = data['expires_at'].to_s
        raise 'License thiếu ngày hết hạn.' if expires_text.empty?
        expires_at = Time.iso8601(expires_text)
        raise 'License đã hết hạn.' if expires_at <= now - CLOCK_SKEW_SECONDS
        raise 'Ngày hết hạn không hợp lệ.' if expires_at <= issued_at
      end

      {
        'ok' => true,
        'activation_code' => clean,
        'license_id' => data['license_id'].to_s,
        'machine_code' => data['machine_code'].to_s.upcase,
        'plan' => plan,
        'plan_label' => PLANS[plan]['label'],
        'price_vnd' => PLANS[plan]['price_vnd'],
        'issued_at' => issued_at.utc.iso8601,
        'expires_at' => expires_at ? expires_at.utc.iso8601 : nil,
        'lifetime' => plan == 'lifetime',
        'rsa_verified' => true,
        'key_id' => RSA_KEY_ID,
        'fingerprint' => RSA_PUBLIC_FINGERPRINT
      }
    rescue JSON::ParserError, ArgumentError => error
      raise "Mã kích hoạt không hợp lệ: #{error.message}"
    end

    def save_activation(state)
      FileUtils.mkdir_p(license_dir)
      wrapper = {
        'format' => 'TT_RSA_OFFLINE_ACTIVATION_V2',
        'saved_at' => Time.now.utc.iso8601,
        'activation_code' => state['activation_code'].to_s
      }
      tmp = "#{license_file}.tmp"
      File.open(tmp, 'wb') { |file| file.write(JSON.generate(wrapper)) }
      FileUtils.mv(tmp, license_file, force: true)
      @state_cache = state
      state
    end

    def activate(code)
      state = parse_activation_code(code)
      save_activation(state)
      state
    end

    def clear_activation
      File.delete(license_file) if File.file?(license_file)
      @state_cache = nil
      true
    rescue StandardError
      false
    end

    def state
      cached = @state_cache
      if cached.is_a?(Hash) && cached['rsa_verified'] == true
        begin
          return parse_activation_code(cached['activation_code'])
        rescue StandardError
          @state_cache = nil
        end
      end

      return invalid_state('Chưa nhập Mã kích hoạt.') unless File.file?(license_file)
      wrapper = JSON.parse(File.read(license_file, mode: 'r:BOM|UTF-8'))
      code = wrapper.is_a?(Hash) ? wrapper['activation_code'].to_s : ''
      return invalid_state('Chưa nhập Mã kích hoạt.') if code.empty?
      @state_cache = parse_activation_code(code)
    rescue StandardError => error
      invalid_state(error.message)
    end

    def invalid_state(message = '')
      {
        'ok' => false,
        'rsa_verified' => false,
        'machine_code' => machine_code,
        'message' => message.to_s,
        'plan' => '',
        'plan_label' => '',
        'expires_at' => nil,
        'lifetime' => false
      }
    end

    def valid?
      state['ok'] == true && state['rsa_verified'] == true
    rescue StandardError
      false
    end

    def remaining_days(current = state)
      return nil unless current.is_a?(Hash) && current['ok'] == true
      return nil if current['lifetime'] == true
      expires = Time.iso8601(current['expires_at'].to_s)
      seconds = expires - Time.now
      days = (seconds / 86_400.0).ceil
      days < 0 ? 0 : days
    rescue StandardError
      0
    end

    # Toàn bộ công cụ dùng chung một giấy phép RSA. Không còn quyền theo từng chức năng.
    def allowed?(_feature = nil, interactive = true)
      return true if valid?
      show_dialog if interactive
      false
    end

    # Giữ tương thích với bootstrap cũ; V2.0.0 không còn gọi server.
    def background_sync
      true
    end

    def sync_now(_feature = nil)
      refresh_dialog
      state
    end

    def show_dialog(_feature = nil)
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        refresh_dialog
        return true
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - KÍCH HOẠT BẢN QUYỀN RSA',
        preferences_key: 'TranTuanNoiThat.RSAOfflineV200',
        scrollable: true,
        resizable: true,
        width: 700,
        height: 780,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('ready') { |_ctx| refresh_dialog }
      @dialog.add_action_callback('activate_code') do |_ctx, code|
        begin
          activate(code)
          refresh_dialog
          UI.messagebox('Kích hoạt bản quyền thành công.')
        rescue StandardError => error
          @last_error = error.message
          refresh_dialog(invalid_state(error.message))
        end
      end
      @dialog.add_action_callback('clear_code') do |_ctx|
        clear_activation
        refresh_dialog
      end
      @dialog.show
      true
    rescue StandardError => error
      UI.messagebox("Không mở được bảng Bản Quyền:\n#{error.message}")
      false
    end

    def refresh_dialog(state_override = nil)
      return false unless @dialog && @dialog.visible?
      current = state_override.is_a?(Hash) ? state_override : state
      payload = {
        machine_code: machine_code,
        active: current['ok'] == true && current['rsa_verified'] == true,
        status_message: current['message'].to_s,
        plan: current['plan'].to_s,
        plan_label: current['plan_label'].to_s,
        expires_at: current['expires_at'],
        lifetime: current['lifetime'] == true,
        remaining_days: remaining_days(current),
        zalo: ZALO,
        bank_name: BANK_NAME,
        bank_account: BANK_ACCOUNT,
        bank_owner: BANK_OWNER,
        transfer_note: machine_code
      }
      @dialog.execute_script("window.renderLicense(#{JSON.generate(payload)})")
      true
    rescue StandardError => error
      puts "[TT RSA Offline UI] #{error.class}: #{error.message}"
      false
    end

    def dialog_html
      <<~HTML
        <!doctype html>
        <html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:14px Arial}.head{padding:18px 22px;background:linear-gradient(135deg,#ea580c,#c2410c)}h1{margin:0;font-size:21px}.sub{margin-top:5px;font-size:12px;opacity:.92}.body{padding:17px}.box{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:14px;margin-bottom:12px}.label{font-size:11px;color:#94a3b8;margin-bottom:5px}.code{font:700 20px Consolas,monospace;color:#fb923c;letter-spacing:.6px;word-break:break-all}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.btn{border:0;border-radius:8px;padding:9px 12px;font-weight:700;cursor:pointer}.orange{background:#f97316;color:white}.dark{background:#334155;color:white}.red{background:#b91c1c;color:white}.green{background:#059669;color:white}.ok{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}.muted{color:#94a3b8}.note{line-height:1.55;color:#cbd5e1}.price{width:100%;border-collapse:collapse;margin-top:8px}.price th,.price td{border-bottom:1px solid #334155;padding:9px 6px;text-align:left}.price th:last-child,.price td:last-child{text-align:right}.price tr:last-child td{border-bottom:0}.money{font-weight:700;color:#fbbf24}.bank{display:grid;grid-template-columns:145px 1fr;gap:8px 10px;margin-top:8px}.bank b{color:#e2e8f0}textarea{width:100%;height:105px;background:#0b1220;color:#e5e7eb;border:1px solid #475569;border-radius:8px;padding:10px;font:12px Consolas,monospace;resize:vertical}.status{padding:10px;border-radius:8px;background:#111827;margin-top:10px}.steps{margin:8px 0 0;padding-left:20px;line-height:1.7}.zalo{font-size:17px;color:#60a5fa;font-weight:800}.pill{display:inline-block;border-radius:999px;padding:4px 8px;font-size:12px;font-weight:700;background:#334155}.pill.ok{background:#065f46;color:#d1fae5}</style></head><body>
        <div class="head"><h1>TRẦN TUẤN · KÍCH HOẠT BẢN QUYỀN RSA</h1><div class="sub">Kích hoạt theo MÃ MÁY · xác minh offline bằng chữ ký số RSA</div></div>
        <div class="body">
          <div class="box"><div class="label">MÃ MÁY</div><div id="machineCode" class="code">-</div><div class="row" style="margin-top:10px"><button class="btn dark" onclick="copyText(document.getElementById('machineCode').textContent,this)">SAO CHÉP MÃ MÁY</button></div></div>

          <div class="box"><div class="label">NHẬP MÃ KÍCH HOẠT</div><textarea id="activationCode" placeholder="Dán Mã bản quyền RSA vào đây..."></textarea><div class="row" style="margin-top:9px"><button class="btn orange" onclick="activateNow()">KÍCH HOẠT</button><button class="btn dark" onclick="pasteCode()">DÁN MÃ</button><button class="btn red" onclick="clearLicense()">XÓA MÃ ĐÃ LƯU</button></div><div id="statusBox" class="status"><b>Trạng thái:</b> <span id="licenseStatus">CHƯA KÍCH HOẠT</span><div id="licenseMeta" class="muted" style="margin-top:6px"></div></div></div>

          <div class="box"><b>HƯỚNG DẪN NHẬN MÃ BẢN QUYỀN</b><ol class="steps"><li>Kết bạn Zalo <span class="zalo">#{ZALO}</span>.</li><li>Gửi <b>Mã máy</b> ở phía trên.</li><li>Chọn thời hạn và chuyển khoản.</li><li>Nhận <b>Mã kích hoạt RSA</b> từ TRẦN TUẤN.</li><li>Dán mã vào ô <b>NHẬP MÃ KÍCH HOẠT</b> → bấm <b>KÍCH HOẠT</b> → sử dụng.</li></ol></div>

          <div class="box"><b>BẢNG GIÁ BẢN QUYỀN</b><table class="price"><tr><th>Thời hạn</th><th>Giá</th></tr><tr><td>90 ngày</td><td class="money">50.000đ</td></tr><tr><td>180 ngày</td><td class="money">100.000đ</td></tr><tr><td>360 ngày</td><td class="money">120.000đ</td></tr><tr><td>Vĩnh viễn</td><td class="money">200.000đ</td></tr></table></div>

          <div class="box"><b>THÔNG TIN CHUYỂN KHOẢN</b><div class="bank"><b>Ngân hàng</b><span>#{BANK_NAME}</span><b>Số tài khoản</b><span class="code" style="font-size:16px">#{BANK_ACCOUNT}</span><b>Chủ tài khoản</b><span>#{BANK_OWNER}</span><b>Nội dung CK</b><span id="transferNote" class="code" style="font-size:15px">-</span></div><div class="row" style="margin-top:10px"><button class="btn dark" onclick="copyBank(this)">SAO CHÉP THÔNG TIN CK</button></div></div>

          <div class="note">Mã kích hoạt được ký bằng PRIVATE KEY của TRẦN TUẤN và chỉ hợp lệ với đúng Mã máy. Plugin chỉ chứa PUBLIC KEY để xác minh; không có cơ chế mua từng chức năng và không cần kết nối máy chủ để sử dụng sau khi kích hoạt.</div>
        </div>
        <script>
        const el=id=>document.getElementById(id);let DATA={};
        function copyText(value,btn){const t=document.createElement('textarea');t.value=value||'';t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();try{document.execCommand('copy');if(btn){const old=btn.textContent;btn.textContent='ĐÃ SAO CHÉP';setTimeout(()=>btn.textContent=old,1000);}}catch(e){}document.body.removeChild(t);}
        async function pasteCode(){try{const t=await navigator.clipboard.readText();if(t)el('activationCode').value=t;}catch(e){}}
        function activateNow(){const code=el('activationCode').value.trim();if(!code){alert('Hãy nhập Mã kích hoạt.');return;}sketchup.activate_code(code);}
        function clearLicense(){if(confirm('Xóa Mã kích hoạt đã lưu trên máy này?'))sketchup.clear_code();}
        function copyBank(btn){const text='Ngân hàng: '+DATA.bank_name+'\\nSố tài khoản: '+DATA.bank_account+'\\nChủ tài khoản: '+DATA.bank_owner+'\\nNội dung CK: '+DATA.transfer_note;copyText(text,btn);}
        window.renderLicense=d=>{DATA=d||{};el('machineCode').textContent=d.machine_code||'-';el('transferNote').textContent=d.transfer_note||d.machine_code||'-';const st=el('licenseStatus');const meta=el('licenseMeta');if(d.active){st.textContent='ĐÃ KÍCH HOẠT';st.className='ok';let m='Gói: '+(d.plan_label||'-');if(d.lifetime){m+=' · VĨNH VIỄN';}else{m+=' · Hết hạn: '+(d.expires_at||'-')+' · Còn '+String(d.remaining_days==null?'-':d.remaining_days)+' ngày';}meta.textContent=m;}else{st.textContent='CHƯA KÍCH HOẠT';st.className='bad';meta.textContent=d.status_message||'Hãy gửi Mã máy qua Zalo để nhận Mã kích hoạt.';}};
        document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
        </script></body></html>
      HTML
    end
  end
end

# Dọn dấu vết runtime/cache của cơ chế thương mại cũ sau khi V2.0.0 được nạp.
begin
  TranTuanNoiThat::License.cleanup_legacy_commercial_artifacts
rescue StandardError
end
