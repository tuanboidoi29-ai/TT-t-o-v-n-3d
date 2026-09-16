# encoding: UTF-8
# TRẦN TUẤN - KHOANH VÙNG CO KÉO MỘT PHẦN
require 'sketchup.rb'
module TranTuanNoiThat
  module StretchMode
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.0.1'.freeze

    class WindowTool < Tool
      def initialize
        super
        @state = :window
        @nodes = []
        @selected_points = []
        @preview_edges = []
        @window_start = nil
        @window_end = nil
        @axis = nil
        @delta = 0.0
        @direction_sign = 1
        @scan_count = 0
      end

      def activate
        window_status
        @model.active_view.invalidate
      end

      def enableVCB?
        @state == :move
      end

      def onMouseMove(flags, x, y, view)
        if @state == :window && @window_start
          @window_end = Geom::Point3d.new(x, y, 0)
        elsif @state == :anchor
          @ip.pick(view, x, y)
          view.tooltip = @ip.valid? ? @ip.tooltip : ''
        elsif @state == :move
          update_window_delta(view, x, y)
        end
        window_status
        view.invalidate
      rescue StandardError => e
        Sketchup.set_status_text(e.message, SB_PROMPT)
      end

      def onLButtonDown(flags, x, y, view)
        case @state
        when :window
          @window_start = Geom::Point3d.new(x, y, 0)
          @window_end = @window_start.clone
        when :anchor
          @ip.pick(view, x, y)
          return UI.beep unless @ip.valid?
          @anchor = world_to_root(@ip.position)
          @state = :move
          @delta = 0.0
          @ip2.pick(view, x, y)
        when :move
          update_window_delta(view, x, y)
          apply_window
        end
        window_status
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Khoanh vùng co kéo:\n#{e.message}")
      end

      def onLButtonUp(flags, x, y, view)
        return unless @state == :window && @window_start
        @window_end = Geom::Point3d.new(x, y, 0)
        a, b = @window_start, @window_end
        @window_start = nil
        @window_end = nil
        if (a.x-b.x).abs < 4 || (a.y-b.y).abs < 4
          UI.beep
          return window_status('Giữ chuột và khoanh vùng đủ rộng rồi thả.')
        end
        scan_window(view, [a.x,b.x].minmax + [a.y,b.y].minmax)
        @state = :anchor unless @selected_points.empty?
        window_status(@selected_points.empty? ? 'Vùng không có điểm. Khoanh lại hoặc chọn đúng Group trước.' : nil)
        view.invalidate
      rescue StandardError => e
        clear_window
        UI.messagebox("Không chọn được vùng:\n#{e.message}")
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 9 && @state == :window && !@window_start
          @model.select_tool(Tool.new)
          return true
        end
        if [37,38,39,40,88,89,90].include?(key) && @state == :move
          return true if repeat.to_i > 1
          next_axis = {39=>0,37=>1,38=>2,88=>0,89=>1,90=>2}[key]
          @forced_axis = key == 40 || @forced_axis == next_axis ? nil : next_axis
          @axis = @forced_axis
          @delta = 0.0
          @direction_sign = 1
          window_status
          view.invalidate
          return true
        end
        false
      end

      def onKeyUp(*args); false; end

      def onUserText(text, view)
        return UI.beep unless @state == :move
        raise 'Chọn hướng bằng chuột hoặc phím X/Y/Z trước khi nhập số.' unless @axis
        raise 'Chế độ khoanh vùng nhận khoảng dịch, ví dụ 100 hoặc -50; không dùng dấu =.' if text.to_s.strip.start_with?('=')
        amount = parse_input_length(text)
        raise 'Khoảng dịch không hợp lệ.' unless amount && amount.to_f.finite?
        @delta = amount.to_f * @direction_sign
        apply_window
        window_status
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Khoanh vùng co kéo:\n#{e.message}")
      end

      def onCancel(reason, view)
        if reason == 2 || @state != :window || @window_start
          clear_window
          window_status('Đã hủy vùng; khoanh lại. Model chưa bị thay đổi bởi preview.')
          view.invalidate
        else
          @model.select_tool(nil)
        end
      end

      def draw(view)
        view.line_width = 2
        if @window_start && @window_end
          a,b=@window_start,@window_end
          points=[a,Geom::Point3d.new(b.x,a.y,0),b,Geom::Point3d.new(a.x,b.y,0)]
          view.drawing_color=Sketchup::Color.new(255,150,20,35)
          view.draw2d(GL_QUADS,points)
          view.drawing_color=Sketchup::Color.new(255,155,20)
          view.line_stipple='-'
          view.draw2d(GL_LINE_LOOP,points)
          view.line_stipple=''
        end
        unless @selected_points.empty?
          view.draw_points(@selected_points.first(8000).map{|p|root_to_world(p)},5,2,Sketchup::Color.new(255,145,0))
          if @state==:move && @axis && @delta.abs>0.001.mm
            points=@preview_edges.flat_map do |a,b,sa,sb|
              [shifted_preview(a,sa),shifted_preview(b,sb)].map{|p|root_to_world(p)}
            end
            view.drawing_color=AXIS_COLORS[@axis]
            view.draw(GL_LINES,points) unless points.empty?
            view.draw_points(@selected_points.first(8000).map{|p|root_to_world(shifted_preview(p,true))},5,2,AXIS_COLORS[@axis])
          end
        end
        @ip.draw(view) if @ip.valid? && [:anchor,:move].include?(@state)
        view.draw_text(Geom::Point3d.new(15,25,0),"KHOANH VÙNG MỘT PHẦN · #{@selected_points.length} điểm · chọn xuyên chiều sâu")
      rescue StandardError => e
        puts "[TT Window preview] #{e.message}"
      ensure
        view.line_stipple='' if view
      end

      def getExtents
        bb=Geom::BoundingBox.new
        @selected_points.each do |p|
          bb.add(root_to_world(p))
          bb.add(root_to_world(shifted_preview(p,true))) if @axis
        end
        bb
      end

      private

      def clear_window
        @nodes=[];@selected_points=[];@preview_edges=[]
        @window_start=nil;@window_end=nil;@axis=nil;@forced_axis=nil;@delta=0.0
        @direction_sign=1;@anchor=nil;@state=:window
        @ip=Sketchup::InputPoint.new;@ip2=Sketchup::InputPoint.new
        clear_vcb
      end

      def window_status(extra=nil)
        text=extra || case @state
        when :window
          'KHOANH VÙNG · giữ chuột kéo khung rồi thả · chọn xuyên chiều sâu · TAB về co kéo P1/P2/P3.'
        when :anchor
          "Đã chọn #{@selected_points.length} điểm màu cam · bấm điểm gốc để bắt đầu kéo · ESC khoanh lại."
        when :move
          axis=@axis ? axis_name(@axis) : 'tự nhận'
          "Kéo theo #{axis} · → X / ← Y / ↑ Z / ↓ bỏ khóa · click để chốt hoặc nhập mm · ngoài vùng giữ nguyên · ESC hủy."
        end
        Sketchup.set_status_text(text,SB_PROMPT)
        if @state==:move
          Sketchup.set_status_text('Khoảng dịch (mm)',SB_VCB_LABEL)
          Sketchup.set_status_text(Sketchup.format_length(@delta),SB_VCB_VALUE)
        end
      end

      def update_window_delta(view,x,y)
        @ip.pick(view,x,y,@ip2)
        return unless @ip.valid?
        p=world_to_root(@ip.position)
        axis=@forced_axis || dominant_axis(@anchor,p)
        return unless axis
        @axis=axis
        if @ip.degrees_of_freedom<3
          @delta=coord(p,axis)-coord(@anchor,axis)
          view.tooltip=@ip.tooltip
        else
          vector=AXES[axis].transform(@context_to_world)
          vector.normalize!
          points=Geom.closest_points(view.pickray(x,y),[root_to_world(@anchor),vector])
          return unless points && points[1]
          @delta=coord(world_to_root(points[1]),axis)-coord(@anchor,axis)
          view.tooltip=''
        end
        @direction_sign=@delta<0 ? -1 : 1 if @delta.abs>0.001.mm
      end

      def shifted_preview(p,selected)
        q=clone_point(p)
        set_coord(q,@axis,coord(q,@axis)+@delta) if selected && @axis
        q
      end

      # Projection is evaluated once on release; selected 3D points stay frozen during orbit.
      def scan_window(view,rect)
        clear_window
        @context_to_world=@model.edit_transform
        groups=@model.selection.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
        @scope=(groups.empty? ? @model.active_entities.to_a : groups).select{|e|selectable?(e)}
        @scan_count=0
        @nodes=@scope.map{|e|scan_node(e,Geom::Transformation.new,view,rect)}.compact
      end

      def scan_node(entity,parent_tr,view,rect)
        return nil unless selectable?(entity)
        tr=parent_tr*entity.transformation
        entities=child_entities(entity)
        edges=entities.grep(Sketchup::Edge).select(&:valid?)
        vertices=edges.flat_map(&:vertices).uniq
        @scan_count+=vertices.length
        raise 'Vùng quá nhiều điểm (hơn 100.000). Chọn riêng tủ/Group cần sửa trước khi khoanh.' if @scan_count>100_000
        selected={}
        vertices.each do |v|
          root=v.position.transform(tr);world=root_to_world(root)
          camera=view.camera
          depth=(world.x-camera.eye.x)*camera.direction.x+(world.y-camera.eye.y)*camera.direction.y+(world.z-camera.eye.z)*camera.direction.z
          next if depth<=0
          screen=view.screen_coords(world)
          if screen.x>=rect[0] && screen.x<=rect[1] && screen.y>=rect[2] && screen.y<=rect[3]
            selected[v.position.to_a]=true
            @selected_points << root
          end
        end
        edges.each do |edge|
          a,b=edge.vertices;sa=!!selected[a.position.to_a];sb=!!selected[b.position.to_a]
          if (sa || sb) && @preview_edges.length<12_000
            @preview_edges << [a.position.transform(tr),b.position.transform(tr),sa,sb]
          end
        end
        children=entities.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
        snapshots=children.map{|child|scan_node(child,tr,view,rect)}
        return nil if selected.empty? && snapshots.compact.empty?
        {entity:entity,definition:entity.definition,transform:entity.transformation.to_a,
         positions:vertices.map{|v|v.position.to_a}.uniq.sort, selected:selected,
         children:children.map{|c|child_signature(c)}, snapshots:snapshots}
      end

      def child_signature(entity)
        bb=entity.definition.bounds
        [entity.transformation.to_a, bb.empty? ? nil : [bb.min.to_a,bb.max.to_a]]
      end

      def node_geometry(entity,node)
        raise 'Khối đã bị xóa/khóa/ẩn; hãy khoanh lại.' unless selectable?(entity)
        raise 'Khối đã đổi vị trí; hãy khoanh lại.' unless entity.transformation.to_a==node[:transform]
        es=child_entities(entity);edges=es.grep(Sketchup::Edge).select(&:valid?)
        vertices=edges.flat_map(&:vertices).uniq
        raise 'Hình học đã thay đổi; hãy khoanh lại.' unless vertices.map{|v|v.position.to_a}.uniq.sort==node[:positions]
        children=es.to_a.select{|e|e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)}
        actual=children.map{|c|child_signature(c)}
        raise 'Cấu trúc khối đã thay đổi; hãy khoanh lại.' unless actual==node[:children]
        [es,edges,vertices,children]
      end

      def verify_node(entity,node,parent_tr)
        es,edges,vertices,children=node_geometry(entity,node)
        tr=parent_tr*entity.transformation
        edges.each do |edge|
          a,b=edge.vertices;sa=!!node[:selected][a.position.to_a];sb=!!node[:selected][b.position.to_a]
          next if sa==sb
          before=coord(b.position.transform(tr),@axis)-coord(a.position.transform(tr),@axis)
          after=before+(sb ? @delta : 0)-(sa ? @delta : 0)
          if before.abs>0.001.mm && before*after<=0
            raise 'Khoảng kéo làm đảo hoặc ép phẳng cạnh. Giảm khoảng dịch hoặc khoanh lại.'
          end
        end
        node[:snapshots].each_with_index{|child,i|verify_node(children[i],child,tr) if child}
      end

      def apply_node(entity,node,parent_tr,root_vector)
        ensure_unique(entity)
        es,edges,vertices,children=node_geometry(entity,node)
        tr=parent_tr*entity.transformation
        targets=vertices.select{|v|node[:selected][v.position.to_a]}
        unless targets.empty?
          local=root_vector.transform(tr.inverse)
          es.transform_by_vectors(targets,targets.map{Geom::Vector3d.new(local.x,local.y,local.z)})
        end
        node[:snapshots].each_with_index{|child,i|apply_node(children[i],child,tr,root_vector) if child}
      end

      def apply_window
        raise 'Chọn hướng và khoảng kéo khác 0.' unless @axis && @delta.abs>0.001.mm
        raise 'Không có điểm đã chọn.' if @nodes.empty?
        raise 'Chế độ sửa đã thay đổi; hãy gọi lại công cụ.' unless @context_to_world.to_a==@model.edit_transform.to_a
        if Array(@model.active_path).any?{|e|e.definition.instances.length>1}
          raise 'Đang sửa Component cha dùng chung. Thoát ra chọn khối từ ngoài để giữ nguyên các bản sao khác.'
        end
        @nodes.each{|node|verify_node(node[:entity],node,Geom::Transformation.new)}
        vector=AXES[@axis].clone;vector.length=@delta.abs;vector.reverse! if @delta<0
        @model.start_operation('TRẦN TUẤN - Khoanh vùng co kéo',true)
        begin
          @nodes.each{|node|apply_node(node[:entity],node,Geom::Transformation.new,vector)}
          @model.commit_operation
        rescue StandardError
          @model.abort_operation
          raise
        end
        clear_window
        true
      end
    end

    def self.activate
      Sketchup.active_model.select_tool(WindowTool.new)
      true
    end
  end
end
