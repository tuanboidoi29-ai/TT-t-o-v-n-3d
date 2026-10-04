require_relative '../files/tran_tuan_noi_that/wall_junctions'
module Sketchup;class Edge;end;class Group;end;end
Point=Struct.new(:values){def to_a;values;end}
Box=Struct.new(:min,:max)
class MockGroup < Sketchup::Group
 attr_reader :bounds,:entities,:merges,:exploded
 def initialize(lo,hi,valid=true);@bounds=Box.new(Point.new(lo),Point.new(hi));@entities=[];@valid=valid;@merges=0;end
 def manifold?;@valid;end
 def valid?;true;end
 def union(other)
  @merges+=1;return nil if $union_fail
  lo=3.times.map{|i|[bounds.min.values[i],other.bounds.min.values[i]].min}
  hi=3.times.map{|i|[bounds.max.values[i],other.bounds.max.values[i]].max}
  MockGroup.new(lo,hi)
 end
 def explode;@exploded=true;end
end
J=TranTuanNoiThat::WallJunctions
n=0
check=lambda{|label,&b|raise label unless b.call;n+=1}
a=MockGroup.new([0,0,0],[2000,110,2800]);l=MockGroup.new([0,0,0],[110,1800,2800]);t=MockGroup.new([1000,110,0],[1110,1800,2800])
check.call('L overlap'){J.touching?(a,l)}
check.call('T face contact'){J.touching?(a,t)}
check.call('door gap kept'){!J.touching?(a,MockGroup.new([2900,0,0],[4000,110,2800]))}
check.call('edge only excluded'){!J.touching?(a,MockGroup.new([2000,110,0],[2100,220,2800]))}
check.call('point only excluded'){!J.touching?(a,MockGroup.new([2000,110,2800],[2100,220,3000]))}
container=MockGroup.new([0,0,0],[2000,1800,2800]);container.entities.concat([a,l]);J.finish(container)
check.call('actual union called'){a.merges==1}
$union_fail=true
container=MockGroup.new([0,0,0],[2000,1800,2800]);a=MockGroup.new([0,0,0],[2000,110,2800]);container.entities.concat([a,l])
begin;J.finish(container);raise 'should fail';rescue RuntimeError=>e;raise unless e.message.include?('Không hợp nhất');end
check.call('failed union never flattened'){!a.exploded && !l.exploded}
$union_fail=false
Normal=Struct.new(:dot_value){def dot(other);dot_value;end}
Pos=Struct.new(:distance){def distance_to_plane(p);distance;end}
Vertex=Struct.new(:position)
Face=Struct.new(:normal,:material,:back_material,:vertices,:plane)
class MockEdge < Sketchup::Edge
 attr_reader :faces,:erased
 def initialize(faces);@faces=faces;end
 def valid?;true;end
 def erase!;@erased=true;end
end
flat=Face.new(Normal.new(1.0),nil,nil,[Vertex.new(Pos.new(0))],[])
angled=Face.new(Normal.new(0.0),nil,nil,[Vertex.new(Pos.new(0))],[])
remote=Face.new(Normal.new(1.0),nil,nil,[Vertex.new(Pos.new(1))],[])
other_material=Face.new(Normal.new(1.0),:red,nil,[Vertex.new(Pos.new(0))],[])
edges=[MockEdge.new([flat,flat]),MockEdge.new([angled,flat]),MockEdge.new([flat,remote]),MockEdge.new([flat,other_material]),MockEdge.new([flat])]
c=MockGroup.new([0,0,0],[1,1,1]);c.entities.concat(edges);J.clean_edges(c)
check.call('coplanar seam erased'){edges[0].erased}
check.call('right angle retained'){!edges[1].erased}
check.call('different planes retained'){!edges[2].erased}
check.call('material boundary retained'){!edges[3].erased}
check.call('outer border retained'){!edges[4].erased}
puts "#{n} junction/cleanup logic checks passed; native Solid Boolean not simulated"
