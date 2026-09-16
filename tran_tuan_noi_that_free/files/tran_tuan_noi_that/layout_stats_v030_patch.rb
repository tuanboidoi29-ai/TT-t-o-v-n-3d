# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.3.0 PATCH
# Preview trong HtmlDialog + 3 mặt cắt + Line/X-Ray. Không mở app ngoài để xem trước.

require 'tmpdir'
require 'base64'
require 'digest'
require 'json'

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.3.0'.freeze

    DEFAULT_CUT_OFFSET_MM = 20.0 unless const_defined?(:DEFAULT_CUT_OFFSET_MM, false)
    PREVIEW_WIDTH = 520 unless const_defined?(:PREVIEW_WIDTH, false)
    PREVIEW_HEIGHT = 368 unless const_defined?(:PREVIEW_HEIGHT, false)

    RENDER_KEYS = %w[
      ModelTransparency MaterialTransparency DrawBackEdges
      DisplaySectionCuts DisplaySectionPlanes SectionCutDrawEdges
      SectionCutFilled Texture EdgeDisplayMode RenderMode
    ].freeze unless const_defined?(:RENDER_KEYS, false)

    SCENE_NAMES = {
      cut_front: 'TT_LAYOUT_05_CAT_TRUOC',
      cut_left: 'TT_LAYOUT_06_CAT_TRAI',
      cut_right: 'TT_LAYOUT_07_CAT_PHAI',
      line_xray: 'TT_LAYOUT_08_LINE_XRAY'
    }.freeze unless const_defined?(:SCENE_NAMES, false)

    SECTION_NAMES = {
      cut_front: 'TT_LAYOUT_SECTION_FRONT',
      cut_left: 'TT_LAYOUT_SECTION_LEFT',
      cut_right: 'TT_LAYOUT_SECTION_RIGHT'
    }.freeze unless const_defined?(:SECTION_NAMES, false)

    @cut_offset_mm ||= DEFAULT_CUT_OFFSET_MM
    @preview_images ||= []

    class << self
      def show
        @stats = build_stats
        invalidate_preview('Chưa xem trước. Bấm XEM TRƯỚC TRONG BẢNG.')

        if @dialog && @dialog.visible?
          sync_dialog
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
          sync_preview_state
        end

        @dialog.add_action_callback('refresh') do |_ctx|
          @stats = build_stats
          invalidate_preview('Đã quét lại mô hình. Cần xem trước lại.')
          sync_dialog
          sync_preview_state
        end

        @dialog.add_action_callback('preview_inline') do |_ctx, cut_mm|
          begin
            @cut_offset_mm = clamp_cut_offset(cut_mm)
            @stats = build_stats
            if @stats[:rows].empty?
              UI.messagebox('Không tìm thấy tấm ván hợp lệ để thống kê.')
              next
            end

            @preview_images = capture_inline_previews(Sketchup.active_model, @cut_offset_mm)
            @preview_signature = current_signature(@stats)
            @preview_ready = true

            payload = {
              cut_offset_mm: @cut_offset_mm,
              items: @preview_images,
              stats_rows: @stats[:rows].first(10).map { |row| tt_preview_row(row) },
              stats_total_rows: @stats[:rows].length,
              stats_pages: tt_stats_page_count(@stats)
            }
            @dialog.execute_script("window.renderLayoutPreview(#{JSON.generate(payload)})")
            sync_preview_state('ĐÃ XEM TRƯỚC TRONG BẢNG · sẵn sàng xuất.')
          rescue StandardError => error
            invalidate_preview("Xem trước thất bại: #{error.message}")
            sync_preview_state
            UI.messagebox("Xem trước Layout thất bại:\n#{error.message}")
            puts "[TT LayoutStats V030 preview] #{error.class}: #{error.message}"
          end
        end

        @dialog.add_action_callback('export_layout') do |_ctx|
          begin
            stats = validated_preview_stats
            export_layout(stats) if stats
          rescue StandardError => error
            UI.messagebox("Xuất LayOut thất bại:\n#{error.message}")
            puts "[TT LayoutStats V030 layout] #{error.class}: #{error.message}"
          end
        end

        @dialog.add_action_callback('export_pdf') do |_ctx|
          begin
            stats = validated_preview_stats
            export_pdf(stats) if stats
          rescue StandardError => error
            UI.messagebox("Xuất PDF thất bại:\n#{error.message}")
            puts "[TT LayoutStats V030 pdf] #{error.class}: #{error.message}"
          end
        end

        @dialog.set_on_closed do
          @dialog = nil
          @preview_images = []
        end
        @dialog.show
      rescue StandardError => error
        UI.messagebox("Không mở được Xuất Layout + Thống Kê Ván:\n#{error.message}")
      end

      def invalidate_preview(message = nil)
        @preview_ready = false
        @preview_signature = nil
        @preview_message = message.to_s
        @preview_images = []
      end

      def sync_preview_state(message = nil)
        return unless @dialog && @dialog.visible?
        text = message.to_s
        text = @preview_message.to_s if text.empty?
        text = @preview_ready ? 'ĐÃ XEM TRƯỚC · sẵn sàng xuất.' : 'CHƯA XEM TRƯỚC.' if text.empty?
        @dialog.execute_script(
          "window.setPreviewState(#{@preview_ready ? 'true' : 'false'}, #{JSON.generate(text)})"
        )
      end

      def sync_dialog
        return unless @dialog && @dialog.visible?
        @stats ||= build_stats

        payload = {
          version: VERSION,
          scope: @stats[:scope],
          total_pieces: @stats[:total_pieces],
          total_types: @stats[:total_types],
          total_area_m2: @stats[:total_area_m2].round(3),
          generated_at: @stats[:generated_at],
          page_count: 8 + tt_stats_page_count(@stats),
          cut_offset_mm: @cut_offset_mm,
          rows: @stats[:rows].map { |row| tt_preview_row(row) }
        }
        @dialog.execute_script("window.renderStats(#{JSON.generate(payload)})")
      end

      def tt_preview_row(row)
        {
          stt: row[:stt],
          name: row[:name],
          length_mm: row[:length_mm].round(1),
          width_mm: row[:width_mm].round(1),
          thickness_mm: row[:thickness_mm].round(1),
          qty: row[:qty],
          material: row[:material],
          grain: row[:grain],
          area_m2: row[:area_m2].round(3)
        }
      end

      def tt_stats_page_count(stats)
        [((stats[:rows].length.to_f / ROWS_PER_PAGE).ceil), 1].max
      end

      def clamp_cut_offset(value)
        number = value.to_f
        number = DEFAULT_CUT_OFFSET_MM if number <= 0.0
        [[number, 1.0].max, 500.0].min
      end

      def capture_inline_previews(model, cut_offset_mm)
        snapshot = tt_capture_model_state(model)
        bounds = tt_scope_bounds(model)
        raise 'Không có hình học để tạo phối cảnh.' unless bounds && bounds.valid?

        planes = tt_ensure_section_planes(model, bounds, cut_offset_mm)
        current_camera = tt_clone_camera(snapshot[:camera])
        view = model.active_view

        specs = [
          ['01 · PHỐI CẢNH TỔNG THỂ', current_camera, :normal, nil],
          ['02 · MẶT TRƯỚC', tt_ortho_camera(:front, bounds), :normal, nil],
          ['03 · BÊN TRÁI', tt_ortho_camera(:left, bounds), :normal, nil],
          ['04 · BÊN PHẢI', tt_ortho_camera(:right, bounds), :normal, nil],
          ['05 · MẶT CẮT TRƯỚC', tt_ortho_camera(:front, bounds), :section, planes[:cut_front]],
          ['06 · MẶT CẮT TRÁI', tt_ortho_camera(:left, bounds), :section, planes[:cut_left]],
          ['07 · MẶT CẮT PHẢI', tt_ortho_camera(:right, bounds), :section, planes[:cut_right]],
          ['08 · PHỐI CẢNH LINE + X-RAY', current_camera, :xray, nil]
        ]

        result = []
        begin
          specs.each_with_index do |spec, index|
            title, camera, profile, section = spec
            tt_apply_view_state(model, camera, profile, section)

            path = File.join(
              Dir.tmpdir,
              format('tt_layout_preview_%d_%02d.jpg', Process.pid, index + 1)
            )
            view.write_image(
              filename: path,
              width: PREVIEW_WIDTH,
              height: PREVIEW_HEIGHT,
              antialias: true,
              transparent: false
            )
            raise "Không tạo được ảnh #{title}" unless File.file?(path)

            result << {
              title: title,
              kind: profile.to_s,
              image: "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(path))}"
            }
            File.delete(path) rescue nil
          end
        ensure
          tt_restore_model_state(model, snapshot)
        end
        result
      end

      def tt_prepare_export_scenes(model, cut_offset_mm)
        snapshot = tt_capture_model_state(model)
        bounds = tt_scope_bounds(model)
        raise 'Không có hình học để tạo scene kỹ thuật.' unless bounds && bounds.valid?

        planes = tt_ensure_section_planes(model, bounds, cut_offset_mm)
        current_camera = tt_clone_camera(snapshot[:camera])
        scenes = {}

        model.start_operation('TRẦN TUẤN - Tạo Scene Layout', true)
        begin
          {
            cut_front: [tt_ortho_camera(:front, bounds), :section, planes[:cut_front]],
            cut_left: [tt_ortho_camera(:left, bounds), :section, planes[:cut_left]],
            cut_right: [tt_ortho_camera(:right, bounds), :section, planes[:cut_right]],
            line_xray: [current_camera, :xray, nil]
          }.each do |key, spec|
            camera, profile, plane = spec
            tt_apply_view_state(model, camera, profile, plane)
            page = tt_upsert_scene(model, SCENE_NAMES[key], profile)
            scenes[key] = tt_scene_layout_index(model, page)
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        ensure
          tt_restore_model_state(model, snapshot)
        end
        scenes
      end

      def tt_upsert_scene(model, name, profile)
        page = model.pages.to_a.find { |item| item.name.to_s == name.to_s }
        page ||= model.pages.add(name)
        page.use_camera = true if page.respond_to?(:use_camera=)
        page.use_rendering_options = true if page.respond_to?(:use_rendering_options=)
        page.use_section_planes = true if page.respond_to?(:use_section_planes=)
        page.include_in_animation = false if page.respond_to?(:include_in_animation=)

        flags = 0
        flags |= PAGE_USE_CAMERA if defined?(PAGE_USE_CAMERA)
        flags |= PAGE_USE_RENDERING_OPTIONS if defined?(PAGE_USE_RENDERING_OPTIONS)
        flags |= PAGE_USE_SECTION_PLANES if defined?(PAGE_USE_SECTION_PLANES)
        flags == 0 ? page.update : page.update(flags)

        begin
          tt_apply_render_profile(page.rendering_options, profile)
        rescue StandardError
          nil
        end
        page
      end

      def tt_scene_layout_index(model, page)
        index = model.pages.to_a.index(page)
        raise "Không tìm thấy scene #{page.name}" unless index
        index + 1
      end

      def tt_scope_bounds(model)
        selected = model.selection.to_a.select { |e| e.respond_to?(:bounds) && e.valid? }
        return model.bounds if selected.empty?

        bb = Geom::BoundingBox.new
        selected.each do |entity|
          eb = entity.bounds
          next unless eb && eb.valid?
          8.times { |i| bb.add(eb.corner(i)) }
        end
        bb.valid? ? bb : model.bounds
      rescue StandardError
        model.bounds
      end

      def tt_ortho_camera(side, bb)
        center = bb.center
        distance = [bb.diagonal.to_f * 2.5, 1000.mm.to_f].max

        case side
        when :left
          eye = center.offset(Geom::Vector3d.new(-1, 0, 0), distance)
          horizontal = bb.height.to_f
        when :right
          eye = center.offset(Geom::Vector3d.new(1, 0, 0), distance)
          horizontal = bb.height.to_f
        else
          eye = center.offset(Geom::Vector3d.new(0, -1, 0), distance)
          horizontal = bb.width.to_f
        end

        camera = Sketchup::Camera.new(eye, center, Z_AXIS, false)
        vertical = bb.depth.to_f
        fit_height = [vertical, horizontal / (420.0 / 297.0)].max * 1.22
        camera.height = [fit_height, 100.mm.to_f].max
        camera
      end

      def tt_ensure_section_planes(model, bb, cut_offset_mm)
        offset = cut_offset_mm.to_f / 25.4
        x_off = [offset, bb.width.to_f * 0.45].min
        y_off = [offset, bb.height.to_f * 0.45].min
        center = bb.center

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
        SECTION_NAMES.each do |key, name|
          plane = model.entities.grep(Sketchup::SectionPlane).find do |item|
            item.valid? && item.name.to_s == name
          end

          unless plane
            plane = model.entities.add_section_plane(points[key], normals[key])
            plane.name = name if plane.respond_to?(:name=)
          end

          begin
            plane.set_plane([points[key], normals[key]])
          rescue StandardError
            plane.erase! if plane.valid?
            plane = model.entities.add_section_plane(points[key], normals[key])
            plane.name = name if plane.respond_to?(:name=)
          end

          begin
            plane.hidden = true
          rescue StandardError
            nil
          end
          out[key] = plane
        end
        out
      end

      def tt_apply_view_state(model, camera, profile, section)
        model.entities.active_section_plane = section
        model.active_view.camera = tt_clone_camera(camera)
        tt_apply_render_profile(model.rendering_options, profile)
        model.active_view.refresh
      end

      def tt_apply_render_profile(options, profile)
        values =
          case profile
          when :section
            {
              'ModelTransparency' => false,
              'MaterialTransparency' => true,
              'DrawBackEdges' => false,
              'DisplaySectionCuts' => true,
              'DisplaySectionPlanes' => false,
              'SectionCutDrawEdges' => true,
              'SectionCutFilled' => false,
              'Texture' => false,
              'EdgeDisplayMode' => 0,
              'RenderMode' => 1
            }
          when :xray
            {
              'ModelTransparency' => true,
              'MaterialTransparency' => true,
              'DrawBackEdges' => true,
              'DisplaySectionCuts' => false,
              'DisplaySectionPlanes' => false,
              'Texture' => false,
              'EdgeDisplayMode' => 0,
              'RenderMode' => 2
            }
          else
            {
              'ModelTransparency' => false,
              'MaterialTransparency' => true,
              'DrawBackEdges' => false,
              'DisplaySectionCuts' => false,
              'DisplaySectionPlanes' => false,
              'Texture' => true,
              'EdgeDisplayMode' => 0,
              'RenderMode' => 2
            }
          end

        values.each { |key, value| options[key] = value rescue nil }
      end

      def tt_capture_model_state(model)
        render = {}
        RENDER_KEYS.each { |key| render[key] = model.rendering_options[key] rescue nil }
        {
          camera: tt_clone_camera(model.active_view.camera),
          render: render,
          active_section: model.entities.active_section_plane,
          selected_page: model.pages.selected_page
        }
      end

      def tt_restore_model_state(model, state)
        model.pages.selected_page = state[:selected_page] if state[:selected_page] rescue nil
        model.entities.active_section_plane = state[:active_section] rescue nil
        model.active_view.camera = tt_clone_camera(state[:camera]) rescue nil
        state[:render].each { |key, value| model.rendering_options[key] = value rescue nil }
        model.active_view.refresh
      end

      def tt_clone_camera(camera)
        copy = Sketchup::Camera.new(
          camera.eye, camera.target, camera.up,
          camera.perspective?,
          camera.perspective? ? camera.fov : 30.0
        )
        copy.height = camera.height unless camera.perspective? rescue nil
        copy.aspect_ratio = camera.aspect_ratio rescue nil
        copy
      end

      def validated_preview_stats
        unless @preview_ready && @preview_signature
          UI.messagebox('Bạn cần bấm XEM TRƯỚC TRONG BẢNG trước khi xuất.')
          return nil
        end

        fresh = build_stats
        unless current_signature(fresh) == @preview_signature
          @stats = fresh
          invalidate_preview('Mô hình / selection / camera đã thay đổi. Hãy xem trước lại.')
          sync_dialog
          sync_preview_state
          UI.messagebox('Dữ liệu đã thay đổi. Hãy XEM TRƯỚC TRONG BẢNG lại.')
          return nil
        end

        @stats = fresh
        fresh
      end

      def current_signature(stats)
        model = Sketchup.active_model
        camera = model.active_view.camera
        selection = model.selection.to_a.map do |entity|
          entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
        end.sort

        data = {
          rows: stats[:rows].map do |row|
            [
              row[:name].to_s,
              row[:length_mm].round(2),
              row[:width_mm].round(2),
              row[:thickness_mm].round(2),
              row[:qty].to_i,
              row[:material].to_s,
              row[:grain].to_s
            ]
          end,
          selection: selection,
          camera: [
            camera.eye.to_a.map { |v| v.to_f.round(5) },
            camera.target.to_a.map { |v| v.to_f.round(5) },
            camera.up.to_a.map { |v| v.to_f.round(5) },
            camera.perspective?,
            camera.perspective? ? camera.fov.to_f.round(4) : camera.height.to_f.round(4)
          ],
          cut: @cut_offset_mm.to_f.round(2)
        }
        Digest::SHA256.hexdigest(JSON.generate(data))
      end

      def export_layout(stats)
        ensure_layout_api!
        model = Sketchup.active_model
        skp_path = ensure_model_saved(model)
        return false unless skp_path

        scenes = tt_prepare_export_scenes(model, @cut_offset_mm)
        model.save
        doc = tt_build_layout_document(stats, skp_path, scenes)

        default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_LAYOUT.layout'
        path = UI.savepanel('Xuất LayOut + Thống Kê Ván', File.dirname(skp_path), default_name)
        return false unless path
        path += '.layout' unless File.extname(path).downcase == '.layout'

        version = defined?(Layout::Document::VERSION_2022) ?
          Layout::Document::VERSION_2022 : Layout::Document::VERSION_CURRENT
        doc.save(path, version)
        UI.messagebox("Đã xuất LayOut thành công.\n\n#{path}")
        true
      end

      def export_pdf(stats)
        ensure_layout_api!
        model = Sketchup.active_model
        skp_path = ensure_model_saved(model)
        return false unless skp_path

        scenes = tt_prepare_export_scenes(model, @cut_offset_mm)
        model.save
        doc = tt_build_layout_document(stats, skp_path, scenes)

        default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_LAYOUT.pdf'
        path = UI.savepanel('Xuất PDF Layout', File.dirname(skp_path), default_name)
        return false unless path
        path += '.pdf' unless File.extname(path).downcase == '.pdf'

        doc.export(
          path,
          start_page: 0,
          end_page: doc.pages.length - 1,
          compress_images: true,
          compress_quality: 0.90
        )
        UI.messagebox("Đã xuất PDF thành công.\n\n#{path}")
        true
      end

      def tt_build_layout_document(stats, skp_path, scenes)
        doc = Layout::Document.new
        setup_a3(doc)
        layer = doc.layers.first
        layer.name = 'TRẦN TUẤN - NỘI THẤT' if layer.respond_to?(:name=)

        tt_add_view_page(doc, layer, doc.pages.first,
          '01 - TỔNG THỂ', 'PHỐI CẢNH TỔNG THỂ', skp_path, stats, :overview, nil)

        tt_add_view_page(doc, layer, doc.pages.add('02 - MẶT TRƯỚC'),
          '02 - MẶT TRƯỚC', 'MẶT TRƯỚC', skp_path, stats, :front, nil)

        tt_add_view_page(doc, layer, doc.pages.add('03 - BÊN TRÁI'),
          '03 - BÊN TRÁI', 'BÊN TRÁI', skp_path, stats, :left, nil)

        tt_add_view_page(doc, layer, doc.pages.add('04 - BÊN PHẢI'),
          '04 - BÊN PHẢI', 'BÊN PHẢI', skp_path, stats, :right, nil)

        tt_add_view_page(doc, layer, doc.pages.add('05 - MẶT CẮT TRƯỚC'),
          '05 - MẶT CẮT TRƯỚC', "MẶT CẮT TRƯỚC · #{@cut_offset_mm.round(1)}mm",
          skp_path, stats, :scene, scenes[:cut_front])

        tt_add_view_page(doc, layer, doc.pages.add('06 - MẶT CẮT TRÁI'),
          '06 - MẶT CẮT TRÁI', "MẶT CẮT TRÁI · #{@cut_offset_mm.round(1)}mm",
          skp_path, stats, :scene, scenes[:cut_left])

        tt_add_view_page(doc, layer, doc.pages.add('07 - MẶT CẮT PHẢI'),
          '07 - MẶT CẮT PHẢI', "MẶT CẮT PHẢI · #{@cut_offset_mm.round(1)}mm",
          skp_path, stats, :scene, scenes[:cut_right])

        tt_add_view_page(doc, layer, doc.pages.add('08 - LINE + X-RAY'),
          '08 - LINE + X-RAY', 'PHỐI CẢNH LINE + X-RAY',
          skp_path, stats, :scene, scenes[:line_xray])

        tt_add_statistics_pages(doc, layer, stats, 9)
        doc
      end

      def tt_add_view_page(doc, layer, page, page_name, title, skp_path, stats, mode, scene_index)
        page.name = page_name
        add_text(doc, layer, page, "TRẦN TUẤN NỘI THẤT · #{title}",
          0.45, 0.28, 15.55, 0.55, 19, true, orange)
        add_text(doc, layer, page, "#{File.basename(skp_path)} · #{stats[:scope]}",
          0.45, 0.82, 15.55, 0.34, 9.0, false, gray)

        viewport = Layout::SketchUpModel.new(
          skp_path,
          Geom::Bounds2d.new(0.55, 1.23, 15.40, 8.95)
        )
        viewport.display_background = false
        viewport.preserve_scale_on_resize = false

        case mode
        when :front
          viewport.view = Layout::SketchUpModel::FRONT_VIEW
          viewport.perspective = false
        when :left
          viewport.view = Layout::SketchUpModel::LEFT_VIEW
          viewport.perspective = false
        when :right
          viewport.view = Layout::SketchUpModel::RIGHT_VIEW
          viewport.perspective = false
        when :scene
          viewport.current_scene = scene_index.to_i
        end
        viewport.render_mode = Layout::SketchUpModel::HYBRID_RENDER
        doc.add_entity(viewport, layer, page)

        begin
          viewport.render if viewport.respond_to?(:render) && viewport.render_needed?
        rescue StandardError
          nil
        end

        summary = "#{stats[:total_pieces]} TẤM · #{stats[:total_types]} LOẠI · " \
                  "#{format('%.3f', stats[:total_area_m2])} m² · #{stats[:generated_at]}"
        add_text(doc, layer, page, summary, 0.55, 10.32, 15.40, 0.45, 10.0, true, dark)
      end

      def tt_add_statistics_pages(doc, layer, stats, first_number)
        chunks = stats[:rows].each_slice(ROWS_PER_PAGE).to_a
        chunks = [[]] if chunks.empty?

        chunks.each_with_index do |chunk, index|
          page_number = first_number + index
          page = doc.pages.add(format('%02d - THỐNG KÊ VÁN%s',
            page_number, index.zero? ? '' : " #{index + 1}"))

          add_text(doc, layer, page, 'BẢNG THỐNG KÊ VÁN',
            0.45, 0.28, 15.55, 0.50, 19, true, orange)

          subtitle = "#{stats[:scope]} · #{stats[:total_pieces]} tấm · " \
                     "#{format('%.3f', stats[:total_area_m2])} m² · " \
                     "Trang #{index + 1}/#{chunks.length}"
          add_text(doc, layer, page, subtitle,
            0.45, 0.80, 15.55, 0.35, 9.5, false, gray)

          add_stats_table(doc, layer, page, chunk)
          add_text(doc, layer, page, "TRẦN TUẤN NỘI THẤT · #{stats[:generated_at]}",
            0.45, 11.08, 15.55, 0.30, 8.5, false, gray)
        end
      end

      def dialog_html
        <<~HTML
          <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}body{margin:0;background:#111827;color:#e5e7eb;font:14px Arial}
          .head{padding:20px 24px;background:linear-gradient(135deg,#f97316,#c2410c)}
          h1{margin:0;font-size:22px}.sub{margin-top:5px;opacity:.92}.body{padding:18px}
          .cards{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin-bottom:14px}
          .card,.panel{background:#1f2937;border:1px solid #374151;border-radius:10px;padding:12px}
          .n{font-size:22px;font-weight:bold;color:#fdba74}.k{font-size:11px;color:#9ca3af;margin-top:3px}
          .scope{margin:10px 0;color:#fbbf24}
          .setup{display:grid;grid-template-columns:180px 1fr auto;gap:10px;align-items:end;margin:12px 0}
          label{display:block;color:#d1d5db;font-size:12px;margin-bottom:5px}
          input{width:100%;padding:10px;border-radius:7px;border:1px solid #4b5563;background:#111827;color:#fff}
          .previewstate{padding:10px 12px;border-radius:8px;background:#7c2d12;color:#fff;margin:12px 0;font-weight:bold}
          .previewstate.ok{background:#065f46}
          .gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin-top:12px}
          .sheet{background:#fff;color:#111827;border:1px solid #4b5563;border-radius:8px;overflow:hidden;box-shadow:0 4px 14px #0006}
          .sheethead{padding:8px 10px;font-weight:bold;font-size:12px;color:#9a3412;border-bottom:1px solid #ddd;display:flex;justify-content:space-between}
          .sheet img{display:block;width:100%;aspect-ratio:420/297;object-fit:cover;background:#f3f4f6}
          .placeholder{width:100%;aspect-ratio:420/297;display:flex;align-items:center;justify-content:center;background:#e5e7eb;color:#6b7280}
          .statsmini{padding:10px;background:#fff;color:#111827;aspect-ratio:420/297;overflow:hidden}
          .tablewrap{max-height:330px;overflow:auto;border:1px solid #374151;border-radius:9px;margin-top:14px}
          table{width:100%;border-collapse:collapse;background:#111827}
          th{position:sticky;top:0;background:#374151;color:#fff;padding:8px;border:1px solid #4b5563;font-size:12px}
          td{padding:7px;border:1px solid #374151;font-size:12px}td.num{text-align:right;white-space:nowrap}
          .buttons{display:flex;flex-wrap:wrap;gap:10px;margin-top:15px}
          button{padding:11px 16px;border:0;border-radius:8px;font-weight:bold;cursor:pointer}
          button:disabled{opacity:.35;cursor:not-allowed}.primary{background:#f97316;color:#fff}
          .green{background:#059669;color:#fff}.blue{background:#2563eb;color:#fff}.dark{background:#374151;color:#fff}
          .note{margin-top:10px;font-size:12px;color:#9ca3af;line-height:1.5}
          .tag{padding:3px 7px;border-radius:999px;background:#ffedd5;color:#9a3412;font-size:10px}
          </style></head><body>
          <div class="head"><h1>XUẤT LAYOUT + THỐNG KÊ VÁN</h1>
          <div class="sub">TRẦN TUẤN NỘI THẤT · V<span id="ver">-</span> · A3 NGANG · XEM TRƯỚC NGAY TRONG BẢNG</div></div>
          <div class="body">

          <div class="cards">
          <div class="card"><div class="n" id="pieces">0</div><div class="k">TỔNG SỐ TẤM</div></div>
          <div class="card"><div class="n" id="types">0</div><div class="k">LOẠI TẤM</div></div>
          <div class="card"><div class="n" id="area">0</div><div class="k">TỔNG m²</div></div>
          <div class="card"><div class="n" id="rows">0</div><div class="k">DÒNG THỐNG KÊ</div></div>
          <div class="card"><div class="n" id="pages">0</div><div class="k">TỔNG TRANG</div></div>
          </div>

          <div class="scope" id="scope">-</div>

          <div class="panel"><b>CÀI ĐẶT BẢN VẼ</b>
          <div class="setup">
          <div><label>Khoảng cắt từ mặt ngoài (mm)</label>
          <input id="cut" type="number" min="1" max="500" step="1" value="20"></div>
          <div class="note">Tạo 3 mặt cắt: trước, trái, phải. Có thêm phối cảnh Line + X-Ray.</div>
          <button class="green" onclick="previewInline()">XEM TRƯỚC TRONG BẢNG</button>
          </div></div>

          <div id="previewstate" class="previewstate">CHƯA XEM TRƯỚC</div>

          <div class="panel"><b>XEM TRƯỚC CÁC TRANG LAYOUT</b>
          <div class="note">Không mở phần mềm khác. Hình xem trước được render trực tiếp trong SketchUp.</div>
          <div id="gallery" class="gallery">
          <div class="sheet"><div class="sheethead">01 · PHỐI CẢNH TỔNG THỂ</div><div class="placeholder">Bấm XEM TRƯỚC TRONG BẢNG</div></div>
          <div class="sheet"><div class="sheethead">02 · MẶT TRƯỚC</div><div class="placeholder">Chưa dựng</div></div>
          <div class="sheet"><div class="sheethead">03 · BÊN TRÁI</div><div class="placeholder">Chưa dựng</div></div>
          <div class="sheet"><div class="sheethead">04 · BÊN PHẢI</div><div class="placeholder">Chưa dựng</div></div>
          <div class="sheet"><div class="sheethead">05 · MẶT CẮT TRƯỚC</div><div class="placeholder">Chưa dựng</div></div>
          <div class="sheet"><div class="sheethead">06 · MẶT CẮT TRÁI</div><div class="placeholder">Chưa dựng</div></div>
          <div class="sheet"><div class="sheethead">07 · MẶT CẮT PHẢI</div><div class="placeholder">Chưa dựng</div></div>
          <div class="sheet"><div class="sheethead">08 · LINE + X-RAY</div><div class="placeholder">Chưa dựng</div></div>
          </div></div>

          <div class="tablewrap"><table><thead><tr>
          <th>STT</th><th>TÊN TẤM</th><th>DÀI</th><th>RỘNG</th><th>DÀY</th><th>SL</th><th>VẬT LIỆU</th><th>VÂN</th><th>m²</th>
          </tr></thead><tbody id="body"></tbody></table></div>

          <div class="buttons">
          <button id="layoutBtn" class="primary" disabled onclick="sketchup.export_layout()">XUẤT LAYOUT</button>
          <button id="pdfBtn" class="blue" disabled onclick="sketchup.export_pdf()">XUẤT PDF</button>
          <button class="dark" onclick="sketchup.refresh()">QUÉT LẠI</button>
          <button class="dark" onclick="window.close()">ĐÓNG</button>
          </div>

          <div class="note">Thứ tự: Tổng thể → Trước → Trái → Phải → Cắt trước → Cắt trái → Cắt phải → Line + X-Ray → Thống kê ván.</div>
          </div>

          <script>
          const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

          window.renderStats=d=>{
            ver.textContent=d.version; pieces.textContent=d.total_pieces; types.textContent=d.total_types;
            area.textContent=Number(d.total_area_m2).toFixed(3); rows.textContent=d.rows.length;
            pages.textContent=d.page_count; cut.value=d.cut_offset_mm||20;
            scope.textContent='PHẠM VI: '+d.scope+' · '+d.generated_at;
            const tb=document.getElementById('body');tb.innerHTML='';
            d.rows.forEach(r=>{
              const tr=document.createElement('tr');
              tr.innerHTML=`<td class="num">${r.stt}</td><td>${esc(r.name)}</td>`+
              `<td class="num">${Number(r.length_mm).toFixed(1)}</td>`+
              `<td class="num">${Number(r.width_mm).toFixed(1)}</td>`+
              `<td class="num">${Number(r.thickness_mm).toFixed(1)}</td>`+
              `<td class="num">${r.qty}</td><td>${esc(r.material)}</td><td>${esc(r.grain)}</td>`+
              `<td class="num">${Number(r.area_m2).toFixed(3)}</td>`;
              tb.appendChild(tr);
            });
          };

          window.setPreviewState=(ok,msg)=>{
            const s=document.getElementById('previewstate');
            s.textContent=msg; s.className='previewstate'+(ok?' ok':'');
            layoutBtn.disabled=!ok; pdfBtn.disabled=!ok;
          };

          function miniStats(rows,totalRows,pagesCount){
            let h='<div class="statsmini"><b>BẢNG THỐNG KÊ VÁN</b>';
            h+=`<div style="font-size:8px;margin:5px 0;color:#666">Hiển thị ${rows.length}/${totalRows} dòng · ${pagesCount} trang</div>`;
            h+='<table style="background:white;color:#111;font-size:7px"><tr><th style="position:static;font-size:7px">STT</th><th style="position:static;font-size:7px">TÊN</th><th style="position:static;font-size:7px">D×R×D</th><th style="position:static;font-size:7px">SL</th></tr>';
            rows.forEach(r=>{h+=`<tr><td>${r.stt}</td><td>${esc(r.name)}</td><td>${Number(r.length_mm).toFixed(0)}×${Number(r.width_mm).toFixed(0)}×${Number(r.thickness_mm).toFixed(1)}</td><td>${r.qty}</td></tr>`;});
            return h+'</table></div>';
          }

          window.renderLayoutPreview=d=>{
            cut.value=d.cut_offset_mm;
            const g=document.getElementById('gallery');g.innerHTML='';
            d.items.forEach(item=>{
              const e=document.createElement('div');e.className='sheet';
              e.innerHTML=`<div class="sheethead"><span>${esc(item.title)}</span><span class="tag">A3</span></div><img src="${item.image}">`;
              g.appendChild(e);
            });
            const s=document.createElement('div');s.className='sheet';
            s.innerHTML='<div class="sheethead"><span>09+ · THỐNG KÊ VÁN</span><span class="tag">A3</span></div>'+miniStats(d.stats_rows,d.stats_total_rows,d.stats_pages);
            g.appendChild(s);
          };

          function previewInline(){
            setPreviewState(false,'ĐANG DỰNG XEM TRƯỚC TRONG BẢNG...');
            sketchup.preview_inline(Number(cut.value));
          }

          document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
          </script></body></html>
        HTML
      end
    end
  end
end
