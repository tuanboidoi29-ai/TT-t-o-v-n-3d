# ============================================================
# TT - TẠO VÁN - TRẦN TUẤN
# ============================================================
module TranTuan
  module TaoVan
    ROOT = File.dirname(__FILE__) unless const_defined?(:ROOT)
    CORE = File.join(ROOT, 'core.rb') unless const_defined?(:CORE)
    UPDATE = File.join(ROOT, 'update.rb') unless const_defined?(:UPDATE)
    Sketchup.require(CORE) unless defined?(@core_loaded) && @core_loaded
    @core_loaded = true
    BOX = File.join(ROOT, 'box.rb') unless const_defined?(:BOX)
    Sketchup.require(BOX)
    DRAWER = File.join(ROOT, 'drawer.rb') unless const_defined?(:DRAWER)
    Sketchup.require(DRAWER)

    class << self
      def register_ui
        icon_dir = File.join(ROOT, 'icons')
        remove_legacy_ui

        @create_command ||= UI::Command.new('TT - Tạo ván Face 3D') { TranTuanDC::TaoVanFace3D.start }
        @create_command.tooltip = 'TT - Tạo ván Face 3D'
        @create_command.status_bar_text = 'Hover Face → Preview 3D → Click 1 nhập độ dày → TAB đổi hướng → Click 2 tạo ván'
        set_command_icons(@create_command, 'tao_van_16.png', 'tao_van_32.png', icon_dir)

        @box_command ||= UI::Command.new('TT - Tạo Box') { TranTuanDC::TaoBox.start }
        @box_command.tooltip = 'TT - Tạo Box'
        @box_command.status_bar_text = 'Tạo khối Box theo chiều rộng, sâu, cao (mm)'
        set_command_icons(@box_command, 'tao_box_16.png', 'tao_box_32.png', icon_dir)

        @drawer_command ||= UI::Command.new('TT - Tạo ngăn kéo') { TranTuan::TaoVan::Drawer.start }
        @drawer_command.tooltip = 'TT - Tạo ngăn kéo AUTO'
        @drawer_command.status_bar_text = 'AUTO: Click 2 điểm chéo bất kỳ → tự tính kích thước → tạo liên tục; TAB mở cài đặt; ESC thoát'
        set_command_icons(@drawer_command, 'tao_ngan_keo_16.png', 'tao_ngan_keo_32.png', icon_dir)

        @detail_command ||= UI::Command.new('TT - Xuất chi tiết ván') { TranTuan::TaoVan.export_board_details }
        @detail_command.tooltip = 'TT - Xuất chi tiết ván'
        @detail_command.status_bar_text = 'Quét Model và xuất chi tiết ván ra CSV để mở bằng Excel'
        set_command_icons(@detail_command, 'xuat_chi_tiet_16.png', 'xuat_chi_tiet_32.png', icon_dir)

        @update_command ||= UI::Command.new('TT - Cập nhật Vision') do
          # QUAN TRỌNG: luôn LOAD updater hiện tại.
          # Sketchup.require chỉ nạp lần đầu, vì vậy updater cũ có thể còn nằm trong bộ nhớ
          # sau khi RBZ mới đã được cài và gây lỗi start_with? của Array.
          raise 'Không tìm thấy update.rb.' unless File.file?(UPDATE)
          load(UPDATE)
          TranTuan::TaoVan::VisionUpdate.run
        end
        @update_command.tooltip = 'TT - Cập nhật Vision'
        @update_command.status_bar_text = 'Kiểm tra và cập nhật Vision'
        set_command_icons(@update_command, 'cap_nhat_16.png', 'cap_nhat_32.png', icon_dir)

        menu = UI.menu('Extensions')
        [
          'TT - Tạo ván Face 3D', 'TT - Cập nhật Vision',
          'TT - Tạo ngăn kéo', 'TT - Tạo Ngăn Kéo', 'TT - Tạo ngăn kéo cũ',
          'TT - Tạo ngăn kéo thủ công', 'TT - Tạo ngăn kéo tự động cũ'
        ].each { |n| remove_menu_item(menu, n) }
        menu.add_item(@create_command)
        menu.add_item(@box_command)
        menu.add_item(@drawer_command)
        menu.add_item(@detail_command)
        menu.add_item(@update_command)
        @menu = menu
        create_toolbar_once
        @ui_registered = true
        true
      end

      def export_board_details
        model = Sketchup.active_model; rows=[]
        scan=lambda do |entities,parent|
          entities.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            name=e.name.to_s.strip
            name=e.definition.name.to_s.strip if name.empty? && e.respond_to?(:definition)
            name='Ván' if name.empty?
            bb=e.bounds; sx=bb.width.to_f.to_mm; sy=bb.depth.to_f.to_mm; sz=bb.height.to_f.to_mm
            dims=[sx,sy,sz].sort; th=dims[0]; area=dims[1]*dims[2]/1_000_000.0; vol=sx*sy*sz/1_000_000_000.0
            rows << [rows.length+1,name,sx.round(2),sy.round(2),sz.round(2),th.round(2),area.round(4),vol.round(6),parent.empty? ? 'Model' : parent]
            children=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
            scan.call(children,"#{parent}/#{name}")
          end
        end
        scan.call(model.entities,'')
        if rows.empty?; UI.messagebox('Không tìm thấy Group/Component để xuất chi tiết ván.'); return end
        path=UI.savepanel('Xuất chi tiết ván',nil,"TT_ChiTiet_Van_#{Time.now.strftime('%Y%m%d_%H%M')}.csv"); return unless path
        require 'csv'
        CSV.open(path,'wb',encoding:'UTF-8') do |csv|
          csv << ['STT','Tên ván','Rộng (mm)','Sâu (mm)','Cao (mm)','Độ dày (mm)','Diện tích (m²)','Thể tích (m³)','Đường dẫn']
          rows.each{|r|csv<<r}
        end
        UI.messagebox("Đã xuất #{rows.length} chi tiết ván.\n\n#{path}")
      rescue => e
        UI.messagebox("Không thể xuất chi tiết ván:\n#{e.message}")
      end

      def reload_core_only
        TranTuanDC::TaoVanFace3D.reload! if defined?(TranTuanDC::TaoVanFace3D) && TranTuanDC::TaoVanFace3D.respond_to?(:reload!)
        true
      rescue => e
        puts "[TT_TaoVan] Core hot reload warning: #{e.message}"; true
      end
      def ui_registered?; !!@ui_registered end
      private
      def set_command_icons(c,s,l,d); sp=File.join(d,s); lp=File.join(d,l); c.small_icon=sp if File.file?(sp); c.large_icon=lp if File.file?(lp) end
      def create_toolbar_once
        if @toolbar
          return
        end
        @toolbar=UI.toolbar('TT - Tạo ván - Trần Tuấn')
        [@create_command,@box_command,@drawer_command,@detail_command,@update_command].each{|c|@toolbar.add_item(c)}
        @toolbar.show
      rescue => e; @toolbar=nil; puts "[TT_TaoVan] Toolbar warning: #{e.message}" end
      def remove_menu_item(menu,name); menu.delete_item(name) rescue nil end
      def remove_legacy_ui
        menu=UI.menu('Extensions')
        [
          'TT - Tạo ván từ Face','TT - Tạo ván từ Face Group','TT - Tạo ván từ Face - Ngoài Group',
          'TT - Tạo ván từ Face - Hover','TT - Tạo ván Face 3D','TT - Tạo ván từ Face 3D Hover',
          'TT - Tạo ván Face 3D','TT - Tạo ván','TRẦN TUẤN DC - Tạo ván từ Face',
          'TT - Tạo ngăn kéo cũ','TT - Tạo ngăn kéo thủ công','TT - Tạo ngăn kéo tự động cũ'
        ].each{|n|remove_menu_item(menu,n)}
      end
    end
    register_ui
  end
end
