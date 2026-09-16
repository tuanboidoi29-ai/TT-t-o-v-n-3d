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
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: Grain V3.5.1 sửa lỗi nạp lại onKeyDown; Update Bridge V1.0.0 cho bản thương mại ký .rbe/.susig; License Commercial V1.4.0; Bo Cong V2.2.7 đã khóa; LayoutStats V0.8.1.'
    ext.version = '1.9.55'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
