require_relative 'sketchup'
load File.expand_path('../../files/tran_tuan_noi_that/cut_block.rb',__dir__)
C=TranTuanNoiThat::CutBlock
$checks=0
def check(v,label);raise label unless v;$checks+=1;end
class Geom::Transformation
 def *(other);self;end
end
ps=[-5,5].product([-4,4],[-3,3]).map { |p| Geom::Point3d.new(*p) }
[X_AXIS,Y_AXIS,Z_AXIS,Geom::Vector3d.new(1,1,1)].each do |axis|
 data=C.plane_data(ps,ORIGIN,axis)
 check(data[:min]<0 && data[:max]>0,'plane crosses volume')
 check(data[:u].dot(data[:v]).abs<1e-8,'orthogonal frame')
 check(data[:n].dot(data[:u]).abs<1e-8,'normal perpendicular')
 check(C.quad(data).all? { |p| (p-ORIGIN).dot(data[:n]).abs<1e-8 },'preview on cutting plane')
 check(C.quad(data,data[:extent]).all? { |p| (p-ORIGIN).dot(data[:n])>data[:max] },'positive cap outside original')
 check(C.quad(data,-data[:extent]).all? { |p| (p-ORIGIN).dot(data[:n])<data[:min] },'negative cap outside original')
end
beyond=C.plane_data(ps,Geom::Point3d.new(0,0,10),Z_AXIS)
check(beyond[:max]<0,'outside plane rejected by signed distance')
class Selection < Array
 def add(e);self << e;end
end
class Entities < Array
 def add_group;g=Solid.new;self << g;g;end
 def add_instance(*);Object.new.tap { |o| def o.explode;end };end
end
class Solid < Sketchup::Group
 attr_accessor :material,:layer,:name,:transformation,:vol,:bad
 attr_reader :entities,:erased
 def initialize
  @entities=Entities.new;@transformation=Geom::Transformation.new;@vol=100;@name='Ván';@bad=false
 end
 def definition;Struct.new(:entities,:name).new(entities,'Ván');end
 def valid?;!@erased;end
 def locked?;false;end
 def manifold?;!bad;end
 def volume;vol;end
 def erase!;@erased=true;end
 def attribute_dictionaries;nil;end
end
class Model
 attr_reader :active_entities,:events,:selection
 def initialize;@active_entities=Entities.new;@events=[];@selection=Selection.new;end
 def edit_transform;Geom::Transformation.new;end
 def start_operation(*);events << :start;end
 def commit_operation;events << :commit;end
 def abort_operation;events << :abort;end
end
# Model the native boolean boundary to verify commit/abort sequencing, not its geometry.
class << C
 alias original_corners corners
 alias original_copy_solid copy_solid
 alias original_cutter cutter
 attr_accessor :answers
 def corners(*);[-5,5].product([-4,4],[-3,3]).map { |p| Geom::Point3d.new(*p) };end
 def cutter(*);Solid.new;end
 def copy_solid(*args)
  solid=Solid.new
  solid.define_singleton_method(:intersect) { |_other| C.answers.shift }
  solid
 end
end
[:both,:positive,:negative].each do |mode|
 model=Model.new;target=Solid.new;model.active_entities << target
 a=Solid.new;a.vol=40;b=Solid.new;b.vol=60;C.answers=[a,b]
 made=C.perform(model,target,ORIGIN,Z_AXIS,mode)
 check(made.length==(mode==:both ? 2 : 1),'keep selected sides')
 check(target.erased,'erase original after successful result')
 check(model.events==[:start,:commit],'single undo operation')
 check(made.all? { |g| g.name.include?('Cắt') },'named groups')
end
[[nil,Solid.new],[Solid.new,nil]].each do |answers|
 model=Model.new;target=Solid.new;model.active_entities << target;C.answers=answers
 begin;C.perform(model,target,ORIGIN,Z_AXIS,:both);raise 'unexpected success';rescue RuntimeError=>e;raise if e.message=='unexpected success';end
 check(!target.erased,'original retained when either half fails')
 check(model.events==[:start,:abort],'rollback when half fails')
end
model=Model.new;target=Solid.new;model.active_entities << target;C.answers=[Solid.new,Solid.new]
begin;C.perform(model,target,ORIGIN,Z_AXIS,:both);rescue RuntimeError;end
check(!target.erased && model.events.last==:abort,'volume mismatch abort')
model=Model.new;target=Solid.new;target.bad=true;model.active_entities << target
begin;C.perform(model,target,ORIGIN,Z_AXIS,:both);rescue RuntimeError;end
check(model.events.empty? && !target.erased,'reject open solid before mutation')
model=Model.new;target=Solid.new;model.active_entities << target
begin;C.perform(model,target,Geom::Point3d.new(0,0,10),Z_AXIS,:both);rescue RuntimeError;end
check(model.events.empty?,'reject outside plane before mutation')
puts "PASS #{$checks} assertions (native boolean not simulated geometrically)"
module UI
 def self.beep;end
end
def ready_tool(model,targets)
 t=C::Tool.new
 {model:model,context:model.active_entities,targets:targets,point:ORIGIN,normal:Z_AXIS,placed:false,down:{}}.each { |k,v| t.instance_variable_set('@'+k.to_s,v) }
 t
end
view=Object.new;def view.invalidate;end
model=Model.new;targets=[Solid.new,Solid.new];targets.each { |t| model.active_entities << t }
tool=ready_tool(model,targets)
C.answers=[40,60,30,70].map { |v| x=Solid.new;x.vol=v;x }
tool.onLButtonDown(0,100,100,view)
check(model.events==[:start,:commit],'click batch uses one operation')
check(model.selection.length==4,'two selected blocks yield four retained groups')
check(tool.instance_variable_get(:@targets).empty?,'ready to select next batch')
model=Model.new;targets=[Solid.new,Solid.new];targets.each { |t| model.active_entities << t }
tool=ready_tool(model,targets)
C.answers=[40,60].map { |v| x=Solid.new;x.vol=v;x }+[nil,nil]
begin;tool.cut_now(view);rescue RuntimeError;end
check(model.events==[:start,:abort],'second block failure aborts entire batch')
# Selection mouse-down/up must only select, never cut.
module Sketchup
 class PickHelper
  PICK_INSIDE=0;PICK_CROSSING=1
 end
end
picker=Object.new
picker.define_singleton_method(:window_pick) { |a,b,kind| @kind=kind }
picker.define_singleton_method(:all_picked) { targets }
view.define_singleton_method(:pick_helper) { picker }
model=Model.new;targets=[Solid.new,Solid.new];targets.each { |t| model.active_entities << t }
tool=ready_tool(model,[])
tool.onLButtonDown(0,10,10,view)
tool.onMouseMove(0,100,100,view)
tool.onLButtonUp(0,100,100,view)
check(tool.instance_variable_get(:@targets)==targets,'rectangle selects multiple groups')
check(picker.instance_variable_get(:@kind)==0,'left-to-right inside selection')
check(model.events.empty?,'selection release does not cut')
puts "PASS #{$checks} total assertions"
