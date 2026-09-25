# encoding: UTF-8
require 'tmpdir'
require_relative 'sketchup'

module TranTuanNoiThat
  NAME = 'TRẦN TUẤN NỘI THẤT'
  ROOT = Dir.mktmpdir('tt-door-tags-')
end

class << Sketchup
  def read_default(_section, key, default)
    (@tt_prefs ||= {}).fetch(key, default)
  end

  def write_default(_section, key, value)
    (@tt_prefs ||= {})[key] = value
  end
end

require_relative '../files/tran_tuan_noi_that/door_standard_tool'

class DoorTagLayer
  attr_reader :name
  def initialize(name); @name = name; end
end

class DoorTagLayers < Hash
  def add(name); self[name] = DoorTagLayer.new(name); end
end

class DoorTagGroup < Sketchup::Group
  attr_accessor :layer
  attr_reader :entities

  def initialize(layer, children = [])
    @layer = layer
    @entities = children
    @attributes = {}
  end

  def get_attribute(dict, key); @attributes[[dict, key]]; end
  def set_attribute(dict, key, value); @attributes[[dict, key]] = value; end
end

class DoorTagModel
  attr_reader :layers, :selection, :commits, :aborts

  def initialize(selection)
    @layers = DoorTagLayers.new
    @selection = selection
    @commits = 0
    @aborts = 0
  end

  def start_operation(*); end
  def commit_operation; @commits += 1; end
  def abort_operation; @aborts += 1; end
end

def assert(condition, message)
  raise message unless condition
end

begin
  door = TranTuanNoiThat::DoorStandard
  old = DoorTagLayer.new('Cánh tủ')
  child = DoorTagGroup.new(old)
  child.set_attribute(door::DICT, 'is_door', true)
  root = DoorTagGroup.new(old, [child])
  root.set_attribute(door::DICT, 'version', '1.9.145')
  unrelated = DoorTagGroup.new(old)
  model = DoorTagModel.new([root, unrelated])
  Sketchup.model = model

  first = door::DEFAULTS.merge('tag_name' => 'HAU P-9MM', 'thickness' => 9.0)
  door.save_preset('HAU P-9MM', first)
  door.save_preset('Mẫu khác', door::DEFAULTS.merge('tag_name' => 'Tag khác'))
  door.load_preset('Mẫu khác')
  saved, = door.load_preset('HAU P-9MM')
  assert(saved['tag_name'] == 'HAU P-9MM' && saved['thickness'] == 9.0,
         'Nạp lại mẫu không khôi phục Tag và độ dày')

  assert(door.sync_selected_instances_tag('HAU P-9MM', saved['tag_name']) == 1,
         'Không tìm thấy group cánh được chọn')
  assert(root.layer.name == 'HAU P-9MM' && child.layer.name == 'HAU P-9MM',
         'Group tổng hoặc cánh con chưa nhận Tag mới')
  assert(unrelated.layer.name == 'Cánh tủ', 'Đã sửa nhầm group không thuộc công cụ')
  assert(model.commits == 1 && model.aborts == 0, 'Cập nhật Tag phải có một lần Undo')

  updated = first.merge('tag_name' => 'HAU P-9MM MỚI', 'gap_vertical' => 3.0)
  door.save_preset('HAU P-9MM', updated, nil, 'HAU P-9MM')
  door.load_preset('Mẫu khác')
  again, = door.load_preset('HAU P-9MM')
  assert(again['tag_name'] == 'HAU P-9MM MỚI' && again['gap_vertical'] == 3.0,
         'Lưu lại và chọn lại mẫu không khôi phục đủ thông số')
  door.sync_selected_instances_tag('HAU P-9MM', again['tag_name'])
  assert(root.layer.name == 'HAU P-9MM MỚI' && child.layer.name == 'HAU P-9MM MỚI',
         'Instance đã chọn không nhận Tag khi lưu lại mẫu')

  puts 'Door preset and selected instance Tag regression: OK'
ensure
  require 'fileutils'
  FileUtils.remove_entry(TranTuanNoiThat::ROOT) if File.directory?(TranTuanNoiThat::ROOT)
end
