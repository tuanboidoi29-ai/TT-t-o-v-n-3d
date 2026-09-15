        if @scan.empty?
          @scan = nil
          UI.beep
          Sketchup.set_status_text('Không tìm thấy tấm có texture để quét.', SB_PROMPT)
        else
          Sketchup.set_status_text("PREVIEW #{@scan.length} tấm · ENTER áp dụng · ESC hủy", SB_PROMPT)
        end
        view.invalidate
        true
      end

      def getMenu(_menu); nil; end

      def draw(view)
        if @scan
          draw_scan(view)
          return
        end
        return unless @target && @analysis
        draw_target_box(view)
        draw_grain_arrow(view, @analysis)
        draw_free_arrows(view) if @free
        draw_label(view)
      rescue StandardError => e
        puts "[TT Grain draw] #{e.class}: #{e.message}"
      end

      private

      def container?(e); e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance); end
      def definition(e); e.respond_to?(:definition) ? e.definition : nil; end
      def entities(e); d = definition(e); d ? d.entities : nil; end
      def bounds(e); d = definition(e); d ? d.bounds : nil; end
      def valid_target?(e); e && e.valid? && container?(e); rescue false; end

      def pick(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        found = nil
        ph.count.times do |i|
          path = ph.path_at(i)
          next unless path
          face = path.reverse.find { |e| e.is_a?(Sketchup::Face) }
          next unless face
          found = [path, face]
          break
        end
        return clear_pick unless found
        @path, @face = found
        @target, @target_tr = board_from_path(@path)
        return clear_pick unless @target
        sync_inherited_material(@target)
        @material = effective_material(@face, @path)
      end

      def board_from_path(path)
        list = []
        tr = Geom::Transformation.new
        path.each do |e|
          next unless container?(e)
          tr = tr * e.transformation
          list << [e, tr.clone]
        end
        list.reverse_each do |e, etr|
          a = analyze(e, etr)
          next unless a
          sizes = a[:sizes_mm].sort
          return [e, etr] if sizes[0] >= 0.1 && sizes[0] <= @max_t && sizes[1] >= 1.0 && sizes[2] >= 1.0
        end
        list.last || [nil, Geom::Transformation.new]
      end

      def effective_material(face, path)
        return face.material if face && face.material
        return face.back_material if face && face.back_material
        path.select { |e| container?(e) }.reverse_each { |e| return e.material if e.material }
        nil
      end

      def textured?(m); m && m.texture; rescue false; end

      def analyze_current
        @analysis = analyze(@target, @target_tr)
        return unless @analysis
        if @free && @free_axis
          @analysis = force_axis(@analysis, @free_axis, @free_sign)
        elsif @lock_mode == 'auto'
          @analysis = part_name_rule(@target, @analysis, @target_tr)
        end
      end

      def analyze(target, tr)
        return nil unless valid_target?(target)
        b = bounds(target)
        return nil unless b && b.valid?
        scales = [tr.xaxis.length, tr.yaxis.length, tr.zaxis.length]
        local = [b.width.to_f, b.height.to_f, b.depth.to_f]
        sizes = local.each_with_index.map { |v, i| v * scales[i] * 25.4 }
        indexed = sizes.each_with_index.sort_by(&:first)
        thickness_axis = indexed[0][1]
        plane = [0, 1, 2] - [thickness_axis]
        a, c = plane
        choice = choose(a, sizes[a], c, sizes[c])
        {bounds:b, local_sizes:local, sizes_mm:sizes, thickness_axis:thickness_axis, plane_axes:plane,
         grain_axis:choice[0], cross_axis:choice[1], grain_size_mm:choice[2], cross_size_mm:choice[3], fits_sheet:choice[4], grain_sign:1}
      rescue StandardError
        nil
      end

      def choose(a, sa, b, sb)
        if @lock_mode == 'length'
          return sa >= sb ? [a,b,sa,sb,sa<=@sheet_l+0.5 && sb<=@sheet_w+0.5] : [b,a,sb,sa,sb<=@sheet_l+0.5 && sa<=@sheet_w+0.5]
        elsif @lock_mode == 'width'
          return sa <= sb ? [a,b,sa,sb,sa<=@sheet_l+0.5 && sb<=@sheet_w+0.5] : [b,a,sb,sa,sb<=@sheet_l+0.5 && sa<=@sheet_w+0.5]
        end
        fit_a = sa <= @sheet_l+0.5 && sb <= @sheet_w+0.5
        fit_b = sb <= @sheet_l+0.5 && sa <= @sheet_w+0.5
        return [a,b,sa,sb,true] if fit_a && !fit_b
        return [b,a,sb,sa,true] if fit_b && !fit_a
        return sa >= sb ? [a,b,sa,sb,fit_a] : [b,a,sb,sa,fit_b] if fit_a || fit_b
        oa = [sa-@sheet_l,0].max + [sb-@sheet_w,0].max
        ob = [sb-@sheet_l,0].max + [sa-@sheet_w,0].max
        oa <= ob ? [a,b,sa,sb,false] : [b,a,sb,sa,false]
      end

      def part_name_rule(target, a, tr)
        name = ((target.name.to_s rescue '') + ' ' + (definition(target).name.to_s rescue '')).downcase
        name = name.unicode_normalize(:nfkd).gsub(/\p{Mn}/,'') rescue name
        name = name.tr('đ','d')
        if name =~ /(canh|door|hoi|side|vach|panel dung|mat canh)/
          axis = a[:plane_axes].max_by do |i|
            v = AXES[i].clone.transform(tr); v.normalize! if v.length > 0.001; v.dot(Z_AXIS).abs
          end
          return force_axis(a, axis, 1) if axis
        end
        if name =~ /(dot|ke|shelf|noc|day|top|bottom|tang)/
          axis = a[:plane_axes].max_by { |i| a[:sizes_mm][i] }
          return force_axis(a, axis, 1)
        end
        a
      end

      def force_axis(a, axis, sign)
        r = a.dup
        cross = (a[:plane_axes] - [axis]).first
        return r unless cross
        r[:grain_axis], r[:cross_axis], r[:grain_sign] = axis, cross, sign.to_i < 0 ? -1 : 1
        r[:grain_size_mm], r[:cross_size_mm] = r[:sizes_mm][axis], r[:sizes_mm][cross]
        r[:fits_sheet] = r[:grain_size_mm] <= @sheet_l+0.5 && r[:cross_size_mm] <= @sheet_w+0.5
        r
      end

      def swapped(a); force_axis(a, a[:cross_axis], 1); end

      def choose_free(mx, my, view)
        return unless @analysis && @target
        b = bounds(@target); c = b.center
        cw = c.transform(@target_tr)
        best = nil
        @analysis[:plane_axes].each do |axis|
          extent = @analysis[:local_sizes][axis] * 0.38
          [1,-1].each do |sign|
            p = c.offset(AXES[axis], extent * sign).transform(@target_tr)
            s = view.screen_coords(p)
            d = Math.hypot(s.x-mx, s.y-my)
            item = [d,axis,sign]
            best = item if best.nil? || d < best[0]
          end
        end
        if best && best[0] < 90
          @free_axis, @free_sign = best[1], best[2]
          @analysis = force_axis(@analysis, @free_axis, @free_sign)
        end
      end

      def locked?; @target.get_attribute(DICT,'locked',false) == true; rescue false; end
      def toggle_lock
        v = !locked?
        @model.start_operation(v ? 'TT - Khóa vân' : 'TT - Mở khóa vân', true)
        @target.set_attribute(DICT,'locked',v)
        @target.set_attribute(ABF,'grain_locked',v)
        @target.set_attribute(ABF,'allow_rotate_90',!v)
        @model.commit_operation
        update_status
      rescue StandardError
        @model.abort_operation
        raise
      end

      def apply_target(target, tr, material, a, mode)
        @model.start_operation('TRẦN TUẤN - Xoay Vân Ván', true)
        target.make_unique if target.is_a?(Sketchup::ComponentInstance)
        before = signature(target)
        count = map_faces(target, material, a)
        raise 'Không tìm thấy mặt chính dùng vật liệu có texture.' if count <= 0
        raise 'Cấu trúc Group/Component thay đổi bất thường.' unless before == signature(target)
        save_metadata(target, material, a, mode)
        @model.commit_operation
        Sketchup.set_status_text("Đã xoay/căn vân #{count} mặt · #{a[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'}", SB_PROMPT)
      rescue StandardError
        @model.abort_operation
