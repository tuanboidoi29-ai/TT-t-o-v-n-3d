# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'digest'
require 'base64'

module TranTuanNoiThat
  ROOT = __dir__.freeze unless const_defined?(:ROOT, false)
  NAME = 'TRẦN TUẤN NỘI THẤT'.freeze unless const_defined?(:NAME, false)

  remove_const(:VERSION) if const_defined?(:VERSION, false)
  VERSION = '1.9.133'.freeze

  class << self
    def setting(key, default = nil)
      Sketchup.read_default(NAME, key.to_s, default)
    end

    def save_setting(key, value)
      Sketchup.write_default(NAME, key.to_s, value)
    end

    def current_version
      VERSION.to_s
    end

    def feature_enabled?(feature)
      value = setting("feature_#{feature}", true)
      value == true || value.to_s.downcase == 'true' || value.to_s == '1'
    end

    def feature_validation_proc(feature)
      proc { feature_enabled?(feature) ? MF_ENABLED : MF_GRAYED }
    end

    # Load the included Ruby source explicitly, including when reloading.
    def runtime_load(stem)
      path = File.join(ROOT, stem.to_s + '.rb')
      return false unless File.file?(path)
      load(path)
      true
    rescue StandardError => error
      puts "[TT runtime_load #{stem}] #{error.class}: #{error.message}"
      false
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

    def reset_layout_runtime
      # Drop patched singleton methods and aliases before loading the 1.9.55 chain.
      [:LayoutTechnical, :LayoutStats].each do |name|
        next unless TranTuanNoiThat.const_defined?(name, false)
        runtime = TranTuanNoiThat.const_get(name)
        runtime.finish_preview(nil) if runtime.respond_to?(:finish_preview)
        runtime.tt_cancel_preview_job if runtime.respond_to?(:tt_cancel_preview_job)
        dialog = runtime.instance_variable_get(:@dialog)
        dialog.close if dialog
        TranTuanNoiThat.send(:remove_const, name)
      end
    end

    def reload_runtime
      reset_layout_runtime
      %w[
        board_tool
        door_standard_tool
        rename_ui
        rename_tool
        tam_pro
        bao_gia_tool
        scale_corner_lock
        box_tool
        drawer_tool
        round_tool
        stretch_mode_tool
        grain_tool
        grain_material_fix
        grain_align_fix
        grain_standard_2440_fix
        grain_reload_v351_fix
        dimension_tool
        layout_stats_tool
        layout_stats_v030_patch
        layout_stats_v040_compat
        layout_stats_v040_patch
        layout_stats_v040_compat
        settings
        updater
      ].each { |stem| raise "Không nạp được #{stem}" unless runtime_load(stem) }

      %w[
        round_smooth_fix
        stretch_detail_fix
        stretch_auto_scan_fix
        stretch_auto_scope_fix
        stretch_window_tool
      ].each { |stem| raise "Không nạp được #{stem}" unless runtime_load(stem) }
      true
    rescue StandardError => error
      UI.messagebox("Không thể nạp lại hệ thống:\n#{error.message}")
      false
    end

    def cleanup_retired_library
      # Dọn sạch Thư viện Nội thất đã gỡ ở 1.9.123.
      begin
        FileUtils.rm_rf(File.join(ROOT, 'library_cache'))
        FileUtils.rm_f(File.join(ROOT, 'library_tool.rb'))
        FileUtils.rm_f(File.join(ROOT, 'icons', 'library.svg'))

        %w[
          library_sources_json
          library_auto_sync
          library_local_folders_json
        ].each do |key|
          Sketchup.write_default(NAME, key, key == 'library_auto_sync' ? false : '[]')
        end

        if const_defined?(:LibraryTool, false)
          remove_const(:LibraryTool)
        end

        if instance_variable_defined?(:@library_cmd) && @library_cmd
          @library_cmd.tooltip = 'Thư Viện Nội Thất (ĐÃ GỠ)'
          @library_cmd.status_bar_text = 'Chức năng Thư Viện Nội Thất đã được gỡ.'
          @library_cmd.set_validation_proc { MF_GRAYED }
        end
      rescue StandardError => error
        puts "[TT cleanup retired library] #{error.class}: #{error.message}"
      end
      true
    end

    def cleanup_retired_cabinet_door
      begin
        FileUtils.rm_f(File.join(ROOT, 'cabinet_door_tool.rb'))
        FileUtils.rm_f(File.join(ROOT, 'icons', 'cabinet_door.svg'))

        # Nếu toolbar cũ còn sống trong phiên hiện tại, biến chính command đó
        # thành Tạo Cánh Chuẩn thay vì để lại icon chết.
        if instance_variable_defined?(:@cabinet_door_cmd) && @cabinet_door_cmd
          title = 'Tạo Cánh Chuẩn'
          @cabinet_door_cmd.tooltip = title
          @cabinet_door_cmd.status_bar_text = 'P1-P2 chéo · preview 3D · / chia cánh · SHIFT Dọc/Ngang · CTRL Lọt/Phủ · TAB cài đặt.'
          @cabinet_door_cmd.menu_text = title if @cabinet_door_cmd.respond_to?(:menu_text=)
          icon = File.join(ROOT, 'icons', 'door_standard.svg')
          if File.file?(icon)
            @cabinet_door_cmd.small_icon = icon
            @cabinet_door_cmd.large_icon = icon
          end
        end
      rescue StandardError => error
        puts "[TT cleanup retired cabinet door] #{error.class}: #{error.message}"
      end
      true
    end

    def install_ui
      cleanup_retired_library
      cleanup_retired_cabinet_door
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

      install_box_ui
      install_drawer_ui
      install_door_standard_ui
      install_rename_ui
      install_tam_pro_ui
      install_bao_gia_ui
      install_scale_corner_lock_ui
      install_round_ui
      install_stretch_mode_ui
      install_grain_ui
      install_layout_stats_ui
      install_dimensions_ui
      refresh_feature_commands
      @toolbar.restore if @toolbar
      @toolbar.show if @toolbar
      true
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

    def install_door_standard_ui
      return false unless defined?(TranTuanNoiThat::DoorStandard)

      @cabinet_door_cmd ||= command(
        'Tạo Cánh Chuẩn',
        'door_standard.svg',
        'P1-P2 chéo tự do · preview 3D · TÂM hoặc / = +1 cánh · SHIFT Dọc/Ngang · CTRL Phủ/Lọt · TAB cài đặt'
      ) { DoorStandard.activate }

      # Đồng bộ lại text/icon khi hot reload từ command Vẽ Cánh Tủ cũ.
      @cabinet_door_cmd.tooltip = 'Tạo Cánh Chuẩn'
      @cabinet_door_cmd.status_bar_text = 'P1-P2 chéo trên mặt đứng · bắt điểm tự do không khóa hướng · tự hiện Mép trái/Tâm/Mép phải · / chia cánh · SHIFT Dọc/Ngang · CTRL Lọt/Phủ · TAB cài đặt.'
      @cabinet_door_cmd.menu_text = 'Tạo Cánh Chuẩn' if @cabinet_door_cmd.respond_to?(:menu_text=)
      icon = File.join(ROOT, 'icons', 'door_standard.svg')
      if File.file?(icon)
        @cabinet_door_cmd.small_icon = icon
        @cabinet_door_cmd.large_icon = icon
      end

      add_feature_command_once(@cabinet_door_cmd, :cabinet_door_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI DoorStandard] #{error.class}: #{error.message}"
      false
    end

    def install_rename_ui
      return false unless defined?(TranTuanNoiThat::RenameTool)

      @rename_cmd ||= command(
        'THỐNG KÊ VÁN',
        'board_stats.svg',
        'Quét Group/Component · thống kê ván · kích thước · độ dày · biên dạng'
      ) { RenameTool.show }

      @rename_cmd.tooltip = 'THỐNG KÊ VÁN'
      @rename_cmd.status_bar_text = 'Quét Group/Component · thống kê ván · kích thước · độ dày · biên dạng.'
      @rename_cmd.menu_text = 'THỐNG KÊ VÁN' if @rename_cmd.respond_to?(:menu_text=)
      icon = File.join(ROOT, 'icons', 'board_stats.svg')
      if File.file?(icon)
        @rename_cmd.small_icon = icon
        @rename_cmd.large_icon = icon
      end

      add_feature_command_once(@rename_cmd, :rename_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI BoardStats] #{error.class}: #{error.message}"
      false
    end

    def install_tam_pro_ui
      return false unless defined?(TranTuanNoiThat::TamPro)
      TamPro.add_menu_items(@main_menu)
      TamPro.add_toolbar_items(@toolbar)
      true
    rescue StandardError => error
      puts "[TT UI TamPro] #{error.class}: #{error.message}"
      false
    end

    def install_bao_gia_ui
      return false unless defined?(TranTuanNoiThat::BaoGiaTool)
      @bao_gia_cmd ||= command(
        'Bảng Báo Giá',
        'bao_gia.svg',
        'Lập báo giá · Lưu/Mở · QR VietQR · Xuất PDF · Chia sẻ Zalo'
      ) { BaoGiaTool.show }
      add_feature_command_once(@bao_gia_cmd, :bao_gia_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI BaoGia] #{error.class}: #{error.message}"
      false
    end

    def install_scale_corner_lock_ui
      return false unless defined?(TranTuanNoiThat::ScaleCornerLock)
      @scale_corner_lock_cmd ||= command(
        'Scale 4 Cạnh',
        'scale_corner_lock.svg',
        'Hiện 4 tay nắm trung điểm Trái/Phải/Trên/Dưới · kéo trung điểm, phía đối diện tự khóa'
      ) { ScaleCornerLock.activate }
      add_feature_command_once(@scale_corner_lock_cmd, :scale_corner_lock_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI ScaleCornerLock] #{error.class}: #{error.message}"
      false
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
        'Preview quét trước khi áp dụng · rule chi tiết · khổ theo vật liệu · UV đúng tỷ lệ · nạp nóng an toàn.',
        :grain
      ) { Grain.activate }
      add_feature_command_once(@grain_cmd, :grain_menu_installed)
      true
    rescue StandardError => error
      puts "[TT UI Grain] #{error.class}: #{error.message}"
      false
    end

    def install_dimensions_ui
      # Existing sessions cannot remove toolbar/menu entries through SketchUp's API.
      # Disable the retired command until the next SketchUp restart.
      @dim_points_cmd.set_validation_proc { MF_GRAYED } if @dim_points_cmd
      @dim_auto_cmd ||= command('DIM tự động mặt trước', 'dim_auto.svg', 'DIM ngang, cao, tổng ba chiều và lọt lòng. Tab mở cài đặt.') { DetailDimensions.launch }
      @dim_auto_cmd.tooltip = 'DIM tự động mặt trước'
      add_feature_command_once(@dim_auto_cmd, :dim_auto_menu_installed)
    end

    def install_layout_stats_ui
      return false unless defined?(TranTuanNoiThat::LayoutStats)
      @layout_stats_ui_installed = true
      @layout_stats_cmd ||= command(
        'Xuất Layout + Thống Kê Ván',
        'layout_stats.svg',
        'Xuất LayOut/PDF kỹ thuật + thống kê ván.',
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
      raise "Nạp hệ thống không thành công." unless reload_runtime
      install_ui
      unless @startup_check_scheduled
        @startup_check_scheduled = true
        UI.start_timer(5.0, false) do
          Updater.check(false) if setting('auto_update', true)
        end
      end
    end
  end
end

TranTuanNoiThat.boot
