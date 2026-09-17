require_relative 'cabinet_door_regression'
s=D.validate(D.defaults)
cells=D.cells_from_doors(D.layout(1000,800,s))
assert(cells==[[2.0,2.0,497.0,796.0],[501.0,2.0,497.0,796.0]])
# Whole horizontal split crosses both leaves, keeping the configured 2 mm gap.
a,lines=D.split_cells(cells,[200,400],1,false,s)
assert(a.length==4 && lines.length==2)
near(a[0][3],397);near(a[1][1],401);near(a[1][3],397)
# Internal mode splits only the hovered leaf; the other leaf is byte-for-byte equal.
b,lines=D.split_cells(cells,[200,400],1,true,s)
assert(b.length==3 && lines.length==1);assert(b.last==cells.last)
# Repeated nested subdivision is local; snapping near center is deterministic.
c,lines=D.split_cells(b,[251,200],0,true,s)
assert(c.length==4 && lines.length==1);near(c[0][2],247.5)
assert(c[2..-1]==b[1..-1])
# Cursor outside or in a gap cannot create a ghost cut.
assert(D.split_cells(cells,[500,400],1,true,s).first.nil?)
assert(D.split_cells(cells,[-10,400],1,false,s).first.nil?)
assert(D.split_cells(cells,[3,400],0,true,s).first.nil?)
# Geometry is translated once, preserving solids, dimensions and model-front depth.
doors=D.layout_cells(b,s)
assert(D.cells_from_doors(doors)==b)
doors.each { |d| d[:parts].each { |p| check_mesh(p[:faces]) } }
# All styles work after nested splits; a frame too large fails before mutation.
['Cánh khung','Cánh kính','Cánh soi huỳnh'].each do |style|
  out=D.layout_cells(b,s.merge('style'=>style))
  assert(D.cells_from_doors(out)==b)
  out.each { |d| d[:parts].each { |p| check_mesh(p[:faces]) } }
end
rejects { D.layout_cells([[0,0,30,100]],s.merge('style'=>'Cánh khung')) }
rejects { D.layout_cells(Array.new(61) { [0,0,300,500] },s) }
# Event contract: SHIFT toggles, key repeat does not double-toggle, settings control local scope,
# clicks keep preview only, Enter alone creates, Backspace restores previous leaves.
module UI
  def self.beep;end
end
module Sketchup
  class << self;attr_accessor :status_text;end
end
class SplitView
  def invalidate;end
end
t=D::Tool.allocate
{settings:s,cells:cells,candidate:nil,split_axis:0,internal:false,stage:2,hover:[200,400],history:[],split_lines:[]}.each { |k,v| t.instance_variable_set("@#{k}",v) }
def t.cache_world; @world=@doors; end
def t.create; @created=@doors; end
view=SplitView.new
t.onKeyDown(16,0,0,view);assert(t.instance_variable_get(:@split_axis)==1)
assert(t.instance_variable_get(:@candidate).length==4)
t.onKeyDown(16,2,0,view);assert(t.instance_variable_get(:@split_axis)==1)
t.instance_variable_set(:@internal,true);t.refresh_split;assert(t.instance_variable_get(:@internal))
assert(t.instance_variable_get(:@candidate).length==3)
preview=t.instance_variable_get(:@doors)
t.onKeyDown(13,0,0,view);assert(t.instance_variable_get(:@created).equal?(preview))
t.instance_variable_set(:@created,nil)
t.onLButtonDown(0,0,0,view)
assert(t.instance_variable_get(:@cells).length==3)
assert(t.instance_variable_get(:@created).nil?)
assert(t.instance_variable_get(:@candidate).nil?)
t.onKeyDown(8,0,0,view);assert(t.instance_variable_get(:@cells)==cells)
assert(t.instance_variable_get(:@history).empty?)
t.onKeyDown(13,0,0,view);assert(t.instance_variable_get(:@created).length==2)
puts "PASS #{$count} assertions including recursive split geometry and keyboard/click contract (API doubles only)."

module TranTuanNoiThat::CabinetDoor
  class << self
    attr_accessor :shown_tool
    def show(tool=nil); self.shown_tool=tool;end
  end
end
t.onKeyDown(9,0,0,view);assert(D.shown_tool.equal?(t))
assert(t.instance_variable_get(:@split_axis)==1)
class SplitModel
  def active_view;SplitView.new;end
end
t.instance_variable_set(:@model,SplitModel.new)
t.instance_variable_set(:@hover,nil)
t.instance_variable_set(:@cells,b)
t.configure(s.merge('thickness'=>20,'split_scope'=>'Ô đang trỏ'))
assert(t.instance_variable_get(:@cells)==b)
near(t.instance_variable_get(:@doors).first[:parts].first[:faces].flatten(1).map(&:last).max,20)
assert(t.instance_variable_get(:@internal))
t.configure(s.merge('split_scope'=>'Toàn vùng'))
assert(!t.instance_variable_get(:@internal))
puts "PASS #{$count} total assertions, including TAB settings and Apply updates preview."
