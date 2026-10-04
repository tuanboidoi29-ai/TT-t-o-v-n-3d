require_relative 'sketchup'
class Numeric;def mm;to_f/25.4;end;end
require_relative '../files/tran_tuan_noi_that/cad_wall_engine'
require_relative '../files/tran_tuan_noi_that/cad_walls'
class FaceMock
 attr_reader :normal,:height
 def initialize;@normal=Geom::Vector3d.new(0,0,1);end
 def pushpull(h);@height=h;end
 def reverse!;end
end
class EntitiesMock
 attr_reader :groups,:points,:face
 def initialize;@groups=[];end
 def add_group;g=GroupMock.new;@groups<<g;g;end
 def add_face(pts);@points=pts;@face=FaceMock.new;end
end
class GroupMock
 attr_accessor :name,:layer,:transformation
 attr_reader :entities
 def initialize;@entities=EntitiesMock.new;end
 def manifold?;!$fail_solid;end
 def set_attribute(*);end
end
class LayersMock
 def initialize;@h={};end
 def [](k);@h[k];end
 def add(k);@h[k]=k;end
end
class SelectionMock
 attr_reader :selected
 def clear;@selected=[];end
 def add(g);@selected<<g;end
end
class ModelMock
 attr_reader :events,:active_entities,:layers,:selection
 def initialize;@events=[];@active_entities=EntitiesMock.new;@layers=LayersMock.new;@selection=SelectionMock.new;end
 def start_operation(*);@events<<:start;end
 def commit_operation;@events<<:commit;end
 def abort_operation;@events<<:abort;end
end
C=TranTuanNoiThat::CadWalls
model=ModelMock.new
C.instance_variable_set(:@model,model);C.instance_variable_set(:@context,model.active_entities);C.instance_variable_set(:@edit,Geom::Transformation.new)
C.instance_variable_set(:@options,{height:2800,base:100});C.instance_variable_set(:@dialog,nil)
def set_wall
 C.instance_variable_set(:@walls,[{id:0,a:[0,55],b:[4000,55],width:110,length:4000,layer:'A-WALL',selected:true}])
end
set_wall;C.create
raise 'wrong transaction' unless model.events==[:start,:commit]
parent=model.active_entities.groups.first;wall=parent.entities.groups.first
raise 'wrong tag' unless parent.layer=='TT_TUONG_CAD'
raise 'height' unless (wall.entities.face.height-2800.mm).abs<1e-8
raise 'base elevation' unless wall.entities.points.all?{|p|(p.z-100.mm).abs<1e-8}
raise 'repeat create' unless C.instance_variable_get(:@walls).empty?
set_wall;$fail_solid=true
begin;C.create;raise 'did not fail';rescue RuntimeError=>e;raise unless e.message.include?('không kín');end
raise 'no abort' unless model.events.last==:abort
['NaN','Infinity','-1','0'].each do |s|
 begin;C.number(s,1,30000,'Height');raise 'invalid accepted';rescue ArgumentError,RuntimeError=>e;raise if e.message=='invalid accepted';end
end
puts 'Create flow: one operation, height/base, tag, reset, abort on non-solid, numeric guards passed'
