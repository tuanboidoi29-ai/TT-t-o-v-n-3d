# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    runtime_folder = 'tran_tuan_noi_that'

    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', "#{runtime_folder}/bootstrap")
    ext.description = 'Bộ công cụ nội thất dùng trực tiếp, không yêu cầu kích hoạt bản quyền.'
    ext.version = '1.9.89'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
