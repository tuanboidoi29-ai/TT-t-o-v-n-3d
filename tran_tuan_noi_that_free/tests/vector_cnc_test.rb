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

puts "VECTOR CNC REGRESSIONS COMPLETE (#{$count})"
