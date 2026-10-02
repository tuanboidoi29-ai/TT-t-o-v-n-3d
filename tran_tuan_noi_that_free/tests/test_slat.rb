$LOAD_PATH.unshift(__dir__)
require_relative '../files/tran_tuan_noi_that/slat_wall_tool'
S=TranTuanNoiThat::SlatWall
$n=0
def check(v);raise "Failed check #{$n+1}" unless v;$n+=1;end
o=S.validate('mode'=>'backed','stock_width'=>0,'backing'=>nil,'width'=>1500)
check(o['mode']=='single' && o['width']==1500)
p=S.layout(5000,3000,{})
check(p[:panels].length==1 && p[:panels][0][:backing].nil?)
check(p[:panels][0][:slats].all?{|b|b[4]==3000})
%w[vertical horizontal].each do |direction|
 %w[manual auto count].each do |mode|
  o={'orientation'=>direction,'spacing_mode'=>mode,'gap'=>37,'count'=>7,'left'=>13,'right'=>27,'top'=>19,'bottom'=>31}
  a=S.layout(1020,760,o);b=S.layout_polygon([[0,0],[1020,0],[1020,760],[0,760]],o)
  check(a[:slat_count]==b[:slat_count]);check((a[:gap]-b[:gap]).abs<1e-6)
  boxes=a[:panels][0][:slats].map{|x,y,z,w,h,d|[x,y,x+w,y+h]}.sort
  polys=b[:panels][0][:slat_polygons].map{|poly|xs=poly.map(&:first);ys=poly.map(&:last);[xs.min,ys.min,xs.max,ys.max]}.sort
  check(boxes.flatten.zip(polys.flatten).all?{|x,y|(x-y).abs<1e-6})
  check(a[:gap]==37) if mode=='manual'
 end
end
%w[diag_right diag_left].each do |direction|
 p=S.layout_polygon([[0,0],[2000,0],[2000,3000],[0,3000]],'orientation'=>direction)
 check(p[:slat_count]>0 && p[:panels][0][:backing].nil?)
end
begin;S.layout_polygon([[0,0],[100,0],[100,100],[0,100]],'left'=>200);raise 'Expected failure';rescue RuntimeError=>e;check(e.message!='Expected failure');end
html=S.settings_html
check(!html.match?(/id=["'](?:stock_width|stock_length|backing|mode)["']/))
File.write('/tmp/slat214.js',html.scan(/<script>(.*?)<\/script>/m).flatten.join("\n"))
puts "#{$n} checks passed"
