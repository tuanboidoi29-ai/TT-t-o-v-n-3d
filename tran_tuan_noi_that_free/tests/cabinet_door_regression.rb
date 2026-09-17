require 'json'
load File.join(ENV.fetch('TT_STRETCH_ROOT'), 'cabinet_door_tool.rb')
D=TranTuanNoiThat::CabinetDoor
$count=0
def assert(v);raise "Assertion #{$count+1}" unless v;$count+=1;end
def near(a,b);assert((a-b).abs<1e-6);end
def rejects
  begin;yield;rescue RuntimeError, ArgumentError; $count+=1;return;end
  raise 'Expected rejection'
end
def sub(a,b);a.zip(b).map { |x,y| x-y };end
def cross(a,b);[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];end
def dot(a,b);a.zip(b).sum { |x,y| x*y };end
def volume(faces)
  faces.sum { |f| (1...f.length-1).sum { |i| dot(f[0],cross(f[i],f[i+1]))/6.0 } }
end
s=D.defaults
flat=D.layout(1000,800,s)
assert(flat.length==2); near(flat[0][:width],497);near(flat[0][:height],796)
near(volume(flat[0][:parts][0][:faces]),497*796*17.5)
# Edge gaps and overlays are independent; inset depth leaves the front at offset.
x=D.layout(1000,800,s.merge('over_left'=>17.5,'over_right'=>17.5,'cols'=>1))[0]
near(x[:width],1031)
f=D.layout(1000,800,s.merge('fit'=>'Lọt lòng','over_left'=>100,'offset'=>3))[0][:parts][0][:faces].flatten(1)
near(f.map(&:last).min,3-17.5);near(f.map(&:last).max,3)
# Every type has closed directed edges after splitting collinear T-junctions.
def check_mesh(faces)
  verts=faces.flatten(1).uniq
  edges=Hash.new(0)
  faces.each do |f|
    assert(f.length>=3)
    assert(dot(cross(sub(f[1],f[0]),sub(f[2],f[0])),cross(sub(f[1],f[0]),sub(f[2],f[0])))>1e-10)
    f.each_with_index do |a,i|
      b=f[(i+1)%f.length]; ab=sub(b,a); len=dot(ab,ab)
      points=verts.select do |p|
        ap=sub(p,a); t=dot(ap,ab)/len
        t>=-1e-8 && t<=1+1e-8 && dot(cross(ap,ab),cross(ap,ab))<1e-8
      end.sort_by { |p| dot(sub(p,a),ab) }
      points.each_cons(2) { |p,q| edges[[p,q]]+=1 }
    end
  end
  edges.each { |(p,q),count| assert(count==1 && edges[[q,p]]==1) }
  assert(volume(faces)>0)
end
['Cánh phẳng','Cánh khung','Cánh kính','Cánh soi huỳnh'].each do |style|
  doors=D.layout(1200,1600,s.merge('style'=>style,'panels'=>3,'rows'=>2))
  assert(doors.length==4)
  doors.each { |door| door[:parts].each { |part| check_mesh(part[:faces]) } }
  if style=='Cánh kính'
    assert(doors[0][:parts].count { |p| p[:glass] }==3)
  end
end
# Routed solid removes material and retains required bottom thickness.
solid=D.layout(1000,800,s.merge('style'=>'Cánh soi huỳnh'))[0]
v=volume(solid[:parts][0][:faces]);assert(v>0 && v<497*796*17.5)
rejects { D.validate(s.merge('cols'=>1.5)) }
rejects { D.validate(s.merge('cols'=>20,'rows'=>20)) }
rejects { D.validate(s.merge('width'=>'NaN')) }
rejects { D.validate(s.merge('left'=>-2)) }
rejects { D.validate(s.merge('style'=>'Cánh kính','glass_thick'=>18)) }
rejects { D.validate(s.merge('style'=>'Cánh soi huỳnh','depth'=>17)) }
rejects { D.layout(100,100,s.merge('style'=>'Cánh khung')) }
rejects { D.layout(1000,800,s.merge('style'=>'Cánh soi huỳnh','bevel'=>400)) }
rejects { D.layout(100,100,s.merge('gap_x'=>1000)) }
near(D.validate(s.merge('thickness'=>'17,5'))['thickness'],17.5)
puts "PASS #{$count} assertions: layouts, gaps, overlays, glass, manifold surfaces, winding, volume, validation. Not a native SketchUp test."
