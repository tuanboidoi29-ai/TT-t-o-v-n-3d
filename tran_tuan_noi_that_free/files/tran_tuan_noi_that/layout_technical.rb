# encoding: UTF-8
# Native linked LayOut documents; SketchUp/LayOut 2021+.
require 'json'
require 'tmpdir'
module TranTuanNoiThat
  module LayoutTechnical
    extend self
    remove_const(:VIEWS) if const_defined?(:VIEWS, false)
    VIEWS = {'top'=>'Mặt bằng','front'=>'Mặt đứng ngoài','left'=>'Mặt bên trái',
             'right'=>'Mặt bên phải','cut_front'=>'Mặt cắt thùng trước',
             'cut_left'=>'Mặt cắt thùng trái','cut_right'=>'Mặt cắt thùng phải',
             'overview'=>'Phối cảnh 3D'}.freeze
    remove_const(:DEFAULTS) if const_defined?(:DEFAULTS, false)
    DEFAULTS = {'project'=>'','scale'=>20.0,'cut_scale'=>20.0,'render'=>'Vector',
                'cut_mm'=>100.0,'quality'=>90.0,'stats'=>true,
                'views'=>VIEWS.keys}.freeze
    def helper; LayoutStats; end
    def normalize(data)
      raise 'Dữ liệu cài đặt không hợp lệ.' unless data.is_a?(Hash)
      out = DEFAULTS.merge(data.select { |k,_| DEFAULTS.key?(k) })
      %w[scale cut_scale cut_mm quality].each do |key|
        out[key] = Float(out[key])
        raise "Thông số #{key} không hợp lệ." unless out[key].finite?
      end
      %w[scale cut_scale].each { |k| raise 'Mẫu số tỷ lệ phải từ 1 đến 500.' unless out[k].between?(1,500) }
      raise 'Vị trí cắt phải từ 0,1 đến 5000 mm.' unless out['cut_mm'].between?(0.1,5000)
      raise 'Chất lượng nén phải từ 50 đến 100%.' unless out['quality'].between?(50,100)
      raise 'Chọn Vector hoặc Hybrid.' unless %w[Vector Hybrid].include?(out['render'])
      raise 'Chọn ít nhất một góc nhìn.' unless out['views'].is_a?(Array) && !out['views'].empty?
      raise 'Góc nhìn không hợp lệ.' unless (out['views'] - VIEWS.keys).empty?
      out['views'] = VIEWS.keys.select { |k| out['views'].include?(k) }
      out['project'] = out['project'].to_s.strip[0,160]
      out['stats'] = out['stats'] == true
      out
    end
    def settings
      normalize(JSON.parse(Sketchup.read_default('TranTuanNoiThat.LayoutTechnical','settings',JSON.generate(DEFAULTS))))
    rescue StandardError
      DEFAULTS.merge('views'=>VIEWS.keys)
    end
    def persist(options)
      value = JSON.generate(options)
      Sketchup.write_default('TranTuanNoiThat.LayoutTechnical','settings',value)
      raise 'Không lưu được cấu hình xuất.' unless Sketchup.read_default('TranTuanNoiThat.LayoutTechnical','settings','') == value
    end
    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @model = Sketchup.active_model
      @dialog = UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN · HỒ SƠ LAYOUT A3',
        preferences_key:'TranTuanNoiThat.LayoutTechnical',scrollable:true,resizable:true,
        width:850,height:780,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(html)
      @dialog.add_action_callback('ready') { |_c| send_state }
      @dialog.add_action_callback('run') do |_c, action, json|
        next if @busy
        @busy = true
        begin
          raise 'Đã đổi mô hình. Đóng bảng và mở lại công cụ.' unless Sketchup.active_model == @model
          options = normalize(JSON.parse(json))
          persist(options)
          case action
          when 'save' then report('Đã lưu cấu hình cho lần xuất sau.')
          when 'check' then report(check_jobs(options).map { |j| "#{j[:name]}: #{j[:stats][:total_pieces]} chi tiết — vừa khung ở tỷ lệ đã chọn." }.join("\n"))
          when 'layout','pdf','preview','template','scenes' then run(action,options)
          else raise 'Thao tác không hợp lệ.'
          end
        rescue StandardError => e
          report(e.message,true)
          puts "[TT LayOut] #{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}"
        ensure
          @busy = false
          @dialog.execute_script('setBusy(false)') if @dialog
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    end
    def send_state
      o = settings
      o['project'] = File.basename(@model.path.to_s,'.skp') if o['project'].empty?
      o['project'] = 'Công trình mới' if o['project'].empty?
      @dialog.execute_script("receive(#{JSON.generate(o)})")
    end
    def report(message,error=false)
      @dialog.execute_script("report(#{JSON.generate(message.to_s)},#{error ? 'true' : 'false'})") if @dialog
    end
    def denominator(key,o); key.start_with?('cut_') ? o['cut_scale'] : o['scale']; end
    # Model bounding box -> projected width/height, in millimetres.
    def projected_size(key,bb)
      case key
      when 'top' then [bb.width,bb.height]
      when 'left','right','cut_left','cut_right' then [bb.height,bb.depth]
      else [bb.width,bb.depth]
      end.map { |v| v.to_f * 25.4 }
    end
    def fit_error(key,bb,o)
      return nil if key == 'overview'
      width,height = projected_size(key,bb)
      d = denominator(key,o)
      return nil if width/d <= 370.0 && height/d <= 215.0
      minimum = [width/370.0,height/215.0].max.ceil
      "#{VIEWS[key]} không vừa vùng vẽ A3 ở 1:#{format('%g',d)} (#{(width/d).round(1)} × #{(height/d).round(1)} mm). Chọn tỷ lệ 1:#{minimum} hoặc nhỏ hơn, hoặc chỉ chọn cụm/chi tiết cần xuất."
    end
    def check_jobs(o)
      model = Sketchup.active_model
      raise 'Thoát chế độ sửa Group/Component trước khi xuất để Scene lưu đúng phạm vi.' if model.active_path && !model.active_path.empty?
      jobs = helper.tt_layout_jobs
      raise 'Chọn Group/Component chứa tủ hoặc tấm ván trước khi xuất.' if jobs.empty?
      jobs.each do |job|
        job[:bounds] = helper.tt_scope_bounds_for_roots(model,job[:roots])
        o['views'].each do |key|
          error = fit_error(key,job[:bounds],o)
          raise "#{job[:name]}: #{error}" if error
        end
      end
      jobs
    end
    def profile(options,section,material)
      values = {'DisplaySectionCuts'=>section,'DisplaySectionPlanes'=>false,
        'SectionCutFilled'=>section,'SectionCutDrawEdges'=>true,
        'SectionDefaultFillColor'=>Sketchup::Color.new(0,0,0),
        'SectionDefaultCutColor'=>Sketchup::Color.new(0,0,0),
        'ModelTransparency'=>false,'DrawBackEdges'=>false,'DrawHidden'=>false,
        'DrawGround'=>false,'DrawHorizon'=>false,'DisplaySketchAxes'=>false,
        'DisplayWatermarks'=>false,'DisplayFog'=>false,'EdgeType'=>0,
        'DrawSilhouettes'=>false,'DrawLineEnds'=>false,'ExtendLines'=>false,
        'EdgeDisplayMode'=>1,'EdgeColorMode'=>0,'ForegroundColor'=>Sketchup::Color.new(0,0,0),
        'BackgroundColor'=>Sketchup::Color.new(255,255,255),
        'FaceFrontColor'=>Sketchup::Color.new(255,255,255),
        'FaceBackColor'=>Sketchup::Color.new(255,255,255),
        'Texture'=>material,'RenderMode'=>material ? 2 : 1}
      keys = options.keys
      values.each { |k,v| options[k] = v if keys.include?(k) }
      %w[ROPDrawHiddenGeometry ROPDrawHiddenObjects].each { |k| options[k] = false if keys.include?(k) }
      raise 'SketchUp không hỗ trợ Section Fills.' if section && !keys.include?('SectionCutFilled')
    end
    def camera(key,bb)
      if key == 'top'
        eye = bb.center.offset(Z_AXIS,[bb.diagonal.to_f*2.5,1000.0/25.4].max)
        cam = Sketchup::Camera.new(eye,bb.center,Y_AXIS,false)
        cam.height = [bb.height.to_f,bb.width.to_f/(390.0/235.0),1.0].max * 1.1
        cam
      elsif key == 'overview'
        helper.tt_iso_camera(bb)
      else
        helper.tt_ortho_camera(key.sub('cut_','').to_sym,bb)
      end
    end
    def prepare_scenes(model,job,o)
      snapshot = helper.tt_capture_model_state(model)
      # Capture ALL rendering keys, including section fills/colors omitted by old exporter.
      snapshot[:render] = {}
      model.rendering_options.each { |k,v| snapshot[:render][k] = v }
      original_style = model.styles.selected_style
      original_shadows = model.shadow_info['DisplayShadows']
      visibility = helper.tt_scope_visibility_state(model)
      scenes = {}
      model.start_operation('TRẦN TUẤN · Scene hồ sơ kỹ thuật',true)
      begin
        planes = if o['views'].any? { |k| k.start_with?('cut_') }
                   helper.tt_ensure_section_planes_for_job(model,job[:bounds],o['cut_mm'],job)
                 else {}; end
        helper.tt_apply_scope_visibility(model,job[:roots])
        o['views'].each do |key|
          section = key.start_with?('cut_')
          model.entities.active_section_plane = section ? planes.fetch(key.to_sym) : nil
          model.active_view.camera = camera(key,job[:bounds])
          material = key == 'overview' || o['render'] == 'Hybrid'
          profile(model.rendering_options,section,material)
          model.shadow_info['DisplayShadows'] = false unless key == 'overview'
          # Stable ownership attributes: rerun updates our scene, never overwrites a user's scene by name.
          owner = "#{job[:key]}:#{key}"
          page = model.pages.find { |p| p.get_attribute('TT_LayoutTechnical','owner') == owner }
          page ||= model.pages.add("#{job[:name]}_#{VIEWS[key]}")
          page.set_attribute('TT_LayoutTechnical','owner',owner)
          page.name = "#{job[:name]}_#{VIEWS[key]}"
          page.use_camera = true
          page.use_shadow_info = true
          page.use_rendering_options = true
          page.use_section_planes = true
          page.use_hidden = true
          page.use_hidden_objects = true if page.respond_to?(:use_hidden_objects=)
          page.use_hidden_layers = true
          page.include_in_animation = false
          page.update
          profile(page.rendering_options,section,material)
          scenes[key] = helper.tt_scene_layout_index(model,page)
        end
        helper.tt_restore_scope_visibility(visibility)
        model.styles.selected_style = original_style
        model.shadow_info['DisplayShadows'] = original_shadows
        helper.tt_restore_model_state(model,snapshot)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      ensure
        helper.tt_restore_scope_visibility(visibility)
        model.styles.selected_style = original_style
        model.shadow_info['DisplayShadows'] = original_shadows
        helper.tt_restore_model_state(model,snapshot)
      end
      scenes
    end
    def text(doc,layer,page,value,x,y,w,h,size=10,bold=false)
      value = value.to_s
      e = Layout::FormattedText.new(value,Geom::Bounds2d.new(x/25.4,y/25.4,w/25.4,h/25.4))
      style = e.style(0)
      style.font_family = 'Arial'
      style.font_size = size.to_f
      style.text_bold = bold
      style.text_color = helper.dark
      e.apply_style(style,0,value.length)
      page ? doc.add_entity(e,layer,page) : doc.add_entity(e,layer)
      e
    end
    def autotext(doc,name,type)
      doc.auto_text_definitions.find { |a| a.name == name } || doc.auto_text_definitions.add(name,type)
    end
    def build_document(job,path,scenes,o)
      doc = Layout::Document.new
      helper.setup_a3(doc)
      doc.object_snap_enabled = true
      doc.grid_snap_enabled = false
      doc.render_mode_override = Layout::SketchUpModel::NO_OVERRIDE if doc.respond_to?(:render_mode_override=)
      models = doc.layers.first
      models.name = 'Đồ gỗ'
      notes = doc.layers.add('Chú thích')
      dims = doc.layers.add('Dim')
      title = doc.layers.add('Khung tên',true)
      stats_layer = doc.layers.add('Thống kê')
      project = autotext(doc,'Project Name',Layout::AutoTextDefinition::TYPE_CUSTOM_TEXT)
      project.custom_text = o['project']
      number = autotext(doc,'PageNumber',Layout::AutoTextDefinition::TYPE_PAGE_NUMBER)
      number.start_index = 1
      number.start_page = doc.pages.first
      # Shared title block updates on every page through AutoText.
      border = Layout::Rectangle.new(Geom::Bounds2d.new(10/25.4,10/25.4,400/25.4,277/25.4))
      style = border.style
      style.solid_filled = false
      style.pattern_filled = false
      style.stroked = true
      style.stroke_width = 0.5
      border.style = style
      doc.add_entity(border,title)
      text(doc,title,nil,'TRẦN TUẤN NỘI THẤT',15,264,140,7,11,true)
      text(doc,title,nil,project.tag,15,274,265,8,11,true)
      text(doc,title,nil,"A3 · mm · Trang #{number.tag}",290,274,108,8,10)
      o['views'].each_with_index do |key,i|
        page = i.zero? ? doc.pages.first : doc.pages.add(VIEWS[key])
        page.name = format('%02d · %s',i+1,VIEWS[key])
        viewport = Layout::SketchUpModel.new(path,Geom::Bounds2d.new(15/25.4,25/25.4,390/25.4,235/25.4))
        viewport.current_scene = scenes.fetch(key)
        viewport.display_background = false
        viewport.render_mode = key == 'overview' || o['render'] == 'Hybrid' ? Layout::SketchUpModel::HYBRID_RENDER : Layout::SketchUpModel::VECTOR_RENDER
        if key != 'overview'
          raise "Scene #{VIEWS[key]} chưa phải hình chiếu song song." if viewport.perspective?
          viewport.scale = 1.0/denominator(key,o)
        end
        viewport.preserve_scale_on_resize = true
        viewport.line_weight = 0.35
        doc.add_entity(viewport,models,page)
        viewport.render if viewport.render_needed?
        ratio = key == 'overview' ? 'Phối cảnh — không dùng đo tỷ lệ' : "Tỷ lệ 1:#{format('%g',denominator(key,o))}"
        text(doc,notes,page,"#{job[:name]} · #{VIEWS[key]}",15,13,275,9,13,true)
        text(doc,notes,page,ratio,295,13,108,9,10)
      end
      if o['stats']
        # Existing table helper: use shared AutoText footer, suppress its old footer/title overlap.
        job[:stats][:rows].each_slice(20).with_index do |rows,i|
          page = doc.pages.add("Thống kê #{i+1}")
          text(doc,notes,page,'THỐNG KÊ CHI TIẾT',15,13,300,9,13,true)
          helper.add_stats_table(doc,stats_layer,page,rows)
        end
      end
      doc.layers.active = dims
      doc.set_attribute('TT_LayoutTechnical','options',JSON.generate(o))
      doc.set_attribute('TT_LayoutTechnical','source',path)
      doc
    end
    def run(action,o)
      helper.ensure_layout_api! unless action == 'scenes'
      jobs = check_jobs(o)
      model = Sketchup.active_model
      path = model.path.to_s
      if action == 'preview'
        folder = Dir.mktmpdir('TT_Layout_')
        target = File.join(folder,'Xem_truoc_A3.pdf')
      elsif action != 'scenes'
        ext = action == 'pdf' ? 'pdf' : 'layout'
        base = action == 'template' ? 'TT_MAU_A3' : 'TT_HO_SO_A3'
        target = UI.savepanel('Lưu hồ sơ A3',path.empty? ? nil : File.dirname(path),"#{base}.#{ext}")
        return report('Đã hủy xuất.') unless target
        target += ".#{ext}" unless File.extname(target).downcase == ".#{ext}"
      end
      path = helper.ensure_model_saved(model)
      return report('Đã hủy lưu mô hình.') unless path
      outputs = []
      scene_sets = jobs.map { |job| prepare_scenes(model,job,o) }
      raise 'Không lưu được các Scene vào SKP.' unless model.save
      return report("Đã lưu Scene cho #{jobs.length} bộ tủ vào SKP.") if action == 'scenes'
      jobs.each_with_index do |job,i|
        report("Đang dựng #{i+1}/#{jobs.length}: #{job[:name]}…")
        doc = build_document(job,path,scene_sets[i],o)
        ext = %w[pdf preview].include?(action) ? 'pdf' : 'layout'
        output = helper.tt_output_path(target,job,i,jobs.length,ext)
        if ext == 'pdf'
          doc.export(output,compress_images:true,compress_quality:o['quality']/100.0)
        else
          # Save using current host format; never request a newer format than installed LayOut.
          doc.save(output)
        end
        raise "Không tạo được tệp: #{output}" unless File.file?(output) && File.size(output)>0
        outputs << output
      end
      message = "Đã xuất #{outputs.length} tệp:\n#{outputs.join("\n")}"
      message += "\nMở file trong LayOut → File → Save As Template để đăng ký mẫu. Công trình sau tạo Scene cùng bộ góc nhìn, Relink SKP rồi kiểm tra lại Scene/tỷ lệ và liên kết Dim." if action == 'template'
      message += "\nPDF đã nén ảnh; chưa hỗ trợ xuất lớp PDF/linearization qua API. Lớp Dim/Chú thích/Đồ gỗ được giữ trong file .layout." if ext == 'pdf'
      report(message)
      helper.open_local_file(outputs.first) if action == 'preview'
    rescue StandardError => e
      suffix = outputs && !outputs.empty? ? "\nĐã tạo trước khi lỗi:\n#{outputs.join("\n")}" : ''
      raise "#{e.message}#{suffix}"
    end
    def html
      <<~'HTML'
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{font:14px Arial,sans-serif;margin:0;background:#f4f6f8;color:#253443}header{background:#173d4a;color:white;padding:20px 24px}h1{font-size:21px;margin:0 0 7px}main{padding:18px 24px}.card{background:white;border:1px solid #dce3e8;border-radius:9px;padding:16px;margin-bottom:14px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}label{display:block}input:not([type=checkbox]),select{display:block;width:100%;padding:8px;border:1px solid #bccbd4;border-radius:5px;margin-top:5px}.views{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}button{border:0;border-radius:5px;padding:10px 13px;background:#156a7a;color:white;cursor:pointer}button.secondary{background:#e3ecf1;color:#253443}button:disabled{opacity:.5;cursor:wait}.buttons{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}small,p{line-height:1.5}.muted{color:#617281}#status{white-space:pre-wrap;padding:12px;border-radius:6px;background:#e9f1f4;overflow-wrap:anywhere}.error{color:#a32929}summary{cursor:pointer;font-weight:bold}h2{font-size:16px;margin:0 0 12px}
      </style></head><body><header><h1>Hồ sơ LayOut A3</h1>Scene riêng · Giữ tỷ lệ · Khung tên tự động</header><main>
      <form id="form"><div class="card"><h2>Công trình & tỷ lệ</h2><label>Tên công trình<input id="project" maxlength="160"></label><div class="grid" style="margin-top:12px">
      <label>Mặt bằng / mặt đứng — tỷ lệ 1:<input id="scale" type="number" min="1" max="500" step="any" list="ratios" required></label>
      <label>Mặt cắt / chi tiết — tỷ lệ 1:<input id="cut_scale" type="number" min="1" max="500" step="any" list="ratios" required></label>
      <datalist id="ratios"><option value="5"><option value="10"><option value="20"><option value="25"><option value="50"></datalist>
      <label>Vị trí cắt vào từ mép (mm)<input id="cut_mm" type="number" min="0.1" max="5000" step="any" required></label>
      <label>Nét kỹ thuật<select id="render"><option>Vector</option><option>Hybrid</option></select></label></div>
      <p class="muted">A3 ngang, 420 × 297 mm. Hình chiếu song song và Preserve Scale luôn bật. Nếu mô hình vượt khung, công cụ báo để bạn chọn lại tỷ lệ.</p></div>
      <div class="card"><h2>Mỗi góc nhìn một trang</h2><div id="views" class="views"></div><p><label><input id="stats" type="checkbox"> Kèm bảng thống kê ván</label></p><small>Chọn Group/Component ngoài model trước khi xuất. Không chọn gì: lấy các cụm trong model. Hướng trước theo −Y, trên theo +Z của hệ trục model.</small></div>
      <div class="card"><h2>In & PDF</h2><div class="grid"><label>Độ phân giải<select disabled><option>High · 300 DPI</option></select></label><label>Chất lượng ảnh nén (%)<input id="quality" type="number" min="50" max="100" required></label></div>
      <p class="muted">Phối cảnh dùng Hybrid. Nét Vector giữ sắc khi phóng to. File LayOut có các lớp Đồ gỗ, Dim, Chú thích, Khung tên và Thống kê.</p>
      <small>Xuất lớp PDF và Optimize for Web: chưa có trong API LayOut; PDF ở đây nén ảnh, không cam kết giữ lớp hoặc mở tức thì.</small></div>
      <div class="buttons"><button type="button" class="secondary" onclick="run('check')">Kiểm tra vùng chọn</button><button type="button" class="secondary" onclick="run('save')">Lưu cấu hình</button><button type="button" class="secondary" onclick="run('scenes')">Tạo / cập nhật Scene</button></div>
      <div class="buttons"><button type="button" onclick="run('layout')">Xuất LayOut</button><button type="button" onclick="run('preview')">Xem trước PDF thật</button><button type="button" onclick="run('pdf')">Xuất PDF</button><button type="button" onclick="run('template')">Tạo file mẫu A3</button></div></form>
      <div id="status" role="status">Sẵn sàng.</div><details class="card" style="margin-top:14px"><summary>Dim liên kết, cập nhật công trình & dùng mẫu</summary>
      <p>Object Snap đã bật. Trong LayOut chọn lớp Dim, dùng Dimension và bắt hai đầu trực tiếp lên cạnh/đỉnh viewport. Không gõ đè số đo. Sau khi sửa và lưu SKP, dùng Update Reference; kiểm tra liên kết nếu đã xóa/tạo lại hình học.</p>
      <p>Đổi tên công trình tại Document Setup → Auto-Text → Project Name. PageNumber tự chạy. In PDF ở Actual Size / 100% để giữ tỷ lệ.</p>
      <p>Tạo file mẫu A3 → mở trong LayOut → Save As Template. Với công trình khác, tạo Scene trước rồi Relink SKP; kiểm tra lại Scene tương ứng và Dim. Thời gian cập nhật phụ thuộc độ nặng mô hình.</p>
      <p>Section Fills chỉ kín khi hình học tại mặt cắt tạo được đường bao kín. Không tự sửa hình học tủ. Các kích thước Dim do bạn đặt trong LayOut, công cụ chưa tự tạo Dim.</p></details></main>
      <script>
      const labels={top:'Mặt bằng',front:'Mặt đứng ngoài',left:'Mặt bên trái',right:'Mặt bên phải',cut_front:'Mặt cắt thùng trước',cut_left:'Mặt cắt thùng trái',cut_right:'Mặt cắt thùng phải',overview:'Phối cảnh 3D'};
      Object.keys(labels).forEach(k=>{const l=document.createElement('label'),c=document.createElement('input');c.type='checkbox';c.dataset.view=k;l.appendChild(c);l.appendChild(document.createTextNode(' '+labels[k]));document.getElementById('views').appendChild(l)});
      function receive(o){['project','scale','cut_scale','cut_mm','render','quality'].forEach(k=>document.getElementById(k).value=o[k]);document.getElementById('stats').checked=o.stats;document.querySelectorAll('[data-view]').forEach(c=>c.checked=o.views.includes(c.dataset.view))}
      function payload(){const o={};['project','scale','cut_scale','cut_mm','render','quality'].forEach(k=>o[k]=document.getElementById(k).value);o.stats=document.getElementById('stats').checked;o.views=Array.from(document.querySelectorAll('[data-view]:checked')).map(c=>c.dataset.view);return o}
      function report(t,e){const s=document.getElementById('status');s.textContent=t;s.className=e?'error':''}
      function setBusy(b){document.querySelectorAll('button').forEach(e=>e.disabled=b)}
      function run(a){if(!document.getElementById('form').reportValidity())return;setBusy(true);report('Đang xử lý…');try{sketchup.run(a,JSON.stringify(payload()))}catch(e){setBusy(false);report(e.message,true)}}
      document.getElementById('form').addEventListener('submit',e=>e.preventDefault());sketchup.ready();
      </script></body></html>
      HTML
    end
  end
  module LayoutStats
    class << self
      def show; LayoutTechnical.show; end
    end
  end
end
