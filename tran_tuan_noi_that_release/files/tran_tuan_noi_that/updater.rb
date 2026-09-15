# encoding: UTF-8
module TranTuanNoiThat
  module Updater
    extend self

    def check(interactive = true)
      manifest = JSON.parse(get(fresh_url(TranTuanNoiThat::MANIFEST_URL)))
      latest = manifest.fetch('version').to_s
      local = TranTuanNoiThat.current_version

      unless newer?(latest, local)
        if files_outdated?(manifest)
          answer = UI.messagebox(
            "Phiên bản #{latest} đã ghi nhận nhưng file cài đặt đang thiếu hoặc chưa đúng.\nSửa và nạp lại ngay không?",
            MB_YESNO
          )
          return false unless answer == IDYES
          return install(manifest)
        end
        return UI.messagebox("Đang dùng phiên bản mới nhất: #{local}") if interactive
        return false
      end

      answer = UI.messagebox("Có phiên bản #{latest}.\nTải, cài và nạp ngay không?", MB_YESNO)
      return false unless answer == IDYES
      install(manifest)
    rescue StandardError => error
      message = "Không kiểm tra được cập nhật:\n#{error.message}"
      interactive ? UI.messagebox(message) : (puts message)
      false
    end

    def install(manifest)
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

      TranTuanNoiThat.save_setting('installed_version', manifest['version'])
      Settings.notify("Đã cập nhật và nạp phiên bản #{manifest['version']}.", 'ok') if defined?(Settings)
      UI.messagebox("Cập nhật #{manifest['version']} thành công.\nKhông cần khởi động lại SketchUp.")
      true
    ensure
      FileUtils.remove_entry(staging) if staging && File.directory?(staging)
    end

    def download_verified(url, expected, relative)
      last_actual = nil
      3.times do
        bytes = get(fresh_url(url))
        return bytes if expected.empty?
        actual = Digest::SHA256.hexdigest(bytes).downcase
        return bytes if actual == expected
        last_actual = actual
        sleep(0.15)
      end
      raise "Sai mã kiểm tra: #{relative}\nMong đợi: #{expected}\nNhận được: #{last_actual}"
    end

    def fresh_url(url)
      separator = url.to_s.include?('?') ? '&' : '?'
      "#{url}#{separator}tt_cache=#{Time.now.to_i}_#{rand(1_000_000)}"
    end

    def get(url, limit = 5)
      raise 'Quá nhiều lần chuyển hướng.' if limit <= 0
      uri = URI.parse(url)
      raise 'Chỉ cho phép cập nhật HTTPS.' unless uri.is_a?(URI::HTTPS)
      request = Net::HTTP::Get.new(
        uri.request_uri,
        'User-Agent' => 'TranTuanNoiThat-SketchUp/1.9.2',
        'Cache-Control' => 'no-cache, no-store, max-age=0',
        'Pragma' => 'no-cache'
      )
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 25) { |http| http.request(request) }
      return get(URI.join(uri, response['location']).to_s, limit - 1) if response.is_a?(Net::HTTPRedirection)
      raise "Máy chủ trả về HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end

    def files_outdated?(manifest)
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

    def install_path(relative)
      plugins = File.expand_path(Sketchup.find_support_file('Plugins'))
      target = File.expand_path(File.join(plugins, relative))
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
  end
end

if TranTuanNoiThat.instance_variable_get(:@ui_installed) &&
   !TranTuanNoiThat.instance_variable_get(:@hot_bootstrap_loading)
  begin
    TranTuanNoiThat.instance_variable_set(:@hot_bootstrap_loading, true)
    load File.join(TranTuanNoiThat::ROOT, 'bootstrap.rb')
  ensure
    TranTuanNoiThat.instance_variable_set(:@hot_bootstrap_loading, false)
  end
end
