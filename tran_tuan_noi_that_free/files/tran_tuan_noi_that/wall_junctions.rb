# encoding: UTF-8
module TranTuanNoiThat
  module WallJunctions
    extend self
    # Only merge touching faces / overlapping volumes, never bridge empty space.
    def touching?(a,b)
      amin,amax=a.bounds.min.to_a,a.bounds.max.to_a
      bmin,bmax=b.bounds.min.to_a,b.bounds.max.to_a
      overlap=3.times.map{|i|[amax[i],bmax[i]].min-[amin[i],bmin[i]].max}
      overlap.all?{|v|v>=-1e-7} && overlap.count{|v|v>1e-7}>=2
    end
    def clean_edges(group)
      group.entities.grep(Sketchup::Edge).each do |edge|
        next unless edge.valid? && edge.faces.length==2
        a,b=edge.faces
        next unless a.normal.dot(b.normal)>0.999999999
        next unless a.material==b.material && a.back_material==b.back_material
        next unless b.vertices.all?{|v|v.position.distance_to_plane(a.plane).abs<1e-7}
        edge.erase!
      end
      raise 'Khối không kín sau khi làm sạch; đã hủy thao tác.' unless group.manifold?
      group
    end
    # Caller owns the transaction. All operands must be inside an isolated work group.
    def finish(container)
      groups=container.entities.grep(Sketchup::Group)
      raise 'Không có khối tường.' if groups.empty?
      raise 'Có tường chưa kín (không phải Solid).' unless groups.all?{|g|g.manifold?}
      loop do
        pair=nil
        groups.each_with_index do |a,i|
          b=groups[(i+1)..-1].find{|g|touching?(a,g)}
          if b;pair=[a,b];break;end
        end
        break unless pair
        a,b=pair
        raise 'SketchUp không hỗ trợ hợp nhất Solid trên máy này.' unless a.respond_to?(:union)
        result=a.union(b)
        raise 'Không hợp nhất được giao tường. Đã hủy; kiểm tra khối kín và mặt chạm nhau.' unless result && result.valid? && result.manifold? && container.valid?
        groups=groups.reject{|g|g.equal?(a)||g.equal?(b)}+[result]
      end
      # Flatten successful solids into one result; no nested wall groups remain.
      groups.each{|g|g.explode}
      clean_edges(container)
    end
  end
end
