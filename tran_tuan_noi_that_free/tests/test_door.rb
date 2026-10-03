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
class Geom::Vector3d
 def transform(t);self;end
end
class Geom::Point3d
 def self.linear_combination(a,p,b,q);new(a*p.x+b*q.x,a*p.y+b*q.y,a*p.z+b*q.z);end
end
V=Struct.new(:position);E=Struct.new(:start,:end);L=Struct.new(:vertices,:edges)
class SnapFace < Sketchup::Face
 attr_reader :outer_loop
 def initialize(x)
  vs=[[x,0,0],[x+18,0,0],[x+18,800,0],[x,800,0]].map{|p|V.new(Geom::Point3d.new(*p))}
  @outer_loop=L.new(vs,vs.each_with_index.map{|v,i|E.new(v,vs[(i+1)%4])})
 end
 def normal;Z_AXIS;end
end
def Geom.intersect_line_plane(ray,plane);ray[0];end
view.define_singleton_method(:pickray){|x,y|[Geom::Point3d.new(x,y,0),Z_AXIS]}
view.define_singleton_method(:screen_coords){|p|p}
view.define_singleton_method(:camera){Struct.new(:direction).new(Z_AXIS)}
f1=SnapFace.new(0);f2=SnapFace.new(600);tr=Geom::Transformation.new
[600,609,618].each do |x|
 snap=t.send(:nearest_board_snap,view,x,0,[[f1,tr],[f2,tr]],true)
 check.call(snap && snap[1].x==x && snap[2]==f2)
end
snap=t.send(:nearest_board_snap,view,609,400,[[f2,tr]],true)
check.call(snap && snap[4]=='Tâm mặt hồi')
check.call(t.send(:nearest_board_snap,view,300,300,[[f1,tr],[f2,tr]],true).nil?)
puts "#{n} total checks passed"

[137,369,711].each do |y|
 [600,609,618].each do |x|
  snap=t.send(:nearest_board_snap,view,x,y,[[f2,tr]],true)
  check.call(snap && (snap[1].x-x).abs<1e-8 && (snap[1].y-y).abs<1e-8)
 end
end
points=[[0,0,0],[800,0,0],[800,18,0],[0,18,0]].map{|a|Geom::Point3d.new(*a)}
rails=t.send(:board_rail_candidates,view,327,9,points)
check.call(rails.map{|a|a[1].y}.sort==[0,9,18])
check.call(rails.all?{|a|a[1].x==327})
t.onUserText('/ 3',view);check.call(t.instance_variable_get(:@received)==3)
# A held Shift changes direction exactly once, regardless of repeat count.
def t.set_split_direction(d,lock);@options['split_direction']=d;end
t.instance_variable_set(:@options,{'split_direction'=>'Dọc'})
t.onKeyDown(16,5,0,view);check.call(t.instance_variable_get(:@options)['split_direction']=='Ngang')
t.onKeyDown(16,6,0,view);check.call(t.instance_variable_get(:@options)['split_direction']=='Ngang')
t.onKeyUp(16,1,0,view)
t.onKeyDown(16,1,0,view);check.call(t.instance_variable_get(:@options)['split_direction']=='Dọc')
puts "#{n} total checks passed"
# P2 chooses XY, XZ, YZ regardless of which corner started the diagonal.
[[[600,800,0],Z_AXIS],[[600,0,800],Y_AXIS],[[0,600,800],X_AXIS]].each do |values,expected|
 [-1,1].each do |sign|
  delta=Geom::Vector3d.new(*values.map{|v|v*sign})
  normal=t.send(:p2_direction_normal,delta,[X_AXIS,Y_AXIS,Z_AXIS],Z_AXIS)
  check.call(normal && normal.dot(expected).abs>0.999)
 end
end
check.call(t.send(:p2_direction_normal,Geom::Vector3d.new(600,0,0),[X_AXIS,Y_AXIS,Z_AXIS],Z_AXIS).nil?)
rotated=Geom::Vector3d.new(1,-1,0).normalize
delta=Geom::Vector3d.new(600,600,800)
check.call(t.send(:p2_direction_normal,delta,[rotated],Y_AXIS).dot(rotated).abs>0.999)
puts "#{n} total checks passed"
module TranTuanNoiThat;NAME="TT test";end
u=T.allocate
u.instance_variable_set(:@state,:ready)
u.instance_variable_set(:@cells,[[0,1,0,1]])
u.instance_variable_set(:@options,{'gap_vertical'=>2,'gap_horizontal'=>4,'split_direction'=>'Dọc'})
def u.valid_region?;true;end
def u.adjusted_bounds;[0,600,0,800];end
def u.rebuild_preview;@doors=@cells.map(&:dup);end
def D.send_settings;end
(1..6).each do |count|
 check.call(u.send(:set_equal_door_count,count))
 check.call(u.instance_variable_get(:@cells).length==count)
end
u.send(:set_split_direction,'Ngang',true)
check.call(u.instance_variable_get(:@cells).length==6)
check.call(u.instance_variable_get(:@cells).all?{|c|c[0]==0 && c[1]==1})
u.onReturn(view)
check.call(u.instance_variable_get(:@state)==:ready)
def u.create_doors;@created=true;end
def u.reset_all;@state=:pick_p1;end
def u.update_status;end
u.onLButtonDown(0,0,0,view)
check.call(u.instance_variable_get(:@created)==true)
puts "#{n} final checks passed"
w=T.allocate
w.instance_variable_set(:@state,:ready)
w.instance_variable_set(:@cells,[[0,1,0,1]])
w.instance_variable_set(:@options,{'gap_vertical'=>2,'gap_horizontal'=>4,'split_direction'=>'Ngang'})
def w.valid_region?;true;end
def w.adjusted_bounds;[0,600,0,800];end
def w.rebuild_preview;@doors=@cells.map(&:dup);end
w.instance_variable_set(:@last_ready_mouse,[100,100])
check.call(w.send(:set_equal_door_count,2))
original=w.instance_variable_get(:@cells).map(&:dup)
w.send(:advance_division_target,103,103)
check.call(w.instance_variable_get(:@numeric_count)==2)
w.send(:advance_division_target,200,200)
w.instance_variable_set(:@active_cell_index,1)
w.send(:set_split_direction,'Dọc',true)
check.call(w.send(:set_equal_door_count,3))
check.call(w.instance_variable_get(:@cells).length==4)
check.call(w.instance_variable_get(:@cells).first==original.first)
check.call(w.send(:set_equal_door_count,4))
check.call(w.instance_variable_get(:@cells).length==5)
check.call(w.instance_variable_get(:@cells).first==original.first)
puts "#{n} nested preview checks passed"
