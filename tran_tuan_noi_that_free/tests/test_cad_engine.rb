require_relative '../files/tran_tuan_noi_that/cad_wall_engine'
E=TranTuanNoiThat::CadWallEngine
O={tolerance:2.0,widths:[110.0,220.0],min_length:250.0}
$count=0
def check(name);raise name unless yield;$count+=1;end
def edge(a,b,l='A-WALL');{a:a,b:b,layer:l};end
def pair(x1,x2,y=0,w=110);[edge([x1,y],[x2,y]),edge([x1,y+w],[x2,y+w])];end
check('Vietnamese wall'){E.label_kind('A-TƯỜNG')=='Tường'}
check('DIM excluded before wall'){E.label_kind('A-WALL-DIM').include?('Bỏ qua')}
check('hatch excluded'){E.label_kind('TUONG_HATCH').include?('Bỏ qua')}
check('window recognized'){E.label_kind('CỬA SỔ').include?('Cửa sổ')}
check('door recognized'){E.label_kind('A-DOOR').include?('Cửa đi')}
check('furniture excluded'){E.label_kind('NỘI THẤT').include?('bỏ qua')}
check('unknown explicit'){E.label_kind('Layer 12')=='Chưa phân loại'}
a=E.recognize(pair(0,4000),O)
check('one wall'){a.length==1 && a[0][:selected]}
check('true thickness'){a[0][:width]==110}
check('true length'){a[0][:length]==4000}
check('correct footprint'){E.footprint(a[0])==[[0.0,0.0],[4000.0,0.0],[4000.0,110.0],[0.0,110.0]]}
a=E.recognize(pair(0,1000)+pair(1900,4000),O)
check('door opening preserved'){a.length==2 && a.map{|w|w[:length]}.sort==[1000.0,2100.0]}
a=E.recognize(pair(0,2000)+pair(2000,4000),O)
check('fragment join'){a.length==1 && a[0][:length]==4000}
a=E.recognize(pair(0,4000)+pair(0,4000),O)
check('duplicate lines removed'){a.length==1}
a=E.recognize([edge([0,0],[4000,0]),edge([4000,110],[0,110])],O)
check('reverse direction'){a.length==1}
check('wrong thickness ignored'){E.recognize(pair(0,4000,0,600),O).empty?}
check('short strokes ignored'){E.recognize(pair(0,100),O).empty?}
check('different layers not paired'){E.recognize([edge([0,0],[4000,0],'a'),edge([0,110],[4000,110],'b')],O).empty?}
a=E.recognize(pair(0,4000)+[edge([0,220],[4000,220])],O)
check('ambiguous pairs disabled'){a.length==3 && a.none?{|w|w[:selected]}}
ang=Math::PI/6;rot=lambda{|p|[p[0]*Math.cos(ang)-p[1]*Math.sin(ang),p[0]*Math.sin(ang)+p[1]*Math.cos(ang)]}
a=E.recognize(pair(0,4000).map{|e|edge(rot.call(e[:a]),rot.call(e[:b]))},O)
check('diagonal wall'){a.length==1 && (a[0][:length]-4000).abs<1e-6 && (a[0][:width]-110).abs<1e-6}
outer=[[0,0],[4000,0],[4000,3000],[0,3000]];inner=[[110,110],[3890,110],[3890,2890],[110,2890]]
edges=[outer,inner].flat_map{|p|4.times.map{|i|edge(p[i],p[(i+1)%4])}}
a=E.recognize(edges,O)
check('four surrounding walls'){a.length==4 && a.all?{|w|w[:selected]}}
check('corners fill bounded by CAD'){a.map{|w|w[:length].round}.sort==[3000,3000,4000,4000]}
pts=a.flat_map{|w|E.footprint(w)}
check('no outside boundary'){pts.all?{|p|p[0]>=-1e-7 && p[0]<=4000.00001 && p[1]>=-1e-7 && p[1]<=3000.00001}}
check('gap not bridged by collinear merge'){E.consolidate(pair(0,1000)+pair(1010,4000),2).length==4}
check('diverging lines rejected'){E.recognize([edge([0,0],[4000,0]),edge([0,110],[4000,115])],O).empty?}
puts "#{$count} CAD geometry/classification checks passed"
