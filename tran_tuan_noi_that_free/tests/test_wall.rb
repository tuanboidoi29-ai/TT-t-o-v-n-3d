class Numeric; def mm;to_f/25.4;end;end
require_relative 'sketchup'
module Sketchup
 class InputPoint;def initialize(*);end;end
end
load File.expand_path('../files/tran_tuan_noi_that/wall_block.rb',__dir__)
tool=TranTuanNoiThat::VeTuongKhoi::WallTool.new(110,2800)
raise 'VCB disabled' unless tool.enableVCB?
p1=Geom::Point3d.new(0,0,0);p2=Geom::Point3d.new(1000.mm,0,0)
[[-55,55],[0,110],[-110,0]].each_with_index do |bounds,i|
 tool.instance_variable_set(:@mode_index,i)
 pts=tool.send(:wall_corners,p1,p2)
 raise 'width/offset' unless (pts.map(&:y).min-bounds[0].mm).abs<1e-8 && (pts.map(&:y).max-bounds[1].mm).abs<1e-8
end
puts 'Wall VCB and three alignment modes OK'
