STDOUT.sync = true
$LOAD_PATH.unshift(File.expand_path(__dir__))
require 'sketchup'
class Numeric
  def to_mm; to_f * 25.4; end
end
module Sketchup
  class SelectionObserver; end
  class Face
    attr_reader :vertices, :outer_loop
    def initialize(vertices)
      @vertices=vertices
      edges=vertices.each_index.map { |i| Edge.new(vertices[i],vertices[(i+1)%vertices.length]) }
      @outer_loop=Struct.new(:edges,:vertices).new(edges,vertices)
    end
    def valid?;true;end
    def area; a=vertices[0].position.vector_to(vertices[1].position);b=vertices[0].position.vector_to(vertices[-1].position);a.cross(b).length;end
  end
  class ComponentInstance
    def hidden?;false;end
  end
  class Definition
    def bounds
      b=Geom::BoundingBox.new
      entities.each do |e|
        if e.respond_to?(:vertices);e.vertices.each{|v|b.add(v.position)}
        else;8.times{|i|b.add(e.bounds.corner(i))};end
      end
      b
    end
  end
end
module Geom
  class Point3d
    def vector_to(p);Vector3d.new(p.x-x,p.y-y,p.z-z);end
    def self.linear_combination(a,p,b,q);new(a*p.x+b*q.x,a*p.y+b*q.y,a*p.z+b*q.z);end
  end
  class Vector3d
    def cross(v);Vector3d.new(y*v.z-z*v.y,z*v.x-x*v.z,x*v.y-y*v.x);end
    def normalize;dup.normalize!;end
  end
  class BoundingBox
    def width;max.x-min.x;end
    def height;max.y-min.y;end
    def depth;max.z-min.z;end
    def center;Point3d.linear_combination(0.5,min,0.5,max);end
    def valid?;!empty?;end
  end
  class Transformation
    def self.axes(o,x,y,z);new([[x.x,y.x,z.x,o.x],[x.y,y.y,z.y,o.y],[x.z,y.z,z.z,o.z],[0,0,0,1]]);end
    def self.scaling(o,x,y=x,z=x);translation(Vector3d.new(o.x,o.y,o.z))*scale(x,y,z)*translation(Vector3d.new(-o.x,-o.y,-o.z));end
  end
end
class TestModel
  attr_accessor :entities,:chosen_tool
  def initialize(items)
    @entities=@active_entities=Sketchup::Entities.new(items);@selection=[];@edit_transform=Geom::Transformation.new;@active_path=[];@active_view=TestView.new;@commits=0;@aborts=0
  end
  def select_tool(t);old=@chosen_tool;@chosen_tool=t;old.deactivate(active_view) if old && old!=t;end
  def start_operation(*args);@before=entities.map{|e|[e,e.transformation]};end
  def abort_operation;@aborts+=1;(@before||[]).each{|e,t|e.transformation=t};end
end
class TestView
  attr_accessor :locked,:drawn
  def lock_inference;@locked=false;end
  def zoom(*a);end
  def drawing_color=(v);end
  def line_width=(v);end
  def draw(*args);(@drawn||=[])<<args;end
  def draw2d(*args);(@drawn||=[])<<args;end
end
GL_QUADS=7;GL_LINES=1
ROOT=File.expand_path('../files/tran_tuan_noi_that', __dir__)
load ROOT+'/tam_pro.rb'
TranTuanNoiThat.const_set(:ROOT, ROOT)
load ROOT+'/door_standard_tool.rb'
load ROOT+'/round_tool.rb'
load ROOT+'/scale_corner_lock.rb'
T=TranTuanNoiThat::TamPro
$count=0
def check(name)
 yield
 $count+=1
 puts "PASS #{name}"
end
def assert(x,msg='assertion failed');raise msg unless x;end
def near(a,b);assert((a-b).abs<0.00001,"#{a} != #{b}");end
def board(x,y,z,inner=Geom::Transformation.new)
 points=8.times.map{|i|Geom::Point3d.new((i&1)==0 ? 0 : x.mm,(i&2)==0 ? 0 : y.mm,(i&4)==0 ? 0 : z.mm).transform(inner)}
 vs=points.map{|p|Sketchup::Vertex.new(p)}
 faces=[[0,1,3,2],[4,5,7,6],[0,1,5,4],[2,3,7,6],[0,2,6,4],[1,3,7,5]].map{|ids|Sketchup::Face.new(ids.map{|i|vs[i]})}
 Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new(faces)))
end
def set_model(*items);Sketchup.model=TestModel.new(items);end
b=board(600,400,17.5);set_model(b)
check('shortest physical board dimension'){near(T.thickness_info(b)[:thickness],17.5)}
rot=Geom::Transformation.new([[0.8,-0.6,0,0],[0.6,0.8,0,0],[0,0,1,0],[0,0,0,1]])
br=board(17.5,400,600,rot);set_model(br)
check('geometry rotated inside group axes'){near(T.thickness_info(br)[:thickness],17.5)}
child=board(600,400,9);parent=Sketchup::Group.new(Sketchup::Definition.new(Sketchup::Entities.new([child])),Geom::Transformation.scale(1,1,2));set_model(parent)
check('parent scale and leaf-only scan'){rows=T.thickness_rows('model');assert(rows.size==1);near(rows[0][:thickness],18)}
copy=Sketchup::ComponentInstance.new(parent.definition,Geom::Transformation.scale(1,1,3));set_model(parent,copy)
check('shared occurrences retain distinct dimensions'){assert(T.thickness_rows('model').map{|r|r[:thickness].round}.sort==[18,27])}
check('shared-parent edits fail before mutation'){begin;T.change_thickness(T.find_matches('model',18,0.01),20);raise 'accepted shared edit';rescue RuntimeError=>e;assert(e.message.include?('Make Unique'));end;near(child.transformation.m[2][2],1)}
set_model(br)
check('rotated shortest direction edit; length and width preserved') do
 rows=T.thickness_rows('model');near(rows[0][:thickness],17.5)
 assert(T.change_thickness(rows,25)==1)
 dims=T.thickness_info(br)[:dims].sort
 dims.zip([25,400,600]).each{|a,c|near(a,c)}
 assert(Sketchup.model.commits==1)
end
set_model(board(500,300,12.3))
check('custom thickness and tolerance'){assert(T.find_matches('model','12,3',0.01).size==1);assert(T.find_matches('model',17.5,0.1).empty?)}
check('invalid target rejected'){begin;T.find_matches('model',0,0.1);raise 'accepted';rescue RuntimeError=>e;assert(e.message.include?('lớn hơn'));end}
check('highlight displays and clears without geometry or selection changes') do
 original=Sketchup.model.entities[0];Sketchup.model.selection<<original
 assert(T.highlight_matches(T.thickness_rows('model'))==1)
 tool=Sketchup.model.chosen_tool;tool.draw(Sketchup.model.active_view)
 assert(Sketchup.model.active_view.drawn.size==7)
 T.clear_highlight;assert(Sketchup.model.chosen_tool.nil?);assert(Sketchup.model.selection==[original]);assert(Sketchup.model.commits==0)
end
check('door direction unlock resolves to implemented method') do
 tool=TranTuanNoiThat::DoorStandard::Tool.allocate
 view=TestView.new;view.locked=true
 assert(tool.send(:clear_inference_lock,view));assert(!view.locked)
 assert(!File.read(ROOT+'/door_standard_tool.rb').include?('unlock_direction_lock'))
end
check('thickness UI preserves manually entered target') do
 html=T.thickness_html;assert(html.include?('list="thicknessList"'));assert(!html.include?('sel.value=old'));assert(html.include?('BỎ SÁNG'))
end
set_model(board(600,400,17.5))
check('scale handle lies at actual edge midpoint; aperture does not jump') do
 tool=TranTuanNoiThat::ScaleCornerLock::Tool.new
  tool.send(:set_entity,Sketchup.model.entities.first)
 tool.send(:refresh_view_plane)
 p=tool.send(:edge_midpoint_world,:u_max)
 ends=tool.send(:edge_world_points,:u_max)
 near(p.distance(ends[0]),p.distance(ends[1]))
 view=Sketchup.model.active_view;screen=view.screen_coords(p)
 tool.send(:begin_drag,:u_max,view,screen.x+9,screen.y+7)
 tool.send(:update_scale_preview,view,screen.x+9,screen.y+7)
 near(tool.instance_variable_get(:@factor),1)
 tool.send(:update_scale_preview,view,screen.x+69,screen.y+7)
 near(tool.instance_variable_get(:@factor),1.1)
end
check('round snap accepts edge endpoint with cursor outside face') do
 vertex=Sketchup::Vertex.new(Geom::Point3d.new(1,2,0));v2=Sketchup::Vertex.new(Geom::Point3d.new(10,20,0));edge=Sketchup::Edge.new(vertex,v2)
 picker=Object.new
 picker.define_singleton_method(:do_pick){|*a|}
 picker.define_singleton_method(:count){1}
 picker.define_singleton_method(:leaf_at){|i|edge}
 picker.define_singleton_method(:transformation_at){|i|Geom::Transformation.new}
 view=TestView.new;view.define_singleton_method(:pick_helper){picker}
 tool=TranTuanNoiThat::Round::Tool.allocate
 tool.define_singleton_method(:build){|v,f,t| {valid:true,vertex:v.position.transform(t)}}
 result=tool.send(:nearby,view,28,54)
 near(result[:vertex].x,1);near(result[:vertex].y,2)
end
puts "ALL #{$count} REGRESSIONS PASSED (API test doubles, not live SketchUp)."
