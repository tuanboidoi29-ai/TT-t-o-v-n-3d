$LOAD_PATH.unshift(__dir__)
require 'sketchup'
class Numeric
 def mm;to_f;end
end
module Sketchup
 def self.status_text=(v);end
end
module UI
 def self.beep;end
end
module TranTuanNoiThat;ROOT=File.expand_path('../files/tran_tuan_noi_that',__dir__);end
require_relative '../files/tran_tuan_noi_that/door_standard_tool'
D=TranTuanNoiThat::DoorStandard
T=D::Tool
n=0
check=->(v){raise "check #{n+1}" unless v;n+=1}
t=T.allocate
t.instance_variable_set(:@origin,ORIGIN);t.instance_variable_set(:@normal,Z_AXIS);t.instance_variable_set(:@u,X_AXIS);t.instance_variable_set(:@v,Y_AXIS)
[[[0,0],[600,800]],[[600,800],[0,0]],[[0,800],[600,0]],[[600,0],[0,800]]].each do |a,b|
 t.send(:build_region_from_points,Geom::Point3d.new(*a,0),Geom::Point3d.new(*b,0))
 r=t.instance_variable_get(:@region);check.call(r[:width]==600 && r[:height]==800 && r[:u0]==0 && r[:v0]==0)
end
def t.adjusted_bounds;[0,600,0,800];end
t.instance_variable_set(:@options,{'gap_vertical'=>2,'gap_horizontal'=>3})
['Dọc','Ngang'].each do |direction|
 [[0,1,0,1],[0.2,0.8,0.1,0.7]].each do |cell|
  [1,2,3,4,12,64].each do |count|
   parts=t.send(:equal_cell_parts,cell,count,direction);axis=direction=='Dọc' ? 0 : 2;span=axis==0 ? 600 : 800;gap=axis==0 ? 2 : 3
   visible=parts.map{|c|[c[axis]*span+(c[axis]>0.000001 ? gap/2.0 : 0),c[axis+1]*span-(c[axis+1]<0.999999 ? gap/2.0 : 0)]}
   widths=visible.map{|a,b|b-a};check.call(widths.max-widths.min<1e-8)
   check.call(visible.each_cons(2).all?{|a,b|(b[0]-a[1]-gap).abs<1e-8})
  end
 end
end
# VCB text updates preview only; plain Enter has its separate callback.
t.instance_variable_set(:@state,:ready)
def t.set_equal_door_count(n);@received=n;n<=64;end
view=Object.new;def view.invalidate;end
t.onUserText('/12',view);check.call(t.instance_variable_get(:@received)==12)
check.call(t.onKeyDown(191,1,0,view)==false)
check.call(t.onKeyDown(51,1,0,view)==false)
check.call(t.onKeyDown(13,1,0,view)==false)
puts "#{n} door checks passed"
# Exact corner/edge hits resolve an adjacent face instead of rejecting P1.
class Geom::Vector3d
 def transform(t);self;end
end
face=Sketchup::Face.new
def face.normal;Z_AXIS;end
edge=Object.new;edge.define_singleton_method(:faces){[face]}
helper=Object.new
helper.define_singleton_method(:do_pick){|*a|nil}
helper.define_singleton_method(:count){1}
helper.define_singleton_method(:path_at){|i|[edge]}
helper.define_singleton_method(:transformation_at){|i|Geom::Transformation.new}
view.define_singleton_method(:pick_helper){helper}
view.define_singleton_method(:camera){Struct.new(:direction).new(Z_AXIS)}
ip=Object.new;def ip.pick(*);end;def ip.valid?;true;end;def ip.position;ORIGIN;end
t.instance_variable_set(:@ip,ip)
def t.nearest_face_snap_point(view,face,tr,x,y,fallback);fallback;end
def t.setup_plane(face,tr,point,view);@face=face;end
check.call(t.send(:pick_first_point,view,0,0)==ORIGIN)
check.call(t.instance_variable_get(:@face)==face)
puts "#{n} total door checks passed"
