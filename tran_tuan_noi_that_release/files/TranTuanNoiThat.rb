# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', 'tran_tuan_noi_that/bootstrap')
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: License Commercial V1.3.0 thêm cấu hình ngân hàng/QR trong OWNER và QR thanh toán cho khách; Bo Cong V2.2.7 đã khóa; Xoay Vân V3.5.0; LayoutStats V0.8.1.'
    ext.version = '1.9.52'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
