# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.7.0
# TÁCH RÕ XUẤT LAYOUT / XUẤT PDF
# - Xuất LayOut: CHỈ 3 trang phối cảnh/kỹ thuật, KHÔNG có bảng thống kê ván.
# - Xuất PDF: xuất trực tiếp 3 trang phối cảnh/kỹ thuật + các trang thống kê ván.
# - PDF không lưu file .layout trung gian.
# - Giữ nguyên scope MODE, multi MODE, preview tuần tự và bố cục A3 của V0.6.0.

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.7.0'.freeze

    class << self
      def tt_build_views_only_document(job, skp_path, scenes)
        doc = Layout::Document.new
        setup_a3(doc)
        layer = doc.layers.first
        layer.name = 'TRẦN TUẤN - NỘI THẤT' if layer.respond_to?(:name=)

        p1 = doc.pages.first
        p1.name = '01 - TỔNG QUAN + X-RAY'
        tt_add_compact_header(doc, layer, p1, 'TỔNG QUAN + LINE/X-RAY', job, skp_path)
        tt_add_scene_viewport(doc, layer, p1, skp_path, scenes[:overview], 0.45, 1.18, 10.25, 9.55, 'PHỐI CẢNH TỔNG THỂ')
        tt_add_scene_viewport(doc, layer, p1, skp_path, scenes[:xray], 10.95, 1.18, 5.05, 5.25, 'LINE + X-RAY')
        add_text(
          doc, layer, p1,
          'LAYOUT PHỐI CẢNH / KỸ THUẬT · KHÔNG KÈM THỐNG KÊ VÁN',
          10.98, 6.85, 4.92, 0.72, 9.2, true, gray
        )

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

        doc
      end

      def tt_build_pdf_document(job, skp_path, scenes)
        # PDF dùng đầy đủ 3 trang phối cảnh/kỹ thuật + thống kê ván.
        # Hàm V0.6.0 đã dựng đúng bố cục compact và thêm thống kê từ trang 4.
        tt_build_compact_document(job, skp_path, scenes)
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

        default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_CANH.layout'
        base_path = UI.savepanel('Xuất LayOut - chỉ phối cảnh/kỹ thuật', File.dirname(skp_path), default_name)
        return false unless base_path
        base_path += '.layout' unless File.extname(base_path).downcase == '.layout'

        version = if defined?(Layout::Document::VERSION_2022)
                    Layout::Document::VERSION_2022
                  else
                    Layout::Document::VERSION_CURRENT
                  end

        outputs = []
        jobs.each_with_index do |job, index|
          doc = tt_build_views_only_document(job, skp_path, scene_sets[index])
          path = tt_output_path(base_path, job, index, jobs.length, 'layout')
          doc.save(path, version)
          outputs << path
        end

        UI.messagebox(
          "Đã xuất #{outputs.length} LayOut CHỈ PHỐI CẢNH / KỸ THUẬT.\n" \
          "Không kèm bảng thống kê ván.\n\n#{outputs.join("\n")}"
        )
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

        default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_BAN_VE_THONG_KE.pdf'
        base_path = UI.savepanel(
          'Xuất PDF trực tiếp - phối cảnh + thống kê ván',
          File.dirname(skp_path),
          default_name
        )
        return false unless base_path
        base_path += '.pdf' unless File.extname(base_path).downcase == '.pdf'

        outputs = []
        jobs.each_with_index do |job, index|
          # Chỉ dựng document tạm trong RAM rồi export PDF trực tiếp.
          # Không gọi doc.save và không tạo .layout trung gian.
          doc = tt_build_pdf_document(job, skp_path, scene_sets[index])
          path = tt_output_path(base_path, job, index, jobs.length, 'pdf')
          doc.export(
            path,
            start_page: 0,
            end_page: doc.pages.length - 1,
            compress_images: true,
            compress_quality: 0.94
          )
          outputs << path
        end

        UI.messagebox(
          "Đã xuất trực tiếp #{outputs.length} PDF.\n" \
          "PDF gồm phối cảnh / mặt đứng / mặt cắt / X-Ray + thống kê ván.\n" \
          "Không tạo file LayOut trung gian.\n\n#{outputs.join("\n")}"
        )
        true
      end
    end
  end
end
