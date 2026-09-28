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

check('PickHelper resolves nested Face and instance transformation from outside group') do
  unless defined?(Sketchup::Face)
    Sketchup.const_set(:Face, Class.new)
  end
  face = Sketchup::Face.new
  entities = Sketchup::Entities.new
  definition = Sketchup::Definition.new(entities)
  instance = Sketchup::ComponentInstance.new(definition,Geom::Transformation.translation(Geom::Vector3d.new(10.mm,20.mm,30.mm)))

  picker = Object.new
  picker.define_singleton_method(:do_pick){|x,y,aperture=0|1}
  picker.define_singleton_method(:count){1}
  picker.define_singleton_method(:leaf_at){|i|face}
  picker.define_singleton_method(:path_at){|i|[instance,face]}
  picker.define_singleton_method(:transformation_at){|i|instance.transformation}
  picker.define_singleton_method(:depth_at){|i|1.0}

  view = Object.new
  view.define_singleton_method(:pick_helper){picker}

  tool = V::PlacementTool.new(V.builtin_template('square'),200,200,3)
  info = tool.send(:pick_grouped_face,view,100,100)
  assert(info)
  assert(info[:face].equal?(face))
  assert(info[:definition].equal?(definition))
  assert(info[:owner_instance].equal?(instance))
  p = Geom::Point3d.new(0,0,0).transform(info[:transform])
  near(p.x,10.mm);near(p.y,20.mm);near(p.z,30.mm)
end

check('PickHelper rejects top-level Face with no Group or Component path') do
  unless defined?(Sketchup::Face)
    Sketchup.const_set(:Face, Class.new)
  end
  face = Sketchup::Face.new
  picker = Object.new
  picker.define_singleton_method(:do_pick){|x,y,aperture=0|1}
  picker.define_singleton_method(:count){1}
  picker.define_singleton_method(:leaf_at){|i|face}
  picker.define_singleton_method(:path_at){|i|[face]}
  picker.define_singleton_method(:transformation_at){|i|Geom::Transformation.new}
  picker.define_singleton_method(:depth_at){|i|0.0}
  view = Object.new
  view.define_singleton_method(:pick_helper){picker}
  model = TestModel.new([])
  model.active_path=[]
  Sketchup.model=model

  tool = V::PlacementTool.new(V.builtin_template('square'),200,200,3)
  assert(tool.send(:pick_grouped_face,view,50,50).nil?)
end

puts "VECTOR CNC REGRESSIONS COMPLETE (#{$count})"
