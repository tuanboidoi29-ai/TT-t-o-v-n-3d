# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', 'tran_tuan_noi_that/bootstrap')
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: Vẽ Ván, BOX, Ngăn Kéo, Bo Cong Khối, Co Giãn Khối MODE, Xoay Vân Ván, Xuất Layout + Thống Kê Ván với xem trước toàn bộ Layout A3 ngay trong bảng, mặt cắt và Line/X-Ray.'
    ext.version = '1.9.31'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
