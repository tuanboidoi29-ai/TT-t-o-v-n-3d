# TT - NGAN KEO AUTO - CAI DAT HAU
# Quy tac:
# - Tat Hau: khong tao tam Hau rieng.
# - Offset mep ngoai 9 mm: HAU LOT.
# - Offset mep ngoai 0 mm: HAU PHU.
# - Offset tu day 15 mm: tinh tu MAT DUOI cua 4 thanh.
# - Khong con truong Do day tam Hau rieng; Hau dung cung do day voi Tam day.
module TranTuan
  module TaoVan
    module Drawer
      module_function

      class << self
        alias_method :tt_cfg_defaults_original, :defaults unless method_defined?(:tt_cfg_defaults_original)
        alias_method :tt_cfg_show_settings_original, :show_settings unless method_defined?(:tt_cfg_show_settings_original)
      end

      def defaults
        d=tt_cfg_defaults_original
        m=Sketchup.active_model
        d['back_enabled']=m.get_attribute(DICT,'back_enabled',1).to_i != 0
        d['back_edge_offset']=m.get_attribute(DICT,'back_edge_offset',9.0).to_f
        d['back_bottom_offset']=m.get_attribute(DICT,'back_bottom_offset',15.0).to_f
        d['back_t']=m.get_attribute(DICT,'bottom_t',9.0).to_f
        d
      end
      module_function :defaults

      def show_settings(tool=nil)
        d=defaults
        @dialog ||= UI::HtmlDialog.new(dialog_title:'TT - CÀI ĐẶT NGĂN KÉO AUTO',preferences_key:'TT_Drawer_Auto_Final_130',scrollable:true,resizable:true,width:450,height:740,style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_html(settings_html(d))
        @dialog.add_action_callback('save_config') do |_c,json|
          begin
            data=JSON.parse(json)
            vals={}
            %w[rail_gap gap_top gap_bottom gap_front depth_reserve wall_t bottom_t back_edge_offset back_bottom_offset].each{|k|vals[k]=parse_mm(data[k])}
            vals['back_enabled']=!!data['back_enabled']
            nums=%w[rail_gap gap_top gap_bottom gap_front depth_reserve wall_t bottom_t back_edge_offset back_bottom_offset]
            raise 'Thông số phải là số mm không âm.' if nums.any?{|k|!vals[k].is_a?(Numeric)||!vals[k].finite?||vals[k]<0}
            raise 'Độ dày 4 thành phải lớn hơn 0.' if vals['wall_t']<=0
            raise 'Độ dày tấm đáy phải lớn hơn 0.' if vals['bottom_t']<=0
            vals['back_edge_offset']=9.0 if (vals['back_edge_offset']-9.0).abs<0.001
            vals['back_edge_offset']=0.0 if vals['back_edge_offset'].abs<0.001
            vals['back_bottom_offset']=15.0 if (vals['back_bottom_offset']-15.0).abs<0.001
            # Hậu dùng cùng độ dày với tấm đáy.
            vals['back_t']=vals['bottom_t'].to_f
            model=Sketchup.active_model
            vals.each{|k,v|model.set_attribute(DICT,k,v.is_a?(Numeric) ? v.to_f : (v ? 1 : 0))}
            @dialog.close
            tool ? tool.apply_settings(vals) : model.select_tool(TwoPointTool.new(vals))
          rescue=>e
            UI.messagebox("Thông số không hợp lệ:\n#{e.message}")
          end
        end
        @dialog.show
      end
      module_function :show_settings

      def settings_html(d)
        esc=->(v){v.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;')}
        fields=[
          ['rail_gap','Ray mỗi bên'],['gap_top','Hở trên'],['gap_bottom','Hở dưới'],['gap_front','Hở trước'],['depth_reserve','Chừa phía sau'],
          ['wall_t','Độ dày 4 thành'],['bottom_t','Độ dày tấm đáy'],['back_edge_offset','Offset hậu từ mép ngoài'],['back_bottom_offset','Offset hậu từ đáy']
        ].map{|k,l|"<label>#{l}</label><input id='#{k}' value='#{esc.call(d[k])}' style='width:110px;padding:7px'>"}.join
        checked=d['back_enabled'] ? 'checked' : ''
        "<html><head><meta charset='utf-8'></head><body style='font:14px Arial;background:#17191d;color:#eee;padding:18px'>" \
        "<h2 style='color:#ff7a00'>TT - NGĂN KÉO AUTO</h2>" \
        "<b style='color:#ff7a00'>TAB = CÀI ĐẶT | CLICK 2 ĐIỂM TRÊN CÙNG MẶT</b>" \
        "<p>4 thành mặc định <b>17,5 mm</b>. Tấm đáy dùng độ dày riêng; <b>tấm hậu dùng cùng độ dày tấm đáy</b>.</p>" \
        "<div style='display:flex;align-items:center;justify-content:space-between;padding:10px 0;border-bottom:1px solid #444'><b>Hậu</b><label style='display:flex;align-items:center;gap:8px'><input id='back_enabled' type='checkbox' #{checked} style='width:20px;height:20px'> BẬT / TẮT</label></div>" \
        "<div style='display:grid;grid-template-columns:1fr 125px;gap:8px;margin-top:12px'>#{fields}</div>" \
        "<div style='margin-top:14px;padding:10px;border:1px solid #555;border-radius:6px'><b>QUY TẮC HẬU</b><br>Tắt Hậu → không tạo phần hậu.<br>Offset mép ngoài = <b>9 mm</b> → HẬU LỌT.<br>Offset mép ngoài = <b>0 mm</b> → HẬU PHỦ.<br>Offset từ đáy = <b>15 mm</b> → tính từ <b>mặt dưới của 4 thành</b>.<br>Độ dày hậu = <b>độ dày tấm đáy</b>.</div>" \
        "<p style='color:#aaa'>SHIFT chuyển nhanh HẬU LỌT ↔ HẬU PHỦ. Muốn tắt Hậu dùng nút BẬT/TẮT ở trên.</p>" \
        "<button onclick='saveConfig()' style='width:100%;padding:12px;background:#ff7a00;color:white;border:0;border-radius:6px;font-weight:bold'>LƯU & TIẾP TỤC AUTO</button>" \
        "<script>function saveConfig(){const a=['rail_gap','gap_top','gap_bottom','gap_front','depth_reserve','wall_t','bottom_t','back_edge_offset','back_bottom_offset'];let o={back_enabled:document.getElementById('back_enabled').checked};a.forEach(k=>o[k]=document.getElementById(k).value);sketchup.save_config(JSON.stringify(o));}</script>" \
        "</body></html>"
      end
      module_function :settings_html

      class TwoPointTool
        alias_method :tt_cfg_initialize_original, :initialize unless method_defined?(:tt_cfg_initialize_original)
        def initialize(cfg)
          tt_cfg_initialize_original(cfg)
          enabled=!(cfg['back_enabled']==false || cfg['back_enabled'].to_s=='0')
          @back_mode=if !enabled
            :none
          elsif cfg['back_edge_offset'].to_f.abs<0.001
            :phủ
          else
            :lọt
          end
          @cfg['back_t']=@cfg['bottom_t'].to_f
        end

        alias_method :tt_cfg_apply_original, :apply_settings unless method_defined?(:tt_cfg_apply_original)
        def apply_settings(cfg)
          tt_cfg_apply_original(cfg)
          @cfg['back_t']=@cfg['bottom_t'].to_f
          enabled=!(cfg['back_enabled']==false || cfg['back_enabled'].to_s=='0')
          @back_mode=if !enabled
            :none
          elsif cfg['back_edge_offset'].to_f.abs<0.001
            :phủ
          else
            :lọt
          end
          status("ĐÃ LƯU → HẬU #{back_mode_name} | CLICK ĐIỂM 1")
        end

        alias_method :tt_cfg_key_original, :onKeyDown unless method_defined?(:tt_cfg_key_original)
        def onKeyDown(key,repeat,*args)
          if key==SHIFT_KEY && !repeat
            if @back_mode==:none
              @back_mode=Drawer.defaults['back_edge_offset'].to_f.abs<0.001 ? :phủ : :lọt
            else
              @back_mode=(@back_mode==:lọt ? :phủ : :lọt)
            end
            Sketchup.active_model.set_attribute(DICT,'back_enabled',1)
            status("HẬU → #{back_mode_name} | SHIFT")
            return true
          end
          tt_cfg_key_original(key,repeat,*args)
        end
      end

      # Giữ 2 fix hình học 1.2.9.
      class TwoPointTool
        alias_method :tt_cfg_depth_original, :depth_from_region unless method_defined?(:tt_cfg_depth_original)
        def depth_from_region(a,b)
          xmin,xmax,zmin,zmax=normalized_region(a,b)
          o=Geom::Point3d.new((xmin+xmax)*0.5,0,(zmin+zmax)*0.5).transform(@frame)
          dir=unit(@frame.yaxis); model=Sketchup.active_model; start=o+dir.clone.tap{|v|v.length=0.5.mm}; traveled=0.0; wall=[@cfg['wall_t'].to_f,0.0].max
          12.times do
            hit=model.raytest([start,dir]); break unless hit&&hit[0].is_a?(Geom::Point3d)
            hp=hit[0]; seg=start.distance(hp).to_mm; break if seg<=0.01; traveled+=seg; start=hp+dir.clone.tap{|v|v.length=0.5.mm}; next if traveled<=wall+2.0; return traveled
          end
          0.0
        rescue
          0.0
        end
      end

      class TwoPointTool
        alias_method :tt_cfg_region_original, :normalized_region unless method_defined?(:tt_cfg_region_original)
        def normalized_region(a,b)
          qa=frame_point(locked_point(a)); qb=frame_point(locked_point(b)); xmin=[qa.x,qb.x].min; xmax=[qa.x,qb.x].max; zmin=[qa.z,qb.z].min; zmax=[qa.z,qb.z].max
          if (xmax-xmin).abs<0.1.mm && @face
            tr=@path ? @path.transformation : Geom::Transformation.new; pts=@face.vertices.map{|v|v.position.transform(tr).transform(@frame.inverse)}; fx=pts.map(&:x); xmin=fx.min; xmax=fx.max
          end
          [xmin,xmax,zmin,zmax]
        rescue
          tt_cfg_region_original(a,b)
        end
      end
    end
  end
end
