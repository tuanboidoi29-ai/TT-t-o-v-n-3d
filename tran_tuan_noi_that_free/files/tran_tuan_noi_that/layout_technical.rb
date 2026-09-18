# encoding: UTF-8
# Native linked LayOut documents; SketchUp/LayOut 2021+.
require 'json'
require 'tmpdir'
require 'fileutils'
require 'tempfile'
require 'base64'
module TranTuanNoiThat
  module LayoutTechnical
    extend self
    @dialog.close if @dialog
    @dialog = nil
    @busy = false
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
    def config_path
      base = ENV['APPDATA'].to_s.strip
      if base.empty?
        home = ENV['USERPROFILE'].to_s.strip
        home = Dir.home if home.empty?
        base = File.join(home, '.config')
      end
      File.join(base, 'TranTuanNoiThat', 'layout_a3_settings.json')
    end
    def settings
      @config_warning = nil
      return normalize(JSON.parse(File.read(config_path, encoding: 'UTF-8'))) if File.file?(config_path)
      legacy = Sketchup.read_default('TranTuanNoiThat.LayoutTechnical','settings','').to_s
      return normalize(JSON.parse(legacy)) unless legacy.empty?
      normalize({})
    rescue StandardError => e
      @config_warning = "Không đọc được cấu hình cũ; đang dùng mặc định. #{e.message}"
      normalize({})
    end
    def persist(options)
      options = normalize(options)
      path = config_path
      FileUtils.mkdir_p(File.dirname(path))
      temp = Tempfile.new(['layout_a3_', '.json'], File.dirname(path))
      begin
        temp.binmode
        temp.write(JSON.pretty_generate(options).encode('UTF-8'))
        temp.flush
        temp.fsync
        temp.close
        saved = normalize(JSON.parse(File.read(temp.path, encoding: 'UTF-8')))
        raise 'Kiểm tra dữ liệu cấu hình thất bại.' unless saved == options
        # Same-directory rename keeps an existing valid configuration intact if writing fails.
        File.rename(temp.path, path)
        saved = normalize(JSON.parse(File.read(path, encoding: 'UTF-8')))
        raise 'Không xác minh được cấu hình đã lưu.' unless saved == options
        true
      ensure
        temp.close! if temp
      end
    rescue StandardError => e
      raise "Không lưu được cấu hình: #{e.message}"
    end
    def dispatch(action, options)
      @config_warning = nil
      case action
      when 'save'
        persist(options)
        report('Đã lưu cấu hình cho lần xuất sau.')
      when 'check'
        report(check_jobs(options).map { |j| "#{j[:name]}: #{j[:stats][:total_pieces]} chi tiết — vừa khung ở tỷ lệ đã chọn." }.join("\n"))
      when 'layout','pdf','preview','template','scenes'
        # Saving preferences is not a prerequisite for processing the current model.
        begin
          persist(options)
        rescue StandardError => e
          @config_warning = "Chưa lưu cấu hình cho lần sau; thao tác này vẫn dùng thông số đang nhập. #{e.message}"
        end
        run(action,options)
      else
        raise 'Thao tác không hợp lệ.'
      end
    end
    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @model = Sketchup.active_model
      @dialog = UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN · HỒ SƠ LAYOUT A3',
        preferences_key:'TranTuanNoiThat.LayoutTechnical',scrollable:true,resizable:true,
        width:1180,height:820,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(html)
      @dialog.add_action_callback('ready') { |_c| send_state }
      @dialog.add_action_callback('run') do |_c, action, json|
        next if @busy
        @busy = true
        begin
          raise 'Đã đổi mô hình. Đóng bảng và mở lại công cụ.' unless Sketchup.active_model == @model
          options = normalize(JSON.parse(json))
          dispatch(action,options)
        rescue StandardError => e
          report(e.message,true)
          puts "[TT LayOut] #{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}"
        ensure
          unless @preview_state
            @busy = false
            @dialog.execute_script('setBusy(false)') if @dialog
          end
        end
      end
      @dialog.add_action_callback('preview_page') { |_c, id| show_preview_page(id) }
      @dialog.add_action_callback('cancel_preview') { |_c| finish_preview('Đã dừng xem trước. Các trang đã dựng vẫn xem được.') }
      @dialog.set_on_closed do
        @dialog = nil
        finish_preview(nil)
        clear_preview_files
      end
      @dialog.show
    end
    def send_state
      o = settings
      o['project'] = File.basename(@model.path.to_s,'.skp') if o['project'].empty?
      o['project'] = 'Công trình mới' if o['project'].empty?
      @dialog.execute_script("receive(#{JSON.generate(o)})")
      report(@config_warning, true) if @config_warning
    end
    def report(message,error=false)
      message = "#{message}\n#{@config_warning}" if @config_warning && message != @config_warning
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
      doc
    end
    def run(action,o)
      helper.ensure_layout_api! unless action == 'scenes'
      jobs = check_jobs(o)
      model = Sketchup.active_model
      path = model.path.to_s
      if action != 'preview' && action != 'scenes'
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
      return start_preview(jobs,path,scene_sets,o) if action == 'preview'
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
    rescue StandardError => e
      suffix = outputs && !outputs.empty? ? "\nĐã tạo trước khi lỗi:\n#{outputs.join("\n")}" : ''
      raise "#{e.message}#{suffix}"
    end
    def clear_preview_files
      if @preview_dir && File.directory?(@preview_dir)
        FileUtils.remove_entry(@preview_dir)
      end
      @preview_dir = nil
      @preview_pages = []
    rescue StandardError => e
      puts "[TT LayOut preview cleanup] #{e.message}"
    end
    def start_preview(jobs,path,scene_sets,options)
      finish_preview(nil)
      clear_preview_files
      @preview_dir = Dir.mktmpdir('TT_Layout_Preview_')
      @preview_pages = []
      @preview_state = {jobs:jobs,path:path,scenes:scene_sets,options:options,
                        job_index:0,page_index:0,doc:nil}
      @busy = true
      @dialog.execute_script('resetPreview();setBusy(true);previewRunning(true)') if @dialog
      report('Đang dựng bảng xem trước từ hồ sơ LayOut…')
      schedule_preview(@preview_state)
    end
    def schedule_preview(state)
      @preview_timer = UI.start_timer(0.05,false) { preview_step(state) }
    end
    def finish_preview(message,error=false)
      UI.stop_timer(@preview_timer) if @preview_timer
      @preview_timer = nil
      @preview_state = nil
      @busy = false
      if @dialog
        @dialog.execute_script('setBusy(false);previewRunning(false)')
        report(message,error) if message
      end
    end
    def preview_step(state)
      return unless @preview_state.equal?(state) && @dialog
      @preview_timer = nil
      raise 'Đã đổi mô hình; hãy mở lại công cụ để xem trước.' unless Sketchup.active_model == @model
      index = state[:job_index]
      if index >= state[:jobs].length
        return finish_preview("Đã dựng #{@preview_pages.length} trang. Chọn trang bên phải để xem; ảnh xem trước 150 DPI, xuất PDF giữ High.")
      end
      job = state[:jobs][index]
      unless state[:doc]
        report("Đang dựng bộ #{index+1}/#{state[:jobs].length}: #{job[:name]}…")
        state[:doc] = build_document(job,state[:path],state[:scenes][index],state[:options])
        schedule_preview(state)
        return
      end
      doc = state[:doc]
      page_index = state[:page_index]
      if page_index >= doc.pages.length
        state[:doc] = nil
        state[:job_index] += 1
        state[:page_index] = 0
      else
        folder = File.join(@preview_dir,format('%03d_%03d',index,page_index))
        FileUtils.mkdir_p(folder)
        doc.export(File.join(folder,'page.png'),start_page:page_index,end_page:page_index,dpi:150)
        # LayOut can append the page name/index to the requested image filename.
        files = Dir.glob(File.join(folder,'**','*')).select { |f| File.file?(f) && File.extname(f).downcase == '.png' }
        raise "Không nhận được ảnh trang #{page_index+1}." unless files.length == 1
        raise 'LayOut trả về ảnh PNG không hợp lệ.' unless File.binread(files.first,8) == "\x89PNG\r\n\x1a\n".b
        label = "#{job[:name]} · #{doc.pages[page_index].name}"
        id = @preview_pages.length
        @preview_pages << {path:files.first,label:label}
        @dialog.execute_script("addPreviewPage(#{JSON.generate({id:id,label:label})})")
        show_preview_page(0) if id.zero?
        state[:page_index] += 1
        report("Đang dựng xem trước: #{@preview_pages.length} trang đã sẵn sàng.")
      end
      schedule_preview(state)
    rescue StandardError => e
      puts "[TT LayOut preview] #{e.class}: #{e.message}"
      finish_preview("Xem trước dừng: #{e.message}",true)
    end
    def show_preview_page(id)
      index = Integer(id)
      raise 'Trang xem trước không hợp lệ.' unless index >= 0 && @preview_pages && index < @preview_pages.length
      page = @preview_pages[index]
      data = 'data:image/png;base64,' + Base64.strict_encode64(File.binread(page[:path]))
      @dialog.execute_script("showPreviewImage(#{JSON.generate({id:index,label:page[:label],src:data})})") if @dialog
    rescue StandardError => e
      report("Không mở được trang xem trước: #{e.message}",true)
    end
    def html
      <<~'HTML'
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{font:14px Arial,sans-serif;margin:0;background:#f4f6f8;color:#253443}header{background:#173d4a;color:white;padding:20px 24px}h1{font-size:21px;margin:0 0 7px}main{padding:18px 24px}.card{background:white;border:1px solid #dce3e8;border-radius:9px;padding:16px;margin-bottom:14px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}label{display:block}input:not([type=checkbox]),select{display:block;width:100%;padding:8px;border:1px solid #bccbd4;border-radius:5px;margin-top:5px}.views{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}button{border:0;border-radius:5px;padding:10px 13px;background:#156a7a;color:white;cursor:pointer}button.secondary{background:#e3ecf1;color:#253443}button:disabled{opacity:.5;cursor:wait}.buttons{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}small,p{line-height:1.5}.muted{color:#617281}#status{white-space:pre-wrap;padding:12px;border-radius:6px;background:#e9f1f4;overflow-wrap:anywhere}.error{color:#a32929}summary{cursor:pointer;font-weight:bold}h2{font-size:16px;margin:0 0 12px}
      .workspace{display:grid;grid-template-columns:minmax(330px,420px) minmax(400px,1fr);gap:18px;align-items:start}.preview-panel{position:sticky;top:12px}.preview-screen{background:#dce3e8;overflow:auto;height:500px;padding:14px;text-align:center}.preview-screen img{max-width:100%;height:auto;box-shadow:0 2px 12px #0003;display:block;margin:auto;background:white}.preview-screen img[hidden]{display:none}.preview-screen.zoom img{max-width:none;width:1600px}.preview-controls{display:flex;gap:6px;align-items:center;margin:10px 0}.preview-controls select{min-width:0;flex:1;margin:0}.preview-controls button{padding:9px}#preview-label{font-weight:bold;margin:8px 0}#preview-note{font-size:12px;color:#617281}@media(max-width:850px){.workspace{grid-template-columns:1fr}.preview-panel{position:static}.preview-screen{height:400px}}
      </style></head><body><header><h1>Hồ sơ LayOut A3</h1>Scene riêng · Giữ tỷ lệ · Khung tên tự động</header><main><div class="workspace"><div>
      <form id="form"><div class="card"><h2>Công trình & tỷ lệ</h2><label>Tên công trình<input id="project" maxlength="160"></label><div class="grid" style="margin-top:12px">
      <label>Mặt bằng / mặt đứng — tỷ lệ 1:<input id="scale" type="number" min="1" max="500" step="any" list="ratios" required></label>
      <label>Mặt cắt / chi tiết — tỷ lệ 1:<input id="cut_scale" type="number" min="1" max="500" step="any" list="ratios" required></label>
      <datalist id="ratios"><option value="5"><option value="10"><option value="20"><option value="25"><option value="50"></datalist>
      <label>Vị trí cắt vào từ mép (mm)<input id="cut_mm" type="number" min="0.1" max="5000" step="any" required></label>
      <label>Nét kỹ thuật<select id="render"><option>Vector</option><option>Hybrid</option></select></label></div>
      <p class="muted">A3 ngang, 420 × 297 mm. Hình chiếu song song và Preserve Scale luôn bật. Nếu mô hình vượt khung, công cụ báo để bạn chọn lại tỷ lệ.</p></div>
      <div class="card"><h2>Mỗi góc nhìn một trang</h2><div id="views" class="views"></div><p><label><input id="stats" type="checkbox"> Kèm bảng thống kê ván</label></p><small>Chọn Group/Component ngoài model trước khi xuất. Không chọn gì: lấy các cụm trong model. Hướng trước theo −Y, trên theo +Z của hệ trục model.</small></div>
      <div class="card"><h2>In & PDF</h2><div class="grid"><label>Độ phân giải<select data-fixed="true" disabled><option>High · 300 DPI</option></select></label><label>Chất lượng ảnh nén (%)<input id="quality" type="number" min="50" max="100" required></label></div>
      <p class="muted">Phối cảnh dùng Hybrid. Nét Vector giữ sắc khi phóng to. File LayOut có các lớp Đồ gỗ, Dim, Chú thích, Khung tên và Thống kê.</p>
      <small>Xuất lớp PDF và Optimize for Web: chưa có trong API LayOut; PDF ở đây nén ảnh, không cam kết giữ lớp hoặc mở tức thì.</small></div>
      <div class="buttons"><button type="button" class="secondary" onclick="run('check')">Kiểm tra vùng chọn</button><button type="button" class="secondary" onclick="run('save')">Lưu cấu hình</button><button type="button" class="secondary" onclick="run('scenes')">Tạo / cập nhật Scene</button></div>
      <div class="buttons"><button type="button" onclick="run('layout')">Xuất LayOut</button><button type="button" onclick="run('preview')">Xem trước hồ sơ</button><button type="button" onclick="run('pdf')">Xuất PDF</button><button type="button" onclick="run('template')">Tạo file mẫu A3</button></div></form>
      <div id="status" role="status">Sẵn sàng.</div><details class="card" style="margin-top:14px"><summary>Dim liên kết, cập nhật công trình & dùng mẫu</summary>
      <p>Object Snap đã bật. Trong LayOut chọn lớp Dim, dùng Dimension và bắt hai đầu trực tiếp lên cạnh/đỉnh viewport. Không gõ đè số đo. Sau khi sửa và lưu SKP, dùng Update Reference; kiểm tra liên kết nếu đã xóa/tạo lại hình học.</p>
      <p>Đổi tên công trình tại Document Setup → Auto-Text → Project Name. PageNumber tự chạy. In PDF ở Actual Size / 100% để giữ tỷ lệ.</p>
      <p>Tạo file mẫu A3 → mở trong LayOut → Save As Template. Với công trình khác, tạo Scene trước rồi Relink SKP; kiểm tra lại Scene tương ứng và Dim. Thời gian cập nhật phụ thuộc độ nặng mô hình.</p>
      <p>Section Fills chỉ kín khi hình học tại mặt cắt tạo được đường bao kín. Không tự sửa hình học tủ. Các kích thước Dim do bạn đặt trong LayOut, công cụ chưa tự tạo Dim.</p></details></div>
      <section class="card preview-panel"><h2>Bảng xem trước A3</h2><p id="preview-note">Bấm Xem trước hồ sơ để dựng từng trang từ LayOut.</p>
      <div class="preview-controls"><button class="preview-nav" onclick="movePage(-1)" title="Trang trước">◀</button><select class="preview-nav" id="preview-list" onchange="selectPage(this.value)" aria-label="Chọn trang"></select><button class="preview-nav" onclick="movePage(1)" title="Trang sau">▶</button></div>
      <div id="preview-label">Chưa có trang xem trước</div><div id="preview-screen" class="preview-screen"><img id="preview-image" alt="Bản vẽ A3" hidden></div>
      <div class="buttons"><button class="preview-nav secondary" onclick="zoomPreview(false)">Vừa khung</button><button class="preview-nav secondary" onclick="zoomPreview(true)">Phóng to</button><button id="cancel-preview" class="preview-nav secondary" onclick="sketchup.cancel_preview()" hidden>Dừng dựng</button></div>
      <small>Ảnh xem trước 150 DPI. Thay đổi model hoặc thông số: bấm Xem trước hồ sơ để cập nhật. PDF xuất ở High.</small></section></div></main>
      <script>
      const labels={top:'Mặt bằng',front:'Mặt đứng ngoài',left:'Mặt bên trái',right:'Mặt bên phải',cut_front:'Mặt cắt thùng trước',cut_left:'Mặt cắt thùng trái',cut_right:'Mặt cắt thùng phải',overview:'Phối cảnh 3D'};
      Object.keys(labels).forEach(k=>{const l=document.createElement('label'),c=document.createElement('input');c.type='checkbox';c.dataset.view=k;l.appendChild(c);l.appendChild(document.createTextNode(' '+labels[k]));document.getElementById('views').appendChild(l)});
      function receive(o){['project','scale','cut_scale','cut_mm','render','quality'].forEach(k=>document.getElementById(k).value=o[k]);document.getElementById('stats').checked=o.stats;document.querySelectorAll('[data-view]').forEach(c=>c.checked=o.views.includes(c.dataset.view))}
      function payload(){const o={};['project','scale','cut_scale','cut_mm','render','quality'].forEach(k=>o[k]=document.getElementById(k).value);o.stats=document.getElementById('stats').checked;o.views=Array.from(document.querySelectorAll('[data-view]:checked')).map(c=>c.dataset.view);return o}
      function report(t,e){const s=document.getElementById('status');s.textContent=t;s.className=e?'error':''}
      function setBusy(b){document.querySelectorAll('#form button,#form input,#form select').forEach(e=>e.disabled=b);document.querySelectorAll('[data-fixed]').forEach(e=>e.disabled=true)}
      function run(a){if(!document.getElementById('form').reportValidity())return;setBusy(true);report('Đang xử lý…');try{sketchup.run(a,JSON.stringify(payload()))}catch(e){setBusy(false);report(e.message,true)}}
      let previewPages=[],currentPage=-1;
      function resetPreview(){previewPages=[];currentPage=-1;document.getElementById('preview-list').textContent='';const im=document.getElementById('preview-image');im.hidden=true;im.removeAttribute('src');document.getElementById('preview-label').textContent='Đang dựng trang…';document.getElementById('preview-note').textContent='Đang dựng từ hồ sơ LayOut. Các trang xong trước có thể xem ngay.'}
      function previewRunning(b){document.getElementById('cancel-preview').hidden=!b;if(!b&&previewPages.length)document.getElementById('preview-note').textContent=previewPages.length+' trang đã dựng. Có thể chuyển trang và phóng to.'}
      function addPreviewPage(p){previewPages.push(p);const o=document.createElement('option');o.value=p.id;o.textContent=(p.id+1)+'. '+p.label;document.getElementById('preview-list').appendChild(o)}
      function selectPage(id){id=Number(id);if(!Number.isInteger(id)||id<0||id>=previewPages.length)return;currentPage=id;document.getElementById('preview-list').value=String(id);sketchup.preview_page(id)}
      function movePage(delta){if(!previewPages.length)return;selectPage(Math.max(0,Math.min(previewPages.length-1,currentPage+delta)))}
      function showPreviewImage(p){currentPage=p.id;document.getElementById('preview-list').value=String(p.id);document.getElementById('preview-label').textContent=p.label;const im=document.getElementById('preview-image');im.src=p.src;im.hidden=false}
      function zoomPreview(b){document.getElementById('preview-screen').classList.toggle('zoom',b)}
      document.getElementById('form').addEventListener('change',()=>{if(previewPages.length)document.getElementById('preview-note').textContent='Thông số đã đổi — bấm Xem trước hồ sơ để cập nhật ảnh.'});
      document.getElementById('form').addEventListener('submit' ,e=>e.preventDefault());sketchup.ready();
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
