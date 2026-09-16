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
    ext.description = 'Hệ thống công cụ nội thất TRẦN TUẤN: License RSA Offline V2.0.0 theo Mã máy; không còn cơ chế thương mại/server/thanh toán theo chức năng.'
    ext.version = '1.9.58'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
