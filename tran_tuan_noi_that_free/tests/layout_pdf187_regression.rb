# No native renderer: verifies temporary reference lifetime and no save on the user's SKP.
require 'tmpdir'
module Sketchup
  class << self;attr_accessor :active_model;end
end
module UI
  @timers={};@id=0;@panels=[]
  class << self
    attr_accessor :target
    attr_reader :panels
    def savepanel(*args);@panels<<args;target;end
    def start_timer(*args,&block);@id+=1;@timers[@id]=block;@id;end
    def stop_timer(id);@timers.delete(id);end
    def drain
      count=0
      until @timers.empty?
        id,block=@timers.first;@timers.delete(id);block.call
        count+=1;raise 'timer runaway' if count>100
      end
    end
  end
end
module TranTuanNoiThat
  module LayoutStats
    extend self
    def ensure_layout_api!;end
    def ensure_model_saved(*args);raise 'MUST NOT ASK TO SAVE SKP';end
    def tt_output_path(target,*args);target;end
  end
end
load ENV.fetch('TT_LAYOUT_SOURCE')
class UnsavedModel
  attr_accessor :path,:fail_copy
  attr_reader :copies
  def initialize(path='');@path=path;@copies=[];end
  def save(*args);raise 'MUST NOT SAVE USER MODEL';end
  def save_copy(path)
    @copies<<path
    File.binwrite(path,'current unsaved geometry and prepared scenes')
    !fail_copy
  end
end
class Dialog
  attr_reader :scripts
  def initialize;@scripts=[];end
  def execute_script(s);@scripts<<s;end
end
class ExportDocument
  Page=Struct.new(:name)
  attr_reader :pages
  def initialize(path,fail_export);@path=path;@fail=fail_export;@pages=[Page.new('Mặt đứng')];end
  def export(target,options)
    raise 'source deleted too early' unless File.read(@path)=='current unsaved geometry and prepared scenes'
    raise 'injected export failure' if @fail
    File.binwrite(target,File.extname(target)=='.png' ? "\x89PNG\r\n\x1a\n".b+'stub' : '%PDF-stub')
  end
end
T=TranTuanNoiThat::LayoutTechnical
module TranTuanNoiThat::LayoutTechnical
  attr_accessor :fail_export
  def check_jobs(o);[{name:'Tủ MDF'}];end
  def prepare_scenes(*args);{'front'=>1};end
  def build_document(job,path,scenes,o)
    raise 'missing source while building document' unless File.file?(path)
    ExportDocument.new(path,fail_export)
  end
end
$count=0
def assert(v,msg);raise msg unless v;$count+=1;end
def rejects(message)
  begin;yield;rescue StandardError=>e;assert(e.message.include?(message),'wrong error: '+e.message);return;end
  raise 'expected failure'
end
Dir.mktmpdir('TT_test187_') do |dir|
  dialog=Dialog.new;T.instance_variable_set(:@dialog,dialog)
  options=T.normalize({})
  model=UnsavedModel.new;Sketchup.active_model=model;T.instance_variable_set(:@model,model)
  UI.target=File.join(dir,'Trực tiếp.pdf')
  T.run('pdf',options)
  assert(File.file?(UI.target),'unsaved model exports PDF')
  assert(model.path.empty?,'model remains untitled')
  assert(UI.panels.size==1 && UI.panels.first.last.end_with?('.pdf'),'only PDF output dialog shown')
  assert(!File.exist?(File.dirname(model.copies.last)),'source removed after export')
  original=File.join(dir,'existing.skp');File.write(original,'old on disk')
  model.path=original;T.run('pdf',options)
  assert(File.read(original)=='old on disk' && model.path==original,'existing SKP not overwritten or renamed')
  before=model.copies.size;UI.target=nil;T.run('pdf',options)
  assert(model.copies.size==before,'cancel output before creating source')
  UI.target=File.join(dir,'error.pdf');model.fail_copy=true
  rejects('Không tạo được bản sao tạm'){T.run('pdf',options)}
  assert(!File.exist?(File.dirname(model.copies.last)),'failed copy cleaned')
  model.fail_copy=false;T.fail_export=true
  rejects('injected export failure'){T.run('pdf',options)}
  assert(!File.exist?(File.dirname(model.copies.last)),'export failure source cleaned')
  T.fail_export=false
  before=UI.panels.size;T.run('preview',options);source=model.copies.last
  assert(File.file?(source),'source retained during asynchronous preview')
  assert(UI.panels.size==before,'preview does not prompt any save dialog')
  UI.drain
  assert(T.instance_variable_get(:@preview_pages).size==1,'preview rendered with live source')
  assert(!File.exist?(File.dirname(source)),'source cleaned after preview completion')
  T.run('preview',options);source=model.copies.last;T.finish_preview('cancelled');UI.drain
  assert(!File.exist?(File.dirname(source)) && !T.instance_variable_get(:@busy),'cancel releases temp source and busy state')
  T.fail_export=true;T.run('preview',options);source=model.copies.last;UI.drain
  assert(!File.exist?(File.dirname(source)) && dialog.scripts.last.include?('injected export failure'),'preview failure releases source and shows error')
  T.clear_preview_files
end
puts "PASS #{$count} direct PDF/temporary SKP checks; native export not tested."
