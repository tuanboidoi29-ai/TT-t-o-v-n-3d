require_relative 'cabinet_equal_regression'
module Geom
  class Point3d
    attr_reader :x,:y,:z
    def initialize(x,y,z);@x=x;@y=y;@z=z;end
    def transform(t);t.call(self);end
    def -(p);self.class.new(x-p.x,y-p.y,z-p.z);end
    def dot(p);x*p.x+y*p.y+z*p.z;end
    def to_a;[x,y,z];end
  end
end
Vertex=Struct.new(:position)
Edge=Struct.new(:start,:end) { def valid?;true;end }
class SnapView
  attr_accessor :tooltip
  def screen_coords(p);p;end
  def camera;Struct.new(:direction,:eye).new(Geom::Point3d.new(0,0,1),Geom::Point3d.new(0,0,-100));end
end
edge=Edge.new(Vertex.new(Geom::Point3d.new(0,0,0)),Vertex.new(Geom::Point3d.new(100,0,0)))
tr=proc { |p| Geom::Point3d.new(200-p.y*3,50+p.x*2,p.z) }
points=D.edge_snap_points(edge,tr)
assert(points.map { |p| p[0].to_a }==[[200,50,0],[200,250,0],[200,150,0]])
v=SnapView.new
assert(D.nearest_snap(points,205,51,v)[0].to_a==[200,50,0])
assert(D.nearest_snap(points,198,249,v)[0].to_a==[200,250,0])
assert(D.nearest_snap(points,203,150,v)[1]=='Trung điểm cạnh')
assert(D.nearest_snap(points,220,150,v).nil?)
assert(D.nearest_snap([[Geom::Point3d.new(200,150,-200),'behind',0]],200,150,v).nil?)
class SnapProbe
  attr_reader :edge,:transformation
  def initialize(edge,tr);@edge=edge;@transformation=tr;end
  def pick(*args);end
  def valid?;true;end
  def tooltip;'native';end
  def copy!(other);@edge=other.edge;@transformation=other.transformation;end
end
t=D::Tool.allocate
t.instance_variable_set(:@stage,0)
t.instance_variable_set(:@ip,SnapProbe.new(edge,tr))
t.instance_variable_set(:@snap_probes,Array.new(9) { SnapProbe.new(edge,tr) })
t.pick(200,150,v)
assert(t.instance_variable_get(:@snap_point).to_a==[200,150,0])
assert(v.tooltip=='Trung điểm cạnh')
t.pick(200,250,v);assert(v.tooltip=='Đầu cạnh')
t.pick(240,150,v);assert(t.instance_variable_get(:@snap_point).nil?);assert(v.tooltip=='native')
puts "PASS #{$count} total assertions including transformed endpoints, midpoint, snap radius and release."
