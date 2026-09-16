# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TTLicenseIssuerLoader
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRANTUAN-NOIITHAT-ADM', 'tt_license_issuer/main')
    ext.description = 'Công cụ OWNER khóa theo máy: nhập Mã máy khách, chọn 90/180 ngày hoặc Vĩnh viễn và cấp 1 mã RSA mở toàn bộ hệ thống.'
    ext.version = '1.1.0'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
