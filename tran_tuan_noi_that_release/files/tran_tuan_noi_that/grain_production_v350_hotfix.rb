# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - GRAIN V3.5.0 HOTFIX
# - Fallback AUTO không dùng super.
# - A/SHIFT chỉ khởi tạo một lượt preview khi giữ phím.

module TranTuanNoiThat
  module Grain
    class Tool
      def onKeyDown(key, repeat, flags, view)
        if @scan && key == ENTER_KEY
          apply_scan(false)
          return
        end

        if key == A_KEY || key == SHIFT_KEY
          return if repeat.to_i > 0
          start_scan_preview(view)
          return
        end

        tt_v350_key_base(key, repeat, flags, view)
      rescue StandardError => error
        puts "[TT Grain V3.5.0 hotfix key] #{error.class}: #{error.message}"
        UI.beep
      end

      private

      def part_name_rule(target, analysis, tr)
        rule = part_rule(target)
        return analysis unless rule

        case rule
        when :vertical
          axis = analysis[:plane_axes].max_by do |index|
            vector = AXES[index].clone.transform(tr)
            vector.normalize! if vector.length > 0.0001
            vector.dot(Z_AXIS).abs
          end
          axis ? force_axis(analysis, axis, 1) : analysis
        when :horizontal, :length
          axis = analysis[:plane_axes].max_by { |index| analysis[:sizes_mm][index] }
          axis ? force_axis(analysis, axis, 1) : analysis
        else
          analysis
        end
      rescue StandardError => error
        puts "[TT Grain V3.5.0 hotfix rule] #{error.class}: #{error.message}"
        analysis
      end
    end
  end
end
