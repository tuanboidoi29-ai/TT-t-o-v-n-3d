$LOAD_PATH.unshift(__dir__)
require 'sketchup'
class Numeric;def mm;to_f/25.4;end;end
module UI;def self.messagebox(s);raise s;end;end
module Sketchup;def self.vcb_value=(s);end;end
require_relative '../files/tran_tuan_noi_that/divide_boards'
D=TranTuanNoiThat::DivideBoards
t=D::Tool.allocate
{source:true,direction:X_AXIS,clear:1000.mm,thickness:18.mm,mouse:[0,0]}.each{|k,v|t.instance_variable_set("@#{k}",v)}
def t.update_preview(*);end
v=Object.new;def v.invalidate;end
n=0
['/','/1','/2','/ 2','/3','/6'].zip([1,1,1,1,2,5]).each do |input,count|
 t.onUserText(input,v);raise input unless t.instance_variable_get(:@count)==count;n+=1
 shifts,gap=D.spacing(1000.mm,18.mm,count)
 # Each interval of open space must match, including both ends.
 gaps=[shifts.first-18.mm]+shifts.each_cons(2).map{|a,b|b-a-18.mm}+[1000.mm-shifts.last]
 raise 'gap mismatch' unless gaps.all?{|g|(g-gap).abs<1e-8};n+=1
end
t.onUserText('250',v);raise unless (t.instance_variable_get(:@distance)-250.mm).abs<1e-8 && t.instance_variable_get(:@count).nil?;n+=1
puts "#{n} checks passed"
subject=[[0,0],[100,0],[100,100],[0,100]]
[[[[40,-10],[60,-10],[60,110],[40,110]],8000],[[[20,20],[80,20],[80,80],[20,80]],6400],[[[200,200],[210,200],[210,210],[200,210]],10000]].each do |cut,expected|
 result=D.subtract_polygon(subject,cut)
 area=result.sum{|p|D.area2(p).abs/2}
 raise "area #{area}" unless (area-expected).abs<1e-6
 raise 'Missing boundary' if D.boundary_segments(result).empty?
 n+=2
end
triangles=[[[0,0],[100,0],[100,100]],[[0,0],[100,100],[0,100]]]
segments=D.boundary_segments(triangles)
raise 'Diagonal retained' unless segments.length==4
n+=1
puts "#{n} geometry/input checks passed"
loops=D.boundary_loops(D.boundary_segments(triangles))
raise 'Not one rectangle' unless loops.length==1 && loops[0].length==4
n+=1
cut=[[20,20],[80,20],[80,80],[20,80]]
parts=D.subtract_polygon(subject,cut).map{|p|D.area2(p)<0 ? p.reverse : p}
loops=D.boundary_loops(D.boundary_segments(parts))
raise 'Hole lost' unless loops.length==2 && loops.count{|p|D.area2(p)>0}==1
n+=1
puts "#{n} closed-boundary checks passed"
# A crossing shelf separates two regions; neither gets triangulation edges.
parts=D.subtract_polygon(subject,[[40,-10],[60,-10],[60,110],[40,110]])
loops=D.boundary_loops(D.boundary_segments(parts))
raise 'Separated regions incorrect' unless loops.length==2 && loops.all?{|p|p.length==4}
n+=1
# A notch touching the outside must remain in the final outline.
parts=D.subtract_polygon(subject,[[40,50],[60,50],[60,110],[40,110]])
loops=D.boundary_loops(D.boundary_segments(parts))
raise 'Notch lost' unless loops.length==1 && loops[0].length==8
n+=1
puts "#{n} final checks passed"
parts=D.subtract_polygon(subject,[[40,-10],[60,-10],[60,110],[40,110]])
parts.map!{|p|D.area2(p)<0 ? p.reverse : p}
left=D.compartment_pieces(parts,[20,50]);right=D.compartment_pieces(parts,[80,50])
raise 'Wrong left bay' unless left.flatten(1).all?{|p|p[0]<=40.00001}
raise 'Wrong right bay' unless right.flatten(1).all?{|p|p[0]>=59.99999}
begin;D.compartment_pieces(parts,[50,50]);raise 'Accepted obstruction';rescue RuntimeError=>e;raise if e.message=='Accepted obstruction';end
n+=3
puts "#{n} compartment checks passed"
