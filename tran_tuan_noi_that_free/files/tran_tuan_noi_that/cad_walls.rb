# encoding: UTF-8
require 'sketchup.rb'
require 'json'
module TranTuanNoiThat
  module CadWalls
    extend self
    def close
      @job=nil
      @dialog.close if @dialog
      @dialog=nil
    end
    def message(text)
      @dialog.execute_script("setStatus(#{JSON.generate(text.to_s)})") if @dialog
    end
    def send_data
      return unless @dialog
      data={evidence:@evidence||[],layers:@layers||[],walls:@walls||[],symbols:@symbols||[],raw:(@raw||[]).first(20000),scale:@scale||1.0,height:(@options||{})[:height],base:(@options||{})[:base]}
      @dialog.execute_script("receive(#{JSON.generate(data)})")
      @model.active_view.invalidate if @model && Sketchup.active_model==@model
    end
    def same_context!
      raise 'Model hoặc ngữ cảnh chỉnh sửa đã đổi. Mở lại công cụ và quét lại.' unless Sketchup.active_model==@model && @model.active_entities==@context
    end
    def open
      if @dialog && @dialog.visible?;@dialog.bring_to_front;return;end
      @model=Sketchup.active_model;@context=@model.active_entities;@edit=@model.edit_transform
      @walls=[];@raw=[];@layers=[];@symbols=[];@sources=[];@job=nil;@scale=1.0;@options=nil;@evidence=[]
      @dialog=UI::HtmlDialog.new(dialog_title:'TT — Nhập CAD / Dựng tường',preferences_key:'TT_CAD_WALLS',scrollable:true,resizable:true,width:1100,height:780,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(CadWallsUI.html)
      @dialog.add_action_callback('ready'){|_|send_data}
      @dialog.add_action_callback('import_cad'){|_|guard{import_cad}}
      @dialog.add_action_callback('scan_selected'){|_|guard{scan_selected}}
      @dialog.add_action_callback('recognize'){|_,payload|guard{recognize(JSON.parse(payload))}}
      @dialog.add_action_callback('toggle_wall'){|_,id,selected|guard{raise 'Đang quét.' if @job;c=@walls.find{|w|w[:id]==id.to_i};c[:selected]=!!selected if c;send_data}}
      @dialog.add_action_callback('save_rules'){|_,payload|guard{save_rules(JSON.parse(payload))}}
      @dialog.add_action_callback('manual_wall'){|_,payload|guard{add_manual(JSON.parse(payload))}}
      @dialog.add_action_callback('preview'){|_|guard{preview}}
      @dialog.add_action_callback('create'){|_|guard{create}}
      @dialog.add_action_callback('cancel_job'){|_|@job=nil;@recognize_after_scan=false;message('Đã dừng quét. Hình học gốc được giữ nguyên.')}
      @dialog.set_on_closed do
        @job=nil
        @model.select_tool(nil) if @preview_active && Sketchup.active_model==@model
        @dialog=nil
      end
      @dialog.show
    end
    def guard
      same_context!;yield
    rescue StandardError=>e
      @job=nil;message(e.message);puts("[TT CAD] #{e.class}: #{e.message}")
    end
    def import_cad
      raise 'Đợi quét xong hoặc bấm Dừng.' if @job
      path=UI.openpanel('Chọn bản vẽ CAD mặt bằng',nil,'CAD (*.dwg;*.dxf)|*.dwg;*.dxf||')
      return unless path
      raise 'Chọn tệp DWG hoặc DXF.' unless ['.dwg','.dxf'].include?(File.extname(path).downcase)
      raise 'Nhập CAD cần SketchUp 2021.1 trở lên và bộ nhập DWG/DXF. Có thể nhập bằng File > Import rồi chọn bản CAD để quét.' unless @model.definitions.respond_to?(:import)
      @model.start_operation('TT - Nhập CAD',true)
      begin
        definition=@model.definitions.import(path,{merge_coplanar_faces:true,orient_faces:true,preserve_origin:false,import_materials:false,show_summary:false})
        raise 'SketchUp không nhập được CAD. Kiểm tra định dạng và bộ nhập DWG/DXF.' unless definition
        instance=@context.add_instance(definition,Geom::Transformation.new)
        instance.name="CAD — #{File.basename(path)}"
        @model.selection.clear;@model.selection.add(instance)
        @model.commit_operation
      rescue StandardError
        @model.abort_operation;raise
      end
      scan_selected
    end
    def run_job(&block)
      raise 'Đang có tác vụ quét. Bấm Dừng trước khi quét lại.' if @job
      @job=Enumerator.new(&block);advance_job
    end
    def advance_job
      current=@job;return unless current && @dialog
      UI.start_timer(0.02,false) do
        next unless @job.equal?(current) && @dialog
        begin
          same_context!;current.next;advance_job
        rescue StopIteration
          @job=nil
          if @recognize_after_scan
            @recognize_after_scan=false;@dialog.execute_script('recognize()') if @dialog
          end
        rescue StandardError=>e
          @job=nil;message(e.message)
        end
      end
    end
    def scan_selected
      raise 'Đợi quét xong hoặc bấm Dừng.' if @job
      selected=@model.selection.to_a
      selected=@context.to_a if selected.empty?
      raise 'Không có đối tượng để quét.' if selected.empty?
      @recognize_after_scan=false;@sources=selected;@options=nil;@scale=1.0;@evidence=[];@walls=[];@raw=[];@layers=[];@symbols=[];send_data
      run_job do |yielder|
        stack=selected.map{|e|[e,@edit,'',0]};stats={};curves={};visited=0;nonplanar=0;zs=[]
        until stack.empty?
          e,tr,inherited,depth=stack.pop
          next unless e.valid?
          visited+=1
          raise 'Bản vẽ quá lớn (>100.000 đối tượng). Chọn riêng mặt bằng hoặc lớp cần dựng.' if visited>100000
          next if e.respond_to?(:hidden?) && e.hidden?
          next if e.respond_to?(:layer) && e.layer && e.layer.respond_to?(:visible?) && !e.layer.visible?
          next if e.respond_to?(:get_attribute) && e.get_attribute('TT_CAD_WALLS','generated',false)
          tag=e.respond_to?(:layer) && e.layer ? e.layer.name.to_s : ''
          tag='' if e.respond_to?(:layer) && e.layer==@model.layers[0]
          label=tag.empty? ? inherited : tag
          if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            raise 'CAD lồng quá 48 cấp.' if depth>48
            name=e.name.to_s
            name=e.definition.name.to_s if name.empty? && e.is_a?(Sketchup::ComponentInstance)
            label=name if !name.empty? && (label.empty? || CadWallEngine.label_kind(name)!='Chưa phân loại')
            ents=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
            nt=tr*e.transformation
            ents.each{|child|stack<<[child,nt,label,depth+1]}
          elsif e.is_a?(Sketchup::Edge)
            label='Không có lớp' if label.empty?
            s=(stats[label]||={name:label,count:0,kind:CadWallEngine.label_kind(label)})
            s[:count]+=1
            a=e.start.position.transform(tr);b=e.end.position.transform(tr)
            if (a.z-b.z).abs>1.mm
              nonplanar+=1
            elsif e.curve && e.curve.is_a?(Sketchup::ArcCurve)
              key=[e.curve.object_id,tr.to_a]
              unless curves[key]
                curves[key]=true
                r=e.curve.radius.to_mm;angle=(e.curve.end_angle-e.curve.start_angle).abs*180.0/Math::PI
                @symbols << {name:label,kind:(angle-90).abs<3 && r.between?(450,1600) ? 'Cung 90° — có thể là cửa đi; chưa khoét' : 'Cung tròn — chưa phân loại',count:1}
              end
            else
              @raw << {a:[a.x.to_mm,a.y.to_mm],b:[b.x.to_mm,b.y.to_mm],layer:label}
              zs<<a.z.to_mm
            end
          end
          if visited%500==0
            message("Đang đọc CAD: #{visited} đối tượng…");yielder<<nil
          end
        end
        @layers=stats.values.sort_by{|s|s[:name]};rules=read_rules
        @layers.each{|s|s[:role]=rules.fetch(s[:name],CadWallEngine.role_for(s[:name]));s[:use]=s[:role]=='Tường'}
        @layers.select{|s|s[:kind].include?('kiểm tra')}.each{|s|@symbols<<{name:s[:name],kind:s[:kind],count:s[:count]}}
        @symbols=@symbols.first(200)
        @recognize_after_scan=true
        @multi_level=!zs.empty? && zs.max-zs.min>1.0
        send_data
        message("Đọc #{@raw.length} nét thẳng / #{@layers.length} lớp; bỏ #{nonplanar} nét nghiêng Z. #{@multi_level ? 'Có nhiều cao độ: chọn riêng mặt bằng cùng cao độ rồi quét lại.' : 'Kiểm tra lớp tường, tỷ lệ rồi bấm Nhận diện.'}")
      end
    end
    def read_rules
      value=JSON.parse(Sketchup.read_default('TT_CAD_WALLS','layer_rules','{}').to_s)
      value.is_a?(Hash) ? value.select{|k,v|k.is_a?(String)&&CadWallEngine::ROLES.include?(v)} : {}
    rescue JSON::ParserError
      {}
    end
    def save_rules(data)
      rules=read_rules
      @layers.each do |l|
        role=data[l[:name]]
        next unless CadWallEngine::ROLES.include?(role)
        rules[l[:name]]=role
      end
      raise 'Không lưu được quy tắc.' unless Sketchup.write_default('TT_CAD_WALLS','layer_rules',JSON.generate(rules))
      message('Đã lưu phân loại theo đúng tên lớp; áp dụng khi quét lại các bản vẽ cùng chuẩn.')
    end
    def add_manual(data)
      raise 'Đợi nhận diện hoàn tất.' if @job
      raise 'Bấm Nhận diện để xác nhận thông số trước.' unless @options
      raise 'Quá 800 đoạn tường.' if @walls.length>=800
      width=number(data['width'],30,2000,'Dày tường')
      wall=CadWallEngine.manual_wall(data['a'],data['b'],width,(@walls.map{|w|w[:id]}.max||-1)+1)
      @walls<<wall;send_data
      message('Đã thêm preview theo tim tường. Kiểm tra vị trí, độ dày và khoảng cửa rồi mới TẠO TƯỜNG.')
    end
    def number(value,min,max,label)
      n=Float(value.to_s.tr(',','.'));raise "#{label} phải từ #{min} đến #{max}." unless n.finite? && n>=min && n<=max;n
    end
    def recognize(data)
      raise 'Quét CAD trước.' if @raw.empty?
      raise 'CAD có nhiều cao độ. Chọn riêng một mặt bằng cùng cao độ rồi quét lại.' if @multi_level
      raise 'Đợi quét xong hoặc bấm Dừng.' if @job
      widths=data.fetch('widths','').split(/[;,\s]+/).reject(&:empty?).map{|v|number(v,30,2000,'Dày tường')}.uniq
      raise 'Nhập ít nhất một độ dày, ví dụ 110;220.' if widths.empty?
      scale=number(data['scale'],0.000001,1000000,'Hệ số tỷ lệ')
      @options={height:number(data['height'],100,30000,'Cao tường'),base:number(data['base'],-100000,100000,'Cao độ chân'),widths:widths,tolerance:number(data['tolerance'],0.1,10,'Sai số'),min_length:number(data['min_length'],50,10000,'Đoạn ngắn nhất')}
      @scale=scale
      roles=data['roles'].is_a?(Hash) ? data['roles'] : {}
      layers=Array(data['layers']);@layers.each{|l|l[:use]=layers.include?(l[:name]);l[:role]=roles[l[:name]] if CadWallEngine::ROLES.include?(roles[l[:name]])}
      all_edges=@raw.map{|e|{a:e[:a].map{|v|v*scale},b:e[:b].map{|v|v*scale},layer:e[:layer]}}
      role_map=@layers.to_h{|l|[l[:name],l[:role]]}
      edges=all_edges.select{|e|layers.include?(e[:layer])}
      # Empty selection still allows explicit manual wall tracing over source CAD.
      @walls=[];send_data
      run_job do |y|
        message('Đang kiểm tra khoảng cách cặp nét…');y<<nil
        @evidence=CadWallEngine.width_evidence(edges){y<<nil}
        message('Đang ghép cặp nét tường…');y<<nil
        outlines,used=CadWallEngine.closed_outlines(all_edges,role_map,@options){y<<nil}
        pairs=CadWallEngine.recognize(edges,@options){|p|message("Nhận diện #{(p*100).round}%…");y<<nil}
        unknown=all_edges.select{|e|role_map[e[:layer]]=='Chưa rõ' && e[:layer].to_s !~ /guide|raster/i}
        measured=CadWallEngine.width_evidence(unknown){y<<nil}
        suggested=CadWallEngine.recognize(unknown,@options.merge(widths:(@options[:widths]+measured.map{|v|v[:width]}).uniq)){y<<nil}
        suggested.select!{|w|w[:length]>=1000 && w[:length]/w[:width]>=5}
        suggested.each{|w|w[:selected]=false;w[:warning]='Cặp nét nghi là tường — xác nhận trước khi dựng'}
        pairs+=suggested
        # Do not add a closed contour over an already proposed parallel strip.
        outlines.reject! do |outline|
          bounds=CadWallEngine.footprint(outline).transpose.map(&:minmax)
          pairs.any? do |pair|
            next false unless pair[:layer]==outline[:layer]
            other=CadWallEngine.footprint(pair).transpose.map(&:minmax)
            2.times.all?{|axis|[bounds[axis][1],other[axis][1]].min-[bounds[axis][0],other[axis][0]].max>0.01}
          end
        end
        @walls=outlines+pairs
        raise 'Quá 800 kết quả. Chọn riêng mặt bằng cần dựng.' if @walls.length>800
        @walls.each_with_index{|w,i|w[:id]=i}
        send_data
        message("Có #{@walls.length} đoạn tường; #{@walls.count{|w|!w[:selected]}} đường bao cần xác nhận. Xem trước và kiểm tra khoảng cửa trước khi tạo.")
        if @walls.empty?
          message('Chưa có cặp nét tường phù hợp. Kiểm tra phân loại/độ dày hoặc bật Thêm theo tim trên nền CAD. Lớp GUIDE/VECTOR cần xác nhận, không tự coi là tường.')
        else
          preview
        end
      end
    end
    def preview
      raise 'Chưa có kết quả nhận diện.' if @walls.empty?
      @model.select_tool(Preview.new(self))
      b=Geom::BoundingBox.new
      @walls.select{|w|w[:selected]}.each{|w|CadWallEngine.footprint(w).each{|p|b.add(Geom::Point3d.new(p[0].mm,p[1].mm,@options[:base].mm));b.add(Geom::Point3d.new(p[0].mm,p[1].mm,(@options[:base]+@options[:height]).mm))}}
      @model.active_view.zoom(b) unless b.empty?
      message('Preview 3D: màu cam nhạt. Dùng chuột giữa xoay góc nhìn; bỏ chọn đoạn sai trong bảng. Bấm TẠO TƯỜNG để xác nhận.')
    end
    def preview_active=(v);@preview_active=v;end
    def preview_data;[@walls||[],@options||{}];end
    def create
      raise 'Đợi nhận diện hoàn tất.' if @job
      chosen=@walls.select{|w|w[:selected]}
      raise 'Chưa chọn đoạn tường nào.' if chosen.empty?
      @model.start_operation('TT - Dựng tường từ CAD',true)
      begin
        parent=@context.add_group;parent.name='TT — Tường từ CAD'
        parent.set_attribute('TT_CAD_WALLS','generated',true)
        tag=@model.layers['TT_TUONG_CAD']||@model.layers.add('TT_TUONG_CAD');parent.layer=tag
        inv=@edit.inverse
        chosen.each_with_index do |w,i|
          group=parent.entities.add_group;group.name="Tường CAD #{i+1} — #{w[:width].round(1)}mm"
          # Build in world coordinates, then place inside the current editing context.
          pts=CadWallEngine.footprint(w).map{|p|Geom::Point3d.new(p[0].mm,p[1].mm,@options[:base].mm)}
          face=group.entities.add_face(pts);raise 'Không tạo được mặt tường.' unless face
          face.reverse! if face.normal.z<0
          face.pushpull(@options[:height].mm)
          raise 'Khối tường không kín; đã hủy lượt tạo.' unless group.manifold?
          group.transformation=inv
          group.set_attribute('TT_CAD_WALLS','source_layer',w[:layer])
          group.set_attribute('TT_CAD_WALLS','thickness_mm',w[:width])
        end
        WallJunctions.finish(parent)
        @model.selection.clear;@model.selection.add(parent);@model.commit_operation
      rescue StandardError
        @model.abort_operation;raise
      end
      @walls=[];@model.select_tool(nil) if @preview_active;send_data
      message("Đã tạo #{chosen.length} đoạn tường, hợp nhất và làm sạch giao L/T thành một Group Solid. CAD gốc giữ nguyên; Ctrl+Z hoàn tác lượt dựng. Góc giao/cửa chưa rõ cần kiểm tra theo CAD.")
    end
    class Preview
      def initialize(owner);@owner=owner;end
      def activate;@owner.preview_active=true;end
      def deactivate(view);@owner.preview_active=false;view.invalidate;end
      def onCancel(reason,view);Sketchup.active_model.select_tool(nil);end
      def draw(view)
        walls,opts=@owner.preview_data;return unless opts[:height]
        walls.select{|w|w[:selected]}.each do |w|
          low=CadWallEngine.footprint(w).map{|p|Geom::Point3d.new(p[0].mm,p[1].mm,opts[:base].mm)}
          high=low.map{|p|Geom::Point3d.new(p.x,p.y,p.z+opts[:height].mm)}
          quads=[]
          low.length.times{|i|j=(i+1)%low.length;quads.concat([low[i],low[j],high[j],high[i]])}
          view.drawing_color=Sketchup::Color.new(245,182,112,85);view.draw(GL_QUADS,quads)
          view.drawing_color=Sketchup::Color.new(173,101,37);view.line_width=1
          view.draw(GL_LINE_LOOP,low);view.draw(GL_LINE_LOOP,high)
          view.draw(GL_LINES,low.length.times.flat_map{|i|[low[i],high[i]]})
        end
      end
      def getExtents
        b=Geom::BoundingBox.new;walls,opts=@owner.preview_data
        walls.select{|w|w[:selected]}.each{|w|CadWallEngine.footprint(w).each{|p|b.add(Geom::Point3d.new(p[0].mm,p[1].mm,opts[:base].mm));b.add(Geom::Point3d.new(p[0].mm,p[1].mm,(opts[:base]+opts[:height]).mm))}} if opts[:height]
        b
      end
    end
  end
end
