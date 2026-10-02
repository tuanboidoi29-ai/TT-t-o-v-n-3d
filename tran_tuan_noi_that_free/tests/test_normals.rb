require_relative 'test_slat'
Vertex=Struct.new(:position)
class TestFace < Sketchup::Face
 attr_reader :vertices,:normal
 def initialize(points)
  @vertices=points.map{|p|Vertex.new(Geom::Point3d.new(*p))}
  a,b,c=@vertices.map(&:position);@normal=(b-a).cross(c-a).normalize
 end
 def reverse!;@normal.reverse!;end
end
Group=Struct.new(:entities,:name)
cases=[[[0,0],[100,0],[0,100]],[[0,0],[100,0],[140,40],[40,40]],[[0,0],[100,0],[100,100],[0,100]]]
%w[diag_left diag_right].each do |direction|
 plan=S.layout_polygon([[0,0],[1000,0],[1000,700],[0,700]],'orientation'=>direction)
 cases.concat(plan[:panels][0][:slat_polygons])
end
cases.each do |poly|
 points=poly.map{|x,y|[x,y,0]}+poly.map{|x,y|[x,y,17.5]}
 topology=S.polygon_prism_topology(poly.length)[0]
 faces=topology.map{|ids|TestFace.new(ids.map{|i|points[i]})}
 faces.each_with_index{|f,i|f.reverse! if i.even?}
 S.orient_outward_faces(Group.new(faces,'test'))
 center=S.shell_center(faces)
 check(faces.all?{|f|S.face_outward_score(f,center)>0})

end
puts "#{$n} total checks passed, including #{cases.length} prism orientation cases"
