# TT - TẠO BOX
require 'sketchup.rb'
module TranTuanDC
  module TaoBox
    class Tool
      def activate; @ip=Sketchup::InputPoint.new; @w=600.0; @d=400.0; @h=300.0; @preview=false; @origin=nil; @mode=:solid; Sketchup.status_text='TT - Tạo Box: Preview 3D | Click để đặt | TAB: Khối Box / Khung không mặt | ESC: hủy.'; end
      def deactivate(view); @ip=nil; view.invalidate if view; end
      def onMouseMove(flags,x,y,view); @ip.pick(view,x,y); if @ip.valid?; @origin=@ip.position; @preview=true; view.invalidate; end; end
      def draw(view); return unless @preview&&@origin; pts=box_points(@origin,@w,@d,@h); edges=[[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]; if @mode==:solid; faces=[[pts[0],pts[3],pts[2],pts[1]],[pts[4],pts[5],pts[6],pts[7]],[pts[0],pts[1],pts[5],pts[4]],[pts[3],pts[7],pts[6],pts[2]],[pts[0],pts[4],pts[7],pts[3]],[pts[1],pts[2],pts[6],pts[5]]]; view.drawing_color=Sketchup::Color.new(255,145,25,90); faces.each{|f|view.draw(GL_QUADS,f)}; view.drawing_color=Sketchup::Color.new(255,95,0,255); view.line_width=3; else; view.drawing_color=Sketchup::Color.new(255,120,0,255); view.line_width=5; end; edges.each{|a,b|view.draw(GL_LINES,pts[a],pts[b])}; end
      def onKeyDown(key,repeat,flags,view); if key==9; @mode=@mode==:solid ? :frame : :solid; Sketchup.status_text="TT - Tạo Box: #{@mode==:solid ? 'KHỐI BOX (có mặt)' : 'KHUNG (không mặt Face)'} | Click để tạo | TAB đổi chế độ"; view.invalidate; elsif key==27; Sketchup.active_model.select_tool(nil); end; end
      def onLButtonDown(flags,x,y,view); @ip.pick(view,x,y); return unless @ip.valid?; @origin=@ip.position; input=UI.inputbox(['Chiều rộng (mm)','Chiều sâu (mm)','Chiều cao (mm)'],[@w,@d,@h],'TT - Tạo khối Box'); return unless input; vals=input.map{|v|v.to_f}; return UI.messagebox('Kích thước phải lớn hơn 0 mm.') if vals.any?{|v|v<=0}; @w,@d,@h=vals; create_box(@origin,@w,@d,@h); view.invalidate; end
      private
      def box_points(o,w,d,h); x=Geom::Vector3d.new(w.mm,0,0); y=Geom::Vector3d.new(0,d.mm,0); z=Geom::Vector3d.new(0,0,h.mm); [o,o+x,o+x+y,o+y,o+z,o+x+z,o+x+y+z,o+y+z]; end
      def create_box(o,w,d,h); model=Sketchup.active_model; model.start_operation(@mode==:solid ? 'TT - Tạo Box':'TT - Tạo Khung Box',true); g=model.active_entities.add_group; e=g.entities; p=box_points(o,w,d,h); if @mode==:solid; e.add_face(p[0],p[3],p[2],p[1]); e.add_face(p[4],p[5],p[6],p[7]); e.add_face(p[0],p[1],p[5],p[4]); e.add_face(p[3],p[7],p[6],p[2]); e.add_face(p[0],p[4],p[7],p[3]); e.add_face(p[1],p[2],p[6],p[5]); g.name="TT_BOX_#{w.to_i}x#{d.to_i}x#{h.to_i}"; else; [[p[0],p[1]],[p[1],p[2]],[p[2],p[3]],[p[3],p[0]],[p[4],p[5]],[p[5],p[6]],[p[6],p[7]],[p[7],p[4]],[p[0],p[4]],[p[1],p[5]],[p[2],p[6]],[p[3],p[7]]].each{|a,b|e.add_line(a,b)}; g.name="TT_KHUNG_BOX_#{w.to_i}x#{d.to_i}x#{h.to_i}"; end; model.commit_operation; g; rescue=>e; model.abort_operation; UI.messagebox("Không thể tạo Box/Khung:\n#{e.message}"); nil end
    end
    def self.start; Sketchup.active_model.select_tool(Tool.new); end
  end
end
