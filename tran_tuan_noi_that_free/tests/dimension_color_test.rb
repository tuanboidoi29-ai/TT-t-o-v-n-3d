require_relative '../files/tran_tuan_noi_that/dimension_tool'
module Sketchup
  class Color
    attr_reader :rgb
    def initialize(*rgb); @rgb=rgb; end
  end
end
m=TranTuanNoiThat::DetailDimensions
valid=m.options.dup
valid['detail_color']='#FF0080'
m.options.replace(m.validate_options(valid))
raise 'RGB conversion' unless m.drawing_color(:detail).rgb==[255,0,128]
[valid.merge('detail_color'=>'red'),valid.merge('height'=>'true'),valid.merge('horizontal'=>false,'depth'=>false,'height'=>false,'opening'=>false,'total'=>false)].each do |invalid|
 rejected=false
 begin;m.validate_options(invalid);rescue RuntimeError;rejected=true;end
 raise 'invalid settings accepted' unless rejected
end
puts 'Color conversion and invalid option validation passed'
