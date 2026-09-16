# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'tmpdir'
require 'digest'
require 'base64'

module TranTuanNoiThat
  ROOT = __dir__.freeze unless const_defined?(:ROOT, false)
  NAME = 'TRẦN TUẤN NỘI THẤT'.freeze unless const_defined?(:NAME, false)

  remove_const(:VERSION) if const_defined?(:VERSION, false)
  VERSION = '1.9.53'.freeze

  remove_const(:MANIFEST_URL) if const_defined?(:MANIFEST_URL, false)
  MANIFEST_URL = 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/tran_tuan_noi_that_release/update_latest.json'.freeze

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

    def feature_validation_proc(feature)
      proc { feature_enabled?(feature) ? MF_ENABLED : MF_GRAYED }
    end

    def refresh_feature_commands
      return false unless @toolbar
      features = {
        'Vẽ Ván' => :board,
        'Tạo Khối BOX' => :box,
        'Vẽ Ngăn Kéo' => :drawer,
        'Bo Cong Khối' => :round,
        'Co Giãn Khối MODE' => :stretch_mode,
        'Xoay Vân Ván' => :grain,
        'Xuất Layout + Thống Kê Ván' => :layout_stats
      }
      @toolbar.each do |item|
        next unless item.is_a?(UI::Command)
        feature = features[item.tooltip.to_s]
        item.set_validation_proc(&feature_validation_proc(feature)) if feature
      end
      true
    rescue StandardError
      false
    end

    def reload_runtime
      # License V1.0.2 -> Payment V1.1.0 -> Owner Admin V1.2.x -> QR V1.3.0 -> AUTO SePay V1.4.0.
      # Grain V3.5.0, LayoutStats V0.8.1 và Bo Cong V2.2.7 giữ nguyên.
      %w[
        board_tool.rb
        box_tool.rb
        drawer_tool.rb
        round_tool.rb
        stretch_mode_tool.rb
        grain_tool.rb
        grain_material_fix.rb
        grain_align_fix.rb
        grain_standard_2440_fix.rb
        license_manager.rb
        license_payment_v110.rb
        license_owner_admin_v120.rb
        license_owner_admin_v121_fix.rb
        license_ui_v122_fix.rb
        license_owner_admin_v123_fix.rb
        license_commercial_v130_qr.rb
        license_commercial_v140_auto.rb
        layout_stats_tool.rb
        layout_stats_v030_patch.rb
        layout_stats_v040_compat.rb
        layout_stats_v040_patch.rb
        layout_stats_v040_compat.rb
        settings.rb
        updater.rb
      ].each do |file|
        path = File.join(ROOT, file)
        load(path) if File.file?(path)
      end

      %w[
        round_smooth_fix.rb
        stretch_detail_fix.rb
        stretch_auto_scan_fix.rb
        stretch_auto_scope_fix.rb
      ].each do |file|
        path = File.join(ROOT, file)
        load(path) if File.file?(path)
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
        [
          command('Vẽ Ván', 've_van.svg', 'Vẽ ván 3D theo P1/P2', :board) { Board.activate },
          command('Cài Đặt Chung', 'settings.svg', 'Mở cài đặt toàn hệ thống') { Settings.show },
          command('Kiểm Tra Cập Nhật', 'update.svg', 'Kiểm tra và nạp phiên bản mới') { Updater.check(true) }
        ].each do |cmd|
          @main_menu.add_item(cmd)
          @toolbar.add_item(cmd)
        end
      end

      install_license_ui
      install_box_ui
      install_drawer_ui
      install_round_ui
      install_stretch_mode_ui
      install_grain_ui
      install_layout_stats_ui
      refresh_feature_commands
      @toolbar.restore if @toolbar
      @toolbar.show if @toolbar
      true
    end

    def install_license_ui
      return false unless defined?(TranTuanNoiThat::License)
      @license_cmd ||= command(
        'Bản Quyền',
        'license.svg',
        'Mã máy · mua từng chức năng · QR + SePay tự nhận thanh toán · OWNER quản lý giá, khách và quyền.'
      ) { License.show_dialog }
      add_feature_command_once(@license_cmd, :license_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI License] #{error.class}: #{error.message}"
      false
    end

    def install_box_ui
      return if @box_ui_installed
      return unless defined?(TranTuanNoiThat::Box)
      @box_ui_installed = true
      cmd = command('Tạo Khối BOX', 'box.svg', 'Tạo BOX khối đặc/khung · SHIFT xoay 90° khi đặt', :box) { Box.show_dialog }
      add_feature_command(cmd)
    end

    def install_drawer_ui
      return if @drawer_ui_installed
      return unless defined?(TranTuanNoiThat::Drawer)
      @drawer_ui_installed = true
      cmd = command('Vẽ Ngăn Kéo', 'drawer.svg', 'Vẽ ngăn kéo 5 tấm theo vùng P1/P2', :drawer) { Drawer.activate }
      add_feature_command(cmd)
    end

    def install_round_ui
      return false unless defined?(TranTuanNoiThat::Round)
      @round_ui_installed = true
      @round_cmd ||= command('Bo Cong Khối', 'bo_cong.svg', 'Bo cung lồi/lõm; giữ 2 biên đầu/cuối', :round) { Round.activate }
      add_feature_command_once(@round_cmd, :round_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI Round] #{error.class}: #{error.message}"
      false
    end

    def install_stretch_mode_ui
      return false unless defined?(TranTuanNoiThat::StretchMode)
      @stretch_mode_ui_installed = true
      @stretch_mode_cmd ||= command('Co Giãn Khối MODE', 'stretch_mode.svg', 'AUTO QUÉT co/kéo khối; TAB đổi sang 3 ĐIỂM.', :stretch_mode) { StretchMode.activate }
      add_feature_command_once(@stretch_mode_cmd, :stretch_mode_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI StretchMode] #{error.class}: #{error.message}"
      false
    end

    def install_grain_ui
      return false unless defined?(TranTuanNoiThat::Grain)
      @grain_ui_installed = true
      @grain_cmd ||= command(
        'Xoay Vân Ván',
        'grain.svg',
        'Preview quét trước khi áp dụng · rule chi tiết · khổ theo vật liệu · UV đúng tỷ lệ.',
        :grain
      ) { Grain.activate }
      add_feature_command_once(@grain_cmd, :grain_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI Grain] #{error.class}: #{error.message}"
      false
    end

    def install_layout_stats_ui
      return false unless defined?(TranTuanNoiThat::LayoutStats)
      @layout_stats_ui_installed = true
      @layout_stats_cmd ||= command(
        'Xuất Layout + Thống Kê Ván',
        'layout_stats.svg',
        'LayOut 5 trang · mặt cắt dùng đúng khoảng mm từ mặt ngoài · PDF nối thêm thống kê ván.',
        :layout_stats
      ) { LayoutStats.show }
      add_feature_command_once(@layout_stats_cmd, :layout_stats_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI LayoutStats] #{error.class}: #{error.message}"
      false
    end

    def add_feature_command(cmd)
      (@main_menu || UI.menu('Extensions')).add_item(cmd)
      @toolbar.add_item(cmd) if @toolbar && !toolbar_has_command?(@toolbar, cmd.tooltip)
      @toolbar.show if @toolbar
    end

    def add_feature_command_once(cmd, menu_flag)
      unless instance_variable_get("@#{menu_flag}")
        (@main_menu || UI.menu('Extensions')).add_item(cmd)
        instance_variable_set("@#{menu_flag}", true)
      end
      if @toolbar && !toolbar_has_command?(@toolbar, cmd.tooltip)
        @toolbar.add_item(cmd)
      end
      @toolbar.show if @toolbar
    end

    def toolbar_has_command?(toolbar, tooltip)
      return false unless toolbar
      @toolbar.each do |item|
        next unless item.is_a?(UI::Command)
        return true if item.tooltip.to_s == tooltip.to_s
      end
      false
    rescue StandardError
      false
    end

    def command(title, icon_name, description, feature = nil, &block)
      cmd = UI::Command.new(title) do
        if feature.nil? || feature_enabled?(feature)
          if feature && defined?(TranTuanNoiThat::License) && !License.allowed?(feature, true)
            next
          end
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
      cmd.set_validation_proc { feature_enabled?(feature) ? MF_ENABLED : MF_GRAYED } if feature
      cmd
    end

    def boot
      reload_runtime
      install_ui
      return if @startup_check_scheduled
      @startup_check_scheduled = true
      UI.start_timer(1.0, false) { License.background_sync if defined?(TranTuanNoiThat::License) }
      UI.start_timer(3.0, false) { Updater.check(false) if setting('auto_update', true) }
    end
  end
end

TranTuanNoiThat.boot
