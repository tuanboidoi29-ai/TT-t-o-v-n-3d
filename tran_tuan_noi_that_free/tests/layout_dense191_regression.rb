require_relative 'layout_detail189_regression'
before=$count
options=T.normalize('views'=>['front','cut_front'],'stats'=>false,'dim_font'=>18)
bb=Box.new(1000/25.4,600/25.4,2000/25.4)
# Fifty adjacent narrow projected parts force more than four label lanes.
parts=50.times.map{|i|solid_part(i,0,0,i+1,600,2000)}
job={bounds:bb,name:'Dense MDF test',detail_parts:parts,stats:{rows:[]}}
doc=T.build_document(job,'sample.skp',{'front'=>2,'cut_front'=>5},options)
assert(doc.pages.size>2,'crowded DIM creates extra pages instead of stopping')
vp=doc.entities.map(&:first).grep(Layout::SketchUpModel)
assert(vp.length==doc.pages.length && vp.all?{|v|v.scale==0.05},'all supplementary pages keep real viewport and exact scale')
chains=doc.entities.map(&:first).grep(Layout::LinearDimension).select{|d|d.style.stroke_width==0.25}
assert(chains.size==100,'all 50 segment dimensions on each of two views retained exactly once')
assert(chains.all?{|d|(Math.hypot(d.a.x-d.b.x,d.a.y-d.b.y)/d.scale*25.4-1).abs<1e-6},'every dimension still measures 1mm')
assert(T.instance_variable_get(:@last_document_focus).length==doc.pages.length,'preview focus metadata covers every supplementary page')
doc.pages.each do |page|
 v=doc.entities.find{|e,l,p|p==page&&e.is_a?(Layout::SketchUpModel)}.first
 expected=page.name.include?('cắt') ? 5 : 2
 assert(v.current_scene==expected,'extra page reuses correct front/section scene')
 offsets=doc.entities.select{|e,l,p|p==page && e.is_a?(Layout::LinearDimension)&&e.style.stroke_width==0.25}.map{|e,l,p|e.start_extent_point.y-e.a.y}.uniq
 assert(offsets.size<=4,'at most four lanes per page')
end
puts "PASS #{$count-before} dense dimension pagination checks; native rendering not tested."
