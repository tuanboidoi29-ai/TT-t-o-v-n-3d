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
  remove_const(:LOCKED_FEATURE_BASELINES) if const_defined?(:LOCKED_FEATURE_BASELINES, false)
  LOCKED_FEATURE_BASELINES = {
    'slat_wall_tool.rb' => {
      version: '1.9.215',
      sha256: '4cc0754cc1b42c12673063e27050f0c006572ac6747d801aa85056fe8f2b5be3'
    }
  }.freeze unless const_defined?(:LOCKED_FEATURE_BASELINES, false)

  remove_const(:VERSION) if const_defined?(:VERSION, false)
  VERSION = '1.9.251'.freeze

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

    def verify_locked_features
      LOCKED_FEATURE_BASELINES.each do |filename, spec|
        path = File.join(ROOT, filename)
        raise "Thiếu file khóa #{filename}." unless File.file?(path)
        actual = Digest::SHA256.file(path).hexdigest
        expected = spec[:sha256].to_s
        next if actual == expected
        raise "Tính năng khóa #{filename} đã bị sửa ngoài chủ đích. Mong đợi #{spec[:version]} / #{expected[0,12]}, nhận #{actual[0,12]}."
      end
      true
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
      CadWalls.close if const_defined?(:CadWalls, false) && CadWalls.respond_to?(:close)
      cleanup_retired_led_contact
      if const_defined?(:TamPro, false)
        TamPro.clear_highlight if TamPro.respond_to?(:clear_highlight)
        dialog = TamPro.instance_variable_get(:@dialog_thickness)
        dialog.close if dialog
      end
      reset_layout_runtime
      %w[
        board_tool
        door_standard_tool
        rename_ui
        rename_tool
        tam_pro
        bao_gia_tool
        scale_corner_lock
        slat_wall_tool
        box_tool
        drawer_tool
        round_tool
        stretch_mode_tool
        divide_boards
        notch_tool
        cut_block
        wall_junctions
        wall_block
        cad_wall_engine
        cad_walls_ui
        cad_walls
        door_open_mark
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
        grain_board_auto
        updater
        don_dim_line
      ].each { |stem| raise "Không nạp được #{stem}" unless runtime_load(stem) }

      verify_locked_features

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

    def cleanup_retired_led_contact
      if const_defined?(:LedTool, false) || const_defined?(:ContactTool, false)
        Sketchup.active_model.select_tool(nil)
      end
      [:LedTool, :ContactTool].each do |name|
        next unless const_defined?(name, false)
        runtime = const_get(name)
        dialog = runtime.instance_variable_get(:@dialog)
        dialog.close if dialog
        remove_const(name)
      end
      [:@led_cmd, :@contact_cmd].each do |key|
        cmd = instance_variable_get(key)
        next unless cmd
        cmd.set_validation_proc { MF_GRAYED }
        cmd.status_bar_text = 'Đã gỡ công cụ. Mở lại SketchUp để xóa nút cũ.'
      end
      %w[led_tool.rb contact_tool.rb icons/led.svg icons/contact.svg].each do |path|
        FileUtils.rm_f(File.join(ROOT, path))
      end
      %w[led_tool contact_tool].each do |folder|
        FileUtils.rm_rf(File.join(ROOT, 'data', folder))
      end
      true
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
          @cabinet_door_cmd.status_bar_text = 'P1-P2 chéo tự do · chuột làm TÂM chia · / hoặc click chia · mũi tên khóa hướng · SHIFT Dọc/Ngang · CTRL Lọt/Phủ · TAB.'
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

    def cleanup_retired_vector_image_cnc
      begin
        FileUtils.rm_f(File.join(ROOT, 'vector_cnc_tool.rb'))
        FileUtils.rm_f(File.join(ROOT, 'icons', 'vector_cnc.svg'))
        FileUtils.rm_rf(File.join(ROOT, 'data', 'vector_cnc'))

        if const_defined?(:VectorCNC, false)
          runtime = const_get(:VectorCNC)
          dialog = runtime.instance_variable_get(:@dialog) if runtime.respond_to?(:instance_variable_get)
          dialog.close if dialog
          remove_const(:VectorCNC)
        end

        if instance_variable_defined?(:@vector_cnc_cmd) && @vector_cnc_cmd
          @vector_cnc_cmd.tooltip = 'Chức năng CNC ảnh đã gỡ'
          @vector_cnc_cmd.status_bar_text = 'VECTOR CNC / ẢNH CNC đã được xóa. Mở lại SketchUp để toolbar làm sạch hoàn toàn.'
          @vector_cnc_cmd.set_validation_proc { MF_GRAYED }
        end
      rescue StandardError => error
        puts "[TT cleanup retired vector/image CNC] #{error.class}: #{error.message}"
      end
      true
    end

    def install_ui
      cleanup_retired_library
      cleanup_retired_cabinet_door
      cleanup_retired_vector_image_cnc
      unless @ui_installed
        @ui_installed = true
        @main_menu = UI.menu('Extensions').add_submenu(NAME)
        @toolbar = UI::Toolbar.new(NAME)
        [
          command('Vẽ Ván', 've_van.svg', 'P1/P2 xác định hướng tại P2; TAB theo Face; SHIFT mép/tâm/mép; nhập độ dày; click tạo', :board) { Board.activate },
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
      install_slat_wall_ui
      install_round_ui
      install_stretch_mode_ui
      install_grain_ui
      install_door_open_mark_ui
      install_notch_ui
      install_cut_block_ui
      install_wall_block_ui
      install_cad_walls_ui
      install_don_dim_line_ui
      install_divide_boards_ui
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
        'P1-P2 chéo tự do · chia lồng từng cánh · đường cũ khóa giữ nguyên · SHIFT Dọc/Ngang · CTRL Lọt/Phủ · TAB cài đặt'
      ) { DoorStandard.activate }

      # Đồng bộ lại text/icon khi hot reload từ command Vẽ Cánh Tủ cũ.
      @cabinet_door_cmd.tooltip = 'Tạo Cánh Chuẩn'
      @cabinet_door_cmd.status_bar_text = 'P1-P2 chéo tự do · chia lồng từng cánh · đường cũ khóa giữ nguyên · SHIFT Dọc/Ngang · CTRL Lọt/Phủ · TAB cài đặt.'
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

    def install_slat_wall_ui
      return false unless defined?(TranTuanNoiThat::SlatWall)
      @slat_wall_cmd ||= command('Tạo Vách Lam', 'slat_wall.svg',
        'Bắt Face hoặc hai góc · Preview lam · TAB thông số · SHIFT đổi hướng') { SlatWall.activate }
      @slat_wall_cmd.status_bar_text = 'Bắt Face hoặc hai góc · Preview lam · TAB thông số · SHIFT đổi hướng'
      add_feature_command_once(@slat_wall_cmd, :slat_wall_menu_installed)
      true
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

    def install_divide_boards_ui
      return false unless defined?(TranTuanNoiThat::DivideBoards)
      @divide_boards_cmd ||= command('Chia ván lọt lòng', 'divide_boards.svg', 'Chọn Face tấm mẫu; kéo hướng; /N chia đều khe; TAB mép/tâm/mép; click hoặc ENTER tạo.') { DivideBoards.activate }
      add_feature_command_once(@divide_boards_cmd, :divide_boards_menu_installed)
    end

    def install_don_dim_line_ui
      @don_dim_line_cmd ||= command('Dọn DIM / Line thừa', 'don_dim_line.svg', 'Dọn DIM trong Group/Component; tùy chọn nét rời; giữ cạnh tạo Face; một lần Undo.') { DonDimLine.run }
      add_feature_command_once(@don_dim_line_cmd, :don_dim_line_menu_installed)
    end

    def install_cad_walls_ui
      @cad_walls_cmd ||= command('Nhập CAD — Dựng tường', 'cad_walls.svg', 'Nhập DWG/DXF hoặc quét CAD đã chọn; lọc lớp, nhận diện nét tường, preview 3D rồi tạo khối.') { CadWalls.open }
      add_feature_command_once(@cad_walls_cmd, :cad_walls_menu_installed)
    end

    def install_wall_block_ui
      @wall_block_cmd ||= command('Vẽ Tường Khối', 'wall_block.svg', 'Nhập dày/cao; chọn P1, P2; TAB đổi giữa/trái/phải; vẽ nối tiếp.') { VeTuongKhoi.start_tool }
      @merge_groups_cmd ||= command('Gộp Group thành 1 khối', 'merge_groups.svg', 'Chọn từ 2 Group; ưu tiên hợp nhất Solid, nếu không được thì gom thành một Group.') { VeTuongKhoi.merge_selected_groups }
      add_feature_command_once(@wall_block_cmd, :wall_block_menu_installed)
      add_feature_command_once(@merge_groups_cmd, :merge_groups_menu_installed)
    end

    def install_cut_block_ui
      return false unless defined?(TranTuanNoiThat::CutBlock)
      @cut_block_cmd ||= command('Cắt Khối', 'cut_block.svg', 'Quét chọn khối · preview mặt cắt · CLICK cắt ngay, giữ cả hai phần · mũi tên/TAB đổi trục') { CutBlock.activate }
      @cut_block_cmd.status_bar_text = 'Quét chọn khối · preview mặt cắt · CLICK cắt ngay, giữ cả hai phần · mũi tên/TAB đổi trục'
      add_feature_command_once(@cut_block_cmd, :cut_block_menu_installed)
    end

    def install_notch_ui
      return false unless defined?(TranTuanNoiThat::NotchTool)
      @notch_cmd ||= command('Khấu ván AUTO', 'notch.svg', 'Click khấu ngay; SHIFT đổi khuôn/tấm bị khấu; TAB lưu mở rộng biên và dao; hoàn tất chỉ beep.') { NotchTool.activate }
      add_feature_command_once(@notch_cmd, :notch_menu_installed)
    end

    def install_door_open_mark_ui
      return false unless defined?(TranTuanNoiThat::DoorOpenMark)
      @door_open_mark_cmd ||= command('Đánh dấu hướng mở cánh', 'door_open_mark.svg', 'Giữa tấm: X nét đứt. Gần cạnh: V đỉnh phía bản lề. Click tạo dấu.') { DoorOpenMark.activate }
      add_feature_command_once(@door_open_mark_cmd, :door_open_mark_menu_installed)
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
      @grain_cmd.status_bar_text = 'Theo chiều dài từng tấm · UV 1220×2440 mm · TAB Tự động/Thủ công · A quét · ENTER áp dụng'
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
      @dim_auto_cmd ||= command('DIM 2 điểm', 'dim_auto.svg', 'Chọn P1, P2 rồi kéo chuột để đặt đường DIM.') { DetailDimensions.launch }
      @dim_auto_cmd.tooltip = 'DIM 2 điểm'
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
