# encoding: UTF-8
require 'cgi'
# Geometry is generated in mm once, shared by preview and creation.
module TranTuanNoiThat
  module CabinetDoor
    extend self
    remove_const(:FIELDS) if const_defined?(:FIELDS, false)
    FIELDS = [
      ['style','Kiểu cánh','Cánh phẳng',['Cánh phẳng','Cánh khung','Cánh kính','Cánh soi huỳnh']],
      ['fit','Lắp đặt','Phủ ngoài',['Phủ ngoài','Lọt lòng']],
      ['split_scope','Phạm vi chia bằng chuột','Ô đang trỏ',['Ô đang trỏ','Toàn vùng']],
      ['width','Rộng vùng chọn (0 = theo chuột)',0], ['height','Cao vùng chọn (0 = theo chuột)',0],
      ['cols','Số cánh ngang',2], ['rows','Số hàng cánh',1],
      ['thickness','Dày cánh / khung',17.5],
      ['left','Khe trái',2], ['right','Khe phải',2], ['top','Khe trên',2], ['bottom','Khe dưới',2],
      ['gap_x','Khe giữa cánh ngang',2], ['gap_y','Khe giữa hàng',2],
      ['over_left','Phủ trái (chỉ Phủ ngoài)',0], ['over_right','Phủ phải',0],
      ['over_top','Phủ trên',0], ['over_bottom','Phủ dưới',0],
      ['offset','Dịch ra trước (+) / vào trong (-)',0],
      ['stile_left','Rộng khung trái',60], ['stile_right','Rộng khung phải',60],
      ['rail_top','Rộng khung trên',60], ['rail_bottom','Rộng khung dưới',60],
      ['panels','Số ô lòng theo chiều cao',1], ['rail_mid','Rộng đố giữa',40],
      ['panel_thick','Dày tấm lòng cánh khung',9], ['glass_thick','Dày kính',5],
      ['recess','Lùi mặt lòng / kính so với mặt khung',4],
      ['bevel','Rộng vát soi huỳnh',12], ['depth','Sâu soi huỳnh',6],
      ['glass_alpha','Độ đậm kính (%)',35]
    ].freeze

    def defaults
      FIELDS.to_h { |f| [f[0], f[2]] }
    end

    def validate(raw)
      s = defaults.merge(raw)
      FIELDS.each do |key, label, default, choices|
        if choices
          raise "#{label} không hợp lệ." unless choices.include?(s[key])
        else
          s[key] = Float(s[key].to_s.tr(',', '.'))
          raise "#{label} phải là số hữu hạn." unless s[key].finite?
          raise "#{label} không được âm." if key != 'offset' && s[key] < 0
          raise "#{label} vượt quá 100.000 mm." if s[key].abs > 100_000
        end
      end
      %w[cols rows panels].each do |k|
        raise 'Số cánh / hàng / ô lòng phải là số nguyên từ 1 đến 20.' unless s[k] == s[k].to_i && s[k].between?(1,20)
        s[k] = s[k].to_i
      end
      raise 'Tối đa 60 cánh mỗi lần tạo.' if s['cols'] * s['rows'] > 60
      raise 'Tối đa 120 ô lòng mỗi lần tạo để giữ thao tác nhẹ.' if s['style'] != 'Cánh phẳng' && s['cols']*s['rows']*s['panels']>120
      raise 'Dày cánh phải từ 1 mm.' if s['thickness'] < 1
      raise 'Độ đậm kính phải từ 1 đến 100%.' unless s['glass_alpha'].between?(1,100)
      unless s['style'] == 'Cánh phẳng'
        %w[stile_left stile_right rail_top rail_bottom rail_mid].each do |k|
          raise 'Bề rộng khung / đố phải từ 1 mm.' if s[k] < 1
        end
        if s['style'] == 'Cánh soi huỳnh'
          raise 'Rộng vát và sâu soi phải từ 0,5 mm; đáy còn ít nhất 1 mm.' unless s['bevel'] >= 0.5 && s['depth'] >= 0.5 && s['depth'] <= s['thickness']-1
        else
          t = s[s['style'] == 'Cánh kính' ? 'glass_thick' : 'panel_thick']
          raise 'Lòng / kính phải dày từ 1 mm và nằm trong chiều dày khung.' unless t >= 1 && t + s['recess'] <= s['thickness']
        end
      end
      s
    rescue ArgumentError, TypeError
      raise 'Thông số không hợp lệ. Nhập số mm, không kèm đơn vị.'
    end

    def built_in_presets
      [
        ['flat','Cánh phẳng','Cánh phẳng',{}],
        ['frame','Khung lòng phẳng','Cánh khung',{}],
        ['glass','Khung kính','Cánh kính',{}],
        ['glass2','Kính 2 ô','Cánh kính',{'panels'=>2}],
        ['panel1','Huỳnh 1 ô','Cánh soi huỳnh',{}],
        ['panel2','Huỳnh 2 ô','Cánh soi huỳnh',{'panels'=>2}],
        ['panel3','Huỳnh 3 ô','Cánh soi huỳnh',{'panels'=>3}],
        ['panelwide','Huỳnh khung rộng','Cánh soi huỳnh',{'stile_left'=>85,'stile_right'=>85,'rail_top'=>85,'rail_bottom'=>85,'bevel'=>20}]
      ].map do |id,name,style,extra|
        {'id'=>'builtin_'+id,'name'=>name,'settings'=>validate(defaults.merge('cols'=>1,'style'=>style).merge(extra))}
      end
    end

    def custom_presets
      raw=TranTuanNoiThat.setting('cabinet_door_presets_v1','[]')
      data=JSON.parse(raw)
      raise 'Dữ liệu mẫu đã lưu không hợp lệ; giữ nguyên dữ liệu để kiểm tra.' unless data.is_a?(Array) && data.all? { |p| p.is_a?(Hash) && p['id'].is_a?(String) && p['name'].is_a?(String) && p['settings'].is_a?(Hash) }
      data
    rescue JSON::ParserError
      raise 'Không đọc được mẫu đã lưu; dữ liệu gốc vẫn được giữ nguyên.'
    end

    def save_preset(name,options)
      name=name.to_s.strip
      raise 'Nhập tên mẫu từ 1 đến 80 ký tự.' if name.empty? || name.length>80
      options=validate(options)
      records=custom_presets
      record={'id'=>"custom_#{Time.now.to_i}_#{rand(1_000_000_000)}",'name'=>name,'settings'=>options}
      records << record
      TranTuanNoiThat.save_setting('cabinet_door_presets_v1',records.to_json)
      record
    end

    def face_color(part,face)
      return [105,185,215,95] if part[:glass]
      a,b,c=face[0,3]
      ab=3.times.map { |i| b[i]-a[i] }; ac=3.times.map { |i| c[i]-a[i] }
      n=[ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]]
      length=Math.sqrt(n.sum { |v| v*v }); nz=length>0 ? n[2]/length : 1
      highest=part[:faces].flatten(1).map { |p| p[2] }.max
      recessed=nz>0.99 && face.all? { |p| p[2]<highest-0.01 }
      return [183,130,78,255] if recessed
      if nz>0.99
        [235,193,140,255]
      elsif nz>0.01
        shade=0.76+0.16*(n[0]-n[1])/length
        [235,193,140].map { |v| (v*shade).round.clamp(0,255) }+[255]
      else
        [145,99,58,255]
      end
    end

    def preset_svg(options)
      # Real preset mesh, projected obliquely: frame, bevel and recessed floor.
      options=validate(options).merge('cols'=>1,'rows'=>1,'width'=>0,'height'=>0,
        'left'=>0,'right'=>0,'top'=>0,'bottom'=>0,'over_left'=>0,'over_right'=>0,'over_top'=>0,'over_bottom'=>0)
      w=[500.0,options['stile_left']+options['stile_right']+options['bevel']*2+120].max
      h=[760.0,options['rail_top']+options['rail_bottom']+(options['panels']-1)*options['rail_mid']+options['panels']*(options['bevel']*2+90)].max
      polys=layout(w,h,options).first[:parts].flat_map do |part|
        part[:faces].map { |f| [f,face_color(part,f)] }
      end
      project=proc { |p| [p[0]+p[2]*0.65,-p[1]+p[0]*0.12-p[2]*0.45] }
      points=polys.flat_map { |f,_| f.map(&project) }
      xmin,xmax=points.map(&:first).minmax; ymin,ymax=points.map(&:last).minmax
      body=polys.sort_by { |f,_| f.sum { |p| p[2] }/f.length }.map do |f,color|
        coords=f.map { |point| project.call(point).map { |v| v.round(2) }.join(',') }.join(' ')
        "<polygon points='#{coords}' fill='rgb(#{color[0,3].join(',')})' fill-opacity='#{color[3]/255.0}' stroke='#634b35' stroke-width='1.6'/>"
      end.join
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='#{xmin-16} #{ymin-16} #{xmax-xmin+32} #{ymax-ymin+32}' role='img' aria-label='Mẫu cánh 3D'>#{body}</svg>"
    end

    def gallery_html(records,warning='')
      cards=records.map do |record|
        begin
          svg=preset_svg(record['settings'])
          "<button class='card' data-id='#{CGI.escapeHTML(record['id'])}'><div class='art'>#{svg}</div><strong>#{CGI.escapeHTML(record['name'])}</strong><span>Chọn & sử dụng</span></button>"
        rescue StandardError
          "<div class='card'>#{CGI.escapeHTML(record['name'])}<p>Mẫu có thông số không hợp lệ.</p></div>"
        end
      end.join
      <<~HTML
        <!doctype html><html lang="vi"><meta charset="utf-8"><style>
        body{font:14px Arial;margin:24px;background:#f3f5f8;color:#24394e}h2{margin:0 0 8px}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.card{font:inherit;background:white;border:1px solid #d3dde7;border-radius:10px;padding:12px;cursor:pointer;color:inherit;text-align:left}.card:hover,.card:focus{border-color:#1673cb;background:#edf6ff}.art{height:175px;display:flex;justify-content:center;margin-bottom:12px}.art svg{height:100%;max-width:100%}strong,span{display:block}span{font-size:12px;margin-top:6px;color:#2670a6}#error{color:#b32626}p{line-height:1.5}@media(max-width:600px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
        </style><h2>MẪU CÁNH TỦ</h2><p>Chọn mẫu để vẽ ngay. <b>TAB</b> mở thông số và lưu mẫu riêng. <b>SHIFT</b> đổi hướng chia; <b>ENTER</b> tạo cánh.</p><p id="error">#{CGI.escapeHTML(warning)}</p><div class="grid">#{cards}</div>
        <script>document.querySelectorAll('button[data-id]').forEach(b=>b.onclick=()=>sketchup.use_preset(b.dataset.id));document.addEventListener('keydown',e=>{if(e.key==='Tab'){e.preventDefault();sketchup.customize();}});function error(s){document.getElementById('error').textContent=s;}</script></html>
      HTML
    end

    def show(tool=nil)
      tool ? show_settings(tool) : show_gallery
    end

    def show_gallery
      @gallery.close if @gallery && @gallery.visible?
      warning=''
      records=built_in_presets
      begin; records+=custom_presets; rescue StandardError=>e; warning=e.message; end
      @gallery=UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN – MẪU CÁNH TỦ',preferences_key:'TT_CabinetDoorGallery',scrollable:true,resizable:true,width:840,height:660,style:UI::HtmlDialog::STYLE_DIALOG)
      @gallery.set_html(gallery_html(records,warning))
      @gallery.add_action_callback('use_preset') do |_ctx,id|
        begin
          record=records.find { |p| p['id']==id }
          raise 'Không tìm thấy mẫu.' unless record
          options=validate(record['settings'])
          TranTuanNoiThat.save_setting('cabinet_door_options',options.to_json)
          Sketchup.active_model.select_tool(Tool.new(options)); @gallery.close
        rescue StandardError=>e
          @gallery.execute_script("error(#{e.message.to_json})")
        end
      end
      @gallery.add_action_callback('customize') { |_ctx| @gallery.close; show_settings }
      @gallery.show
    end

    def show_settings(tool = nil)
      @dialog.close if @dialog && @dialog.visible?
      @dialog = UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN – VẼ CÁNH TỦ', preferences_key:'TT_CabinetDoor', scrollable:true, resizable:true, width:680, height:760, style:UI::HtmlDialog::STYLE_DIALOG)
      values = tool ? tool.settings : (JSON.parse(TranTuanNoiThat.setting('cabinet_door_options','{}')) rescue {})
      values = defaults.merge(values)
      inputs = FIELDS.map do |k,label,d,choices|
        control = if choices
          "<select id='#{k}'>#{choices.map { |c| "<option#{values[k] == c ? ' selected' : ''}>#{c}</option>" }.join}</select>"
        else
          "<input id='#{k}' type='number' step='any' value='#{Float(values[k]) rescue d}'>"
        end
        heading={'style'=>'Mẫu cánh & kích thước','left'=>'Khe hở','over_left'=>'Phủ cạnh & vị trí','stile_left'=>'Khung & đố','panel_thick'=>'Lòng cánh & kính','bevel'=>'Soi huỳnh'}[k]
        "#{heading ? "<h3>#{heading}</h3>" : ''}<label>#{label}#{control}</label>"
      end.join
      @dialog.set_html(<<~HTML)
        <!doctype html><html lang="vi"><meta charset="utf-8"><style>
        body{font:14px Arial;margin:22px;background:#f4f6fa;color:#192d42}h2{margin:0 0 10px}p{line-height:1.5}
        h3{grid-column:1/-1;margin:12px 0 0;color:#146dcc}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}label{display:block}input,select{display:block;box-sizing:border-box;width:100%;padding:9px;margin-top:5px;border:1px solid #b6c6d6;border-radius:5px;background:white}
        footer{position:sticky;bottom:0;background:#f4f6fa;padding:12px 0}button{background:#146dcc;color:white;padding:12px 22px;border:0;border-radius:5px;cursor:pointer}#error{color:#b32222;margin:8px 0}
        </style><h2>VẼ CÁNH TỦ</h2><p>Đơn vị: mm (trừ số lượng và %). Chọn 2 góc của vùng lắp cánh; SHIFT đổi chia ngang/dọc; gõ /3, /4… chia đều ô đang trỏ; click giữ đường chia; ENTER tạo. TAB mở thông số, Áp dụng cập nhật preview; F đảo hướng ra trước. Rộng/cao = 0 để lấy theo chuột.</p>
        <p>Áp dụng sẽ cập nhật preview. Đổi kích thước vùng, số cánh, khe hoặc độ phủ sẽ đặt lại các đường chia bằng chuột; đổi mẫu, khung, độ dày giữ các ô đã chia.</p><div class="grid">#{inputs}</div><footer><div id="error"></div><label>Tên mẫu riêng<input id="preset_name" placeholder="Ví dụ: Huỳnh tủ áo 2 ô"></label><button onclick="savePreset()">Lưu thành mẫu mới</button> <button onclick="apply()">Áp dụng & xem trước</button></footer>
        <script>const keys=#{FIELDS.map(&:first).to_json};function values(){let s={};keys.forEach(k=>s[k]=document.getElementById(k).value);return s;}function apply(){sketchup.apply(JSON.stringify(values()));}function savePreset(){sketchup.save_preset(document.getElementById("preset_name").value,JSON.stringify(values()));}function error(s){document.getElementById('error').textContent=s;}</script></html>
      HTML
      @dialog.add_action_callback('save_preset') do |_ctx,name,json|
        begin
          save_preset(name,JSON.parse(json))
          @dialog.execute_script("error(#{'Đã lưu mẫu mới. Lần mở công cụ sau, chọn mẫu trong danh sách.'.to_json})")
        rescue StandardError=>e
          @dialog.execute_script("error(#{e.message.to_json})")
        end
      end
      @dialog.add_action_callback('apply') do |_ctx,json|
        begin
          s = validate(JSON.parse(json))
          TranTuanNoiThat.save_setting('cabinet_door_options',s.to_json)
          if tool && tool.active?
            tool.configure(s)
          else
            Sketchup.active_model.select_tool(Tool.new(s))
          end
          @dialog.close
        rescue StandardError => e
          @dialog.execute_script("error(#{e.message.to_json})")
        end
      end
      @dialog.show
    end

    def ring(x,y,w,h,z)
      [[x,y,z],[x+w,y,z],[x+w,y+h,z],[x,y+h,z]]
    end

    def bridge(a,b)
      4.times.map { |i| [a[i],a[(i+1)%4],b[(i+1)%4],b[i]] }
    end

    def prism(name,x,y,w,h,z,t,glass=false)
      a=ring(x,y,w,h,z); b=ring(x,y,w,h,z+t)
      {name:name, glass:glass, faces:[a.reverse,b]+bridge(a,b)}
    end

    # Returns closed solids, including actual bevel faces for routed panels.
    def layout(width,height,s)
      s=validate(s)
      raise 'Vùng lắp cánh phải rộng và cao từ 1 mm.' unless width >= 1 && height >= 1
      over=s['fit']=='Phủ ngoài'
      x=s['left']-(over ? s['over_left'] : 0)
      y=s['bottom']-(over ? s['over_bottom'] : 0)
      total_w=width-x-s['right']+(over ? s['over_right'] : 0)
      total_h=height-y-s['top']+(over ? s['over_top'] : 0)
      w=(total_w-(s['cols']-1)*s['gap_x'])/s['cols']
      h=(total_h-(s['rows']-1)*s['gap_y'])/s['rows']
      raise 'Khe hở / số cánh quá lớn: mỗi cánh phải rộng, cao từ 10 mm.' unless w >= 10 && h >= 10
      t=s['thickness']; z=s['offset']-(over ? 0 : t)
      Array.new(s['rows']) do |r|
        Array.new(s['cols']) do |c|
          xx=x+c*(w+s['gap_x']); yy=y+r*(h+s['gap_y'])
          parts=[]
          if s['style']=='Cánh phẳng'
            parts << prism('Tấm cánh',xx,yy,w,h,z,t)
          else
            l=s['stile_left']; rr=s['stile_right']; top=s['rail_top']; bot=s['rail_bottom']
            iw=w-l-rr; ih=(h-top-bot-(s['panels']-1)*s['rail_mid'])/s['panels']
            raise 'Khung / đố quá rộng: ô lòng phải rộng và cao từ 5 mm.' unless iw>=5 && ih>=5
            if s['style']=='Cánh soi huỳnh'
              bevel=s['bevel']; depth=s['depth']
              raise 'Vát soi quá rộng so với ô lòng.' unless iw>2*bevel+1 && ih>2*bevel+1
              # One manifold slab: outer sides/back, front frame strips, bevels and recessed floors.
              a=ring(xx,yy,w,h,z); b=ring(xx,yy,w,h,z+t)
              faces=[a.reverse]+bridge(a,b)
              faces << ring(xx,yy,l,h,z+t) << ring(xx+w-rr,yy,rr,h,z+t)
              faces << ring(xx+l,yy,iw,bot,z+t) << ring(xx+l,yy+h-top,iw,top,z+t)
              s['panels'].times do |i|
                py=yy+bot+i*(ih+s['rail_mid'])
                outer=ring(xx+l,py,iw,ih,z+t)
                inner=ring(xx+l+bevel,py+bevel,iw-2*bevel,ih-2*bevel,z+t-depth)
                faces.concat(bridge(outer,inner)); faces << inner
                faces << ring(xx+l,py+ih,iw,s['rail_mid'],z+t) if i<s['panels']-1
              end
              parts << {name:'Cánh soi huỳnh',glass:false,faces:faces}
            else
              parts << prism('Khung trái',xx,yy,l,h,z,t) << prism('Khung phải',xx+w-rr,yy,rr,h,z,t)
              parts << prism('Khung dưới',xx+l,yy,iw,bot,z,t) << prism('Khung trên',xx+l,yy+h-top,iw,top,z,t)
              glass=s['style']=='Cánh kính'; pt=s[glass ? 'glass_thick' : 'panel_thick']
              s['panels'].times do |i|
                py=yy+bot+i*(ih+s['rail_mid'])
                parts << prism("#{glass ? 'Kính' : 'Lòng cánh'} #{i+1}",xx+l,py,iw,ih,z+t-s['recess']-pt,pt,glass)
                parts << prism("Đố giữa #{i+1}",xx+l,py+ih,iw,s['rail_mid'],z,t) if i<s['panels']-1
              end
            end
          end
          {name:format('TT_CÁNH_%02d_%02d %s %.1fx%.1f',r+1,c+1,s['style'],w,h),parts:parts,width:w,height:h}
        end
      end.flatten
    end

    def cells_from_doors(doors)
      doors.map do |door|
        pts=door[:parts].flat_map { |p| p[:faces].flatten(1) }
        [pts.map { |p| p[0] }.min,pts.map { |p| p[1] }.min,door[:width],door[:height]]
      end
    end

    def layout_cells(cells,s)
      raise 'Tối đa 60 cánh mỗi lần tạo.' if cells.length>60
      raise 'Tối đa 120 ô lòng mỗi lần tạo.' if s['style']!='Cánh phẳng' && cells.length*s['panels']>120
      local=s.merge('cols'=>1,'rows'=>1,'width'=>0,'height'=>0,
        'left'=>0,'right'=>0,'top'=>0,'bottom'=>0,
        'over_left'=>0,'over_right'=>0,'over_top'=>0,'over_bottom'=>0)
      cells.each_with_index.map do |(x,y,w,h),i|
        door=layout(w,h,local).first
        door[:name]=format('TT_CÁNH_%02d %s %.1fx%.1f',i+1,s['style'],w,h)
        door[:parts].each do |part|
          part[:faces]=part[:faces].map { |face| face.map { |p| [p[0]+x,p[1]+y,p[2]] } }
        end
        door
      end
    end

    def split_cells(cells,point,axis,internal,s)
      # Hover only offers a split inside a leaf, never in a gap or outside.
      index=cells.index { |x,y,w,h| point[0]>x && point[0]<x+w && point[1]>y && point[1]<y+h }
      return [nil,[]] unless index
      target=cells[index]; start=target[axis]; extent=target[axis+2]
      cut=point[axis]
      middle=start+extent/2.0
      cut=middle if (cut-middle).abs <= [extent*0.03,10.0].min
      gap=s[axis==0 ? 'gap_x' : 'gap_y']
      changed=false; lines=[]
      result=cells.each_with_index.flat_map do |cell,i|
        low=cell[axis]; size=cell[axis+2]
        if (!internal || i==index) && cut>low && cut<low+size
          first=cell.dup; second=cell.dup
          first[axis+2]=cut-low-gap/2.0
          second[axis]=cut+gap/2.0; second[axis+2]=low+size-cut-gap/2.0
          # Reject the whole proposal rather than silently altering only some leaves.
          return [nil,[]] if first[axis+2]<10 || second[axis+2]<10
          x,y,w,h=cell
          lines << (axis==0 ? [[cut,y],[cut,y+h]] : [[x,cut],[x+w,cut]])
          changed=true
          [first,second]
        else
          [cell.dup]
        end
      end
      [changed ? result : nil,lines]
    end

    def equal_cells(cells,point,axis,count,internal,s)
      raise 'Nhập /2 đến /60 để chia đều.' unless count.is_a?(Integer) && count.between?(2,60)
      index=cells.index { |x,y,w,h| point && point[0]>x && point[0]<x+w && point[1]>y && point[1]<y+h }
      raise 'Hãy trỏ chuột vào ô cánh cần chia trước khi gõ /N.' unless index
      gap=s[axis==0 ? 'gap_x' : 'gap_y']; lines=[]
      result=cells.each_with_index.flat_map do |cell,i|
        next [cell.dup] if internal && i!=index
        start=cell[axis]; size=cell[axis+2]
        part=(size-(count-1)*gap)/count
        raise 'Số phần / khe quá lớn: mỗi cánh phải từ 10 mm.' if part<10
        Array.new(count) do |j|
          item=cell.dup; item[axis]=start+j*(part+gap); item[axis+2]=part
          if j<count-1
            cut=item[axis]+part+gap/2.0; x,y,w,h=cell
            lines << (axis==0 ? [[cut,y],[cut,y+h]] : [[x,cut],[x+w,cut]])
          end
          item
        end
      end
      raise 'Tối đa 60 cánh mỗi lần tạo.' if result.length>60
      [result,lines]
    end

    def edge_snap_points(edge,transformation)
      a=edge.start.position.transform(transformation)
      b=edge.end.position.transform(transformation)
      mid=Geom::Point3d.new((a.x+b.x)/2.0,(a.y+b.y)/2.0,(a.z+b.z)/2.0)
      [[a,'Đầu cạnh',0],[b,'Đầu cạnh',0],[mid,'Trung điểm cạnh',1]]
    end

    def nearest_snap(candidates,x,y,view,radius=14)
      ranked=candidates.filter_map do |item|
        point=item[0]
        next if view.camera.direction.dot(point-view.camera.eye)<=0
        screen=view.screen_coords(point)
        distance=Math.hypot(screen.x-x,screen.y-y)
        next if distance>radius
        [distance,item[2],item]
      end
      ranked.min_by { |distance,priority,_| [distance,priority] }&.last
    end

    class Tool
      attr_reader :settings
      def initialize(s)
        @settings=s; @ip=Sketchup::InputPoint.new; @ref=Sketchup::InputPoint.new
        @model=Sketchup.active_model; @path=@model.active_path
        @snap_probes=Array.new(9) { Sketchup::InputPoint.new }; reset
      end
      def activate; @active=true; status; end
      def active?; @active && Sketchup.active_model==@model; end
      def deactivate(view); @active=false; view.invalidate; end
      def resume(view); @active=true; status; view.invalidate; end
      def reset
        @snap_point=nil; @snap_label=nil; @snap_cell=nil; @stage=0; @equal_count=nil; @equal_anchor=nil; @vcb_typing=false; @split_axis=0; @internal=@settings['split_scope']!='Toàn vùng'; @cells=nil; @candidate=nil; @history=[]; @hover=nil; @split_lines=[]; @sign=1; @doors=nil; @origin=nil; @error=nil; @last=nil
        @u=X_AXIS; @v=Z_AXIS; @n=@u.cross(@v); @ip.clear; @ref.clear; status
      end
      def configure(s)
        old=@settings; had_cells=!!@cells
        region_keys=%w[width height cols rows left right top bottom over_left over_right over_top over_bottom fit gap_x gap_y]
        reset_grid=had_cells && region_keys.any? { |k| old[k]!=s[k] }
        @settings=s
        @internal=s['split_scope']!='Toàn vùng'
        if reset_grid
          @cells=nil; @history=[]; @hover=nil; @candidate=nil; @split_lines=[]; @equal_count=nil; @equal_anchor=nil; @vcb_typing=false
          rebuild if @origin && @last
          if @doors
            @cells=CabinetDoor.cells_from_doors(@doors); @stage=2
          else
            @stage=1
          end
        elsif @cells
          refresh_split
        elsif @origin && @last
          rebuild
        end
        @model.active_view.invalidate; status
      end
      def status
        direction=@split_axis==0 ? 'DỌC' : 'NGANG'
        mode=@internal ? 'TRONG Ô ĐANG TRỎ' : 'TOÀN VÙNG'
        Sketchup.status_text=@error || [
          'VẼ CÁNH: Chọn góc 1 | TAB thông số.',
          "Chọn góc 2, preview 3D | SHIFT chia #{direction} | ← XZ, → YZ, ↑ XY | F đảo hướng | TAB thông số.",
          "Chia #{direction} · #{mode} | SHIFT đổi hướng · TAB thông số | Click giữ đường chia · ENTER tạo · /N chia đều · Backspace lùi."
        ][@stage]
      end
      def onCancel(reason,view)
        @stage==0 ? @model.select_tool(nil) : reset
        view.invalidate
      end
      def axes_from_face
        f=@ip.face; return unless f
        tr=@ip.transformation
        vs=f.outer_loop.vertices.map { |v| v.position.transform(tr) }
        normal=nil
        (1...vs.length-1).each do |i|
          candidate=(vs[i]-vs[0]).cross(vs[i+1]-vs[0])
          if candidate.length>1e-8
            normal=candidate.normalize; break
          end
        end
        return unless normal
        # Choose vertical from model axes projected into the actual face plane.
        axis=normal.parallel?(Z_AXIS) ? Y_AXIS : Z_AXIS
        dot=axis.dot(normal)
        v=Geom::Vector3d.new(axis.x-normal.x*dot,axis.y-normal.y*dot,axis.z-normal.z*dot); v.normalize!
        @u=v.cross(normal).normalize; @v=v; @n=normal
      end
      def pick(x,y,view)
        @stage==0 ? @ip.pick(view,x,y) : @ip.pick(view,x,y,@ref)
        candidates=[]
        offsets=[[0,0],[-8,0],[8,0],[0,-8],[0,8],[-8,-8],[8,-8],[-8,8],[8,8]]
        offsets.each_with_index do |(dx,dy),i|
          probe=@snap_probes[i]
          @stage==0 ? probe.pick(view,x+dx,y+dy) : probe.pick(view,x+dx,y+dy,@ref)
          next unless probe.valid?
          edge=probe.edge
          if edge && edge.valid?
            CabinetDoor.edge_snap_points(edge,probe.transformation).each do |point,label,priority|
              candidates << [point,label,priority,probe,nil]
            end
          elsif probe.vertex
            candidates << [probe.position,'Đầu cạnh',0,probe,nil]
          end
        end
        # Preview cells do not exist in the model yet: provide their own snap points.
        if @stage==2 && @cells
          z=@settings['offset']+(@settings['fit']=='Phủ ngoài' ? @settings['thickness'] : 0)
          @cells.each_with_index do |(cx,cy,w,h),i|
            corners=[[cx,cy],[cx+w,cy],[cx+w,cy+h],[cx,cy+h]]
            corners.each_with_index do |point,j|
              candidates << [world([point[0],point[1],z]),'Góc ô cánh',0,nil,i]
              other=corners[(j+1)%4]
              mid=[(point[0]+other[0])/2.0,(point[1]+other[1])/2.0]
              candidates << [world([mid[0],mid[1],z]),'Trung điểm cạnh ô cánh',1,nil,i]
            end
          end
        end
        best=CabinetDoor.nearest_snap(candidates,x,y,view)
        @snap_point=best && best[0]; @snap_label=best && best[1]; @snap_cell=best && best[4]
        @ip.copy!(best[3]) if best && best[3]
        view.tooltip=@snap_point ? @snap_label : (@ip.valid? ? @ip.tooltip : '')
      end
      def onMouseMove(flags,x,y,view)
        if @stage==2
          pick(x,y,view)
          # Intersect the pointer ray with the displayed FRONT plane: no parallax
          # when the preview is offset or thickness is reversed.
          z=@settings['offset']+(@settings['fit']=='Phủ ngoài' ? @settings['thickness'] : 0)
          plane_origin=@base.offset(@n,(z*@sign).mm)
          point=Geom.intersect_line_plane(view.pickray(x,y),[plane_origin,@n])
          if @snap_point
            point=@snap_point
          elsif @ip.valid? && @ip.degrees_of_freedom<3
            point=@ip.position
          end
          if point
            d=point-@base; @hover=[d.dot(@u).to_mm,d.dot(@v).to_mm]
            # An edge midpoint belongs to this preview cell. Move only the
            # targeting coordinate inside; retain the exact cut coordinate.
            if @snap_cell && @cells[@snap_cell]
              cell=@cells[@snap_cell]; other=1-@split_axis
              @hover[other]=cell[other]+cell[other+2]/2.0
            end
          else
            @hover=nil
          end
          refresh_split; status; view.invalidate; return
        end
        pick(x,y,view)
        update_rectangle(x,y,view) if @stage==1
        view.invalidate
      end
      def update_rectangle(x,y,view)
        p=Geom.intersect_line_plane(view.pickray(x,y),[@origin,@n])
        p=@snap_point || (@ip.valid? && @ip.degrees_of_freedom<3 ? @ip.position : p)
        @last=p
        if p
          rebuild
        else
          @doors=nil; @error='Không bắt được mặt phẳng. Đổi góc nhìn hoặc khóa mặt phẳng.'
        end
        status
      end
      def rebuild
        d=@last-@origin; a=d.dot(@u).to_mm; b=d.dot(@v).to_mm
        a=(@settings['width'])*(a<0 ? -1 : 1) if @settings['width']>0
        b=(@settings['height'])*(b<0 ? -1 : 1) if @settings['height']>0
        @base=@origin.offset(@u,[a,0].min.mm).offset(@v,[b,0].min.mm)
        @rect_size=[a.abs,b.abs]
        settings=@settings
        if @split_axis==1
          settings=@settings.merge('cols'=>@settings['rows'],'rows'=>@settings['cols'])
        end
        @doors=CabinetDoor.layout(a.abs,b.abs,settings); @error=nil
        cache_world
      rescue StandardError=>e
        @doors=nil; @world=nil; @error=e.message
      end
      def world(p)
        @base.offset(@u,p[0].mm).offset(@v,p[1].mm).offset(@n,(p[2]*@sign).mm)
      end
      def onLButtonDown(flags,x,y,view)
        if @stage==0
          pick(x,y,view); return unless @ip.valid?
          @origin=@snap_point || @ip.position; @ref=Sketchup::InputPoint.new(@origin); axes_from_face; @stage=1
          @last=@origin.offset(@u,500.mm).offset(@v,760.mm); rebuild
        elsif @stage==1
          pick(x,y,view); update_rectangle(x,y,view)
          return UI.beep unless @doors
          @cells=CabinetDoor.cells_from_doors(@doors)
          @history=[]; @hover=nil; @candidate=nil; @split_lines=[]; @stage=2
        elsif @candidate
          @history << @cells.map(&:dup)
          @cells=@candidate; @candidate=nil; @hover=nil; @split_lines=[]; @equal_count=nil; @equal_anchor=nil; @vcb_typing=false
          @doors=CabinetDoor.layout_cells(@cells,@settings); cache_world
        end
        status; view.invalidate
      end
      def enableVCB?; @stage==2; end

      def onUserText(text,view)
        return unless @stage==2
        match=/\A\s*\/\s*(\d+)\s*\z/.match(text.to_s)
        raise 'Nhập /3, /4… (từ /2 đến /60).' unless match
        count=match[1].to_i; point=@equal_anchor || @hover
        candidate,lines=CabinetDoor.equal_cells(@cells,point,@split_axis,count,@internal,@settings)
        doors=CabinetDoor.layout_cells(candidate,@settings)
        @equal_count=count; @equal_anchor=point.dup
        @candidate=candidate; @split_lines=lines; @doors=doors
        @vcb_typing=false; @error=nil; cache_world
        Sketchup.set_status_text('',SB_VCB_VALUE)
        status; view.invalidate
      rescue StandardError=>e
        @vcb_typing=true; @error=e.message; status; view.invalidate; UI.beep
      end

      def onKeyDown(key,repeat,flags,view)
        # Pass printable keys through to Measurements; Enter submits text first.
        if @stage==2 && ([191,111,47].include?(key) || (48..57).include?(key) || (96..105).include?(key))
          @vcb_typing=true
          return false
        end
        return false if @stage==2 && @vcb_typing && [8,13,46].include?(key)
        return true if repeat.to_i>1 && [9,16,13,8,70,83].include?(key)
        case key
        when 16
          @split_axis=1-@split_axis
          @cells ? refresh_split : (rebuild if @last)
        when 9
          CabinetDoor.show_settings(self)
        when 13
          if @stage==2 && @doors
            # Create exactly the currently displayed geometry (including candidate).
            create
          else
            UI.beep
          end
        when 8
          if @stage==2 && @equal_count
            @equal_count=nil; @equal_anchor=nil; @hover=nil; refresh_split
          elsif @stage==2 && !@history.empty?
            @cells=@history.pop; @hover=nil; refresh_split
          end
        when 83
          return
        when 70
          if @stage>0
            @sign *= -1
            @cells ? refresh_split : (rebuild if @last)
          end
        when 37,38,39
          return unless @stage==1
          @u,@v=({37=>[X_AXIS,Z_AXIS],38=>[X_AXIS,Y_AXIS],39=>[Y_AXIS,Z_AXIS]})[key]
          @n=@u.cross(@v); rebuild if @last
        else
          return
        end
        status; view.invalidate; true
      end

      def cache_world
        @world=@doors.map do |door|
          door[:parts].map do |part|
            part[:preview_colors]=part[:faces].map { |face| CabinetDoor.face_color(part,face) }
            [part,part[:faces].map { |face| face.map { |p| world(p) } }]
          end
        end
      end

      def refresh_split
        @candidate=nil; @split_lines=[]; @error=nil
        if @equal_count || @hover
          candidate,lines=if @equal_count
            CabinetDoor.equal_cells(@cells,@equal_anchor,@split_axis,@equal_count,@internal,@settings)
          else
            CabinetDoor.split_cells(@cells,@hover,@split_axis,@internal,@settings)
          end
          if candidate
            begin
              @doors=CabinetDoor.layout_cells(candidate,@settings)
              @candidate=candidate; @split_lines=lines
            rescue StandardError=>e
              @error="Chưa thể chia: #{e.message} | TAB chỉnh thông số; ENTER tạo phần đã giữ."
            end
          end
        end
        @doors=CabinetDoor.layout_cells(@cells,@settings) unless @candidate
        cache_world
      rescue StandardError=>e
        @doors=nil; @world=nil; @error=e.message
      end

      def draw(view)
        @ip.draw(view) if @ip.display? && !@snap_point
        if @snap_point
          color=Sketchup::Color.new(20,180,90)
          # Square endpoints, triangle midpoints (SketchUp draw_points styles).
          style=@snap_label.to_s.include?('Trung điểm') ? 6 : 1
          view.draw_points([@snap_point],10,style,color)
        end
        return unless @doors && @world
        view.line_width=1
        @world.each do |parts|
          parts.each do |part,faces|
            faces.each_with_index do |face,index|
              view.drawing_color=Sketchup::Color.new(*part[:preview_colors][index])
              view.draw(GL_POLYGON,face)
              view.drawing_color=Sketchup::Color.new(125,72,30)
              view.draw(GL_LINE_LOOP,face)
            end
          end
        end
        if @stage==2
          z=@settings['offset']+(@settings['fit']=='Phủ ngoài' ? @settings['thickness'] : 0)+0.15
          view.line_width=3; view.drawing_color=Sketchup::Color.new(20,150,245)
          @split_lines.each { |a,b| view.draw(GL_LINES,[world([a[0],a[1],z]),world([b[0],b[1],z])]) }
        end
      end
      def getExtents
        bb=Geom::BoundingBox.new
        bb.add(@snap_point) if @snap_point
        (@world || []).each { |parts| parts.each { |_p,faces| faces.each { |f| bb.add(f) } } }
        bb
      end
      def create
        raise 'Ngữ cảnh model đã đổi. Hãy gọi lại công cụ.' unless Sketchup.active_model==@model && @model.active_path==@path
        raise 'Không tạo cánh trong đối tượng bị khóa.' if (@path || []).any?(&:locked?)
        # Editing a shared definition would modify its other instances.
        raise 'Hãy Make Unique component đang mở trước khi tạo cánh.' if (@path || []).any? { |e| e.definition.instances.length>1 }
        @model.start_operation('TT - Vẽ cánh tủ',true); started=true
        inv=@model.edit_transform.inverse
        created=[]
        @doors.each_with_index do |door,i|
          group=@model.active_entities.add_group; group.name=door[:name]; created<<group
          group.set_attribute('TT_CABINET_DOOR','settings',@settings.to_json)
          group.set_attribute('TT_CABINET_DOOR','width_mm',door[:width])
          group.set_attribute('TT_CABINET_DOOR','height_mm',door[:height])
          @world[i].each do |part,faces|
            child=group.entities.add_group; child.name=part[:name]
            faces.each do |poly|
              points=poly.map { |p| p.transform(inv) }
              face=child.entities.add_face(points)
              raise 'Không tạo được mặt cánh. Kiểm tra kích thước.' unless face && face.valid?
              wanted=(points[1]-points[0]).cross(points[2]-points[0])
              wanted.reverse! if @sign<0
              # Account for mirrored editing contexts.
              wanted.reverse! if @model.edit_transform.xaxis.cross(@model.edit_transform.yaxis).dot(@model.edit_transform.zaxis)<0
              face.reverse! if face.normal.dot(wanted)<0
            end
            if part[:glass]
              name="TT_Kính_#{@settings['glass_alpha'].to_i}"
              mat=@model.materials[name] || @model.materials.add(name)
              mat.color=Sketchup::Color.new(150,205,225); mat.alpha=@settings['glass_alpha']/100.0
              child.material=mat
            end
          end
        end
        @model.commit_operation; started=false
        @model.selection.clear; @model.selection.add(created); reset
      rescue StandardError=>e
        @model.abort_operation if started
        UI.messagebox("Không tạo được cánh:\n#{e.message}")
      end
    end
  end
end
