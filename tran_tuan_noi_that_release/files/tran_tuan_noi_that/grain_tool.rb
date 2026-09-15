# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN loader
# Source được chia thành 3 phần để nạp nóng ổn định.
parts = %w[grain_tool_part1.inc grain_tool_part2.inc grain_tool_part3.inc]
code = parts.map do |name|
  path = File.join(__dir__, name)
  raise "Thiếu file Xoay Vân Ván: #{name}" unless File.file?(path)
  File.binread(path).force_encoding('UTF-8')
end.join
eval(code, TOPLEVEL_BINDING, File.join(__dir__, 'grain_tool_combined.rb'))
