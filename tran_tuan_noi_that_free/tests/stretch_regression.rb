require 'sketchup'
ROOT=ENV.fetch('TT_STRETCH_ROOT', File.expand_path('../files/tran_tuan_noi_that',__dir__))
def load_tool
 %w[stretch_mode_tool stretch_detail_fix stretch_auto_scan_fix stretch_auto_scope_fix].each{|f|load(File.join(ROOT,f+'.rb'))}
end
load_tool
$count=0
def assert(v,message='assertion failed');raise message unless v;$count+=1;end
def close(a,b);assert((a-b).abs<1e-7,"#{a} != #{b}");end
def box(x=100,y=60,z=20)
 ps=8.times.map{|i|Sketchup::Vertex.new(Geom::Point3d.new((i&1)==0 ? 0 : x.mm,(i&2)==0 ? 0 : y.mm,(i&4)==0 ? 0 : z.mm))}
 es=Sketchup::Entities.new
 [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]].each{|a,b|es << Sketchup::Edge.new(ps[a],ps[b])}
 Sketchup::Group.new(Sketchup::Definition.new(es))
end
def setup(items)
 Sketchup.model=TestModel.new(items)
 Sketchup.model.selection=items
 TranTuanNoiThat::StretchMode::Tool.new
end
def region(t,axis,sign,cut,delta)
 {axis:axis,side_sign:sign,cut_coord:cut.mm,ref_coord:0,delta:delta.mm,scope:t.instance_variable_get(:@scope)}
end
# Six directions, fixed boundary on the exact end face, preserving other dimensions.
3.times do |axis|
 [-1,1].each do |sign|
  g=box;tool=setup([g]);size=[100,60,20][axis]
  tool.send(:commit_regions,[region(tool,axis,sign,sign>0 ? 0 : size,sign*10)])
  close(g.bounds.min.to_a[axis],sign>0 ? 0 : -10.mm)
  close(g.bounds.max.to_a[axis],sign>0 ? (size+10).mm : size.mm)
  close(g.transformation.m[axis][3],0)
  assert(Sketchup.model.commits==1)
 end
end
# True selected-side movement through nested, rotated/scaled containers.
g=box;tr=Geom::Transformation.new([[0,-2,0,30.mm],[1,0,0,40.mm],[0,0,1,0],[0,0,0,1]])
parent=Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new([g])),tr)
t=setup([parent]);t.send(:commit_regions,[region(t,1,1,40,20)])
close(parent.bounds.min.y,40.mm);close(parent.bounds.max.y,160.mm);close(g.definition.bounds.max.x,120.mm)
# Shared components: change only selected occurrence, both root and nested definitions unique.
a=box;b=Sketchup::Group.new(a.definition);t=setup([a]);t.send(:commit_regions,[region(t,0,1,0,10)])
close(a.bounds.max.x,110.mm);close(b.bounds.max.x,100.mm);assert(a.definition != b.definition)
# Locked child is untouched.
a=box;b=box;b.locked=true;parent=Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new([a,b])))
t=setup([parent]);t.send(:commit_regions,[region(t,0,1,0,10)]);close(a.bounds.max.x,110.mm);close(b.bounds.max.x,100.mm)
# Fold-over rejected and entire multi-direction operation rolls back.
g=box;t=setup([g]);begin;t.send(:commit_regions,[region(t,0,1,0,10),region(t,1,1,0,-100)]);raise 'expected rejection';rescue RuntimeError=>e;assert(e.message.include?('Khoảng co'));end
close(g.bounds.max.x,100.mm);close(g.bounds.max.y,60.mm);assert(Sketchup.model.aborts==1)
# Don't swallow failures of make_unique.
a=box;b=Sketchup::Group.new(a.definition);def a.make_unique;raise 'unique failed';end
t=setup([a]);begin;t.send(:commit_regions,[region(t,0,1,0,10)]);raise 'expected';rescue RuntimeError=>e;assert(e.message=='unique failed');end
close(b.bounds.max.x,100.mm)
# Bare numbers are mm even if the model is using inches; explicit units still parse.
t=setup([box]);close(t.send(:parse_input_length,'200'),200.mm);close(t.send(:parse_input_length,'-12,5'),-12.5.mm);close(t.send(:parse_input_length,'2cm'),20.mm)
# Click-click-click input, measurements enabled, = uses outer bound not P2.
g=box;t=setup([g]);v=Sketchup.model.active_view
v.point=Geom::Point3d.new(0,0,0);t.onLButtonDown(0,0,0,v);t.onLButtonUp(0,0,0,v)
assert(t.instance_variable_get(:@state)==:p2)
v.point=Geom::Point3d.new(50.mm,0,0);t.onLButtonDown(0,20,0,v);assert(t.enableVCB?)
t.onUserText('=150',v);close(g.bounds.max.x,150.mm);close(g.bounds.min.x,0)
# P3 recomputes the final click instead of reusing the last mouse move.
g=box;t=setup([g]);v=Sketchup.model.active_view
v.point=Geom::Point3d.new(0,0,0);t.onLButtonDown(0,0,0,v);t.onLButtonUp(0,0,0,v)
v.point=Geom::Point3d.new(100.mm,0,0);t.onLButtonDown(0,20,0,v)
t.instance_variable_set(:@delta,5.mm);v.point=Geom::Point3d.new(125.mm,0,0);t.onLButtonDown(0,30,0,v);close(g.bounds.max.x,125.mm)
# Pick must be a root in the active editing context. Empty-space clicks never select all.
a=box;b=box;t=setup([a,b]);Sketchup.model.selection=[];v=Sketchup.model.active_view
v.pick_helper.target=nil;t.send(:prepare_auto_scope,v,0,0);assert(t.instance_variable_get(:@scope).empty?)
v.pick_helper.target=a;t.send(:prepare_auto_scope,v,0,0);assert(t.instance_variable_get(:@scope)==[a])
# Queuing then changing selection cannot redirect earlier directions to another object.
t.instance_variable_set(:@pending_regions,[region(t,0,1,0,10)]);Sketchup.model.selection=[b]
t.send(:reset_current_points);t.send(:prepare_auto_scope,v,0,0);assert(t.instance_variable_get(:@scope)==[a])
# World extents include edit transformation.
t=setup([box]);Sketchup.model.edit_transform=Geom::Transformation.translation(Geom::Vector3d.new(500.mm,0,0));t.send(:reset_current_points)
close(t.getExtents.min.x,500.mm);close(t.getExtents.max.x,600.mm)
# Explicit axis lock and toggle.
t.instance_variable_set(:@state,:p2);t.onKeyDown(90,0,0,Sketchup.model.active_view)
assert(t.send(:dominant_axis,Geom::Point3d.new,Geom::Point3d.new(100,2,3))==2)
t.onKeyDown(90,0,0,Sketchup.model.active_view);assert(t.instance_variable_get(:@forced_axis).nil?)
# Reload aliases must target fresh base methods, no recursion after repeated updates.
5.times do
 load_tool;t=setup([box]);t.activate;assert(t.instance_variable_get(:@input_mode)==:auto_scan)
 assert(t.respond_to?(:onLButtonDown));assert(!t.enableVCB?)
end
# Drag-release accepts a clear P2; ESC clears all gesture state before retry.
g=box;t=setup([g]);v=Sketchup.model.active_view
v.point=Geom::Point3d.new(0,0,0);t.onLButtonDown(0,0,0,v)
v.point=Geom::Point3d.new(100.mm,0,0);t.onLButtonUp(0,25,0,v)
assert(t.instance_variable_get(:@state)==:p3)
t.onCancel(0,v);assert(t.instance_variable_get(:@state)==:p1);assert(!t.instance_variable_get(:@auto_dragging))
# A cut outside the selected volume must not turn stretching into whole-object movement.
v.point=Geom::Point3d.new(-20.mm,0,0);t.onLButtonDown(0,0,0,v);t.onLButtonUp(0,0,0,v)
v.point=Geom::Point3d.new(100.mm,0,0);assert(!t.send(:finalize_p2,v,20,0));assert(Sketchup.model.commits==0)
# Mirrored and non-uniformly scaled panels use inverse transforms for vertex displacement.
g=box;g.transformation=Geom::Transformation.scale(-2,3,1);t=setup([g]);t.send(:commit_regions,[region(t,0,-1,0,-20)])
close(g.bounds.min.x,-220.mm);close(g.bounds.max.x,0);close(g.bounds.max.y,180.mm)
# Reject editing shared active ancestors before starting the operation.
g=box;t=setup([g]);ancestor=box;copy=Sketchup::Group.new(ancestor.definition);Sketchup.model.active_path=[ancestor]
begin;t.send(:commit_regions,[region(t,0,1,0,10)]);raise 'expected';rescue RuntimeError=>e;assert(e.message.include?('Component dùng chung'));end
close(g.bounds.max.x,100.mm);assert(Sketchup.model.commits==0)
puts "PASS #{$count} regression assertions (SketchUp API doubles; no native geometry kernel)."
