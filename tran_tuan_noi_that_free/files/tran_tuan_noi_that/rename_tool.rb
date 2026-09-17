# encoding: UTF-8
require 'json'
require 'cgi'
module TranTuanNoiThat
  module RenameTool
    extend self
    def container?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end
    def entities(e); e.definition.entities; end
    def key(path); path.map(&:persistent_id).join('/'); end
    def transform(path)
      path.inject(Geom::Transformation.new) { |tr,e| tr*e.transformation }
    end
    def dimensions(entity,path)
      b=entity.definition.bounds; tr=transform(path)
      [b.width*tr.xaxis.length,b.height*tr.yaxis.length,b.depth*tr.zaxis.length].map { |v| v.to_mm.round(2) }
    end
    def row(path)
      e=path.last; children=entities(e).select { |x| container?(x) && x.valid? }
      dims=dimensions(e,path); leaf=children.empty? && entities(e).any? { |x| x.is_a?(Sketchup::Face) || x.is_a?(Sketchup::Edge) }
      {id:key(path),name:e.name.to_s,type:e.is_a?(Sketchup::Group) ? 'Group' : 'Component',
       tag:e.layer.name,depth:path.length-1,leaf:leaf,dims:dims,thickness:leaf ? dims.min : nil,
       locked:path.any?(&:locked?),shared:path[0...-1].any? { |p| p.definition.instances.length>1 }}
    end
    def summary(rows)
      details=rows.select { |r| r[:leaf] }
      {total:rows.length,details:details.length,assemblies:rows.length-details.length,
       thickness:details.group_by { |r| r[:thickness].round(1) }.sort.map { |t,rs| {value:t,count:rs.length} }}
    end
    def send_js(fn,data)
      @dialog.execute_script("#{fn}(#{JSON.generate(data)});") if @dialog && @dialog.visible?
    end
    def error(e); send_js('showError',e.to_s); end
    def ensure_model
      raise 'Model đã đổi. Đóng và mở lại Đổi Tên.' unless Sketchup.active_model==@model
    end
    def show
      if @dialog && @dialog.visible? && @model==Sketchup.active_model
        @dialog.bring_to_front; return
      end
      @dialog.close if @dialog && @dialog.visible?
      cleanup
      @model=Sketchup.active_model; @model.select_tool(nil); @paths={}; @rows=[]; @generation=0
      @dialog=UI::HtmlDialog.new(dialog_title:'TRẦN TUẤN – ĐỔI TÊN',preferences_key:'TT_Rename_178',width:1180,height:800,resizable:true,scrollable:true,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(RenameUI.html)
      @dialog.add_action_callback('scan') { |_c,all| scan(all==true) }
      @dialog.add_action_callback('choose') { |_c,id| choose(id,true) }
      @dialog.add_action_callback('projection') { |_c,id,axis| choose(id,false,axis) }
      @dialog.add_action_callback('save') { |_c,json| mutate(JSON.parse(json),false) rescue error($!.message) }
      @dialog.add_action_callback('clear_names') { |_c,json| mutate(JSON.parse(json),true) rescue error($!.message) }
      @dialog.add_action_callback('ready') { |_c| scan(false) }
      @dialog.set_on_closed { cleanup }
      @observer=SelectionWatcher.new; @model.selection.add_observer(@observer)
      @dialog.show
    end
    def cleanup
      @generation=(@generation || 0)+1
      UI.stop_timer(@timer) if @timer
      UI.stop_timer(@selection_timer) if @selection_timer
      @model.selection.remove_observer(@observer) if @model && @observer
      @observer=nil; @timer=nil; @selection_timer=nil; @busy=false
    rescue StandardError
      @observer=nil; @busy=false
    end
    def scan(all=false,paths=nil)
      ensure_model
      @generation+=1; generation=@generation; @busy=true
      UI.stop_timer(@timer) if @timer
      if paths
        queue=paths.select { |path| path.all?(&:valid?) }
      else
        prefix=all ? [] : (@model.active_path || [])
        selected=all ? [] : @model.selection.to_a.select { |e| container?(e) }
        roots=selected.empty? ? (all ? @model.entities : @model.active_entities).select { |e| container?(e) } : selected
        queue=roots.map { |e| prefix+[e] }
        @roots=queue.map(&:dup)
      end
      @paths={};@rows=[];visited={}
      send_js('scanState',{busy:true,message:'Đang quét…'})
      tick=nil
      tick=proc do
        begin
          next if generation!=@generation
          ensure_model
          100.times do
            path=queue.pop; break unless path
            next unless path.all?(&:valid?)
            id=key(path);next if visited[id];visited[id]=true
            raise 'Vượt 20.000 đối tượng. Chọn một cụm nhỏ hơn để quét.' if @rows.length>=20_000
            e=path.last; @paths[id]=path;@rows<<row(path)
            raise 'Cấu trúc lồng quá 64 cấp. Chọn cụm con để quét riêng.' if path.length>=64
            entities(e).each do |child|
              next unless container?(child) && child.valid?
              next if path.any? { |p| p.definition==child.definition }
              queue << path+[child]
            end
          end
          if queue.empty?
            @busy=false;@timer=nil;publish
          else
            send_js('scanState',{busy:true,message:"Đã quét #{@rows.length} đối tượng…"})
            @timer=UI.start_timer(0.01,false,&tick)
          end
        rescue StandardError=>e
          @busy=false;@timer=nil;send_js('scanState',{busy:false,message:'Quét chưa hoàn tất'});error(e.message)
        end
      end
      tick.call
    rescue StandardError=>e
      @busy=false;error(e.message)
    end
    def publish
      @rows=@paths.values.select { |p| p.all?(&:valid?) }.map { |p| row(p) }
      @rows.sort_by! { |r| [r[:name].downcase,r[:id]] }
      send_js('setRows',{rows:@rows,summary:summary(@rows)})
    end
    # Orthographic projection of real edges in the selected object's local axes.
    def outline(path,axis='auto')
      root=path.last; dims=dimensions(root,path)
      axes=case axis
      when 'xy';[0,1]
      when 'xz';[0,2]
      when 'yz';[1,2]
      else;(0..2).to_a.sort_by { |i| -dims[i] }[0,2]
      end
      tr=transform(path);scales=[tr.xaxis.length,tr.yaxis.length,tr.zaxis.length]
      stack=[[root,Geom::Transformation.new,[]]];lines=[];truncated=false
      until stack.empty?
        obj,local,ancestors=stack.pop
        next if ancestors.include?(obj.definition)
        entities(obj).each do |e|
          if e.is_a?(Sketchup::Edge)
            a=e.start.position.transform(local).to_a;b=e.end.position.transform(local).to_a
            points=[a,b].map { |p| axes.map { |i| (p[i]*scales[i]).to_mm } }
            lines<<points unless points[0]==points[1]
            if lines.length>=6000;truncated=true;break;end
          elsif container?(e) && e.valid?
            stack<<[e,local*e.transformation,ancestors+[obj.definition]]
          end
        end
        break if truncated
      end
      return {svg:'',note:'Đối tượng không có cạnh để hiển thị.'} if lines.empty?
      xs=lines.flatten(1).map(&:first);ys=lines.flatten(1).map(&:last)
      w=[xs.max-xs.min,0.01].max;h=[ys.max-ys.min,0.01].max;k=[440/w,340/h].min
      body=lines.uniq.map do |a,b|
        p=[a,b].map { |x,y| [30+(x-xs.min)*k,30+(ys.max-y)*k] }
        "M#{p[0][0].round(2)},#{p[0][1].round(2)}L#{p[1][0].round(2)},#{p[1][1].round(2)}"
      end.join(' ')
      {svg:"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 500 400'><path d='#{body}' fill='none' stroke='#ce782a' stroke-width='1.2'/></svg>",note:truncated ? 'Hiển thị tối đa 6.000 cạnh.' : 'Biên dạng chiếu từ cạnh thật; gồm cạnh trước và sau.'}
    end
    def choose(id,select_model=false,axis='auto')
      ensure_model;raise 'Đợi quét xong.' if @busy
      path=@paths[id];raise 'Đối tượng không còn tồn tại. Quét lại.' unless path && path.all?(&:valid?)
      if select_model && !path.any?(&:locked?)
        @syncing=true
        begin
          parent=path[0...-1]
          @model.active_path=parent.empty? ? nil : parent
          @model.selection.clear;@model.selection.add(path.last)
        ensure;@syncing=false;end
      end
      send_js('showDetail',row(path).merge(outline(path,axis)))
    rescue StandardError=>e;error(e.message)
    end
    def selection_changed
      return if @syncing || @busy || !@dialog || !@dialog.visible?
      UI.stop_timer(@selection_timer) if @selection_timer
      @selection_timer=UI.start_timer(0.1,false) do
        @selection_timer=nil
        begin
          ensure_model
          prefix=@model.active_path || []
          paths=@model.selection.to_a.select { |e| container?(e) }.map { |e| prefix+[e] }
          ids=paths.map { |p| key(p) }
          paths.each { |p| @paths[key(p)]=p }
          publish unless paths.empty?
          send_js('selectRows',ids)
          choose(ids.first,false) if ids.first
        rescue StandardError=>e;error(e.message);end
      end
    end
    def mutate(data,clear)
      ensure_model;raise 'Đợi quét xong.' if @busy
      ids=Array(data['ids']).uniq
      raise 'Chọn ít nhất một đối tượng trong danh sách.' if ids.empty?
      paths=ids.map { |id| @paths[id] }
      raise 'Có đối tượng đã bị xóa. Quét lại trước khi lưu.' unless paths.all? { |p| p && p.all?(&:valid?) }
      raise 'Có đối tượng hoặc nhóm cha đang khóa.' if paths.any? { |p| p.any?(&:locked?) }
      raise 'Chi tiết nằm trong nhóm cha có nhiều bản sao. Make Unique nhóm cha trước khi đổi riêng chi tiết đó.' if paths.any? { |p| p[0...-1].any? { |e| e.definition.instances.length>1 } }
      name=data['name'].to_s.strip;tag=data['tag'].to_s.strip
      raise 'Tên tối đa 120 ký tự.' if name.length>120 || tag.length>120
      raise 'Nhập tên mới hoặc dùng Xóa tên.' if !clear && name.empty?
      @model.start_operation(clear ? 'TT - Xóa / thay tên' : 'TT - Đổi tên chi tiết',true);started=true
      layer= if clear || data['change_tag']==true
        tag.empty? ? @model.layers[0] : (@model.layers[tag] || @model.layers.add(tag))
      end
      paths.map(&:last).uniq.each do |e|
        e.name=name;e.layer=layer if layer
      end
      @model.commit_operation;started=false
      publish
      choose(ids.first,false)
      send_js('saved',{count:paths.length,ids:ids,message:"Đã lưu #{paths.length} đối tượng. Ctrl+Z hoàn tác lượt này."})
    rescue StandardError=>e
      @model.abort_operation if started
      error(e.message)
    end
    class SelectionWatcher < Sketchup::SelectionObserver
      def onSelectionBulkChange(_s);RenameTool.selection_changed;end
      def onSelectionAdded(_s,_e);RenameTool.selection_changed;end
      def onSelectionCleared(_s);RenameTool.selection_changed;end
      def onSelectionRemoved(_s,_e);RenameTool.selection_changed;end
      alias_method :onSelectedRemoved,:onSelectionRemoved
    end
  end
end
