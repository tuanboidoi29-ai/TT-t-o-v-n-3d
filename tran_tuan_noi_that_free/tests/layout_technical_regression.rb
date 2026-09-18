# Strict contract doubles; this does not execute the native SketchUp/LayOut renderer.
require 'json'
module Sketchup
  class Color
    attr_reader :rgb
    def initialize(*rgb); @rgb=rgb; end
  end
  def self.read_default(a,b,d); (@defaults||={}).fetch([a,b],d); end
  def self.write_default(a,b,v); (@defaults||={})[[a,b]]=v; end
end
module Geom
  Point2d=Struct.new(:x,:y)
  Point3d=Struct.new(:x,:y,:z)
  class Bounds2d
    attr_reader :values
    def initialize(*a);@values=a;end
  end
end
module Layout
  class Style
    DECIMAL_MILLIMETERS=1;ARROW_SLASH_RIGHT=2;DIMENSION_TEXT=3
    attr_accessor :stroke_color,:start_arrow_type,:end_arrow_type,:start_arrow_size,:end_arrow_size
    attr_reader :units
    def set_dimension_units(*args);@units=args;end
    def get_sub_style(type);Style.new;end
    def set_sub_style(*args);end
    attr_accessor :solid_filled,:pattern_filled,:stroked,:stroke_width,:font_family,:font_size,:text_bold,:text_color
  end
  class FormattedText
    ANCHOR_TYPE_TOP_LEFT=0
    attr_reader :value,:applied_style
    def initialize(value,*a);@value=value;end
    def style(i);Style.new;end
    def apply_style(style,*a);@applied_style=style;end
  end
  class Table
    Cell=Struct.new(:data);Column=Struct.new(:width)
    attr_reader :bounds,:cells,:columns,:dimensions
    def initialize(bounds,rows,cols)
      @bounds=bounds;@dimensions=[rows,cols];@cells=Array.new(rows){Array.new(cols){Cell.new}};@columns=Array.new(cols){Column.new}
    end
    def [](r,c);@cells.fetch(r).fetch(c);end
    def get_column(i);@columns.fetch(i);end
  end
  class Rectangle
    attr_accessor :style
    def initialize(b);@style=Style.new;end
  end
  class Layer
    attr_accessor :name
    attr_reader :shared
    def initialize(n,s=false);@name=n;@shared=s;end
  end
  class Layers < Array
    attr_accessor :active
    def add(n,s=false); x=Layer.new(n,s);self<<x;x;end
  end
  class Page
    attr_accessor :name
    def initialize(n);@name=n;end
  end
  class Pages < Array
    def add(n);x=Page.new(n);self<<x;x;end
  end
  class AutoTextDefinition
    TYPE_CUSTOM_TEXT=1;TYPE_PAGE_NUMBER=2
    attr_accessor :name,:custom_text,:start_index,:start_page
    def initialize(n);@name=n;end
    def tag;"<#{name}>";end
  end
  class AutoTexts < Array
    def add(n,t);x=AutoTextDefinition.new(n);self<<x;x;end
  end
  class Document
    attr_accessor :object_snap_enabled,:grid_snap_enabled,:render_mode_override
    attr_reader :layers,:pages,:auto_text_definitions,:entities
    def initialize
      @layers=Layers.new;@layers.add('Default');@pages=Pages.new;@pages.add('First');@auto_text_definitions=AutoTexts.new;@entities=[]
    end
    def add_entity(e,l,p=nil)
      raise 'page missing' unless l.shared || p
      @entities<<[e,l,p]
    end
  end
  class LinearDimension
    attr_accessor :auto_scale,:scale,:custom_text,:start_extent_point,:end_extent_point,:start_offset_length,:end_offset_length,:style
    attr_reader :a,:b
    def initialize(a,b,height);@a=a;@b=b;@style=Style.new;end
  end
  class SketchUpModel
    NO_OVERRIDE=0;VECTOR_RENDER=1;HYBRID_RENDER=2
    attr_accessor :display_background,:render_mode,:preserve_scale_on_resize,:line_weight
    attr_reader :scale,:events,:current_scene
    def initialize(path,bounds);@events=[];end
    def current_scene=(n);@current_scene=n;@events<<:scene;end
    def model_to_paper_point(p)
      s=scale||0.05
      case current_scene
      when 1 then Geom::Point2d.new(2+p.x*s,7-p.y*s)
      when 3,4,6,7 then Geom::Point2d.new(2+p.y*s,7-p.z*s)
      else Geom::Point2d.new(2+p.x*s,7-p.z*s)
      end
    end
    def perspective?;false;end
    def scale=(s);raise 'scale before scene' unless current_scene;@scale=s;@events<<:scale;end
    def render_needed?;true;end
    def render;@events<<:render;end
  end
end
module TranTuanNoiThat
  module LayoutStats
    extend self
    def setup_a3(doc);end
    def format_mm(v);format("%g",v.to_f);end
    def dark;Sketchup::Color.new(0,0,0);end
    def add_text(doc,layer,page,*args);doc.add_entity(args,layer,page);args;end
    def add_stats_table(doc,layer,page,rows);doc.add_entity(rows,layer,page);end
  end
end
load (ENV['TT_LAYOUT_SOURCE'] || File.expand_path('../release183/tran_tuan_noi_that/layout_technical.rb',__dir__))
T=TranTuanNoiThat::LayoutTechnical
$count=0
def assert(v,msg);raise msg unless v;$count+=1;end
def rejects(msg)
  begin;yield;rescue StandardError;$count+=1;return;end
  raise msg
end
options=T.normalize({})
assert(options['scale']==20,'default scale')
rejects('zero scale accepted'){T.normalize('scale'=>0)}
rejects('nonfinite accepted'){T.normalize('scale'=>Float::INFINITY)}
rejects('missing views accepted'){T.normalize('views'=>[])}
rejects('unknown view accepted'){T.normalize('views'=>['fake'])}
rejects('invalid compression accepted'){T.normalize('quality'=>49)}
rejects('invalid cut accepted'){T.normalize('cut_mm'=>-1)}
T.persist(options)
assert(T.settings==options,'preferences roundtrip')
Box=Struct.new(:width,:height,:depth) do
  def corner(i);Geom::Point3d.new((i&1)==0 ? 0 : width,(i&2)==0 ? 0 : height,(i&4)==0 ? 0 : depth);end
end
bb=Box.new(6000.0/25.4,600.0/25.4,2400.0/25.4)
assert(T.fit_error('front',bb,options).nil?,'6m cabinet fits at 1:20')
assert(T.fit_error('front',bb,options.merge('scale'=>10)).include?('không vừa'),'oversized rejected')
assert(T.projected_size('top',bb).map(&:round)==[6000,600],'plan projected axes')
assert(T.projected_size('left',bb).map(&:round)==[600,2400],'side projected axes')
assert(T.denominator('cut_front',options.merge('cut_scale'=>5))==5,'independent cut scale')
job={bounds:bb,name:'Bếp mẫu',stats:{rows:Array.new(41){|i|{stt:i+1}}}}
scenes=options['views'].each_with_index.to_h.transform_values{|i|i+1}
doc=T.build_document(job,'test.skp',scenes,options)
vp=doc.entities.map(&:first).grep(Layout::SketchUpModel)
assert(vp.size==8,'8 views')
if options['dimensions']
  dimensions=doc.entities.map(&:first).grep(Layout::LinearDimension)
  assert(dimensions.size==14,'two dimensions for each orthographic page')
  assert(dimensions.all?{|d|d.scale==0.05 && d.custom_text==false && d.auto_scale==false},'native dimensions use true viewport scale')
  measures=dimensions.first(4).map{|d|(Math.hypot(d.a.x-d.b.x,d.a.y-d.b.y)/d.scale*25.4).round(1)}
  assert(measures==[6000.0,600.0,6000.0,2400.0],'top and front dimension values in mm')
  assert(dimensions[0].start_extent_point.y>dimensions[0].a.y,'horizontal dimension outside below')
  assert(dimensions[1].start_extent_point.x<dimensions[1].a.x,'vertical dimension outside left')
  assert(dimensions.all?{|d|d.style.units==[1,0.1]},'mm precision')
end
assert(vp.all?(&:preserve_scale_on_resize),'all preserve scale')
assert(vp.first(7).all?{|v|v.scale==0.05},'technical exact 1:20')
assert(vp.last.scale.nil?,'perspective not labelled scaled')
assert(vp.first(7).all?{|v|v.render_mode==1} && vp.last.render_mode==2,'vector/hybrid split')
assert(vp.all?{|v|v.events.last==:render},'native render requested')
assert(doc.object_snap_enabled==true,'object snap')
assert(doc.layers.map(&:name)==['Đồ gỗ','Chú thích','Dim','Khung tên','Thống kê'],'layer separation')
assert(doc.layers.active.name=='Dim','ready for linked manual dimensions')
assert(doc.pages.size==12,'8 drawing + 4 legible statistics pages')
tables=doc.entities.map(&:first).grep(Layout::Table)
assert(tables.flat_map{|t|t.cells.drop(1)}.size==41,'all statistics rows retained across page breaks')
assert(tables.all?{|t|t.dimensions[0]<=12},'at most 11 body rows at 14pt')
assert(tables.all?{|t|t.cells.flatten.all?{|c|c.data.applied_style.font_size==14}},'14pt applies to every header and body cell')
assert(tables.all?{|t|(t.columns.sum(&:width)*25.4-390).abs<0.01},'table columns fit 390mm print width')
assert(tables.all?{|t|(t.bounds.values[1]+t.bounds.values[3])*25.4<260},'statistics stay above title block')
assert(T.stats_rows_per_page(options.merge('stats_font'=>18))<T.stats_rows_per_page(options),'larger text gets fewer rows')
rejects('too small statistics font accepted'){T.normalize('stats_font'=>8)}
assert(doc.auto_text_definitions.map(&:tag)==['<Project Name>','<PageNumber>'],'real autotext tokens')
assert(doc.entities.any?{|e,l,p| l.shared && p.nil?},'shared title block')
keys=%w[DisplaySectionCuts DisplaySectionPlanes SectionCutFilled SectionCutDrawEdges SectionDefaultFillColor SectionDefaultCutColor Texture RenderMode]
render=keys.to_h{|k|[k,nil]}
T.profile(render,true,false)
assert(render['SectionCutFilled']==true && render['SectionDefaultFillColor'].rgb==[0,0,0],'black section fill')
T.profile(render,false,true)
assert(render['SectionCutFilled']==false && render['Texture']==true,'hybrid materials')
# Reload must still route the toolbar to the new exporter, without alias recursion.
load (ENV['TT_LAYOUT_SOURCE'] || File.expand_path('../release183/tran_tuan_noi_that/layout_technical.rb',__dir__))
assert(TranTuanNoiThat::LayoutStats.method(:show).source_location.first.end_with?('layout_technical.rb'),'reload routing')
File.write(File.expand_path('../output/layout183_ui.html',__dir__),T.html)
puts "PASS #{$count} contract/logic checks; native renderer not tested."
require 'ostruct'
class SceneDouble
  attr_accessor :name,:use_camera,:use_rendering_options,:use_section_planes,:use_hidden,:use_hidden_objects,:use_hidden_layers,:include_in_animation,:use_shadow_info
  attr_reader :rendering_options
  def initialize(n,render);@name=n;@rendering_options=render.dup;@attrs={};end
  def get_attribute(d,k);@attrs[[d,k]];end
  def set_attribute(d,k,v);@attrs[[d,k]]=v;end
  def update;end
end
class SceneList < Array
  def initialize(render);@render=render;end
  def add(n);s=SceneDouble.new(n,@render);self<<s;s;end
end
class ModelDouble
  attr_reader :rendering_options,:styles,:shadow_info,:pages,:entities,:active_view,:operations
  def initialize(render)
    @rendering_options=render.dup;@styles=OpenStruct.new(selected_style: :original)
    @shadow_info={'DisplayShadows'=>true};@pages=SceneList.new(render)
    @entities=OpenStruct.new(active_section_plane: :user_plane);@active_view=OpenStruct.new(camera: :user_camera);@operations=[]
  end
  def start_operation(*a);@operations<<:start;end
  def commit_operation;@operations<<:commit;end
  def abort_operation;@operations<<:abort;end
end
module TranTuanNoiThat::LayoutStats
  def tt_capture_model_state(m);{camera:m.active_view.camera,active_section:m.entities.active_section_plane};end
  def tt_scope_visibility_state(m);[];end
  def tt_apply_scope_visibility(*a);end
  def tt_restore_scope_visibility(*a);end
  def tt_restore_model_state(m,s)
    m.active_view.camera=s[:camera];m.entities.active_section_plane=s[:active_section];m.rendering_options.replace(s[:render])
  end
  def tt_ensure_section_planes_for_job(m,*a)
    raise 'planes outside transaction' unless m.operations.last==:start
    {cut_front: :front_plane,cut_left: :left_plane,cut_right: :right_plane}
  end
  def tt_scene_layout_index(m,p);m.pages.index(p)+1;end
end
module TranTuanNoiThat::LayoutTechnical
  def camera(key,bb);key;end
end
model=ModelDouble.new(render)
job[:key]='job-123';job[:roots]=[];job[:bounds]=bb
original=model.rendering_options.dup
result=T.prepare_scenes(model,job,options)
assert(result.size==8 && model.operations==[:start,:commit],'scene operation')
assert(model.rendering_options==original && model.active_view.camera==:user_camera && model.entities.active_section_plane==:user_plane,'restore render/camera/section')
assert(model.shadow_info['DisplayShadows']==true && model.styles.selected_style==:original,'restore shadows/style')
assert(model.pages.find{|p|p.name.include?('cắt thùng trước')}.rendering_options['SectionCutFilled']==true,'section scene stores fill')
assert(model.pages.all?{|p|p.use_camera && p.use_rendering_options && p.use_hidden && !p.include_in_animation},'scene saved flags')
T.prepare_scenes(model,job,options)
assert(model.pages.size==8,'repeat updates scenes')
module TranTuanNoiThat::LayoutTechnical
  def camera(key,bb);raise 'injected scene failure';end
end
rejects('scene failure swallowed'){T.prepare_scenes(model,job,options)}
assert(model.operations.last==:abort && model.active_view.camera==:user_camera && model.rendering_options==original,'abort restores state')
puts "PASS #{$count} total contract/logic checks; native renderer not tested."
