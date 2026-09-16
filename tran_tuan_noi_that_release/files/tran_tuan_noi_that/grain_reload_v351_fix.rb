# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN V3.5.1
# HOT RELOAD SAFE FIX
#
# Mục tiêu:
# - Không để reload_runtime dừng vì Grain::Tool thiếu onKeyDown khi V3.5.0 alias callback.
# - Nếu base callback còn tồn tại thì giữ nguyên bằng alias.
# - Nếu callback bị thiếu do reload dở dang / file cũ, tạo fallback TAB tối thiểu để
#   V3.5.0 có thể nạp tiếp an toàn; sau đó grain_tool.rb/settings.rb sẽ khôi phục đầy đủ.
# - Không explode/regroup, không thay geometry, material, UV hay transform.

module TranTuanNoiThat
  module Grain
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.5.1'.freeze

    class Tool
      key_base_defined = method_defined?(:tt_v350_key_base) ||
                         private_method_defined?(:tt_v350_key_base) ||
                         protected_method_defined?(:tt_v350_key_base)

      unless key_base_defined
        key_defined = method_defined?(:onKeyDown) ||
                      private_method_defined?(:onKeyDown) ||
                      protected_method_defined?(:onKeyDown)

        if key_defined
          alias_method :tt_v350_key_base, :onKeyDown
        else
          def tt_v350_key_base(key, _repeat, _flags, view)
            tab_key = if Grain.const_defined?(:TAB_KEY, false)
                        Grain.const_get(:TAB_KEY)
                      else
                        9
                      end
            return unless key.to_i == tab_key.to_i

            # Fallback an toàn cho trạng thái reload dở dang: vẫn cho mở bảng TAB.
            Grain.open_settings(self) if Grain.respond_to?(:open_settings)
            view.invalidate if view && view.respond_to?(:invalidate)
          rescue StandardError => error
            puts "[TT Grain V3.5.1 reload key] #{error.class}: #{error.message}"
          end
        end
      end

      # Marker cho CI / chẩn đoán runtime.
      def tt_grain_reload_safe_v351?
        true
      end
    end
  end
end
