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
tool = mod::Tool.new(false)
tool.instance_variable_set(:@state,:place)
tool.instance_variable_set(:@points,[[0,0,0],[18.mm,7.mm,0],[600.mm,0,0]])
tool.instance_variable_set(:@cursor,[0,0,200.mm])
tool.rebuild
specs = tool.instance_variable_get(:@specs)
assert(specs.size == 3,'two details and total')
assert(specs.all? { |a,b,o,k| a.y == b.y && a.z == b.z && o.x == 0 },'projected aligned dimension perpendicular offset')
assert(specs.last.last == :total,'outer overall dimension')
assert(specs.last[2].z > specs.first[2].z,'overall outside details')
tool.instance_variable_set(:@cursor,[0,0,-200.mm]); tool.rebuild
assert(tool.instance_variable_get(:@specs).all? { |s| s[2].z < 0 },'opposite placement')
auto = mod::Tool.new(true)
auto.instance_variable_set(:@state,:place)
auto.instance_variable_set(:@lo,[0,0,0]);auto.instance_variable_set(:@hi,[600.mm,550.mm,800.mm])
auto.instance_variable_set(:@values,[[0,18.mm,582.mm,600.mm],[0,550.mm],[0,18.mm,782.mm,800.mm]])
auto.instance_variable_set(:@cursor,[-120.mm,-120.mm,-120.mm])
3.times do |plane|
 auto.instance_variable_set(:@plane,plane);auto.rebuild
 specs=auto.instance_variable_get(:@specs)
 assert(specs.count { |s| s.last == :total } == 3,"three overall dimensions plane #{plane}")
 assert(specs.all? { |a,b,o,k| ((b.x-a.x)*o.x+(b.y-a.y)*o.y+(b.z-a.z)*o.z).abs < 1e-6 },'perpendicular offsets')
end
puts 'Geometry checks passed: projection, offset sides, total lanes and three planes'
