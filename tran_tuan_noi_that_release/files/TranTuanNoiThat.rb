# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    # SketchUp Extension Warehouse expects the top-level loader and support
    # folder to share the same basename. Commercial RBZ builds therefore use:
    #   TranTuanNoiThat.rb + TranTuanNoiThat/
    # Keep a lowercase fallback so legacy installations continue to load.
    runtime_folder = if File.directory?(File.join(__dir__, 'TranTuanNoiThat'))
                       'TranTuanNoiThat'
                     else
                       'tran_tuan_noi_that'
                     end

    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', "#{runtime_folder}/bootstrap")
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: License Commercial V1.4.0 tự nhận thanh toán SePay, tự kiểm tra giao dịch và mở quyền; Bo Cong V2.2.7 đã khóa; Xoay Vân V3.5.0; LayoutStats V0.8.1.'
    ext.version = '1.9.53'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
