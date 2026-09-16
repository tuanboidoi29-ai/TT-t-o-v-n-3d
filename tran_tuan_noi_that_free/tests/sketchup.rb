# Test doubles only. Not included in plugin and not a SketchUp kernel substitute.
class Numeric
  def mm; to_f / 25.4; end
end
class String
  def to_l
    raise ArgumentError, 'invalid length' unless match?(/\A[+-]?[\d.]+(?:mm|cm|m|in)?\z/)
    factor = end_with?('mm') ? 1.mm : (end_with?('cm') ? 10.mm : (end_with?('m') ? 1000.mm : 1.0))
    to_f * factor
  end
end
SB_PROMPT=0;SB_VCB_LABEL=1;SB_VCB_VALUE=2
module Geom
  class Point3d
    attr_accessor :x,:y,:z
    def initialize(x=0,y=0,z=0);@x=x.to_f;@y=y.to_f;@z=z.to_f;end
    def to_a;[x,y,z];end
    def transform(t);self.class.new(*t.apply(to_a,is_a?(Vector3d) ? 0 : 1));end
    def distance(p);Math.sqrt(to_a.zip(p.to_a).sum{|a,b|(a-b)**2});end
  end
  class Vector3d < Point3d
    def length;Math.sqrt(x*x+y*y+z*z);end
    def length=(n);f=n/length;@x*=f;@y*=f;@z*=f;end
    def normalize!;self.length=1.0;self;end
    def reverse!;@x=-x;@y=-y;@z=-z;self;end
  end
  class Transformation
    attr_reader :m
    def initialize(m=nil);@m=m || Array.new(4){|i|Array.new(4){|j|i==j ? 1.0 : 0.0}};end
    def self.translation(v);t=new;3.times{|i|t.m[i][3]=v.to_a[i]};t;end
    def self.scale(x,y,z);t=new;[x,y,z].each_with_index{|v,i|t.m[i][i]=v};t;end
    def apply(a,w);v=a+[w];3.times.map{|i|4.times.sum{|j|m[i][j]*v[j]}};end
    def *(o);self.class.new(Array.new(4){|i|Array.new(4){|j|4.times.sum{|k|m[i][k]*o.m[k][j]}}});end
    def inverse
      a=m.each_with_index.map{|row,i|row.dup+Array.new(4){|j|i==j ? 1.0 : 0.0}}
      4.times do |i|
        k=(i...4).max_by{|j|a[j][i].abs};raise 'singular' if a[k][i].abs<1e-12
        a[i],a[k]=a[k],a[i];f=a[i][i];a[i].map!{|v|v/f}
        4.times{|j|next if i==j;f=a[j][i];8.times{|n|a[j][n]-=f*a[i][n]}}
      end
      self.class.new(a.map{|row|row[4,4]})
    end
  end
  class BoundingBox
    def initialize;@points=[];end
    def add(p);@points << p;self;end
    def empty?;@points.empty?;end
    def min;Point3d.new(*3.times.map{|i|@points.map{|p|p.to_a[i]}.min});end
    def max;Point3d.new(*3.times.map{|i|@points.map{|p|p.to_a[i]}.max});end
    def corner(i);Point3d.new(*3.times.map{|a|(i & (1<<a))==0 ? min.to_a[a] : max.to_a[a]});end
  end
end
module UI
  @messages=[]
  class << self
    attr_reader :messages
    def beep;end
    def messagebox(s);@messages << s;end
  end
end
module Sketchup
  class << self
    attr_accessor :model,:status_text
    def active_model;model;end
    def set_status_text(*args);end
    def format_length(x);(x*25.4).round(4).to_s+'mm';end
  end
  class Color
    attr_reader :red,:green,:blue
    def initialize(r,g,b,a=255);@red=r;@green=g;@blue=b;end
  end
  class Layer
    attr_accessor :visible
    def initialize;@visible=true;end
    def visible?;@visible;end
  end
  class Vertex
    attr_accessor :position
    def initialize(p);@position=p;end
    def valid?;true;end
  end
  class Edge
    attr_reader :vertices
    def initialize(a,b);@vertices=[a,b];end
    def start;vertices[0];end
    def end;vertices[1];end
    def valid?;true;end
  end
  class Entities < Array
    def transform_by_vectors(vs,vectors)
      vs.zip(vectors).each{|v,d|v.position=Geom::Point3d.new(*v.position.to_a.zip(d.to_a).map{|a,b|a+b})}
    end
  end
  class Definition
    attr_accessor :entities,:instances
    def initialize(entities);@entities=entities;@instances=[];end
    def bounds
      b=Geom::BoundingBox.new
      entities.each do |e|
        if e.is_a?(Edge);e.vertices.each{|v|b.add(v.position)}
        else;8.times{|i|b.add(e.bounds.corner(i))};end
      end
      b
    end
  end
  class ComponentInstance
    attr_accessor :definition,:transformation,:locked,:visible
    attr_reader :layer
    def initialize(defn,tr=Geom::Transformation.new)
      @definition=defn;defn.instances << self;@transformation=tr;@locked=false;@visible=true;@layer=Layer.new
    end
    def valid?;true;end
    def persistent_id;object_id;end
    def locked?;@locked;end
    def visible?;@visible;end
    def transform!(t);@transformation=t*@transformation;end
    def bounds;b=Geom::BoundingBox.new;8.times{|i|b.add(definition.bounds.corner(i).transform(transformation))};b;end
    def make_unique
      orig=definition;orig.instances.delete(self)
      edges=orig.entities.grep(Edge);map={};edges.flat_map(&:vertices).uniq.each{|v|map[v]=Vertex.new(Geom::Point3d.new(*v.position.to_a))}
      es=Entities.new
      orig.entities.each{|e|es << (e.is_a?(Edge) ? Edge.new(*e.vertices.map{|v|map[v]}) : e.class.new(e.definition,e.transformation))}
      @definition=Definition.new(es);@definition.instances << self;self
    end
  end
  class Group < ComponentInstance;end
  class InputPoint
    def initialize;@point=nil;end
    def pick(view,x,y,ref=nil);@point=view.point;@dof=view.dof;end
    def valid?;!@point.nil?;end
    def position;@point;end
    def degrees_of_freedom;@dof;end
    def tooltip;'Endpoint';end
    def draw(v);end
  end
end
class TestPicker
  attr_accessor :target
  def do_pick(x,y);end
  def best_picked;target;end
end
class TestView
  attr_accessor :point,:dof,:tooltip
  def initialize;@dof=0;@picker=TestPicker.new;end
  def invalidate;end
  def pick_helper;@picker;end
end
class TestModel
  attr_accessor :selection,:active_entities,:edit_transform,:active_path,:active_view
  attr_reader :commits,:aborts
  def initialize(items)
    @active_entities=Sketchup::Entities.new(items);@selection=[];@edit_transform=Geom::Transformation.new;@active_path=[];@active_view=TestView.new;@commits=0;@aborts=0
  end
  def select_tool(t);end
  def start_operation(*a)
    @snapshot=[];visit=lambda do |es|
      es.each do |e|
        if e.is_a?(Sketchup::Edge)
          e.vertices.each{|v|@snapshot << [v,:position,v.position]}
        else
          @snapshot << [e,:definition,e.definition];@snapshot << [e,:transformation,e.transformation];visit.call(e.definition.entities)
        end
      end
    end
    visit.call(active_entities)
  end
  def commit_operation;@commits+=1;end
  def abort_operation;@aborts+=1;@snapshot.reverse_each{|o,k,v|o.send(k.to_s+'=',v)};end
end
