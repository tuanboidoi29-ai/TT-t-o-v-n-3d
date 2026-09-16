ENV['TT_STRETCH_ROOT']=File.expand_path('../files/tran_tuan_noi_that',__dir__) unless ENV['TT_STRETCH_ROOT']
require_relative 'stretch_regression'
load(File.join(ROOT,'stretch_window_tool.rb'))
def win(items,rect)
 Sketchup.model=TestModel.new(items);Sketchup.model.selection=items
 t=TranTuanNoiThat::StretchMode::WindowTool.new
 t.send(:scan_window,Sketchup.model.active_view,rect)
 t
end
def apply(t,axis,mm)
 t.instance_variable_set(:@axis,axis);t.instance_variable_set(:@delta,mm.mm);t.send(:apply_window)
end
# Rectangle on right end: four selected corners, all left corners fixed, one Undo.
g=box;t=win([g],[90,110,-1,70]);assert(t.instance_variable_get(:@selected_points).length==4)
apply(t,0,20);close(g.bounds.max.x,120.mm);close(g.bounds.min.x,0);close(g.bounds.max.y,60.mm);assert(Sketchup.model.commits==1)
# Partial height: only the two projected top-right corners move (front and back).
g=box;t=win([g],[90,110,50,70]);assert(t.instance_variable_get(:@selected_points).length==2)
apply(t,0,15)
vs=g.definition.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
vs.each{|v|close(v.position.x,(v.position.y>50.mm && v.position.x>90.mm) ? 115.mm : (v.position.x>90.mm ? 100.mm : 0))}
# Outside rectangle stays fixed even though it lies on the same positive halfspace.
g=box;t=win([g],[-1,1,50,70]);apply(t,0,10)
close(g.bounds.max.x,100.mm);assert(g.definition.entities.flat_map(&:vertices).uniq.count{|v|(v.position.x-10.mm).abs<1e-8}==2)
# Selection is frozen after camera/view changes; only original selected positions move.
g=box;t=win([g],[90,110,-1,70]);view=Sketchup.model.active_view;def view.screen_coords(p);Geom::Point3d.new(-100,-100,0);end
apply(t,0,20);close(g.bounds.max.x,120.mm)
# Shared root and nested instances do not deform their external copies.
child=box;parent=Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new([child])))
copy=Sketchup::Group.new(parent.definition);t=win([parent],[90,110,-1,70]);apply(t,0,20)
close(parent.bounds.max.x,120.mm);close(copy.bounds.max.x,100.mm)
# Two shared siblings with different transforms: move only screen-selected occurrence.
a=box;b=Sketchup::Group.new(a.definition,Geom::Transformation.translation(Geom::Vector3d.new(200.mm,0,0)))
parent=Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new([a,b])))
t=win([parent],[90,110,-1,70]);apply(t,0,10);close(a.bounds.max.x,110.mm);close(b.bounds.max.x,300.mm)
# Non-uniform scale and mirror convert world axis displacement correctly.
g=box;g.transformation=Geom::Transformation.scale(-2,3,1);t=win([g],[-210,-190,-1,190]);apply(t,0,-20)
close(g.bounds.min.x,-220.mm);close(g.bounds.max.x,0)
# Locked selected root must not fall through to all active objects.
g=box;other=box;g.locked=true;t=win([g],[-1,110,-1,70]);Sketchup.model.active_entities << other
t.send(:scan_window,Sketchup.model.active_view,[-1,110,-1,70]);assert(t.instance_variable_get(:@nodes).empty?)
# Fold-over refused before modifying anything.
g=box;t=win([g],[90,110,-1,70]);begin;apply(t,0,-150);raise 'expected';rescue RuntimeError=>e;assert(e.message.include?('Khoảng kéo'));end
close(g.bounds.max.x,100.mm);assert(Sketchup.model.commits==0)
# Deliberate mutation after scanning requires a rescan, not stale vertex selection.
g=box;t=win([g],[90,110,-1,70]);g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(2,0,0)))
begin;apply(t,0,10);raise 'expected';rescue RuntimeError=>e;assert(e.message.include?('đổi vị trí'));end
# Escape before confirmation never mutates geometry.
g=box;t=win([g],[90,110,-1,70]);t.instance_variable_set(:@state,:anchor);t.onCancel(0,Sketchup.model.active_view)
assert(t.instance_variable_get(:@nodes).empty?);close(g.bounds.max.x,100.mm);assert(Sketchup.model.commits==0)
# Full UI gesture: drag rectangle, anchor, lock X and enter mm.
g=box;t=win([g],[-5,-1,-5,-1]);v=Sketchup.model.active_view
t.onLButtonDown(0,90,-1,v);t.onLButtonUp(0,110,70,v);assert(t.instance_variable_get(:@state)==:anchor)
v.point=Geom::Point3d.new(100.mm,60.mm,0);t.onLButtonDown(0,100,60,v);assert(t.enableVCB?)
t.onKeyDown(88,0,0,v);t.onUserText('25',v);close(g.bounds.max.x,125.mm)
# Multiple reloads don't recurse or change old tools.
3.times do
 load_tool;load(File.join(ROOT,'stretch_window_tool.rb'));t=win([box],[90,110,-1,70]);assert(t.instance_variable_get(:@selected_points).size==4)
end
puts "PASS #{$count} total assertions, including window selection and legacy stretch (API doubles only)."
