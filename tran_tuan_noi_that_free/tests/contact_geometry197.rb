$LOADED_FEATURES << 'sketchup.rb'
module TranTuanNoiThat; ROOT = '/tmp/tt_contact_test'; end
module Sketchup
  def self.active_model; @model ||= Struct.new(:layers).new([:untagged]); end
end
require_relative '../files/tran_tuan_noi_that/contact_tool'
class EdgeDouble
  attr_accessor :layer, :hidden, :soft, :smooth
  attr_reader :faces
  def initialize(count)
    @faces = Array.new(count) { Object.new }
    @layer = :hidden_machining_tag
    @hidden = @soft = @smooth = true
  end
  def valid?; true; end
  def find_faces; 0; end
end
def check(value); raise 'FAILED' unless value; end
tool = TranTuanNoiThat::ContactTool
edges = Array.new(4) { EdgeDouble.new(2) }
check(tool.heal_contact_topology(edges))
edges.each do |e|
  check(e.layer == :untagged)
  check(!e.hidden && !e.soft && !e.smooth)
end
[0,1,3].each do |count|
  edge = EdgeDouble.new(count)
  begin
    tool.heal_contact_topology([edge])
    raise 'Accepted detached/nonmanifold geometry'
  rescue RuntimeError => e
    check(e.message.include?('chưa chia Face'))
    check(edge.layer == :hidden_machining_tag)
  end
end
bad = EdgeDouble.new(2)
def bad.find_faces; raise 'native failure'; end
begin
  tool.heal_contact_topology([bad])
  raise 'Swallowed native error'
rescue RuntimeError => e
  check(e.message == 'native failure')
end
puts 'PASS: attached edges visible/Untagged; detached and nonmanifold rejected; native error propagated'
module Sketchup
  class ComponentInstance; end
  class Group
    attr_reader :entities, :attrs
    def initialize(entities); @entities=entities; @attrs=[]; end
    def set_attribute(*args); @attrs << args; end
  end
end
class EdgeDouble
  attr_reader :attrs
  def set_attribute(*args); (@attrs ||= []) << args; end
end
class PointDouble
  def transform(_); self; end
end
class TransformDouble
  def inverse; self; end
end
class EntitiesDouble
  attr_reader :edges
  def initialize(count); @count=count; @edges=[]; end
  def add_line(*_); edge=EdgeDouble.new(@count); @edges << edge; edge; end
  # No add_group API: creating a secondary group fails this test.
end
model=Sketchup.active_model
def model.start_operation(*_); @result=:started; end
def model.commit_operation; @result=:committed; end
def model.abort_operation; @result=:aborted; end
def model.result; @result; end
plan={valid:true,points:Array.new(4){PointDouble.new},options:{'instance_name'=>'sample'},rotation_deg:0}
entities=EntitiesDouble.new(2)
target=Sketchup::Group.new(entities)
tool.create_contact(target,TransformDouble.new,plan)
check(model.result==:committed && entities.edges.length==4)
check((target.attrs+entities.edges.flat_map(&:attrs)).none?{|a| a.first=='ABF'})
check(entities.edges.all?{|e|e.layer==:untagged})
begin
  tool.create_contact(Sketchup::Group.new(EntitiesDouble.new(1)),TransformDouble.new,plan)
  raise 'Accepted detached profile'
rescue RuntimeError => e
  check(e.message.include?('chưa chia Face') && model.result==:aborted)
end
puts 'PASS: create uses host edges only, no ABF attributes, no child groups; invalid topology aborts operation'
