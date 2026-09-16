# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', 'tran_tuan_noi_that/bootstrap')
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: Xoay Vân Ván V3.5.0; LayoutStats V0.8.0 xuất 5 trang kỹ thuật gồm Tổng thể, Line+X-Ray, Khung LINE, Mặt đứng và Mặt cắt; PDF nối thêm thống kê ván.'
    ext.version = '1.9.41'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
