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
      data={layers:@layers||[],walls:@walls||[],symbols:@symbols||[],height:(@options||{})[:height],base:(@options||{})[:base]}
      @dialog.execute_script("receive(#{JSON.generate(data)})")
      @model.active_view.invalidate if @model && Sketchup.active_model==@model
    end
    def same_context!
      raise 'Model hoặc ngữ cảnh chỉnh sửa đã đổi. Mở lại công cụ và quét lại.' unless Sketchup.active_model==@model && @model.active_entities==@context
    end
    def open
      if @dialog && @dialog.visible?;@dialog.bring_to_front;return;end
      @model=Sketchup.active_model;@context=@model.active_entities;@edit=@model.edit_transform
      @walls=[];@raw=[];@layers=[];@symbols=[];@sources=[];@job=nil
      @dialog=UI::HtmlDialog.new(dialog_title:'TT — Nhập CAD / Dựng tường',preferences_key:'TT_CAD_WALLS',scrollable:true,resizable:true,width:1100,height:780,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_html(CadWallsUI.html)
      @dialog.add_action_callback('ready'){|_|send_data}
      @dialog.add_action_callback('import_cad'){|_|guard{import_cad}}
      @dialog.add_action_callback('scan_selected'){|_|guard{scan_selected}}
      @dialog.add_action_callback('recognize'){|_,payload|guard{recognize(JSON.parse(payload))}}
      @dialog.add_action_callback('toggle_wall'){|_,id,selected|guard{raise 'Đang quét.' if @job;c=@walls.find{|w|w[:id]==id.to_i};c[:selected]=!!selected if c;send_data}}
      @dialog.add_action_callback('preview'){|_|guard{preview}}
      @dialog.add_action_callback('create'){|_|guard{create}}
      @dialog.add_action_callback('cancel_job'){|_|@job=nil;message('Đã dừng quét. Hình học gốc được giữ nguyên.')}
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
        rescue StandardError=>e
          @job=nil;message(e.message)
        end
      end
    end
    def scan_selected
      raise 'Đợi quét xong hoặc bấm Dừng.' if @job
      selected=@model.selection.to_a
      raise 'Chọn Group CAD hoặc các nét mặt bằng cần quét trước.' if selected.empty?
      @sources=selected;@walls=[];@raw=[];@layers=[];@symbols=[];send_data
      run_job do |yielder|
        stack=selected.map{|e|[e,@edit,'',0]};stats={};curves={};visited=0;nonplanar=0;zs=[]
        until stack.empty?
          e,tr,inherited,depth=stack.pop
          next unless e.valid?
          visited+=1
          raise 'Bản vẽ quá lớn (>100.000 đối tượng). Chọn riêng mặt bằng hoặc lớp cần dựng.' if visited>100000
          next if e.respond_to?(:hidden?) && e.hidden?
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
        @layers=stats.values.sort_by{|s|s[:name]};@layers.each{|s|s[:use]=s[:kind]=='Tường'}
        @layers.select{|s|s[:kind].include?('kiểm tra')}.each{|s|@symbols<<{name:s[:name],kind:s[:kind],count:s[:count]}}
        @symbols=@symbols.first(200)
        @multi_level=!zs.empty? && zs.max-zs.min>1.0
        send_data
        message("Đọc #{@raw.length} nét thẳng / #{@layers.length} lớp; bỏ #{nonplanar} nét nghiêng Z. #{@multi_level ? 'Có nhiều cao độ: chọn riêng mặt bằng cùng cao độ rồi quét lại.' : 'Kiểm tra lớp tường, tỷ lệ rồi bấm Nhận diện.'}")
      end
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
      layers=Array(data['layers']);@layers.each{|l|l[:use]=layers.include?(l[:name])}
      edges=@raw.select{|e|layers.include?(e[:layer])}.map{|e|{a:e[:a].map{|v|v*scale},b:e[:b].map{|v|v*scale},layer:e[:layer]}}
      raise 'Chọn ít nhất một lớp có nét thẳng.' if edges.empty?
      @walls=[];send_data
      run_job do |y|
        message('Đang ghép cặp nét tường…');y<<nil
        @walls=CadWallEngine.recognize(edges,@options){|p|message("Nhận diện #{(p*100).round}%…");y<<nil}
        send_data
        message("Có #{@walls.length} đoạn tường; #{@walls.count{|w|!w[:selected]}} đoạn chồng nhau cần chọn lại. Xem trước và kiểm tra khoảng cửa trước khi tạo.")
        if @walls.empty?
          message('Không tìm được tường theo độ dày đã nhập. Kiểm tra lớp WALL/TƯỜNG, hệ số tỷ lệ và bổ sung độ dày thực tế (ví dụ 250 mm), rồi bấm Nhận diện lại.')
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
          quads=low+high.reverse
          4.times{|i|j=(i+1)%4;quads.concat([low[i],low[j],high[j],high[i]])}
          view.drawing_color=Sketchup::Color.new(245,182,112,85);view.draw(GL_QUADS,quads)
          view.drawing_color=Sketchup::Color.new(173,101,37);view.line_width=1
          view.draw(GL_LINE_LOOP,low);view.draw(GL_LINE_LOOP,high)
          view.draw(GL_LINES,4.times.flat_map{|i|[low[i],high[i]]})
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
