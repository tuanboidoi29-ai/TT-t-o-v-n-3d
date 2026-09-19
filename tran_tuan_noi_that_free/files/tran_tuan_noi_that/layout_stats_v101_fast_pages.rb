# encoding: UTF-8
require 'tmpdir'
require 'fileutils'
module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION,false)
    VERSION = '0.10.1'.freeze
    remove_const(:V060_STEP_DELAY) if const_defined?(:V060_STEP_DELAY,false)
    V060_STEP_DELAY = 0.01
    FAST_VIEWS = [[:overview,'PHỐI CẢNH TỔNG THỂ'],[:xray,'LINE + X-RAY'],[:line,'KHUNG LINE'],
                  [:front,'MẶT TRƯỚC'],[:left,'MẶT TRÁI'],[:right,'MẶT PHẢI'],
                  [:cut_front,'MẶT CẮT TRƯỚC'],[:cut_left,'MẶT CẮT TRÁI'],[:cut_right,'MẶT CẮT PHẢI'],
                  [:dim_front,'DIM MẶT TRƯỚC'],[:dim_side,'DIM MẶT BÊN'],[:dim_top,'DIM MẶT TRÊN']].freeze
    class << self
      alias_method :tt_fast_original_show, :show
      alias_method :tt_fast_original_html, :dialog_html
      alias_method :tt_fast_original_tasks, :tt_preview_tasks
      alias_method :tt_fast_original_sync, :sync_dialog
      alias_method :tt_fast_original_append, :tt_append_stream_item

      def show
        tt_fast_original_show
        return unless @dialog
        [:layout,:pdf].each do |type|
          @dialog.add_action_callback("export_#{type}") do |_context,cut|
            begin
              value = Float(cut || @cut_offset_mm || 20)
              raise 'Khoảng cắt phải từ 1 đến 500 mm.' unless value.finite? && value >= 1 && value <= 500
              @cut_offset_mm = value
              tt_fast_export(type)
            rescue StandardError => error
              UI.messagebox("Xuất thất bại: #{error.message}")
            end
          end
        end
      end

      def dialog_html
        html = tt_fast_original_html
        html = html.gsub('sketchup.export_layout()',"sketchup.export_layout(document.getElementById('cut').value)")
        html = html.gsub('sketchup.export_pdf()',"sketchup.export_pdf(document.getElementById('cut').value)")
        html = html.gsub('CHƯA XEM TRƯỚC', 'XEM TRƯỚC TÙY CHỌN')
        html = html.gsub(/Thứ tự: Tổng thể[^<]+/, '12 trang riêng: Tổng thể / X-Ray / Line / Trước / Trái / Phải / 3 mặt cắt / 3 mặt DIM → Thống kê ván.')
        html.sub('</body>', '<p style="padding:12px;color:#fbbf24">Mỗi mặt chiếu một trang A3 · Xuất trực tiếp, không bắt xem trước · Chọn nơi lưu một lần. LayOut có thư mục SKP đi kèm.</p></body>')
      end

      def sync_preview_state(message=nil)
        return unless @dialog
        text = @fast_export_busy ? 'Đang xuất…' : 'Có thể xuất trực tiếp · Xem trước là tùy chọn · Mỗi mặt chiếu một trang.'
        @dialog.execute_script("window.setPreviewState(#{@fast_export_busy ? 'false' : 'true'},#{JSON.generate(text)})")
      end

      def tt_preview_tasks(model,job)
        tt_fast_original_tasks(model,job).each_with_index.map do |task,index|
          task.merge(page: FAST_VIEWS[index][0],slot: :main)
        end
      end

      def tt_page_required(_page); 1; end

      def tt_page_title(job,page)
        index = FAST_VIEWS.index { |key,_| key == page } || 0
        "MODE #{job[:index]} · #{job[:name]} · #{format('%02d',index+1)} #{FAST_VIEWS[index][1]}"
      end

      def tt_append_stream_item(item)
        item = item.merge(page_no: item[:page_no].to_i + 6) if item[:kind] == 'stats'
        tt_fast_original_append(item)
      end

      def sync_dialog
        tt_fast_original_sync
        return unless @dialog && @layout_jobs
        count = @layout_jobs.sum { |job| FAST_VIEWS.size + [(job[:stats][:rows].size.to_f/ROWS_PER_PAGE).ceil,1].max }
        @dialog.execute_script("if(document.getElementById('pages')) document.getElementById('pages').textContent=#{count};")
      end

      def tt_build_five_view_document(job,skp_path,scenes,include_stats)
        doc = Layout::Document.new
        setup_a3(doc)
        doc.page_info.output_resolution = Layout::PageInfo::RESOLUTION_MEDIUM
        layer = doc.layers.first
        FAST_VIEWS.each_with_index do |(key,title),index|
          raise "Thiếu scene #{title}" unless scenes[key]
          page = index == 0 ? doc.pages.first : doc.pages.add(title)
          page.name = format('%02d - %s',index+1,title)
          tt_add_compact_header(doc,layer,page,title,job,skp_path)
          tt_add_scene_viewport(doc,layer,page,skp_path,scenes[key],0.48,1.15,15.45,9.65,title)
        end
        tt_add_statistics_pages(doc,layer,job[:stats],FAST_VIEWS.size+1) if include_stats
        doc
      end

      def tt_add_scene_viewport(doc,layer,page,skp_path,scene_index,x,y,w,h,label)
        add_text(doc,layer,page,label,x,y-0.28,w,0.24,9.0,true,orange)
        viewport = Layout::SketchUpModel.new(skp_path,Geom::Bounds2d.new(x,y,w,h))
        viewport.display_background = false
        viewport.preserve_scale_on_resize = false
        viewport.current_scene = scene_index
        viewport.render_mode = Layout::SketchUpModel::RASTER_RENDER
        doc.add_entity(viewport,layer,page)
        # Render once in Raster; avoid the costly Hybrid vector pass.
        viewport.render if viewport.render_needed?
        viewport
      end

      def export_layout(_stats=nil); tt_fast_export(:layout); end
      def export_pdf(_stats=nil); tt_fast_export(:pdf); end

      def tt_fast_export(type)
        return false if @fast_export_busy
        @fast_export_busy = true
        source_dir = nil
        outputs = []
        begin
          tt_cancel_preview_job
          ensure_layout_api!
          model = Sketchup.active_model
          raise 'Hãy thoát chế độ sửa Group/Component trước khi xuất.' if model.active_path
          raise 'SketchUp không hỗ trợ lưu bản sao mô hình.' unless model.respond_to?(:save_copy)
          # Ask once, before scene creation or file writes. Never save the user's SKP.
          folder = @fast_export_folder || (model.path.empty? ? Dir.home : File.dirname(model.path))
          name = model.path.empty? ? 'TRANTUAN_HO_SO' : File.basename(model.path,File.extname(model.path))+'_TT'
          base = UI.savepanel("Xuất #{type == :pdf ? 'PDF' : 'LayOut'} — mỗi mặt một trang",folder,"#{name}.#{type}")
          return false unless base
          base += ".#{type}" unless File.extname(base).downcase == ".#{type}"
          @fast_export_folder = File.dirname(base)
          sync_preview_state
          jobs = tt_layout_jobs
          raise 'Không có cụm ván hợp lệ để xuất.' if jobs.empty?
          paths = jobs.each_with_index.map { |job,i| tt_output_path(base,job,i,jobs.size,type.to_s) }
          # Never silently overwrite derived filenames that the save dialog did not show.
          if jobs.size > 1 && paths.any? { |path| File.exist?(path) }
            stamp = Time.now.strftime('%Y%m%d_%H%M%S')+'_'+rand(1000000).to_s
            base = base.sub(/\.[^.]+\z/,"_#{stamp}.#{type}")
            paths = jobs.each_with_index.map { |job,i| tt_output_path(base,job,i,jobs.size,type.to_s) }
          end
          scene_sets = jobs.map { |job| tt_prepare_export_scenes_for_job(model,job) }
          source_dir = type == :layout ? Dir.mktmpdir('TT_LAYOUT_NGUON_',File.dirname(base)) : Dir.mktmpdir('tt_pdf_')
          skp = File.join(source_dir,'model.skp')
          raise 'Không lưu được bản sao SKP cho hồ sơ.' unless model.save_copy(skp)
          jobs.each_with_index do |job,index|
            Sketchup.set_status_text("Đang xuất #{index+1}/#{jobs.size} · 12 mặt chiếu riêng")
            doc = tt_build_five_view_document(job,skp,scene_sets[index],type == :pdf)
            path = paths[index]
            if type == :pdf
              ok = doc.export(path,start_page:0,end_page:doc.pages.length-1,compress_images:true,compress_quality:0.85)
            else
              version = defined?(Layout::Document::VERSION_2022) ? Layout::Document::VERSION_2022 : Layout::Document::VERSION_CURRENT
              ok = doc.save(path,version)
            end
            raise "Không ghi được #{path}" if ok == false
            outputs << path
            doc = nil
          end
          message = "Đã xuất #{outputs.size} #{type.to_s.upcase} · mỗi mặt chiếu một trang."
          message += "\nGiữ thư mục #{File.basename(source_dir)} cạnh hồ sơ LayOut." if type == :layout
          UI.messagebox(message+"\n\n"+outputs.join("\n"))
          true
        rescue StandardError => error
          raise "#{error.message}\nĐã ghi #{outputs.size} tệp trước khi dừng: #{outputs.join(', ')}"
        ensure
          if source_dir && (type == :pdf || outputs.empty?)
            FileUtils.remove_entry(source_dir) rescue nil
          end
          @fast_export_busy = false
          sync_preview_state
          Sketchup.set_status_text('')
        end
      end
    end
  end
end
