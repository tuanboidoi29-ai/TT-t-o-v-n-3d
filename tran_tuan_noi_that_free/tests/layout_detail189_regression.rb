require_relative 'layout_technical189_regression'
module TranTuanNoiThat::LayoutStats
  def tt_v081_effective_offsets(bb,mm)
    {front:[mm/25.4,bb.height-0.5/25.4].min,left:[mm/25.4,bb.width-0.5/25.4].min,right:[mm/25.4,bb.width-0.5/25.4].min}
  end
end
class Box
  def min;Geom::Point3d.new(0,0,0);end
  def max;Geom::Point3d.new(width,height,depth);end
end
def solid_part(x0,y0,z0,x1,y1,z1)
  pts=8.times.map{|i|Geom::Point3d.new(((i&1)==0 ? x0:x1)/25.4,((i&2)==0 ? y0:y1)/25.4,((i&4)==0 ? z0:z1)/25.4)}
  edges=[];8.times{|i|[1,2,4].each{|mask|edges<<[pts[i],pts[i^mask]] if i<(i^mask)}}
  {points:pts,edges:edges}
end
opts=T.normalize({})
assert(opts['cut_mm']==20 && opts['xray_views'].size==8,'20mm default and independent X-ray for all views')
rejects('invalid scope'){T.normalize('scope'=>'other')}
rejects('invalid xray'){T.normalize('xray_views'=>['rear'])}
rejects('invalid title font'){T.normalize('title_font'=>4)}
bb=Box.new(1000/25.4,600/25.4,2000/25.4)
door=solid_part(0,0,0,1000,18,2000)
assert(T.clipped_detail_points(door,'cut_front',bb,opts).empty?,'20mm front cut removes 18mm door from dimensions')
shelf=solid_part(17.5,0,1000,982.5,600,1017.5)
clipped=T.clipped_detail_points(shelf,'cut_front',bb,opts)
assert((clipped.map(&:y).min*25.4-20).abs<1e-6 && (clipped.map(&:y).max*25.4-600).abs<1e-6,'intersect edges at true cut location')
assert((T.clipped_detail_points(shelf,'cut_front',bb,opts.merge('cut_mm'=>50)).map(&:y).min*25.4-50).abs<1e-6,'custom cut depth changes dimension geometry')
assert((T.clipped_detail_points(shelf,'cut_right',bb,opts).map(&:x).max*25.4-980).abs<1e-6,'right cut retains inner side')
assert((T.clipped_detail_points(shelf,'cut_left',bb,opts).map(&:x).min*25.4-20).abs<1e-6,'left cut retains inner side')
parts=[solid_part(0,0,0,17.5,600,2000),solid_part(982.5,0,0,1000,600,2000),shelf,door]
job={bounds:bb,name:'Tủ MDF',detail_parts:parts,stats:{rows:[]}}
opts=opts.merge('views'=>['front','cut_front'],'stats'=>false,'drawing'=>'Tủ bếp A')
doc=T.build_document(job,'sample.skp',{'front'=>2,'cut_front'=>5},opts)
dims=doc.entities.map(&:first).grep(Layout::LinearDimension)
measure=dims.map{|d|(Math.hypot(d.a.x-d.b.x,d.a.y-d.b.y)/d.scale*25.4).round(1)}
assert(measure.include?(17.5) && measure.include?(965.0) && measure.include?(982.5),'detail chain includes board thickness, clear width and vertical subdivisions')
assert(measure.count(1000.0)>=2 && measure.count(2000.0)==2,'both pages retain correct total width and height')
assert(doc.entities.map(&:first).grep(Layout::SketchUpModel).all?{|v|v.render_mode==2},'X-ray uses Hybrid viewport')
chains=T.chain_segments([0,1,1.00001,2],0.05)
assert(chains==[[0,1],[1,2]],'duplicate co-planar boundaries do not make tiny false dimensions')
lanes=T.dimension_lanes([[0,0.02],[0.02,0.04],[0.04,0.06]],0.05,10)
assert(lanes.map(&:last).uniq.size>1,'short dimension labels use separate lanes')
assert(T.safe_filename('Bếp/A:*?')=='Bếp_A___','drawing name sanitized for Windows output')
# Real recursive traversal contract, including parent rotation and translation.
module Geom
  class Transformation
    attr_reader :m
    def initialize(m=nil);@m=m||[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]];end
    def *(other);Transformation.new(Array.new(4){|r|Array.new(4){|c|4.times.sum{|k|m[r][k]*other.m[k][c]}}});end
  end
  class Point3d
    def transform(tr);v=[x,y,z,1];Point3d.new(*3.times.map{|r|4.times.sum{|k|tr.m[r][k]*v[k]}});end
  end
end
module Sketchup
  Face=Class.new { def valid?;true;end }
  Vertex=Struct.new(:position)
  Edge=Struct.new(:start,:end) { def valid?;true;end }
end
Container=Struct.new(:transformation,:children,:name,:hidden_flag) do
  def valid?;true;end
  def hidden?;!!hidden_flag;end
  def layer;Struct.new(:visible?).new(true);end
end
module TranTuanNoiThat::LayoutStats
  def container?(e);e.is_a?(Container);end
  def child_entities(e);e.children;end
  def tt_scope_name(e,i);e.name;end
  def tt_entity_id(e);e.object_id;end
  def tt_stats_for_roots(roots,label);{rows:[],total_pieces:roots.length};end
end
edge=Sketchup::Edge.new(Sketchup::Vertex.new(Geom::Point3d.new(0,0,0)),Sketchup::Vertex.new(Geom::Point3d.new(10,0,0)))
child=Container.new(Geom::Transformation.new,[Sketchup::Face.new,edge],'Ván',false)
parent=Container.new(Geom::Transformation.new([[0,-1,0,50],[1,0,0,60],[0,0,1,0],[0,0,0,1]]),[child],'Tủ A',false)
other=Container.new(Geom::Transformation.new,[],'Tủ B',false)
scanned=T.detail_parts([parent])
assert(scanned.first[:points].map{|p|[p.x,p.y,p.z]}==[[50,60,0],[50,70,0]],'nested parent rotation correctly transforms detail geometry')
child.hidden_flag=true;assert(T.detail_parts([parent]).empty?,'hidden geometry excluded from detail dimensions');child.hidden_flag=false
model=Struct.new(:entities,:selection).new([parent,other],[parent])
assert(T.export_jobs(model,opts.merge('scope'=>'selected')).map{|j|j[:name]}==['Tủ A'],'selected scope only')
assert(T.export_jobs(model,opts.merge('scope'=>'all')).map{|j|j[:name]}==['Tủ A','Tủ B'],'all scope ignores current selection and makes separate jobs')
model.selection=[];rejects('empty selected scope must not silently export all'){T.export_jobs(model,opts.merge('scope'=>'selected'))}
puts "PASS #{$count} cumulative document/detail geometry/scope checks; native renderer not tested."
