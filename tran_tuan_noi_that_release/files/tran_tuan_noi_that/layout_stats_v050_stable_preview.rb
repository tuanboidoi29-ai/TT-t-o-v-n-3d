# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.5.0
# STABLE / SMOOTH PREVIEW
# - Không render 8 ảnh liên tiếp trong một callback HtmlDialog.
# - Mỗi lần chỉ render 1 trang, trả quyền điều khiển về SketchUp giữa các bước.
# - Không giữ toàn bộ Base64 preview trong Ruby RAM; đẩy từng trang sang HtmlDialog ngay.
# - Preview ảnh nhẹ hơn (480x340, JPEG nén, không antialias) để giảm nguy cơ treo/sập.
# - Có token hủy job cũ khi bấm preview/quét lại/đóng bảng.
# - Chỉ bật Xuất LayOut/PDF sau khi toàn bộ preview hoàn tất và dữ liệu không đổi.

require 'tmpdir'
require 'base64'
require 'json'

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.5.0'.freeze

    STABLE_PREVIEW_WIDTH = 480 unless const_defined?(:STABLE_PREVIEW_WIDTH, false)
    STABLE_PREVIEW_HEIGHT = 340 unless const_defined?(:STABLE_PREVIEW_HEIGHT, false)
    STABLE_PREVIEW_DELAY = 0.08 unless const_defined?(:STABLE_PREVIEW_DELAY, false)

    class << self
      def show
        tt_cancel_preview_job
        @stats = build_stats
        invalidate_preview('Chưa xem trước. Bấm XEM TRƯỚC LAYOUT.')

        if @dialog && @dialog.visible?
          sync_dialog
          tt_install_stream_js
          sync_preview_state
          @dialog.bring_to_front
          return
        end

        @dialog = UI::HtmlDialog.new(
          dialog_title: 'TRẦN TUẤN - XUẤT LAYOUT + THỐNG KÊ VÁN',
          preferences_key: 'TranTuanNoiThat.LayoutStats',
          scrollable: true,
          resizable: true,
          width: 1160,
          height: 820,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(dialog_html)

        @dialog.add_action_callback('ready') do |_ctx|
          sync_dialog
          tt_install_stream_js
          sync_preview_state
        end

        @dialog.add_action_callback('refresh') do |_ctx|
          tt_cancel_preview_job
          @stats = build_stats
          invalidate_preview('Đã quét lại mô hình. Cần xem trước lại.')
          sync_dialog
          tt_install_stream_js
          sync_preview_state
        end

        @dialog.add_action_callback('preview_inline') do |_ctx, cut_mm|
          tt_start_stable_preview(cut_mm)
        end

        @dialog.add_action_callback('export_layout') do |_ctx|
          begin
            stats = validated_preview_stats
            export_layout(stats) if stats
          rescue StandardError => error
            UI.messagebox("Xuất LayOut thất bại:\n#{error.message}")
            puts "[TT LayoutStats V050 layout] #{error.class}: #{error.message}"
          end
        end

        @dialog.add_action_callback('export_pdf') do |_ctx|
          begin
            stats = validated_preview_stats
            export_pdf(stats) if stats
          rescue StandardError => error
            UI.messagebox("Xuất PDF thất bại:\n#{error.message}")
            puts "[TT LayoutStats V050 pdf] #{error.class}: #{error.message}"
          end
        end

        @dialog.set_on_closed do
          tt_cancel_preview_job
          @dialog = nil
          @preview_images = []
        end
        @dialog.show
      rescue StandardError => error
        tt_cancel_preview_job
        UI.messagebox("Không mở được Xuất Layout + Thống Kê Ván:\n#{error.message}")
      end

      def tt_start_stable_preview(cut_mm)
        tt_cancel_preview_job
        @cut_offset_mm = clamp_cut_offset(cut_mm)
        @stats = build_stats

        if @stats[:rows].empty?
          invalidate_preview('Không có tấm ván hợp lệ để xem trước.')
          sync_preview_state
          UI.messagebox('Không tìm thấy tấm ván hợp lệ để thống kê.')
          return false
        end

        model = Sketchup.active_model
        bounds = tt_scope_bounds(model)
        raise 'Không có hình học để tạo phối cảnh.' unless bounds && bounds.valid?

        planes = tt_ensure_section_planes(model, bounds, @cut_offset_mm)
        base_camera = tt_clone_camera(model.active_view.camera)
        specs = [
          ['01 · PHỐI CẢNH TỔNG THỂ', base_camera, :normal, nil],
          ['02 · MẶT TRƯỚC', tt_ortho_camera(:front, bounds), :normal, nil],
          ['03 · BÊN TRÁI', tt_ortho_camera(:left, bounds), :normal, nil],
          ['04 · BÊN PHẢI', tt_ortho_camera(:right, bounds), :normal, nil],
          ['05 · MẶT CẮT TRƯỚC', tt_ortho_camera(:front, bounds), :section, planes[:cut_front]],
          ['06 · MẶT CẮT TRÁI', tt_ortho_camera(:left, bounds), :section, planes[:cut_left]],
          ['07 · MẶT CẮT PHẢI', tt_ortho_camera(:right, bounds), :section, planes[:cut_right]],
          ['08 · PHỐI CẢNH LINE + X-RAY', base_camera, :xray, nil]
        ]

        chunks = @stats[:rows].each_slice(ROWS_PER_PAGE).to_a
        chunks = [[]] if chunks.empty?
        stats_items = chunks.each_with_index.map do |chunk, index|
          page_no = 9 + index
          title = if index.zero?
                    format('%02d · THỐNG KÊ VÁN', page_no)
                  else
                    format('%02d · THỐNG KÊ VÁN %d', page_no, index + 1)
                  end
          {
            title: title,
            kind: 'stats',
            page_no: page_no,
            stats_page: index + 1,
            stats_pages: chunks.length,
            rows: chunk.map { |row| tt_preview_row(row) }
          }
        end

        token = (@preview_job_token || 0) + 1
        @preview_job_token = token
        @preview_ready = false
        @preview_signature = nil
        @preview_images = []
        @preview_job = {
          token: token,
          model: model,
          specs: specs,
          view_index: 0,
          stats_items: stats_items,
          stats_index: 0,
          initial_signature: current_signature(@stats)
        }

        tt_install_stream_js
        tt_reset_stream_gallery
        tt_set_preview_progress("ĐANG DỰNG LAYOUT · 0/#{specs.length} HÌNH")
        UI.start_timer(STABLE_PREVIEW_DELAY, false) { tt_stable_preview_step(token) }
        true
      rescue StandardError => error
        tt_preview_failed(error)
        false
      end

      def tt_stable_preview_step(token)
        job = @preview_job
        return unless job && job[:token] == token && @preview_job_token == token
        return tt_cancel_preview_job unless @dialog && @dialog.visible?

        if job[:view_index] < job[:specs].length
          index = job[:view_index]
          spec = job[:specs][index]
          item = tt_render_one_preview(job[:model], spec, index)
          return unless @preview_job && @preview_job[:token] == token

          tt_append_stream_item(item)
          job[:view_index] += 1
          tt_set_preview_progress(
            "ĐANG DỰNG LAYOUT · #{job[:view_index]}/#{job[:specs].length} HÌNH"
          )
          UI.start_timer(STABLE_PREVIEW_DELAY, false) { tt_stable_preview_step(token) }
          return
        end

        if job[:stats_index] < job[:stats_items].length
          item = job[:stats_items][job[:stats_index]]
          tt_append_stream_item(item)
          job[:stats_index] += 1
          total = job[:stats_items].length
          tt_set_preview_progress("ĐANG DỰNG BẢNG THỐNG KÊ · #{job[:stats_index]}/#{total}")
          UI.start_timer(0.03, false) { tt_stable_preview_step(token) }
          return
        end

        tt_finish_stable_preview(token)
      rescue StandardError => error
        tt_preview_failed(error)
      end

      def tt_render_one_preview(model, spec, index)
        title, camera, profile, section = spec
        step_state = tt_capture_model_state(model)
        path = File.join(
          Dir.tmpdir,
          format('tt_layout_stable_%d_%02d.jpg', Process.pid, index + 1)
        )

        begin
          tt_apply_view_state(model, camera, profile, section)
          options = {
            filename: path,
            width: STABLE_PREVIEW_WIDTH,
            height: STABLE_PREVIEW_HEIGHT,
            antialias: false,
            transparent: false,
            compression: 0.72
          }
          begin
            model.active_view.write_image(options)
          rescue ArgumentError
            options.delete(:compression)
            model.active_view.write_image(options)
          end
          raise "Không tạo được ảnh #{title}" unless File.file?(path)

          bytes = File.binread(path)
          {
            title: title,
            kind: profile.to_s,
            image: "data:image/jpeg;base64,#{Base64.strict_encode64(bytes)}"
          }
        ensure
          File.delete(path) rescue nil
          tt_restore_model_state(model, step_state) rescue nil
        end
      end

      def tt_finish_stable_preview(token)
        job = @preview_job
        return unless job && job[:token] == token && @preview_job_token == token

        fresh = build_stats
        fresh_signature = current_signature(fresh)
        unless fresh_signature == job[:initial_signature]
          @stats = fresh
          invalidate_preview('Mô hình / selection / camera đã thay đổi trong lúc xem trước. Hãy xem lại.')
          @preview_job = nil
          sync_dialog
          sync_preview_state
          return
        end

        @stats = fresh
        @preview_signature = fresh_signature
        @preview_ready = true
        @preview_message = 'ĐÃ XEM TRƯỚC TOÀN BỘ LAYOUT · sẵn sàng xuất.'
        @preview_job = nil
        sync_preview_state(@preview_message)
        Sketchup.set_status_text('LAYOUT: xem trước hoàn tất · có thể Xuất LayOut / PDF.', SB_PROMPT)
      rescue StandardError => error
        tt_preview_failed(error)
      end

      def tt_preview_failed(error)
        puts "[TT LayoutStats V050 preview] #{error.class}: #{error.message}"
        tt_cancel_preview_job
        invalidate_preview("Xem trước thất bại: #{error.message}")
        sync_preview_state
        UI.messagebox("Xem trước Layout thất bại:\n#{error.message}") if @dialog && @dialog.visible?
      end

      def tt_cancel_preview_job
        @preview_job_token = (@preview_job_token || 0) + 1
        @preview_job = nil
        true
      end

      def tt_install_stream_js
        return unless @dialog && @dialog.visible?
        @dialog.execute_script(<<~JS)
          (function(){
            if(window.ttLayoutStreamInstalled){ return; }
            window.ttLayoutStreamInstalled = true;
            window.ttResetLayoutPreview = function(){
              var g = document.getElementById('gallery');
              if(g){ g.innerHTML = ''; }
            };
            window.ttAppendLayoutPreview = function(item){
              var g = document.getElementById('gallery');
              if(!g || !item){ return; }
              var e = document.createElement('div');
              e.className = 'sheet';
              e.dataset.title = item.title || 'Trang Layout';
              if(item.kind === 'stats'){
                e.innerHTML = (typeof statsSheet === 'function') ? statsSheet(item) : '';
              }else{
                e.innerHTML = (typeof viewSheet === 'function') ? viewSheet(item) : '';
              }
              e.onclick = function(){ if(typeof openModal === 'function'){ openModal(e); } };
              g.appendChild(e);
            };
          })();
        JS
      rescue StandardError => error
        puts "[TT LayoutStats V050 JS] #{error.class}: #{error.message}"
      end

      def tt_reset_stream_gallery
        return unless @dialog && @dialog.visible?
        @dialog.execute_script('window.ttResetLayoutPreview && window.ttResetLayoutPreview();')
      end

      def tt_append_stream_item(item)
        return unless @dialog && @dialog.visible?
        @dialog.execute_script(
          "window.ttAppendLayoutPreview && window.ttAppendLayoutPreview(#{JSON.generate(item)});"
        )
      end

      def tt_set_preview_progress(message)
        @preview_ready = false
        @preview_message = message.to_s
        return unless @dialog && @dialog.visible?
        @dialog.execute_script(
          "window.setPreviewState(false, #{JSON.generate(message.to_s)});"
        )
      end
    end
  end
end
