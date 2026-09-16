# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.8.1
# FIX KHOẢNG CẮT TỪ MẶT NGOÀI
# - Bỏ giới hạn cũ 45% làm nhiều giá trị mm rơi vào cùng một vị trí.
# - Cắt trước đo từ Y min; cắt trái từ X min; cắt phải từ X max.
# - Chỉ chặn sát mặt đối diện để section plane luôn nằm trong MODE.
# - Bounds được quy đổi từ active context về Model Axis bằng edit_transform.
# - Preview hiển thị số mm đang dùng và đổi input sẽ bắt xem trước lại.

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.8.1'.freeze

    CUT_EPSILON_MM = 0.5 unless const_defined?(:CUT_EPSILON_MM, false)
    CUT_MAX_INPUT_MM = 5000.0 unless const_defined?(:CUT_MAX_INPUT_MM, false)

    class << self
      alias_method :tt_v081_dialog_html_base, :dialog_html unless method_defined?(:tt_v081_dialog_html_base)
      alias_method :tt_v081_preview_tasks_base, :tt_preview_tasks unless method_defined?(:tt_v081_preview_tasks_base)
      alias_method :tt_v081_page_title_base, :tt_page_title unless method_defined?(:tt_v081_page_title_base)

      def clamp_cut_offset(value)
        number = value.to_f
        number = DEFAULT_CUT_OFFSET_MM if number.nan? || number.infinite? || number <= 0.0
        [[number, 0.1].max, CUT_MAX_INPUT_MM].min
      rescue StandardError
        DEFAULT_CUT_OFFSET_MM
      end

      # Luôn trả bounds theo Model Axis / model root coordinates.
      # Khi đang edit Group/Component, entity.bounds nằm trong active context nên
      # phải đi qua model.edit_transform trước khi dùng cho camera/section plane.
      def tt_scope_bounds_for_roots(model, roots)
        return model.bounds if roots.nil? || roots.empty?

        bb = Geom::BoundingBox.new
        tr = model.edit_transform || Geom::Transformation.new
        roots.each do |entity|
          next unless entity && entity.valid? && entity.respond_to?(:bounds)
          eb = entity.bounds
          next unless eb && eb.valid?
          8.times { |i| bb.add(eb.corner(i).transform(tr)) }
        end
        bb.valid? ? bb : model.bounds
      rescue StandardError => error
        puts "[TT LayoutStats V081 bounds] #{error.class}: #{error.message}"
        model.bounds
      end

      def tt_v081_effective_offsets(bb, requested_mm)
        requested_in = clamp_cut_offset(requested_mm).mm.to_f
        epsilon_in = CUT_EPSILON_MM.mm.to_f

        x_span = bb.width.to_f.abs
        y_span = bb.height.to_f.abs

        x_max = [x_span - epsilon_in, epsilon_in].max
        y_max = [y_span - epsilon_in, epsilon_in].max

        x_in = [[requested_in, epsilon_in].max, x_max].min
        y_in = [[requested_in, epsilon_in].max, y_max].min

        {
          left: x_in,
          right: x_in,
          front: y_in,
          left_mm: x_in.to_f * 25.4,
          right_mm: x_in.to_f * 25.4,
          front_mm: y_in.to_f * 25.4
        }
      end

      def tt_ensure_section_planes_for_job(model, bb, cut_offset_mm, job)
        offsets = tt_v081_effective_offsets(bb, cut_offset_mm)
        center = bb.center
        suffix = Digest::SHA1.hexdigest(job[:key].to_s)[0, 8]

        points = {
          cut_front: Geom::Point3d.new(center.x, bb.min.y + offsets[:front], center.z),
          cut_left:  Geom::Point3d.new(bb.min.x + offsets[:left], center.y, center.z),
          cut_right: Geom::Point3d.new(bb.max.x - offsets[:right], center.y, center.z)
        }
        normals = {
          cut_front: Geom::Vector3d.new(0, -1, 0),
          cut_left:  Geom::Vector3d.new(-1, 0, 0),
          cut_right: Geom::Vector3d.new(1, 0, 0)
        }

        out = {}
        points.each do |key, point|
          name = "TT_LAYOUT_#{suffix}_#{key.to_s.upcase}"
          plane = model.entities.grep(Sketchup::SectionPlane).find do |item|
            item.valid? && item.name.to_s == name
          end

          unless plane
            plane = model.entities.add_section_plane(point, normals[key])
            plane.name = name if plane.respond_to?(:name=)
          end

          begin
            plane.set_plane([point, normals[key]])
          rescue StandardError
            plane.erase! if plane && plane.valid?
            plane = model.entities.add_section_plane(point, normals[key])
            plane.name = name if plane.respond_to?(:name=)
          end

          plane.hidden = true if plane.respond_to?(:hidden=)
          begin
            effective_mm = case key
                           when :cut_front then offsets[:front_mm]
                           when :cut_left then offsets[:left_mm]
                           else offsets[:right_mm]
                           end
            plane.set_attribute('TT_LAYOUT_SECTION', 'requested_offset_mm', clamp_cut_offset(cut_offset_mm))
            plane.set_attribute('TT_LAYOUT_SECTION', 'effective_offset_mm', effective_mm.round(3))
            plane.set_attribute('TT_LAYOUT_SECTION', 'source_side', key.to_s)
          rescue StandardError
            nil
          end
          out[key] = plane
        end
        out
      rescue StandardError => error
        puts "[TT LayoutStats V081 planes] #{error.class}: #{error.message}"
        raise
      end

      # Giữ nguyên 5 trang của V0.8.0 nhưng ghi rõ mm thật trên 3 preview mặt cắt.
      def tt_preview_tasks(model, job)
        tasks = tt_v081_preview_tasks_base(model, job)
        bb = tt_scope_bounds_for_roots(model, job[:roots])
        offsets = tt_v081_effective_offsets(bb, @cut_offset_mm)
        labels = {
          'MẶT CẮT TRƯỚC' => format('MẶT CẮT TRƯỚC · %.1f mm', offsets[:front_mm]),
          'MẶT CẮT TRÁI' => format('MẶT CẮT TRÁI · %.1f mm', offsets[:left_mm]),
          'MẶT CẮT PHẢI' => format('MẶT CẮT PHẢI · %.1f mm', offsets[:right_mm])
        }
        tasks.each do |task|
          replacement = labels[task[:title].to_s]
          next unless replacement
          task[:title] = replacement
          task[:spec][0] = replacement if task[:spec].is_a?(Array)
        end
        tasks
      rescue StandardError => error
        puts "[TT LayoutStats V081 task label] #{error.class}: #{error.message}"
        tt_v081_preview_tasks_base(model, job)
      end

      def tt_page_title(job, page)
        title = tt_v081_page_title_base(job, page)
        page == :sections ? "#{title} · CẮT #{@cut_offset_mm.to_f.round(1)} mm TỪ MẶT NGOÀI" : title
      end

      # Không cho xuất bằng preview cũ sau khi người dùng đổi ô khoảng cắt.
      def dialog_html
        html = tt_v081_dialog_html_base.to_s
        old_input = 'id="cut" type="number" min="1" max="500" step="1" value="20"'
        new_input = 'id="cut" type="number" min="0.1" max="5000" step="1" value="20" oninput="if(window.setPreviewState){window.setPreviewState(false,\'ĐÃ ĐỔI KHOẢNG CẮT · HÃY XEM TRƯỚC LẠI\');}"'
        html = html.gsub(old_input, new_input)
        html = html.gsub(
          'Tạo 3 mặt cắt: trước, trái, phải. Có thêm phối cảnh Line + X-Ray.',
          'Khoảng cắt được đo THẬT từ mặt ngoài của MODE: trước từ mặt trước, trái từ mép trái, phải từ mép phải. Đổi số mm phải XEM TRƯỚC lại.'
        )
        html
      end
    end
  end
end
