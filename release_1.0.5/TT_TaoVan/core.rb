# ============================================================
# TT - TẠO VÁN FACE 3D - TRẦN TUẤN
# ============================================================
module TranTuanDC
  module TaoVanFace3D
    def self.reload!; true end unless respond_to?(:reload!)
    @active=false
    PREVIEW_FRONT=Sketchup::Color.new(255,120,0,110)
    PREVIEW_BACK=Sketchup::Color.new(255,145,0,145)
    PREVIEW_LINE=Sketchup::Color.new(255,55,0)
    class FaceTool
      def initialize; @ip=Sketchup::InputPoint.new; @face=nil; @points=[]; @normal=nil; @thickness=17.mm; @direction=1; @state=:hover; end
      def activate; Sketchup.set_status_text('DI CHUỘT LÊN FACE | PREVIEW 3D | CLICK 1: NHẬP ĐỘ DÀY'); end
      def onMouseMove(flags,x,y,view); @ip.pick(view,x,y); f=@ip.face; if f && f.valid?; @face=f; @points=f.outer_loop.vertices.map{|v|v.position}; @normal=f.normal; else @face=nil if @state==:hover; end; view.invalidate; end
      def onKeyDown(key,repeat,flags,view); return unless key==9; @direction*=-1; view.invalidate; end
      def draw(view); return unless @face && @face.valid? && @points.length>=3; off=@normal.clone; off.length=@thickness; off.reverse! if @direction<0; back=@points.map{|p|p+off}; view.drawing_color=PREVIEW_FRONT; view.draw(GL_POLYGON,@points); view.drawing_color=PREVIEW_BACK; view.draw(GL_POLYGON,back); view.line_width=4; view.drawing_color=PREVIEW_LINE; view.draw(GL_LINE_LOOP,@points); view.draw(GL_LINE_LOOP,back); @ip.draw(view) if @ip.valid?; end
      def onLButtonDown(flags,x,y,view); return unless @face && @face.valid?; if @state==:hover; r=UI.inputbox(['Độ dày ván (mm):'],[@thickness.to_f.to_mm.round(2)],'TT - TẠO VÁN'); return unless r; v=r[0].to_f; return UI.messagebox('Độ dày phải lớn hơn 0 mm.') if v<=0; @thickness=v.mm; @state=:confirm; else create_board; end; view.invalidate; end
      def create_board; model=Sketchup.active_model; face=@face; parent=face.parent; ents=parent.respond_to?(:entities) ? parent.entities : model.active_entities; model.start_operation('TT - Tạo ván Face 3D',true); begin; g=ents.add_group; g.name="TT_VAN_#{@thickness.to_f.to_mm.round(2)}mm"; pts=face.outer_loop.vertices.map{|v|v.position}; f=g.entities.add_face(pts); f.reverse! if f.normal.dot(face.normal)<0; f.pushpull(@thickness.to_f*@direction); g.set_attribute('TranTuanDC','type','VAN'); g.set_attribute('TranTuanDC','thickness_mm',@thickness.to_f.to_mm); face.erase! if face.valid?; model.selection.clear; model.selection.add(g); model.commit_operation; @state=:hover; rescue=>e; model.abort_operation; UI.messagebox("LỖI TẠO VÁN:\n#{e.message}"); end; end
    end
    def self.set_active(v); @active=!!v; end
    def self.active?; !!@active; end
    def self.start; set_active(true); Sketchup.active_model.select_tool(FaceTool.new); end
  end
end
