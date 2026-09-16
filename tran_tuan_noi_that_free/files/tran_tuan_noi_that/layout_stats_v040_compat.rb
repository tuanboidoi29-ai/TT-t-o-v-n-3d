# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.4.1 HOTFIX
# Chặn lỗi alias capture_inline_previews khi hot reload.
# File này được load 2 lần: trước V0.4.0 để giữ Method gốc V0.3.0,
# và sau V0.4.0 để nâng VERSION lên 0.4.1.

module TranTuanNoiThat
  module LayoutStats
    unless instance_variable_defined?(:@tt_v040_base_capture_proc)
      if respond_to?(:capture_inline_previews, true)
        @tt_v040_base_capture_proc = method(:capture_inline_previews)
      end
    end

    class << self
      unless method_defined?(:tt_v040_base_capture_inline_previews)
        def tt_v040_base_capture_inline_previews(model, cut_offset_mm)
          base = instance_variable_get(:@tt_v040_base_capture_proc)
          raise 'Engine preview Layout V0.3.0 chưa được nạp.' unless base
          base.call(model, cut_offset_mm)
        end
      end
    end

    if const_defined?(:VERSION, false) && VERSION.to_s == '0.4.0'
      remove_const(:VERSION)
      VERSION = '0.4.1'.freeze
    end
  end
end
