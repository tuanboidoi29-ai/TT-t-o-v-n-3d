# encoding: UTF-8
STDOUT.sync = true
require 'tmpdir'
$LOAD_PATH.unshift(File.expand_path(__dir__))
require 'sketchup'

tmp = Dir.mktmpdir('tt_vector_cnc')
module TranTuanNoiThat; end
TranTuanNoiThat.const_set(:ROOT, tmp)
load File.expand_path('../files/tran_tuan_noi_that/vector_cnc_tool.rb', __dir__)

V = TranTuanNoiThat::VectorCNC
$count = 0

def assert(value, message='assertion failed')
  raise message unless value
end

def near(a,b,eps=0.0001)
  assert((a.to_f-b.to_f).abs <= eps, "#{a} != #{b}")
end

def check(name)
  yield
  $count += 1
  puts "PASS #{name}"
end

check('built-in vector library has common CNC shapes') do
  ids = V.builtins.map { |row| row['id'] }
  %w[circle square rectangle triangle right_triangle diamond hexagon octagon oval star].each do |id|
    assert(ids.include?(id), "missing #{id}")
  end
  assert(V.builtins.all? { |row| row['name'].start_with?('ABF_') })
end

check('scaled vector respects direct width and height') do
  tpl = V.builtin_template('square')
  pts = V.scaled_points(tpl,500,300)
  xs = pts.map(&:first)
  ys = pts.map(&:last)
  near(xs.max-xs.min,500)
  near(ys.max-ys.min,300)
end

check('custom library names are always ABF-prefixed') do
  saved = V.save_custom(V.builtin_template('circle'),'Lo tron am')
  assert(saved['name']=='ABF_LO_TRON_AM')
  assert(File.file?(V::LIBRARY_FILE))
  rows = V.custom_templates
  assert(rows.any? { |row| row['name']=='ABF_LO_TRON_AM' })
end

check('SVG polygon imports as normalized vector') do
  path = File.join(tmp,'tam_giac.svg')
  File.write(path,'<svg xmlns="http://www.w3.org/2000/svg"><polygon points="0,100 50,0 100,100"/></svg>')
  tpl = V.import_file(path)
  assert(tpl['name']=='ABF_TAM_GIAC')
  assert(tpl['points'].length==3)
end

check('SVG circle imports with enough points for smooth CNC') do
  path = File.join(tmp,'tron.svg')
  File.write(path,'<svg xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="40"/></svg>')
  tpl = V.import_file(path)
  assert(tpl['points'].length>=64)
end

check('DXF LWPOLYLINE imports') do
  path = File.join(tmp,'vuong.dxf')
  File.write(path,[
    '0','SECTION','2','ENTITIES',
    '0','LWPOLYLINE','90','4',
    '10','0','20','0',
    '10','100','20','0',
    '10','100','20','100',
    '10','0','20','100',
    '0','ENDSEC','0','EOF'
  ].join("\n"))
  tpl = V.import_file(path)
  assert(tpl['points'].length==4)
end

check('JSON vector imports') do
  path = File.join(tmp,'diamond.json')
  File.write(path,JSON.generate({'points'=>[[0,-50],[50,0],[0,50],[-50,0]]}))
  tpl = V.import_file(path)
  assert(tpl['points'].length==4)
end

check('invalid open vector is rejected') do
  begin
    V.sanitize_template('points'=>[[0,0],[100,0]])
    raise 'accepted invalid vector'
  rescue RuntimeError => e
    assert(e.message.include?('ít nhất 3'))
  end
end

def box_definition(length_mm,width_mm,thickness_mm)
  xs=[0,length_mm.mm];ys=[0,width_mm.mm];zs=[0,thickness_mm.mm]
  verts={}
  xs.each_with_index do |x,ix|
    ys.each_with_index do |y,iy|
      zs.each_with_index do |z,iz|
        verts[[ix,iy,iz]]=Sketchup::Vertex.new(Geom::Point3d.new(x,y,z))
      end
    end
  end
  edges=Sketchup::Entities.new
  [
    [[0,0,0],[1,0,0]],[[0,1,0],[1,1,0]],[[0,0,1],[1,0,1]],[[0,1,1],[1,1,1]],
    [[0,0,0],[0,1,0]],[[1,0,0],[1,1,0]],[[0,0,1],[0,1,1]],[[1,0,1],[1,1,1]],
    [[0,0,0],[0,0,1]],[[1,0,0],[1,0,1]],[[0,1,0],[0,1,1]],[[1,1,0],[1,1,1]]
  ].each{|a,b|edges << Sketchup::Edge.new(verts[a],verts[b])}
  definition=Sketchup::Definition.new(edges)
  definition.name='TEST_BOX'
  definition
end

check('object dimensions read length width thickness from selected Group Component') do
  definition=box_definition(1000,500,18)
  instance=Sketchup::ComponentInstance.new(definition,Geom::Transformation.new)
  instance.name='VAN_TEST'
  info=V.instance_dimensions(instance)
  near(info['length'],1000,0.01)
  near(info['width'],500,0.01)
  near(info['thickness'],18,0.01)
  assert(info['name']=='VAN_TEST')

  model=TestModel.new([instance])
  model.selection=[instance]
  Sketchup.model=model
  selected=V.selected_target_info
  near(selected['length'],1000,0.01)
  near(selected['width'],500,0.01)
  near(selected['thickness'],18,0.01)
end

check('circle oval smoothness changes segment count but square keeps exact corners') do
  circle=V.builtin_template('circle')
  assert(V.scaled_points(circle,200,200,24).length==24)
  assert(V.scaled_points(circle,200,200,144).length==144)
  oval=V.builtin_template('oval')
  assert(V.scaled_points(oval,300,180,96).length==96)
  square=V.builtin_template('square')
  assert(V.scaled_points(square,200,200,144).length==4)
end

check('CNC settings preserve border smoothness cut mode and alignment') do
  settings=V.cnc_settings(300,180,4,20,30,8,120,'right_top','outside')
  near(settings['width'],300)
  near(settings['height'],180)
  near(settings['depth'],4)
  near(settings['border_width'],8)
  assert(settings['smoothness']==120)
  assert(settings['anchor']=='right_top')
  assert(settings['cut_mode']=='outside')
end

check('nine point alignment computes left right top bottom and center') do
  tpl=V.builtin_template('square')
  geom={min_x:0.0,max_x:1000.mm,min_y:0.0,max_y:500.mm}

  cases={
    'left'=>[120,280],
    'right'=>[880,280],
    'top'=>[520,420],
    'bottom'=>[520,80],
    'left_top'=>[120,420],
    'right_top'=>[880,420],
    'left_bottom'=>[120,80],
    'right_bottom'=>[880,80],
    'center'=>[520,280]
  }
  cases.each do |anchor,(x_mm,y_mm)|
    tool=V::PlacementTool.new(tpl,{
      'width'=>200,'height'=>100,'offset_x'=>20,'offset_y'=>30,
      'border_width'=>5,'smoothness'=>72,'anchor'=>anchor,'cut_mode'=>'inside'
    })
    center,_reference=tool.send(:center_for_anchor,geom)
    near(center.x*25.4,x_mm,0.01)
    near(center.y*25.4,y_mm,0.01)
  end
end

check('selected apply rejects when no Group or Component is selected') do
  model=TestModel.new([])
  model.selection=[]
  Sketchup.model=model
  tool=V::PlacementTool.new(V.builtin_template('circle'),{
    'width'=>200,'height'=>200,'border_width'=>2,'smoothness'=>96
  })
  begin
    tool.apply_selected
    raise 'accepted empty selection'
  rescue RuntimeError=>e
    assert(e.message.include?('chọn một Group') || e.message.include?('Group hoặc Component'))
  end
end

check('direct CNC panel plan creates complete panel dimensions and centered vector') do
  tpl=V.builtin_template('circle')
  plan=V.direct_panel_plan(
    tpl,
    {'length'=>1200,'width'=>600,'thickness'=>17.5,'name'=>'TAM_CNC','orientation'=>'xz'},
    V.cnc_settings(400,300,4,0,0,20,96,'center','inside')
  )
  near(plan[:panel]['length'],1200)
  near(plan[:panel]['width'],600)
  near(plan[:panel]['thickness'],17.5)
  near(plan[:center][0],600)
  near(plan[:center][1],300)
  assert(plan[:profile].length==96)
  assert(plan[:border_profile].length==96)
end

check('direct CNC panel plan supports nine-point alignment and rejects oversized vector border') do
  tpl=V.builtin_template('square')
  plan=V.direct_panel_plan(
    tpl,
    {'length'=>1000,'width'=>500,'thickness'=>18,'orientation'=>'xy'},
    V.cnc_settings(200,100,3,20,30,5,72,'right_top','outside')
  )
  near(plan[:center][0],880)
  near(plan[:center][1],420)
  begin
    V.direct_panel_plan(
      tpl,
      {'length'=>300,'width'=>200,'thickness'=>18},
      V.cnc_settings(280,180,3,0,0,20,72,'center','inside')
    )
    raise 'accepted oversized vector plus border'
  rescue RuntimeError=>e
    assert(e.message.include?('viền rộng'))
  end
end

check('image CNC template keeps multiple closed contours in one library item') do
  loops=[
    [[0,0],[100,0],[100,100],[0,100]],
    [[150,0],[200,0],[200,50],[150,50]]
  ]
  item=V.sanitize_template(
    'id'=>'image_test',
    'name'=>'ANH_TEST',
    'label'=>'Ảnh test',
    'loops'=>loops,
    'source_type'=>'image',
    'source_name'=>'test.png'
  )
  assert(item['source_type']=='image')
  assert(item['loops'].length==2)
  assert(item['points'].length>=4)
  all=item['loops'].flatten(1)
  assert(all.map{|p|p[0]}.min>=-1.0001)
  assert(all.map{|p|p[0]}.max<=1.0001)
end

check('image CNC screen expands every image contour into through-cut profiles') do
  tpl=V.sanitize_template(
    'id'=>'image_two',
    'name'=>'ANH_HAI_LO',
    'label'=>'Ảnh hai lỗ',
    'loops'=>[
      [[0,0],[100,0],[100,100],[0,100]],
      [[150,0],[200,0],[200,50],[150,50]]
    ],
    'source_type'=>'image'
  )
  plan=V.screen_panel_plan(
    tpl,
    {'length'=>1000,'width'=>500,'thickness'=>17.5,'orientation'=>'xz'},
    V.cnc_settings(200,100,3,0,0,0,72,'center','inside'),
    {'mode'=>'repeat','frame_width'=>40,'rows'=>2,'cols'=>3,'gap_x'=>20,'gap_y'=>20,'preserve_ratio'=>true}
  )
  assert(plan[:profiles].length==12)
  assert(plan[:screen]['through_cut']==true)
  assert(plan[:profiles].map{|p|p[:loop_index]}.uniq.sort==[0,1])
end

check('CNC screen repeat mode fills rows and columns inside outer frame') do
  tpl=V.builtin_template('circle')
  plan=V.screen_panel_plan(
    tpl,
    {'length'=>1200,'width'=>600,'thickness'=>17.5,'name'=>'VACH_CNC','orientation'=>'xz'},
    V.cnc_settings(200,200,3,0,0,0,72,'center','inside'),
    {'mode'=>'repeat','frame_width'=>50,'rows'=>3,'cols'=>5,'gap_x'=>20,'gap_y'=>20,'preserve_ratio'=>true}
  )
  assert(plan[:profiles].length==15)
  assert(plan[:screen]['through_cut']==true)
  assert(V.respond_to?(:punch_through_profile))
  near(plan[:inner][0],50)
  near(plan[:inner][1],50)
  near(plan[:inner][2],1100)
  near(plan[:inner][3],500)
  plan[:profiles].each do |item|
    item[:points].each do |x,y|
      assert(x>=50-0.001 && x<=1150+0.001)
      assert(y>=50-0.001 && y<=550+0.001)
    end
  end
end

check('CNC screen fit mode creates one centered pattern preserving ratio') do
  tpl=V.builtin_template('rectangle')
  plan=V.screen_panel_plan(
    tpl,
    {'length'=>1000,'width'=>500,'thickness'=>18,'orientation'=>'xz'},
    V.cnc_settings(200,120,4,0,0,0,96,'center','outside'),
    {'mode'=>'fit','frame_width'=>40,'preserve_ratio'=>true}
  )
  assert(plan[:profiles].length==1)
  item=plan[:profiles].first
  near(item[:center][0],500)
  near(item[:center][1],250)
  assert(item[:width]<=920.001)
  assert(item[:height]<=420.001)
end

check('CNC screen rejects impossible frame and repeat spacing') do
  tpl=V.builtin_template('square')
  begin
    V.screen_panel_plan(
      tpl,
      {'length'=>300,'width'=>200,'thickness'=>18},
      V.cnc_settings(100,100,3,0,0,0,72,'center','inside'),
      {'mode'=>'repeat','frame_width'=>120,'rows'=>2,'cols'=>2,'gap_x'=>10,'gap_y'=>10}
    )
    raise 'accepted oversized frame'
  rescue RuntimeError=>e
    assert(e.message.include?('Viền khung'))
  end
  begin
    V.screen_panel_plan(
      tpl,
      {'length'=>500,'width'=>300,'thickness'=>18},
      V.cnc_settings(100,100,3,0,0,0,72,'center','inside'),
      {'mode'=>'repeat','frame_width'=>30,'rows'=>2,'cols'=>4,'gap_x'=>200,'gap_y'=>10}
    )
    raise 'accepted impossible gap'
  rescue RuntimeError=>e
    assert(e.message.include?('Khoảng cách ngang'))
  end
end

check('VECTOR CNC HtmlDialog has non-blank static UI and apply controls') do
  html=V.dialog_html
  assert(html.length>5000)
  assert(html.include?('VECTOR CNC / ẢNH CNC UI đã nạp'))
  assert(html.include?('TT – VECTOR CNC / ẢNH CNC'))
  assert(html.include?('ÁP DỤNG VECTOR VÀO KHỐI ĐANG CHỌN'))
  assert(html.include?('borderWidth'))
  assert(html.include?('smoothness'))
  assert(html.include?('align-grid'))
  assert(html.include?('TẠO TẤM CNC MỚI'))
  assert(html.include?('panelLength'))
  assert(html.include?('create_panel'))
  assert(html.include?('TẠO VÁCH CNC TỪ MẪU'))
  assert(html.include?('create_screen'))
  assert(html.include?('screenPreview'))
  assert(html.include?('drawTemplateThumb'))
  assert(html.include?('ẢNH CNC · NHẬP ẢNH'))
  assert(html.include?('imageFile'))
  assert(html.include?('imageThreshold'))
  assert(html.include?('imageVectorPreview'))
  assert(html.include?('save_image_template'))
  assert(html.include?('traceMaskLoops'))
  assert(html.include?('ĐỤC THỦNG THẬT'))
  assert(html.include?('LỖ ĐỤC THỦNG'))
  V.ensure_data
  File.write(V::UI_FILE,html,encoding:'UTF-8')
  assert(File.size(V::UI_FILE)>5000)
end

puts "VECTOR CNC REGRESSIONS COMPLETE (#{$count})"
