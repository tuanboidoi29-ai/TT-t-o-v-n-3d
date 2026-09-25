# Run with the geometry doubles from the preceding upgrade regression.
load File.join(__dir__, 'upgrade_146_test.rb')
load ROOT+'/slat_wall_tool.rb'
SW=TranTuanNoiThat::SlatWall
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
check('backing contact and recess measured exactly') do
 [0,3,5].each do |depth|
  p=SW.layout(1000,1000,SW::DEFAULTS.merge('mode'=>'backed','recess'=>depth))
  near(p[:panels][0][:slats][0][2],9-depth)
  near(p[:panels][0][:backing][5],9)
 end
end
check('CNC custom tag normalized; invalid recess and oversize rejected') do
 assert(SW.validate(SW::DEFAULTS.merge('tag'=>'TEST'))['tag']=='ABF_TEST')
 begin;SW.validate(SW::DEFAULTS.merge('mode'=>'backed','recess'=>9));raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('Hạ âm'));end
 begin;SW.layout(100_000,100_000,SW::DEFAULTS);raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('200'));end
end
# Geometry recording doubles: exercise the production builder, not a copy of it.
module Attrs
 def get_attribute(d,k,default=nil);(@attrs||={}).fetch([d,k],default);end
 def set_attribute(d,k,v);(@attrs||={})[[d,k]]=v;end
end
class Sketchup::Face
 attr_accessor :layer
 def edges;outer_loop.edges;end
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
  f=Sketchup::Face.new(points.map{|p|Sketchup::Vertex.new(p)});self<<f;f
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
check('real builder: VL hierarchy, individual slats, closed CNC paths and custom tag') do
 p=SW.layout(1400,1000,SW::DEFAULTS.merge('mode'=>'backed','cnc'=>true,'tag'=>'ABF_TEST','recess'=>3))
 parent=SW.create(Sketchup.model,p,Geom::Transformation.new)
 assert(parent.entities.map(&:name)==['VL1','VL2'])
 parent.entities.each_with_index do |vl,i|
  backing=vl.entities.first
  assert(backing.name.end_with?('TAM_LOT'));assert(backing.layer.name=='Layer0');assert(backing.get_attribute('ABF','is-board')==true)
  count=p[:panels][i][:slats].size
  assert(vl.entities.size==count+1)
  assert(backing.get_attribute(SW::KEY,'profile_count')==count)
  profiles=backing.entities.grep(Sketchup::Group)
  assert(profiles.size==count)
  assert(backing.entities.grep(Sketchup::Edge).empty?)
  profiles.each do |profile|
   assert(profile.layer.name=='ABF_TEST')
   assert(profile.get_attribute(SW::KEY,'depth_mm')==3)
   loop=profile.entities.grep(Sketchup::Edge)
   assert(loop.size==4)
   near(loop.first.start.position.distance(loop.last.end.position),0)
   assert(loop.all?{|e|e.layer.name=='Layer0'})
  end
  assert(backing.entities.grep(Sketchup::Face).size==6)
 end
 assert(Sketchup.model.commits==1)
 parent2=SW.create(Sketchup.model,p,Geom::Transformation.new)
 assert(parent2.entities.first.name=='VL3')
end
set_model
check('CNC off leaves backing with no machining profile edges') do
 p=SW.layout(500,700,SW::DEFAULTS.merge('mode'=>'backed','cnc'=>false))
 parent=SW.create(Sketchup.model,p,Geom::Transformation.new)
 backing=parent.entities.first.entities.first
 assert(backing.entities.grep(Sketchup::Edge).empty?)
 assert(backing.get_attribute(SW::KEY,'profile_count')==0)
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
puts 'SLAT WALL REGRESSIONS COMPLETE'
module Sketchup
 def self.write_default(*args);true;end
end
check('SHIFT switches once per key press and switches back on next press') do
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 tool.onKeyDown(16,1,0,view)
 assert(tool.instance_variable_get(:@options)['mode']=='backed')
 tool.onKeyDown(16,1,0,view)
 assert(tool.instance_variable_get(:@options)['mode']=='backed')
 tool.onKeyUp(16,1,0,view);tool.onKeyDown(16,1,0,view)
 assert(tool.instance_variable_get(:@options)['mode']=='single')
end
check('two clicks create exactly once and reset for continuous creation') do
 set_model;Sketchup.model.selection=Sketchup::Selection.new
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 tool.define_singleton_method(:pick){|v,x,y|Geom::Point3d.new(x.mm,y.mm,0)}
 tool.define_singleton_method(:basis_at){|p,v|Geom::Transformation.translation(Geom::Vector3d.new(p.x,p.y,p.z))}
 tool.onLButtonDown(0,0,0,view);tool.onLButtonUp(0,0,0,view)
 assert(Sketchup.model.commits==0)
 tool.onLButtonDown(0,1000,2000,view);tool.onLButtonUp(0,1000,2000,view)
 assert(Sketchup.model.commits==1)
 assert(tool.instance_variable_get(:@p1).nil?)
end
check('drag release creates exactly once; Escape discards pending region') do
 set_model;Sketchup.model.selection=Sketchup::Selection.new
 tool=SW::Tool.new(SW::DEFAULTS.dup);view=TestView.new
 tool.define_singleton_method(:pick){|v,x,y|Geom::Point3d.new(x.mm,y.mm,0)}
 tool.define_singleton_method(:basis_at){|p,v|Geom::Transformation.translation(Geom::Vector3d.new(p.x,p.y,p.z))}
 tool.onLButtonDown(0,0,0,view);tool.onLButtonUp(0,1000,2000,view)
 assert(Sketchup.model.commits==1)
 tool.onLButtonDown(0,0,0,view);tool.onCancel(0,view)
 assert(Sketchup.model.commits==1);assert(tool.instance_variable_get(:@p1).nil?)
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
check('repair legacy backing moves CNC edges once and preserves board faces') do
 set_model
 tag=Sketchup.model.layers.add('ABF_HANENLAMAM')
 backing=SW.make_box(Sketchup.model.entities,[0,0,0,600,1200,9],'VL1_TAM_LOT',nil,tag)
 points=[[20,20],[60,20],[60,1180],[20,1180]].map{|a,b|Geom::Point3d.new(a.mm,b.mm,9.mm)}
 backing.entities.add_edges(*(points+[points.first])).each{|e|e.set_attribute(SW::KEY,'profiles',[1]);e.layer=tag}
 backing.set_attribute(SW::KEY,'cnc_tag',tag.name);backing.set_attribute(SW::KEY,'profile_count',1)
 SW.repair_backing(backing,Sketchup.model)
 assert(backing.layer.name=='Layer0');assert(backing.get_attribute('ABF','is-board'))
 assert(backing.entities.grep(Sketchup::Face).size==6)
 assert(backing.entities.grep(Sketchup::Edge).empty?)
 profiles=backing.entities.grep(Sketchup::Group);assert(profiles.size==1)
 assert(profiles.first.layer.name=='ABF_HANENLAMAM')
 assert(profiles.first.entities.grep(Sketchup::Edge).size==4)
 SW.repair_backing(backing,Sketchup.model)
 assert(backing.entities.grep(Sketchup::Group).size==1)
end
