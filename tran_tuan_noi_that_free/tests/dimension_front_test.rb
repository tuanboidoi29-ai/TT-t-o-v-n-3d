# Run with Ruby, no SketchUp required. Real geometry rendering needs SketchUp.
require_relative '../files/tran_tuan_noi_that/dimension_tool'
def assert(value, message); raise message unless value; end
m = TranTuanNoiThat::DetailDimensions
# Millimetre-space fixtures; the sweep is unit independent.
left = [[0,0,0],[18,550,800]]
right = [[582,0,0],[600,550,800]]
bottom = [[18,0,0],[582,550,18]]
top = [[18,0,782],[582,550,800]]
back = [[18,541,18],[582,550,782]]
door = [[0,-18,0],[600,0,800]]
parts = [left,right,bottom,top,back,door]
assert(m.openings(parts,1) == [[18,582,18,782]],'clear opening excludes board thickness, back and door')
divider = [[291,0,18],[309,550,782]]
assert(m.openings(parts+[divider],1) == [[18,291,18,782],[309,582,18,782]],'divider creates two clear widths')
shelf = [[18,0,390],[582,550,408]]
assert(m.openings(parts+[shelf],1) == [[18,582,18,390],[18,582,408,782]],'shelf splits compartments vertically')
assert(m.openings([left],1).empty?,'one wall never invents an opening')
assert(m.openings([back,door],1).empty?,'thin depth panels are not cavity walls')
assert(m.marks([0,0.01,17.5,599.9,600],1) == [0,17.5,600],'thin board and exact overall end')
puts '6 front-dimension geometry checks passed'
