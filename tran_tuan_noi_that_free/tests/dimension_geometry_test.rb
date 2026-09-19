class Numeric
  def mm; self / 25.4; end
end
module Geom
  class Vector3d
    attr_accessor :x,:y,:z
    def initialize(x,y,z); @x,@y,@z=x,y,z; end
    def length=(n)
      scale = n / Math.sqrt(x*x+y*y+z*z)
      @x*=scale; @y*=scale; @z*=scale
    end
    def reverse!; @x=-x; @y=-y; @z=-z; self; end
    def to_a; [x,y,z]; end
  end
  class Point3d < Vector3d
    def offset(v,n); self.class.new(x+v.x*n,y+v.y*n,z+v.z*n); end
  end
end
module Sketchup
  class InputPoint; end
end
require_relative '../files/tran_tuan_noi_that/dimension_tool'
def assert(v,message); raise message unless v; end
mod = TranTuanNoiThat::DetailDimensions
tool = mod::Tool.new
tool.instance_variable_set(:@lo,[0,0,0])
tool.instance_variable_set(:@hi,[600.mm,550.mm,800.mm])
tool.instance_variable_set(:@values,[[0,18.mm,582.mm,600.mm],[0,550.mm],[0,18.mm,782.mm,800.mm]])
tool.instance_variable_set(:@front,0)
tool.instance_variable_set(:@openings,[[18.mm,582.mm,18.mm,782.mm]])
[-120,1200].each do |side|
 tool.instance_variable_set(:@cursor,[side.mm,0,side.mm]);tool.rebuild
 specs=tool.instance_variable_get(:@specs)
 assert(specs.count { |s| s.last == :total } == 3,'three overall dimensions')
 assert(specs.count { |s| s.last == :opening } == 1,'clear width dimension')
 specs.each do |a,b,o,kind|
  delta=[b.x-a.x,b.y-a.y,b.z-a.z]
  assert(delta.count { |v| v.abs > 1e-6 } == 1,'single-axis dimension')
  assert((delta.zip(o.to_a).map { |x,y| x*y }.inject(0,:+)).abs < 1e-6,'perpendicular offset')
  assert(a.y == 0 && b.y == 0,'front plane') unless kind == :total || (b.y-a.y).abs > 1e-6
 end
end
puts 'Front projection, horizontal/vertical axes, perpendicular offsets and three totals passed'

mod.options['horizontal']=false
mod.options['height']=false
mod.options['depth']=false
mod.options['total']=false
tool.rebuild
assert(tool.instance_variable_get(:@specs).all? { |s| s.last == :opening },'opening-only filter')
mod.options['opening']=false
mod.options['depth']=true
tool.rebuild
assert(tool.instance_variable_get(:@specs).all? { |a,b,o,k| b.y != a.y && b.x == a.x && b.z == a.z },'depth-only filter')
puts 'Dimension type filters passed'
