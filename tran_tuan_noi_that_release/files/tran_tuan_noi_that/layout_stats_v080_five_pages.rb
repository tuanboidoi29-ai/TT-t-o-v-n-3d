# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.8.0
# 5 TRANG PHỐI CẢNH / KỸ THUẬT
# 01 Tổng thể
# 02 Line + X-Ray
# 03 Khung LINE / toàn bộ đường biên
# 04 Mặt trước + Trái + Phải
# 05 Mặt cắt trước + Cắt trái + Cắt phải
#
# Xuất LayOut: chỉ 5 trang kỹ thuật, không thống kê.
# Xuất PDF: cùng 5 trang kỹ thuật + thống kê ván từ trang 6.
# Preview trong bảng dùng đúng cùng thứ tự 5 trang.

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.8.0'.freeze

    class << self
      alias_method :tt_v080_render_profile_base, :tt_apply_render_profile unless method_defined?(:tt_v080_render_profile_base)

      def tt_apply_render_profile(options, profile)
        if profile == :line
          values = {
            'ModelTransparency' => false,
            'MaterialTransparency' => false,
            'DrawBackEdges' => true,
            'DisplaySectionCuts' => false,
            'DisplaySectionPlanes' => false,
            'SectionCutDrawEdges' => false,
            'SectionCutFilled' => false,
            'Texture' => false,
            'EdgeDisplayMode' => 0,
            'RenderMode' => 0
          }
          values.each { |key, value| options[key] = value rescue nil }
        else
          tt_v080_render_profile_base(options, profile)
        end
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
          { page: :xray, slot: :main, title: 'LINE + X-RAY', spec: ['LINE + X-RAY', iso, :xray, nil] },
          { page: :line, slot: :main, title: 'KHUNG LINE / ĐƯỜNG BIÊN', spec: ['KHUNG LINE', iso, :line, nil] },
          { page: :elevations, slot: :main, title: 'MẶT TRƯỚC', spec: ['MẶT TRƯỚC', front, :normal, nil] },
          { page: :elevations, slot: :top, title: 'BÊN TRÁI', spec: ['BÊN TRÁI', left, :normal, nil] },
          { page: :elevations, slot: :bottom, title: 'BÊN PHẢI', spec: ['BÊN PHẢI', right, :normal, nil] },
          { page: :sections, slot: :main, title: 'MẶT CẮT TRƯỚC', spec: ['CẮT TRƯỚC', front, :section, planes[:cut_front]] },
          { page: :sections, slot: :top, title: 'MẶT CẮT TRÁI', spec: ['CẮT TRÁI', left, :section, planes[:cut_left]] },
          { page: :sections, slot: :bottom, title: 'MẶT CẮT PHẢI', spec: ['CẮT PHẢI', right, :section, planes[:cut_right]] }
        ]
      end

      def tt_page_required(page)
        [:overview, :xray, :line].include?(page) ? 1 : 3
      end

      def tt_page_title(job, page)
        base = "MODE #{job[:index]} · #{job[:name]}"
        case page
        when :overview
          "#{base} · 01 TỔNG THỂ"
        when :xray
          "#{base} · 02 LINE + X-RAY"
        when :line
          "#{base} · 03 KHUNG LINE"
        when :elevations
          "#{base} · 04 MẶT ĐỨNG"
        else
          "#{base} · 05 MẶT CẮT"
        end
      end

      def tt_stable_preview_step(token)
        job_state = @preview_job
        return unless job_state && job_state[:token] == token && @preview_job_token == token
        return tt_cancel_preview_job unless @dialog && @dialog.visible?

        jobs = job_state[:jobs]
        return tt_finish_stable_preview(token) if job_state[:job_index] >= jobs.length

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

          done_views = job_state[:job_index] * 9 + job_state[:task_index]
          total_views = jobs.length * 9
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
            page_no: 6 + index,
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

      def sync_dialog
        return unless @dialog && @dialog.visible?
        jobs = tt_layout_jobs
        @layout_jobs = jobs
        @stats = tt_aggregate_job_stats(jobs)
        pages = jobs.inject(0) do |sum, job|
          stats_pages = [((job[:stats][:rows].length.to_f / ROWS_PER_PAGE).ceil), 1].max
          sum + 5 + stats_pages
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
            function cellHtml(c, extra){
              return '<div style="position:relative;border:1px solid #cbd5e1;background:#f8fafc;overflow:hidden;'+(extra||'')+'">'+
                '<div style="position:absolute;left:8px;top:6px;z-index:2;background:rgba(255,255,255,.92);padding:3px 7px;font:700 11px Arial;color:#9a3412">'+esc(c.title)+'</div>'+
                '<img src="'+c.image+'" style="width:100%;height:100%;object-fit:contain;background:#eef1ec">'+
              '</div>';
            }
            window.ttAppendLayoutPreview=function(item){
              var g=document.getElementById('gallery'); if(!g||!item){return;}
              var e=document.createElement('div'); e.className='sheet'; e.dataset.title=item.title||'Trang Layout';
              if(item.kind==='stats'){
                e.innerHTML=(typeof statsSheet==='function')?statsSheet(item):'';
              }else if(item.kind==='composite'){
                var cells=item.cells||[];
                var head='<div style="font:700 16px Arial;color:#c2410c;margin:0 0 8px">'+esc(item.title)+'</div>';
                if(cells.length===1){
                  e.innerHTML=head+cellHtml(cells[0],'height:410px;width:100%;');
                }else{
                  var main=cells.find(function(x){return x.slot==='main';})||cells[0];
                  var top=cells.find(function(x){return x.slot==='top';});
                  var bottom=cells.find(function(x){return x.slot==='bottom';});
                  var body='<div style="display:grid;grid-template-columns:2fr 1fr;grid-template-rows:1fr 1fr;gap:8px;height:390px">';
                  if(main){body+=cellHtml(main,'grid-row:1 / span 2;');}
                  if(top){body+=cellHtml(top,'');}
                  if(bottom){body+=cellHtml(bottom,'');}
                  body+='</div>';
                  e.innerHTML=head+body;
                }
              }else{
                e.innerHTML=(typeof viewSheet==='function')?viewSheet(item):'';
              }
              e.onclick=function(){if(typeof openModal==='function'){openModal(e);}};
              g.appendChild(e);
            };
          })();
        JS
      rescue StandardError => error
        puts "[TT LayoutStats V080 JS] #{error.class}: #{error.message}"
      end

      def tt_prepare_export_scenes_for_job(model, job)
        snapshot = tt_capture_model_state(model)
        visibility = tt_scope_visibility_state(model)
        bounds = tt_scope_bounds_for_roots(model, job[:roots])
        planes = tt_ensure_section_planes_for_job(model, bounds, @cut_offset_mm, job)
        suffix = Digest::SHA1.hexdigest(job[:key].to_s)[0, 8]
        defs = {
          overview: [tt_iso_camera(bounds), :normal, nil],
          xray: [tt_iso_camera(bounds), :xray, nil],
          line: [tt_iso_camera(bounds), :line, nil],
          front: [tt_ortho_camera(:front, bounds), :normal, nil],
          left: [tt_ortho_camera(:left, bounds), :normal, nil],
          right: [tt_ortho_camera(:right, bounds), :normal, nil],
          cut_front: [tt_ortho_camera(:front, bounds), :section, planes[:cut_front]],
          cut_left: [tt_ortho_camera(:left, bounds), :section, planes[:cut_left]],
          cut_right: [tt_ortho_camera(:right, bounds), :section, planes[:cut_right]]
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

      def tt_build_five_view_document(job, skp_path, scenes, include_stats)
        stats = job[:stats]
        doc = Layout::Document.new
        setup_a3(doc)
        layer = doc.layers.first
        layer.name = 'TRẦN TUẤN - NỘI THẤT' if layer.respond_to?(:name=)

        p1 = doc.pages.first
        p1.name = '01 - TỔNG THỂ'
        tt_add_compact_header(doc, layer, p1, 'PHỐI CẢNH TỔNG THỂ', job, skp_path)
        tt_add_scene_viewport(doc, layer, p1, skp_path, scenes[:overview], 0.48, 1.15, 15.45, 9.65, 'TỔNG THỂ')

        p2 = doc.pages.add('02 - LINE + X-RAY')
        tt_add_compact_header(doc, layer, p2, 'PHỐI CẢNH LINE + X-RAY', job, skp_path)
        tt_add_scene_viewport(doc, layer, p2, skp_path, scenes[:xray], 0.48, 1.15, 15.45, 9.65, 'LINE + X-RAY')

        p3 = doc.pages.add('03 - KHUNG LINE')
        tt_add_compact_header(doc, layer, p3, 'KHUNG HIỂN THỊ TOÀN BỘ ĐƯỜNG LINE', job, skp_path)
        tt_add_scene_viewport(doc, layer, p3, skp_path, scenes[:line], 0.48, 1.15, 15.45, 9.65, 'WIREFRAME / KHUNG LINE')

        p4 = doc.pages.add('04 - MẶT ĐỨNG')
        tt_add_compact_header(doc, layer, p4, 'MẶT TRƯỚC + TRÁI + PHẢI', job, skp_path)
        tt_add_scene_viewport(doc, layer, p4, skp_path, scenes[:front], 0.45, 1.18, 10.25, 9.55, 'MẶT TRƯỚC')
        tt_add_scene_viewport(doc, layer, p4, skp_path, scenes[:left], 10.95, 1.18, 5.05, 4.45, 'BÊN TRÁI')
        tt_add_scene_viewport(doc, layer, p4, skp_path, scenes[:right], 10.95, 6.28, 5.05, 4.45, 'BÊN PHẢI')

        p5 = doc.pages.add('05 - MẶT CẮT')
        tt_add_compact_header(doc, layer, p5, "MẶT CẮT · #{@cut_offset_mm.round(1)}mm", job, skp_path)
        tt_add_scene_viewport(doc, layer, p5, skp_path, scenes[:cut_front], 0.45, 1.18, 10.25, 9.55, 'MẶT CẮT TRƯỚC')
        tt_add_scene_viewport(doc, layer, p5, skp_path, scenes[:cut_left], 10.95, 1.18, 5.05, 4.45, 'MẶT CẮT TRÁI')
        tt_add_scene_viewport(doc, layer, p5, skp_path, scenes[:cut_right], 10.95, 6.28, 5.05, 4.45, 'MẶT CẮT PHẢI')

        tt_add_statistics_pages(doc, layer, stats, 6) if include_stats
        doc
      end

      def tt_build_views_only_document(job, skp_path, scenes)
        tt_build_five_view_document(job, skp_path, scenes, false)
      end

      def tt_build_pdf_document(job, skp_path, scenes)
        tt_build_five_view_document(job, skp_path, scenes, true)
      end
    end
  end
end
