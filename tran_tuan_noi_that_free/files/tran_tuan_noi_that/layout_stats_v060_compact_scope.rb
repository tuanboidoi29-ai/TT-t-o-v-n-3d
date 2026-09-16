# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.6.0
# SCOPE MODE + MULTI MODE + COMPACT A3 + SHARP PREVIEW
# - Có selection: chỉ lấy đúng vùng chọn. Nếu nhiều Group cha độc lập dạng MODE => mỗi Group 1 bộ Layout.
# - Không selection: quét toàn context; nếu có nhiều Group MODE top-level => mỗi MODE 1 bộ Layout, vẫn bao phủ toàn bộ context.
# - Preview từng bước, fit theo đúng bounds MODE, 720x510 antialias để line nét hơn nhưng không render dồn.
# - Bố cục A3 tối ưu: Trang 1 Tổng thể + X-Ray; Trang 2 Mặt trước + Trái/Phải; Trang 3 Mặt cắt trước + Cắt Trái/Phải; sau đó thống kê.
# - Export nhiều MODE: một lần xuất tạo nhiều file .layout/.pdf cùng thư mục, mỗi MODE một file.

require 'digest'
require 'json'
require 'tmpdir'
require 'base64'

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.6.0'.freeze

    V060_PREVIEW_W = 720 unless const_defined?(:V060_PREVIEW_W, false)
    V060_PREVIEW_H = 510 unless const_defined?(:V060_PREVIEW_H, false)
    V060_STEP_DELAY = 0.10 unless const_defined?(:V060_STEP_DELAY, false)

    class << self
      def tt_entity_id(entity)
        entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
      rescue StandardError
        entity.object_id
      end

      def tt_scope_name(entity, index = nil)
        name = part_name(entity).to_s.strip
        name = "MODE #{index || 1}" if name.empty?
        name
      rescue StandardError
        "MODE #{index || 1}"
      end

      def tt_safe_filename(text)
        value = text.to_s.strip
        value = 'MODE' if value.empty?
        value = value.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '') rescue value
        value = value.tr('đĐ', 'dD')
        value.gsub(/[\\\/:*?"<>|]+/, '_').gsub(/\s+/, '_')[0, 60]
      end

      def tt_module_root?(entity, model = Sketchup.active_model)
        return false unless container?(entity) && entity.valid?
        ents = child_entities(entity)
        return false unless ents
        children = ents.to_a.select { |child| container?(child) && child.valid? }
        return false if children.empty?

        tr = (model.edit_transform || Geom::Transformation.new) * entity.transformation
        dims = dimensions_mm(entity, tr)
        return false if dims && board_dimensions?(dims) && board_name_hint?(entity)
        true
      rescue StandardError
        false
      end

      def tt_stats_for_roots(roots, scope_label)
        model = Sketchup.active_model
        records = []
        base_tr = model.edit_transform || Geom::Transformation.new
        roots.each do |entity|
          scan_entity(entity, base_tr, nil, records)
        end

        grouped = {}
        records.each do |record|
          key = [
            record[:name].to_s,
            record[:length_mm].round(1),
            record[:width_mm].round(1),
            record[:thickness_mm].round(1),
            record[:material].to_s,
            record[:grain].to_s
          ]
          row = grouped[key]
          if row
            row[:qty] += 1
            row[:area_m2] += record[:area_m2]
          else
            grouped[key] = record.merge(qty: 1)
          end
        end

        rows = grouped.values.sort_by do |r|
          [r[:material].to_s.downcase, r[:name].to_s.downcase, -r[:length_mm], -r[:width_mm]]
        end
        rows.each_with_index { |row, index| row[:stt] = index + 1 }

        {
          rows: rows,
          total_pieces: rows.inject(0) { |sum, row| sum + row[:qty].to_i },
          total_types: rows.length,
          total_area_m2: rows.inject(0.0) { |sum, row| sum + row[:area_m2].to_f },
          scope: scope_label,
          source_count: records.length,
          generated_at: Time.now.strftime('%d/%m/%Y %H:%M')
        }
      end

      def tt_layout_jobs
        model = Sketchup.active_model
        selected = model.selection.to_a.select { |e| container?(e) && e.valid? }
        jobs = []

        if !selected.empty?
          if selected.length > 1 && selected.all? { |e| tt_module_root?(e, model) }
            selected.each_with_index do |root, index|
              name = tt_scope_name(root, index + 1)
              jobs << { roots: [root], name: name, scope: "MODE ĐANG CHỌN · #{name}" }
            end
          else
            name = selected.length == 1 ? tt_scope_name(selected.first, 1) : 'VÙNG ĐANG CHỌN'
            jobs << { roots: selected, name: name, scope: "ĐỐI TƯỢNG ĐANG CHỌN · #{name}" }
          end
        else
          roots = model.active_entities.to_a.select { |e| container?(e) && e.valid? }
          modules = roots.select { |e| tt_module_root?(e, model) }

          if modules.length >= 2
            modules.each_with_index do |root, index|
              name = tt_scope_name(root, index + 1)
              jobs << { roots: [root], name: name, scope: "MODE #{index + 1} · #{name}" }
            end
            leftovers = roots.reject { |e| modules.include?(e) }
            unless leftovers.empty?
              jobs << { roots: leftovers, name: 'PHẦN CÒN LẠI', scope: 'CONTEXT · PHẦN CÒN LẠI' }
            end
          else
            jobs << { roots: roots, name: 'TOÀN BỘ CONTEXT', scope: 'TOÀN BỘ CONTEXT HIỆN TẠI' }
          end
        end

        jobs.each_with_index do |job, index|
          job[:index] = index + 1
          job[:key] = job[:roots].map { |r| tt_entity_id(r) }.join('_')
          job[:stats] = tt_stats_for_roots(job[:roots], job[:scope])
        end
        jobs.reject { |job| job[:roots].empty? || job[:stats][:rows].empty? }
      end

      def tt_aggregate_job_stats(jobs)
        records = []
        jobs.each do |job|
          job[:stats][:rows].each do |row|
            row[:qty].to_i.times do
              records << row.merge(qty: 1, area_m2: row[:area_m2].to_f / [row[:qty].to_i, 1].max)
            end
          end
        end

        grouped = {}
        records.each do |record|
          key = [record[:name], record[:length_mm].round(1), record[:width_mm].round(1),
                 record[:thickness_mm].round(1), record[:material], record[:grain]]
          if grouped[key]
            grouped[key][:qty] += 1
            grouped[key][:area_m2] += record[:area_m2].to_f
          else
            grouped[key] = record.merge(qty: 1)
          end
        end
        rows = grouped.values.sort_by { |r| [r[:material].to_s.downcase, r[:name].to_s.downcase] }
        rows.each_with_index { |row, index| row[:stt] = index + 1 }
        now = Time.now.strftime('%d/%m/%Y %H:%M')
        {
          rows: rows,
          total_pieces: rows.inject(0) { |sum, row| sum + row[:qty].to_i },
          total_types: rows.length,
          total_area_m2: rows.inject(0.0) { |sum, row| sum + row[:area_m2].to_f },
          scope: jobs.length > 1 ? "#{jobs.length} MODE / KHỐI" : (jobs.first ? jobs.first[:scope] : '—'),
          source_count: rows.length,
          generated_at: now,
          mode_count: jobs.length
        }
      end

      def build_stats
        jobs = tt_layout_jobs
        @layout_jobs = jobs
        tt_aggregate_job_stats(jobs)
      end

      def tt_scope_bounds_for_roots(model, roots)
        return model.bounds if roots.nil? || roots.empty?
        bb = Geom::BoundingBox.new
        roots.each do |entity|
          eb = entity.bounds
          next unless eb && eb.valid?
          8.times { |i| bb.add(eb.corner(i)) }
        end
        bb.valid? ? bb : model.bounds
      rescue StandardError
        model.bounds
      end

      def tt_scope_visibility_state(model)
        model.active_entities.to_a.each_with_object([]) do |entity, out|
          next unless entity.respond_to?(:hidden?) && entity.respond_to?(:hidden=)
          out << [entity, entity.hidden?]
        end
      end

      def tt_apply_scope_visibility(model, roots)
        keep = roots.map { |e| tt_entity_id(e) }
        model.active_entities.to_a.each do |entity|
          next unless entity.respond_to?(:hidden=)
          entity.hidden = !keep.include?(tt_entity_id(entity))
        rescue StandardError
          nil
        end
      end

      def tt_restore_scope_visibility(states)
        Array(states).each do |entity, hidden|
          entity.hidden = hidden if entity && entity.valid? && entity.respond_to?(:hidden=)
        rescue StandardError
          nil
        end
      end

      def tt_iso_camera(bb)
        center = bb.center
        direction = Geom::Vector3d.new(1.0, -1.25, 0.82)
        direction.normalize!
        distance = [bb.diagonal.to_f * 2.8, 800.mm.to_f].max
        eye = center.offset(direction, distance)
        camera = Sketchup::Camera.new(eye, center, Z_AXIS, false)
        camera.height = [bb.diagonal.to_f * 0.78, 120.mm.to_f].max
        camera
      end

      def tt_apply_sharp_edges(model)
        options = model.rendering_options
        {
          'JitterEdges' => false,
          'DrawDepthCue' => false,
          'DrawLineEnds' => false,
          'DrawProfilesOnly' => false,
          'EdgeDisplayMode' => 0
        }.each { |key, value| options[key] = value rescue nil }
      end

      def tt_ensure_section_planes_for_job(model, bb, cut_offset_mm, job)
        offset = cut_offset_mm.to_f / 25.4
        x_off = [offset, bb.width.to_f * 0.45].min
        y_off = [offset, bb.height.to_f * 0.45].min
        center = bb.center
        suffix = Digest::SHA1.hexdigest(job[:key].to_s)[0, 8]

        points = {
          cut_front: Geom::Point3d.new(center.x, bb.min.y + y_off, center.z),
          cut_left: Geom::Point3d.new(bb.min.x + x_off, center.y, center.z),
          cut_right: Geom::Point3d.new(bb.max.x - x_off, center.y, center.z)
        }
        normals = {
          cut_front: Geom::Vector3d.new(0, -1, 0),
          cut_left: Geom::Vector3d.new(-1, 0, 0),
          cut_right: Geom::Vector3d.new(1, 0, 0)
        }

        out = {}
        points.each do |key, point|
          name = "TT_LAYOUT_#{suffix}_#{key.to_s.upcase}"
          plane = model.entities.grep(Sketchup::SectionPlane).find { |p| p.valid? && p.name.to_s == name }
          unless plane
            plane = model.entities.add_section_plane(point, normals[key])
            plane.name = name if plane.respond_to?(:name=)
          end
          begin
            plane.set_plane([point, normals[key]])
          rescue StandardError
            plane.erase! if plane.valid?
            plane = model.entities.add_section_plane(point, normals[key])
            plane.name = name if plane.respond_to?(:name=)
          end
          plane.hidden = true if plane.respond_to?(:hidden=)
          out[key] = plane
        end
        out
      end

      def tt_preview_tasks(model, job)
        bounds = tt_scope_bounds_for_roots(model, job[:roots])
        planes = tt_ensure_section_planes_for_job(model, bounds, @cut_offset_mm, job)
        iso = tt_iso_camera(bounds)
        front = tt_ortho_camera(:front, bounds)
        left = tt_ortho_camera(:left, bounds)
        right = tt_ortho_camera(:right, bounds)

        [
          { page: :overview, slot: :main, title: 'PHỐI CẢNH TỔNG THỂ', spec: ['TỔNG THỂ', iso, :normal, nil] },
          { page: :overview, slot: :side, title: 'LINE + X-RAY', spec: ['LINE + X-RAY', iso, :xray, nil] },
          { page: :elevations, slot: :main, title: 'MẶT TRƯỚC', spec: ['MẶT TRƯỚC', front, :normal, nil] },
          { page: :elevations, slot: :top, title: 'BÊN TRÁI', spec: ['BÊN TRÁI', left, :normal, nil] },
          { page: :elevations, slot: :bottom, title: 'BÊN PHẢI', spec: ['BÊN PHẢI', right, :normal, nil] },
          { page: :sections, slot: :main, title: 'MẶT CẮT TRƯỚC', spec: ['CẮT TRƯỚC', front, :section, planes[:cut_front]] },
          { page: :sections, slot: :top, title: 'MẶT CẮT TRÁI', spec: ['CẮT TRÁI', left, :section, planes[:cut_left]] },
          { page: :sections, slot: :bottom, title: 'MẶT CẮT PHẢI', spec: ['CẮT PHẢI', right, :section, planes[:cut_right]] }
        ]
      end

      def tt_page_required(page)
        page == :overview ? 2 : 3
      end

      def tt_page_title(job, page)
        base = "MODE #{job[:index]} · #{job[:name]}"
        case page
        when :overview then "#{base} · 01 TỔNG QUAN + X-RAY"
        when :elevations then "#{base} · 02 MẶT ĐỨNG"
        else "#{base} · 03 MẶT CẮT"
        end
      end

      def tt_render_one_preview_v060(model, task, index, roots)
        spec = task[:spec]
        _title, camera, profile, section = spec
        step_state = tt_capture_model_state(model)
        visibility = tt_scope_visibility_state(model)
        path = File.join(Dir.tmpdir, format('tt_layout_v060_%d_%02d.jpg', Process.pid, index + 1))

        begin
          tt_apply_scope_visibility(model, roots)
          tt_apply_view_state(model, camera, profile, section)
          tt_apply_sharp_edges(model)
          options = {
            filename: path,
            width: V060_PREVIEW_W,
            height: V060_PREVIEW_H,
            antialias: true,
            transparent: false,
            compression: 0.86
          }
          begin
            model.active_view.write_image(options)
          rescue ArgumentError
            options.delete(:compression)
            model.active_view.write_image(options)
          end
          raise "Không tạo được ảnh #{task[:title]}" unless File.file?(path)
          {
            title: task[:title],
            slot: task[:slot].to_s,
            image: "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(path))}"
          }
        ensure
          File.delete(path) rescue nil
          tt_restore_scope_visibility(visibility)
          tt_restore_model_state(model, step_state) rescue nil
        end
      end

      def tt_start_stable_preview(cut_mm)
        tt_cancel_preview_job
        @cut_offset_mm = clamp_cut_offset(cut_mm)
        jobs = tt_layout_jobs
        if jobs.empty?
          invalidate_preview('Không có MODE / tấm ván hợp lệ để xem trước.')
          sync_preview_state
          UI.messagebox('Không tìm thấy tấm ván hợp lệ để thống kê.')
          return false
        end

        @layout_jobs = jobs
        @stats = tt_aggregate_job_stats(jobs)
        token = (@preview_job_token || 0) + 1
        @preview_job_token = token
        @preview_ready = false
        @preview_signature = nil
        @preview_job = {
          token: token,
          model: Sketchup.active_model,
          jobs: jobs,
          job_index: 0,
          task_index: 0,
          buffers: {},
          stats_index: 0,
          initial_signature: tt_jobs_signature(jobs)
        }

        tt_install_stream_js
        tt_reset_stream_gallery
        tt_set_preview_progress("ĐANG DỰNG #{jobs.length} MODE · 0%")
        UI.start_timer(V060_STEP_DELAY, false) { tt_stable_preview_step(token) }
        true
      rescue StandardError => error
        tt_preview_failed(error)
        false
      end

      def tt_stable_preview_step(token)
        job_state = @preview_job
        return unless job_state && job_state[:token] == token && @preview_job_token == token
        return tt_cancel_preview_job unless @dialog && @dialog.visible?

        jobs = job_state[:jobs]
        if job_state[:job_index] >= jobs.length
          return tt_finish_stable_preview(token)
        end

        job = jobs[job_state[:job_index]]
        tasks = (job_state[:tasks] ||= tt_preview_tasks(job_state[:model], job))

        if job_state[:task_index] < tasks.length
          task = tasks[job_state[:task_index]]
          item = tt_render_one_preview_v060(job_state[:model], task, job_state[:task_index], job[:roots])
          page = task[:page]
          job_state[:buffers][page] ||= []
          job_state[:buffers][page] << item
          job_state[:task_index] += 1

          if job_state[:buffers][page].length >= tt_page_required(page)
            tt_append_stream_item({
              kind: 'composite',
              title: tt_page_title(job, page),
              layout: page.to_s,
              cells: job_state[:buffers].delete(page),
              summary: "#{job[:stats][:total_pieces]} tấm · #{job[:stats][:total_types]} loại · #{format('%.3f', job[:stats][:total_area_m2])} m²"
            })
          end

          done_views = job_state[:job_index] * 8 + job_state[:task_index]
          total_views = jobs.length * 8
          percent = ((done_views.to_f / [total_views, 1].max) * 90).round
          tt_set_preview_progress("ĐANG DỰNG MODE #{job[:index]}/#{jobs.length} · #{percent}%")
          UI.start_timer(V060_STEP_DELAY, false) { tt_stable_preview_step(token) }
          return
        end

        chunks = job[:stats][:rows].each_slice(ROWS_PER_PAGE).to_a
        chunks = [[]] if chunks.empty?
        if job_state[:stats_index] < chunks.length
          index = job_state[:stats_index]
          rows = chunks[index].map { |row| tt_preview_row(row) }
          tt_append_stream_item({
            kind: 'stats',
            title: "MODE #{job[:index]} · #{job[:name]} · THỐNG KÊ #{index + 1}/#{chunks.length}",
            page_no: 4 + index,
            stats_page: index + 1,
            stats_pages: chunks.length,
            rows: rows
          })
          job_state[:stats_index] += 1
          UI.start_timer(0.04, false) { tt_stable_preview_step(token) }
          return
        end

        job_state[:job_index] += 1
        job_state[:task_index] = 0
        job_state[:stats_index] = 0
        job_state[:tasks] = nil
        job_state[:buffers] = {}
        UI.start_timer(V060_STEP_DELAY, false) { tt_stable_preview_step(token) }
      rescue StandardError => error
        tt_preview_failed(error)
      end

      def tt_finish_stable_preview(token)
        state = @preview_job
        return unless state && state[:token] == token && @preview_job_token == token
        fresh_jobs = tt_layout_jobs
        fresh_signature = tt_jobs_signature(fresh_jobs)
        unless fresh_signature == state[:initial_signature]
          @layout_jobs = fresh_jobs
          @stats = tt_aggregate_job_stats(fresh_jobs)
          invalidate_preview('Mô hình / vùng chọn / camera đã thay đổi trong lúc xem trước. Hãy xem lại.')
          @preview_job = nil
          sync_dialog
          sync_preview_state
          return
        end

        @layout_jobs = fresh_jobs
        @stats = tt_aggregate_job_stats(fresh_jobs)
        @preview_signature = fresh_signature
        @preview_ready = true
        @preview_message = "ĐÃ XEM TRƯỚC #{fresh_jobs.length} MODE · sẵn sàng xuất."
        @preview_job = nil
        sync_preview_state(@preview_message)
        Sketchup.set_status_text('LAYOUT: preview hoàn tất · có thể Xuất LayOut / PDF.', SB_PROMPT)
      rescue StandardError => error
        tt_preview_failed(error)
      end

      def tt_jobs_signature(jobs)
        model = Sketchup.active_model
        camera = model.active_view.camera
        payload = jobs.map do |job|
          {
            ids: job[:roots].map { |r| tt_entity_id(r) }.sort,
            rows: job[:stats][:rows].map do |row|
              [row[:name].to_s, row[:length_mm].round(2), row[:width_mm].round(2),
               row[:thickness_mm].round(2), row[:qty].to_i, row[:material].to_s, row[:grain].to_s]
            end
          }
        end
        payload << {
          camera: [camera.eye.to_a.map { |v| v.to_f.round(5) },
                   camera.target.to_a.map { |v| v.to_f.round(5) },
                   camera.up.to_a.map { |v| v.to_f.round(5) }],
          cut: @cut_offset_mm.to_f.round(2)
        }
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end

      def validated_preview_stats
        unless @preview_ready && @preview_signature
          UI.messagebox('Bạn cần XEM TRƯỚC LAYOUT hoàn tất trước khi xuất.')
          return nil
        end
        jobs = tt_layout_jobs
        if tt_jobs_signature(jobs) != @preview_signature
          @layout_jobs = jobs
          @stats = tt_aggregate_job_stats(jobs)
          invalidate_preview('Mô hình / vùng chọn / camera đã thay đổi. Hãy xem trước lại.')
          sync_dialog
          sync_preview_state
          UI.messagebox('Dữ liệu đã thay đổi. Hãy XEM TRƯỚC LAYOUT lại trước khi xuất.')
          return nil
        end
        @layout_jobs = jobs
        @stats = tt_aggregate_job_stats(jobs)
        @stats
      end

      def sync_dialog
        return unless @dialog && @dialog.visible?
        jobs = tt_layout_jobs
        @layout_jobs = jobs
        @stats = tt_aggregate_job_stats(jobs)
        pages = jobs.inject(0) do |sum, job|
          stats_pages = [((job[:stats][:rows].length.to_f / ROWS_PER_PAGE).ceil), 1].max
          sum + 3 + stats_pages
        end
        payload = {
          version: VERSION,
          scope: @stats[:scope],
          total_pieces: @stats[:total_pieces],
          total_types: @stats[:total_types],
          total_area_m2: @stats[:total_area_m2].round(3),
          generated_at: @stats[:generated_at],
          page_count: pages,
          cut_offset_mm: @cut_offset_mm,
          rows: @stats[:rows].map { |row| tt_preview_row(row) }
        }
        @dialog.execute_script("window.renderStats(#{JSON.generate(payload)})")
      end

      def tt_install_stream_js
        return unless @dialog && @dialog.visible?
        @dialog.execute_script(<<~JS)
          (function(){
            window.ttLayoutStreamInstalled = true;
            window.ttResetLayoutPreview = function(){
              var g=document.getElementById('gallery'); if(g){g.innerHTML='';}
            };
            function esc(s){return String(s||'').replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
            function cellHtml(c, cls){
              return '<div class="'+cls+'" style="position:relative;border:1px solid #cbd5e1;background:#f8fafc;overflow:hidden">'+
                '<div style="position:absolute;left:8px;top:6px;z-index:2;background:rgba(255,255,255,.9);padding:3px 7px;font:700 11px Arial;color:#9a3412">'+esc(c.title)+'</div>'+
                '<img src="'+c.image+'" style="width:100%;height:100%;object-fit:contain;background:#eef1ec">'+
              '</div>';
            }
            window.ttAppendLayoutPreview=function(item){
              var g=document.getElementById('gallery'); if(!g||!item){return;}
              var e=document.createElement('div'); e.className='sheet'; e.dataset.title=item.title||'Trang Layout';
              if(item.kind==='stats'){
                e.innerHTML=(typeof statsSheet==='function')?statsSheet(item):'';
              }else if(item.kind==='composite'){
                var cells=item.cells||[]; var main=cells.find(function(x){return x.slot==='main';})||cells[0];
                var side=cells.find(function(x){return x.slot==='side';});
                var top=cells.find(function(x){return x.slot==='top';});
                var bottom=cells.find(function(x){return x.slot==='bottom';});
                var head='<div style="font:700 16px Arial;color:#c2410c;margin:0 0 8px">'+esc(item.title)+'</div>';
                var body='<div style="display:grid;grid-template-columns:2fr 1fr;grid-template-rows:1fr 1fr;gap:8px;height:390px">';
                if(main){body+=cellHtml(main,'main').replace('class="main"','class="main" style="grid-row:1 / span 2;position:relative;border:1px solid #cbd5e1;background:#f8fafc;overflow:hidden"');}
                if(side){body+=cellHtml(side,'side');body+='<div style="border:1px solid #cbd5e1;padding:14px;font:12px Arial;color:#334155;background:#fff">'+esc(item.summary||'')+'</div>';}
                else {if(top){body+=cellHtml(top,'top');} if(bottom){body+=cellHtml(bottom,'bottom');}}
                body+='</div>';
                e.innerHTML=head+body;
              }else{
                e.innerHTML=(typeof viewSheet==='function')?viewSheet(item):'';
              }
              e.onclick=function(){if(typeof openModal==='function'){openModal(e);}};
              g.appendChild(e);
            };
          })();
        JS
      rescue StandardError => error
        puts "[TT LayoutStats V060 JS] #{error.class}: #{error.message}"
      end

      def tt_upsert_scope_scene(model, name, profile)
        page = model.pages.to_a.find { |item| item.name.to_s == name.to_s }
        page ||= model.pages.add(name)
        page.use_camera = true if page.respond_to?(:use_camera=)
        page.use_rendering_options = true if page.respond_to?(:use_rendering_options=)
        page.use_section_planes = true if page.respond_to?(:use_section_planes=)
        page.use_hidden = true if page.respond_to?(:use_hidden=)
        page.use_hidden_layers = true if page.respond_to?(:use_hidden_layers=)
        page.include_in_animation = false if page.respond_to?(:include_in_animation=)

        flags = 0
        flags |= PAGE_USE_CAMERA if defined?(PAGE_USE_CAMERA)
        flags |= PAGE_USE_RENDERING_OPTIONS if defined?(PAGE_USE_RENDERING_OPTIONS)
        flags |= PAGE_USE_SECTION_PLANES if defined?(PAGE_USE_SECTION_PLANES)
        flags |= PAGE_USE_HIDDEN if defined?(PAGE_USE_HIDDEN)
        flags |= PAGE_USE_HIDDEN_LAYERS if defined?(PAGE_USE_HIDDEN_LAYERS)
        flags == 0 ? page.update : page.update(flags)
        begin
          tt_apply_render_profile(page.rendering_options, profile)
        rescue StandardError
          nil
        end
        page
      end

      def tt_prepare_export_scenes_for_job(model, job)
        snapshot = tt_capture_model_state(model)
        visibility = tt_scope_visibility_state(model)
        bounds = tt_scope_bounds_for_roots(model, job[:roots])
        planes = tt_ensure_section_planes_for_job(model, bounds, @cut_offset_mm, job)
        suffix = Digest::SHA1.hexdigest(job[:key].to_s)[0, 8]
        defs = {
          overview: [tt_iso_camera(bounds), :normal, nil],
          front: [tt_ortho_camera(:front, bounds), :normal, nil],
          left: [tt_ortho_camera(:left, bounds), :normal, nil],
          right: [tt_ortho_camera(:right, bounds), :normal, nil],
          cut_front: [tt_ortho_camera(:front, bounds), :section, planes[:cut_front]],
          cut_left: [tt_ortho_camera(:left, bounds), :section, planes[:cut_left]],
          cut_right: [tt_ortho_camera(:right, bounds), :section, planes[:cut_right]],
          xray: [tt_iso_camera(bounds), :xray, nil]
        }
        scenes = {}

        model.start_operation("TRẦN TUẤN - Scene Layout #{job[:index]}", true)
        begin
          tt_apply_scope_visibility(model, job[:roots])
          defs.each do |key, spec|
            camera, profile, section = spec
            tt_apply_view_state(model, camera, profile, section)
            tt_apply_sharp_edges(model)
            page = tt_upsert_scope_scene(model, "TT_LY_#{suffix}_#{key.to_s.upcase}", profile)
            scenes[key] = tt_scene_layout_index(model, page)
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        ensure
          tt_restore_scope_visibility(visibility)
          tt_restore_model_state(model, snapshot) rescue nil
        end
        scenes
      end

      def tt_add_scene_viewport(doc, layer, page, skp_path, scene_index, x, y, w, h, label)
        add_text(doc, layer, page, label, x, y - 0.28, w, 0.24, 9.0, true, orange) if y >= 0.55
        viewport = Layout::SketchUpModel.new(skp_path, Geom::Bounds2d.new(x, y, w, h))
        viewport.display_background = false
        viewport.preserve_scale_on_resize = false
        viewport.current_scene = scene_index.to_i
        viewport.render_mode = Layout::SketchUpModel::HYBRID_RENDER
        doc.add_entity(viewport, layer, page)
        begin
          viewport.render if viewport.respond_to?(:render) && viewport.render_needed?
        rescue StandardError
          nil
        end
        viewport
      end

      def tt_add_compact_header(doc, layer, page, title, job, skp_path)
        add_text(doc, layer, page, "TRẦN TUẤN NỘI THẤT · #{title}", 0.42, 0.22, 15.6, 0.42, 17, true, orange)
        add_text(doc, layer, page, "#{File.basename(skp_path)} · MODE #{job[:index]} · #{job[:name]}", 0.42, 0.66, 15.6, 0.28, 8.8, false, gray)
      end

      def tt_build_compact_document(job, skp_path, scenes)
        stats = job[:stats]
        doc = Layout::Document.new
        setup_a3(doc)
        layer = doc.layers.first
        layer.name = 'TRẦN TUẤN - NỘI THẤT' if layer.respond_to?(:name=)

        p1 = doc.pages.first
        p1.name = '01 - TỔNG QUAN + X-RAY'
        tt_add_compact_header(doc, layer, p1, 'TỔNG QUAN + LINE/X-RAY', job, skp_path)
        tt_add_scene_viewport(doc, layer, p1, skp_path, scenes[:overview], 0.45, 1.18, 10.25, 9.55, 'PHỐI CẢNH TỔNG THỂ')
        tt_add_scene_viewport(doc, layer, p1, skp_path, scenes[:xray], 10.95, 1.18, 5.05, 5.25, 'LINE + X-RAY')
        summary = "#{stats[:total_pieces]} TẤM\n#{stats[:total_types]} LOẠI\n#{format('%.3f', stats[:total_area_m2])} m²\n#{stats[:generated_at]}"
        add_text(doc, layer, p1, summary, 11.0, 6.72, 4.9, 2.25, 12.0, true, dark)

        p2 = doc.pages.add('02 - MẶT ĐỨNG')
        tt_add_compact_header(doc, layer, p2, 'MẶT ĐỨNG', job, skp_path)
        tt_add_scene_viewport(doc, layer, p2, skp_path, scenes[:front], 0.45, 1.18, 10.25, 9.55, 'MẶT TRƯỚC')
        tt_add_scene_viewport(doc, layer, p2, skp_path, scenes[:left], 10.95, 1.18, 5.05, 4.45, 'BÊN TRÁI')
        tt_add_scene_viewport(doc, layer, p2, skp_path, scenes[:right], 10.95, 6.28, 5.05, 4.45, 'BÊN PHẢI')

        p3 = doc.pages.add('03 - MẶT CẮT')
        tt_add_compact_header(doc, layer, p3, "MẶT CẮT · #{@cut_offset_mm.round(1)}mm", job, skp_path)
        tt_add_scene_viewport(doc, layer, p3, skp_path, scenes[:cut_front], 0.45, 1.18, 10.25, 9.55, 'MẶT CẮT TRƯỚC')
        tt_add_scene_viewport(doc, layer, p3, skp_path, scenes[:cut_left], 10.95, 1.18, 5.05, 4.45, 'MẶT CẮT TRÁI')
        tt_add_scene_viewport(doc, layer, p3, skp_path, scenes[:cut_right], 10.95, 6.28, 5.05, 4.45, 'MẶT CẮT PHẢI')

        tt_add_statistics_pages(doc, layer, stats, 4)
        doc
      end

      def tt_output_path(base_path, job, index, total, ext)
        base_dir = File.dirname(base_path)
        base_name = File.basename(base_path, File.extname(base_path))
        return File.join(base_dir, "#{base_name}.#{ext}") if total <= 1
        suffix = format('%02d_%s', index + 1, tt_safe_filename(job[:name]))
        File.join(base_dir, "#{base_name}_#{suffix}.#{ext}")
      end

      def export_layout(_stats = nil)
        ensure_layout_api!
        jobs = @layout_jobs || tt_layout_jobs
        return false if jobs.empty?
        model = Sketchup.active_model
        skp_path = ensure_model_saved(model)
        return false unless skp_path

        scene_sets = jobs.map { |job| tt_prepare_export_scenes_for_job(model, job) }
        model.save
        default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_LAYOUT.layout'
        base_path = UI.savepanel('Xuất LayOut', File.dirname(skp_path), default_name)
        return false unless base_path
        base_path += '.layout' unless File.extname(base_path).downcase == '.layout'

        version = defined?(Layout::Document::VERSION_2022) ? Layout::Document::VERSION_2022 : Layout::Document::VERSION_CURRENT
        outputs = []
        jobs.each_with_index do |job, index|
          doc = tt_build_compact_document(job, skp_path, scene_sets[index])
          path = tt_output_path(base_path, job, index, jobs.length, 'layout')
          doc.save(path, version)
          outputs << path
        end
        UI.messagebox("Đã xuất #{outputs.length} LayOut.\n\n#{outputs.join("\n")}")
        true
      end

      def export_pdf(_stats = nil)
        ensure_layout_api!
        jobs = @layout_jobs || tt_layout_jobs
        return false if jobs.empty?
        model = Sketchup.active_model
        skp_path = ensure_model_saved(model)
        return false unless skp_path

        scene_sets = jobs.map { |job| tt_prepare_export_scenes_for_job(model, job) }
        model.save
        default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_LAYOUT.pdf'
        base_path = UI.savepanel('Xuất PDF Layout', File.dirname(skp_path), default_name)
        return false unless base_path
        base_path += '.pdf' unless File.extname(base_path).downcase == '.pdf'

        outputs = []
        jobs.each_with_index do |job, index|
          doc = tt_build_compact_document(job, skp_path, scene_sets[index])
          path = tt_output_path(base_path, job, index, jobs.length, 'pdf')
          doc.export(path, start_page: 0, end_page: doc.pages.length - 1, compress_images: true, compress_quality: 0.94)
          outputs << path
        end
        UI.messagebox("Đã xuất #{outputs.length} PDF.\n\n#{outputs.join("\n")}")
        true
      end
    end
  end
end
