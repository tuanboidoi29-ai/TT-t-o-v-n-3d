# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module TTLicenseIssuerLoader
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('TRẦN TUẤN - CẤP MÃ BẢN QUYỀN OWNER', 'tt_license_issuer/main')
    ext.description = 'Công cụ OWNER: nhập Mã máy khách, chọn thời hạn và tạo mã kích hoạt RSA Offline V2 để sao chép trực tiếp.'
    ext.version = '1.0.0'
    ext.creator = 'TRẦN TUẤN'
    ext.copyright = '2026 TRẦN TUẤN'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
