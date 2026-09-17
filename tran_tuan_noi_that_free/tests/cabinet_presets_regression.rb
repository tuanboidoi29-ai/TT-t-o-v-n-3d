require_relative 'cabinet_snap_regression'
module TranTuanNoiThat
  @test_store={}
  def self.setting(k,d=nil);@test_store.fetch(k,d);end
  def self.save_setting(k,v);@test_store[k]=v;end
end
presets=D.built_in_presets
assert(presets.length==8)
assert(presets.map { |p| p['id'] }.uniq.length==8)
presets.each { |p| assert(D.preset_svg(p['settings']).include?('<polygon')) }
custom=D.save_preset('Huỳnh riêng',D.defaults.merge('style'=>'Cánh soi huỳnh','bevel'=>18))
assert(D.custom_presets.first==custom)
D.save_preset('Huỳnh riêng',D.defaults)
assert(D.custom_presets.length==2)
assert(D.custom_presets.map { |p| p['id'] }.uniq.length==2)
rejects { D.save_preset('',D.defaults) }
rejects { D.save_preset('Sai',D.defaults.merge('thickness'=>-1)) }
html=D.gallery_html(presets+D.custom_presets)
assert(!html.include?('<input'))
assert(html.include?('use_preset') && html.include?('customize'))
hostile=D.save_preset('<script>alert(1)</script>',D.defaults)
assert(!D.gallery_html([hostile]).include?('<script>alert(1)</script>'))
original=TranTuanNoiThat.setting('cabinet_door_presets_v1')
TranTuanNoiThat.save_setting('cabinet_door_presets_v1','corrupt')
rejects { D.save_preset('Do not overwrite',D.defaults) }
assert(TranTuanNoiThat.setting('cabinet_door_presets_v1')=='corrupt')
TranTuanNoiThat.save_setting('cabinet_door_presets_v1',original)
# The routed preview must distinguish flat frame, bevel and recessed floor.
part=D.layout(500,760,D.defaults.merge('style'=>'Cánh soi huỳnh','cols'=>1)).first[:parts].first
colors=part[:faces].map { |face| D.face_color(part,face) }.uniq
assert(colors.include?([235,193,140,255]))
assert(colors.include?([183,130,78,255]))
assert(colors.length>=4)
# Opening the command shows the gallery; only its TAB callback calls settings.
module UI
  class HtmlDialog
    STYLE_DIALOG=0
    attr_reader :html,:callbacks
    def initialize(**args);@callbacks={};end
    def visible?;false;end
    def set_html(s);@html=s;end
    def add_action_callback(k,&b);@callbacks[k]=b;end
    def show;end
    def close;end
  end
end
D.show
palette=D.instance_variable_get(:@gallery)
assert(palette.html.include?('MẪU CÁNH TỦ'))
assert(!palette.html.include?('Áp dụng & xem trước'))
D.shown_tool=:not_called
palette.callbacks['customize'].call(nil)
assert(D.shown_tool.nil?)
File.write('/tmp/tt_huynh_preview.svg',D.preset_svg(presets.find { |p| p['id']=='builtin_panel2' }['settings']))
puts "PASS #{$count} total assertions including preset persistence, gallery entry and routed preview shading."
