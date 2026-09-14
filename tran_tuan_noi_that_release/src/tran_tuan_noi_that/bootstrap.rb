# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'tmpdir'
require 'digest'

module TranTuanNoiThat
  ROOT = __dir__.freeze unless const_defined?(:ROOT)
  VERSION = '1.8.1'.freeze unless const_defined?(:VERSION)
  NAME = 'TRẦN TUẤN NỘI THẤT'.freeze unless const_defined?(:NAME)
  MANIFEST_URL = 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/tran_tuan_noi_that_release/update.json'.freeze unless const_defined?(:MANIFEST_URL)

  class << self
    def setting(key, default = nil)
      Sketchup.read_default(NAME, key.to_s, default)
    end

    def save_setting(key, value)
      Sketchup.write_default(NAME, key.to_s, value)
    end

    def current_version
      setting('installed_version', VERSION).to_s
    end

    def feature_enabled?(feature)
      value = setting("feature_#{feature}", true)
      value == true || value.to_s.downcase == 'true' || value.to_s == '1'
    end

    def refresh_feature_commands
      return false unless @toolbar
      features = {
        'Vẽ Ván' => :board,
        'Tạo Khối BOX' => :box,
        'Vẽ Ngăn Kéo' => :drawer,
        'Bo Cong Khối' => :round
      }
      @toolbar.each do |item|
        next unless item.is_a?(UI::Command)
        feature = features[item.tooltip.to_s]
        next unless feature
        item.set_validation_proc(&feature_validation_proc(feature))
      end
      true
    end

    def feature_validation_proc(feature)
      proc { feature_enabled?(feature) ? MF_ENABLED : MF_GRAYED }
    end

    def reload_runtime
      %w[board_tool.rb box_tool.rb drawer_tool.rb round_tool.rb settings.rb updater.rb].each do |file|
        load File.join(ROOT, file)
      end
      true
    rescue StandardError => error
      UI.messagebox("Không thể nạp lại hệ thống:\n#{error.message}")
      false
    end

    def install_ui
      unless @ui_installed
        @ui_installed = true
        @main_menu = UI.menu('Extensions').add_submenu(NAME)
        @toolbar = UI::Toolbar.new(NAME)
        commands = [
          command('Vẽ Ván', 've_van.svg', 'Vẽ ván 3D theo P1/P2', :board) { Board.activate },
          command('Cài Đặt Chung', 'settings.svg', 'Mở cài đặt toàn hệ thống') { Settings.show },
          command('Kiểm Tra Cập Nhật', 'update.svg', 'Kiểm tra và nạp phiên bản mới') { Updater.check(true) }
        ]
        commands.each do |cmd|
          @main_menu.add_item(cmd)
          @toolbar.add_item(cmd)
        end
      end

      install_box_ui
      install_drawer_ui
      install_round_ui
      refresh_feature_commands
      @toolbar.restore if @toolbar
    end

    # Có thể gọi lại sau cập nhật nóng. Chỉ thêm nút BOX đúng một lần trong phiên.
    def install_box_ui
      return if @box_ui_installed
      return unless defined?(TranTuanNoiThat::Box)

      @box_ui_installed = true
      cmd = command('Tạo Khối BOX', 'box.svg', 'Tạo BOX khối đặc hoặc khung', :box) { Box.show_dialog }
      (@main_menu || UI.menu('Extensions')).add_item(cmd)
      @toolbar.add_item(cmd) if @toolbar
      @toolbar.show if @toolbar
    end

    def install_drawer_ui
      return if @drawer_ui_installed
      return unless defined?(TranTuanNoiThat::Drawer)

      @drawer_ui_installed = true
      cmd = command('Vẽ Ngăn Kéo', 'drawer.svg', 'Vẽ ngăn kéo 5 tấm theo vùng P1/P2', :drawer) { Drawer.activate }
      (@main_menu || UI.menu('Extensions')).add_item(cmd)
      @toolbar.add_item(cmd) if @toolbar
      @toolbar.show if @toolbar
    end

    def install_round_ui
      return if @round_ui_installed
      return unless defined?(TranTuanNoiThat::Round)

      @round_ui_installed = true
      cmd = command('Bo Cong Khối', 'bo_cong.svg', 'Bo cung lồi/lõm tại góc; TAB đổi chế độ', :round) { Round.activate }
      (@main_menu || UI.menu('Extensions')).add_item(cmd)
      @toolbar.add_item(cmd) if @toolbar
      @toolbar.show if @toolbar
    end

    def command(title, icon_name, description, feature = nil, &block)
      cmd = UI::Command.new(title) do
        if feature.nil? || feature_enabled?(feature)
          block.call
        else
          UI.messagebox("Tính năng #{title} đang tắt trong Cài Đặt Chung.")
        end
      end
      icon = File.join(ROOT, 'icons', icon_name)
      cmd.small_icon = icon
      cmd.large_icon = icon
      cmd.tooltip = title
      cmd.status_bar_text = description
      if feature
        cmd.set_validation_proc { feature_enabled?(feature) ? MF_ENABLED : MF_GRAYED }
      end
      cmd
    end

    def boot
      reload_runtime
      install_ui
      return if @startup_check_scheduled
      @startup_check_scheduled = true
      UI.start_timer(3.0, false) { Updater.check(false) if setting('auto_update', true) }
    end
  end
end

TranTuanNoiThat.boot
