module Geom
 class Vector3d
  attr_accessor :x,:y,:z
  def initialize(x,y,z);@x,@y,@z=x.to_f,y.to_f,z.to_f;end
  def to_a;[x,y,z];end
  def length;Math.sqrt(dot(self));end
  def dot(v);x*v.x+y*v.y+z*v.z;end
  def cross(v);Vector3d.new(y*v.z-z*v.y,z*v.x-x*v.z,x*v.y-y*v.x);end
  def normalize;v=clone;v.normalize!;v;end
  def normalize!;l=length;raise if l<1e-12;@x/=l;@y/=l;@z/=l;self;end
  def reverse!;@x=-x;@y=-y;@z=-z;self;end
 end
 class Point3d < Vector3d
  def -(p);Vector3d.new(x-p.x,y-p.y,z-p.z);end
  def offset(v,d=1);v=v.normalize;Point3d.new(x+v.x*d,y+v.y*d,z+v.z*d);end
  def transform(t);Point3d.new(*t.rows.map { |r| r[0]*x+r[1]*y+r[2]*z+r[3] });end
  def distance(p);(self-p).length;end
 end
 class Transformation
  attr_reader :rows
  def initialize(rows=nil);@rows=rows || [[1,0,0,0],[0,1,0,0],[0,0,1,0]];end
  def inverse
   a,b,c=rows.map { |r| Vector3d.new(*r[0,3]) };det=a.dot(b.cross(c))
   cols=[b.cross(c),c.cross(a),a.cross(b)].map { |v| v.to_a.map { |x| x/det } }
   r=cols.transpose;d=rows.map(&:last)
   Transformation.new(r.map { |v| v+[-v.zip(d).sum { |x,y| x*y }] })
  end
 end
 class BoundingBox
  def initialize;@pts=[];end
  def add(*pts);@pts.concat(pts);end
  def min;Point3d.new(*3.times.map { |i| @pts.map { |p| p.to_a[i] }.min });end
  def width;span(0);end;def height;span(1);end;def depth;span(2);end
  def span(i);v=@pts.map { |p| p.to_a[i] };v.max-v.min;end
  def empty?;@pts.empty?;end
 end
end
X_AXIS=Geom::Vector3d.new(1,0,0);Y_AXIS=Geom::Vector3d.new(0,1,0);Z_AXIS=Geom::Vector3d.new(0,0,1);ORIGIN=Geom::Point3d.new(0,0,0);SB_PROMPT=0
module Sketchup
 @prefs={}
 def self.read_default(s,k,d);@prefs.fetch([s,k],d);end
 def self.write_default(s,k,v);@prefs[[s,k]]=v;end
 def self.set_status_text(*);end
 class Face;end
 class Edge;end
 class Group;end
 class ComponentInstance;end
end
module UI
 @timers={};@next=0
 def self.start_timer(*,&b);@next+=1;@timers[@next]=b;@next;end
 def self.stop_timer(id);@timers.delete(id);end
 def self.fire(id);@timers.delete(id)&.call;end
end
def file_loaded?(*);true;end
