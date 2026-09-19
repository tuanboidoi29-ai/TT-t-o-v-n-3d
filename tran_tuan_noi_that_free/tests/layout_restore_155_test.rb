require 'json'
module TranTuanNoiThat; end
base = File.expand_path('../files/tran_tuan_noi_that',__dir__)
chain = %w[layout_stats_tool layout_stats_v030_patch layout_stats_v040_compat layout_stats_v040_patch layout_stats_v040_compat layout_stats_v040_compat layout_stats_v040_patch layout_stats_v040_compat layout_stats_v050_stable_preview layout_stats_v060_compact_scope layout_stats_v070_export_split layout_stats_v080_five_pages layout_stats_v081_cut_offset_fix layout_stats_v090_technical_dim]
2.times do
 TranTuanNoiThat.send(:remove_const,:LayoutStats) if TranTuanNoiThat.const_defined?(:LayoutStats,false)
 chain.each { |stem| load File.join(base,stem+'.rb') }
 m=TranTuanNoiThat::LayoutStats
 raise 'Wrong legacy version' unless m::VERSION=='0.9.0'
 raise 'Wrong UI route' unless m.method(:show).source_location.first.include?('layout_stats_')
 html=m.dialog_html
 raise 'Missing legacy DIM page handler' unless m.method(:tt_page_required).source_location.first.end_with?('layout_stats_v090_technical_dim.rb')
 raise 'Empty legacy UI' unless html.include?('<html')
 raise 'Unexpected new UI' if html.include?('overview_style')
end
puts 'Legacy chain and HTML loaded twice with original 1.9.55 DIM page'
