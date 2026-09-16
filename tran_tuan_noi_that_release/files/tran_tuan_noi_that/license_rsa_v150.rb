# encoding: UTF-8
# TRẦN TUẤN - LICENSE RSA V1.5.0
# Khóa bản quyền theo MÃ MÁY bằng chữ ký số RSA-3072 / SHA-256.
# PRIVATE KEY chỉ ở server. Plugin chỉ chứa PUBLIC KEY để xác minh.

require 'openssl'
require 'base64'
require 'time'
require 'fileutils'
require 'json'
require 'digest'

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.5.0'.freeze

    RSA_SCHEMA = 'TT_LICENSE_RSA_V1'.freeze
    RSA_ALGORITHM = 'RS256'.freeze
    RSA_KEY_ID = 'tt-rsa-20260916-28302d4e'.freeze
    RSA_PUBLIC_FINGERPRINT = 'd38044559f2e3b624df8492fb1ac2a61375f3f85615a0b539b67a5245e663bfc'.freeze
    RSA_CLOCK_SKEW_SECONDS = 300
    RSA_REFRESH_MARGIN_SECONDS = 60
    RSA_FREE_FEATURES = %i[board box].freeze

    RSA_PUBLIC_KEY_PEM = <<~PEM.freeze
      -----BEGIN PUBLIC KEY-----
      MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAouvyl1lmPv+mD5qJK0C6
      xsT9pD+yvzqyRPoJC+ve6TPfoKATaLZKcjck1M+h+JB+2uGmCrJ1h6D3sJuKsTjo
      KZHIuq2+oV5AfFBlsRnWp4y/4V7tWXwx3UHJPjcXWGDHV/SfjNX6eI0EKcwcdpXI
      2x2xocYL07R5D1bWRfIVTyYOhk9oOxePubBwJnwYz1iGYH6eklrjg/i8IzWF3ydy
      yU3AozWkwzOEKN+iM93Gaj9u4tkxt0j0pOTKR9K69DQAYb0af3BQGkl8kZQP6KkB
      Yn8EDxnNM9JU4bkuKsEQmJdI0EOZ17Ei6BTGkOeSpPJRvQwBuAt+vNV+3ggpfK6F
      l1aeJMN+65STNEBSSc6cDqLTCfKHrvS+gWas/ZDUiZNnkLTzURn0O1YdjVtduOKc
      RjeoVUtAE+Fpdb7hUKB3xS3VvpNHjqA8/F1qsOIHud/DUWAoTJ5SJndxDuE4ZXvF
      d3Zvm6iAnnnX4cUi31039N1DCOnaQmKGs2clF9xgdqFPAgMBAAE=
      -----END PUBLIC KEY-----
    PEM

    unless method_defined?(:tt_machine_code_before_rsa_v150)
      alias_method :tt_machine_code_before_rsa_v150, :machine_code
    end
    unless method_defined?(:tt_request_status_raw_before_rsa_v150)
      alias_method :tt_request_status_raw_before_rsa_v150, :request_status_raw
    end
    unless method_defined?(:tt_refresh_dialog_before_rsa_v150)
      alias_method :tt_refresh_dialog_before_rsa_v150, :refresh_dialog
    end
    unless method_defined?(:tt_dialog_html_before_rsa_v150)
      alias_method :tt_dialog_html_before_rsa_v150, :dialog_html
    end

    # Không tin Mã máy đã lưu trong Registry. Nếu MachineGuid đọc được thì luôn
    # tính lại tại máy hiện tại; như vậy copy cache/license sang PC khác sẽ fail.
    def machine_code
      return @rsa_machine_code_v150 if @rsa_machine_code_v150.to_s.match?(/\ATT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/)

      raw = windows_machine_guid.to_s.strip
      if !raw.empty?
        digest = Digest::SHA256.hexdigest("TRANTUAN|#{raw}").upcase
        code = "TT-#{digest[0, 4]}-#{digest[4, 4]}-#{digest[8, 4]}"
        @rsa_machine_code_v150 = code
        begin
          TranTuanNoiThat.save_setting(MACHINE_KEY, code)
        rescue StandardError
        end
        return code
      end

      @rsa_machine_code_v150 = tt_machine_code_before_rsa_v150
    rescue StandardError
      tt_machine_code_before_rsa_v150
    end

    def rsa_cache_file
      File.join(cache_dir, 'license_rsa_v1.json')
    end

    def rsa_public_key(public_key_pem = RSA_PUBLIC_KEY_PEM)
      OpenSSL::PKey::RSA.new(public_key_pem.to_s)
    end

    def rsa_valid_until_time(payload)
      text = payload.is_a?(Hash) ? payload['valid_until'].to_s : ''
      return nil if text.empty?
      Time.iso8601(text)
    rescue StandardError
      nil
    end

    def rsa_issued_at_time(payload)
      text = payload.is_a?(Hash) ? payload['issued_at'].to_s : ''
      return nil if text.empty?
      Time.iso8601(text)
    rescue StandardError
      nil
    end

    def verify_signed_license_response(response, expected_machine = machine_code, public_key_pem = RSA_PUBLIC_KEY_PEM, now = Time.now)
      raise 'Server thiếu signed_license.' unless response.is_a?(Hash)
      envelope = response['signed_license']
      raise 'Server thiếu signed_license.' unless envelope.is_a?(Hash)
      raise 'Sai thuật toán chữ ký.' unless envelope['alg'].to_s == RSA_ALGORITHM
      raise 'Sai khóa ký bản quyền.' unless envelope['key_id'].to_s == RSA_KEY_ID
      raise 'Sai schema chữ ký.' unless envelope['schema'].to_s == RSA_SCHEMA

      raw = Base64.strict_decode64(envelope['data_b64'].to_s)
      signature = Base64.strict_decode64(envelope['signature_b64'].to_s)
      raise 'Payload RSA rỗng.' if raw.empty? || signature.empty?

      digest = OpenSSL::Digest::SHA256.new
      raise 'Chữ ký RSA không hợp lệ.' unless rsa_public_key(public_key_pem).verify(digest, signature, raw)

      text = raw.dup.force_encoding('UTF-8')
      raise 'Payload RSA không phải UTF-8.' unless text.valid_encoding?
      data = JSON.parse(text)
      raise 'Sai schema license.' unless data['schema'].to_s == RSA_SCHEMA
      raise 'License không thuộc máy này.' unless data['machine_code'].to_s.upcase == expected_machine.to_s.upcase

      issued_at = rsa_issued_at_time(data)
      valid_until = rsa_valid_until_time(data)
      raise 'License thiếu issued_at.' unless issued_at
      raise 'License thiếu valid_until.' unless valid_until
      raise 'Thời gian license không hợp lệ.' if issued_at > now + RSA_CLOCK_SKEW_SECONDS
      raise 'License RSA đã hết hạn.' if valid_until <= now - RSA_CLOCK_SKEW_SECONDS

      payload = normalize_payload(data)
      payload['ok'] = true
      payload['api_version'] = 3
      payload['rsa_verified'] = true
      payload['rsa_algorithm'] = RSA_ALGORITHM
      payload['rsa_key_id'] = RSA_KEY_ID
      payload['rsa_public_fingerprint'] = RSA_PUBLIC_FINGERPRINT
      payload['rsa_license_id'] = data['license_id'].to_s
      payload['rsa_valid_until'] = data['valid_until'].to_s
      payload['_signed_license'] = envelope.dup
      payload
    end

    # request_status_raw cũ chỉ làm HTTP. Từ V1.5.0 dữ liệu chỉ được chấp nhận
    # sau khi chữ ký RSA và machine_code đều hợp lệ.
    def request_status_raw(code, version, feature)
      response = tt_request_status_raw_before_rsa_v150(code, version, feature)
      verify_signed_license_response(response, code)
    rescue StandardError => error
      @last_error = "RSA: #{error.message}"
      raise
    end

    # Cache V1/V3 cũ không được tin cậy. Chỉ lưu envelope đã ký.
    def cache
      payload = @memory_cache
      if payload.is_a?(Hash) && payload['rsa_verified'] == true
        return payload
      end
      return {} unless File.file?(rsa_cache_file)

      wrapper = JSON.parse(File.read(rsa_cache_file, mode: 'r:BOM|UTF-8'))
      envelope = wrapper.is_a?(Hash) ? wrapper['signed_license'] : nil
      return {} unless envelope.is_a?(Hash)

      payload = verify_signed_license_response({ 'signed_license' => envelope }, machine_code)
      @memory_cache = payload
      @memory_cache_time = wrapper['saved_at'].to_i
      payload
    rescue StandardError => error
      @last_error = "RSA cache: #{error.message}"
      puts "[TT License RSA cache] #{error.class}: #{error.message}"
      @memory_cache = nil
      {}
    end

    def cache_time
      return @memory_cache_time.to_i if @memory_cache_time.to_i > 0
      return 0 unless File.file?(rsa_cache_file)
      wrapper = JSON.parse(File.read(rsa_cache_file, mode: 'r:BOM|UTF-8'))
      @memory_cache_time = wrapper.is_a?(Hash) ? wrapper['saved_at'].to_i : File.mtime(rsa_cache_file).to_i
      @memory_cache_time.to_i
    rescue StandardError
      0
    end

    def save_cache(payload)
      raise 'Không lưu cache chưa xác minh RSA.' unless payload.is_a?(Hash) && payload['rsa_verified'] == true
      envelope = payload['_signed_license']
      raise 'License RSA thiếu envelope.' unless envelope.is_a?(Hash)

      now = Time.now.to_i
      @memory_cache = payload
      @memory_cache_time = now
      FileUtils.mkdir_p(cache_dir)
      wrapper = {
        'format' => 'TT_LICENSE_RSA_CACHE_V1',
        'saved_at' => now,
        'machine_code' => machine_code,
        'key_id' => RSA_KEY_ID,
        'signed_license' => envelope
      }
      tmp = "#{rsa_cache_file}.tmp"
      File.open(tmp, 'wb') { |file| file.write(JSON.generate(wrapper)) }
      FileUtils.mv(tmp, rsa_cache_file, force: true)
      payload
    rescue StandardError => error
      puts "[TT License RSA cache write] #{error.class}: #{error.message}"
      @memory_cache = payload if payload.is_a?(Hash) && payload['rsa_verified'] == true
      payload
    end

    def stale?(payload = cache)
      return true unless payload.is_a?(Hash) && payload['rsa_verified'] == true
      valid_until = rsa_valid_until_time(payload)
      return true unless valid_until
      Time.now + RSA_REFRESH_MARGIN_SECONDS >= valid_until
    rescue StandardError
      true
    end

    def cached_allowed?(feature)
      payload = cache
      return false unless payload.is_a?(Hash) && payload['rsa_verified'] == true
      return false if stale?(payload)
      feature_info(feature, payload)['allowed'] == true
    rescue StandardError
      false
    end

    # Paid tools luôn cần license RSA hợp lệ. Vẽ Ván + BOX là FREE nên vẫn mở
    # khi mất mạng hoàn toàn. Khi commercial_enforcement=false server sẽ ký
    # allowed=true cho các tool; khi OWNER bật thương mại, chữ ký mới phản ánh
    # đúng quyền đã mua.
    def allowed?(feature, interactive = true)
      feature = feature.to_sym
      payload = cache

      if payload.is_a?(Hash) && payload['rsa_verified'] == true && !stale?(payload)
        return true if feature_info(feature, payload)['allowed'] == true
        show_dialog(feature) if interactive
        return false
      end

      fresh = sync_now(feature)
      if fresh.is_a?(Hash) && fresh['rsa_verified'] == true && feature_info(feature, fresh)['allowed'] == true
        return true
      end

      return true if RSA_FREE_FEATURES.include?(feature)

      show_dialog(feature) if interactive
      false
    rescue StandardError => error
      @last_error = "RSA: #{error.class}: #{error.message}"
      puts "[TT License RSA allowed] #{@last_error}"
      return true if RSA_FREE_FEATURES.include?(feature)
      show_dialog(feature) if interactive
      false
    end

    def dialog_html
      html = tt_dialog_html_before_rsa_v150
      box = <<~HTML
        <div id="ttRsaBoxV150" class="box" style="border-color:#2563eb">
          <b style="color:#93c5fd">CHỮ KÝ SỐ RSA</b>
          <div style="margin-top:7px"><b>Trạng thái:</b> <span id="ttRsaStatusV150">CHƯA XÁC MINH</span></div>
          <div style="margin-top:5px"><b>Key:</b> <span id="ttRsaKeyV150" class="muted">#{RSA_KEY_ID}</span></div>
          <div style="margin-top:5px"><b>License:</b> <span id="ttRsaLicenseV150" class="muted">-</span></div>
          <div style="margin-top:5px"><b>Hiệu lực offline đến:</b> <span id="ttRsaUntilV150" class="muted">-</span></div>
        </div>
      HTML
      marker = '<div class="box"><b>QUYỀN CHỨC NĂNG</b>'
      html.include?(marker) ? html.sub(marker, box + marker) : html
    end

    def refresh_dialog(payload_override = nil)
      result = tt_refresh_dialog_before_rsa_v150(payload_override)
      return result unless @dialog && @dialog.visible?

      payload = payload_override.is_a?(Hash) ? payload_override : cache
      verified = payload.is_a?(Hash) && payload['rsa_verified'] == true && !stale?(payload)
      ui = {
        verified: verified,
        key_id: payload.is_a?(Hash) ? payload['rsa_key_id'].to_s : RSA_KEY_ID,
        license_id: payload.is_a?(Hash) ? payload['rsa_license_id'].to_s : '',
        valid_until: payload.is_a?(Hash) ? payload['rsa_valid_until'].to_s : ''
      }
      @dialog.execute_script(<<~JS)
        (function(d){
          var s=document.getElementById('ttRsaStatusV150');
          var k=document.getElementById('ttRsaKeyV150');
          var l=document.getElementById('ttRsaLicenseV150');
          var u=document.getElementById('ttRsaUntilV150');
          if(s){s.textContent=d.verified?'HỢP LỆ · KHÓA THEO MÁY':'CHƯA HỢP LỆ';s.className=d.verified?'ok':'bad';}
          if(k)k.textContent=d.key_id||'#{RSA_KEY_ID}';
          if(l)l.textContent=d.license_id||'-';
          if(u)u.textContent=d.valid_until||'-';
        })(#{JSON.generate(ui)});
      JS
      result
    rescue StandardError => error
      puts "[TT License RSA UI] #{error.class}: #{error.message}"
      result
    end
  end
end
