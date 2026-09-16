# encoding: UTF-8
require 'base64'
require 'cgi'

module TranTuanNoiThat
  module Updater
    extend self

    RAW_MANIFEST_URL = 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/tran_tuan_noi_that_release/update_latest.json'.freeze
    API_MANIFEST_URL = 'https://api.github.com/repos/tuanboidoi29-ai/TT-t-o-v-n-3d/contents/tran_tuan_noi_that_release/update_latest.json?ref=main'.freeze
    BRIDGE_LOADER = 'TT_TranTuan_UpdateLoader.rb'.freeze
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 8

    def silent_update?
      @silent_update == true
    end

    def check(interactive = true)
      manifest = fetch_manifest
      latest = manifest.fetch('version').to_s
      local = TranTuanNoiThat.current_version.to_s

      if !newer?(latest, local)
        if files_outdated?(manifest)
          if interactive
            answer = UI.messagebox(
              "Phiên bản #{latest} đã ghi nhận nhưng file cài đặt đang thiếu hoặc chưa đúng.\nSửa và nạp lại ngay không?",
              MB_YESNO
            )
            return false unless answer == IDYES
          end
          return with_update_mode(!interactive) { install(manifest) }
        end
        UI.messagebox("Đang dùng phiên bản mới nhất: #{local}") if interactive
        return false
      end

      if interactive
        answer = UI.messagebox("Có phiên bản #{latest}.\nTải, cài và nạp ngay không?", MB_YESNO)
        return false unless answer == IDYES
      end

      with_update_mode(!interactive) { install(manifest) }
    rescue StandardError => error
      message = "Không kiểm tra được cập nhật:\n#{friendly_error(error)}"
      if interactive
        UI.messagebox(message)
      else
        puts "[TT Auto Update] #{message}"
        Sketchup.status_text = message.gsub("\n", ' ') if defined?(Sketchup)
      end
      false
    end

    def with_update_mode(silent)
      previous = @silent_update
      @silent_update = !!silent
      close_transient_dialogs if @silent_update
      yield
    ensure
      @silent_update = previous
    end

    def close_transient_dialogs
      if defined?(TranTuanNoiThat::License) && TranTuanNoiThat::License.respond_to?(:close_license_dialog)
        TranTuanNoiThat::License.close_license_dialog
      end
      true
    rescue StandardError => error
      puts "[TT Auto Update close dialogs] #{error.class}: #{error.message}"
      false
    end

    def fetch_manifest
      errors = []
      [RAW_MANIFEST_URL, API_MANIFEST_URL].each do |url|
        begin
          body = get(fresh_url(url))
          manifest = decode_json_payload(body)
          return manifest if manifest.is_a?(Hash) && manifest['version'] && manifest['files']
          errors << "Dữ liệu manifest không hợp lệ từ #{URI.parse(url).host}"
        rescue StandardError => error
          errors << "#{URI.parse(url).host}: #{friendly_error(error)}"
        end
      end
      raise "Không lấy được dữ liệu cập nhật từ cả 2 máy chủ.\n#{errors.join("\n")}"
    end

    def signed_runtime?
      root = TranTuanNoiThat::ROOT.to_s
      File.file?(File.join(root, 'TranTuanNoiThat.susig')) || !Dir.glob(File.join(root, '*.rbe')).empty?
    rescue StandardError
      false
    end

    def bridge_path
      File.join(Sketchup.find_support_file('Plugins'), BRIDGE_LOADER)
    end

    def load_bridge
      path = bridge_path
      return false unless File.file?(path)
      load(path) unless defined?(TTTranTuanUpdateLoader)
      TTTranTuanUpdateLoader.patch_updater if defined?(TTTranTuanUpdateLoader)
      defined?(TTTranTuanUpdateLoader) ? true : false
    rescue StandardError => error
      puts "[TT Update Bridge load] #{error.class}: #{error.message}"
      false
    end

    def install(manifest)
      if signed_runtime?
        load_bridge
        if defined?(TTTranTuanUpdateLoader)
          return TTTranTuanUpdateLoader.install_manifest(manifest)
        end
        raise "Bản thương mại đang dùng .rbe/.susig nhưng thiếu Update Bridge.\nHãy cài bản chuyển tiếp 1.9.54 một lần."
      end
      install_direct(manifest)
    end

    def install_direct(manifest)
      files = manifest.fetch('files')
      staging = Dir.mktmpdir('tt_noi_that_')
      downloaded = []

      files.each do |item|
        relative = safe_path(item.fetch('path'))
        expected = item['sha256'].to_s.downcase
        bytes = download_verified(item.fetch('url'), expected, relative)
        local = File.join(staging, relative)
        FileUtils.mkdir_p(File.dirname(local))
        File.binwrite(local, bytes)
        downloaded << [local, install_path(relative)]
      end

      backup_root = File.join(TranTuanNoiThat::ROOT, 'backup', Time.now.strftime('%Y%m%d_%H%M%S'))
      downloaded.each do |source, target|
        if File.file?(target)
          backup = File.join(backup_root, target.sub(Sketchup.find_support_file('Plugins'), ''))
          FileUtils.mkdir_p(File.dirname(backup))
          FileUtils.cp(target, backup)
        end
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
      end

      ok = TranTuanNoiThat.reload_runtime
      raise 'Đã chép file nhưng không thể nạp mã mới.' unless ok

      load_round_fix
      TranTuanNoiThat.save_setting('installed_version', manifest['version'])
      Settings.notify("Đã cập nhật và nạp phiên bản #{manifest['version']}.", 'ok') if defined?(Settings)

      if silent_update?
        message = "Đã tự cập nhật #{manifest['version']} · không cần khởi động lại máy tính."
        puts "[TT Auto Update] #{message}"
        Sketchup.status_text = message if defined?(Sketchup)
      else
        UI.messagebox("Cập nhật #{manifest['version']} thành công.\nKhông cần khởi động lại SketchUp.")
      end
      true
    ensure
      FileUtils.remove_entry(staging) if defined?(staging) && staging && File.directory?(staging)
    end

    def load_round_fix
      rb = File.join(TranTuanNoiThat::ROOT, 'round_smooth_fix.rb')
      rbe = File.join(TranTuanNoiThat::ROOT, 'round_smooth_fix.rbe')
      file = File.file?(rb) ? rb : rbe
      load(file) if File.file?(file)
      true
    rescue StandardError => error
      puts "[TT Round Smooth Fix] #{error.class}: #{error.message}"
      false
    end

    def download_verified(url, expected, relative)
      errors = []
      candidate_urls(url).each do |candidate|
        begin
          bytes = download_bytes(candidate)
          if expected.empty? || Digest::SHA256.hexdigest(bytes).downcase == expected
            return bytes
          end
          errors << "#{URI.parse(candidate).host}: sai SHA"
        rescue StandardError => error
          errors << "#{URI.parse(candidate).host}: #{friendly_error(error)}"
        end
      end
      raise "Không tải được #{relative}.\n#{errors.join("\n")}"
    end

    def candidate_urls(url)
      list = [fresh_url(url)]
      api = raw_to_api(url)
      list << fresh_url(api) if api
      list.uniq
    end

    def raw_to_api(url)
      uri = URI.parse(url)
      return nil unless uri.host == 'raw.githubusercontent.com'
      parts = uri.path.sub(%r{\A/}, '').split('/')
      return nil if parts.length < 4
      owner = parts.shift
      repo = parts.shift
      ref = parts.shift
      path = parts.join('/')
      "https://api.github.com/repos/#{owner}/#{repo}/contents/#{path}?ref=#{CGI.escape(ref)}"
    rescue StandardError
      nil
    end

    def download_bytes(url)
      body = get(url)
      uri = URI.parse(url)
      if uri.host == 'api.github.com' && uri.path.include?('/contents/')
        parsed = JSON.parse(body)
        if parsed.is_a?(Hash) && parsed['content'] && parsed['encoding'].to_s.downcase == 'base64'
          return Base64.decode64(parsed['content'].to_s)
        end
      end
      body
    end

    def decode_json_payload(body)
      parsed = JSON.parse(body)
      if parsed.is_a?(Hash) && parsed['content'] && parsed['encoding'].to_s.downcase == 'base64'
        JSON.parse(Base64.decode64(parsed['content'].to_s))
      else
        parsed
      end
    end

    def fresh_url(url)
      separator = url.to_s.include?('?') ? '&' : '?'
      "#{url}#{separator}tt_cache=#{Time.now.to_i}_#{rand(1_000_000)}"
    end

    def get(url, limit = 4)
      raise 'Quá nhiều lần chuyển hướng.' if limit <= 0
      uri = URI.parse(url)
      raise 'Chỉ cho phép cập nhật HTTPS.' unless uri.is_a?(URI::HTTPS)

      headers = {
        'User-Agent' => 'TranTuanNoiThat-SketchUp/1.9.60',
        'Cache-Control' => 'no-cache, no-store, max-age=0',
        'Pragma' => 'no-cache'
      }
      if uri.host == 'api.github.com'
        headers['Accept'] = 'application/vnd.github+json'
        headers['X-GitHub-Api-Version'] = '2022-11-28'
      end

      request = Net::HTTP::Get.new(uri.request_uri, headers)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(request) }

      if response.is_a?(Net::HTTPRedirection)
        location = response['location']
        raise 'Máy chủ chuyển hướng nhưng thiếu địa chỉ.' if location.to_s.empty?
        return get(URI.join(uri, location).to_s, limit - 1)
      end

      raise "Máy chủ trả về HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end

    def friendly_error(error)
      case error
      when Net::OpenTimeout, Net::ReadTimeout
        'Kết nối GitHub quá thời gian.'
      when SocketError
        'Không phân giải được địa chỉ GitHub.'
      else
        error.message.to_s.empty? ? error.class.to_s : error.message.to_s
      end
    end

    def files_outdated?(manifest)
      return false if signed_runtime?

      manifest.fetch('files').any? do |item|
        relative = safe_path(item.fetch('path'))
        expected = item['sha256'].to_s.downcase
        target = install_path(relative)
        !File.file?(target) || (!expected.empty? && Digest::SHA256.file(target).hexdigest.downcase != expected)
      end
    rescue StandardError
      true
    end

    def safe_path(path)
      clean = path.to_s.tr('\\', '/')
      raise 'Đường dẫn cập nhật không hợp lệ.' if clean.empty? || clean.start_with?('/') || clean.split('/').include?('..')
      clean
    end

    def runtime_relative_path(relative)
      clean = safe_path(relative)
      legacy_prefix = 'tran_tuan_noi_that/'
      return clean unless clean.start_with?(legacy_prefix)
      return clean unless File.basename(TranTuanNoiThat::ROOT.to_s) == 'TranTuanNoiThat'
      "TranTuanNoiThat/#{clean.delete_prefix(legacy_prefix)}"
    end

    def install_path(relative)
      plugins = File.expand_path(Sketchup.find_support_file('Plugins'))
      mapped = runtime_relative_path(relative)
      target = File.expand_path(File.join(plugins, mapped))
      raise 'File cập nhật nằm ngoài thư mục Plugins.' unless target.start_with?(plugins + File::SEPARATOR)
      target
    end

    def newer?(remote, local)
      (normalize(remote) <=> normalize(local)) == 1
    end

    def normalize(version)
      parts = version.to_s.split('.').first(4).map { |part| part.to_i }
      parts << 0 while parts.length < 4
      parts
    end

    def schedule_transition_cleanup
      return false unless signed_runtime?
      source = File.expand_path(__FILE__)
      return false unless File.extname(source).downcase == '.rb'
      return false unless File.basename(File.dirname(source)) == 'TranTuanNoiThat'
      UI.start_timer(2.0, false) do
        begin
          File.delete(source) if File.file?(source)
          puts '[TT Updater] Đã xóa updater.rb chuyển tiếp; chữ ký thương mại được giữ sạch.'
        rescue StandardError => error
          puts "[TT Updater cleanup] #{error.class}: #{error.message}"
        end
      end
      true
    rescue StandardError
      false
    end
  end
end

if defined?(TranTuanNoiThat::Updater)
  TranTuanNoiThat::Updater.load_bridge
  TranTuanNoiThat::Updater.schedule_transition_cleanup
end
