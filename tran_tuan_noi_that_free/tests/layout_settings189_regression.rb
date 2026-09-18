require 'tmpdir'
require 'json'
module Sketchup
  # Reproduces the readback failure from 1.9.83 on every preference read.
  def self.read_default(*a);'';end
  def self.write_default(*a);raise 'Registry must not be used for new saves';end
end
module TranTuanNoiThat; module LayoutStats;end;end
load (ENV['TT_LAYOUT_SOURCE'] || File.expand_path('../release184/tran_tuan_noi_that/layout_technical.rb',__dir__))
T=TranTuanNoiThat::LayoutTechnical
$count=0
def assert(v,m);raise m unless v;$count+=1;end
def rejects(m)
  begin;yield;rescue StandardError;$count+=1;return;end
  raise m
end
Dir.mktmpdir('TT_layout_test_') do |dir|
  original=ENV['APPDATA']
  ENV['APPDATA']=File.join(dir,'Tên người dùng')
  begin
    options=T.normalize('project'=>'Bếp "nhà" \\ tầng 1 — hậu phủ','scale'=>'25','views'=>['front','cut_front'])
    assert(T.persist(options)==true,'save with broken registry')
    assert(T.settings==options,'UTF-8 and quotes roundtrip')
    path=T.config_path
    assert(File.file?(path),'real JSON file')
    assert(JSON.parse(File.read(path))['project']==options['project'],'not escaped twice')
    changed=options.merge('scale'=>10.0)
    T.persist(changed)
    assert(T.settings==changed,'overwrite existing config')
    assert(Dir.children(File.dirname(path))==[File.basename(path)],'temporary files removed')
    File.write(path,'corrupt')
    assert(T.settings['scale']==20,'corrupt config safe defaults')
    assert(T.instance_variable_get(:@config_warning).include?('Không đọc'),'corrupt config visible warning')
    T.persist(options)
    assert(T.settings==options,'save repairs config')
  ensure
    ENV['APPDATA']=original
  end
end
module TranTuanNoiThat::LayoutTechnical
  attr_reader :last_run,:last_report
  def persist(options);raise Errno::EACCES,'injected disk denied';end
  def run(action,options);@last_run=[action,options];report('Đã chạy');end
  def report(message,error=false);@last_report=message;end
  def check_jobs(options);[{name:'Tủ',stats:{total_pieces:6}}];end
end
o=T.normalize({})
T.dispatch('check',o)
assert(T.last_report.include?('6 chi tiết'),'check does not save')
%w[scenes layout pdf preview template].each do |action|
 T.dispatch(action,o)
 assert(T.last_run==[action,o],"#{action} blocked by preference failure")
 assert(T.instance_variable_get(:@config_warning).include?('Chưa lưu'),"#{action} silently lost save failure")
end
rejects('save falsely succeeds'){T.dispatch('save',o)}
rejects('unknown action allowed'){T.dispatch('unknown',o)}
puts "PASS #{$count} persistence/failure-path checks; native SketchUp not tested."
