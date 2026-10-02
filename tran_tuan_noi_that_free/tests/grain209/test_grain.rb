require_relative 'sketchup'
load File.expand_path('../../files/tran_tuan_noi_that/grain_board_auto.rb',__dir__)
G=TranTuanNoiThat::GrainBoardAuto
$checks=0
def check(v,label);raise label unless v;$checks+=1;end
def near(a,b);(a-b).abs<1e-6;end
Vertex=Struct.new(:position);Loop=Struct.new(:vertices)
Texture=Struct.new(:image_width,:image_height);Material=Struct.new(:texture)
class Face < Sketchup::Face
 attr_accessor :material,:back_material,:fail
 attr_reader :vertices,:edges,:mappings
 def initialize(ps,mat)
  @vertices=ps.map { |p| Vertex.new(Geom::Point3d.new(*p)) };@edges=[];@material=mat;@mappings=[];@attrs={}
 end
 def outer_loop;Loop.new(vertices);end
 def area(tr);G.frame(vertices.map { |v| v.position.transform(tr).to_a })[:area];end
 def get_attribute(d,k,v=nil);@attrs.fetch([d,k],v);end
 def set_attribute(d,k,v);@attrs[[d,k]]=v;end
 def position_material(mat,mapping,front);raise 'mapping failure' if @fail;@mappings << [mapping,front];true;end
end
class Geom::Transformation
 def *(t)
  r=rows.map do |row|
   (0..2).map { |j| (0..2).sum { |k| row[k]*t.rows[k][j] } }+[(0..2).sum { |k| row[k]*t.rows[k][3] }+row[3]]
  end
  self.class.new(r)
 end
end
class Group < Sketchup::Group
 attr_accessor :material,:transformation,:locked,:after_unique
 attr_reader :unique_count
 def initialize(es=[]);@es=es;@transformation=Geom::Transformation.new;@locked=false;@attrs={};@unique_count=0;end
 def definition;Struct.new(:entities).new(@es);end
 def valid?;true;end
 def locked?;@locked;end
 def make_unique;@unique_count+=1;@es=@after_unique if @after_unique;end
 def get_attribute(d,k,v=nil);@attrs.fetch([d,k],v);end
 def set_attribute(d,k,v);@attrs[[d,k]]=v;end
end
class Model
 attr_accessor :entities,:active_entities,:selection,:active_path
 attr_reader :events,:active_view
 def initialize;@entities=[];@active_entities=@entities;@selection=[];@events=[];@active_view=Object.new;def @active_view.invalidate;end;end
 def edit_transform;Geom::Transformation.new;end
 def start_operation(*);@events << :start;end
 def commit_operation;@events << :commit;end
 def abort_operation;@events << :abort;end
 def select_tool(t);@tool=t;end
end
module Sketchup
 def self.active_model;@model ||= Model.new;end
end
id=Geom::Transformation.new
rect=[[0,0,0],[40,0,0],[40,12,0],[0,12,0]]
vert=rect.map { |x,y,z| [y,z,x] }
check(near(G.frame(rect)[:length],40),'real length')
check(G.frame(vert)[:g][2].abs>0.999,'standing')
check(G.frame(rect)[:g][0].abs>0.999,'horizontal')
chamfer=[[1,0,0],[39,0,0],[40,1,0],[40,11,0],[39,12,0],[1,12,0],[0,11,0],[0,1,0]]
check(G.frame(chamfer)[:g][0].abs>0.999,'ignore chamfer')
check(G.frame([[0,0,0],[1,0,0],[2,0,0]]).nil?,'degenerate skip')
mat=Material.new(Texture.new(100,200))
transforms=[id,Geom::Transformation.new([[0,-2,0,20],[3,0,0,10],[0,0,-1,5]]),Geom::Transformation.new([[2,0.5,0,3],[0,1,0,4],[0,0,1,5]])]
transforms.each do |tr|
 basis=G.frame(rect.map { |p| Geom::Point3d.new(*p).transform(tr).to_a })
 [Texture.new(100,200),Texture.new(200,100)].each do |tex|
  [false,true].each do |manual|
   m=G.uv_mapping(basis,tex,tr,manual)
   p0=m[0].transform(tr);u=m[2].transform(tr)-p0;v=m[4].transform(tr)-p0
   expect=G.texture_axis(tex)==:v ? [1220,2440] : [2440,1220]
   check(near(u.length*25.4,expect[0])&&near(v.length*25.4,expect[1]),'UV physical size')
   check(u.normalize.dot(v.normalize).abs<1e-7,'no shear UV')
   check(m[3].x==1&&m[5].y==1,'UV 0..1')
  end
 end
end
h=Face.new(rect,mat);v=Face.new(vert,mat)
plans=G.face_plans([h,v],id,nil,80)
check(plans.length==2,'multiple separate boards in Group')
check(plans[0][:frame][:g][0].abs>0.99&&plans[1][:frame][:g][2].abs>0.99,'own board directions')
back=Face.new(rect.map { |x,y,z| [x,y,0.7] },mat)
edge=Struct.new(:faces).new([h,back]);h.edges << edge;back.edges << edge
plans=G.face_plans([h,back],id,nil,80)
check(plans.length==2&&plans.all? { |p| p[:frame][:g][0].abs>0.99 },'both main faces')
tool=G::Tool.new;model=Sketchup.active_model;view=model.active_view
# Walk always obtains fresh descendants after unique.
stale=Group.new([Face.new(vert,mat)]);fresh=Group.new([Face.new(rect,mat)]);root=Group.new([stale]);root.after_unique=[fresh]
plans=[];tool.walk(root,id,nil,true) { |p| plans << p }
check(root.unique_count==1&&fresh.unique_count==1&&stale.unique_count==0,'fresh nested instances after unique')
check(plans.first[:frame][:g][0].abs>0.99,'fresh geometry used')
root.locked=true;plans=[];tool.walk(root,id,nil,false) { |p| plans << p };check(plans.empty?,'skip locked')
root.locked=false
# Preview must be read-only.
u=root.unique_count;tool.walk(root,id,nil,false) { |_p| };check(root.unique_count==u,'preview no mutation')
# TAB initial repeat 1 or 0, hold repeat ignored; next press toggles.
check(tool.onKeyDown(9,1,0,view),'TAB consumed')
tool.onKeyDown(9,2,0,view);check(tool.instance_variable_get(:@manual),'TAB one toggle')
tool.onKeyUp(9,0,0,view);tool.onKeyDown(9,0,0,view);check(!tool.instance_variable_get(:@manual),'TAB toggles back')
tool.onKeyUp(9,0,0,view)
model.events.clear;target=Group.new([h]);tool.apply([target],view)
check(model.events==[:start,:commit],'one Undo operation')
check(h.mappings.length==1,'front face mapped')
tool.instance_variable_set(:@manual,true);check(tool.preview_turn(h),'manual preview before click')
tool.apply([target],view);check(!tool.preview_turn(h),'manual next preview follows stored orientation')
h.fail=true;model.events.clear;tool.apply([target],view);check(model.events==[:start,:abort],'mapping error aborts operation');h.fail=false
model.selection=[target];tool.scan(view);model.active_entities=[];model.events.clear;tool.onKeyDown(13,1,0,view);check(model.events.empty?,'changed context blocks stale apply')
load File.expand_path('../../files/tran_tuan_noi_that/grain_board_auto.rb',__dir__)
check(TranTuanNoiThat::Grain.method(:activate).source_location.first.end_with?('grain_board_auto.rb'),'suite entry calls new tool')
wide_upright=[[0,0,0],[80,0,0],[80,0,12],[0,0,12]]
wide=G.frame(wide_upright)
check(wide[:g][2]>0.999 && near(wide[:length],12),'wide upright board uses vertical grain')
flat=G.frame([[0,0,0],[12,0,0],[12,80,0],[0,80,0]])
check(flat[:g][1].abs>0.999 && near(flat[:length],80),'flat board uses true long direction')
rotated=wide_upright.map { |x,y,z| [x*0.6,x*0.8,z] }
check(G.frame(rotated)[:g][2]>0.999,'rotated upright still vertical')
puts "PASS #{$checks} assertions"
