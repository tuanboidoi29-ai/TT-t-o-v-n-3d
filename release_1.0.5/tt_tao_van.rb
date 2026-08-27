# ============================================================
# TT - TẠO VÁN - TRẦN TUẤN
# Root loader
# ============================================================
require 'sketchup.rb'
require 'extensions.rb'

module TranTuan
  module TaoVan
    EXTENSION = SketchupExtension.new(
      'TT - tạo ván -Trần Tuấn',
      'TT_TaoVan/main'
    )
    EXTENSION.version = '1.2.4'
    EXTENSION.creator = 'TRẦN TUẤN'
    EXTENSION.description = 'Tạo ván Face 3D, Tạo Box, Tạo Ngăn Kéo, Xuất chi tiết ván và Hot Update.'
    EXTENSION.copyright = '© 2026 TRẦN TUẤN'
    unless defined?(@registered) && @registered
      Sketchup.register_extension(EXTENSION, true)
      @registered = true
    end
  end
end
