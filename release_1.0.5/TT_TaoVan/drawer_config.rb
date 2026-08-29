# TT Drawer configuration override
# Quy tac Hau:
# - Tat Hau: khong tao Hau.
# - Offset mep ngoai = 9 mm: Hau lot.
# - Offset mep ngoai = 0 mm: Hau phu.
# - Offset tu day = 15 mm: tinh tu mat duoi cua 4 thanh.
module TranTuan
  module TaoVan
    module Drawer
      module_function

      class << self
        alias_method :defaults_before_config_override, :defaults
      end

      def defaults
        d = defaults_before_config_override
        d['back_enabled'] = Sketchup.active_model.get_attribute(DICT, 'back_enabled', 1).to_i != 0
        d
      end
      module_function :defaults

      class << self
        alias_method :show_settings_before_config_override, :show_settings
      end

      def show_settings(tool=nil)
        d = defaults
        @dialog ||= UI::HtmlDialog.new(
          dialog_title: 'TT - CÀI ĐẶT NGĂN KÉO AUTO',
          preferences_key: 'TT_Drawer_Auto_Final',
          scrollable: true, resizable: true, width: 450, height: 760,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save_config') do |_c, json|
          begin
            data = JSON.parse(json)
            vals = {}
            %w[rail_gap gap_top gap_bottom gap_front depth_reserve wall_t bottom_t back_t back_edge_offset back_bottom_offset].each do |k|
              vals[k] = parse_mm(data[k])
            end
            vals['back_enabled'] = !!data['back_enabled']
            raise 'Thong so phai la so mm khong am.' if vals.values_at('rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t','back_t','back_edge_offset','back_bottom_offset').any? { |v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Do day 4 thanh phai lon hon 0.' if vals['wall_t'] <= 0
            raise 'Do day tam hau phai lon hon 0.' if vals['back_t'] <= 0

            # Offset la nguon quyet dinh che do: 0 = phu, 9 = lot.
            vals['back_edge_offset'] = 0.0 if vals['back_edge_offset'].abs < 0.001
            vals['back_edge_offset'] = 9.0 if (vals['back_edge_offset'] - 9.0).abs < 0.001
            vals['back_bottom_offset'] = 15.0 if (vals['back_bottom_offset'] - 15.0).abs < 0.001

            model = Sketchup.active_model
            vals.each { |k,v| model.set_attribute(DICT, k, v.is_a?(Numeric) ? v.to_f : (v ? 1 : 0)) }
            @dialog.close
            tool ? tool.apply_settings(vals) : model.select_tool(TwoPointTool.new(vals))
          rescue => e
            UI.messagebox("Thong so khong hop le:\n#{e.message}")
          end
        end
        @dialog.show
      end
      module_function :show_settings

      def settings_html(d)
        esc = ->(v) { v.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;') }
        fields = [
          ['rail_gap','Ray moi ben'], ['gap_top','Ho tren'], ['gap_bottom','Ho duoi'],
          ['gap_front','Ho truoc'], ['depth_reserve','Chua phia sau'],
          ['wall_t','Do day 4 thanh'], ['bottom_t','Do day tam day'],
          ['back_t','Do day tam hau'], ['back_edge_offset','Offset hau tu mep ngoai'],
          ['back_bottom_offset','Offset hau tu day']
        ].map do |k,l|
          "<label>#{l}</label><input id='#{k}' value='#{esc.call(d[k])}' style='width:110px;padding:7px'>"
        end.join
        checked = d['back_enabled'] ? 'checked' : ''
        "<html><head><meta charset='utf-8'></head><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'>" \
        "<h2 style='color:#ff7a00'>TT - NGAN KEO AUTO</h2>" \
        "<b style='color:#ff7a00'>TAB = CAI DAT | CLICK 2 DIEM TREN CUNG MAT</b>" \
        "<p>4 thanh mac dinh 17,5 mm. Tam day la bo phan chinh cua ngan keo.</p>" \
        "<div style='display:flex;align-items:center;justify-content:space-between;padding:10px 0;border-bottom:1px solid #444'>" \
        "<b>Hậu</b><label style='display:flex;align-items:center;gap:8px'><input id='back_enabled' type='checkbox' #{checked} style='width:20px;height:20px'> BẬT / TẮT</label></div>" \
        "<div style='display:grid;grid-template-columns:1fr 125px;gap:8px;margin-top:12px'>#{fields}</div>" \
        "<div style='margin-top:14px;padding:10px;border:1px solid #555;border-radius:6px'>" \
        "<b>QUY TẮC HẬU</b><br>" \
        "Tắt Hậu → không tạo phần hậu lọt riêng.<br>" \
        "Offset hậu từ mép ngoài = <b>9 mm</b> → HẬU LỌT.<br>" \
        "Offset hậu từ mép ngoài = <b>0 mm</b> → HẬU PHỦ.<br>" \
        "Offset hậu từ đáy = <b>15 mm</b> → tính từ <b>mặt dưới của 4 thành</b>.</div>" \
        "<p style='color:#aaa'>SHIFT là phím tắt bật/tắt Hậu. Cấu hình chính được lưu trong TAB Cài đặt.</p>" \
        "<button onclick='saveConfig()' style='width:100%;padding:12px;background:#ff7a00;color:white;border:0;border-radius:6px;font-weight:bold'>LƯU & TIẾP TỤC AUTO</button>" \
        "<script>function saveConfig(){const a=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t','back_t','back_edge_offset','back_bottom_offset'];let o={back_enabled:document.getElementById('back_enabled').checked};a.forEach(k=>o[k]=document.getElementById(k).value);sketchup.save_config(JSON.stringify(o));}</script>" \
        "</body></html>"
      end
      module_function :settings_html

      class TwoPointTool
        alias_method :initialize_before_config_override, :initialize
        def initialize(cfg)
          initialize_before_config_override(cfg)
          @back_mode = if cfg['back_enabled'] == false || cfg['back_enabled'].to_i == 0
                         :none
                       elsif (cfg['back_edge_offset'].to_f).abs < 0.001
                         :phủ
                       else
                         :lọt
                       end
        end

        alias_method :apply_settings_before_config_override, :apply_settings
        def apply_settings(cfg)
          apply_settings_before_config_override(cfg)
          @back_mode = if cfg['back_enabled'] == false || cfg['back_enabled'].to_i == 0
                         :none
                       elsif (cfg['back_edge_offset'].to_f).abs < 0.001
                         :phủ
                       else
                         :lọt
                       end
          status("ĐÃ LƯU → HẬU #{back_mode_name} | CLICK ĐIỂM 1")
        end

        alias_method :onKeyDown_before_config_override, :onKeyDown
        def onKeyDown(key, repeat, *args)
          if key == SHIFT_KEY && !repeat
            enabled = !(@back_mode != :none)
            enabled = !enabled
            cfg = Drawer.defaults
            cfg['back_enabled'] = enabled
            @back_mode = if !enabled
                           :none
                         elsif cfg['back_edge_offset'].to_f.abs < 0.001
                           :phủ
                         else
                           :lọt
                         end
            Sketchup.active_model.set_attribute(DICT, 'back_enabled', enabled ? 1 : 0)
            status("HẬU → #{back_mode_name} | SHIFT bật/tắt")
            return true
          end
          onKeyDown_before_config_override(key, repeat, *args)
        end
      end
    end
  end
end
