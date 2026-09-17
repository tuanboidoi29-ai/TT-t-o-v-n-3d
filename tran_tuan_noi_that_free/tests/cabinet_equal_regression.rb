require_relative 'cabinet_split_regression'
SB_VCB_VALUE=2 unless defined?(SB_VCB_VALUE)
module Sketchup
  def self.set_status_text(*args);end
end
s=D.validate(D.defaults)
cells=[[2.0,2.0,900.0,800.0],[904.0,2.0,400.0,800.0]]
out,lines=D.equal_cells(cells,[200,200],0,3,true,s)
assert(out.length==4 && lines.length==2)
3.times { |i| near(out[i][2],896.0/3) }
near(out[1][0]-out[0][0]-out[0][2],2)
near(out[2][0]+out[2][2],902)
assert(out.last==cells.last)
a,_=D.equal_cells(cells,[200,200],1,4,true,s)
4.times { |i| near(a[i][3],198.5) }
near(a[3][1]+a[3][3],802)
b,_=D.equal_cells(cells,[200,200],0,2,false,s);assert(b.length==4)
rejects { D.equal_cells(cells,nil,0,3,true,s) }
rejects { D.equal_cells(cells,[903,300],0,3,true,s) }
rejects { D.equal_cells(cells,[200,200],0,1,true,s) }
rejects { D.equal_cells(cells,[200,200],0,61,true,s) }
rejects { D.equal_cells(cells,[200,200],0,60,false,s) }
D.layout_cells(out,s).each { |d| d[:parts].each { |p| check_mesh(p[:faces]) } }
t=D::Tool.allocate
{settings:s,cells:cells,stage:2,hover:[200,200],history:[],split_axis:0,internal:true,split_lines:[]}.each { |k,v| t.instance_variable_set("@#{k}",v) }
def t.cache_world;@world=@doors;end
def t.create;@created=@doors;end
v=SplitView.new
assert(t.enableVCB?)
assert(t.onKeyDown(191,1,0,v)==false)
assert(t.onKeyDown(51,1,0,v)==false)
assert(t.onKeyDown(13,1,0,v)==false)
assert(t.instance_variable_get(:@created).nil?)
t.onUserText('/3',v);assert(t.instance_variable_get(:@candidate).length==4)
assert(!t.instance_variable_get(:@vcb_typing))
# Changing N replaces preview, never compounds it on previously previewed leaves.
t.onUserText('/4',v);assert(t.instance_variable_get(:@candidate).length==5)
t.onKeyDown(16,1,0,v);near(t.instance_variable_get(:@candidate)[0][3],198.5)
# Hover movement does not relocate a numeric split.
t.instance_variable_set(:@hover,[1000,100]);t.refresh_split
assert(t.instance_variable_get(:@candidate).last==cells.last)
preview=t.instance_variable_get(:@doors)
t.onKeyDown(13,1,0,v);assert(t.instance_variable_get(:@created).equal?(preview))
t.instance_variable_set(:@created,nil)
t.onUserText('/0',v);assert(t.instance_variable_get(:@vcb_typing))
assert(t.onKeyDown(13,1,0,v)==false);assert(t.instance_variable_get(:@created).nil?)
t.onUserText('/3',v);t.onLButtonDown(0,0,0,v)
assert(t.instance_variable_get(:@cells).length==4)
assert(t.instance_variable_get(:@equal_count).nil?)
assert(t.instance_variable_get(:@history).length==1)
puts "PASS #{$count} total assertions, including /N preview and Enter text submission."
