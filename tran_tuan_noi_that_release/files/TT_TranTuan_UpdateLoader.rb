# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'

# TRẦN TUẤN - UPDATE BRIDGE
# Giữ nguyên thư mục extension thương mại đã ký (.rbe/.susig).
# Các bản vá online được lưu ngoài thư mục đã ký rồi nạp đè ở runtime.
module TTTranTuanUpdateLoader
  VERSION = '1.0.1'.freeze
  PLUGINS_ROOT = File.expand_path(Sketchup.find_support_file('Plugins')).freeze
  UPDATE_ROOT = File.join(PLUGINS_ROOT, 'TT_TranTuan_Updates').freeze
  STATE_FILE = File.join(UPDATE_ROOT, 'state.json').freeze
  LOADER_NAME = 'TT_TranTuan_UpdateLoader.rb'.freeze
  SKIP_BASENAMES = %w[TranTuanNoiThat.rb bootstrap.rb settings.rb updater.rb].freeze

  class << self
    def signed_runtime?
      return false unless defined?(TranTuanNoiThat::ROOT)
      root = TranTuanNoiThat::ROOT.to_s
      File.file?(File.join(root, 'TranTuanNoiThat.susig')) || !Dir.glob(File.join(root, '*.rbe')).empty?
    rescue StandardError
      false
    end

    def silent_update?
      defined?(TranTuanNoiThat::Updater) && TranTuanNoiThat::Updater.respond_to?(:silent_update?) && TranTuanNoiThat::Updater.silent_update?
    rescue StandardError
      false
    end

    def notify(message, error: false)
      if silent_update?
        puts "[TT Update Bridge] #{message}"
        Sketchup.status_text = message.to_s.gsub("\n", ' ') if defined?(Sketchup)
      else
        UI.messagebox(message)
      end
      !error
    rescue StandardError
      !error
    end

    def read_state
      return {} unless File.file?(STATE_FILE)
      data = JSON.parse(File.binread(STATE_FILE).force_encoding('UTF-8'))
      data.is_a?(Hash) ? data : {}
    rescue StandardError => error
      puts "[TT Update Bridge state] #{error.class}: #{error.message}"
      {}
    end

    def write_state(state)
      FileUtils.mkdir_p(UPDATE_ROOT)
      tmp = "#{STATE_FILE}.tmp"
      File.binwrite(tmp, JSON.pretty_generate(state))
      FileUtils.mv(tmp, STATE_FILE, force: true)
      state
    end

    def cache_root(version)
      File.join(UPDATE_ROOT, version.to_s.gsub(/[^0-9A-Za-z_.-]/, '_'))
    end

    def safe_cache_path(root, relative)
      clean = relative.to_s.tr('\\', '/')
      raise 'Đường dẫn update cache không hợp lệ.' if clean.empty? || clean.start_with?('/') || clean.split('/').include?('..')
      target = File.expand_path(File.join(root, clean))
      root_expanded = File.expand_path(root)
      unless target == root_expanded || target.start_with?(root_expanded + File::SEPARATOR)
        raise 'File update nằm ngoài cache.'
      end
      target
    end

    def install_manifest(manifest)
      raise 'Manifest cập nhật không hợp lệ.' unless manifest.is_a?(Hash)
      version = manifest.fetch('version').to_s
      files = manifest.fetch('files')
      raise 'Danh sách file cập nhật không hợp lệ.' unless files.is_a?(Array)

      root = cache_root(version)
      staging = "#{root}.staging_#{Process.pid}_#{Time.now.to_i}"
      FileUtils.rm_rf(staging)
      FileUtils.mkdir_p(staging)
      cached_paths = []

      files.each do |item|
        relative = TranTuanNoiThat::Updater.safe_path(item.fetch('path'))
        expected = item['sha256'].to_s.downcase
        bytes = TranTuanNoiThat::Updater.download_verified(item.fetch('url'), expected, relative)

        if relative == LOADER_NAME
          loader_target = File.join(PLUGINS_ROOT, LOADER_NAME)
          File.binwrite("#{loader_target}.new", bytes)
          FileUtils.mv("#{loader_target}.new", loader_target, force: true)
          next
        end

        target = safe_cache_path(staging, relative)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, bytes)
        cached_paths << relative
      end

      FileUtils.rm_rf(root)
      FileUtils.mv(staging, root)
      state = {
        'version' => version,
        'updated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        'files' => cached_paths
      }
      write_state(state)

      raise 'Đã tải update nhưng không thể nạp bản vá runtime.' unless apply_state(state)

      TranTuanNoiThat.save_setting('installed_version', version)
      if defined?(TranTuanNoiThat::Settings)
        begin
          TranTuanNoiThat::Settings.notify("Đã cập nhật online #{version} qua Update Bridge.", 'ok')
        rescue StandardError
        end
      end
      notify("Cập nhật #{version} thành công.\nBản thương mại đã ký được giữ nguyên, không cần khởi động lại SketchUp.")
      true
    rescue StandardError => error
      FileUtils.rm_rf(staging) if defined?(staging) && staging && File.directory?(staging)
      notify("Không thể cập nhật bản thương mại:\n#{error.message}", error: true)
      false
    end

    def loadable_relative?(relative)
      clean = relative.to_s.tr('\\', '/')
      return false unless clean.downcase.end_with?('.rb')
      return false if clean == LOADER_NAME
      return false if SKIP_BASENAMES.include?(File.basename(clean))
      true
    end

    def apply_state(state = read_state)
      return true unless state.is_a?(Hash)
      version = state['version'].to_s
      files = Array(state['files'])
      return true if version.empty? || files.empty?

      root = cache_root(version)
      loaded = 0
      files.each do |relative|
        next unless loadable_relative?(relative)
        path = safe_cache_path(root, relative)
        next unless File.file?(path)
        load(path)
        loaded += 1
      end

      TranTuanNoiThat.save_setting('installed_version', version) if defined?(TranTuanNoiThat)
      TranTuanNoiThat.refresh_feature_commands if defined?(TranTuanNoiThat) && TranTuanNoiThat.respond_to?(:refresh_feature_commands)
      puts "[TT Update Bridge] Applied #{loaded} runtime patch file(s), version #{version}."
      true
    rescue StandardError => error
      puts "[TT Update Bridge apply] #{error.class}: #{error.message}"
      false
    end

    def patch_updater
      return false unless defined?(TranTuanNoiThat::Updater)
      updater = TranTuanNoiThat::Updater
      sc = class << updater; self; end

      unless sc.method_defined?(:tt_update_bridge_original_install)
        sc.alias_method :tt_update_bridge_original_install, :install
      end
      unless sc.method_defined?(:tt_update_bridge_original_files_outdated)
        sc.alias_method :tt_update_bridge_original_files_outdated, :files_outdated?
      end

      updater.define_singleton_method(:install) do |manifest|
        if TTTranTuanUpdateLoader.signed_runtime?
          TTTranTuanUpdateLoader.install_manifest(manifest)
        else
          tt_update_bridge_original_install(manifest)
        end
      end

      updater.define_singleton_method(:files_outdated?) do |manifest|
        if TTTranTuanUpdateLoader.signed_runtime?
          latest = manifest['version'].to_s
          local = TranTuanNoiThat.current_version.to_s
          state = TTTranTuanUpdateLoader.read_state
          state_version = state['version'].to_s
          return false if latest == local
          return false if !state_version.empty? && state_version == latest
          false
        else
          tt_update_bridge_original_files_outdated(manifest)
        end
      end

      true
    rescue StandardError => error
      puts "[TT Update Bridge patch] #{error.class}: #{error.message}"
      false
    end

    def boot
      attempts = 0
      timer_id = nil
      timer_id = UI.start_timer(0.5, true) do
        attempts += 1
        if defined?(TranTuanNoiThat::Updater)
          UI.stop_timer(timer_id) if timer_id
          patch_updater
          apply_state
        elsif attempts >= 40
          UI.stop_timer(timer_id) if timer_id
          puts '[TT Update Bridge] Không tìm thấy TranTuanNoiThat::Updater sau 20 giây.'
        end
      end
      true
    end
  end
end

TTTranTuanUpdateLoader.boot
