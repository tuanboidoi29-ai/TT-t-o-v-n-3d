# Run with the geometry doubles from the preceding upgrade regression.
load File.join(__dir__, 'upgrade_146_test.rb')
load ROOT+'/slat_wall_tool.rb'
SW=TranTuanNoiThat::SlatWall
GL_TRIANGLES=4 unless defined?(GL_TRIANGLES)
GL_LINE_LOOP=2 unless defined?(GL_LINE_LOOP)
check('single mode; no backing; picked height controls every slat') do
 p=SW.layout(1000,2200,SW::DEFAULTS)
 assert(p[:panels].size==1)
 assert(p[:panels][0][:backing].nil?)
 assert(p[:panels][0][:slats].all?{|s|s[4]==2200 && s[2]==0})
end
check('split both stock axes with complete equal coverage') do
 p=SW.layout(3000,5000,SW::DEFAULTS.merge('mode'=>'backed'))
 assert(p[:columns]==3 && p[:rows]==3)
 near(p[:panels].sum{|v|v[:width]*v[:height]},15_000_000)
 assert(p[:panels].all?{|v|v[:width]<=1220 && v[:height]<=2440 && v[:backing]})
 assert(p[:panels].map{|v|[v[:x],v[:y]]}.uniq.size==9)
end
check('long narrow region splits even below stock area') do
 assert(SW.layout(300,3000,SW::DEFAULTS)[:rows]==2)
end
check('manual spacing exact; remainder centered with edge allowances') do
 p=SW.layout(1000,1000,SW::DEFAULTS.merge('spacing_mode'=>'manual','gap'=>30,'left'=>10,'right'=>20,'top'=>12,'bottom'=>18))
 ss=p[:panels][0][:slats]
 ss.each_cons(2){|a,b|near(b[0]-a[0]-a[3],30)}
 near(ss.first[0]-10,1000-20-ss.last[0]-ss.last[3])
 near(ss.first[1],18);near(ss.first[4],970)
end
check('auto gaps evenly fill usable width') do
 p=SW.layout(987,1000,SW::DEFAULTS.merge('left'=>13,'right'=>19))
 ss=p[:panels][0][:slats]
 near(ss.first[0],13);near(ss.last[0]+ss.last[3],968)
 ss.each_cons(2){|a,b|near(b[0]-a[0]-a[3],p[:gap])}
end
check('horizontal orientation fills height and keeps full usable length') do
 p=SW.layout(900,700,SW::DEFAULTS.merge('orientation'=>'horizontal','left'=>10,'right'=>20,'top'=>30,'bottom'=>40))
 ss=p[:panels][0][:slats]
 assert(p[:orientation]=='horizontal')
 assert(ss.all?{|s|s[0]==10 && s[3]==870 && s[4]==40})
 near(ss.first[1],40)
 near(ss.last[1]+ss.last[4],670)
end
check('AUTO polygon layout fills a circular grouped-face shape') do
 circle=32.times.map do |i|
  a=2.0*Math::PI*i/32.0
  [500.0+500.0*Math.cos(a),500.0+500.0*Math.sin(a)]
 end
 %w[vertical horizontal diag_right diag_left].each do |orientation|
  p=SW.layout_polygon(circle,SW::DEFAULTS.merge('orientation'=>orientation,'width'=>40,'gap'=>40))
  assert(p[:source_shape]=='face')
  assert(p[:options]['mode']=='single')
  assert(p[:slat_count]>0)
  p[:panels].first[:slat_polygons].each do |poly|
   assert(poly.length>=3)
   poly.each do |x,y|
    r=Math.sqrt((x-500.0)**2+(y-500.0)**2)
    assert(r<=500.1)
   end
  end
 end
end
check('AUTO polygon layout rejects concave source face instead of creating wrong slats') do
 concave=[[0,0],[800,0],[800,600],[400,300],[0,600]]
 begin
  SW.layout_polygon(concave,SW::DEFAULTS)
  raise 'accepted concave face'
 rescue RuntimeError=>e
  assert(e.message.include?('lõm'))
 end
end
check('count mode uses exact requested quantity and equal computed gaps') do
 p=SW.layout(1000,1000,SW::DEFAULTS.merge('spacing_mode'=>'count','count'=>8,'width'=>50,'left'=>20,'right'=>20))
 ss=p[:panels][0][:slats]
 assert(ss.length==8 && p[:count_per_panel]==8)
 near(ss.first[0],20);near(ss.last[0]+ss.last[3],980)
 ss.each_cons(2){|a,b|near(b[0]-a[0]-a[3],p[:gap])}
end
check('invalid orientation and impossible count are rejected') do
 assert(SW.validate(SW::DEFAULTS.merge('orientation'=>'diag_right'))['orientation']=='diag_right')
 assert(SW.validate(SW::DEFAULTS.merge('orientation'=>'diag_left'))['orientation']=='diag_left')
 begin;SW.validate(SW::DEFAULTS.merge('orientation'=>'diagonal'));raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('Hướng lam'));end
 begin;SW.layout(200,500,SW::DEFAULTS.merge('spacing_mode'=>'count','count'=>10,'width'=>40));raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('Số lượng'));end
end
check('ABF backing uses front z=0 and thickness goes to -17.5') do
 [0,3,5].each do |depth|
  p=SW.layout(1000,1000,SW::DEFAULTS.merge('mode'=>'backed','recess'=>depth))
  near(p[:panels][0][:slats][0][2],-depth)
  near(p[:panels][0][:backing][2],-17.5)
  near(p[:panels][0][:backing][5],17.5)
  near(p[:panels][0][:backing][2]+p[:panels][0][:backing][5],0)
 end
end
check('CNC custom tag normalized; invalid recess and oversize rejected') do
 assert(SW.validate(SW::DEFAULTS.merge('tag'=>'TEST'))['tag']=='ABF_TEST')
 begin;SW.validate(SW::DEFAULTS.merge('mode'=>'backed','recess'=>17.5));raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('Hạ âm'));end
 begin;SW.layout(100_000,100_000,SW::DEFAULTS);raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('200'));end
end
# Geometry recording doubles: exercise the production builder, not a copy of it.
module Attrs
 def get_attribute(d,k,default=nil);(@attrs||={}).fetch([d,k],default);end
 def set_attribute(d,k,v);(@attrs||={})[[d,k]]=v;end
end
class Geom::Vector3d
 def dot(v);x*v.x+y*v.y+z*v.z;end unless method_defined?(:dot)
end
class Sketchup::Face
 include Attrs
 attr_accessor :layer,:material,:back_material,:mock_edges
 def edges;@mock_edges || [];end
 def bounds
  b=Geom::BoundingBox.new
  vertices.each{|v|b.add(v.position)}
  b
 end
 def normal
  a=vertices[0].position
  (1...(vertices.length-1)).each do |i|
   n=a.vector_to(vertices[i].position).cross(a.vector_to(vertices[i+1].position))
   return n.normalize if n.length>1.0e-9
  end
  Geom::Vector3d.new(0,0,0)
 end
 def reverse!
  vertices.reverse!
  self
 end
end
class Sketchup::Edge
 include Attrs
 attr_accessor :layer
end
class Sketchup::Group
 include Attrs
 attr_accessor :name,:material,:layer
 def entities;definition.entities;end
end
class Sketchup::Entities
 def add_group
  g=Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new));g.name='';self<<g;g
 end
 def add_face(points)
  vertices=points.map{|p|Sketchup::Vertex.new(p)}
  edges=vertices.each_with_index.map do |v,i|
   Sketchup::Edge.new(v,vertices[(i+1)%vertices.length])
  end
  f=Sketchup::Face.new(vertices)
  f.mock_edges=edges
  edges.each{|e|self<<e}
  self<<f
  f
 end
 def add_edges(*points)
  points.each_cons(2).map do |a,b|
   edge=Sketchup::Edge.new(Sketchup::Vertex.new(a),Sketchup::Vertex.new(b));self<<edge;edge
  end
 end
end
class Catalog < Hash
 def [](key);self[0] = Struct.new(:name,:color).new('Layer0',nil) if key==0 && !key?(0);super;end
 def add(name);self[name]=Struct.new(:name,:color).new(name,nil);end
end
class TestModel
 include Attrs
 attr_reader :materials,:layers
 def materials;@materials||=Catalog.new;end
 def layers;@layers||=Catalog.new;end
 def definitions;entities.map(&:definition);end
end
set_model
check('real builder: every slat becomes ABF Intersect for Aspire') do
 p=SW.layout(1400,1000,SW::DEFAULTS.merge('mode'=>'backed','cnc'=>true,'tag'=>'ABF_TEST','recess'=>3))
 parent=SW.create(Sketchup.model,p,Geom::Transformation.new)
 assert(parent.entities.map(&:name)==['VL1','VL2'])
 parent.entities.each_with_index do |vl,i|
  backing=vl.entities.first
  assert(backing.name.end_with?('TAM_LOT'))
  assert(backing.layer.name=='Layer0')
  assert(backing.get_attribute('ABF','is-board')==true)
  count=p[:panels][i][:slats].size
  summary=SW.backing_profile_summary(backing)
  assert(summary[:cutting_group_count]==0)
  assert(summary[:intersect_group_count]==count)
  assert(summary[:unknown_nested_count]==0)
  assert(summary[:direct_edge_count]==0)
  assert(summary[:profile_count]==count)
  assert(summary[:edge_count]==count*4)
  assert(summary[:complete])
  assert(summary[:face_count]==6)
  intersects=backing.entities.grep(Sketchup::Group).select{|g|SW.abf_intersect_group?(g)}
  assert(intersects.size==count)
  assert(intersects.all?{|g|g.name=='_ABF_Intersect'})
  assert(intersects.all?{|g|g.layer.name=='ABF_TEST'})
  assert(intersects.all?{|g|g.get_attribute('ABF','is-intersect')==true})
  assert(intersects.all?{|g|g.get_attribute('ABF','intersect-offset')==0.0})
  assert(intersects.all?{|g|g.entities.grep(Sketchup::Face).size==1})
  assert(intersects.all?{|g|g.entities.grep(Sketchup::Edge).size==4})
  assert(intersects.all?{|g|g.entities.grep(Sketchup::Edge).all?{|e|near(e.start.position.z,0);near(e.end.position.z,0);true}})
  cnc_face=SW.backing_front_face(backing)
  assert(cnc_face.get_attribute('ABF','is-cnced-face')==true)
  assert(backing.get_attribute(SW::KEY,'profile_type')=='ABF_Intersect')
  assert(backing.get_attribute(SW::KEY,'profiles_on_face')==true)
  near(backing.definition.bounds.min.z,-17.5.mm)
  near(backing.definition.bounds.max.z,0)
 end
 assert(Sketchup.model.commits==1)
end
set_model
check('diagonal slats stay inside backing and create one ABF Intersect each') do
 p=SW.layout(900,700,SW::DEFAULTS.merge('mode'=>'backed','orientation'=>'diag_right','cnc'=>true,'tag'=>'ABF_TEST','recess'=>3))
 parent=SW.create(Sketchup.model,p,Geom::Transformation.new)
 vl=parent.entities.first
 backing=vl.entities.first
 count=p[:panels].first[:slats].length
 slats=vl.entities.grep(Sketchup::Group).select{|g|g.get_attribute(SW::KEY,'role')=='slat'}
 assert(slats.length==count)
 summary=SW.backing_profile_summary(backing)
 assert(summary[:intersect_group_count]==count)
 assert(summary[:profile_count]==count)
 assert(summary[:complete])
 intersects=backing.entities.grep(Sketchup::Group).select{|g|SW.abf_intersect_group?(g)}
 assert(intersects.all?{|g|g.entities.grep(Sketchup::Face).size==1 && g.entities.grep(Sketchup::Edge).size==4})
end
set_model
check('backed mode keeps ABF Intersect profiles even when depth is zero') do
 p=SW.layout(500,700,SW::DEFAULTS.merge('mode'=>'backed','cnc'=>false))
 count=p[:panels][0][:slats].size
 parent=SW.create(Sketchup.model,p,Geom::Transformation.new)
 backing=parent.entities.first.entities.first
 intersects=backing.entities.grep(Sketchup::Group).select{|g|SW.abf_intersect_group?(g)}
 assert(intersects.size==count)
 assert(intersects.all?{|g|g.entities.grep(Sketchup::Face).size==1})
 assert(intersects.all?{|g|g.entities.grep(Sketchup::Edge).size==4})
 assert(intersects.all?{|g|g.get_attribute(SW::KEY,'depth_mm')==0.0})
 assert(SW.backing_front_face(backing).get_attribute('ABF','is-cnced-face')==true)
end
set_model
check('backing integrity rejects _ABF_cuttingLines as slat machining and unknown nested objects') do
 backing=SW.make_box(Sketchup.model.entities,[0,0,-17.5,600,1200,17.5],'VLX_TAM_LOT',nil)
 cutting=SW.ensure_abf_cutting_group(backing)
 begin
  SW.enforce_backing_integrity(backing,0)
  raise 'accepted cutting lines as slat machining'
 rescue RuntimeError=>e
  assert(e.message.include?('_ABF_cuttingLines'))
 end
 backing.entities.delete(cutting)
 nested=backing.entities.add_group
 nested.name='BAD'
 begin
  SW.enforce_backing_integrity(backing,0)
  raise 'accepted unknown group'
 rescue RuntimeError=>e
  assert(e.message.include?('không thuộc chuẩn ABF'))
 end
end
set_model
check('creation inside scaled context matches world preview') do
 tr=Geom::Transformation.scale(2,3,4);Sketchup.model.edit_transform=tr
 p=SW.layout(500,700,SW::DEFAULTS)
 world=Geom::Transformation.translation(Geom::Vector3d.new(10,20,30))
 parent=SW.create(Sketchup.model,p,world)
 actual=Sketchup.model.edit_transform*parent.transformation
 actual.m.flatten.zip(world.m.flatten).each{|a,b|near(a,b)}
end
class Sketchup::InputPoint
 def clear;@point=nil;end
end
class Sketchup::Selection < Array
 def add(x);self<<x;end
end
class Geom::Transformation
 def xaxis;Geom::Vector3d.new(m[0][0],m[1][0],m[2][0]);end
 def yaxis;Geom::Vector3d.new(m[0][1],m[1][1],m[2][1]);end
 def zaxis;Geom::Vector3d.new(m[0][2],m[1][2],m[2][2]);end
end
class Geom::Vector3d
 def dot(v);x*v.x+y*v.y+z*v.z;end unless method_defined?(:dot)
end
module Geom
 def self.intersect_line_plane(line,plane)
  p,d=line;q,n=plane
  den=d.x*n.x+d.y*n.y+d.z*n.z
  return nil if den.abs<1.0e-9
  t=((q.x-p.x)*n.x+(q.y-p.y)*n.y+(q.z-p.z)*n.z)/den
  Point3d.new(p.x+d.x*t,p.y+d.y*t,p.z+d.z*t)
 end
end
check('free-space first point uses current camera target plane, not model origin') do
 tool=SW::Tool.new(SW::DEFAULTS)
 view=TestView.new
 view.point=nil
 camera=Struct.new(:eye,:target,:direction,:up).new(
  Geom::Point3d.new(0,0,-1000.mm),
  Geom::Point3d.new(500.mm,600.mm,350.mm),
  Geom::Vector3d.new(0,0,1),
  Geom::Vector3d.new(0,1,0)
 )
 view.define_singleton_method(:camera){camera}
 view.define_singleton_method(:pickray){|x,y|[Geom::Point3d.new(x.mm,y.mm,-1000.mm),Geom::Vector3d.new(0,0,1)]}
 p=tool.send(:pick,view,120,240)
 assert(p)
 near(p.x,120.mm);near(p.y,240.mm);near(p.z,350.mm)
end
check('free wall basis follows P1-P2 XY direction instead of locking to camera') do
 tool=SW::Tool.new(SW::DEFAULTS)
 view=TestView.new
 p1=Geom::Point3d.new(0,0,0)
 b1=tool.send(:free_basis_from,p1,Geom::Point3d.new(100.mm,100.mm,500.mm),view)
 b2=tool.send(:free_basis_from,p1,Geom::Point3d.new(-100.mm,100.mm,500.mm),view)
 assert(b1 && b2)
 u1=b1.xaxis;u2=b2.xaxis
 near(u1.x.abs,u1.y.abs);near(u2.x.abs,u2.y.abs)
 assert(u1.x>0 && u1.y>0)
 assert(u2.x<0 && u2.y>0)
 assert((u1.x-u2.x).abs>0.001)
end
check('AUTO recognizes Face only when it belongs to Group or Component definition') do
 tool=SW::Tool.new(SW::DEFAULTS)
 vs=[
  Sketchup::Vertex.new(Geom::Point3d.new(0,0,0)),
  Sketchup::Vertex.new(Geom::Point3d.new(100.mm,0,0)),
  Sketchup::Vertex.new(Geom::Point3d.new(100.mm,100.mm,0)),
  Sketchup::Vertex.new(Geom::Point3d.new(0,100.mm,0))
 ]
 face=Sketchup::Face.new(vs)
 raw_owner=Object.new
 raw_parent=Struct.new(:parent).new(raw_owner)
 face.define_singleton_method(:parent){raw_parent}
 assert(!tool.send(:grouped_component_face?,face))

 definition=Sketchup::Definition.new(Sketchup::Entities.new)
 grouped_parent=Struct.new(:parent).new(definition)
 face.define_singleton_method(:parent){grouped_parent}
 assert(tool.send(:grouped_component_face?,face))

 view=TestView.new
 camera=Struct.new(:direction).new(Geom::Vector3d.new(0,0,-1))
 view.define_singleton_method(:camera){camera}
 polygon,tr,boundary=tool.send(:face_auto_geometry,face,Geom::Transformation.new,view)
 assert(polygon.length==4)
 assert(boundary.length==4)
 assert(tr)
end
check('P1 endpoint snap is limited to 24px and ignores Face-only inference') do
 tool=SW::Tool.new(SW::DEFAULTS)
 view=TestView.new
 pos=Geom::Point3d.new(100.mm,100.mm,0)
 vertex=Sketchup::Vertex.new(pos)
 ip=Object.new
 ip.define_singleton_method(:valid?){true}
 ip.define_singleton_method(:position){pos}
 ip.define_singleton_method(:vertex){vertex}
 ip.define_singleton_method(:edge){nil}
 ip.define_singleton_method(:face){nil}
 ip.define_singleton_method(:transformation){Geom::Transformation.new}
 snap=tool.send(:endpoint_snap_point,ip,view,110,110)
 assert(snap)
 near(snap.x,100.mm);near(snap.y,100.mm)
 assert(tool.send(:endpoint_snap_point,ip,view,140,140).nil?)

 face_ip=Object.new
 face_ip.define_singleton_method(:valid?){true}
 face_ip.define_singleton_method(:position){pos}
 face_ip.define_singleton_method(:vertex){nil}
 face_ip.define_singleton_method(:edge){nil}
 face_ip.define_singleton_method(:face){Object.new}
 assert(tool.send(:endpoint_snap_point,face_ip,view,100,100).nil?)
end
check('edge snap chooses the nearest real endpoint, never a sliding edge inference point') do
 tool=SW::Tool.new(SW::DEFAULTS)
 view=TestView.new
 a=Sketchup::Vertex.new(Geom::Point3d.new(100.mm,100.mm,0))
 b=Sketchup::Vertex.new(Geom::Point3d.new(200.mm,100.mm,0))
 edge=Sketchup::Edge.new(a,b)
 ip=Object.new
 ip.define_singleton_method(:valid?){true}
 ip.define_singleton_method(:position){Geom::Point3d.new(150.mm,100.mm,0)}
 ip.define_singleton_method(:vertex){nil}
 ip.define_singleton_method(:edge){edge}
 ip.define_singleton_method(:transformation){Geom::Transformation.new}
 snap=tool.send(:endpoint_snap_point,ip,view,102,100)
 assert(snap)
 near(snap.x,100.mm);near(snap.y,100.mm)
 assert(tool.send(:endpoint_snap_point,ip,view,150,100).nil?)
end
check('P1 stays fixed while arbitrary diagonal P2 auto-detects X or Y') do
 tool=SW::Tool.new(SW::DEFAULTS)
 origin=Geom::Point3d.new(125.mm,275.mm,40.mm)
 tool.send(:lock_first_point,origin)
 locked=tool.instance_variable_get(:@p1)
 near(locked.x,125.mm);near(locked.y,275.mm);near(locked.z,40.mm)

 cases=[
  [Geom::Point3d.new(1125.mm,325.mm,2040.mm),:x],
  [Geom::Point3d.new(-875.mm,225.mm,2040.mm),:x],
  [Geom::Point3d.new(175.mm,1275.mm,-960.mm),:y],
  [Geom::Point3d.new(75.mm,-725.mm,-960.mm),:y]
 ]
 cases.each do |p2,axis|
  assert(tool.send(:model_axis_for,p2)==axis)
  current=tool.instance_variable_get(:@p1)
  near(current.x,125.mm);near(current.y,275.mm);near(current.z,40.mm)
 end
 assert(tool.instance_variable_get(:@p1_locked)==true)
end
check('P2 construction plane follows detected Model axis through locked P1') do
 tool=SW::Tool.new(SW::DEFAULTS)
 p1=Geom::Point3d.new(100.mm,200.mm,300.mm)
 tool.send(:lock_first_point,p1)

 tool.instance_variable_set(:@free_axis,:x)
 plane=tool.send(:axis_construction_plane)
 near(plane[0].x,p1.x);near(plane[0].y,p1.y);near(plane[0].z,p1.z)
 near(plane[1].x,0);near(plane[1].y,1);near(plane[1].z,0)

 tool.instance_variable_set(:@free_axis,:y)
 plane=tool.send(:axis_construction_plane)
 near(plane[1].x,1);near(plane[1].y,0);near(plane[1].z,0)
end
check('axis hysteresis prevents X/Y chatter near diagonal but still switches clearly') do
 tool=SW::Tool.new(SW::DEFAULTS)
 tool.send(:lock_first_point,Geom::Point3d.new(0,0,0))
 assert(tool.send(:model_axis_for,Geom::Point3d.new(100.mm,20.mm,0))==:x)
 assert(tool.send(:model_axis_for,Geom::Point3d.new(100.mm,110.mm,0))==:x)
 assert(tool.send(:model_axis_for,Geom::Point3d.new(80.mm,110.mm,0))==:y)
 assert(tool.send(:model_axis_for,Geom::Point3d.new(100.mm,110.mm,0))==:y)
 assert(tool.send(:model_axis_for,Geom::Point3d.new(140.mm,100.mm,0))==:x)
end
check('detected free basis is aligned exactly to a Model axis and Z is vertical') do
 tool=SW::Tool.new(SW::DEFAULTS)
 tool.instance_variable_set(:@p1,Geom::Point3d.new(0,0,0))
 view=TestView.new
 b=tool.send(:model_axis_basis_from,Geom::Point3d.new(0,0,0),Geom::Point3d.new(200.mm,20.mm,500.mm),view)
 assert(b)
 u=b.xaxis;v=b.yaxis
 near(u.y,0);near(u.z,0);near(u.x,1)
 near(v.x,0);near(v.y,0);near(v.z,1)
end
check('SHIFT slat orientations are vertical horizontal diagonal-right diagonal-left') do
 assert(SW::SLAT_ORIENTATIONS==%w[vertical horizontal diag_right diag_left])
 p=SW.layout(900,700,SW::DEFAULTS.merge('orientation'=>'diag_right','width'=>40,'gap'=>40))
 assert(p[:orientation]=='diag_right')
 panel=p[:panels].first
 assert(panel[:slat_polygons] && panel[:slat_polygons].length==panel[:slats].length)
 panel[:slat_polygons].each do |poly|
  assert(poly.length==4)
  poly.each do |x,y|
   assert(x>=-1.0e-6 && x<=900+1.0e-6)
   assert(y>=-1.0e-6 && y<=700+1.0e-6)
  end
 end
 p2=SW.layout(900,700,SW::DEFAULTS.merge('orientation'=>'diag_left','width'=>40,'gap'=>40))
 assert(p2[:panels].first[:slat_polygons].all?{|poly|poly.length==4})
end
check('diagonal slat ends are clipped flush to the rectangular frame') do
 %w[diag_right diag_left].each do |orientation|
  p=SW.layout(900,700,SW::DEFAULTS.merge('orientation'=>orientation,'width'=>40,'gap'=>40))
  polys=p[:panels].first[:slat_polygons]
  assert(!polys.empty?)
  polys.each do |poly|
   assert(poly.length==4)
   poly.each do |x,y|
    on_boundary=(x.abs<1.0e-5)||((x-900).abs<1.0e-5)||(y.abs<1.0e-5)||((y-700).abs<1.0e-5)
    assert(on_boundary)
   end
  end
 end
end
check('cycling SHIFT rotates slats only and never moves locked P1 or wall plane') do
 tool=SW::Tool.new(SW::DEFAULTS)
 p1=Geom::Point3d.new(250.mm,350.mm,450.mm)
 tool.send(:lock_first_point,p1)
 tool.instance_variable_set(:@basis,Geom::Transformation.new)
 original=tool.instance_variable_get(:@p1)
 view=TestView.new
 %w[horizontal diag_right diag_left vertical].each do |expected|
  tool.send(:cycle_slat_orientation,view)
  assert(tool.instance_variable_get(:@options)['orientation']==expected)
  locked=tool.instance_variable_get(:@p1)
  near(locked.x,original.x);near(locked.y,original.y);near(locked.z,original.z)
  assert(tool.instance_variable_get(:@plane_mode)==:auto)
 end
end
check('four diagonal drag directions produce the same dimensions') do
 tool=SW::Tool.new(SW::DEFAULTS)
 [-1,1].product([-1,1]).each do |sx,sy|
  tool.instance_variable_set(:@p1,Geom::Point3d.new)
  tool.instance_variable_set(:@basis,Geom::Transformation.new)
  tool.instance_variable_set(:@p2,Geom::Point3d.new(sx*1000.mm,sy*2000.mm,0))
  tool.send(:rebuild)
  p=tool.instance_variable_get(:@plan);assert(p)
  near(p[:width],1000);near(p[:height],2000)
  t=tool.instance_variable_get(:@draw_transform)
  near(t.m[0][3],[sx*1000.mm,0].min);near(t.m[1][3],[sy*2000.mm,0].min)
 end
end
# Make sure box winding is outward before relying on the SketchUp kernel.
check('all six real-box face normals point outward') do
 points=SW.box_points([0,0,0,40,200,17.5]);center=Geom::Point3d.new(20.mm,100.mm,8.75.mm)
 SW::BOX_FACES.each do |ids|
  a,b,c=ids.first(3).map{|i|points[i]}
  n=a.vector_to(b).cross(a.vector_to(c));out=center.vector_to(a)
  assert(n.x*out.x+n.y*out.y+n.z*out.z>0)
 end
end
check('backing front face points toward positive local depth') do
 points=SW.box_points([0,0,0,600,1200,9])
 ids=SW::BOX_FACES[1]
 a,b,c=ids.first(3).map{|i|points[i]}
 n=a.vector_to(b).cross(a.vector_to(c));n.normalize!
 assert(n.z>0.999)
end
puts 'SLAT WALL REGRESSIONS COMPLETE'
module Sketchup
 def self.write_default(*args);true;end
end
check('SHIFT rotates slats once per physical key press') do
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 original_mode=tool.instance_variable_get(:@options)['mode']
 assert(tool.instance_variable_get(:@options)['orientation']=='vertical')
 tool.onKeyDown(16,1,0,view)
 assert(tool.instance_variable_get(:@options)['orientation']=='horizontal')
 assert(tool.instance_variable_get(:@options)['mode']==original_mode)
 tool.onKeyDown(16,1,0,view)
 assert(tool.instance_variable_get(:@options)['orientation']=='horizontal')
 tool.onKeyUp(16,1,0,view);tool.onKeyDown(16,1,0,view)
 assert(tool.instance_variable_get(:@options)['orientation']=='diag_right')
 assert(tool.instance_variable_get(:@options)['mode']==original_mode)
end
check('two clicks create exactly once and reset for continuous creation') do
 set_model;Sketchup.model.selection=Sketchup::Selection.new
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 tool.define_singleton_method(:pick) do |v,x,y|
  if instance_variable_get(:@p1_locked)
   instance_variable_set(:@free_axis,:x)
   instance_variable_set(:@basis,Geom::Transformation.new)
  end
  Geom::Point3d.new(x.mm,y.mm,0)
 end
 tool.onLButtonDown(0,0,0,view);tool.onLButtonUp(0,0,0,view)
 assert(Sketchup.model.commits==0)
 tool.onLButtonDown(0,1000,2000,view);tool.onLButtonUp(0,1000,2000,view)
 assert(Sketchup.model.commits==1)
 assert(tool.instance_variable_get(:@p1).nil?)
end
check('drag release creates exactly once; Escape discards pending region') do
 set_model;Sketchup.model.selection=Sketchup::Selection.new
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 tool.define_singleton_method(:pick) do |v,x,y|
  if instance_variable_get(:@p1_locked)
   instance_variable_set(:@free_axis,:x)
   instance_variable_set(:@basis,Geom::Transformation.new)
  end
  Geom::Point3d.new(x.mm,y.mm,0)
 end
 tool.onLButtonDown(0,0,0,view);tool.onLButtonUp(0,1000,2000,view)
 assert(Sketchup.model.commits==1)
 tool.onLButtonDown(0,0,0,view);tool.onCancel(0,view)
 assert(Sketchup.model.commits==1);assert(tool.instance_variable_get(:@p1).nil?)
end
check('drag release commits last valid preview without repicking P2') do
 set_model;Sketchup.model.selection=Sketchup::Selection.new
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 calls=0
 tool.define_singleton_method(:pick) do |v,x,y|
  calls+=1
  calls==1 ? Geom::Point3d.new(0,0,0) : nil
 end
 tool.define_singleton_method(:basis_at){|p,v|Geom::Transformation.new}
 tool.onLButtonDown(0,0,0,view)
 tool.instance_variable_set(:@free_axis,:x)
 tool.instance_variable_set(:@basis,Geom::Transformation.new)
 tool.instance_variable_set(:@p2,Geom::Point3d.new(1000.mm,2000.mm,0))
 tool.send(:rebuild)
 before=calls
 tool.onLButtonUp(0,1000,2000,view)
 assert(Sketchup.model.commits==1)
 assert(calls==before)
end
puts "TOTAL #{$count} REGRESSIONS PASSED"
module Attrs
 def delete_attribute(d,k);(@attrs||={}).delete([d,k]);end
end
class Sketchup::Edge
 def faces;[];end
end
class Sketchup::Entities
 def add_line(a,b);add_edges(a,b).first;end
 def erase_entities(e);delete(e);end
end
check('repair migrates legacy profile into ABF Intersect with Face') do
 set_model
 tag=Sketchup.model.layers.add('ABF_HANENLAMAM')
 backing=SW.make_box(Sketchup.model.entities,[0,0,0,600,1200,17.5],'VL1_TAM_LOT',nil)
 points=[[20,20],[60,20],[60,1180],[20,1180]].map{|a,b|Geom::Point3d.new(a.mm,b.mm,17.5.mm)}
 legacy=backing.entities.add_group
 legacy.name='ABF_HANENLAMAM_1';legacy.layer=tag
 legacy.set_attribute(SW::KEY,'role','cnc_profile')
 legacy.set_attribute(SW::KEY,'profile',1)
 legacy.set_attribute(SW::KEY,'depth_mm',3)
 legacy.entities.add_edges(*(points+[points.first]))
 backing.set_attribute(SW::KEY,'operation_tag','ABF_HANENLAMAM')
 backing.set_attribute(SW::KEY,'profile_count',1)
 backing.set_attribute(SW::KEY,'depth_mm',3)
 SW.repair_backing(backing,Sketchup.model)
 assert(backing.layer.name=='Layer0')
 assert(backing.get_attribute('ABF','is-board'))
 assert(backing.entities.grep(Sketchup::Face).size==6)
 intersects=backing.entities.grep(Sketchup::Group).select{|g|SW.abf_intersect_group?(g)}
 assert(intersects.size==1)
 profile=intersects.first
 assert(profile.name=='_ABF_Intersect')
 assert(profile.layer.name=='ABF_HANENLAMAM')
 assert(profile.get_attribute('ABF','is-intersect')==true)
 assert(profile.entities.grep(Sketchup::Edge).size==4)
 assert(profile.entities.grep(Sketchup::Face).size==1)
 assert(profile.entities.grep(Sketchup::Edge).all?{|e|near(e.start.position.z,0);near(e.end.position.z,0);true})
 assert(SW.backing_front_face(backing).get_attribute('ABF','is-cnced-face')==true)
 summary=SW.backing_profile_summary(backing)
 assert(summary[:cutting_group_count]==0)
 assert(summary[:intersect_group_count]==1)
 assert(summary[:profile_count]==1 && summary[:complete])
 assert(backing.get_attribute(SW::KEY,'profile_type')=='ABF_Intersect')
end
