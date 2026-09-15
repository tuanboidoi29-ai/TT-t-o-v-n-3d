# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', 'tran_tuan_noi_that/bootstrap')
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: Xoay Vân Ván V3.5.0 preview trước khi áp dụng, rule theo chi tiết, nhớ khổ theo vật liệu, khóa sản xuất và UV đúng tỷ lệ; Layout/PDF giữ V0.7.0.'
    ext.version = '1.9.40'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
