# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.9.0
# TRANG 06 - DIM KỸ THUẬT
# - Tạo DIM ngoài Group/Component, không sửa hình học MODE.
# - DIM nằm trên tag TT_LAYOUT_DIM_KY_THUAT và mặc định ẩn trong model.
# - Scene DIM riêng: Front (X/Z), Right (Y/Z), Top (X/Y).
# - Quét bounds + các cạnh trục trong toàn bộ Group/Component con để lấy mốc giao chi tiết.
# - DIM tổng ngoài cùng + DIM chuỗi các mốc giao; bỏ trùng theo dung sai.
# - Preview / LayOut / PDF đều thêm trang 06. PDF thống kê bắt đầu từ trang 07.

require 'digest'
require 'base64'
require 'tmpdir'

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.9.0'.freeze

    DIM_TAG_NAME = 'TT_LAYOUT_DIM_KY_THUAT'.freeze unless const_defined?(:DIM_TAG_NAME, false)
    DIM_DICT = 'TT_LAYOUT_DIM'.freeze unless const_defined?(:DIM_DICT, false)
    DIM_CLUSTER_TOL_MM = 1.0 unless const_defined?(:DIM_CLUSTER_TOL_MM, false)
    DIM_EDGE_TOL_MM = 1.0 unless const_defined?(:DIM_EDGE_TOL_MM, false)
    DIM_MIN_EDGE_MM = 8.0 unless const_defined?(:DIM_MIN_EDGE_MM, false)
    DIM_MIN_SEGMENT_MM = 4.0 unless const_defined?(:DIM_MIN_SEGMENT_MM, false)
    DIM_MAX_MARKS = 36 unless const_defined?(:DIM_MAX_MARKS, false)

    class << self
      alias_method :tt_v090_dialog_html_base, :dialog_html unless method_defined?(:tt_v090_dialog_html_base)
      alias_method :tt_v090_render_one_preview_base, :tt_render_one_preview_v060 unless method_defined?(:tt_v090_render_one_preview_base)

      # ---------- DIM DATA / SCAN ----------

      def tt_dim_add_candidate(store, value, weight = 1.0)
        return unless value
        number = value.to_f
        return if number.nan? || number.infinite?
        store << [number, weight.to_f]
      rescue StandardError
        nil
      end

      def tt_dim_add_box_candidates(bb, xs, ys, zs, weight = 4.0)
        return unless bb && bb.valid?
        tt_dim_add_candidate(xs, bb.min.x, weight)
        tt_dim_add_candidate(xs, bb.max.x, weight)
        tt_dim_add_candidate(ys, bb.min.y, weight)
        tt_dim_add_candidate(ys, bb.max.y, weight)
        tt_dim_add_candidate(zs, bb.min.z, weight)
        tt_dim_add_candidate(zs, bb.max.z, weight)
      end

      def tt_dim_transform_bounds(bounds, transform)
        bb = Geom::BoundingBox.new
        8.times { |i| bb.add(bounds.corner(i).transform(transform)) }
        bb
      rescue StandardError
        nil
      end

      def tt_dim_scan_entities(entities, transform, xs, ys, zs, depth = 0)
        return if depth > 24
        edge_tol = DIM_EDGE_TOL_MM.mm.to_f
        min_edge = DIM_MIN_EDGE_MM.mm.to_f

        entities.each do |entity|
          next unless entity && entity.valid?

          if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            begin
              local_bb = if entity.respond_to?(:definition) && entity.definition
                           entity.definition.bounds
                         else
                           nil
                         end
              if local_bb && local_bb.valid?
                world_bb = tt_dim_transform_bounds(local_bb, transform * entity.transformation)
                tt_dim_add_box_candidates(world_bb, xs, ys, zs, 4.0)
              end
            rescue StandardError
              nil
            end

            child = child_entities(entity) rescue nil
            tt_dim_scan_entities(child, transform * entity.transformation, xs, ys, zs, depth + 1) if child
            next
          end

          next unless entity.is_a?(Sketchup::Edge)

          p1 = entity.start.position.transform(transform)
          p2 = entity.end.position.transform(transform)
          dx = (p2.x - p1.x).abs
          dy = (p2.y - p1.y).abs
          dz = (p2.z - p1.z).abs

          # Cạnh gần song song X -> mốc X ở 2 đầu, mốc Y/Z của đường giao.
          if dx >= min_edge && dy <= edge_tol && dz <= edge_tol
            tt_dim_add_candidate(xs, p1.x, 1.0)
            tt_dim_add_candidate(xs, p2.x, 1.0)
            tt_dim_add_candidate(ys, (p1.y + p2.y) * 0.5, 1.5)
            tt_dim_add_candidate(zs, (p1.z + p2.z) * 0.5, 1.5)
          end

          # Cạnh gần song song Y.
          if dy >= min_edge && dx <= edge_tol && dz <= edge_tol
            tt_dim_add_candidate(ys, p1.y, 1.0)
            tt_dim_add_candidate(ys, p2.y, 1.0)
            tt_dim_add_candidate(xs, (p1.x + p2.x) * 0.5, 1.5)
            tt_dim_add_candidate(zs, (p1.z + p2.z) * 0.5, 1.5)
          end

          # Cạnh gần song song Z.
          if dz >= min_edge && dx <= edge_tol && dy <= edge_tol
            tt_dim_add_candidate(zs, p1.z, 1.0)
            tt_dim_add_candidate(zs, p2.z, 1.0)
            tt_dim_add_candidate(xs, (p1.x + p2.x) * 0.5, 1.5)
            tt_dim_add_candidate(ys, (p1.y + p2.y) * 0.5, 1.5)
          end
        rescue StandardError
          nil
        end
      end

      def tt_dim_cluster_candidates(candidates, min_value, max_value)
        tol = DIM_CLUSTER_TOL_MM.mm.to_f
        values = Array(candidates).select do |pair|
          value = pair[0].to_f
          value >= min_value.to_f - tol && value <= max_value.to_f + tol
        end.sort_by { |pair| pair[0].to_f }

        clusters = []
        values.each do |value, weight|
          if clusters.empty? || (value.to_f - clusters.last[:last]).abs > tol
            clusters << { sum: value.to_f * weight.to_f, weight: weight.to_f, last: value.to_f }
          else
            cluster = clusters.last
            cluster[:sum] += value.to_f * weight.to_f
            cluster[:weight] += weight.to_f
            cluster[:last] = value.to_f
          end
        end

        marks = clusters.map do |cluster|
          [cluster[:sum] / [cluster[:weight], 0.001].max, cluster[:weight]]
        end

        # Giữ mốc biên tuyệt đối.
        marks << [min_value.to_f, 999.0]
        marks << [max_value.to_f, 999.0]
        marks.sort_by! { |pair| pair[0] }

        # Gộp lần cuối sau khi ép biên.
        compact = []
        marks.each do |value, weight|
          if compact.empty? || (value - compact.last[0]).abs > tol
            compact << [value, weight]
          elsif weight > compact.last[1]
            compact[-1] = [value, weight]
          end
        end

        # Nếu quá nhiều giao tuyến, ưu tiên các vị trí xuất hiện nhiều lần.
        if compact.length > DIM_MAX_MARKS
          first = compact.first
          last = compact.last
          middle = compact[1...-1].sort_by { |pair| [-pair[1], pair[0]] }.first(DIM_MAX_MARKS - 2)
          compact = ([first] + middle + [last]).sort_by { |pair| pair[0] }
        end

        compact.map { |pair| pair[0] }
      rescue StandardError
        [min_value.to_f, max_value.to_f]
      end

      def tt_dim_scan_job(model, job, bounds)
        xs = []
        ys = []
        zs = []
        base_tr = model.edit_transform || Geom::Transformation.new

        tt_dim_add_box_candidates(bounds, xs, ys, zs, 12.0)
        Array(job[:roots]).each do |root|
          next unless root && root.valid?
          begin
            root_bb = tt_dim_transform_bounds(root.bounds, base_tr)
            tt_dim_add_box_candidates(root_bb, xs, ys, zs, 8.0)
          rescue StandardError
            nil
          end

          child = child_entities(root) rescue nil
          tt_dim_scan_entities(child, base_tr * root.transformation, xs, ys, zs, 0) if child
        end

        {
          x: tt_dim_cluster_candidates(xs, bounds.min.x, bounds.max.x),
          y: tt_dim_cluster_candidates(ys, bounds.min.y, bounds.max.y),
          z: tt_dim_cluster_candidates(zs, bounds.min.z, bounds.max.z)
        }
      end

      # ---------- DIM ENTITIES ----------

      def tt_dim_tag(model)
        model.layers[DIM_TAG_NAME] || model.layers.add(DIM_TAG_NAME)
      end

      def tt_dim_job_entities(model, job_key, role = nil)
        model.entities.grep(Sketchup::DimensionLinear).select do |dim|
          next false unless dim.valid?
          next false unless dim.get_attribute(DIM_DICT, 'job_key').to_s == job_key.to_s
          role.nil? || dim.get_attribute(DIM_DICT, 'role').to_s == role.to_s
        end
      rescue StandardError
        []
      end

      def tt_dim_remove_job_entities(model, job_key)
        old = tt_dim_job_entities(model, job_key)
        model.entities.erase_entities(old) unless old.empty?
      rescue StandardError
        nil
      end

      def tt_dim_register(dim, tag, job_key, role, kind)
        dim.layer = tag if dim.respond_to?(:layer=)
        dim.set_attribute(DIM_DICT, 'job_key', job_key.to_s)
        dim.set_attribute(DIM_DICT, 'role', role.to_s)
        dim.set_attribute(DIM_DICT, 'kind', kind.to_s)
        dim.hidden = true if dim.respond_to?(:hidden=)
        begin
          dim.arrow_type = Sketchup::Dimension::ARROW_CLOSED if dim.respond_to?(:arrow_type=)
        rescue StandardError
          nil
        end
        dim
      end

      def tt_dim_add_linear(model, tag, job, role, kind, p1, p2, offset)
        return nil if p1.distance(p2) < DIM_MIN_SEGMENT_MM.mm.to_f
        dim = model.entities.add_dimension_linear(p1, p2, offset)
        tt_dim_register(dim, tag, job[:key], role, kind)
      rescue StandardError => error
        puts "[TT LayoutStats V090 dim #{role}] #{error.class}: #{error.message}"
        nil
      end

      def tt_dim_offsets(bounds)
        span = [bounds.width.to_f.abs, bounds.height.to_f.abs, bounds.depth.to_f.abs].max
        chain = [[span * 0.055, 80.mm.to_f].max, 180.mm.to_f].min
        total = chain + [[span * 0.035, 55.mm.to_f].max, 120.mm.to_f].min
        { chain: chain, total: total, face: 3.mm.to_f }
      end

      def tt_dim_add_chain(model, tag, job, role, kind, values, point_builder, offset_vector)
        vals = Array(values).sort
        return if vals.length < 3
        vals.each_cons(2) do |a, b|
          next if (b - a).abs < DIM_MIN_SEGMENT_MM.mm.to_f
          p1 = point_builder.call(a)
          p2 = point_builder.call(b)
          tt_dim_add_linear(model, tag, job, role, kind, p1, p2, offset_vector)
        end
      end

      def tt_dim_build_front(model, tag, job, bb, marks, offsets)
        role = :front
        y = bb.min.y - offsets[:face]
        z0 = bb.min.z
        x0 = bb.min.x
        chain = offsets[:chain]
        total = offsets[:total]

        # Ngang X: DIM chuỗi + phủ bì.
        builder_x = proc { |x| Geom::Point3d.new(x, y, z0) }
        tt_dim_add_chain(model, tag, job, role, :chain_x, marks[:x], builder_x,
                         Geom::Vector3d.new(0, 0, -chain))
        tt_dim_add_linear(model, tag, job, role, :overall_x,
                          Geom::Point3d.new(bb.min.x, y, z0),
                          Geom::Point3d.new(bb.max.x, y, z0),
                          Geom::Vector3d.new(0, 0, -total))

        # Đứng Z: DIM chuỗi + phủ bì.
        builder_z = proc { |z| Geom::Point3d.new(x0, y, z) }
        tt_dim_add_chain(model, tag, job, role, :chain_z, marks[:z], builder_z,
                         Geom::Vector3d.new(-chain, 0, 0))
        tt_dim_add_linear(model, tag, job, role, :overall_z,
                          Geom::Point3d.new(x0, y, bb.min.z),
                          Geom::Point3d.new(x0, y, bb.max.z),
                          Geom::Vector3d.new(-total, 0, 0))
      end

      def tt_dim_build_side(model, tag, job, bb, marks, offsets)
        role = :side
        x = bb.max.x + offsets[:face]
        z0 = bb.min.z
        y0 = bb.min.y
        chain = offsets[:chain]
        total = offsets[:total]

        builder_y = proc { |y| Geom::Point3d.new(x, y, z0) }
        tt_dim_add_chain(model, tag, job, role, :chain_y, marks[:y], builder_y,
                         Geom::Vector3d.new(0, 0, -chain))
        tt_dim_add_linear(model, tag, job, role, :overall_y,
                          Geom::Point3d.new(x, bb.min.y, z0),
                          Geom::Point3d.new(x, bb.max.y, z0),
                          Geom::Vector3d.new(0, 0, -total))

        builder_z = proc { |z| Geom::Point3d.new(x, y0, z) }
        tt_dim_add_chain(model, tag, job, role, :chain_z, marks[:z], builder_z,
                         Geom::Vector3d.new(0, -chain, 0))
        tt_dim_add_linear(model, tag, job, role, :overall_z,
                          Geom::Point3d.new(x, y0, bb.min.z),
                          Geom::Point3d.new(x, y0, bb.max.z),
                          Geom::Vector3d.new(0, -total, 0))
      end

      def tt_dim_build_top(model, tag, job, bb, marks, offsets)
        role = :top
        z = bb.max.z + offsets[:face]
        y0 = bb.min.y
        x0 = bb.min.x
        chain = offsets[:chain]
        total = offsets[:total]

        builder_x = proc { |x| Geom::Point3d.new(x, y0, z) }
        tt_dim_add_chain(model, tag, job, role, :chain_x, marks[:x], builder_x,
                         Geom::Vector3d.new(0, -chain, 0))
        tt_dim_add_linear(model, tag, job, role, :overall_x,
                          Geom::Point3d.new(bb.min.x, y0, z),
                          Geom::Point3d.new(bb.max.x, y0, z),
                          Geom::Vector3d.new(0, -total, 0))

        builder_y = proc { |y| Geom::Point3d.new(x0, y, z) }
        tt_dim_add_chain(model, tag, job, role, :chain_y, marks[:y], builder_y,
                         Geom::Vector3d.new(-chain, 0, 0))
        tt_dim_add_linear(model, tag, job, role, :overall_y,
                          Geom::Point3d.new(x0, bb.min.y, z),
                          Geom::Point3d.new(x0, bb.max.y, z),
                          Geom::Vector3d.new(-total, 0, 0))
      end

      def tt_ensure_dimensions_for_job(model, job, bounds = nil)
        bounds ||= tt_scope_bounds_for_roots(model, job[:roots])
        marks = tt_dim_scan_job(model, job, bounds)
        tag = tt_dim_tag(model)
        offsets = tt_dim_offsets(bounds)

        model.start_operation("TRẦN TUẤN - DIM Kỹ Thuật #{job[:index]}", true)
        begin
          tt_dim_remove_job_entities(model, job[:key])
          tt_dim_build_front(model, tag, job, bounds, marks, offsets)
          tt_dim_build_side(model, tag, job, bounds, marks, offsets)
          tt_dim_build_top(model, tag, job, bounds, marks, offsets)
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end

        {
          front: tt_dim_job_entities(model, job[:key], :front),
          side: tt_dim_job_entities(model, job[:key], :side),
          top: tt_dim_job_entities(model, job[:key], :top),
          marks: marks,
          offsets: offsets
        }
      end

      def tt_dim_hide_all(model)
        model.entities.grep(Sketchup::DimensionLinear).each do |dim|
          next unless dim.get_attribute(DIM_DICT, 'job_key')
          dim.hidden = true if dim.respond_to?(:hidden=)
        rescue StandardError
          nil
        end
      end

      def tt_dim_show_role(model, job_key, role)
        tt_dim_hide_all(model)
        tt_dim_job_entities(model, job_key, role).each do |dim|
          dim.hidden = false if dim.respond_to?(:hidden=)
        rescue StandardError
          nil
        end
        tag = model.layers[DIM_TAG_NAME]
        tag.visible = true if tag && tag.respond_to?(:visible=)
      rescue StandardError
        nil
      end

      # ---------- DIM CAMERAS ----------

      def tt_dim_expanded_bounds(bb, role, offsets)
        out = Geom::BoundingBox.new
        8.times { |i| out.add(bb.corner(i)) }
        pad = offsets[:total] * 1.18
        case role
        when :front
          out.add(Geom::Point3d.new(bb.min.x - pad, bb.min.y, bb.min.z - pad))
          out.add(Geom::Point3d.new(bb.max.x, bb.max.y, bb.max.z))
        when :side
          out.add(Geom::Point3d.new(bb.min.x, bb.min.y - pad, bb.min.z - pad))
          out.add(Geom::Point3d.new(bb.max.x, bb.max.y, bb.max.z))
        when :top
          out.add(Geom::Point3d.new(bb.min.x - pad, bb.min.y - pad, bb.min.z))
          out.add(Geom::Point3d.new(bb.max.x, bb.max.y, bb.max.z))
        end
        out
      end

      def tt_dim_top_camera(bb)
        center = bb.center
        distance = [bb.diagonal.to_f * 2.5, 1000.mm.to_f].max
        eye = center.offset(Geom::Vector3d.new(0, 0, 1), distance)
        camera = Sketchup::Camera.new(eye, center, Y_AXIS, false)
        horizontal = bb.width.to_f
        vertical = bb.height.to_f
        fit_height = [vertical, horizontal / (420.0 / 297.0)].max * 1.22
        camera.height = [fit_height, 100.mm.to_f].max
        camera
      end

      def tt_dim_camera(role, bb, offsets)
        expanded = tt_dim_expanded_bounds(bb, role, offsets)
        case role
        when :front then tt_ortho_camera(:front, expanded)
        when :side then tt_ortho_camera(:right, expanded)
        else tt_dim_top_camera(expanded)
        end
      end

      # ---------- PREVIEW ----------

      def tt_preview_tasks(model, job)
        bounds = tt_scope_bounds_for_roots(model, job[:roots])
        planes = tt_ensure_section_planes_for_job(model, bounds, @cut_offset_mm, job)
        dim_data = tt_ensure_dimensions_for_job(model, job, bounds)
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
          { page: :sections, slot: :bottom, title: 'MẶT CẮT PHẢI', spec: ['CẮT PHẢI', right, :section, planes[:cut_right]] },
          { page: :dimensions, slot: :main, title: 'DIM MẶT TRƯỚC · NGANG + CAO',
            spec: ['DIM FRONT', tt_dim_camera(:front, bounds, dim_data[:offsets]), :line, nil], dim_role: :front, job_key: job[:key] },
          { page: :dimensions, slot: :top, title: 'DIM MẶT BÊN · SÂU + CAO',
            spec: ['DIM SIDE', tt_dim_camera(:side, bounds, dim_data[:offsets]), :line, nil], dim_role: :side, job_key: job[:key] },
          { page: :dimensions, slot: :bottom, title: 'DIM MẶT TRÊN · NGANG + SÂU',
            spec: ['DIM TOP', tt_dim_camera(:top, bounds, dim_data[:offsets]), :line, nil], dim_role: :top, job_key: job[:key] }
        ]
      end

      def tt_page_required(page)
        [:elevations, :sections, :dimensions].include?(page) ? 3 : 1
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
        when :sections
          "#{base} · 05 MẶT CẮT · CẮT #{@cut_offset_mm.to_f.round(1)} mm TỪ MẶT NGOÀI"
        else
          "#{base} · 06 DIM KỸ THUẬT"
        end
      end

      def tt_render_one_preview_v060(model, task, index, roots)
        return tt_v090_render_one_preview_base(model, task, index, roots) unless task[:dim_role]

        spec = task[:spec]
        _title, camera, profile, section = spec
        step_state = tt_capture_model_state(model)
        visibility = tt_scope_visibility_state(model)
        path = File.join(Dir.tmpdir, format('tt_layout_dim_v090_%d_%02d.jpg', Process.pid, index + 1))

        begin
          tt_apply_scope_visibility(model, roots)
          tt_dim_show_role(model, task[:job_key], task[:dim_role])
          tt_apply_view_state(model, camera, profile, section)
          tt_apply_sharp_edges(model)
          options = {
            filename: path,
            width: V060_PREVIEW_W,
            height: V060_PREVIEW_H,
            antialias: true,
            transparent: false,
            compression: 0.88
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
          tt_dim_hide_all(model)
          tt_restore_scope_visibility(visibility)
          tt_restore_model_state(model, step_state) rescue nil
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

          done_views = job_state[:job_index] * 12 + job_state[:task_index]
          total_views = jobs.length * 12
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
            page_no: 7 + index,
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
          sum + 6 + stats_pages
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

      # ---------- EXPORT SCENES ----------

      def tt_prepare_export_scenes_for_job(model, job)
        snapshot = tt_capture_model_state(model)
        visibility = tt_scope_visibility_state(model)
        bounds = tt_scope_bounds_for_roots(model, job[:roots])
        planes = tt_ensure_section_planes_for_job(model, bounds, @cut_offset_mm, job)
        dim_data = tt_ensure_dimensions_for_job(model, job, bounds)
        suffix = Digest::SHA1.hexdigest(job[:key].to_s)[0, 8]
        defs = {
          overview: [tt_iso_camera(bounds), :normal, nil, nil],
          xray: [tt_iso_camera(bounds), :xray, nil, nil],
          line: [tt_iso_camera(bounds), :line, nil, nil],
          front: [tt_ortho_camera(:front, bounds), :normal, nil, nil],
          left: [tt_ortho_camera(:left, bounds), :normal, nil, nil],
          right: [tt_ortho_camera(:right, bounds), :normal, nil, nil],
          cut_front: [tt_ortho_camera(:front, bounds), :section, planes[:cut_front], nil],
          cut_left: [tt_ortho_camera(:left, bounds), :section, planes[:cut_left], nil],
          cut_right: [tt_ortho_camera(:right, bounds), :section, planes[:cut_right], nil],
          dim_front: [tt_dim_camera(:front, bounds, dim_data[:offsets]), :line, nil, :front],
          dim_side: [tt_dim_camera(:side, bounds, dim_data[:offsets]), :line, nil, :side],
          dim_top: [tt_dim_camera(:top, bounds, dim_data[:offsets]), :line, nil, :top]
        }
        scenes = {}

        model.start_operation("TRẦN TUẤN - Scene Layout + DIM #{job[:index]}", true)
        begin
          tt_apply_scope_visibility(model, job[:roots])
          defs.each do |key, spec|
            camera, profile, section, dim_role = spec
            tt_dim_hide_all(model)
            tt_dim_show_role(model, job[:key], dim_role) if dim_role
            tt_apply_view_state(model, camera, profile, section)
            tt_apply_sharp_edges(model)
            page = tt_upsert_scope_scene(model, "TT_LY_#{suffix}_#{key.to_s.upcase}", profile)
            scenes[key] = tt_scene_layout_index(model, page)
          end
          tt_dim_hide_all(model)
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        ensure
          tt_dim_hide_all(model)
          tt_restore_scope_visibility(visibility)
          tt_restore_model_state(model, snapshot) rescue nil
        end
        scenes
      end

      # ---------- LAYOUT DOCUMENT ----------

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

        p6 = doc.pages.add('06 - DIM KỸ THUẬT')
        tt_add_compact_header(doc, layer, p6, 'DIM KỸ THUẬT · NGANG / CAO / SÂU / GIAO ĐIỂM', job, skp_path)
        tt_add_scene_viewport(doc, layer, p6, skp_path, scenes[:dim_front], 0.45, 1.18, 10.25, 9.55, 'MẶT TRƯỚC · DIM NGANG + CAO')
        tt_add_scene_viewport(doc, layer, p6, skp_path, scenes[:dim_side], 10.95, 1.18, 5.05, 4.45, 'MẶT BÊN · DIM SÂU + CAO')
        tt_add_scene_viewport(doc, layer, p6, skp_path, scenes[:dim_top], 10.95, 6.28, 5.05, 4.45, 'MẶT TRÊN · DIM NGANG + SÂU')

        tt_add_statistics_pages(doc, layer, stats, 7) if include_stats
        doc
      end

      # ---------- DIALOG TEXT ----------

      def dialog_html
        html = tt_v090_dialog_html_base.to_s
        html = html.gsub(
          'Khoảng cắt được đo THẬT từ mặt ngoài của MODE: trước từ mặt trước, trái từ mép trái, phải từ mép phải. Đổi số mm phải XEM TRƯỚC lại.',
          'Khoảng cắt đo THẬT từ mặt ngoài. Trang 06 tự tạo DIM kỹ thuật: ngang/cao/sâu + chuỗi kích thước theo các mép và giao tuyến chi tiết trong Group/Component.'
        )
        html = html.gsub(
          'Thứ tự: Tổng thể → Trước → Trái → Phải → Cắt trước → Cắt trái → Cắt phải → Line + X-Ray → Thống kê ván.',
          'Thứ tự: Tổng thể → Line + X-Ray → Khung Line → Mặt đứng → Mặt cắt → DIM kỹ thuật → Thống kê ván.'
        )
        html
      end
    end
  end
end
