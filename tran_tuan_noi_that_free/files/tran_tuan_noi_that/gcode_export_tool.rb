# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - NCStudio G-code exporter
# Conservative first release: exports closed, horizontal top-face contours from selected Groups/Components.
require 'sketchup.rb'

module TranTuanNoiThat
  module GCodeExport
    extend self

    MM = 1.0 / 25.4
    DEFAULTS = {
      'tool_diameter' => 6.0,
      'spindle' => 18000,
      'feed' => 2500,
      'plunge' => 600,
      'depth' => 9.0,
      'stepdown' => 3.0,
      'safe_z' => 5.0
    }.freeze

    def mm(value)
      value.to_f * 25.4
    end

    def collect_faces(entities, transform, output)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Face)
          normal = entity.normal.transform(transform)
          next unless normal.z > 0.999
          loops = [entity.outer_loop] + entity.loops.reject(&:outer?)
          loop_points = loops.map do |loop|
            loop.vertices.map { |vertex| vertex.position.transform(transform) }
          end
          outer_points = loop_points.first
          next if outer_points.length < 3
          z_values = outer_points.map(&:z)
          next unless (z_values.max - z_values.min).abs < 0.001
          output << [z_values.sum / z_values.length, loop_points]
        elsif entity.is_a?(Sketchup::Group)
          collect_faces(entity.entities, transform * entity.transformation, output)
        elsif entity.is_a?(Sketchup::ComponentInstance)
          collect_faces(entity.definition.entities, transform * entity.transformation, output)
        end
      end
    end

    def selected_contours(model)
      roots = model.selection.to_a.select { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
      raise 'Hãy chọn ít nhất một Group hoặc Component chứa tấm ván.' if roots.empty?

      contours = []
      roots.each do |root|
        faces = []
        entities = root.is_a?(Sketchup::Group) ? root.entities : root.definition.entities
        collect_faces(entities, root.transformation, faces)
        raise "Không tìm thấy mặt phẳng ngang hợp lệ trong: #{root.name}." if faces.empty?
        top_z = faces.map(&:first).max
        top_faces = faces.select { |face| (face[0] - top_z).abs < 0.001 }
        top_faces.each do |_z, loops|
          loops.each do |points|
            contours << points if points.length >= 3
          end
        end
      end
      contours
    end

    def config_dialog
      keys = %w[tool_diameter spindle feed plunge depth stepdown safe_z]
      prompts = ['Đường kính dao (mm)', 'Tốc độ trục chính (RPM)', 'Tốc độ chạy XY (mm/phút)', 'Tốc độ xuống Z (mm/phút)', 'Chiều sâu cắt tổng (mm)', 'Chiều sâu mỗi lớp (mm)', 'Chiều cao an toàn Z (mm)']
      defaults = keys.map { |k| TranTuanNoiThat.setting("gcode_#{k}", DEFAULTS[k]) }
      values = UI.inputbox(prompts, defaults, 'NCStudio - Thiết lập xuất G-code')
      return nil unless values
      cfg = {}
      keys.each_with_index do |key, i|
        n = Float(values[i]) rescue nil
        raise "Thông số không hợp lệ: #{prompts[i]}." unless n && n > 0
        cfg[key] = n
        TranTuanNoiThat.save_setting("gcode_#{key}", n)
      end
      raise 'Chiều sâu mỗi lớp không được lớn hơn chiều sâu cắt tổng.' if cfg['stepdown'] > cfg['depth']
      cfg
    end

    def gcode(contours, cfg)
      points = contours.flatten
      min_x = points.map(&:x).min
      min_y = points.map(&:y).min
      max_x = points.map(&:x).max
      max_y = points.map(&:y).max
      raise 'Kích thước phôi không hợp lệ.' if max_x <= min_x || max_y <= min_y

      lines = []
      lines << '(TRẦN TUẤN - NCStudio)'
      lines << '(G54: bottom-left | X: length | Y: width | Z: negative)'
      lines << '(UNITS: mm | ABSOLUTE | TOOLPATH: CONTOUR CENTERLINE - NO TOOL RADIUS COMPENSATION)'
      lines << 'G21'
      lines << 'G17'
      lines << 'G90'
      lines << 'G54'
      lines << 'G94'
      lines << "M03 S#{cfg['spindle'].round}"
      lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
      lines << "G00 X0.000 Y0.000"
      depth = cfg['stepdown']
      passes = []
      while depth < cfg['depth'] - 0.0001
        passes << depth
        depth += cfg['stepdown']
      end
      passes << cfg['depth']
      contours.each do |contour|
        xy = contour.map { |p| [mm(p.x - min_x), mm(p.y - min_y)] }
        next if xy.length < 3
        passes.each do |cut_depth|
          lines << "(PASS Z-#{format('%.3f', cut_depth)})"
          lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
          lines << "G00 X#{format('%.3f', xy[0][0])} Y#{format('%.3f', xy[0][1])}"
          lines << "G01 Z-#{format('%.3f', cut_depth)} F#{cfg['plunge'].round}"
          xy[1..-1].each do |x, y|
            lines << "G01 X#{format('%.3f', x)} Y#{format('%.3f', y)} F#{cfg['feed'].round}"
          end
          lines << "G01 X#{format('%.3f', xy[0][0])} Y#{format('%.3f', xy[0][1])} F#{cfg['feed'].round}"
          lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
        end
      end
      lines << 'M05'
      lines << 'G00 Z20.000'
      lines << 'M30'
      [lines.join("\n") + "\n", mm(max_x - min_x), mm(max_y - min_y), passes.length]
    end

    def run
      model = Sketchup.active_model
      contours = selected_contours(model)
      cfg = config_dialog
      return unless cfg
      text, length, width, pass_count = gcode(contours, cfg)
      preview = "ĐÃ QUÉT: #{contours.length} đường bao\nKích thước vùng: #{format('%.1f', length)} × #{format('%.1f', width)} mm\nDao: Ø#{cfg['tool_diameter']} mm\nSố lớp cắt: #{pass_count}\nGốc G54: góc dưới-trái\n\nCẢNH BÁO: Bản đầu xuất đường tâm theo biên dạng, CHƯA bù bán kính dao. Chỉ dùng để kiểm tra/mô phỏng; không chạy máy thật trước khi kiểm tra offset, chiều sâu, gá phôi và mã M theo máy.\n\nXuất tệp .NC? "
      return unless UI.messagebox(preview, MB_YESNO) == IDYES
      path = UI.savepanel('Lưu chương trình NCStudio', '', 'TT_NCStudio.NC')
      return unless path
      path += '.NC' unless path.downcase.end_with?('.nc')
      File.open(path, 'wb') { |f| f.write(text.encode('UTF-8')) }
      UI.messagebox("Đã tạo tệp NC:\n#{path}\n\nHãy mô phỏng và chạy thử không tải trước khi gia công.")
    rescue StandardError => e
      UI.messagebox("Xuất G-code thất bại:\n#{e.class}: #{e.message}")
    end
  end
end
