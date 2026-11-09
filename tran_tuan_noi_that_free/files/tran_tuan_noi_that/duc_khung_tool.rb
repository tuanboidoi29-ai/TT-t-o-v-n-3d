# encoding: UTF-8
# TT - ĐỤC KHUNG: preview biên dạng âm quanh Face và tạo hèm/rãnh chữ nhật.
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module DucKhung
    extend self
    PREF = 'TT_DUC_KHUNG'.freeze
    DEFAULTS = { 'profile_name'=>'Hèm kính', 'width'=>12.0, 'depth'=>5.0, 'corner'=>'square', 'color'=>'#18A957', 'tag'=>'ABF_Hem_kinh', 'instance'=>'Hem_kinh_01' }.freeze
    PRESETS = {
      'Hèm kính' => { 'width'=>12.0, 'depth'=>5.0, 'corner'=>'square' },
      'Rãnh U' => { 'width'=>8.0, 'depth'=>4.0, 'corner'=>'square' },
      'Rãnh rộng' => { 'width'=>18.0, 'depth'=>6.0, 'corner'=>'square' },
      'Khung vát góc' => { 'width'=>12.0, 'depth'=>5.0, 'corner'=>'chamfer' }
    }.freeze

    def config
      DEFAULTS.each_with_object({}) { |(k,v),h| h[k] = TranTuanNoiThat.setting("duc_khung_#{k}",v) }
    end
    def library
      raw = TranTuanNoiThat.setting('duc_khung_library','[]').to_s
      data = JSON.parse(raw) rescue []
      data.is_a?(Array) ? data : []
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
      presets = PRESETS.keys
      options = presets.map { |x| "<option>#{x}</option>" }.join
      html = <<~HTML
        <!doctype html><html lang="vi"><meta charset="utf-8"><style>
        body{font:13px Arial;background:#f4f6f5;color:#202722;margin:0;padding:14px}
        h2{margin:0 0 12px;color:#137b43}label{display:block;font-weight:600;margin:10px 0 4px}
        input,select{box-sizing:border-box;width:100%;padding:8px;border:1px solid #cbd5ce;border-radius:6px;background:white}
        .grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.bar{display:flex;gap:8px;margin-top:14px;flex-wrap:wrap}
        button{border:0;border-radius:6px;padding:10px 12px;background:#16894b;color:white;font-weight:600;cursor:pointer}
        button.alt{background:#53635a}#msg{margin-top:10px;color:#12683a;min-height:18px}
        .hint{color:#66736b;font-size:12px;line-height:1.4}.swatch{height:24px;border-radius:5px;border:1px solid #ccd}
        </style><body><h2>ĐỤC KHUNG — Biên dạng quanh Face</h2>
        <label>Thư viện biên dạng</label><select id="preset">#{options}<option value="custom">Biên dạng tùy chỉnh</option></select>
        <div class="grid"><div><label>Tên biên dạng</label><input id="name" value="#{cfg['profile_name']}"></div><div><label>Chiều rộng (mm)</label><input id="width" type="number" min="0.5" max="100" step="0.5" value="#{cfg['width']}"></div>
        <div><label>Chiều sâu (mm)</label><input id="depth" type="number" min="0.5" max="50" step="0.5" value="#{cfg['depth']}"></div><div><label>Kiểu góc</label><select id="corner"><option value="square">Góc vuông</option><option value="chamfer">Vát góc nhẹ</option></select></div>
        <div><label>Tag / Layer (ABF_)</label><input id="tag" value="#{cfg['tag']}"></div><div><label>Tên Instance</label><input id="instance" value="#{cfg['instance']}"></div>
        <div><label>Màu Preview</label><input id="color" type="color" value="#{cfg['color']}"></div><div><label>Thư viện đã lưu</label><select id="saved"><option value="">Chọn mẫu đã lưu</option></select></div></div>
        <p class="hint">Rê chuột lên Face để xem trước trực tiếp. Click Face để tạo rãnh lõm. Hỗ trợ Face phẳng, biên dạng lồi, một vòng biên khép kín. Bản đầu hỗ trợ rãnh chữ nhật và góc vát.</p>
        <div class="bar"><button onclick="save()">Lưu biên dạng</button><button onclick="start()">Bắt đầu mô phỏng</button><button class="alt" onclick="closeDlg()">Đóng</button></div><div id="msg"></div>
        <script>
        const $=id=>document.getElementById(id);
        function payload(){return {name:$('name').value,width:$('width').value,depth:$('depth').value,corner:$('corner').value,tag:$('tag').value,instance:$('instance').value,color:$('color').value};}
        function apply(p){$('name').value=p.name||'';$('width').value=p.width||12;$('depth').value=p.depth||5;$('corner').value=p.corner||'square';$('tag').value=p.tag||'ABF_Hem_kinh';$('instance').value=p.instance||'Hem_kinh_01';$('color').value=p.color||'#18a957';}
        $('preset').onchange=()=>{const p=#{JSON.generate(PRESETS)}[$('preset').value];if(p){$('width').value=p.width;$('depth').value=p.depth;$('corner').value=p.corner;$('name').value=$('preset').value;}};
        function refresh(){ $('saved').innerHTML='<option value="">Chọn mẫu đã lưu</option>'; const a=#{JSON.generate(library)};a.forEach((p,i)=>{let o=document.createElement('option');o.value=i;o.textContent=p.name;$('saved').appendChild(o);});}
        $('saved').onchange=()=>{const a=#{JSON.generate(library)};if(a[$('saved').value])apply(a[$('saved').value]);};
        function save(){sketchup.save_profile(JSON.stringify(payload()));}
        function start(){sketchup.start_tool(JSON.stringify(payload()));}
        function closeDlg(){sketchup.close_dialog();}
        refresh();
        </script></body></html>
      HTML
      @dialog.close if @dialog && @dialog.visible?
      @dialog = UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN — ĐỤC KHUNG',preferences_key:'TT_DUC_KHUNG',scrollable:true,resizable:true,width:430,height:610,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(html)
      @dialog.add_action_callback('save_profile') { |_d,json| save_profile(json) }
      @dialog.add_action_callback('start_tool') { |_d,json| start_tool(json) }
      @dialog.add_action_callback('close_dialog') { |_d| @dialog.close }
      @dialog.show
    end
    def normalize(raw)
      p = raw.is_a?(String) ? JSON.parse(raw) : raw
      width = Float(p['width']); depth = Float(p['depth'])
      raise 'Chiều rộng phải từ 0.5 đến 100 mm.' unless width.between?(0.5,100)
      raise 'Chiều sâu phải từ 0.5 đến 50 mm.' unless depth.between?(0.5,50)
      tag = p['tag'].to_s.strip
      tag = "ABF_#{tag}" unless tag.start_with?('ABF_')
      raise 'Hãy nhập tên Tag/Layer.' if tag == 'ABF_'
      { 'name'=>p['name'].to_s.strip.empty? ? 'Biên dạng mới' : p['name'].to_s.strip,
        'width'=>width,'depth'=>depth,'corner'=>p['corner'].to_s=='chamfer' ? 'chamfer' : 'square',
        'tag'=>tag,'instance'=>p['instance'].to_s.strip.empty? ? 'Duc_Khung' : p['instance'].to_s.strip,
        'color'=>p['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/) ? p['color'] : '#18A957' }
    end
    def persist(p)
      p.each { |k,v| TranTuanNoiThat.save_setting("duc_khung_#{k}",v) }
    end
    def save_profile(raw)
      p=normalize(raw); persist(p); save_library(p)
      @dialog.execute_script("document.getElementById('msg').textContent='Đã lưu biên dạng: '+#{JSON.generate(p['name'])};")
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
        view.tooltip=@candidate ? "ĐỤC KHUNG #{@cfg['name']} · rộng #{@cfg['width']} mm · sâu #{@cfg['depth']} mm" : 'Chọn Face phẳng, khép kín'
        view.invalidate
      rescue StandardError=>e
        @candidate=nil; puts "[TT DucKhung hover] #{e.class}: #{e.message}"; view.invalidate
      end
      def draw(view)
        return unless @candidate
        pts=@candidate[:outer]; inner=@candidate[:inner]
        c=@cfg['color']; rgb=[c[1,2].to_i(16),c[3,2].to_i(16),c[5,2].to_i(16)]
        view.drawing_color=Sketchup::Color.new(*rgb,210)
        view.line_width=3
        view.draw(GL_LINE_LOOP,pts)
        view.draw(GL_LINE_LOOP,inner)
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
        inner2=offset_polygon(coords,@cfg['width']/25.4)
        return nil unless inner2 && inner2.length>=3
        inner2=chamfer_polygon(inner2,[@cfg['width']/25.4*0.2,2.0/25.4].min) if @cfg['corner']=='chamfer'
        inner=inner2.map{|x,y| origin.offset(xaxis,x).offset(yaxis,y)}
        return nil unless inner.all?{|p| [Sketchup::Face::PointInside,Sketchup::Face::PointOnEdge].include?(face.classify_point(p))}
        outer_world=pts.map{|p| p.transform(tr)}
        inner_world=inner.map{|p| p.transform(tr)}
        {face:face,transform:tr,outer:outer_world,inner:inner_world,local_inner:inner,normal:normal}
      rescue StandardError
        nil
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
      def commit(c)
        model=Sketchup.active_model; face=c[:face]
        raise 'Face đã thay đổi hoặc bị xóa.' unless face.valid?
        ents=face.parent
        raise 'Không xác định được bộ chứa hình học.' unless ents.respond_to?(:add_face)
        model.start_operation('ĐỤC KHUNG',true)
        before_entities=ents.to_a
        layer_name=@cfg['tag']
        layer=model.layers[layer_name] || model.layers.add(layer_name)
        points=c[:local_inner]
        new_face=ents.add_face(points)
        raise 'Không tạo được mặt trong. Kiểm tra chiều rộng hoặc biên dạng Face.' unless new_face && new_face.valid?
        new_face.reverse! if new_face.normal.dot(face.normal)<0
        new_face.layer=layer
        new_face.set_attribute(PREF,'profile_name',@cfg['name'])
        new_face.set_attribute(PREF,'instance_name',@cfg['instance'])
        new_face.set_attribute(PREF,'width_mm',@cfg['width'])
        new_face.set_attribute(PREF,'depth_mm',@cfg['depth'])
        new_face.set_attribute(PREF,'corner',@cfg['corner'])
        material_name="TT_DUC_KHUNG_#{@cfg['name'].gsub(/[^A-Za-z0-9_]/,'_')}"
        material=model.materials[material_name] || model.materials.add(material_name)
        color=@cfg['color']
        material.color=Sketchup::Color.new(color[1,2].to_i(16),color[3,2].to_i(16),color[5,2].to_i(16))
        new_face.material=material
        new_face.pushpull(-(@cfg['depth']/25.4),false)
        created=ents.to_a-before_entities
        created.each do |entity|
          next unless entity.valid? && (entity.is_a?(Sketchup::Face)||entity.is_a?(Sketchup::Edge))
          entity.layer=layer
          entity.material=material if entity.is_a?(Sketchup::Face)
          entity.set_attribute(PREF,'profile_name',@cfg['name'])
          entity.set_attribute(PREF,'instance_name',@cfg['instance'])
        end
        model.commit_operation
        UI.messagebox("Đã tạo ĐỤC KHUNG: #{@cfg['name']}\nTag: #{layer_name}\nInstance: #{@cfg['instance']}\nLưu ý: kiểm tra kết quả Solid và Undo nếu mặt nằm trên khối phức tạp.")
      rescue StandardError
        model.abort_operation if model && model.respond_to?(:abort_operation)
        raise
      end
    end
  end
end
