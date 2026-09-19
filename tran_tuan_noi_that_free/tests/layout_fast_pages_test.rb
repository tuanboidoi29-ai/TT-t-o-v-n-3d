require_relative 'layout_restore_155_test'
require 'tmpdir'
load File.expand_path('../files/tran_tuan_noi_that/layout_stats_v101_fast_pages.rb',__dir__)
module Sketchup
  class << self
    attr_accessor :active_model
    def set_status_text(*); end
  end
end
module UI
  class << self
    attr_accessor :destination,:prompts
    def savepanel(*); @prompts=(@prompts||0)+1; @destination; end
    def messagebox(*); end
  end
end
module Layout
  module PageInfo; RESOLUTION_MEDIUM=1; end
  class Pages < Array
    def add(name); page=Struct.new(:name).new(name); self << page; page; end
  end
  class Document
    VERSION_2022=2022
    attr_reader :pages,:page_info,:layers
    def initialize;@pages=Pages.new;@pages.add('first');@page_info=Struct.new(:output_resolution).new;@layers=[Object.new];end
    def export(path,**_);File.write(path,'pdf');true;end
    def save(path,*);File.write(path,'layout');true;end
  end
end
class ModelDouble
  attr_accessor :copies
  def initialize;@copies=0;end
  def path;'';end
  def active_path;nil;end
  def save(*);raise 'User model must not be saved';end
  def save_copy(path);@copies+=1;File.write(path,'skp');true;end
end
m=TranTuanNoiThat::LayoutStats
class << m
  attr_accessor :viewports,:statistics_start,:scene_calls
  def setup_a3(*);end
  def ensure_layout_api!;end
  def tt_add_compact_header(*);end
  def tt_add_statistics_pages(_doc,_layer,_stats,start);@statistics_start=start;end
  def tt_add_scene_viewport(_doc,_layer,page,_path,scene,*);(@viewports||=[]) << [page,scene];end
  def tt_layout_jobs;[{index:1,name:'Cabinet',stats:{}}];end
  def tt_prepare_export_scenes_for_job(*);@scene_calls=(@scene_calls||0)+1;FAST_VIEWS.each_with_index.to_h { |(key,_),i| [key,i+1] };end
  def tt_output_path(base,*);base;end
end
# Singleton constant lookup above uses lexical module scope; provide explicit constant.
def m.tt_prepare_export_scenes_for_job(*)
 @scene_calls=(@scene_calls||0)+1
 TranTuanNoiThat::LayoutStats::FAST_VIEWS.each_with_index.to_h { |(key,_),i| [key,i+1] }
end
def assert(v,msg);raise msg unless v;end
Dir.mktmpdir do |dir|
 Sketchup.active_model=ModelDouble.new
 UI.destination=nil;UI.prompts=0
 assert(m.tt_fast_export(:pdf)==false,'cancel')
 assert(Sketchup.active_model.copies==0 && !m.scene_calls,'cancel has no saves/scenes')
 UI.destination=File.join(dir,'test.pdf');UI.prompts=0
 m.tt_fast_export(:pdf)
 assert(UI.prompts==1 && Sketchup.active_model.copies==1,'one prompt and one save_copy')
 assert(m.viewports.size==12 && m.viewports.map(&:first).uniq.size==12,'one viewport on each page')
 assert(m.statistics_start==13,'statistics starts after views')
 UI.destination=File.join(dir,'test.layout');UI.prompts=0
 m.tt_fast_export(:layout)
 assert(UI.prompts==1,'one layout prompt')
 assert(Dir.glob(File.join(dir,'TT_LAYOUT_NGUON_*','model.skp')).size==1,'retained linked source')
end
assert(m.tt_page_required(:front)==1,'single preview image per page')
assert(m.dialog_html.include?("sketchup.export_pdf(document.getElementById('cut').value)"),'export uses current cut input')
puts 'Fast export checks passed: one prompt/copy, cancellation, 12 separate pages and retained LayOut source'
