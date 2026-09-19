require_relative '../files/tran_tuan_noi_that/dimension_tool'
module Sketchup
  class Group
    attr_accessor :name
    attr_reader :attributes, :entities
    def initialize(id=0); @id=id; @attributes={}; @entities=[]; end
    def persistent_id; @id; end
    def valid?; true; end
    def locked?; false; end
    def get_attribute(dict,key); @attributes[[dict,key]]; end
    def set_attribute(dict,key,value); @attributes[[dict,key]]=value; end
  end
  class ComponentInstance < Group; end
end
class Entities < Array
  attr_reader :erased
  def add_group; group=Sketchup::Group.new; self << group; group; end
  def erase_entities(old); @erased=old; old.each { |e| delete(e) }; end
end
class Model
  attr_reader :entities,:events
  def initialize; @entities=Entities.new; @events=[]; end
  def start_operation(*args); @backup=@entities.dup; @events << :start; end
  def commit_operation; @events << :commit; end
  def abort_operation; @entities.replace(@backup); @events << :abort; end
end
def assert(value,message); raise message unless value; end
# Allocate skips geometric SketchUp objects; test the transaction boundary only.
tool=TranTuanNoiThat::DetailDimensions::Tool.allocate
model=Model.new
root=Sketchup::Group.new(42)
old=Sketchup::Group.new;old.set_attribute('TT_FRONT_DIM','source','42');model.entities << old
other=Sketchup::Group.new;other.set_attribute('TT_FRONT_DIM','source','99');model.entities << other
tool.instance_variable_set(:@model,model)
tool.instance_variable_set(:@roots,[root]);tool.instance_variable_set(:@specs,[[1,2,3,:total]])
tool.instance_variable_set(:@cursor,[0,0,0])
def tool.render_dimension(*args); raise 'font failure'; end
begin;tool.commit;rescue RuntimeError => e;raise unless e.message=='font failure';end
assert(model.events==[:start,:abort],'failed render aborts')
assert(model.entities.include?(old),'failure preserves previous DIM')
assert(model.entities.erased.nil?,'never erase before successful render')
def tool.render_dimension(*args); true; end
tool.commit
assert(model.events.last(2)==[:start,:commit],'one operation for update')
assert(!model.entities.include?(old) && model.entities.include?(other),'replace only matching cabinet DIM')
assert(model.entities.size==2,'no duplicate DIM group')
puts 'Update transaction and failed-render rollback checks passed'
