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
        alias_method :defaults_before_config_override, :defaults unless method_defined?(:defaults_before_config_override)
      end

      def defaults
        d = defaults_before_config_override
        d['back_enabled'] = Sketchup.active_model.get_attribute(DICT, 'back_enabled', 1).to_i != 0
        d
      end
      module_function :defaults

      class << self
        alias_method :show_settings_before_config_override, :show_settings unless method_defined?(:show_settings_before_config_override)
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
            raise 'Thông số phải là số mm không âm.' if vals.values_at('rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t','back_t','back_edge_offset','back_bottom_offset').any? { |v| !v.is_a?(Numeric) || !v.finite? || v < 0 }
            raise 'Độ dày 4 thành phải lớn hơn 0.' if vals['wall_t'] <= 0
            raise 'Độ dày tấm hậu phải lớn hơn 0.' if vals['back_t'] <= 0
            vals['back_edge_offset'] = 0.0 if vals['back_edge_offset'].abs < 0.001
            vals['back_edge_offset'] = 9.0 if (vals['back_edge_offset'] - 9.0).abs < 0.001
            vals['back_bottom_offset'] = 15.0 if (vals['back_bottom_offset'] - 15.0).abs < 0.001
            model = Sketchup.active_model
            vals.each { |k,v| model.set_attribute(DICT, k, v.is_a?(Numeric) ? v.to_f : (v ? 1 : 0)) }
            @dialog.close
            tool ? tool.apply_settings(vals) : model.select_tool(TwoPointTool.new(vals))
          rescue => e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end
      module_function :show_settings

      def settings_html(d)
        esc = ->(v) { v.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;') }
        fields = [
          ['rail_gap','Ray mỗi bên'], ['gap_top','Hở trên'], ['gap_bottom','Hở dưới'],
          ['gap_front','Hở trước'], ['depth_reserve','Chừa phía sau'],
          ['wall_t','Độ dày 4 thành'], ['bottom_t','Độ dày tấm đáy'],
          ['back_t','Độ dày tấm hậu'], ['back_edge_offset','Offset hậu từ mép ngoài'],
          ['back_bottom_offset','Offset hậu từ đáy']
        ].map do |k,l|
          "<label>#{l}</label><input id='#{k}' value='#{esc.call(d[k])}' style='width:110px;padding:7px'>"
        end.join
        checked = d['back_enabled'] ? 'checked' : ''
        "<html><head><meta charset='utf-8'></head><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'>" \
        "<h2 style='color:#ff7a00'>TT - NGAN KEO AUTO</h2>" \
        "<b style='color:#ff7a00'>TAB = CAI DAT | CLICK 2 DIEM TREN CUNG MAT</b>" \
        "<p>4 thành mặc định 17,5 mm. Tấm đáy là bộ phận chính của ngăn kéo.</p>" \
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
        alias_method :initialize_before_config_override, :initialize unless method_defined?(:initialize_before_config_override)
        def initialize(cfg)
          initialize_before_config_override(cfg)
          enabled = !(cfg['back_enabled'] == false || cfg['back_enabled'].to_s == '0')
          @back_mode = if !enabled
                         :none
                       elsif cfg['back_edge_offset'].to_f.abs < 0.001
                         :phủ
                       else
                         :lọt
                       end
        end

        alias_method :apply_settings_before_config_override, :apply_settings unless method_defined?(:apply_settings_before_config_override)
        def apply_settings(cfg)
          apply_settings_before_config_override(cfg)
          enabled = !(cfg['back_enabled'] == false || cfg['back_enabled'].to_s == '0')
          @back_mode = if !enabled
                         :none
                       elsif cfg['back_edge_offset'].to_f.abs < 0.001
                         :phủ
                       else
                         :lọt
                       end
          status("ĐÃ LƯU → HẬU #{back_mode_name} | CLICK ĐIỂM 1")
        end

        alias_method :onKeyDown_before_config_override, :onKeyDown unless method_defined?(:onKeyDown_before_config_override)
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

      # Fix 1.2.9: lấy chiều sâu qua nhiều lần raytest, bỏ qua mặt đối diện
      # của chính tấm thành (thường đúng bằng 17,5 mm). Khi raytest đầu tiên
      # chạm thành dày 17,5 mm, tiếp tục ray từ sau mặt đó để tìm mặt khoang.
      class TwoPointTool
        alias_method :depth_from_region_before_129, :depth_from_region unless method_defined?(:depth_from_region_before_129)
        def depth_from_region(a,b)
          xmin,xmax,zmin,zmax = normalized_region(a,b)
          o = Geom::Point3d.new((xmin+xmax)*0.5, 0, (zmin+zmax)*0.5).transform(@frame)
          dir = unit(@frame.yaxis)
          model = Sketchup.active_model
          start = o + dir.clone.tap { |v| v.length = 0.5.mm }
          traveled = 0.0
          wall = [@cfg['wall_t'].to_f, 0.0].max
          12.times do
            hit = model.raytest([start, dir])
            break unless hit && hit[0].is_a?(Geom::Point3d)
            hp = hit[0]
            seg = start.distance(hp).to_mm
            break if seg <= 0.01
            traveled += seg
            # Bỏ qua lớp mặt/thành đầu tiên và tiếp tục vào khoang.
            start = hp + dir.clone.tap { |v| v.length = 0.5.mm }
            next if traveled <= wall + 2.0
            # Nếu đã đi qua lớp thành, đây là mặt giới hạn khoang hợp lệ.
            return traveled
          end
          0.0
        rescue
          0.0
        end
      end

      # Fix 1.2.9: nếu 2 điểm cùng X (R=0), dùng chiều rộng thực của Face
      # thay vì báo vùng rộng 0 mm. Hai điểm vẫn quyết định cao độ.
      class TwoPointTool
        alias_method :normalized_region_before_129, :normalized_region unless method_defined?(:normalized_region_before_129)
        def normalized_region(a,b)
          qa = frame_point(locked_point(a)); qb = frame_point(locked_point(b))
          xmin = [qa.x,qb.x].min; xmax = [qa.x,qb.x].max
          zmin = [qa.z,qb.z].min; zmax = [qa.z,qb.z].max
          if (xmax-xmin).abs < 0.1.mm && @face
            tr = @path ? @path.transformation : Geom::Transformation.new
            pts = @face.vertices.map { |v| v.position.transform(tr).transform(@frame.inverse) }
            fx = pts.map(&:x)
            xmin = fx.min
            xmax = fx.max
          end
          [xmin,xmax,zmin,zmax]
        rescue
          normalized_region_before_129(a,b)
        end
      end
    end
  end
end
