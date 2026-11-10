# encoding: UTF-8
# TT - ĐỤC KHUNG: tạo biên dạng ABF thật bên trong Group/Component; không khoét sâu.
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module DucKhung
    extend self
    PREF = 'TT_DUC_KHUNG'.freeze
    DEFAULTS = { 'profile_name'=>'Hèm kính', 'width'=>8.0, 'offset'=>12.0, 'radius'=>3.0, 'corner'=>'round', 'color'=>'#18A957', 'tag'=>'ABF_Hem_kinh', 'instance'=>'ABF_Hem_kinh_01', 'simulate'=>true, 'offset_direction'=>'inside', 'decorative_border'=>false, 'pattern_shape'=>'triangle', 'arrangement'=>'straight', 'symbol_size'=>8.0, 'symbol_spacing'=>24.0 }.freeze
    PRESETS = {
      'Hèm kính' => { 'width'=>8.0, 'offset'=>12.0, 'radius'=>3.0, 'corner'=>'round', 'tracks'=>[0.0,1.0] },
      'Rãnh U' => { 'width'=>6.0, 'offset'=>8.0, 'radius'=>2.0, 'corner'=>'square', 'tracks'=>[0.0,1.0] },
      'Rãnh rộng' => { 'width'=>12.0, 'offset'=>18.0, 'radius'=>4.0, 'corner'=>'round', 'tracks'=>[0.0,1.0] },
      'Khung vát góc' => { 'width'=>8.0, 'offset'=>12.0, 'radius'=>2.0, 'corner'=>'chamfer', 'tracks'=>[0.0,1.0] },
      'Rãnh đôi' => { 'width'=>8.0, 'offset'=>10.0, 'radius'=>1.5, 'corner'=>'square', 'tracks'=>[0.0,0.48,1.0] },
      'Rãnh ba chỉ' => { 'width'=>10.0, 'offset'=>12.0, 'radius'=>1.5, 'corner'=>'square', 'tracks'=>[0.0,0.32,0.68,1.0] },
      'Khung viền kép' => { 'width'=>10.0, 'offset'=>14.0, 'radius'=>2.0, 'corner'=>'round', 'tracks'=>[0.0,0.14,0.86,1.0] },
      'Khung chỉ đơn' => { 'width'=>9.0, 'offset'=>16.0, 'radius'=>4.0, 'corner'=>'round', 'tracks'=>[0.0,1.0] },
      'Khung chỉ vát' => { 'width'=>9.0, 'offset'=>16.0, 'radius'=>1.0, 'corner'=>'chamfer', 'tracks'=>[0.0,1.0] },
      'Khung bậc 2 cấp' => { 'width'=>12.0, 'offset'=>14.0, 'radius'=>2.0, 'corner'=>'square', 'tracks'=>[0.0,0.22,0.78,1.0] },
      'Khung cổ điển' => { 'width'=>14.0, 'offset'=>18.0, 'radius'=>3.0, 'corner'=>'round', 'tracks'=>[0.0,0.18,0.38,0.62,0.82,1.0] },
      'Khung tân cổ điển' => { 'width'=>12.0, 'offset'=>20.0, 'radius'=>2.0, 'corner'=>'chamfer', 'tracks'=>[0.0,0.12,0.28,0.72,0.88,1.0] },
      'Khung trang trí 3 chỉ' => { 'width'=>16.0, 'offset'=>22.0, 'radius'=>3.0, 'corner'=>'round', 'tracks'=>[0.0,0.12,0.5,0.88,1.0] },
      'Rãnh V đôi' => { 'width'=>10.0, 'offset'=>12.0, 'radius'=>0.0, 'corner'=>'chamfer', 'tracks'=>[0.0,0.5,1.0] },
      'Khung nổi nhiều cấp' => { 'width'=>18.0, 'offset'=>24.0, 'radius'=>3.0, 'corner'=>'round', 'tracks'=>[0.0,0.16,0.32,0.68,0.84,1.0] },
      'Khung tối giản' => { 'width'=>5.0, 'offset'=>8.0, 'radius'=>1.0, 'corner'=>'square', 'tracks'=>[0.0,1.0] }
    }.freeze

    def config
      DEFAULTS.each_with_object({}) { |(k,v),h| h[k] = TranTuanNoiThat.setting("duc_khung_#{k}",v) }
    end
    def html_attr(value)
      value.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
    end
    def library
      raw = TranTuanNoiThat.setting('duc_khung_library','[]').to_s
      data = JSON.parse(raw) rescue []
      data.is_a?(Array) ? data.select { |item| item.is_a?(Hash) && !item['name'].to_s.strip.empty? } : []
    end
    def save_library(profile)
      list = library.reject { |p| p.is_a?(Hash) && p['name'].to_s == profile['name'].to_s }
      list << profile
      TranTuanNoiThat.save_setting('duc_khung_library', JSON.generate(list))
    end
    def activate
      show_dialog
    end
    def show_dialog
      cfg = config
      saved_profiles_json = JSON.generate(library).gsub('</', '<\\/')
      presets_json = JSON.generate(PRESETS).gsub('</', '<\\/')
      gallery = PRESETS.map do |name, p|
        count = p['tracks'].length
        lines = p['tracks'].map do |t|
          inset = 12 + (t * 24)
          "<rect x=\"#{inset}\" y=\"#{inset * 0.62}\" width=\"#{120 - inset * 2}\" height=\"#{76 - inset * 1.24}\" rx=\"#{p['corner']=='round' ? 5 : 0}\" fill=\"none\" stroke=\"#16894b\" stroke-width=\"2\"/>"
        end.join
        "<button type=\"button\" class=\"profile-card\" data-profile=\"#{html_attr(name)}\"><svg viewBox=\"0 0 120 76\">#{lines}</svg><span>#{html_attr(name)}</span><small>#{count} đường biên · #{p['corner']=='round' ? 'bo cong' : (p['corner']=='chamfer' ? 'vát góc' : 'góc vuông')}</small></button>"
      end.join
      html = <<~HTML
        <!doctype html><html lang="vi"><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{font:13px Arial;background:#f4f6f5;color:#202722;margin:0;padding:14px}
        h2{margin:0 0 8px;color:#137b43}.sub{color:#66736b;font-size:12px;margin:0 0 10px}
        label{display:block;font-weight:600;margin:9px 0 4px}
        input,select{width:100%;padding:8px;border:1px solid #cbd5ce;border-radius:6px;background:white}
        .gallery{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px;max-height:260px;overflow:auto;padding:2px}
        .profile-card{min-width:0;padding:5px;background:#fff;border:1px solid #d6dfd9;border-radius:8px;color:#25352b;cursor:pointer;text-align:center}
        .profile-card:hover,.profile-card.active{border:2px solid #16894b;padding:4px;background:#eef8f1}
        .profile-card svg{display:block;width:100%;height:62px}.profile-card span{display:block;font-weight:700;font-size:11px;min-height:25px}
        .profile-card small{display:block;color:#718078;font-size:9px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:9px}
        .bar{display:flex;gap:8px;margin-top:13px;flex-wrap:wrap}
        .bar button{border:0;border-radius:6px;padding:10px 12px;background:#16894b;color:white;font-weight:600;cursor:pointer}
        .bar button.alt{background:#53635a}#msg{margin-top:9px;color:#12683a;min-height:18px}
        .hint{color:#66736b;font-size:11px;line-height:1.4}.section{font-weight:700;margin:12px 0 6px;color:#33463a}
        </style><body><h2>ĐỤC KHUNG — THƯ VIỆN BIÊN DẠNG</h2>
        <p class="sub">Chọn mẫu bằng hình xem trước. Có 16 mẫu dựng sẵn và thư viện mẫu tự lưu.</p>
        <div class="gallery" id="gallery">#{gallery}</div>
        <div class="section">Viền trang trí · Preview trực tiếp</div>
        <label><input id="decorative_border" type="checkbox" style="width:auto"> Bật biên dạng viền trang trí</label>
        <div style="background:#fff;border:1px solid #d6dfd9;border-radius:8px;padding:8px;margin:6px 0">
          <svg id="livePreview" viewBox="0 0 320 150" style="width:100%;height:130px"><rect x="18" y="12" width="284" height="126" rx="8" fill="#f8faf8" stroke="#87958b"/><rect x="38" y="30" width="244" height="90" rx="4" fill="none" stroke="#16894b" stroke-width="2"/></svg>
          <div class="hint" id="previewInfo">Xem trước mẫu viền đang chọn</div>
        </div>
        <div class="section">Thông số mẫu đang chọn</div>
        <div class="grid">
          <div><label>Tên biên dạng</label><input id="name" value="#{html_attr(cfg['profile_name'])}"></div>
          <div><label>Offset từ mép Face (mm)</label><input id="offset" type="number" min="0" max="500" step="0.5" value="#{cfg['offset']}"></div>
          <div><label>Hướng Offset</label><select id="offset_direction"><option value="inside">Vào trong Face</option><option value="outside">Ra ngoài Face</option></select></div>
          <div><label>Bề rộng biên dạng (mm)</label><input id="width" type="number" min="0.5" max="100" step="0.5" value="#{cfg['width']}"></div>
          <div><label>Bán kính bo góc (mm)</label><input id="radius" type="number" min="0" max="100" step="0.5" value="#{cfg['radius']}"></div>
          <div><label>Kiểu góc</label><select id="corner"><option value="square">Góc vuông</option><option value="chamfer">Góc vát</option><option value="round">Góc bo cong</option></select></div>
          <div><label>Mô phỏng</label><select id="simulate"><option value="true">Bật mô phỏng</option><option value="false">Tắt mô phỏng</option></select></div>
          <div><label>Tag / Layer (ABF_)</label><input id="tag" value="#{html_attr(cfg['tag'])}"></div>
          <div><label>Tên Instance (tự thêm ABF_)</label><input id="instance" value="#{html_attr(cfg['instance'])}"></div>
          <div><label>Màu Preview</label><input id="color" type="color" value="#{cfg['color']}"></div>
          <div><label>Mẫu đã lưu</label><select id="saved"><option value="">Chọn mẫu đã lưu</option></select></div>
          <div><label>Hình trang trí</label><select id="pattern_shape"><option value="triangle">Tam giác</option><option value="circle">Tròn</option><option value="square">Vuông</option><option value="diamond">Thoi</option><option value="dentil">Răng đinh</option><option value="semicircle">Nửa tròn</option><option value="zigzag">Zíc zắc</option></select></div>
          <div><label>Cách sắp xếp</label><select id="arrangement"><option value="straight">Thẳng / đều</option><option value="staggered">So le</option><option value="random">Ngẫu nhiên</option><option value="symmetric">Đối xứng</option><option value="cycle">Theo chu kỳ</option></select></div>
          <div><label>Kích thước hình (mm)</label><input id="symbol_size" type="number" min="1" max="100" step="0.5" value="8"></div>
          <div><label>Khoảng cách hình (mm)</label><input id="symbol_spacing" type="number" min="2" max="300" step="1" value="24"></div>
        </div>
        <p class="hint">Preview trên Face hiển thị toàn bộ đường biên theo mẫu đã chọn. Click để tạo Group ABF thật bên trong bộ chứa Face; không Push/Pull, không khoét sâu.</p>
        <div class="bar"><button onclick="save()">Lưu biên dạng hiện tại</button><button onclick="start()">Bắt đầu mô phỏng trên Face</button><button class="alt" onclick="closeDlg()">Đóng</button></div><div id="msg"></div>
        <script>
        const $=id=>document.getElementById(id), PRESETS=#{presets_json};
        let selectedTracks=[0,1], savedProfiles=#{saved_profiles_json};
        function payload(){return {name:$('name').value,width:$('width').value,offset:$('offset').value,offset_direction:$('offset_direction').value,radius:$('radius').value,corner:$('corner').value,tracks:selectedTracks,tag:$('tag').value,instance:$('instance').value,color:$('color').value,simulate:$('simulate').value,decorative_border:$('decorative_border').checked,pattern_shape:$('pattern_shape').value,arrangement:$('arrangement').value,symbol_size:$('symbol_size').value,symbol_spacing:$('symbol_spacing').value};}
        function drawLive(){const svg=$('livePreview'),on=$('decorative_border').checked,shape=$('pattern_shape').value,sz=Math.max(2,Math.min(10,Number($('symbol_size').value)||8)),gap=Math.max(14,Math.min(42,(Number($('symbol_spacing').value)||24)*1.15));let a=['<rect x="18" y="12" width="284" height="126" rx="8" fill="#f8faf8" stroke="#87958b"/>','<rect x="38" y="30" width="244" height="90" rx="4" fill="none" stroke="#16894b" stroke-width="2"/>'];if(on){for(let x=45;x<=275;x+=gap){let y=22;if(shape==='circle')a.push('<circle cx="'+x+'" cy="'+y+'" r="'+sz/2+'" fill="#18a957"/>');else a.push('<polygon points="'+(x)+','+(y-sz)+' '+(x+sz)+','+(y+sz)+' '+(x-sz)+','+(y+sz)+'" fill="#18a957"/>');if(shape==='circle')a.push('<circle cx="'+x+'" cy="128" r="'+sz/2+'" fill="#18a957"/>');else a.push('<polygon points="'+x+', '+(128-sz)+' '+(x+sz)+', '+(128+sz)+' '+(x-sz)+', '+(128+sz)+'" fill="#18a957"/>');}for(let y=42;y<=112;y+=gap){a.push('<circle cx="28" cy="'+y+'" r="'+sz/2+'" fill="#18a957"/><circle cx="292" cy="'+y+'" r="'+sz/2+'" fill="#18a957"/>');}}svg.innerHTML=a.join('');$('previewInfo').textContent=on?'Đang bật viền trang trí · '+shape+' · '+$('arrangement').value+' · cỡ '+$('symbol_size').value+' mm · cách '+$('symbol_spacing').value+' mm · offset '+$('offset').value+' mm':'Đang tắt viền trang trí';}
        ['decorative_border','pattern_shape','arrangement','symbol_size','symbol_spacing','offset','width'].forEach(id=>$(id).addEventListener('input',drawLive));
        function apply(p){$('decorative_border').checked=p.decorative_border===true;$('pattern_shape').value=p.pattern_shape||'triangle';$('arrangement').value=p.arrangement||'straight';$('symbol_size').value=p.symbol_size||8;$('symbol_spacing').value=p.symbol_spacing||24;$('name').value=p.name||'';$('width').value=p.width||8;$('offset').value=p.offset||12;$('offset_direction').value=p.offset_direction||'inside';$('radius').value=p.radius||3;$('corner').value=p.corner||'round';$('tag').value=p.tag||'ABF_Hem_kinh';$('instance').value=p.instance||'ABF_Hem_kinh_01';$('color').value=p.color||'#18a957';$('simulate').value=String(p.simulate!==false);selectedTracks=Array.isArray(p.tracks)?p.tracks:[0,1];}
        function choose(name){const p=PRESETS[name];if(!p)return;apply(Object.assign({name:name},p));document.querySelectorAll('.profile-card').forEach(el=>el.classList.toggle('active',el.dataset.profile===name));}
        document.querySelectorAll('.profile-card').forEach(el=>el.addEventListener('click',()=>choose(el.dataset.profile)));
        function refresh(list){if(Array.isArray(list))savedProfiles=list;$('saved').innerHTML='<option value="">Chọn mẫu đã lưu</option>';savedProfiles.forEach((p,i)=>{let o=document.createElement('option');o.value=String(i);o.textContent=String(p.name||'Mẫu không tên');$('saved').appendChild(o);});}
        $('saved').onchange=()=>{const i=Number($('saved').value);if($('saved').value!==''&&savedProfiles[i])apply(savedProfiles[i]);};
        $('name').addEventListener('input',()=>document.querySelectorAll('.profile-card').forEach(el=>el.classList.remove('active')));
        function save(){sketchup.save_profile(JSON.stringify(payload()));}
        function start(){sketchup.start_tool(JSON.stringify(payload()));}
        function closeDlg(){sketchup.close_dialog();}
        refresh();choose(Object.keys(PRESETS)[0]);drawLive();
        </script></body></html>
      HTML
      @dialog.close if @dialog && @dialog.visible?
      @dialog = UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN — ĐỤC KHUNG',preferences_key:'TT_DUC_KHUNG',scrollable:true,resizable:true,width:560,height:850,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(html)
      @dialog.add_action_callback('save_profile') { |_d,json| save_profile(json) }
      @dialog.add_action_callback('start_tool') { |_d,json| start_tool(json) }
      @dialog.add_action_callback('close_dialog') { |_d| @dialog.close }
      @dialog.show
    end
    def normalize(raw)
      p = raw.is_a?(String) ? JSON.parse(raw) : raw
      width = Float(p['width']); offset = Float(p.fetch('offset',12)); radius = Float(p.fetch('radius',3)); offset_direction = p.fetch('offset_direction','inside').to_s
      raise 'Bề rộng hèm phải từ 0.5 đến 100 mm.' unless width.between?(0.5,100)
      raise 'Offset phải từ 0 đến 500 mm.' unless offset.between?(0,500)
      raise 'Bán kính bo góc phải từ 0 đến 100 mm.' unless radius.between?(0,100)
      tag = p['tag'].to_s.strip
      tag = "ABF_#{tag}" unless tag.start_with?('ABF_')
      raise 'Hãy nhập tên Tag/Layer.' if tag == 'ABF_'
      tracks = p['tracks'].is_a?(Array) ? p['tracks'].map { |v| [[Float(v),0.0].max,1.0].min }.uniq.sort : [0.0,1.0]
      tracks = [0.0,1.0] unless tracks.length.between?(2,8)
      tracks[0] = 0.0
      tracks[-1] = 1.0
      symbol_size=Float(p.fetch('symbol_size',8)); symbol_spacing=Float(p.fetch('symbol_spacing',24))
      raise 'Kích thước hình trang trí phải từ 1 đến 100 mm.' unless symbol_size.between?(1,100)
      raise 'Khoảng cách hình phải từ 2 đến 300 mm.' unless symbol_spacing.between?(2,300)
      pattern_shape=p.fetch('pattern_shape','triangle').to_s
      arrangement=p.fetch('arrangement','straight').to_s
      { 'name'=>p['name'].to_s.strip.empty? ? 'Biên dạng mới' : p['name'].to_s.strip,
        'width'=>width,'offset'=>offset,'offset_direction'=>(%w[inside outside].include?(offset_direction) ? offset_direction : 'inside'),'radius'=>radius,'corner'=>%w[square chamfer round].include?(p['corner'].to_s) ? p['corner'].to_s : 'round',
        'tracks'=>tracks,'decorative_border'=>p['decorative_border']==true || p['decorative_border'].to_s=='true','pattern_shape'=>(%w[triangle circle square diamond dentil semicircle zigzag].include?(pattern_shape) ? pattern_shape : 'triangle'),'arrangement'=>(%w[straight staggered random symmetric cycle].include?(arrangement) ? arrangement : 'straight'),'symbol_size'=>symbol_size,'symbol_spacing'=>symbol_spacing,'tag'=>tag,'instance'=>(p['instance'].to_s.strip.empty? ? 'ABF_Bien_Dang' : (p['instance'].to_s.strip.start_with?('ABF_') ? p['instance'].to_s.strip : "ABF_#{p['instance'].to_s.strip}")), 'simulate'=>p['simulate'].to_s!='false',
        'color'=>p['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/) ? p['color'] : '#18A957' }
    end
    def persist(p)
      p.each { |k,v| TranTuanNoiThat.save_setting("duc_khung_#{k}",v) }
    end
    def save_profile(raw)
      p=normalize(raw); persist(p); save_library(p)
      @dialog.execute_script("document.getElementById('msg').textContent='Đã lưu biên dạng: '+#{JSON.generate(p['name'])}; refresh(#{JSON.generate(library)}); document.getElementById('saved').value=String(document.getElementById('saved').options.length-1);")
    rescue StandardError=>e
      @dialog.execute_script("document.getElementById('msg').textContent=#{JSON.generate(e.message)};")
    end
    def start_tool(raw)
      p=normalize(raw); persist(p); @dialog.close if @dialog
      Sketchup.active_model.select_tool(Tool.new(p))
    rescue StandardError=>e
      UI.messagebox("ĐỤC KHUNG: #{e.message}")
    end

    class Tool
      def initialize(cfg); @cfg=cfg; @ip=Sketchup::InputPoint.new; @candidate=nil; end
      def activate
        Sketchup.set_status_text('ĐỤC KHUNG: rê chuột lên Face để mô phỏng trực tiếp · click tạo rãnh · ESC thoát', SB_PROMPT)
      end
      def onCancel(_reason,view); Sketchup.active_model.select_tool(nil); view.invalidate; end
      def onMouseMove(_flags,x,y,view)
        ph=view.pick_helper; ph.do_pick(x,y)
        @candidate=nil
        ph.count.times do |i|
          face=ph.leaf_at(i)
          next unless face.is_a?(Sketchup::Face) && face.valid?
          tr=Sketchup.active_model.edit_transform * (ph.transformation_at(i) || Geom::Transformation.new)
          candidate=build_preview(face,tr)
          if candidate
            @candidate=candidate; break
          end
        end
        view.tooltip=@candidate ? "ABF #{@cfg['name']} · dày ván #{@candidate[:thickness]} mm · offset #{@cfg['offset']} mm (#{@cfg['offset_direction']=='outside' ? 'ra ngoài' : 'vào trong'}) · rộng #{@cfg['width']} mm" : 'Chọn Face trong Group/Component'
        view.invalidate
      rescue StandardError=>e
        @candidate=nil; puts "[TT DucKhung hover] #{e.class}: #{e.message}"; view.invalidate
      end
      def draw(view)
        return unless @candidate && @cfg['simulate']
        c=@cfg['color']; rgb=[c[1,2].to_i(16),c[3,2].to_i(16),c[5,2].to_i(16)]
        view.drawing_color=Sketchup::Color.new(*rgb,210)
        view.line_width=3
        @candidate[:paths_world].each { |path| view.draw(GL_LINE_LOOP,path) }
      end
      def onLButtonDown(_flags,x,y,view)
        onMouseMove(0,x,y,view)
        raise 'Hãy rê chuột lên một Face hợp lệ.' unless @candidate
        commit(@candidate)
        @candidate=nil; view.invalidate
      rescue StandardError=>e
        UI.messagebox("ĐỤC KHUNG: #{e.message}")
      end
      private
      def build_preview(face,tr)
        return nil unless face.loops.length==1
        verts=face.outer_loop.vertices
        return nil if verts.length<3
        pts=verts.map(&:position)
        normal=face.normal.clone; normal.normalize!
        xaxis=pts[1]-pts[0]; return nil if xaxis.length<0.001; xaxis.normalize!
        yaxis=normal.cross(xaxis); yaxis.normalize!
        origin=pts[0]
        coords=pts.map{|p| v=p-origin; [v.dot(xaxis),v.dot(yaxis)]}
        offset_sign=@cfg['offset_direction']=='outside' ? -1.0 : 1.0
        tracks = @cfg['tracks'].is_a?(Array) ? @cfg['tracks'] : [0.0,1.0]
        paths = tracks.map do |fraction|
          distance = @cfg['offset'] + (@cfg['width'] * fraction.to_f)
          poly = offset_polygon(coords,offset_sign*distance/25.4)
          next nil unless poly && poly.length>=3
          if @cfg['corner']=='chamfer'
            poly=chamfer_polygon(poly,[@cfg['width']/25.4*0.2,2.0/25.4].min)
          elsif @cfg['corner']=='round'
            poly=round_polygon(poly,[@cfg['radius']/25.4,(@cfg['width']/25.4)*0.35].min)
          end
          poly.map{|x,y| origin.offset(xaxis,x).offset(yaxis,y)}
        end
        return nil if paths.any?(&:nil?)
        if @cfg['decorative_border']
          center=offset_polygon(coords,offset_sign*(@cfg['offset']+@cfg['width']*0.5)/25.4)
          return nil unless center
          paths.concat(decorative_paths(center,@cfg['pattern_shape'],@cfg['symbol_size']/25.4,@cfg['symbol_spacing']/25.4,@cfg['arrangement']))
        end
        return nil unless paths.all? { |path| path.all? { |point| [Sketchup::Face::PointInside,Sketchup::Face::PointOnEdge].include?(face.classify_point(point)) } }
        outer_world=pts.map{|p| p.transform(tr)}
        paths_world=paths.map{|path| path.map{|point| point.transform(tr)}}
        {face:face,transform:tr,outer:outer_world,paths_world:paths_world,local_paths:paths,normal:normal,thickness:detect_thickness(face)}
      rescue StandardError
        nil
      end
      def decorative_paths(poly,shape,size,spacing,arrangement)
        lengths=[]; total=0.0
        poly.each_with_index do |a,i|
          b=poly[(i+1)%poly.length]; len=Math.hypot(b[0]-a[0],b[1]-a[1])
          lengths << [total,len,a,b]; total+=len
        end
        return [] if total<=size*2 || spacing<=0
        count=[[((total/spacing).floor),500].min,1].max
        result=[]
        count.times do |idx|
          distance=case arrangement
          when 'staggered' then (idx*spacing+(idx.odd? ? spacing*0.5 : 0.0))%total
          when 'random' then ((idx*0.61803398875+((idx*37)%17)/17.0)*total)%total
          when 'symmetric' then count<=1 ? total*0.5 : (idx.to_f/(count-1))*total
          else idx*spacing
          end
          seg=lengths.find{|entry| distance>=entry[0] && distance<=entry[0]+entry[1]} || lengths.last
          base,len,a,b=seg; next if len<size*1.4
          t=[[((distance-base)/len),0.0].max,1.0].min
          cx=a[0]+(b[0]-a[0])*t; cy=a[1]+(b[1]-a[1])*t
          tx=(b[0]-a[0])/len; ty=(b[1]-a[1])/len; nx=-ty; ny=tx; radius=size*0.5
          sides=shape=='circle' ? 12 : (shape=='triangle' ? 3 : 4)
          pts=sides.times.map do |j|
            angle=2.0*Math::PI*j/sides+(shape=='diamond' ? Math::PI/4.0 : 0.0)
            along=Math.cos(angle)*radius; across=Math.sin(angle)*radius
            [cx+tx*along+nx*across,cy+ty*along+ny*across]
          end
          result << pts
        end
        result
      end
      def offset_polygon(poly,d)
        area=poly.each_with_index.sum{|p,i| q=poly[(i+1)%poly.length];p[0]*q[1]-q[0]*p[1]} / 2.0
        return nil if area.abs<1e-8
        sign=area>0 ? 1.0 : -1.0
        lines=poly.each_with_index.map do |p,i|
          q=poly[(i+1)%poly.length]; dx=q[0]-p[0];dy=q[1]-p[1];len=Math.hypot(dx,dy);return nil if len<1e-7
          nx=-dy/len*sign;ny=dx/len*sign
          [[p[0]+nx*d,p[1]+ny*d],[dx,dy]]
        end
        result=[]
        lines.each_with_index do |line,i|
          prev=lines[(i-1)%lines.length]
          a=prev[0];r=prev[1];b=line[0];s=line[1]
          den=r[0]*s[1]-r[1]*s[0];return nil if den.abs<1e-8
          t=((b[0]-a[0])*s[1]-(b[1]-a[1])*s[0])/den
          result << [a[0]+t*r[0],a[1]+t*r[1]]
        end
        return nil if result.each_with_index.any?{|p,i| Math.hypot(p[0]-result[(i+1)%result.length][0],p[1]-result[(i+1)%result.length][1])<0.001}
        result
      end
      def round_polygon(poly,radius)
        return poly if radius<=0.0001
        out=[]
        poly.each_with_index do |p,i|
          prev=poly[(i-1)%poly.length]; nxt=poly[(i+1)%poly.length]
          v1=[prev[0]-p[0],prev[1]-p[1]]; v2=[nxt[0]-p[0],nxt[1]-p[1]]
          l1=Math.hypot(v1[0],v1[1]); l2=Math.hypot(v2[0],v2[1])
          return poly if [l1,l2].min<=radius*2
          a=[p[0]+v1[0]/l1*radius,p[1]+v1[1]/l1*radius]
          b=[p[0]+v2[0]/l2*radius,p[1]+v2[1]/l2*radius]
          6.times do |j|
            t=j/5.0; u=1.0-t
            out << [u*u*a[0]+2*u*t*p[0]+t*t*b[0],u*u*a[1]+2*u*t*p[1]+t*t*b[1]]
          end
        end
        out
      end
      def chamfer_polygon(poly,d)
        return poly if d<=0.0001
        out=[]
        poly.each_with_index do |p,i|
          prev=poly[(i-1)%poly.length]; nxt=poly[(i+1)%poly.length]
          v1=[prev[0]-p[0],prev[1]-p[1]]; v2=[nxt[0]-p[0],nxt[1]-p[1]]
          l1=Math.hypot(v1[0],v1[1]); l2=Math.hypot(v2[0],v2[1])
          return poly if [l1,l2].min<=d*2
          out << [p[0]+v1[0]/l1*d,p[1]+v1[1]/l1*d]
          out << [p[0]+v2[0]/l2*d,p[1]+v2[1]/l2*d]
        end
        out
      end
      def detect_thickness(face)
        parent=face.parent
        ents=parent.respond_to?(:grep) ? parent : (parent.respond_to?(:entities) ? parent.entities : nil)
        return 0.0 unless ents
        n=face.normal
        base=face.vertices.map(&:position).map{|pt| pt.dot(n)}.sum / face.vertices.length
        candidates=ents.grep(Sketchup::Face).select{|f| f.valid? && f!=face && f.normal.parallel?(n)}
        distances=candidates.map{|f| f.vertices.map(&:position).map{|pt| (pt.dot(n)-base).abs}.min}.select{|d| d>0.01}
        distances.empty? ? 0.0 : (distances.min*25.4).round(2)
      rescue StandardError
        0.0
      end
      def commit(c)
        model=Sketchup.active_model
        face=c[:face]
        raise 'Face đã thay đổi hoặc bị xóa.' unless face && face.valid?
        parent=face.parent
        ents=parent.respond_to?(:add_edges) ? parent : (parent.respond_to?(:entities) ? parent.entities : nil)
        raise 'Không xác định được bộ chứa Face. Hãy mở Group/Component để chỉnh sửa rồi thử lại.' unless ents && ents.respond_to?(:add_edges)
        definition=parent if parent.respond_to?(:instances)
        if definition && definition.instances.length>1
          raise 'Component đang dùng chung nhiều bản sao. Hãy Make Unique trước khi tạo biên dạng.'
        end
        model.start_operation('TẠO BIÊN DẠNG ABF',true)
        tag_name=@cfg['tag'].to_s.start_with?('ABF_') ? @cfg['tag'] : "ABF_#{@cfg['tag']}"
        layer=model.layers[tag_name] || model.layers.add(tag_name)
        profile_group=ents.add_group
        profile_group.name=@cfg['instance']
        profile_group.layer=layer
        profile_group.set_attribute(PREF,'profile_name',@cfg['name'])
        profile_group.set_attribute(PREF,'instance_name',@cfg['instance'])
        profile_group.set_attribute(PREF,'board_thickness_mm',c[:thickness])
        profile_group.set_attribute(PREF,'corner_radius_mm',@cfg['radius'])
        profile_entities=profile_group.entities
        created_edges = c[:local_paths].map do |path|
          profile_entities.add_edges(path + [path.first])
        end
        raise 'Không tạo được đường biên dạng. Hãy giảm Offset/Bề rộng/Bán kính.' if created_edges.any? { |edges| edges.nil? || edges.empty? }
        created_edges.flatten.uniq.each { |edge| edge.layer=layer if edge.valid? }
        model.commit_operation
        UI.messagebox("Đã tạo biên dạng ABF: #{@cfg['name']}\\nInstance: #{@cfg['instance']}\\nTag: #{tag_name}\\nĐộ dày nhận diện: #{c[:thickness]} mm\\nKhông khoét sâu.")
      rescue StandardError
        model.abort_operation if model && model.respond_to?(:abort_operation)
        raise
      end
    end
  end
end
