require_relative '../files/tran_tuan_noi_that/dimension_tool'
def assert(condition, message)
  raise message unless condition
end
m = TranTuanNoiThat::DetailDimensions
assert(m.marks([],1) == [], 'empty')
assert(m.marks([0,0,18,18,582,600],1) == [0,18,582,600], 'board boundaries')
assert(m.marks([600,18,0,582,18],1) == [0,18,582,600], 'sort and deduplicate')
assert(m.marks([0,0.01,17.5,599.9,600],1) == [0,17.5,600], 'thin board and overall maximum')
assert(m.marks([0,0.01],1) == [0], 'ignore subminimum segment')
puts '5 dimension mark checks passed'
