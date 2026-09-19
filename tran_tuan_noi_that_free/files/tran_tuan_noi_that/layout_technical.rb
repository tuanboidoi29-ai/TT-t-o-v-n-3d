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
    DEFAULTS = {'drawing'=>'Hồ sơ tủ','scope'=>'selected','detail_dims'=>true,'title_font'=>13.0,'xray_views'=>(VIEWS.keys - ['overview']),'project'=>'','scale'=>20.0,'cut_scale'=>20.0,'render'=>'Vector',
                'cut_mm'=>20.0,'quality'=>90.0,'overview_style'=>'','pdf_mode'=>'fast','stats'=>true,'stats_font'=>14.0,
                'dimensions'=>true,'dim_offset'=>12.0,'dim_font'=>10.0,
                'views'=>VIEWS.keys}.freeze
    def helper; LayoutStats; end
    def normalize(data)
      raise 'Dữ liệu cài đặt không hợp lệ.' unless data.is_a?(Hash)
      out = DEFAULTS.merge(data.select { |k,_| DEFAULTS.key?(k) })
      %w[scale cut_scale cut_mm quality dim_offset dim_font stats_font title_font].each do |key|
        out[key] = Float(out[key])
        raise "Thông số #{key} không hợp lệ." unless out[key].finite?
      end
      %w[scale cut_scale].each { |k| raise 'Mẫu số tỷ lệ phải từ 1 đến 500.' unless out[k].between?(1,500) }
      raise 'Vị trí cắt phải từ 0,1 đến 5000 mm.' unless out['cut_mm'].between?(0.1,5000)
      raise 'Chất lượng nén phải từ 50 đến 100%.' unless out['quality'].between?(50,100)
      raise 'Chế độ PDF không hợp lệ.' unless %w[fast print].include?(out['pdf_mode'])
      raise 'Chọn Vector hoặc Hybrid.' unless %w[Vector Hybrid].include?(out['render'])
      raise 'Chọn ít nhất một góc nhìn.' unless out['views'].is_a?(Array) && !out['views'].empty?
      raise 'Góc nhìn không hợp lệ.' unless (out['views'] - VIEWS.keys).empty?
      out['views'] = VIEWS.keys.select { |k| out['views'].include?(k) }
      raise 'Phạm vi quét không hợp lệ.' unless %w[selected all].include?(out['scope'])
      raise 'Danh sách X-ray không hợp lệ.' unless out['xray_views'].is_a?(Array) && (out['xray_views']-VIEWS.keys).empty?
      out['xray_views'] = VIEWS.keys.select { |k| k != 'overview' && out['xray_views'].include?(k) }
      out['drawing'] = out['drawing'].to_s.strip[0,100]
      out['drawing'] = 'Hồ sơ tủ' if out['drawing'].empty?
      out['detail_dims'] = out['detail_dims'] == true
      raise 'Cỡ chữ tiêu đề phải từ 10 đến 18 pt.' unless out['title_font'].between?(10,18)
      out['overview_style'] = out['overview_style'].to_s
      out['project'] = out['project'].to_s.strip[0,160]
      raise 'Khoảng cách DIM phải từ 5 đến 20 mm trên giấy.' unless out['dim_offset'].between?(5,20)
      raise 'Cỡ chữ DIM phải từ 6 đến 18 pt.' unless out['dim_font'].between?(6,18)
      raise 'Cỡ chữ thống kê phải từ 12 đến 18 pt.' unless out['stats_font'].between?(12,18)
      out['dimensions'] = out['dimensions'] == true
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
      File.join(base, 'TranTuanNoiThat', 'layout_a3_v189_settings.json')
    end
    def settings
      @config_warning = nil
      return normalize(JSON.parse(File.read(config_path, encoding: 'UTF-8'))) if File.file?(config_path)
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
      when 'excel'
        export_excel(options)
      when 'preview'
        start_safe_preview(options)
      when 'save'
        persist(options)
        report('Đã lưu cấu hình cho lần xuất sau.')
      when 'check'
        report(check_jobs(options).map { |j| "#{j[:name]}: #{j[:stats][:total_pieces]} chi tiết — vừa khung ở tỷ lệ đã chọn." }.join("\n"))
      when 'layout','pdf','template','scenes'
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
      @busy = false
      @model = Sketchup.active_model
      @dialog = UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN · HỒ SƠ LAYOUT A3',
        preferences_key:'TranTuanNoiThat.LayoutTechnical189',scrollable:true,resizable:true,
        width:1180,height:820,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(html)
      @dialog.add_action_callback('ready') do |_c|
        begin
          send_state
        rescue StandardError => e
          @dialog.execute_script("receive(#{JSON.generate(normalize({}))})") if @dialog
          report("Không nạp được cấu hình cũ; dùng mặc định. #{e.message}",true)
        end
      end
      @dialog.add_action_callback('run') do |_c, action, json|
        if @busy
          report('Đang xử lý thao tác trước. Nếu đang xem trước, bấm Dừng dựng để kết thúc.')
          next
        end
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
      @dialog.add_action_callback('refresh_styles') do |_c|
        send_styles if !@busy && Sketchup.active_model == @model
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
      send_styles(o['overview_style'])
      @dialog.execute_script("receive(#{JSON.generate(o)})")
      report(@config_warning, true) if @config_warning
    end
    def send_styles(selected=nil)
      names = @model.styles.map { |style| style.name.to_s }.uniq.sort
      @dialog.execute_script("receiveStyles(#{JSON.generate(names)},#{JSON.generate(selected)})") if @dialog
    end
    def check_overview_style(model,options)
      return unless options['views'].include?('overview')
      name=options['overview_style'].to_s
      return if name.empty? || name == '__current__'
      style=model.styles.find { |item| item.name.to_s == name }
      raise "Style '#{name}' không còn trong model. Bấm Làm mới Styles rồi chọn lại." unless style
      if model.styles.active_style_changed && model.styles.selected_style != style
        raise 'Style hiện tại có chỉnh sửa chưa lưu. Trong bảng Styles của SketchUp, cập nhật Style trước khi chuyển sang Style khác.'
      end
    end
    def apply_overview_style(model,options)
      name = options['overview_style'].to_s
      if name.empty?
        profile(model.rendering_options,false,true,false)
        overview_profile(model.rendering_options)
      elsif name != '__current__'
        style = model.styles.find { |item| item.name.to_s == name }
        raise "Style '#{name}' không còn trong model. Bấm Làm mới Styles rồi chọn lại." unless style
        model.styles.selected_style = style unless model.styles.selected_style == style
      end
      # Keep appearance from the selected Style; only remove drafting overlays/cuts.
      values={'DisplaySectionCuts'=>false,'DisplaySectionPlanes'=>false,
              'DisplaySketchAxes'=>false,'DisplayInstanceAxes'=>false,
              'DisplayDims'=>false,'DisplayText'=>false,'HideConstructionGeometry'=>true}
      keys=model.rendering_options.keys
      values.each { |key,value| model.rendering_options[key]=value if keys.include?(key) }
    end
    def report(message,error=false)
      message = "#{message}\nModel mới đã được lưu nền tại: #{@auto_model_path}\nDùng File → Save As khi muốn đổi nơi lưu model." if @auto_model_path
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
      reserve = o['detail_dims'] ? detail_outer_offset(o)+o['dim_font']*25.4/72.0+6.0 : o['dimensions'] ? o['dim_offset'] + o['dim_font'] * 25.4 / 72.0 + 4.0 : 10.0
      available_w = 390.0 - reserve * 2
      available_h = 235.0 - reserve * 2
      return nil if width/d <= available_w && height/d <= available_h
      minimum = [width/available_w,height/available_h].max.ceil
      "#{VIEWS[key]} không vừa vùng vẽ A3 ở 1:#{format('%g',d)} (#{(width/d).round(1)} × #{(height/d).round(1)} mm). Chọn tỷ lệ 1:#{minimum} hoặc nhỏ hơn, hoặc chỉ chọn cụm/chi tiết cần xuất."
    end
    def export_jobs(model,options)
      source = options['scope'] == 'all' ? model.entities.to_a : model.selection.to_a
      roots = source.select { |e| e.valid? && helper.container?(e) }
      raise 'Chưa chọn Group/Component. Chọn tủ trong model hoặc đổi phạm vi sang Quét tất cả.' if roots.empty?
      # Each selected parent produces its own document, including all nested boards.
      roots.each_with_index.map do |root,i|
        name = helper.tt_scope_name(root,i+1)
        {roots:[root],name:name,key:helper.tt_entity_id(root).to_s,index:i+1,
         stats:helper.tt_stats_for_roots([root],name)}
      end
    end
    def detail_parts(roots,edge_limit=200000)
      parts=[]
      edge_count=0
      visit = lambda do |entity,parent,path|
        return unless entity.valid? && helper.container?(entity)
        return if entity.hidden? || (entity.respond_to?(:layer) && !entity.layer.visible?)
        tr = parent * entity.transformation
        entities = helper.child_entities(entity)
        return unless entities
        children = entities.to_a.select { |e| e.valid? && helper.container?(e) }
        faces = entities.grep(Sketchup::Face)
        unless faces.empty?
          edge_count += entities.grep(Sketchup::Edge).length
          raise 'Phạm vi có quá nhiều cạnh để đặt DIM chi tiết. Chọn từng cụm tủ nhỏ hơn hoặc tắt DIM chi tiết.' if edge_count > edge_limit
          edges = entities.grep(Sketchup::Edge).map { |e| [e.start.position.transform(tr),e.end.position.transform(tr)] }
          points = edges.flatten.uniq { |point| [point.x,point.y,point.z] }
          parts << {points:points,edges:edges,path:path+[entity]} unless points.empty?
        end
        children.each { |child| visit.call(child,tr,path+[entity]) }
      end
      roots.each { |root| visit.call(root,Geom::Transformation.new,[]) }
      parts
    end
    def check_jobs(o)
      model = Sketchup.active_model
      raise 'Thoát chế độ sửa Group/Component trước khi xuất để Scene lưu đúng phạm vi.' if model.active_path && !model.active_path.empty?
      jobs = export_jobs(model,o)
      raise 'Chọn Group/Component chứa tủ hoặc tấm ván trước khi xuất.' if jobs.empty?
      jobs.each do |job|
        job[:bounds] = helper.tt_scope_bounds_for_roots(model,job[:roots])
        job[:detail_parts] = detail_parts(job[:roots]) if o['detail_dims'] && o['views'].any? { |key| key == 'front' || key.start_with?('cut_') }
        o['views'].each do |key|
          error = fit_error(key,job[:bounds],o)
          raise "#{job[:name]}: #{error}" if error
        end
      end
      jobs
    end
    def profile(options,section,material,xray=false)
      values = {'DisplaySectionCuts'=>section,'DisplaySectionPlanes'=>false,
        'SectionCutFilled'=>section,'SectionCutDrawEdges'=>true,
        'SectionDefaultFillColor'=>Sketchup::Color.new(0,0,0),
        'SectionDefaultCutColor'=>Sketchup::Color.new(0,0,0),
        'ModelTransparency'=>xray,'MaterialTransparency'=>true,'DrawBackEdges'=>xray,'DrawHidden'=>false,
        'DrawGround'=>false,'DrawHorizon'=>false,'DisplaySketchAxes'=>false,
        'DisplayWatermarks'=>false,'DisplayFog'=>false,'EdgeType'=>0,
        'DrawSilhouettes'=>false,'DrawLineEnds'=>false,'ExtendLines'=>false,
        'EdgeDisplayMode'=>1,'EdgeColorMode'=>0,'ForegroundColor'=>Sketchup::Color.new(0,0,0),
        'BackgroundColor'=>Sketchup::Color.new(255,255,255),
        'FaceFrontColor'=>Sketchup::Color.new(255,255,255),
        'FaceBackColor'=>Sketchup::Color.new(255,255,255),
        'Texture'=>material,'RenderMode'=>(material || xray) ? 2 : 1}
      keys = options.keys
      values.each { |k,v| options[k] = v if keys.include?(k) }
      %w[ROPDrawHiddenGeometry ROPDrawHiddenObjects].each { |k| options[k] = false if keys.include?(k) }
      raise 'SketchUp không hỗ trợ Section Fills.' if section && !keys.include?('SectionCutFilled')
    end
    def capture_overview_camera(model,options)
      @overview_camera_data = nil
      return unless options['views'].include?('overview')
      view = model.active_view
      source = view.camera
      if source.is_2d?
        raise 'Góc nhìn Two-Point Perspective/Match Photo chưa được hỗ trợ. Chọn Camera → Perspective hoặc Parallel Projection rồi xuất lại.'
      end
      aspect = source.aspect_ratio.to_f
      aspect = view.vpwidth.to_f / [view.vpheight,1].max if aspect <= 0.0
      @overview_camera_data = {
        eye:source.eye.to_a,target:source.target.to_a,up:source.up.to_a,
        perspective:source.perspective?,aspect:aspect,
        fov:source.perspective? ? source.fov : nil,
        fov_vertical:source.perspective? ? source.fov_is_height? : nil,
        height:source.perspective? ? nil : source.height
      }
    end
    def overview_camera_from_data(data)
      cam = Sketchup::Camera.new(data[:eye],data[:target],data[:up],data[:perspective])
      cam.aspect_ratio = data[:aspect]
      if data[:perspective]
        fov = data[:fov]
        if cam.fov_is_height? != data[:fov_vertical]
          tangent = Math.tan(fov*Math::PI/360.0)
          tangent = data[:fov_vertical] ? tangent*data[:aspect] : tangent/data[:aspect]
          fov = 2.0*Math.atan(tangent)*180.0/Math::PI
        end
        cam.fov = fov
      else
        cam.height = data[:height]
      end
      cam
    end
    def camera(key,bb)
      if key == 'top'
        eye = bb.center.offset(Z_AXIS,[bb.diagonal.to_f*2.5,1000.0/25.4].max)
        cam = Sketchup::Camera.new(eye,bb.center,Y_AXIS,false)
        cam.height = [bb.height.to_f,bb.width.to_f/(390.0/235.0),1.0].max * 1.1
        cam
      elsif key == 'overview'
        raise 'Chưa lấy góc nhìn SketchUp. Bấm Xem trước hoặc Xuất lại.' unless @overview_camera_data
        overview_camera_from_data(@overview_camera_data)
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
          model.styles.selected_style = original_style unless model.styles.selected_style == original_style
          snapshot[:render].each { |name,value| model.rendering_options[name]=value }
          section = key.start_with?('cut_')
          model.entities.active_section_plane = section ? planes.fetch(key.to_sym) : nil
          model.active_view.camera = camera(key,job[:bounds])
          material = key == 'overview' || o['render'] == 'Hybrid'
          if key == 'overview'
            apply_overview_style(model,o)
          else
            profile(model.rendering_options,section,material,o['xray_views'].include?(key))
          end
          model.shadow_info['DisplayShadows'] = false unless key == 'overview'
          # Stable ownership attributes: rerun updates our scene, never overwrites a user's scene by name.
          owner = "#{job[:key]}:#{key}"
          page = model.pages.find { |p| p.get_attribute('TT_LayoutTechnical','owner') == owner }
          page ||= model.pages.add("#{o['drawing']}_#{job[:name]}_#{VIEWS[key]}")
          page.set_attribute('TT_LayoutTechnical','owner',owner)
          page.name = "#{o['drawing']}_#{job[:name]}_#{VIEWS[key]}"
          page.use_style = true
          page.use_camera = true
          page.use_shadow_info = true
          page.use_rendering_options = true
          page.use_section_planes = true
          page.use_hidden = true
          page.use_hidden_objects = true if page.respond_to?(:use_hidden_objects=)
          page.use_hidden_layers = true
          page.include_in_animation = false
          page.update
          if key == 'overview'
            model.rendering_options.each { |name,value| page.rendering_options[name]=value if page.rendering_options.keys.include?(name) }
          else
            profile(page.rendering_options,section,material,o['xray_views'].include?(key))
          end
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
    def paper_bounds(viewport, bounds)
      points = 8.times.map { |i| viewport.model_to_paper_point(bounds.corner(i)) }
      [points.map(&:x).min,points.map(&:y).min,points.map(&:x).max,points.map(&:y).max]
    end
    def focus_rectangle(box, padding_mm)
      left,top,right,bottom = box
      pad = padding_mm/25.4
      page_w = 420.0/25.4; page_h = 297.0/25.4
      left = [[left-pad,0.0].max,page_w].min
      top = [[top-pad,0.0].max,page_h].min
      right = [[right+pad,0.0].max,page_w].min
      bottom = [[bottom+pad,0.0].max,page_h].min
      return nil unless right>left && bottom>top
      [left/page_w,top/page_h,(right-left)/page_w,(bottom-top)/page_h]
    end
    def detail_outer_offset(options)
      8.0 + 4.0 * (options['dim_font']*25.4/72.0+2.0)
    end
    def clipped_detail_points(part,key,bounds,options)
      return part[:points] unless key.start_with?('cut_')
      offsets = helper.tt_v081_effective_offsets(bounds,options['cut_mm'])
      axis = key == 'cut_front' ? :y : :x
      coordinate = case key
                   when 'cut_front' then bounds.min.y + offsets[:front]
                   when 'cut_left' then bounds.min.x + offsets[:left]
                   else bounds.max.x - offsets[:right]
                   end
      sign = key == 'cut_right' ? -1.0 : 1.0
      distance = lambda { |point| (point.public_send(axis)-coordinate)*sign }
      points = part[:points].select { |point| distance.call(point) >= -0.000001 }
      part[:edges].each do |a,b|
        da=distance.call(a);db=distance.call(b)
        next unless da*db < 0.0
        t=da/(da-db)
        points << Geom::Point3d.new(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
      end
      points
    end
    def chain_segments(values,scale)
      tolerance=0.1/25.4*scale
      sorted=[]
      values.sort.each { |v| sorted<<v if sorted.empty? || v-sorted.last > tolerance }
      sorted.each_cons(2).to_a
    end
    def dimension_lanes(segments,scale,font)
      lanes=Array.new(4) { [] }
      segments.map do |a,b|
        mm=(b-a).abs/scale*25.4
        # Reserve label width, not only the short measured span (e.g. board thickness).
        width=[format('%.1f',mm).length*font*0.62/72.0+2.0/25.4,(b-a).abs].max
        center=(a+b)/2.0;range=[center-width/2,center+width/2]
        lane=lanes.index { |ranges| ranges.none? { |l,r| range[0]<r && range[1]>l } }
        unless lane
          lane=lanes.length
          lanes<<[]
        end
        lanes[lane]<<range
        [a,b,lane]
      end
    end
    def add_chain_dimension(doc,layer,page,viewport,a,b,ea,eb,options)
      dimension=Layout::LinearDimension.new(Geom::Point2d.new(*a),Geom::Point2d.new(*b),4.0/25.4)
      dimension.auto_scale=false
      dimension.scale=viewport.scale
      dimension.custom_text=false
      dimension.start_extent_point=Geom::Point2d.new(*ea)
      dimension.end_extent_point=Geom::Point2d.new(*eb)
      dimension.start_offset_length=1.0/25.4
      dimension.end_offset_length=1.0/25.4
      style=dimension.style
      style.set_dimension_units(Layout::Style::DECIMAL_MILLIMETERS,0.1)
      style.stroke_width=0.25
      style.stroke_color=helper.dark
      style.start_arrow_type=Layout::Style::ARROW_SLASH_RIGHT
      style.end_arrow_type=Layout::Style::ARROW_SLASH_RIGHT
      style.start_arrow_size=1.5;style.end_arrow_size=1.5
      ts=style.get_sub_style(Layout::Style::DIMENSION_TEXT)
      ts.font_family='Arial';ts.font_size=options['dim_font'];ts.text_color=helper.dark
      style.set_sub_style(Layout::Style::DIMENSION_TEXT,ts)
      dimension.style=style
      doc.add_entity(dimension,layer,page)
    end
    def add_detail_dimensions(doc,layer,page,viewport,job,key,box,options)
      xs=[];ys=[]
      Array(job[:detail_parts]).each do |part|
        points=clipped_detail_points(part,key,job[:bounds],options)
        next if points.empty?
        projected=points.map { |p| viewport.model_to_paper_point(p) }
        xs.concat([projected.map(&:x).min,projected.map(&:x).max])
        ys.concat([projected.map(&:y).min,projected.map(&:y).max])
      end
      @detail_batches={}
      count=0
      [[:x,xs],[:y,ys]].each do |axis,values|
        segments=chain_segments(values,viewport.scale)
        # One segment duplicates the total, so add chains only for subdivision.
        next if segments.length<2
        dimension_lanes(segments,viewport.scale,options['dim_font']).each do |a,b,lane|
          batch=lane/4
          spec=[axis,a,b,lane%4]
          if batch.zero?
            draw_detail_spec(doc,layer,page,viewport,box,options,spec)
          else
            (@detail_batches[batch] ||= []) << spec
          end
          count+=1
        end
      end
      count
    end
    def draw_detail_spec(doc,layer,page,viewport,box,options,spec)
      axis,a,b,lane=spec
      offset=(4.0+lane*(options['dim_font']*25.4/72.0+2.0))/25.4
      if axis == :x
        add_chain_dimension(doc,layer,page,viewport,[a,box[3]],[b,box[3]],
          [a,box[3]+offset],[b,box[3]+offset],options)
      else
        add_chain_dimension(doc,layer,page,viewport,[box[0],a],[box[0],b],
          [box[0]-offset,a],[box[0]-offset,b],options)
      end
    end
    def drawing_viewport(doc,layer,page,path,scene,key,options)
      viewport = Layout::SketchUpModel.new(path,Geom::Bounds2d.new(15/25.4,25/25.4,390/25.4,235/25.4))
      viewport.current_scene = scene
      viewport.display_background = key == 'overview' && !options['overview_style'].to_s.empty?
      viewport.render_mode = if options['_fast_pdf'] || (key == 'overview' && !options['overview_style'].to_s.empty?)
                               Layout::SketchUpModel::RASTER_RENDER
                             elsif key == 'overview' || options['render'] == 'Hybrid' || options['xray_views'].include?(key)
                               Layout::SketchUpModel::HYBRID_RENDER
                             else
                               Layout::SketchUpModel::VECTOR_RENDER
                             end
      if key != 'overview'
        raise "Scene #{VIEWS[key]} chưa phải hình chiếu song song." if viewport.perspective?
        viewport.scale = 1.0/denominator(key,options)
      end
      viewport.preserve_scale_on_resize = true
      viewport.line_weight = 0.35
      doc.add_entity(viewport,layer,page)
      # Fast PDF is rendered once by Document#export at output resolution.
      # model_to_paper_point uses the camera transform, not raster output.
      viewport.render if !options['_fast_pdf'] && viewport.render_needed?
      viewport
    end
    def add_total_dimensions(doc,layer,page,viewport,box,options)
      left,top,right,bottom = box
      offset = options['dim_offset']/25.4
      # Three-argument constructor only: the alignment overload requires LayOut 2026.
      # Aligned paper-space endpoints produce horizontal/vertical dimensions on 2021–2025.
      specs = [
        [[left,bottom],[right,bottom],[left,bottom+offset],[right,bottom+offset]],
        [[left,bottom],[left,top],[left-offset,bottom],[left-offset,top]]
      ]
      specs.each do |a,b,extent_a,extent_b|
        next if Math.hypot(a[0]-b[0],a[1]-b[1]) < 0.00001
        dim = Layout::LinearDimension.new(Geom::Point2d.new(*a),Geom::Point2d.new(*b),offset)
        dim.auto_scale = false
        dim.scale = viewport.scale
        dim.custom_text = false
        dim.start_extent_point = Geom::Point2d.new(*extent_a)
        dim.end_extent_point = Geom::Point2d.new(*extent_b)
        dim.start_offset_length = 1.0/25.4
        dim.end_offset_length = 1.0/25.4
        style = dim.style
        style.set_dimension_units(Layout::Style::DECIMAL_MILLIMETERS,0.1)
        style.stroke_width = 0.35
        style.stroke_color = helper.dark
        style.start_arrow_type = Layout::Style::ARROW_SLASH_RIGHT
        style.end_arrow_type = Layout::Style::ARROW_SLASH_RIGHT
        style.start_arrow_size = 2.0
        style.end_arrow_size = 2.0
        text_style = style.get_sub_style(Layout::Style::DIMENSION_TEXT)
        text_style.font_family = 'Arial'
        text_style.font_size = options['dim_font']
        text_style.text_color = helper.dark
        style.set_sub_style(Layout::Style::DIMENSION_TEXT,text_style)
        dim.style = style
        doc.add_entity(dim,layer,page)
      end
    end
    def stats_row_height(options)
      # Room for three lines plus cell padding; never shrink text to fit a page.
      options['stats_font'] * 25.4 / 72.0 * 3.3 + 2.0
    end
    def stats_rows_per_page(options)
      [(220.0 / stats_row_height(options)).floor - 1, 1].max
    end
    def add_readable_stats(doc,layer,page,rows,options)
      headers = ['STT','TÊN TẤM','DÀI','RỘNG','DÀY','SL','VẬT LIỆU','VÂN','m²']
      widths = [14,100,32,32,24,18,90,50,30]
      table = Layout::Table.new(Geom::Bounds2d.new(15/25.4,32/25.4,390/25.4,
        stats_row_height(options)*(rows.length+1)/25.4),rows.length+1,headers.length)
      widths.each_with_index { |width,i| table.get_column(i).width = width/25.4 }
      values = [headers] + rows.map do |row|
        [row[:stt].to_s,row[:name].to_s,helper.format_mm(row[:length_mm]),
         helper.format_mm(row[:width_mm]),helper.format_mm(row[:thickness_mm]),
         row[:qty].to_i.to_s,row[:material].to_s,row[:grain].to_s,format('%.3f',row[:area_m2].to_f)]
      end
      values.each_with_index do |cells,r|
        cells.each_with_index do |value,c|
          value = ' ' if value.empty?
          item = Layout::FormattedText.new(value,Geom::Point2d.new(0,0),Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
          style = item.style(0)
          style.font_family = 'Arial'
          style.font_size = options['stats_font']
          style.text_bold = r.zero?
          style.text_color = helper.dark
          item.apply_style(style,0,value.length)
          table[r,c].data = item
        end
      end
      doc.add_entity(table,layer,page)
    end
    def build_document(job,path,scenes,o)
      doc = Layout::Document.new
      @last_document_focus = []
      helper.setup_a3(doc)
      if o['_fast_pdf']
        doc.page_info.output_resolution = Layout::PageInfo::RESOLUTION_MEDIUM
        doc.page_info.display_resolution = Layout::PageInfo::RESOLUTION_MEDIUM
      end
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
        @detail_batches={}
        report("Đang dựng #{job[:name]} · góc #{i+1}/#{o['views'].length}: #{VIEWS[key]}…")
        viewport = drawing_viewport(doc,models,page,path,scenes.fetch(key),key,o)
        box = paper_bounds(viewport,job.fetch(:bounds))
        measured = o['detail_dims'] && (key == 'front' || key.start_with?('cut_'))
        detail_count = measured ? add_detail_dimensions(doc,dims,page,viewport,job,key,box,o) : 0
        total_options = detail_count > 0 ? o.merge('dim_offset'=>detail_outer_offset(o)) : o
        add_total_dimensions(doc,dims,page,viewport,box,total_options) if o['dimensions'] && key != 'overview'
        padding = detail_count > 0 ? detail_outer_offset(o)+o['dim_font']*25.4/72.0+6.0 : o['dimensions'] && key != 'overview' ? o['dim_offset'] + o['dim_font']*25.4/72.0 + 6.0 : 8.0
        @last_document_focus << focus_rectangle(box,padding)
        ratio = key == 'overview' ? 'Phối cảnh — không dùng đo tỷ lệ' : "Tỷ lệ 1:#{format('%g',denominator(key,o))}"
        text(doc,notes,page,"#{o['drawing']} · #{job[:name]} · #{VIEWS[key]}#{o['xray_views'].include?(key) ? ' · X-ray' : ''}",15,13,290,12,o['title_font'],true)
        text(doc,notes,page,ratio,310,13,95,9,10)
        unless @detail_batches.empty?
          text(doc,notes,page,"DIM còn lại: xem #{@detail_batches.length} trang chi tiết tiếp theo.",15,26,390,7,9)
          @detail_batches.sort.each do |batch,specs|
            extra_page=doc.pages.add("#{VIEWS[key]} · DIM chi tiết #{batch+1}")
            extra_view=drawing_viewport(doc,models,extra_page,path,scenes.fetch(key),key,o)
            extra_box=paper_bounds(extra_view,job.fetch(:bounds))
            specs.each { |spec| draw_detail_spec(doc,dims,extra_page,extra_view,extra_box,o,spec) }
            add_total_dimensions(doc,dims,extra_page,extra_view,extra_box,total_options) if o['dimensions']
            text(doc,notes,extra_page,"#{o['drawing']} · #{VIEWS[key]} · DIM chi tiết #{batch+1}",15,13,290,12,o['title_font'],true)
            text(doc,notes,extra_page,ratio,310,13,95,9,10)
            @last_document_focus << focus_rectangle(extra_box,padding)
          end
        end
      end
      if o['stats']
        job[:stats][:rows].each_slice(stats_rows_per_page(o)).with_index do |rows,i|
          page = doc.pages.add("Thống kê #{i+1}")
          text(doc,notes,page,'THỐNG KÊ CHI TIẾT · KÍCH THƯỚC mm',15,13,390,12,16,true)
          add_readable_stats(doc,stats_layer,page,rows,o)
          @last_document_focus << nil
        end
      end
      doc.layers.active = dims
      doc
    end
    def save_initial_model(model)
      raise 'Chỉ lưu nền tự động cho model chưa từng lưu.' unless model.path.to_s.empty?
      base = File.join(File.dirname(config_path),'ModelBackups')
      FileUtils.mkdir_p(base)
      # This is the model's first real save, not an expendable export temporary file.
      # Never remove this directory on success, cancellation, export failure or dialog close.
      folder = Dir.mktmpdir('TT_Model_',base)
      path = File.join(folder,'Model.skp')
      report('Model mới chưa từng lưu. Đang tạo bản SKP nền để xem trước/xuất PDF…')
      raise "Không lưu được model nền tại #{path}." unless model.save(path) && File.file?(path) && File.size(path)>0
      @auto_model_path = path
      path
    end
    def safe_filename(name)
      value = name.to_s.gsub(/[<>:"\\\/|?*\x00-\x1f]/,'_').sub(/[. ]+\z/,'')
      value.empty? ? 'TT_HO_SO_A3' : value
    end
    def run(action,o)
      check_overview_style(Sketchup.active_model,o)
      capture_overview_camera(Sketchup.active_model,o)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      o = o.merge('_fast_pdf' => (action == 'pdf' && o['pdf_mode'] == 'fast'))
      @auto_model_path = nil unless Sketchup.active_model.path.to_s == @auto_model_path
      helper.ensure_layout_api! unless action == 'scenes'
      report('Đang quét model và kiểm tra kích thước…')
      jobs = check_jobs(o)
      model = Sketchup.active_model
      path = model.path.to_s
      if action != 'preview' && action != 'scenes'
        ext = action == 'pdf' ? 'pdf' : 'layout'
        base = action == 'template' ? 'TT_MAU_A3' : safe_filename(o['drawing'])
        target = UI.savepanel('Lưu hồ sơ A3',path.empty? ? nil : File.dirname(path),"#{base}.#{ext}")
        return report('Đã hủy xuất.') unless target
        target += ".#{ext}" unless File.extname(target).downcase == ".#{ext}"
      end
      temporary_source = %w[pdf preview].include?(action)
      unless temporary_source
        path = helper.ensure_model_saved(model)
        return report('Đã hủy lưu mô hình.') unless path
      end
      outputs = []
      report('Đang tạo các góc nhìn và mặt cắt…')
      scene_sets = jobs.map { |job| prepare_scenes(model,job,o) }
      if temporary_source
        if model.path.to_s.empty?
          path = save_initial_model(model)
        else
          source_folder = Dir.mktmpdir('TT_PDF_Source_')
          path = File.join(source_folder,'model.skp')
          report('Đang chuẩn bị mô hình tạm để xuất…')
          raise 'Không tạo được bản sao tạm để xuất PDF.' unless model.save_copy(path) && File.file?(path) && File.size(path)>0
        end
      else
        raise 'Không lưu được các Scene vào SKP.' unless model.save
      end
      return report("Đã lưu Scene cho #{jobs.length} bộ tủ vào SKP.") if action == 'scenes'
      if action == 'preview'
        start_preview(jobs,path,scene_sets,o,source_folder)
        source_folder = nil # Ownership passes to the asynchronous preview until finish/cancel.
        return
      end
      jobs.each_with_index do |job,i|
        report("Đang dựng #{i+1}/#{jobs.length}: #{job[:name]}…")
        doc = build_document(job,path,scene_sets[i],o)
        ext = %w[pdf preview].include?(action) ? 'pdf' : 'layout'
        output = helper.tt_output_path(target,job,i,jobs.length,ext)
        if ext == 'pdf'
          report("Đang ghi PDF #{i+1}/#{jobs.length}…")
          doc.export(output,compress_images:true,compress_quality:o['quality']/100.0)
        else
          # Save using current host format; never request a newer format than installed LayOut.
          doc.save(output)
        end
        raise "Không tạo được tệp: #{output}" unless File.file?(output) && File.size(output)>0
        outputs << output
      end
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC)-started_at).round(1)
      message = "Đã xuất #{outputs.length} tệp trong #{elapsed} giây:\n#{outputs.join("\n")}"
      message += "\nPDF nhanh: mô hình dạng ảnh Medium; chữ, DIM và bảng thống kê giữ riêng." if o['_fast_pdf']
      message += "\nMở file trong LayOut → File → Save As Template để đăng ký mẫu. Công trình sau tạo Scene cùng bộ góc nhìn, Relink SKP rồi kiểm tra lại Scene/tỷ lệ và liên kết Dim." if action == 'template'
      message += "\nPDF đã nén ảnh; chưa hỗ trợ xuất lớp PDF/linearization qua API. Lớp Dim/Chú thích/Đồ gỗ được giữ trong file .layout." if ext == 'pdf'
      report(message)
    rescue StandardError => e
      suffix = outputs && !outputs.empty? ? "\nĐã tạo trước khi lỗi:\n#{outputs.join("\n")}" : ''
      raise "#{e.message}#{suffix}"
    ensure
      doc = nil
      remove_source_folder(source_folder) if source_folder
    end
    def remove_source_folder(folder)
      FileUtils.remove_entry(folder) if folder && File.directory?(folder)
    rescue StandardError => e
      puts "[TT temporary SKP cleanup] #{e.message}"
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
    def start_preview(jobs,path,scene_sets,options,source_folder=nil)
      finish_preview(nil)
      clear_preview_files
      @preview_dir = Dir.mktmpdir('TT_Layout_Preview_')
      @preview_pages = []
      @preview_state = {jobs:jobs,path:path,scenes:scene_sets,options:options,
                        job_index:0,page_index:0,doc:nil,source_folder:source_folder}
      @busy = true
      @dialog.execute_script('resetPreview();setBusy(true);previewRunning(true)') if @dialog
      report('Đang dựng bảng xem trước từ hồ sơ LayOut…')
      schedule_preview(@preview_state)
    end
    def schedule_preview(state)
      @preview_timer = UI.start_timer(0.05,false) { state[:safe] ? safe_preview_step(state) : preview_step(state) }
    end
    def finish_preview(message,error=false)
      UI.stop_timer(@preview_timer) if @preview_timer
      @preview_timer = nil
      state = @preview_state
      @preview_state = nil
      if state
        state[:doc] = nil
        remove_source_folder(state[:source_folder])
      end
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
        state[:focus] = @last_document_focus || []
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
        @preview_pages << {path:files.first,label:label,focus:Array(state[:focus])[page_index]}
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
      data = (page[:svg] ? 'data:image/svg+xml;base64,' + Base64.strict_encode64(page[:svg]) : 'data:image/png;base64,' + Base64.strict_encode64(File.binread(page[:path])))
      @dialog.execute_script("showPreviewImage(#{JSON.generate({id:index,label:page[:label],src:data,focus:page[:focus]})})") if @dialog
    rescue StandardError => e
      report("Không mở được trang xem trước: #{e.message}",true)
    end
    def xml_text(value)
      value.to_s.encode('UTF-8',invalid: :replace,undef: :replace,replace:'').gsub(/[\x00-\x08\x0b\x0c\x0e-\x1f]/,'').gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;')
    end
    # Preview avoids LayOut rendering. Overview temporarily captures the SketchUp viewport.
    def start_safe_preview(options)
      check_overview_style(@model,options)
      capture_overview_camera(@model,options)
      finish_preview(nil)
      clear_preview_files
      raise 'Thoát chế độ sửa Group/Component trước khi xem trước.' if @model.active_path
      jobs = export_jobs(@model,options)
      raise 'Chọn ít cụm hơn: xem trước tối đa 48 góc nhìn mỗi lần.' if jobs.length * options['views'].length > 48
      @preview_pages = []
      @preview_state = {safe:true,jobs:jobs,options:options,job_index:0,page_index:0}
      @busy = true
      @dialog.execute_script('resetPreview();setBusy(true);previewRunning(true)')
      schedule_preview(@preview_state)
    end
    def safe_preview_step(state)
      return unless @preview_state.equal?(state) && @dialog
      @preview_timer = nil
      raise 'Đã đổi mô hình; mở lại công cụ.' unless Sketchup.active_model == @model
      job = state[:jobs][state[:job_index]]
      return finish_preview("Đã dựng #{@preview_pages.length} trang xem trước. Phối cảnh 3D hiển thị màu và vật liệu model.") unless job
      o = state[:options]
      key = o['views'][state[:page_index]]
      unless key
        state[:job_index] += 1
        state[:page_index] = 0
        state[:parts] = nil
        state[:bounds] = nil
        schedule_preview(state)
        return
      end
      raise 'Đối tượng đã thay đổi. Hãy quét lại.' unless job[:roots].all?(&:valid?)
      state[:bounds] ||= helper.tt_scope_bounds_for_roots(@model,job[:roots])
      if key == 'overview'
        svg = overview_preview_svg(job,state[:bounds],o)
        label = "#{job[:name]} · Phối cảnh 3D · Style đã chọn"
      else
        state[:parts] ||= detail_parts(job[:roots],30000)
        svg = safe_preview_svg(job,state[:parts],state[:bounds],key,o)
        label = "#{job[:name]} · #{VIEWS[key]} · nét hình học"
      end
      id = @preview_pages.length
      @preview_pages << {svg:svg,label:label,focus:nil}
      @dialog.execute_script("addPreviewPage(#{JSON.generate({id:id,label:label})})")
      show_preview_page(0) if id.zero?
      state[:page_index] += 1
      report("Đã dựng #{@preview_pages.length} trang xem trước…")
      schedule_preview(state)
    rescue StandardError => e
      finish_preview("Không dựng được xem trước: #{e.message}",true)
    end
    def overview_profile(options)
      # Shaded faces with textures; material alpha remains enabled for glass.
      values = {'RenderMode'=>2,'Texture'=>true,'ModelTransparency'=>false,
                'MaterialTransparency'=>true,'DisplayColorByLayer'=>false,
                'DrawBackEdges'=>false,'DrawHidden'=>false,
                'DisplaySectionCuts'=>false,'DisplaySectionPlanes'=>false,
                'DisplaySketchAxes'=>false,'DisplayInstanceAxes'=>false,
                'DisplayDims'=>false,'DisplayText'=>false,'HideConstructionGeometry'=>true,
                'ROPDrawHiddenGeometry'=>false,'ROPDrawHiddenObjects'=>false}
      keys = options.keys
      values.each { |key,value| options[key]=value if keys.include?(key) }
    end
    def overview_preview_svg(job,bounds,options)
      model = @model
      view = model.active_view
      saved_style = model.styles.selected_style
      saved_camera = helper.tt_clone_camera(view.camera)
      saved_render = {}
      model.rendering_options.each { |key,value| saved_render[key]=value }
      visibility = helper.tt_scope_visibility_state(model)
      selection = model.selection.to_a
      @preview_dir ||= Dir.mktmpdir('TT_Overview_Preview_')
      path = File.join(@preview_dir,"overview_#{job[:index]}.png")
      operation_open = false
      begin
        model.start_operation('TT · Ảnh xem trước tạm',true)
        operation_open = true
        helper.tt_apply_scope_visibility(model,job[:roots])
        model.selection.clear
        apply_overview_style(model,options)
        cam = camera('overview',bounds)
        view.camera = cam
        view.refresh
        written = view.write_image(filename:path,width:1170,height:705,antialias:false,transparent:false)
        raise 'SketchUp không tạo được ảnh phối cảnh 3D.' unless written && File.file?(path) && File.size(path)>8
        raise 'Ảnh phối cảnh không hợp lệ.' unless File.binread(path,8)=="\x89PNG\r\n\x1a\n".b
        image_data=Base64.strict_encode64(File.binread(path))
      ensure
        begin
          model.abort_operation if operation_open
        ensure
          helper.tt_restore_scope_visibility(visibility)
          model.styles.selected_style=saved_style unless model.styles.selected_style == saved_style
          saved_render.each { |key,value| model.rendering_options[key]=value }
          view.camera=saved_camera
          model.selection.clear
          valid_selection=selection.select(&:valid?)
          model.selection.add(valid_selection) unless valid_selection.empty?
          view.invalidate
        end
      end
      label=xml_text("#{job[:name]} · PHỐI CẢNH 3D")
      "<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='1260' height='891' viewBox='0 0 1260 891'><rect width='1260' height='891' fill='white'/><rect x='20' y='20' width='1220' height='851' fill='none' stroke='#334155'/><text x='45' y='55' font-family='Arial' font-size='22' fill='#173d4a'>#{label}</text><image x='45' y='85' width='1170' height='705' xlink:href='data:image/png;base64,#{image_data}'/><text x='45' y='845' font-family='Arial' font-size='17'>Phối cảnh theo Style đã chọn · Không dùng đo tỷ lệ</text></svg>"
    end
    def safe_preview_svg(job,parts,bounds,key,o)
      project = lambda do |p|
        case key
        when 'top' then [p.x,-p.y]
        when 'left','cut_left' then [-p.y,-p.z]
        when 'right','cut_right' then [p.y,-p.z]
        when 'overview' then [(p.x-p.y)*0.70710678,(p.x+p.y)*0.40824829-p.z*0.81649658]
        else [p.x,-p.z]
        end
      end
      segments=[]
      axis=nil
      if key.start_with?('cut_')
        offsets=helper.tt_v081_effective_offsets(bounds,o['cut_mm'])
        axis=key == 'cut_front' ? :y : :x
        coordinate=key == 'cut_front' ? bounds.min.y+offsets[:front] : key == 'cut_left' ? bounds.min.x+offsets[:left] : bounds.max.x-offsets[:right]
        sign=key == 'cut_right' ? -1.0 : 1.0
      end
      parts.each do |part|
        part[:edges].each do |a,b|
          if axis
            da=(a.public_send(axis)-coordinate)*sign;db=(b.public_send(axis)-coordinate)*sign
            next if da<0 && db<0
            if da*db<0
              t=da/(da-db)
              point=Geom::Point3d.new(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
              if da < 0
                a = point
              else
                b = point
              end
            end
          end
          segments << [project.call(a),project.call(b)]
        end
      end
      points=segments.flatten(1)
      raise 'Không có hình học trong góc nhìn này.' if points.empty?
      xs=points.map(&:first);ys=points.map(&:last)
      minx,maxx=xs.minmax;miny,maxy=ys.minmax
      w=[maxx-minx,0.01].max;h=[maxy-miny,0.01].max
      scale=key == 'overview' ? [1000.0/w,600.0/h].min : 25.4*3.0/denominator(key,o)
      raise 'Hình vượt khung xem trước. Tăng mẫu số tỷ lệ.' if w*scale>1080 || h*scale>660
      ox=630-w*scale/2;oy=440-h*scale/2
      path=segments.map { |a,b| format('M%.2f %.2fL%.2f %.2f',ox+(a[0]-minx)*scale,oy+(a[1]-miny)*scale,ox+(b[0]-minx)*scale,oy+(b[1]-miny)*scale) }.join
      label=xml_text("#{job[:name]} · #{VIEWS[key]}")
      dimensions=''
      if o['dimensions'] && key!='overview'
        dimensions="<text x='630' y='810' text-anchor='middle'>Khung hình chiếu: #{(w*25.4).round(1)} × #{(h*25.4).round(1)} mm · 1:#{denominator(key,o)}</text>"
      end
      "<svg xmlns='http://www.w3.org/2000/svg' width='1260' height='891' viewBox='0 0 1260 891'><rect width='1260' height='891' fill='white'/><rect x='20' y='20' width='1220' height='851' fill='none' stroke='#334155'/><g font-family='Arial' font-size='19' fill='#173d4a'><text x='40' y='57'>#{label}</text><text x='40' y='850' font-size='14'>Xem trước nét hình học · có cạnh khuất · chưa mô phỏng DIM chi tiết / vật liệu / nét giao cắt</text>#{dimensions}</g><path d='#{path}' fill='none' stroke='#334155' stroke-width='1'/></svg>"
    end
    # Minimal standards-compliant XLSX package; no Excel installation required.
    def write_xlsx_zip(path,entries)
      require 'zlib'
      central=[]
      File.open(path,'wb') do |io|
        entries.each do |name,body|
          name=name.b;body=body.encode('UTF-8').b
          crc=Zlib.crc32(body);size=body.bytesize;offset=io.pos
          io.write([0x04034b50,20,0,0,0,33,crc,size,size,name.bytesize,0].pack('VvvvvvVVVvv'))
          io.write(name);io.write(body)
          central << [0x02014b50,20,20,0,0,0,33,crc,size,size,name.bytesize,0,0,0,0,0,offset].pack('VvvvvvvVVVvvvvvVV')+name
        end
        offset=io.pos;central.each { |entry| io.write(entry) };size=io.pos-offset
        io.write([0x06054b50,0,0,central.length,central.length,size,offset,0].pack('VvvvvVVv'))
      end
    end
    def export_excel(o)
      model=Sketchup.active_model
      raise 'Thoát chế độ sửa Group/Component trước khi thống kê.' if model.active_path
      jobs=export_jobs(model,o)
      target=UI.savepanel('Xuất thống kê ván Excel',nil,"#{safe_filename(o['drawing'])}_VAN.xlsx")
      return report('Đã hủy xuất Excel.') unless target
      target += '.xlsx' unless File.extname(target).downcase=='.xlsx'
      rows=[['Cụm tủ','STT','Tên ván','Dài (mm)','Rộng (mm)','Dày (mm)','Số lượng','Vật liệu','Hướng vân','Diện tích (m²)']]
      jobs.each do |job|
        job[:stats][:rows].each do |r|
          rows << [job[:name],r[:stt].to_i,r[:name],r[:length_mm].to_f,r[:width_mm].to_f,r[:thickness_mm].to_f,r[:qty].to_i,r[:material],r[:grain],r[:area_m2].to_f]
        end
      end
      raise 'Không tìm thấy ván để xuất.' if rows.length==1
      raise 'Quá nhiều dòng cho một bảng Excel.' if rows.length>1048575
      data=rows.each_with_index.map do |row,i|
        cells=row.each_with_index.map do |v,j|
          ref="#{(65+j).chr}#{i+1}"
          v.is_a?(Numeric) ? "<c r='#{ref}'><v>#{v}</v></c>" : "<c r='#{ref}' t='inlineStr'><is><t xml:space='preserve'>#{xml_text(v)}</t></is></c>"
        end.join
        "<row r='#{i+1}'>#{cells}</row>"
      end.join
      last=rows.length;total=last+1
      data += "<row r='#{total}'><c r='A#{total}' t='inlineStr'><is><t>TỔNG CỘNG</t></is></c><c r='G#{total}'><f>SUM(G2:G#{last})</f><v>#{rows.drop(1).sum { |r| r[6] }}</v></c><c r='J#{total}'><f>SUM(J2:J#{last})</f><v>#{rows.drop(1).sum { |r| r[9] }}</v></c></row>"
      ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
      entries={
        '[Content_Types].xml'=>%Q{<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>},
        '_rels/.rels'=>'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        'xl/workbook.xml'=>%Q{<workbook xmlns="#{ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Thống kê ván" sheetId="1" r:id="rId1"/></sheets><calcPr fullCalcOnLoad="1"/></workbook>},
        'xl/_rels/workbook.xml.rels'=>'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
        'xl/worksheets/sheet1.xml'=>%Q{<worksheet xmlns="#{ns}"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="28" customWidth="1"/><col min="2" max="2" width="8" customWidth="1"/><col min="3" max="3" width="32" customWidth="1"/><col min="4" max="10" width="18" customWidth="1"/></cols><sheetData>#{data}</sheetData><autoFilter ref="A1:J#{last}"/></worksheet>}
      }
      tmp=Tempfile.new(['TT_Excel_','.xlsx'],File.dirname(target));temp_path=tmp.path;tmp.close
      write_xlsx_zip(temp_path,entries)
      FileUtils.mv(temp_path,target,force:true)
      report("Đã xuất #{rows.length-1} dòng ván của #{jobs.length} cụm tủ:\n#{target}")
    ensure
      tmp.close! if tmp
    end
    def html
      <<~'HTML'
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{font:14px Arial,sans-serif;margin:0;background:#f4f6f8;color:#253443}header{background:#173d4a;color:white;padding:20px 24px}h1{font-size:21px;margin:0 0 7px}main{padding:18px 24px}.card{background:white;border:1px solid #dce3e8;border-radius:9px;padding:16px;margin-bottom:14px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}label{display:block}input:not([type=checkbox]),select{display:block;width:100%;padding:8px;border:1px solid #bccbd4;border-radius:5px;margin-top:5px}.views{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}button{border:0;border-radius:5px;padding:10px 13px;background:#156a7a;color:white;cursor:pointer}button.secondary{background:#e3ecf1;color:#253443}button:disabled{opacity:.5;cursor:wait}.buttons{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}small,p{line-height:1.5}.muted{color:#617281}#status{white-space:pre-wrap;padding:12px;border-radius:6px;background:#e9f1f4;overflow-wrap:anywhere}.error{color:#a32929}summary{cursor:pointer;font-weight:bold}h2{font-size:16px;margin:0 0 12px}
      .workspace{display:flex;flex-direction:column;gap:18px}.workspace>div{width:100%}.preview-panel{order:-1;width:100%;position:static}.preview-screen{background:#dce3e8;overflow:auto;height:500px;padding:14px;text-align:center}.preview-screen img{max-width:100%;height:auto;box-shadow:0 2px 12px #0003;display:block;margin:auto;background:white}.preview-screen img[hidden]{display:none}.preview-screen.zoom img{max-width:none;width:1600px}.preview-screen canvas{width:100%;max-width:100%;height:auto;display:block;background:white}.preview-screen canvas[hidden]{display:none}.preview-screen.zoom canvas{max-width:none;width:1600px}.preview-controls{display:flex;gap:6px;align-items:center;margin:10px 0}.preview-controls select{min-width:0;flex:1;margin:0}.preview-controls button{padding:9px}#preview-label{font-weight:bold;margin:8px 0}#preview-note{font-size:12px;color:#617281}@media(max-width:850px){.workspace{grid-template-columns:1fr}.preview-panel{position:static}.preview-screen{height:400px}}
      </style></head><body><header><h1>Hồ sơ LayOut A3 · 1.9.97</h1>Scene riêng · Giữ tỷ lệ · Khung tên tự động</header><main><div id="status" role="status" style="position:sticky;top:0;z-index:5;margin-bottom:12px">Sẵn sàng.</div><div class="workspace"><div>
      <form id="form"><div class="card"><h2>1. Phạm vi & tên bản vẽ</h2><label>Phạm vi quét<select id="scope"><option value="selected">Quét Group/Component đang chọn</option><option value="all">Quét tất cả Group/Component</option></select></label><label>Tên bản vẽ<input id="drawing" maxlength="100"></label><label>Tên công trình<input id="project" maxlength="160"></label><div class="grid" style="margin-top:12px">
      <label>Mặt bằng / mặt đứng — tỷ lệ 1:<input id="scale" type="number" min="1" max="500" step="any" list="ratios" required></label>
      <label>Mặt cắt / chi tiết — tỷ lệ 1:<input id="cut_scale" type="number" min="1" max="500" step="any" list="ratios" required></label>
      <datalist id="ratios"><option value="5"><option value="10"><option value="20"><option value="25"><option value="50"></datalist>
      <label>Vị trí cắt vào từ mép (mm)<input id="cut_mm" type="number" min="0.1" max="5000" step="any" required></label>
      <label>Nét kỹ thuật<select id="render"><option>Vector</option><option>Hybrid</option></select></label></div>
      <p class="muted">A3 ngang, 420 × 297 mm. Hình chiếu song song và Preserve Scale luôn bật. Nếu mô hình vượt khung, công cụ báo để bạn chọn lại tỷ lệ.</p></div>
      <div class="card"><h2>2. Góc nhìn & X-ray</h2><p>Mỗi góc nhìn một trang. Chọn X-ray bên cạnh góc nhìn cần xuyên thấu.</p><p class="muted"><b>Hướng phối cảnh: góc nhìn hiện tại trong SketchUp.</b> Xoay/zoom model trước khi bấm Xem trước hoặc Xuất PDF. Mỗi lần bấm sẽ lấy lại góc nhìn; không tự xoay hoặc zoom vừa cụm. Giữ Perspective/Parallel Projection. Khung A3 có thể thêm khoảng trống do khác tỷ lệ màn hình.</p><label>Style phối cảnh 3D<select id="overview_style"><option value="">Màu và vật liệu model</option><option value="__current__">Style đang hiển thị trong SketchUp</option></select></label><button type="button" class="secondary" onclick="sketchup.refresh_styles()">Làm mới Styles</button><p class="muted">Chọn Style trong model. Để thêm Style từ thư viện SketchUp, chọn nó trong Window → Default Tray → Styles rồi bấm Làm mới Styles. Style áp dụng cho phối cảnh xem trước và PDF; các trang kỹ thuật giữ thiết lập riêng.</p><div id="views" class="views"></div><p><label><input id="stats" type="checkbox"> Kèm bảng thống kê ván</label></p><label>Cỡ chữ bảng thống kê (pt)<input id="stats_font" type="number" min="12" max="18" step="1" required></label><p class="muted">Mặc định 14 pt. Chữ lớn hơn sẽ tự chia thêm trang.</p><small>Chọn Group/Component ngoài model trước khi xuất. Quét tất cả: mỗi Group/Component cha thành một hồ sơ riêng. Hướng trước theo −Y, trên theo +Z của hệ trục model.</small></div>
      <div class="card"><h2>3. DIM & cỡ chữ</h2><label><input id="detail_dims" type="checkbox"> DIM chia đoạn tại mặt trước và các mặt cắt</label><label><input id="dimensions" type="checkbox"> Tạo DIM tổng ngang / dọc</label><div class="grid" style="margin-top:12px"><label>Cách biên (mm trên giấy)<input id="dim_offset" type="number" min="5" max="20" step="any" required></label><label>Cỡ chữ DIM (pt)<input id="dim_font" type="number" min="6" max="18" step="any" required></label></div><label>Cỡ chữ tiêu đề (pt)<input id="title_font" type="number" min="10" max="18" step="any" required></label><p class="muted">DIM dày chữ sẽ tự tách sang trang chi tiết bổ sung, giữ đủ số đo và tỷ lệ. DIM chi tiết theo biên hình học tấm trong mặt chiếu; mặt cắt chỉ lấy phần còn lại sau cắt. DIM tổng theo biên khối, đơn vị mm, nằm trên lớp Dim. Khi sửa model, dựng/xuất lại để cập nhật DIM tự tạo. Trang phối cảnh không đặt DIM đo theo hình chiếu.</p></div>
      <div class="card"><h2>In & PDF</h2><p>Không cần chọn nơi lưu SKP trước. Model chưa từng lưu sẽ được lưu nền tự động, giữ lại trong ModelBackups; đường dẫn hiện ở thông báo. Model đã lưu dùng bản sao tạm. Chỉ chọn nơi lưu PDF.</p><div class="grid"><label>Chế độ xuất PDF<select id="pdf_mode"><option value="fast">PDF nhanh · ảnh mô hình Medium</option><option value="print">PDF chất lượng in · Vector/Hybrid, High</option></select></label><label>Chất lượng ảnh nén (%)<input id="quality" type="number" min="50" max="100" required></label></div>
      <p class="muted">PDF nhanh dùng ảnh mô hình Medium: nhẹ hơn nhưng nét mô hình giảm độ sắc khi phóng to. Chữ, DIM và thống kê giữ riêng; không bỏ trang hoặc số đo. Chất lượng in dùng Vector/Hybrid và High. File LayOut có các lớp Đồ gỗ, Dim, Chú thích, Khung tên và Thống kê.</p>
      <small>Xuất lớp PDF và Optimize for Web: chưa có trong API LayOut; PDF ở đây nén ảnh, không cam kết giữ lớp hoặc mở tức thì.</small></div>
      <div class="buttons"><button type="button" class="secondary" data-action="check">Quét / kiểm tra model</button><button type="button" class="secondary" data-action="save">Lưu cấu hình</button><button type="button" class="secondary" data-action="scenes">Tạo / cập nhật Scene</button></div>
      <div class="buttons"><button type="button" data-action="layout">Xuất LayOut</button><button type="button" data-action="preview">Xem trước hồ sơ</button><button type="button" data-action="pdf">Xuất PDF</button><button type="button" data-action="excel">Xuất thống kê Excel</button><button type="button" data-action="template">Tạo file mẫu A3</button></div></form>
      <details class="card" style="margin-top:14px"><summary>Dim liên kết, cập nhật công trình & dùng mẫu</summary>
      <p>Object Snap đã bật. Trong LayOut chọn lớp Dim, dùng Dimension và bắt hai đầu trực tiếp lên cạnh/đỉnh viewport. Không gõ đè số đo. Sau khi sửa và lưu SKP, dùng Update Reference; kiểm tra liên kết nếu đã xóa/tạo lại hình học.</p>
      <p>Đổi tên công trình tại Document Setup → Auto-Text → Project Name. PageNumber tự chạy. In PDF ở Actual Size / 100% để giữ tỷ lệ.</p>
      <p>Tạo file mẫu A3 → mở trong LayOut → Save As Template. Với công trình khác, tạo Scene trước rồi Relink SKP; kiểm tra lại Scene tương ứng và Dim. Thời gian cập nhật phụ thuộc độ nặng mô hình.</p>
      <p>Section Fills chỉ kín khi hình học tại mặt cắt tạo được đường bao kín. Không tự sửa hình học tủ. Công cụ tạo DIM tổng ngang/dọc từ biên khối. DIM tự tạo cần dựng/xuất lại khi model đổi; DIM chi tiết có thể đặt thêm trực tiếp trong LayOut bằng Object Snap.</p></details></div>
      <section class="card preview-panel"><h2>Bảng xem trước A3</h2><p id="preview-note">Phối cảnh 3D hiển thị mặt, màu và vật liệu của model; các mặt kỹ thuật dùng hình chiếu nét nhẹ.</p>
      <div class="preview-controls"><button class="preview-nav" onclick="movePage(-1)" title="Trang trước">◀</button><select class="preview-nav" id="preview-list" onchange="selectPage(this.value)" aria-label="Chọn trang"></select><button class="preview-nav" onclick="movePage(1)" title="Trang sau">▶</button></div>
      <div id="preview-label">Chưa có trang xem trước</div><div id="preview-screen" class="preview-screen"><img id="preview-image" alt="Bản vẽ A3" hidden><canvas id="preview-canvas" aria-label="Xem trước bản vẽ và kích thước" hidden></canvas></div>
      <div class="buttons"><button class="preview-nav secondary" onclick="focusPreview(true)">Gần đối tượng</button><button class="preview-nav secondary" onclick="focusPreview(false)">Toàn trang</button><button class="preview-nav secondary" onclick="zoomPreview(false)">Vừa khung</button><button class="preview-nav secondary" onclick="zoomPreview(true)">Phóng to</button><button id="cancel-preview" class="preview-nav secondary" onclick="sketchup.cancel_preview()" hidden>Dừng dựng</button></div>
      <small>Phối cảnh 3D theo Style đã chọn; chọn Màu và vật liệu model để xem có vật liệu, không X-ray. Các trang kỹ thuật xem trước bằng nét, chưa mô phỏng DIM chi tiết và nét giao mặt cắt. PDF dùng bộ dựng riêng.</small></section></div></main>
      <script>
      window.addEventListener('error',function(e){var box=document.getElementById('status');if(box){box.textContent='Lỗi giao diện: '+e.message;box.className='error'}});
      const labels={top:'Mặt bằng',front:'Mặt đứng ngoài',left:'Mặt bên trái',right:'Mặt bên phải',cut_front:'Mặt cắt thùng trước',cut_left:'Mặt cắt thùng trái',cut_right:'Mặt cắt thùng phải',overview:'Phối cảnh 3D'};
      Object.keys(labels).forEach(k=>{const l=document.createElement('label'),c=document.createElement('input');c.type='checkbox';c.dataset.view=k;l.appendChild(c);l.appendChild(document.createTextNode(' '+labels[k]));document.getElementById('views').appendChild(l);const xl=document.createElement('label'),xc=document.createElement('input');xc.type='checkbox';xc.dataset.xray=k;if(k==='overview'){xc.dataset.fixed='true';xc.disabled=true;}xl.appendChild(xc);xl.appendChild(document.createTextNode(k==='overview'?' Theo Style đã chọn':' X-ray'));document.getElementById('views').appendChild(xl)});
      let readyReceived=false;
      function receiveStyles(names,selected){const e=document.getElementById('overview_style'),old=selected==null?e.value:selected;e.textContent='';[['','Màu và vật liệu model'],['__current__','Style đang hiển thị trong SketchUp'],...names.map(n=>[n,n])].forEach(([v,t])=>{const opt=document.createElement('option');opt.value=v;opt.textContent=t;e.appendChild(opt)});if(old&&!['__current__',...names].includes(old)){const opt=document.createElement('option');opt.value=old;opt.textContent=old+' (không còn trong model)';e.appendChild(opt)}e.value=old||'';}
      function receive(o){readyReceived=true;o=Object.assign({},initialOptions,o);['project','scale','cut_scale','cut_mm','render','quality','dim_offset','dim_font','stats_font','drawing','scope','title_font','pdf_mode','overview_style'].forEach(k=>document.getElementById(k).value=o[k]);document.getElementById('stats').checked=o.stats;document.getElementById('dimensions').checked=o.dimensions;document.getElementById('detail_dims').checked=o.detail_dims;document.querySelectorAll('[data-xray]').forEach(c=>c.checked=c.dataset.xray!=='overview'&&o.xray_views.includes(c.dataset.xray));document.querySelectorAll('[data-view]').forEach(c=>c.checked=o.views.includes(c.dataset.view))}
      function payload(){const o={};['project','scale','cut_scale','cut_mm','render','quality','dim_offset','dim_font','stats_font','drawing','scope','title_font','pdf_mode','overview_style'].forEach(k=>o[k]=document.getElementById(k).value);o.stats=document.getElementById('stats').checked;o.dimensions=document.getElementById('dimensions').checked;o.detail_dims=document.getElementById('detail_dims').checked;o.xray_views=Array.from(document.querySelectorAll('[data-xray]:checked')).map(c=>c.dataset.xray);o.views=Array.from(document.querySelectorAll('[data-view]:checked')).map(c=>c.dataset.view);return o}
      function report(t,e){const s=document.getElementById('status');s.textContent=t;s.className=e?'error':''}
      function setBusy(b){document.querySelectorAll('#form button,#form input,#form select').forEach(e=>e.disabled=b);document.querySelectorAll('[data-fixed]').forEach(e=>e.disabled=true)}
      function run(a){
        try{
          const invalid=Array.from(document.querySelectorAll('#form input,#form select')).find(e=>!e.disabled&&e.willValidate&&!e.validity.valid);
          if(invalid){const label=invalid.closest('label');report('Kiểm tra '+(label?label.textContent.trim():invalid.id)+': '+invalid.validationMessage,true);invalid.focus();invalid.reportValidity();return}
          if(!window.sketchup||typeof window.sketchup.run!=='function'){report('Chưa kết nối được với SketchUp. Đóng bảng và mở lại công cụ.',true);return}
          const json=JSON.stringify(payload());
          setBusy(true);report('Đang xử lý…');window.sketchup.run(a,json);
        }catch(e){setBusy(false);report('Không thực hiện được: '+e.message,true)}
      }
      let previewPages=[],currentPage=-1,focusMode=true,currentFocus=null;
      function resetPreview(){previewPages=[];currentPage=-1;document.getElementById('preview-list').textContent='';const im=document.getElementById('preview-image');im.hidden=true;im.removeAttribute('src');document.getElementById('preview-canvas').hidden=true;currentFocus=null;document.getElementById('preview-label').textContent='Đang dựng trang…';document.getElementById('preview-note').textContent='Đang dựng hình chiếu nét nhẹ. Các trang xong trước có thể xem ngay.'}
      function previewRunning(b){document.getElementById('cancel-preview').hidden=!b;if(!b&&previewPages.length)document.getElementById('preview-note').textContent=previewPages.length+' trang đã dựng. Có thể chuyển trang và phóng to.'}
      function addPreviewPage(p){previewPages.push(p);const o=document.createElement('option');o.value=p.id;o.textContent=(p.id+1)+'. '+p.label;document.getElementById('preview-list').appendChild(o)}
      function selectPage(id){id=Number(id);if(!Number.isInteger(id)||id<0||id>=previewPages.length)return;currentPage=id;document.getElementById('preview-list').value=String(id);sketchup.preview_page(id)}
      function movePage(delta){if(!previewPages.length)return;selectPage(Math.max(0,Math.min(previewPages.length-1,currentPage+delta)))}
      function showPreviewImage(p){currentPage=p.id;document.getElementById('preview-list').value=String(p.id);document.getElementById('preview-label').textContent=p.label;const im=document.getElementById('preview-image');currentFocus=p.focus||null;im.onload=drawPreview;im.src=p.src;im.hidden=true;if(im.complete&&im.naturalWidth)drawPreview()}
      function cropRegion(w,h,f){if(!f||f.length!==4||!f.every(Number.isFinite))return [0,0,w,h];const x=Math.max(0,Math.min(1,f[0])),y=Math.max(0,Math.min(1,f[1])),rw=Math.max(0,Math.min(1-x,f[2])),rh=Math.max(0,Math.min(1-y,f[3]));return rw>0&&rh>0?[x*w,y*h,rw*w,rh*h]:[0,0,w,h]}
      function drawPreview(){const im=document.getElementById('preview-image'),c=document.getElementById('preview-canvas');if(!im.naturalWidth)return;const r=cropRegion(im.naturalWidth,im.naturalHeight,focusMode?currentFocus:null);c.width=Math.max(1,Math.round(r[2]));c.height=Math.max(1,Math.round(r[3]));c.getContext('2d').drawImage(im,...r,0,0,c.width,c.height);c.hidden=false}
      function focusPreview(b){focusMode=b;zoomPreview(false);drawPreview()}
      function zoomPreview(b){document.getElementById('preview-screen').classList.toggle('zoom',b)}
      document.getElementById('form').addEventListener('change',()=>{if(previewPages.length)document.getElementById('preview-note').textContent='Thông số đã đổi — bấm Xem trước hồ sơ để cập nhật ảnh.'});
      document.getElementById('form').addEventListener('submit' ,e=>e.preventDefault());
      const initialOptions={drawing:'Hồ sơ tủ',scope:'selected',title_font:13,detail_dims:true,xray_views:Object.keys(labels).filter(k=>k!=='overview'),project:'Công trình mới',scale:20,cut_scale:20,cut_mm:20,render:'Vector',quality:90,pdf_mode:'fast',overview_style:'',dim_offset:12,dim_font:10,stats_font:14,stats:true,dimensions:true,views:Object.keys(labels)};
      receive(initialOptions);readyReceived=false;
      let readyAttempts=0;
      function connectRuby(){
        if(readyReceived)return;
        readyAttempts++;
        try{if(window.sketchup&&typeof window.sketchup.ready==='function')window.sketchup.ready()}catch(e){report('Chưa nhận được cấu hình: '+e.message,true)}
        if(!readyReceived&&readyAttempts<4)setTimeout(connectRuby,500);
        else if(!readyReceived)report('Chưa nhận được cấu hình từ SketchUp. Đang dùng thông số mặc định; nếu nút vẫn không phản hồi, đóng bảng và mở lại công cụ.',true);
      }
      document.querySelectorAll('[data-action]').forEach(button=>button.addEventListener('click',()=>run(button.dataset.action)));
      connectRuby();
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
