module Sketchup
  def self.active_model;:model;end
end
module UI
  class HtmlDialog
    STYLE_DIALOG=0
    attr_reader :callbacks,:scripts
    def initialize(**args);@callbacks={};@scripts=[];end
    def set_html(s);end
    def add_action_callback(name,&b);@callbacks[name]=b;end
    def execute_script(s);@scripts<<s;end
    def set_on_closed(&b);@closed=b;end
    def show;end
    def visible?;false;end
  end
end
module TranTuanNoiThat;module LayoutStats;end;end
load ENV.fetch('TT_LAYOUT_SOURCE')
T=TranTuanNoiThat::LayoutTechnical
module TranTuanNoiThat::LayoutTechnical
  attr_accessor :fail_action
  attr_reader :actions
  def send_state;raise 'injected ready failure';end
  def dispatch(action,options);(@actions||=[])<<action;raise 'injected action failure' if fail_action;end
end
T.instance_variable_set(:@busy,true)
T.show
d=T.instance_variable_get(:@dialog)
raise 'stale busy persisted' if T.instance_variable_get(:@busy)
d.callbacks['ready'].call(nil)
raise 'missing defaults' unless d.scripts.any?{|s|s.start_with?('receive(')&&s.include?('stats_font')}
raise 'missing ready error' unless d.scripts.last.include?('injected ready failure')
%w[check save scenes layout preview pdf template].each do |action|
 d.callbacks['run'].call(nil,action,JSON.generate(T.normalize({})))
 raise 'not dispatched' unless T.actions.last==action
 raise 'not unlocked' unless d.scripts.last=='setBusy(false)' && !T.instance_variable_get(:@busy)
end
T.fail_action=true;d.callbacks['run'].call(nil,'pdf','{}')
raise 'error hidden' unless d.scripts.any?{|s|s.include?('injected action failure')}
raise 'locked after failure' if T.instance_variable_get(:@busy)
puts 'PASS dialog initialization fallback, 7 callbacks, stale busy reset and error unlocking; native UI not tested.'
