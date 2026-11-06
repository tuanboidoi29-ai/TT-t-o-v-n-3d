# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT RIÊNG + LỌC DIM TRÙNG
# V0.11.0
#
# - Layout/PDF chỉ chứa bản vẽ kỹ thuật, không còn trang thống kê ván.
# - Preview không hiển thị bảng thống kê.
# - Layout không quét/không phụ thuộc dữ liệu thống kê ván để nhận MODE.
# - Trong từng hình chiếu, chỉ giữ một DIM cho mỗi trị số; DIM phủ bì được ưu tiên.
# - DIM cùng số ở hình chiếu khác vẫn được giữ.

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.11.0'.freeze

    DIM_DUPLICATE_TOL_MM = 0.2 unless const_defined?(:DIM_DUPLICATE_TOL_MM, false)

    class << self
      alias_method :tt_v110_original_dialog_html, :dialog_html unless method_defined?(:tt_v110_original_dialog_html)
      alias_method :tt_v110_original_append_stream_item, :tt_append_stream_item unless method_defined?(:tt_v110_original_append_stream_item)
      alias_method :tt_v110_original_sync_dialog, :sync_dialog unless method_defined?(:tt_v110_original_sync_dialog)
      alias_method :tt_v110_original_build_document, :tt_build_five_view_document unless method_defined?(:tt_v110_original_build_document)
      alias_method :tt_v110_original_layout_jobs, :tt_layout_jobs unless method_defined?(:tt_v110_original_layout_jobs)
      alias_method :tt_v110_original_ensure_dimensions, :tt_ensure_dimensions_for_job unless method_defined?(:tt_v110_original_ensure_dimensions)
      alias_method :tt_v110_original_fast_export, :tt_fast_export unless method_defined?(:tt_v110_original_fast_export)

      # ---------- LAYOUT: KHÔNG PHỤ THUỘC THỐNG KÊ VÁN ----------

      def tt_layout_root_valid?(entity)
        return false unless entity && entity.valid? && container?(entity)
        bounds = entity.bounds
        bounds && bounds.valid? && bounds.diagonal.to_f > 0.0
      rescue StandardError
        false
      end

      def tt_empty_layout_stats(scope)
        {
          rows: [],
          total_pieces: 0,
          total_types: 0,
          total_area_m2: 0.0,
          scope: scope.to_s,
          source_count: 0,
          generated_at: Time.now.strftime('%d/%m/%Y %H:%M')
        }
      end

      def tt_layout_jobs
        model = Sketchup.active_model
        selected = model.selection.to_a.select { |entity| container?(entity) && entity.valid? }
        jobs = []

        if !selected.empty?
          if selected.length > 1 && selected.all? { |entity| tt_module_root?(entity, model) }
            selected.each_with_index do |root, index|
              name = tt_scope_name(root, index + 1)
              jobs << { roots: [root], name: name, scope: "MODE ĐANG CHỌN · #{name}" }
            end
          else
            name = selected.length == 1 ? tt_scope_name(selected.first, 1) : 'VÙNG ĐANG CHỌN'
            jobs << { roots: selected, name: name, scope: "ĐỐI TƯỢNG ĐANG CHỌN · #{name}" }
          end
        else
          roots = model.active_entities.to_a.select { |entity| container?(entity) && entity.valid? }
          modules = roots.select { |entity| tt_module_root?(entity, model) }

          if modules.length >= 2
            modules.each_with_index do |root, index|
              name = tt_scope_name(root, index + 1)
              jobs << { roots: [root], name: name, scope: "MODE #{index + 1} · #{name}" }
            end
            leftovers = roots.reject { |entity| modules.include?(entity) }
            unless leftovers.empty?
              jobs << { roots: leftovers, name: 'PHẦN CÒN LẠI', scope: 'CONTEXT · PHẦN CÒN LẠI' }
            end
          else
            jobs << { roots: roots, name: 'TOÀN BỘ CONTEXT', scope: 'TOÀN BỘ CONTEXT HIỆN TẠI' }
          end
        end

        jobs.each_with_index do |job, index|
          job[:roots] = Array(job[:roots]).select { |root| tt_layout_root_valid?(root) }
          job[:index] = index + 1
          job[:key] = job[:roots].map { |root| tt_entity_id(root) }.join('_')
          # Giữ cấu trúc dữ liệu tương thích với bộ dựng preview cũ,
          # nhưng không quét hoặc xuất thống kê ván trong chức năng Layout.
          job[:stats] = tt_empty_layout_stats(job[:scope])
        end

        jobs.reject { |job| job[:roots].empty? }
      end

      # ---------- PREVIEW / GIAO DIỆN: CHỈ HIỆN TRANG KỸ THUẬT ----------

      def dialog_html
        html = tt_v110_original_dialog_html.to_s
        html = html.gsub('XUẤT LAYOUT + THỐNG KÊ VÁN', 'XUẤT LAYOUT KỸ THUẬT')
        html = html.gsub(
          /12 trang riêng:[^<]*/,
          '12 TRANG KỸ THUẬT: Tổng thể / X-Ray / Line / Trước / Trái / Phải / 3 mặt cắt / 3 mặt DIM. Thống kê ván dùng lệnh riêng.'
        )
        html = html.gsub('12 mặt chiếu riêng', '12 mặt chiếu kỹ thuật')
        style = '<style id="tt-layout-only-v110">.cards,.scope,.tablewrap,.statsmini{display:none!important}</style>'
        html.sub('</head>', "#{style}</head>")
      end

      def tt_append_stream_item(item)
        return if item && item[:kind].to_s == 'stats'
        data = item
        if item && item[:kind].to_s == 'composite'
          data = item.dup
          data.delete(:summary)
        end
        tt_v110_original_append_stream_item(data)
      end

      def sync_dialog
        tt_v110_original_sync_dialog
        return unless @dialog && @dialog.visible?
        jobs = @layout_jobs || []
        page_count = jobs.length * FAST_VIEWS.length
        @dialog.execute_script(
          "if(document.getElementById('pages')) document.getElementById('pages').textContent=#{page_count};"
        )
      end

      # Dù đường gọi cũ truyền include_stats=true cho PDF, luôn ép tài liệu
      # chỉ có 12 trang kỹ thuật; bảng thống kê nằm ở lệnh riêng.
      def tt_build_five_view_document(job, skp_path, scenes, _include_stats = false)
        tt_v110_original_build_document(job, skp_path, scenes, false)
      end

      def tt_fast_export(type)
        tt_v110_original_fast_export(type)
      rescue StandardError => error
        message = error.message.to_s.gsub(
          'Không có cụm ván hợp lệ để xuất.',
          'Không có Group/Component hợp lệ để xuất Layout.'
        )
        raise message
      end

      # ---------- DIM: GỘP CÁC KÍCH THƯỚC TRÙNG NHAU ----------

      def tt_dim_add_linear(model, tag, job, role, kind, p1, p2, offset)
        length = p1.distance(p2).to_f
        return nil if length < DIM_MIN_SEGMENT_MM.mm.to_f

        seen = @tt_v110_dim_seen ||= Hash.new { |hash, key| hash[key] = [] }
        bucket = [job[:key].to_s, role.to_s]
        entries = seen[bucket]
        tolerance = DIM_DUPLICATE_TOL_MM.mm.to_f
        priority = kind.to_s.start_with?('overall_') ? 2 : 1
        duplicate = entries.find { |entry| (entry[:length] - length).abs <= tolerance }

        if duplicate
          return nil if priority <= duplicate[:priority]
          old_dim = duplicate[:dim]
          begin
            model.entities.erase_entities([old_dim]) if old_dim && old_dim.valid?
          rescue StandardError
            nil
          end
          entries.delete(duplicate)
        end

        dim = model.entities.add_dimension_linear(p1, p2, offset)
        dim = tt_dim_register(dim, tag, job[:key], role, kind)
        entries << { length: length, priority: priority, dim: dim }
        dim
      rescue StandardError => error
        puts "[TT LayoutStats V110 dim #{role}] #{error.class}: #{error.message}"
        nil
      end

      def tt_ensure_dimensions_for_job(model, job, bounds = nil)
        @tt_v110_dim_seen = Hash.new { |hash, key| hash[key] = [] }
        tt_v110_original_ensure_dimensions(model, job, bounds)
      ensure
        @tt_v110_dim_seen = nil
      end
    end
  end
end
