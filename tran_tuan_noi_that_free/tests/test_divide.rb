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
