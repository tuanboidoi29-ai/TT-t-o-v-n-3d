# encoding: UTF-8
load File.join(__dir__, 'upgrade_146_test.rb')
load ROOT+'/led_tool.rb'
LED=TranTuanNoiThat::LedTool

check('LED defaults keep exact CNC INSTANCE and Tag convention') do
  o=LED.normalize({})
  assert(o['cnc_instance']=='ABF_RANHLED')
  assert(o['cnc_tag']=='ABF_ranhled')
  assert(o['groove_width']==10.0)
  assert(o['simulate']==true && o['cnc']==true)
  assert(o['brightness']==100.0)
  assert(o['light_distance']==80.0)
  assert(o['light_spread']==40.0)
  assert(o['quantity']==1)
  assert(o['spacing']==50.0)
  assert(o['led_color']=='#ffe08a')
  assert(LED.normalize({'cnc_instance'=>'ranh led phong khach'})['cnc_instance']=='ABF_RANH_LED_PHONG_KHACH')
  assert(LED.normalize({'cnc_tag'=>'ranhled_phongkhach'})['cnc_tag']=='ABF_ranhled_phongkhach')
  assert(LED.normalize({'cnc_instance'=>'ABF_RANHLED_12'})['cnc_instance']=='ABF_RANHLED_12')
end

check('AUTO LED length uses both end clearances') do
  p=LED.groove_plan(1000,400,LED::DEFAULTS.merge('end_clearance'=>25,'edge_offset'=>30,'groove_width'=>12,'groove_length'=>0),:min)
  near(p[:length],950)
  near(p[:u0],25)
  near(p[:u1],975)
  near(p[:v0],30)
  near(p[:v1],42)
  assert(p[:auto_length])
end

check('manual LED length stays centered inside end clearances') do
  p=LED.groove_plan(1000,400,LED::DEFAULTS.merge('end_clearance'=>50,'groove_length'=>600,'edge_offset'=>20,'groove_width'=>10),:min)
  near(p[:length],600)
  near(p[:u0],200)
  near(p[:u1],800)
  assert(!p[:auto_length])
end

check('hover side switches groove to opposite outside edge') do
  a=LED.groove_plan(1000,400,LED::DEFAULTS.merge('edge_offset'=>30,'groove_width'=>10),:min)
  b=LED.groove_plan(1000,400,LED::DEFAULTS.merge('edge_offset'=>30,'groove_width'=>10),:max)
  near(a[:v0],30);near(a[:v1],40)
  near(b[:v0],360);near(b[:v1],370)
end

check('LED quantity and clear spacing generate parallel groove plans') do
  plans=LED.groove_plans(
    1000,400,
    LED::DEFAULTS.merge('quantity'=>3,'spacing'=>20,'edge_offset'=>30,'groove_width'=>10),
    :min
  )
  assert(plans.length==3)
  near(plans[0][:v0],30)
  near(plans[1][:v0],60)
  near(plans[2][:v0],90)
  assert(plans.all?{|p|p[:count]==3})
end

check('LED invalid offsets are rejected before geometry creation') do
  begin
    LED.groove_plan(200,50,LED::DEFAULTS.merge('end_clearance'=>110),:min)
    raise 'accepted invalid end clearance'
  rescue RuntimeError=>e
    assert(e.message.include?('2 đầu'))
  end
  begin
    LED.groove_plan(500,30,LED::DEFAULTS.merge('edge_offset'=>25,'groove_width'=>10),:min)
    raise 'accepted invalid edge offset'
  rescue RuntimeError=>e
    assert(e.message.include?('mép ngoài'))
  end
end

check('LED local rectangle uses true groove dimensions on face plane') do
  analysis={
    origin:Geom::Point3d.new(0,0,0),
    u:Geom::Vector3d.new(1,0,0),
    v:Geom::Vector3d.new(0,1,0),
    normal:Geom::Vector3d.new(0,0,1),
    min_u:0,min_v:0
  }
  plan=LED.groove_plan(1000,400,LED::DEFAULTS.merge('end_clearance'=>20,'edge_offset'=>30,'groove_width'=>10),:min)
  pts=LED.local_rect(analysis,plan)
  near((pts[0].distance(pts[1]))*25.4,960)
  near((pts[1].distance(pts[2]))*25.4,10)
end

check('Tạo LED UI contains preset and live preview controls') do
  html=LED.dialog_html
  assert(html.include?('TẠO LED'))
  assert(html.include?('MẪU ĐÃ LƯU'))
  assert(html.include?('Cách 2 đầu'))
  assert(html.include?('Cách mép ngoài'))
  assert(html.include?('Độ rộng rãnh LED'))
  assert(html.include?('Chiều dài rãnh'))
  assert(html.include?('Màu LED mô phỏng'))
  assert(html.include?('Độ sáng LED'))
  assert(html.include?('Khoảng hắt sáng'))
  assert(html.include?('Độ loang ánh sáng'))
  assert(html.include?('Số lượng rãnh'))
  assert(html.include?('Khoảng cách giữa'))
  assert(html.include?('PREVIEW ÁNH SÁNG LED'))
  assert(html.include?('light_preview'))
  assert(html.include?('VÀNG ẤM'))
  assert(html.include?('VÀNG SÁNG'))
  assert(html.include?('TRẮNG ẤM'))
  assert(html.include?('BẮT ĐẦU TẠO LIÊN TỤC'))
  assert(html.include?('CHIẾU XUỐNG · Model -Z'))
  assert(html.include?('LED DỌC · HẮT XUỐNG + RA MẶT'))
  assert(html.include?('ABF_RANHLED'))
  assert(html.include?('ABF_ranhled'))
  assert(html.include?('INSTANCE CNC'))
  assert(html.include?('TAG CNC'))
  assert(html.include?('CẬP NHẬT PREVIEW'))
  assert(html.include?('ABF/is-cutting-lines=true'))
  assert(html.include?('trực tiếp vào Face/hình học của Group/Component'))
  assert(html.include?('bắt buộc heal/split vào Face thật'))
  assert(html.include?('không tạo Group CNC con'))
end

check('Tạo LED CNC uses exact entities that own the host Face') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?('def face_entities(host_face,target)'))
  assert(source.include?('parent = host_face.respond_to?(:parent) ? host_face.parent : nil'))
  assert(source.include?('entities = face_entities(host_face,target)'))
  assert(source.include?("Không tìm lại được Face bên trong Group/Component"))
  assert(!source.include?("host_face ||= @face"))
end

check('Tạo LED CNC stores INSTANCE ABF_RANHLED and Tag ABF_ranhled without child group') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?("'cnc_instance'=>'ABF_RANHLED'"))
  assert(source.include?("'cnc_tag'=>'ABF_ranhled'"))
  body=source.split("def add_abf_profile",2)[1].split("def midpoint",2)[0]
  assert(body.include?("instance_name = normalize_instance(opts['cnc_instance'])"))
  assert(body.include?("tag_name = normalize_tag(opts['cnc_tag'])"))
  assert(body.include?("edge.layer = tag"))
  assert(body.include?("edge.set_attribute('ABF','instance',instance_name)"))
  assert(body.include?("edge.set_attribute('ABF','instance-name',instance_name)"))
  assert(body.include?("edge.set_attribute('ABF','tag-name',tag_name)"))
  assert(body.include?("target.set_attribute('ABF','instance',instance_name)"))
  assert(!body.include?("entities.add_group"))
end

check('Tạo LED CNC edges are embedded directly in host entities without child group') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  body=source.split("def add_abf_profile",2)[1].split("def midpoint",2)[0]
  assert(body.include?("edge = entities.add_line(point,nxt)"))
  assert(body.include?("edge.layer = tag"))
  assert(body.include?("edge.set_attribute('ABF','is-cutting-lines',true)"))
  assert(body.include?("led_profile_grouped',false"))
  assert(body.include?("phải có đúng 4 Edge kín"))
  assert(!body.include?("entities.add_group"))
end

check('Tạo LED CNC heals four edges into real Face topology') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?('def heal_profile_face'))
  assert(source.include?('edge.find_faces if edge.respond_to?(:find_faces)'))
  assert(source.include?('chưa ăn vào Face thật của tấm.'))
  assert(source.include?("profile_faces = heal_profile_face(entities,edges,points,instance_name,tag_name)"))
  assert(source.include?('chưa tạo được loop Face kín thật.'))
  assert(source.include?("edges.all? { |edge| face_edges.include?(edge) }"))
  assert(source.include?("embedded_face_count"))
  assert(source.include?("led_profile_face_count"))
  assert(source.include?("tag.visible = true if tag.respond_to?(:visible=)"))
end

check('Tạo LED light always casts downward and halo fades smoothly') do
  analysis={
    origin:Geom::Point3d.new(0,0,0),
    u:Geom::Vector3d.new(1,0,0),
    v:Geom::Vector3d.new(0,1,0),
    normal:Geom::Vector3d.new(0,0,1),
    min_u:0,min_v:0
  }
  plan=LED.groove_plan(1000,400,LED::DEFAULTS,:min)
  direction=LED.light_direction_world(analysis,plan,Geom::Transformation.new)
  near(direction.x,0.0)
  near(direction.y,0.0)
  near(direction.z,-1.0)

  vertical_analysis=analysis.merge(u:Geom::Vector3d.new(0,0,1),normal:Geom::Vector3d.new(0,1,0))
  vertical_direction=LED.light_direction_world(vertical_analysis,plan,Geom::Transformation.new)
  assert(vertical_direction.z < -0.5)
  assert(vertical_direction.y.abs > 0.1)

  rect=[
    Geom::Point3d.new(0,0,100.mm),
    Geom::Point3d.new(100.mm,0,100.mm),
    Geom::Point3d.new(100.mm,10.mm,100.mm),
    Geom::Point3d.new(0,10.mm,100.mm)
  ]
  light=LED.light_geometry(rect,LED::DEFAULTS,direction)
  assert(light[:bands].length==72)
  assert(light[:levels].length==72)
  assert(light[:bands].first[:alpha] > light[:bands].last[:alpha])
  assert(light[:direction].z < 0)
  far=light[:bands].last[:points]
  assert(far[2].z < rect[1].z)

  off=LED.light_geometry(rect,LED::DEFAULTS.merge('brightness'=>0),direction)
  assert(off[:bands].all?{|row|row[:alpha]==0})
end

check('Tạo LED viewport and dialog use fixed downward cast direction') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?("direction = LedTool.light_direction_world(@analysis,plan,@target_tr)"))
  assert(source.include?("Geom::Vector3d.new(0,0,-1)"))
  assert(source.include?("tip = LedTool.shift_point(source,direction,arrow_len)"))
  assert(source.include?("view.draw(GL_LINES,[source,tip,tip,left,tip,right])"))
  assert(source.include?("CHIẾU XUỐNG · Model -Z"))
end

check('Tạo LED dialog exposes warm color presets and explicit continuous-create callback') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?("setLedColor('#ffbd59')"))
  assert(source.include?("setLedColor('#ffe08a')"))
  assert(source.include?("setLedColor('#fff0c2')"))
  assert(source.include?("function startContinuous(){sketchup.start_continuous"))
  assert(source.include?("add_action_callback('start_continuous')"))
  assert(source.include?("ĐÃ BẬT TẠO LIÊN TỤC"))
end

check('Tạo LED create flow loops all groove plans and stays continuous') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?("plans = LedTool.groove_plans"))
  assert(source.include?("plans.each_with_index do |plan,index|"))
  assert(source.include?("LedTool.add_abf_profile(target,host_face,local_points,@options,index,plans.length)"))
  assert(source.include?("tiếp tục rà/click"))
end

check('Tạo LED accepts Group and Component targets') do
  g=board(600,400,17.5)
  assert(LED.container?(g))
  ci=Sketchup::ComponentInstance.new(g.definition)
  assert(LED.container?(ci))
end

check('Tạo LED simulation avoids non-planar quad faces') do
  source=File.read(ROOT+'/led_tool.rb',encoding:'UTF-8')
  assert(source.include?('def add_safe_quad_faces'))
  assert(source.include?('add_triangle_face(entities,points[0],points[1],points[2])'))
  assert(source.include?('add_triangle_face(entities,points[0],points[2],points[3])'))
  assert(!source.include?('group.entities.add_face(core_pts)'))
  assert(source.include?('band_count = 72'))
end

puts "LED TOOL REGRESSIONS COMPLETE"
