# TT - NGAN KEO AUTO - CAI DAT CHUAN 1.3.2
# Quy tac HAU:
# - Tat: khong tao hau.
# - Lot: hau lot trong khung, offset mep ngoai 9 mm.
# - Phu: hau phu ngoai thanh sau, offset mep ngoai 0 mm.
# - Do day hau = do day tam day (khong con o "Do day tam hau").
# - Offset tu day = 15 mm, tinh tu mat duoi cua 4 thanh.
module TranTuan
  module TaoVan
    module Drawer
      module_function

      class << self
        alias_method :defaults_before_132, :defaults unless method_defined?(:defaults_before_132)
      end

      def defaults
        d = defaults_before_132
        model = Sketchup.active_model
        enabled = model.get_attribute(DICT, 'back_enabled', 1).to_i != 0
        stored_mode = model.get_attribute(DICT, 'back_mode', nil).to_s
        edge = model.get_attribute(DICT, 'back_edge_offset', 9.0).to_f
        mode = if stored_mode == 'phu' || stored_mode == 'phủ'
                 'phu'
               elsif stored_mode == 'lot' || stored_mode == 'lọt'
                 'lot'
               elsif edge.abs < 0.001
                 'phu'
               else
                 'lot'
               end
        d['back_enabled'] = enabled
        d['back_mode'] = enabled ? mode : 'none'
        d['back_edge_offset'] = (mode == 'phu' ? 0.0 : 9.0)
        d['back_t'] = d['bottom_t'].to_f
        d
      end
      module_function :defaults

      class << self
        alias_method :show_settings_before_132, :show_settings unless method_defined?(:show_settings_before_132)
      end

      def show_settings(tool=nil)
        d = defaults
        @dialog ||= UI::HtmlDialog.new(
          dialog_title: 'TT - CÀI ĐẶT NGĂN KÉO AUTO',
          preferences_key: 'TT_Drawer_Auto_Final_132',
          scrollable: true,
          resizable: true,
          width: 470,
          height: 790,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save_config_132') do |_c, json|
          begin
            data = JSON.parse(json)
            vals = {}
            %w[rail_gap gap_top gap_bottom gap_front depth_reserve wall_t bottom_t back_bottom_offset].each do |k|
              vals[k] = parse_mm(data[k])
            end
            vals['back_enabled'] = !!data['back_enabled']
            vals['back_mode'] = data['back_mode'].to_s

            numeric_keys = %w[rail_gap gap_top gap_bottom gap_front depth_reserve wall_t bottom_t back_bottom_offset]
            bad = numeric_keys.any? do |k|
              v = vals[k]
              !v.is_a?(Numeric) || !v.finite? || v < 0
            end
            raise 'Thông số phải là số mm không âm.' if bad
            raise 'Độ dày 4 thành phải lớn hơn 0.' if vals['wall_t'] <= 0
            raise 'Độ dày tấm đáy phải lớn hơn 0.' if vals['bottom_t'] <= 0
            raise 'Chế độ hậu không hợp lệ.' unless %w[none lot phu].include?(vals['back_mode'])

            if !vals['back_enabled']
              vals['back_mode'] = 'none'
              vals['back_edge_offset'] = 9.0
            elsif vals['back_mode'] == 'phu'
              vals['back_edge_offset'] = 0.0
            else
              vals['back_mode'] = 'lot'
              vals['back_edge_offset'] = 9.0
            end

            # Từ 1.3.2: Hậu dùng đúng độ dày tấm đáy.
            vals['back_t'] = vals['bottom_t'].to_f

            model = Sketchup.active_model
            vals.each do |k,v|
              model.set_attribute(DICT, k, v.is_a?(Numeric) ? v.to_f : (v ? 1 : 0))
            end
            model.set_attribute(DICT, 'back_mode', vals['back_mode'])
            model.set_attribute(DICT, 'back_enabled', vals['back_enabled'] ? 1 : 0)
            model.set_attribute(DICT, 'back_t', vals['back_t'])

            @dialog.close
            tool ? tool.apply_settings(defaults) : model.select_tool(TwoPointTool.new(defaults))
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
          ['rail_gap','Ray mỗi bên'],
          ['gap_top','Hở trên'],
          ['gap_bottom','Hở dưới'],
          ['gap_front','Hở trước'],
          ['depth_reserve','Chừa phía sau'],
          ['wall_t','Độ dày 4 thành'],
          ['bottom_t','Độ dày tấm đáy'],
          ['back_bottom_offset','Offset hậu từ đáy']
        ].map do |k,l|
          "<label>#{l}</label><input id='#{k}' value='#{esc.call(d[k])}' inputmode='decimal' style='width:120px;padding:8px;box-sizing:border-box'>"
        end.join

        checked = d['back_enabled'] ? 'checked' : ''
        lot_checked = d['back_mode'] == 'lot' ? 'checked' : ''
        phu_checked = d['back_mode'] == 'phu' ? 'checked' : ''

        "<html><head><meta charset='utf-8'><style>" \
        "body{font:14px Arial;background:#17191d;color:#eee;padding:18px;margin:0}" \
        "h2{color:#ff7a00;margin-top:0}" \
        ".row{display:flex;align-items:center;justify-content:space-between;padding:9px 0;border-bottom:1px solid #3b3d42}" \
        ".grid{display:grid;grid-template-columns:1fr 130px;gap:8px;margin-top:12px;align-items:center}" \
        ".mode{margin-top:14px;padding:12px;border:1px solid #555;border-radius:7px}" \
        ".mode label{display:block;padding:7px 0;cursor:pointer}" \
        ".note{color:#aaa;font-size:12px;line-height:1.5}" \
        "button{width:100%;padding:12px;margin-top:14px;background:#ff7a00;color:#fff;border:0;border-radius:6px;font-weight:bold;cursor:pointer}" \
        "</style></head><body>" \
        "<h2>TT - NGĂN KÉO AUTO</h2>" \
        "<b style='color:#ff7a00'>TAB = CÀI ĐẶT</b>" \
        "<p>Click 2 điểm chéo trên cùng mặt để tạo ngăn kéo. Preview 3D dùng đúng kích thước khi tạo thật.</p>" \
        "<div class='row'><b>Hậu</b><label><input id='back_enabled' type='checkbox' #{checked} style='width:20px;height:20px;vertical-align:middle'> BẬT / TẮT</label></div>" \
        "<div class='mode'><b>CHẾ ĐỘ HẬU</b>" \
        "<label><input type='radio' name='back_mode' value='lot' #{lot_checked}> <b>HẬU LỌT</b> — lọt trong khung, offset mép ngoài 9 mm</label>" \
        "<label><input type='radio' name='back_mode' value='phu' #{phu_checked}> <b>HẬU PHỦ</b> — phủ ngoài thành sau, offset mép ngoài 0 mm</label>" \
        "<div class='note'>Độ dày Hậu tự động = Độ dày tấm đáy. Không còn mục nhập riêng “Độ dày tấm hậu”.</div></div>" \
        "<div class='grid'>#{fields}</div>" \
        "<div class='mode'><b>QUY TẮC ĐÁY HẬU</b><br>Offset hậu từ đáy được tính từ <b>mặt dưới của 4 thành</b>.<br>Mặc định: <b>15 mm</b>.</div>" \
        "<p class='note'>SHIFT khi đang vẽ: chuyển nhanh HẬU LỌT ↔ HẬU PHỦ; nếu Hậu đang tắt thì SHIFT sẽ bật HẬU LỌT.</p>" \
        "<button onclick='saveConfig()'>LƯU &amp; TIẾP TỤC AUTO</button>" \
        "<script>function saveConfig(){const keys=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t','back_bottom_offset'];let o={back_enabled:document.getElementById('back_enabled').checked,back_mode:(document.querySelector('input[name=back_mode]:checked')||{}).value||'lot'};keys.forEach(k=>o[k]=document.getElementById(k).value);sketchup.save_config_132(JSON.stringify(o));}</script>" \
        "</body></html>"
      end
      module_function :settings_html

      class TwoPointTool
        alias_method :initialize_before_132, :initialize unless method_defined?(:initialize_before_132)
        def initialize(cfg)
          initialize_before_132(cfg)
          mode = cfg['back_mode'].to_s
          enabled = cfg['back_enabled'] != false && cfg['back_enabled'].to_s != '0'
          @back_mode = if !enabled
                         :none
                       elsif mode == 'phu' || mode == 'phủ'
                         :phủ
                       else
                         :lọt
                       end
        end

        alias_method :apply_settings_before_132, :apply_settings unless method_defined?(:apply_settings_before_132)
        def apply_settings(cfg)
          apply_settings_before_132(cfg)
          mode = cfg['back_mode'].to_s
          enabled = cfg['back_enabled'] != false && cfg['back_enabled'].to_s != '0'
          @back_mode = if !enabled
                         :none
                       elsif mode == 'phu' || mode == 'phủ'
                         :phủ
                       else
                         :lọt
                       end
          status("ĐÃ LƯU → HẬU #{back_mode_name} | CLICK ĐIỂM 1")
        end

        alias_method :onKeyDown_before_132, :onKeyDown unless method_defined?(:onKeyDown_before_132)
        def onKeyDown(key, repeat, *args)
          if key == SHIFT_KEY && !repeat
            @back_mode = case @back_mode
                         when :none then :lọt
                         when :lọt then :phủ
                         else :lọt
                         end
            model = Sketchup.active_model
            if @back_mode == :none
              model.set_attribute(DICT, 'back_enabled', 0)
            else
              model.set_attribute(DICT, 'back_enabled', 1)
              model.set_attribute(DICT, 'back_mode', @back_mode == :phủ ? 'phu' : 'lot')
              model.set_attribute(DICT, 'back_edge_offset', @back_mode == :phủ ? 0.0 : 9.0)
              model.set_attribute(DICT, 'back_t', model.get_attribute(DICT, 'bottom_t', 9.0).to_f)
            end
            status("HẬU → #{back_mode_name} | SHIFT")
            return true
          end
          onKeyDown_before_132(key, repeat, *args)
        end
      end

      # Fix chiều sâu: bỏ qua lớp thành đầu tiên trước khi lấy mặt giới hạn khoang.
      class TwoPointTool
        alias_method :depth_from_region_before_132, :depth_from_region unless method_defined?(:depth_from_region_before_132)
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
            start = hp + dir.clone.tap { |v| v.length = 0.5.mm }
            next if traveled <= wall + 2.0
            return traveled
          end
          0.0
        rescue
          0.0
        end
      end

      # Fix: nếu hai điểm cùng X thì lấy bề rộng thật của Face.
      class TwoPointTool
        alias_method :normalized_region_before_132, :normalized_region unless method_defined?(:normalized_region_before_132)
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
          normalized_region_before_132(a,b)
        end
      end
    end
  end
end
