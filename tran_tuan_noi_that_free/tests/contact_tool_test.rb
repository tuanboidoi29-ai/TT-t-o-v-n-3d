# encoding: UTF-8
load File.join(__dir__, 'upgrade_146_test.rb')
load ROOT+'/contact_tool.rb'
CONTACT=TranTuanNoiThat::ContactTool

check('Tạo Tiếp Diện normalizes INSTANCE and Tag to ABF names') do
  o=CONTACT.validate({
    'instance_name'=>'tiep dien tay nam',
    'tag_name'=>'tiep dien tay nam',
    'width'=>120,'height'=>50,'radius'=>6,'corner_mode'=>'all'
  })
  assert(o['instance_name']=='ABF_TIEP_DIEN_TAY_NAM')
  assert(o['tag_name']=='ABF_TIEP_DIEN_TAY_NAM')
  near(o['width'],120)
  near(o['height'],50)
  near(o['radius'],6)
end

check('rounded rectangle supports 4 corners top 2 bottom 2 and none') do
  none=CONTACT.rounded_rect_points(100,50,8,'none')
  all=CONTACT.rounded_rect_points(100,50,8,'all')
  top=CONTACT.rounded_rect_points(100,50,8,'top')
  bottom=CONTACT.rounded_rect_points(100,50,8,'bottom')
  assert(none.length==4)
  assert(all.length>none.length)
  assert(top.length>none.length)
  assert(bottom.length>none.length)
  assert(all.length>top.length)
  assert(all.length>bottom.length)
end

check('custom template scales to requested contact dimensions') do
  o=CONTACT.validate({
    'width'=>200,'height'=>100,
    'template'=>{'kind'=>'custom','points'=>[[-1,-1],[1,-1],[1,1],[-1,1]]}
  })
  pts=CONTACT.shape_points_mm(o)
  near(pts.map(&:first).min,-100)
  near(pts.map(&:first).max,100)
  near(pts.map(&:last).min,-50)
  near(pts.map(&:last).max,50)
end

check('contact preview follows cursor and rejects profile outside host Face') do
  face=[
    Geom::Point3d.new(0,0,0),
    Geom::Point3d.new(1000.mm,0,0),
    Geom::Point3d.new(1000.mm,500.mm,0),
    Geom::Point3d.new(0,500.mm,0)
  ]
  center=Geom::Point3d.new(500.mm,250.mm,0)
  plan=CONTACT.contact_plan(face,center,{
    'width'=>200,'height'=>100,'radius'=>0,'corner_mode'=>'none',
    'instance_name'=>'ABF_TEST','tag_name'=>'ABF_TEST',
    'template'=>{'kind'=>'rect','points'=>[]}
  },0)
  assert(plan[:valid])
  near(plan[:face_length_mm],1000)
  near(plan[:face_width_mm],500)
  near(plan[:rotation_deg],0)

  edge=Geom::Point3d.new(990.mm,250.mm,0)
  outside=CONTACT.contact_plan(face,edge,{
    'width'=>200,'height'=>100,'radius'=>0,'corner_mode'=>'none',
    'instance_name'=>'ABF_TEST','tag_name'=>'ABF_TEST',
    'template'=>{'kind'=>'rect','points'=>[]}
  },0)
  assert(!outside[:valid])
end

check('arrow/SHIFT direction rotations are present in tool source') do
  source=File.read(ROOT+'/contact_tool.rb',encoding:'UTF-8')
  assert(source.include?('KEY_LEFT = 37'))
  assert(source.include?('KEY_UP = 38'))
  assert(source.include?('KEY_RIGHT = 39'))
  assert(source.include?('KEY_DOWN = 40'))
  assert(source.include?('@rotation_deg = (@rotation_deg+90)%360'))
  assert(source.include?('KEY_TAB = 9'))
end

check('contact profile is real host topology and mirrored to ABF cutting lines for flattening') do
  source=File.read(ROOT+'/contact_tool.rb',encoding:'UTF-8')
  body=source.split('def create_contact',2)[1].split('def selection_template',2)[0]
  assert(body.include?('edge = entities.add_line(point,nxt)'))
  assert(body.include?('heal_contact_topology(edges)'))
  assert(body.include?('mirror_contact_to_abf_group(target,local_points,opts,plan)'))
  assert(source.include?("ABF_CUTTING_TAG = 'ABF_cuttingLines'"))
  assert(source.include?("ABF_CUTTING_GROUP = '_ABF_cuttingLines'"))
  assert(source.include?("group.set_attribute('ABF','is-cutting-lines',true)"))
  assert(source.include?("edge.set_attribute('ABF','is-cutting-lines',true)"))
  assert(source.include?('def repair_selected_contacts'))
  assert(source.include?('SỬA TIẾP DIỆN ABF ĐÃ CHỌN'))
end

check('Tạo Tiếp Diện supports drawing and importing profiles from SketchUp') do
  html=CONTACT.dialog_html
  assert(html.include?('THƯ VIỆN BIÊN DẠNG'))
  assert(html.include?('VẼ TRỰC TIẾP'))
  assert(html.include?('LẤY TỪ SKETCHUP'))
  assert(html.include?('TẠO MỚI'))
  assert(html.include?('LƯU MẪU'))
  assert(html.include?('XÓA MẪU'))
  assert(html.include?('Bo 4 góc'))
  assert(html.include?('Bo 2 góc trên'))
  assert(html.include?('Bo 2 góc dưới'))
  assert(html.include?('INSTANCE'))
  assert(html.include?('Tag'))
  assert(html.include?('SHIFT xoay 90°'))
  assert(html.include?('TAB mở thư viện/cài đặt'))
end

check('Tạo Tiếp Diện source can import selected Face or closed Edges') do
  source=File.read(ROOT+'/contact_tool.rb',encoding:'UTF-8')
  assert(source.include?('def selection_template'))
  assert(source.include?('face.outer_loop.vertices.map(&:position)'))
  assert(source.include?('def ordered_edge_loop'))
  assert(source.include?("Hãy chọn 1 Face hoặc một chuỗi Edge kín."))
end

check('Tạo Tiếp Diện accepts Group and Component targets') do
  g=board(600,400,17.5)
  assert(CONTACT.valid_container?(g))
  ci=Sketchup::ComponentInstance.new(g.definition)
  assert(CONTACT.valid_container?(ci))
end



check('Tạo Tiếp Diện auto-detects nested Face without relying on face.parent') do
  source=File.read(ROOT+'/contact_tool.rb',encoding:'UTF-8')
  assert(source.include?('def target_and_transform_from_path'))
  assert(source.include?('containers = rows.select { |entity| ContactTool.valid_container?(entity) }'))
  assert(source.include?('target = containers.last'))
  assert(source.include?('active_target = Array(active_path).last'))
  assert(source.include?('transform = transform * entity.transformation'))
  assert(!source.include?('def face_owner(face,path)'))
end

check('Tạo Tiếp Diện validates cursor on detected Face and draws Face outline preview') do
  source=File.read(ROOT+'/contact_tool.rb',encoding:'UTF-8')
  assert(source.include?('return nil unless ContactTool.point_in_polygon?(cursor_2d,polygon_2d)'))
  assert(source.include?('view.draw(GL_LINE_LOOP, face_outline)'))
  assert(source.include?('ĐÃ NHẬN FACE'))
end

puts "CONTACT TOOL REGRESSIONS COMPLETE"
