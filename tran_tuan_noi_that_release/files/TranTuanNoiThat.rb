# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', 'tran_tuan_noi_that/bootstrap')
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: Vẽ Ván, BOX, Ngăn Kéo, Bo Cong Khối, Co Giãn Khối MODE, Xoay Vân chuẩn 2440x1220, Xuất Layout chỉ phối cảnh và PDF trực tiếp phối cảnh + thống kê ván.'
    ext.version = '1.9.38'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
