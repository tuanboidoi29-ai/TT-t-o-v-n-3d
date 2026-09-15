        raise
      end

      def signature(target)
        es = entities(target)
        [es.grep(Sketchup::Face).length, es.grep(Sketchup::Edge).length,
         es.grep(Sketchup::Group).length, es.grep(Sketchup::ComponentInstance).length,
         target.transformation.to_a.map { |x| x.to_f.round(10) }]
      end

      def main_faces(target, a)
        es = entities(target); axis = AXES[a[:thickness_axis]]
        es.grep(Sketchup::Face).select do |f|
          n=f.normal.clone; next false if n.length < 0.001; n.normalize!; n.dot(axis).abs >= 0.98
        end.sort_by { |f| -f.area.to_f }
      end

      def map_faces(target, material, a)
        faces = main_faces(target,a)
        count = 0
        faces.each do |face|
          front = same_material?(face.material || target.material, material)
          back  = same_material?(face.back_material || target.material, material)
          next unless front || back
          use_front = front
          if use_front && face.material.nil?
            face.material = material
            mark_inherited(face, material)
          elsif !use_front && face.back_material.nil?
            face.back_material = material
            mark_inherited(face, material)
          end
          position_face(face, material, use_front, a)
          count += 1
        end
        count
      end

      def position_face(face, material, front, a)
        g = AXES[a[:grain_axis]].clone
        g.reverse! if a[:grain_sign].to_i < 0
        c = AXES[a[:cross_axis]].clone
        b = face.bounds
        center = b.center
        plane = face.plane
        origin = center.project_to_plane(plane)
        u_len = [material.texture.width.to_f, 1.0].max
        v_len = [material.texture.height.to_f, 1.0].max
        p1 = origin
        p2 = p1.offset(g, u_len)
        p3 = p1.offset(c, v_len)
        q1 = Geom::Point3d.new(0,0,0)
        q2 = Geom::Point3d.new(u_len,0,0)
        q3 = Geom::Point3d.new(0,v_len,0)
        face.position_material(material, [p1,q1,p2,q2,p3,q3], front)
      end

      def same_material?(a,b)
        return false unless a && b
        return true if a.equal?(b)
        (a.persistent_id rescue nil) == (b.persistent_id rescue :x) || a.name.to_s == b.name.to_s
      end

      def material_key(m); "#{m.name}:#{m.persistent_id rescue 0}"; end
      def mark_inherited(face, material)
        face.set_attribute(FACE_DICT,'inherited_source',true)
        face.set_attribute(FACE_DICT,'last_material_key',material_key(material))
      end

      def sync_inherited_material(target)
        tm = target.material
        return unless tm
        entities(target).grep(Sketchup::Face).each do |f|
          next unless f.get_attribute(FACE_DICT,'inherited_source',false)
          old = f.get_attribute(FACE_DICT,'last_material_key','').to_s
          if f.material && material_key(f.material) != old
            f.set_attribute(FACE_DICT,'inherited_source',false)
            next
          end
          f.material = tm
          f.set_attribute(FACE_DICT,'last_material_key',material_key(tm))
        end
      rescue StandardError
        nil
      end

      def save_metadata(target, material, a, mode)
        target.set_attribute(DICT,'grain_axis',AXIS_NAMES[a[:grain_axis]])
        target.set_attribute(DICT,'cross_axis',AXIS_NAMES[a[:cross_axis]])
        target.set_attribute(DICT,'grain_sign',a[:grain_sign])
        target.set_attribute(DICT,'board_length_mm',@sheet_l)
        target.set_attribute(DICT,'board_width_mm',@sheet_w)
        target.set_attribute(DICT,'part_grain_mm',a[:grain_size_mm])
        target.set_attribute(DICT,'part_cross_mm',a[:cross_size_mm])
        target.set_attribute(DICT,'fits_sheet',a[:fits_sheet])
        target.set_attribute(DICT,'material_name',material.name.to_s)
        target.set_attribute(DICT,'mode',mode)
        target.set_attribute(DICT,'version',VERSION)
        target.set_attribute(ABF,'grain_sensitive',true)
        target.set_attribute(ABF,'grain_axis',AXIS_NAMES[a[:grain_axis]])
        target.set_attribute(ABF,'grain_locked',locked?)
        target.set_attribute(ABF,'allow_rotate_90',!locked?)
      end

      def build_scan
        roots = @model.selection.to_a.select { |e| container?(e) }
        roots = @model.active_entities.to_a.select { |e| container?(e) } if roots.empty?
        out=[]
        roots.each { |e| scan_entity(e, Geom::Transformation.new, out) }
        out.uniq { |i| i[:target].persistent_id rescue i[:target].entityID }
      end

      def scan_entity(e, parent_tr, out)
        return unless valid_target?(e)
        tr = parent_tr * e.transformation
        a = analyze(e,tr)
        if a && a[:sizes_mm].min <= @max_t && a[:sizes_mm].sort[1] >= 1.0
          m = e.material || entities(e).grep(Sketchup::Face).map { |f| f.material || f.back_material }.compact.find { |x| textured?(x) }
          out << {target:e,tr:tr,analysis:a,material:m,ok:!!(m && textured?(m))}
        end
        entities(e).each { |c| scan_entity(c,tr,out) if container?(c) }
      end

      def apply_scan(include_warning)
        list=@scan || []; @scan=nil
        ok=list.select { |i| i[:ok] && (i[:analysis][:fits_sheet] || include_warning) }
        return UI.beep if ok.empty?
        ok.each do |i|
          begin
            @target=i[:target]; @target_tr=i[:tr]; @material=i[:material]; @analysis=i[:analysis]
            apply_target(@target,@target_tr,@material,@analysis,'batch') unless locked?
          rescue StandardError => e
            puts "[TT Grain batch] #{e.class}: #{e.message}"
          end
        end
        Sketchup.set_status_text("Đã áp dụng vân cho #{ok.length} tấm.",SB_PROMPT)
        @view.invalidate
      end

      def draw_scan(view)
        (@scan || []).each do |i|
          b=bounds(i[:target]); next unless b
          pts=(0..7).map { |n| b.corner(n).transform(i[:tr]) }
          view.drawing_color = i[:ok] ? Sketchup::Color.new(40,200,90) : Sketchup::Color.new(230,170,40)
          view.line_width=2
          pairs=[[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
          view.draw(GL_LINES,pairs.flat_map{|x,y|[pts[x],pts[y]]})
        end
      end

      def draw_target_box(view)
        b=bounds(@target); pts=(0..7).map{|n|b.corner(n).transform(@target_tr)}
        view.drawing_color=Sketchup::Color.new(255,135,35); view.line_width=3
        pairs=[[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
        view.draw(GL_LINES,pairs.flat_map{|x,y|[pts[x],pts[y]]})
      end

      def draw_grain_arrow(view,a)
        b=bounds(@target); c=b.center; axis=AXES[a[:grain_axis]]; len=a[:local_sizes][a[:grain_axis]]*0.36
        s=a[:grain_sign].to_i<0 ? -1 : 1
        p1=c.offset(axis,-len*s).transform(@target_tr); p2=c.offset(axis,len*s).transform(@target_tr)
        view.drawing_color=Sketchup::Color.new(255,95,20); view.line_width=6; view.draw(GL_LINES,[p1,p2]); view.draw_points([p2],12,1,Sketchup::Color.new(255,95,20))
      end

      def draw_free_arrows(view)
        b=bounds(@target); c=b.center; cw=c.transform(@target_tr)
        @analysis[:plane_axes].each do |axis|
          half=@analysis[:local_sizes][axis]*0.38
          [1,-1].each do |sign|
            p=c.offset(AXES[axis],half*sign).transform(@target_tr)
            sel=(axis==@free_axis && sign==@free_sign)
            col=sel ? Sketchup::Color.new(50,220,100) : Sketchup::Color.new(145,145,145)
            view.drawing_color=col; view.line_width=sel ? 7 : 3; view.draw(GL_LINES,[cw,p]); view.draw_points([p],sel ? 13 : 8,1,col)
          end
        end
      end

      def draw_label(view)
        p=bounds(@target).center.transform(@target_tr); s=view.screen_coords(p)
        mode=@free ? "TỰ DO #{(@free_sign<0 ? '-' : '+')}#{AXIS_NAMES[@analysis[:grain_axis]]}" : 'AUTO'
        text="#{mode} · VÂN #{@analysis[:grain_size_mm].round(1)}mm · NGANG #{@analysis[:cross_size_mm].round(1)}mm · #{@analysis[:fits_sheet] ? 'VỪA KHỔ' : 'VƯỢT KHỔ'}#{locked? ? ' · KHÓA' : ''}"
        view.draw_text(s,text,size:14,bold:true,color:Sketchup::Color.new(255,120,40))
      rescue StandardError
        nil
      end

      def update_status
        if @target && @analysis
          Sketchup.set_status_text("XOAY VÂN | #{@free ? 'TỰ DO 4 HƯỚNG' : 'AUTO'} | Click áp dụng · Alt+Click đảo 90° · Ctrl+Click khóa · TAB khổ · TAB TAB đổi mode · Chuột phải quét",SB_PROMPT)
        else
          Sketchup.set_status_text('XOAY VÂN VÁN | Rê vào tấm · TAB khai báo khổ · TAB TAB AUTO/TỰ DO · Chuột phải quét',SB_PROMPT)
        end
      end

      def clear_pick
        @target=nil; @face=nil; @path=nil; @material=nil; @analysis=nil; @free_axis=nil; @free_sign=1
      end
    end
  end
end
