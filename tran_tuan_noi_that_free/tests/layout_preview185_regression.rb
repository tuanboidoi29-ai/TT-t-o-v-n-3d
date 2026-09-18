require 'tmpdir'
module Sketchup
  def self.active_model;:model;end
end
module UI
  @timers={};@id=0
  class << self
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
module TranTuanNoiThat;module LayoutStats;end;end
load File.expand_path('../release185/tran_tuan_noi_that/layout_technical.rb',__dir__)
class FakeDialog
  attr_reader :scripts
  def initialize;@scripts=[];end
  def execute_script(s);@scripts<<s;end
end
class PreviewDoc
  Page=Struct.new(:name)
  attr_reader :pages,:exports
  def initialize;@pages=[Page.new('Mặt đứng'),Page.new('Mặt cắt')];@exports=[];end
  def export(path,o)
    @exports<<o
    raise 'range mismatch' unless o[:start_page]==o[:end_page] && [0,1].include?(o[:start_page]) && o[:dpi]==150
    # Deliberately different filename, matching LayOut's documented image set behavior.
    File.binwrite(path.sub('.png',"_#{o[:start_page]+1}.png"),"\x89PNG\r\n\x1a\n".b+'stub image')
  end
end
T=TranTuanNoiThat::LayoutTechnical
module TranTuanNoiThat::LayoutTechnical
  attr_reader :built
  def build_document(*args);(@built||=[])<<PreviewDoc.new;@built.last;end
end
$count=0
def assert(v,m);raise m unless v;$count+=1;end
dialog=FakeDialog.new
T.instance_variable_set(:@dialog,dialog);T.instance_variable_set(:@model,:model)
jobs=[{name:'Bếp'},{name:'Tủ áo'}]
T.start_preview(jobs,'test.skp',[{},{}],{})
assert(T.instance_variable_get(:@busy),'preview busy')
UI.drain
pages=T.instance_variable_get(:@preview_pages)
assert(pages.size==4,'all jobs and pages rendered')
assert(pages.map{|p|p[:label]}==['Bếp · Mặt đứng','Bếp · Mặt cắt','Tủ áo · Mặt đứng','Tủ áo · Mặt cắt'],'page order and labels')
assert(!T.instance_variable_get(:@busy),'preview unlocks controls')
assert(T.built.all?{|d|d.exports.map{|o|o[:start_page]}==[0,1]},'zero-based page ranges')
assert(dialog.scripts.any?{|s|s.include?('data:image/png;base64,')},'embedded local image')
T.show_preview_page(3)
assert(dialog.scripts.last.include?('Tủ áo · Mặt cắt'),'select final page')
T.show_preview_page(-1)
assert(dialog.scripts.last.include?('không hợp lệ'),'negative index rejected')
oldfolder=T.instance_variable_get(:@preview_dir)
T.start_preview(jobs,'test.skp',[{},{}],{})
assert(!File.directory?(oldfolder),'old preview files cleaned')
stale=T.instance_variable_get(:@preview_state)
T.finish_preview('cancelled');T.preview_step(stale);UI.drain
assert(T.instance_variable_get(:@preview_pages).empty?,'cancelled timer ignored')
# Simulate closing dialog while pending.
T.start_preview(jobs,'test.skp',[{},{}],{})
T.instance_variable_set(:@dialog,nil);T.finish_preview(nil);T.clear_preview_files;UI.drain
assert(!T.instance_variable_get(:@busy),'close releases busy')
assert(T.instance_variable_get(:@preview_dir).nil?,'close clears temp directory')
# Native export failure must be visible and release the buttons.
T.instance_variable_set(:@dialog,dialog)
module TranTuanNoiThat::LayoutTechnical
  def build_document(*a);raise 'injected render error';end
end
T.start_preview(jobs,'test.skp',[{},{}],{});UI.drain
assert(!T.instance_variable_get(:@busy) && dialog.scripts.last.include?('injected render error'),'render failure visible and unlocked')
T.clear_preview_files
puts "PASS #{$count} preview pipeline checks; native rendering not tested."
