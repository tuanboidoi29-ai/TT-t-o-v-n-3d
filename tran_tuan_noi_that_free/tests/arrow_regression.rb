require_relative 'window_regression'
[TranTuanNoiThat::StretchMode::Tool,TranTuanNoiThat::StretchMode::WindowTool].each do |klass|
 Sketchup.model=TestModel.new([box]);t=klass.new;v=Sketchup.model.active_view
 t.instance_variable_set(:@state,klass==TranTuanNoiThat::StretchMode::Tool ? :p2 : :move)
 {39=>0,37=>1,38=>2}.each do |key,axis|
  assert(t.onKeyDown(key,1,0,v)==true)
  assert(t.instance_variable_get(:@forced_axis)==axis)
  t.onKeyDown(key,2,0,v);assert(t.instance_variable_get(:@forced_axis)==axis)
  t.onKeyDown(40,1,0,v);assert(t.instance_variable_get(:@forced_axis).nil?)
  t.onKeyDown(key,1,0,v);t.onKeyDown(key,1,0,v);assert(t.instance_variable_get(:@forced_axis).nil?)
 end
end
puts "PASS #{$count} assertions including arrow locks in both stretch modes."
