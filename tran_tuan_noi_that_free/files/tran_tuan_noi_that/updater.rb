# encoding: UTF-8
require 'net/http'
require 'uri'
require 'openssl'
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'base64'
require 'cgi'

module TranTuanNoiThat
  module Updater
    extend self
    RAW_MANIFEST_URL = 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/tran_tuan_noi_that_free/update_latest.json'.freeze unless const_defined?(:RAW_MANIFEST_URL, false)
    API_MANIFEST_URL = 'https://api.github.com/repos/tuanboidoi29-ai/TT-t-o-v-n-3d/contents/tran_tuan_noi_that_free/update_latest.json?ref=main'.freeze unless const_defined?(:API_MANIFEST_URL, false)
    OPEN_TIMEOUT = 15 unless const_defined?(:OPEN_TIMEOUT, false)
    READ_TIMEOUT = 45 unless const_defined?(:READ_TIMEOUT, false)

    def check(interactive = true)
      return false if @busy
      @busy = true
      begin
        if TranTuanNoiThat.respond_to?(:restart_required?) && TranTuanNoiThat.restart_required?
          UI.messagebox('Bản cập nhật đã được cài. Hãy đóng và mở lại SketchUp trước khi kiểm tra cập nhật lần nữa.') if interactive
          return false
        end
        manifest = fetch_manifest
        validate_manifest(manifest)
        latest = manifest.fetch('version')
        local = TranTuanNoiThat.current_version
        comparison = normalize(latest) <=> normalize(local)
        pending_changes = changed_files(manifest)
        pending_removals = removed_files_present(manifest)
        pending_removed_dirs = removed_dirs_present(manifest)
        if comparison < 0 || (comparison == 0 && pending_changes.empty? && pending_removals.empty? && pending_removed_dirs.empty?)
          UI.messagebox("Đang dùng bản không bản quyền mới nhất: #{local}.") if interactive
          return false
        end
        # Automatic checks announce updates without silently replacing a running tool.
        unless interactive
          Sketchup.status_text = "TRẦN TUẤN: Có cập nhật #{latest}. Bấm Kiểm Tra Cập Nhật để cài."
          return true
        end
        text = comparison == 0 ? "Kiểm tra thấy tệp cần khôi phục ở bản #{latest}." : "Có bản không bản quyền #{latest} trên GitHub."
        return false unless UI.messagebox("#{text}\nTải, sao lưu và nạp bản cập nhật ngay?", MB_YESNO) == IDYES
        install(manifest)
      rescue StandardError => error
        message = "Không cập nhật được:\n#{friendly_error(error)}"
        interactive ? UI.messagebox(message) : puts("[TT Update] #{message}")
        false
      ensure
        @busy = false
      end
    end

    def fetch_manifest
      errors = []
      candidates = []

      [RAW_MANIFEST_URL, API_MANIFEST_URL].each do |url|
        begin
          data = decode_json_payload(get(fresh_url(url)))
          validate_manifest(data)
          candidates << data
        rescue StandardError => error
          errors << "#{url.include?('api.github.com') ? 'API' : 'RAW'}: #{friendly_error(error)}"
        end
      end

      unless candidates.empty?
        # Không tin nguồn trả về đầu tiên: RAW/proxy có thể đang giữ manifest cũ.
        # Luôn chọn version cao nhất giữa RAW và GitHub API.
        return candidates.max_by { |data| normalize(data.fetch('version')) }
      end

      raise "Không lấy được cập nhật GitHub.\n#{errors.join("\n")}"
    end

    def validate_manifest(data)
      raise 'Nguồn cập nhật không phải bản không bản quyền.' unless data.is_a?(Hash) && data['edition'] == 'no_license' && data['license_required'] == false
      raise 'Phiên bản cập nhật không hợp lệ.' unless data['version'].to_s.match?(/\A\d+\.\d+\.\d+\z/)
      files = data['files']
      raise 'Danh sách cập nhật trống.' unless files.is_a?(Array) && !files.empty?
      paths = files.map do |item|
        raise 'Thông tin tệp không hợp lệ.' unless item.is_a?(Hash)
        path = safe_path(item['path'])
        raise 'Thiếu SHA256 kiểm tra tệp.' unless item['sha256'].to_s.match?(/\A[0-9a-f]{64}\z/)
        uri = URI.parse(item['url'].to_s)
        prefix = '/tuanboidoi29-ai/TT-t-o-v-n-3d/main/tran_tuan_noi_that_free/files/'
        raise 'Nguồn tệp không thuộc kênh cập nhật này.' unless uri.is_a?(URI::HTTPS) && uri.host == 'raw.githubusercontent.com' && uri.path == prefix + path && uri.query.nil? && uri.fragment.nil?
        path
      end
      raise 'Danh sách tệp bị trùng.' unless paths.uniq.length == paths.length

      remove_paths = Array(data['remove_files']).map do |remove_path|
        safe_path(remove_path)
      end
      raise 'Danh sách tệp cần xóa bị trùng.' unless remove_paths.uniq.length == remove_paths.length
      raise 'Tệp vừa cập nhật vừa bị yêu cầu xóa.' unless (paths & remove_paths).empty?

      remove_dirs = Array(data['remove_dirs']).map do |relative|
        safe_remove_dir(relative)
      end
      raise 'Danh sách thư mục cần xóa bị trùng.' unless remove_dirs.uniq.length == remove_dirs.length

      %w[TranTuanNoiThat.rb tran_tuan_noi_that/bootstrap.rb tran_tuan_noi_that/settings.rb tran_tuan_noi_that/updater.rb].each do |path|
        raise "Gói cập nhật thiếu #{path}" unless paths.include?(path)
      end
      true
    end

    def safe_path(path)
      clean = path.to_s
      valid = ['TranTuanNoiThat.rb', 'TT_TranTuan_UpdateLoader.rb'].include?(clean) || clean.match?(/\Atran_tuan_noi_that\/(?:[a-z0-9_]+\.rb|icons\/[a-z0-9_]+\.svg|ui\/[a-z0-9_]+\.html)\z/)
      raise 'Đường dẫn cập nhật không hợp lệ.' unless valid
      raise 'Gói cập nhật có tệp cấp phép thương mại.' if clean.match?(/licen[sc]e|commercial|payment|owner_admin/i)
      clean
    end

    def safe_remove_dir(path)
      clean = path.to_s
      allowed = [
        'tran_tuan_noi_that/library_cache',
        'tran_tuan_noi_that/data/vector_cnc'
      ]
      raise 'Thư mục cần xóa không nằm trong danh sách an toàn.' unless allowed.include?(clean)
      clean
    end

    def remove_dir_path(relative)
      clean = safe_remove_dir(relative)
      plugins = File.expand_path(Sketchup.find_support_file('Plugins'))
      target = File.expand_path(File.join(plugins, clean))
      raise 'Đường dẫn thư mục nằm ngoài Plugins.' unless target.start_with?(plugins + File::SEPARATOR)
      target
    end

    def install_path(relative)
      clean = safe_path(relative)
      plugins = File.expand_path(Sketchup.find_support_file('Plugins'))
      target = File.expand_path(File.join(plugins, clean))
      raise 'Đường dẫn nằm ngoài Plugins.' unless target.start_with?(plugins + File::SEPARATOR)
      target
    end

    def changed_files(manifest)
      manifest.fetch('files').select do |item|
        target = install_path(item.fetch('path'))
        !File.file?(target) || Digest::SHA256.file(target).hexdigest != item.fetch('sha256')
      end
    end

    def removed_files_present(manifest)
      Array(manifest['remove_files']).select do |relative|
        File.file?(install_path(relative))
      end
    end

    def removed_dirs_present(manifest)
      Array(manifest['remove_dirs']).select do |relative|
        File.directory?(remove_dir_path(relative))
      end
    end

    def install(manifest)
      validate_manifest(manifest)
      raise 'Không cài lùi phiên bản.' if (normalize(manifest['version']) <=> normalize(TranTuanNoiThat.current_version)) < 0
      stage = Dir.mktmpdir('tt_update_')
      backups = []
      begin
        items = changed_files(manifest)
        # Download and verify every changed file before touching installed files.
        items.each do |item|
          relative = safe_path(item.fetch('path'))
          bytes = download_verified(item.fetch('url'), item.fetch('sha256'), relative)
          path = File.join(stage, relative)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, bytes)
        end

        backup_root = File.join(TranTuanNoiThat::ROOT, 'backup', "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{Process.pid}")
        items.each do |item|
          relative = item.fetch('path')
          target = install_path(relative)
          backup = File.join(backup_root, relative)
          existed = File.file?(target)
          if existed
            FileUtils.mkdir_p(File.dirname(backup))
            FileUtils.cp(target, backup)
          end
          backups << [target, backup, existed]
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(File.join(stage, relative), target)
        end

        Array(manifest['remove_files']).each do |relative|
          relative = safe_path(relative)
          target = install_path(relative)
          next unless File.file?(target)
          backup = File.join(backup_root, relative)
          FileUtils.mkdir_p(File.dirname(backup))
          FileUtils.cp(target, backup)
          backups << [target, backup, true]
          FileUtils.rm_f(target)
        end

        Array(manifest['remove_dirs']).each do |relative|
          target = remove_dir_path(relative)
          next unless File.directory?(target)
          backup = File.join(backup_root, relative)
          FileUtils.mkdir_p(File.dirname(backup))
          FileUtils.cp_r(target, backup)
          backups << [target, backup, true, :directory]
          FileUtils.rm_rf(target)
        end

        # Không hot-reload Ruby trong phiên SketchUp đang chạy.
        # Các dialog/tool đang mở có thể giữ callback và constant cũ; chỉ nạp sau khi khởi động lại.
        verify_release_version(manifest, stage)
        TranTuanNoiThat.save_setting('installed_version', manifest['version'])
        TranTuanNoiThat.instance_variable_set(:@restart_required, true)
        UI.messagebox(
          "Đã cập nhật an toàn phiên bản #{manifest['version']} từ GitHub.\n" \
          "Tất cả tệp đã được xác minh SHA256 và lưu bản sao lưu.\n\n" \
          "Hãy ĐÓNG SketchUp và MỞ LẠI để nạp các mô-đun mới trong phiên sạch.\n" \
          "Không cần gỡ plugin hoặc xóa dữ liệu."
        )
        true
      rescue StandardError, ScriptError => error
        rollback_errors = []
        backups.reverse_each do |target, backup, existed, kind|
          begin
            if kind == :directory
              FileUtils.rm_rf(target)
              if existed && File.directory?(backup)
                FileUtils.mkdir_p(File.dirname(target))
                FileUtils.cp_r(backup, target)
              end
            else
              existed ? FileUtils.cp(backup, target) : FileUtils.rm_f(target)
            end
          rescue StandardError => rollback_error
            rollback_errors << "#{target}: #{rollback_error.message}"
          end
        end
        unless backups.empty?
          begin
            load(File.join(TranTuanNoiThat::ROOT, 'bootstrap.rb'))
          rescue StandardError, ScriptError => reload_error
            rollback_errors << reload_error.message
          end
        end
        detail = rollback_errors.empty? ? 'Tệp cũ được giữ hoặc khôi phục.' : "Cần mở lại SketchUp/khôi phục từ thư mục backup: #{rollback_errors.join('; ')}"
        raise "#{error.message}\n#{detail}"
      ensure
        FileUtils.remove_entry(stage) if stage && File.directory?(stage)
      end
    end

    def verify_release_version(manifest, stage)
      version = manifest.fetch('version').to_s
      checks = {
        'tran_tuan_noi_that/bootstrap.rb' => /VERSION\s*=\s*['"]#{Regexp.escape(version)}['"]/,
        'TranTuanNoiThat.rb' => /ext\.version\s*=\s*['"]#{Regexp.escape(version)}['"]/
      }
      checks.each do |relative, pattern|
        staged = File.join(stage, relative)
        source = File.file?(staged) ? staged : install_path(relative)
        raise "Thiếu tệp kiểm tra phiên bản #{relative}." unless File.file?(source)
        raise "Phiên bản trong #{relative} không khớp #{version}." unless pattern.match?(File.read(source))
      end
      true
    end

    def normalize(version)
      version.to_s.split('.').map(&:to_i).values_at(0, 1, 2).map { |v| v || 0 }
    end
    def download_verified(url, expected, relative)
      errors = []
      candidate_urls(url).each do |candidate|
        begin
          bytes = download_bytes(candidate)
          if Digest::SHA256.hexdigest(bytes).downcase == expected
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
      raise 'Máy chủ cập nhật không hợp lệ.' unless %w[raw.githubusercontent.com api.github.com].include?(uri.host)

      headers = {
        'User-Agent' => 'TranTuanNoiThat-SketchUp/1.9.331',
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
        open_timeout: 15,
        read_timeout: 45
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

  end
end
