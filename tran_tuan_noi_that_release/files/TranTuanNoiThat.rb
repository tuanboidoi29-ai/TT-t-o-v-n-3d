# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TranTuanNoiThat
  unless file_loaded?(__FILE__)
    runtime_folder = if File.directory?(File.join(__dir__, 'TranTuanNoiThat'))
                       'TranTuanNoiThat'
                     else
                       'tran_tuan_noi_that'
                     end

    ext = SketchupExtension.new('TRẦN TUẤN NỘI THẤT', "#{runtime_folder}/bootstrap")
    ext.description = 'Bản thương mại TRẦN TUẤN: RSA theo MÃ MÁY; cảnh báo bản quyền không modal, có nút đóng và ESC.'
    ext.version = '1.9.60'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
