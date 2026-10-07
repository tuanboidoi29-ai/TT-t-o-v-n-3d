# encoding: UTF-8
module TranTuanNoiThat
  module WineRack
    extend self
    # Convex polygon clipping in millimetres; all boards remain within P1/P2.
    def clip(poly,n,c)
      out=[]
      poly.each_with_index do |a,i|
        b=poly[(i+1)%poly.length]
        da=a[0]*n[0]+a[1]*n[1]-c;db=b[0]*n[0]+b[1]*n[1]-c
        out << a if da<=1e-7
        if (da<0 && db>0)||(da>0 && db<0)
          f=da/(da-db);out << [a[0]+f*(b[0]-a[0]),a[1]+f*(b[1]-a[1])]
        end
      end
      out=out.each_with_object([]){|p,r|r<<p if r.empty? || Math.hypot(p[0]-r[-1][0],p[1]-r[-1][1])>1e-6}
      out.pop if out.length>1 && Math.hypot(out[0][0]-out[-1][0],out[0][1]-out[-1][1])<1e-6
      out
    end
    def area(p)
      return 0 if p.length<3
      p.each_with_index.sum{|a,i|b=p[(i+1)%p.length];a[0]*b[1]-a[1]*b[0]}.abs/2
    end
    def rect(x,y,w,h);[[x,y],[x+w,y],[x+w,y+h],[x,y+h]];end
    def layout(w,h,t,target,kind)
      raise 'Vùng quá nhỏ so với độ dày ván.' unless w>4*t && h>4*t
      iw=w-2*t;ih=h-2*t
      polys=[rect(0,0,w,t),rect(0,h-t,w,t),rect(0,t,t,ih),rect(w-t,t,t,ih)]
      base=rect(t,t,iw,ih)
      if kind=='Vuông'
        cols=[((iw+t)/(target+t)).ceil,1].max
        rows=[((ih+t)/(target+t)).ceil,1].max
        raise 'Quá nhiều ô; tăng kích thước ô mong muốn.' if cols*rows>200
        cw=(iw-(cols-1)*t)/cols;ch=(ih-(rows-1)*t)/rows
        raise 'Ô quá nhỏ.' unless cw>1 && ch>1
        (1...cols).each{|i|polys<<rect(t+i*cw+(i-1)*t,t,t,ih)}
        cols.times{|i|(1...rows).each{|j|polys<<rect(t+i*(cw+t),t+j*ch+(j-1)*t,cw,t)}}
        note="#{cols} cột × #{rows} hàng · Lọt lòng #{cw.round(1)} × #{ch.round(1)} mm"
      else
        a=[1/Math.sqrt(2),1/Math.sqrt(2)];b=[-a[0],a[1]]
        bands=[]
        [a,b].each do |n|
          vals=base.map{|p|p[0]*n[0]+p[1]*n[1]};lo,hi=vals.minmax
          count=[((hi-lo)/(target+t)).ceil,1].max
          raise 'Quá nhiều nan chéo; tăng kích thước ô.' if count>20
          pitch=(hi-lo)/count
          raise 'Ô quá nhỏ.' unless pitch>t+1
          bands << [(1...count).map{|i|lo+pitch*i},n,pitch]
        end
        first,n,pitch=bands[0]
        first.each{|c|polys<<clip(clip(base,n,c+t/2),n.map{|v|-v},-c+t/2)}
        second,m,_=bands[1]
        second.each do |c|
          pieces=[clip(clip(base,m,c+t/2),m.map{|v|-v},-c+t/2)]
          first.each do |cut|
            pieces=pieces.flat_map{|p|[clip(p,n,cut-t/2),clip(p,n.map{|v|-v},-cut-t/2)]}.select{|p|area(p)>0.01}
          end
          polys.concat(pieces)
        end
        note="Ô chéo đầy đủ: cạnh lọt lòng #{(pitch-t).round(1)} mm · Ô sát khung được cắt theo biên"
      end
      polys=polys.select{|p|area(p)>0.01}
      raise 'Quá nhiều chi tiết; tăng kích thước ô.' if polys.length>250
      [polys,note]
    end
    def activate
      Sketchup.active_model.select_tool(Tool.new(17.5.mm))
    end
    class Tool < Board::Tool
      def initialize(thickness)
        super
        @wine_kind=TranTuanNoiThat.setting('wine_kind','Vuông')
        @wine_kind='Vuông' unless ['Vuông','Chéo'].include?(@wine_kind)
        @wine_t=TranTuanNoiThat.setting('wine_thickness',17.5).to_f
        @wine_depth=TranTuanNoiThat.setting('wine_depth',300).to_f
        @wine_cell=TranTuanNoiThat.setting('wine_cell',100).to_f
        @wine_polys=[]
      end
      def update(view,x,y)
        super
        @wine_polys=[];@wine_note=''
        return unless @loops && @loops.first && @loops.first.length==4 && @p1
        p,a,q,b=@loops.first
        u=a-p;v=b-p
        return if u.length<0.1.mm || v.length<0.1.mm
        polys,@wine_note=WineRack.layout(u.length.to_mm,v.length.to_mm,@wine_t,@wine_cell,@wine_kind)
        @wine_origin=p;@wine_u=u.normalize;@wine_v=v.normalize
        @wine_polys=polys
      rescue StandardError=>e
        @wine_polys=[];@wine_note=e.message
      end
      def world(p,back=false)
        pt=@wine_origin.offset(@wine_u,p[0].mm).offset(@wine_v,p[1].mm)
        back ? pt.offset(displacement,@wine_depth.mm) : pt
      end
      def onKeyDown(key,repeat,flags,view)
        if key==9
          return true if @held[key]
          @held[key]=true
          values=UI.inputbox(['Kiểu ô','Dày ván (mm)','Chiều sâu (mm)','Lọt lòng ô tối đa mong muốn (mm)'],
            [@wine_kind,@wine_t,@wine_depth,@wine_cell],['Vuông|Chéo','','',''],'Vẽ Ô Rượu')
          if values
            kind,t,d,c=values;t=Float(t);d=Float(d);c=Float(c)
            raise 'Độ dày, chiều sâu và kích thước ô phải dương.' unless [t,d,c].all?{|x|x.finite? && x>0} && t>=1 && c>t
            @wine_kind=kind;@wine_t=t;@wine_depth=d;@wine_cell=c
            {'kind'=>kind,'thickness'=>t,'depth'=>d,'cell'=>c}.each{|k,val|TranTuanNoiThat.save_setting("wine_#{k}",val)}
            update(view,*@mouse) if @mouse
          end
          @held.delete(9);status;view.invalidate;return true
        end
        return super if [16,17,70,37,38,39,40].include?(key)
        false
      rescue StandardError=>e
        @held.delete(9);UI.messagebox(e.message);true
      end
      def onMouseMove(flags,x,y,view)
        super
        status
      end
      def getExtents
        box=Geom::BoundingBox.new
        if @p1 && @wine_polys
          @wine_polys.each{|poly|poly.each{|p|box.add(world(p),world(p,true))}}
        end
        box
      end
      def enableVCB?;false;end
      def draw(view)
        @ip.draw(view) if @ip.display?
        return if !@wine_polys || @wine_polys.empty? || !@p1
        view.drawing_color=Sketchup::Color.new(255,180,195,100)
        @wine_polys.each do |poly|
          a=poly.map{|p|world(p)};b=poly.map{|p|world(p,true)}
          [a,b].each{|pts|view.draw(GL_TRIANGLES,(1...pts.length-1).flat_map{|i|[pts[0],pts[i],pts[i+1]]})}
          view.draw(GL_QUADS,a.each_index.flat_map{|i|j=(i+1)%a.length;[a[i],a[j],b[j],b[i]]})
          view.drawing_color=Sketchup::Color.new(160,80,95)
          view.draw(GL_LINE_LOOP,a);view.draw(GL_LINE_LOOP,b)
          view.drawing_color=Sketchup::Color.new(255,180,195,100)
        end
      end
      def create_board
        return false unless same_context? && @wine_polys && !@wine_polys.empty?
        @model.start_operation('TT - Vẽ Ô Rượu',true)
        parent=@context.add_group;parent.name="Ô Rượu #{@wine_kind}"
        @wine_polys.each_with_index do |poly,i|
          g=parent.entities.add_group;g.name=format('VAN_RUOU_%03d',i+1)
          face=g.entities.add_face(poly.map{|p|world(p)})
          raise 'Không tạo được mặt nan.' unless face
          face.reverse! if face.normal.dot(displacement)<0
          face.pushpull(@wine_depth.mm)
          raise 'Nan chưa kín; đã hủy.' unless g.manifold?
          g.set_attribute('TRẦN TUẤN NỘI THẤT','do_day_mm',@wine_t)
        end
        parent.transformation=@edit.inverse
        @model.commit_operation
        @model.selection.clear;@model.selection.add(parent)
        @wine_polys=[]
        true
      rescue StandardError=>e
        @model.abort_operation;UI.messagebox(e.message);false
      end
      def status_text
        "VẼ Ô RƯỢU #{@wine_kind} · P1 → P2 → click tạo · Giữ SHIFT khóa hướng · TAB cài đặt · CTRL đảo sâu · #{@wine_note}"
      end
    end
  end
end
