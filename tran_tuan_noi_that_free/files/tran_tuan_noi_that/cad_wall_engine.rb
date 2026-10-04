# encoding: UTF-8
# Pure geometry in millimetres; no changes to the source CAD.
module TranTuanNoiThat
  module CadWallEngine
    extend self
    def label_kind(name)
      s=name.to_s.downcase.tr('đ','d').unicode_normalize(:nfd).gsub(/\p{Mn}/,'')
      return 'Bỏ qua: DIM/trục/chữ' if s =~ /dim|kich.?thuoc|text|anno|grid|axis|truc|center/
      return 'Bỏ qua: hatch/vật liệu' if s =~ /hatch|pattern|vat.?lieu/
      return 'Cửa sổ (kiểm tra)' if s =~ /window|cua.?so/
      return 'Cửa đi (kiểm tra)' if s =~ /door|cua/
      return 'Nội thất (bỏ qua)' if s =~ /furn|noi.?that|sofa|bed|giuong|sanitary|fixture/
      return 'Hướng dẫn tường (kiểm tra)' if s =~ /wall.*guide|trace|vector|raster/
      return 'Tường' if s =~ /wall|tuong|masonry/
      return 'Cột (kiểm tra)' if s =~ /column|cot|pillar/
      'Chưa phân loại'
    end
    ROLES = ['Tường','Cửa đi','Cửa sổ','Cột','Nội thất','Bỏ qua','Chưa rõ'].freeze
    def role_for(name)
      kind=label_kind(name)
      return 'Tường' if kind=='Tường'
      return 'Cửa đi' if kind.start_with?('Cửa đi')
      return 'Cửa sổ' if kind.start_with?('Cửa sổ')
      return 'Cột' if kind.start_with?('Cột')
      return 'Nội thất' if kind.start_with?('Nội thất')
      return 'Bỏ qua' if kind.start_with?('Bỏ qua')
      'Chưa rõ'
    end
    # Evidence only: furniture can also contain these parallel pairs.
    def width_evidence(edges)
      rows=edges.map{|e|canonical(e)}.compact.select{|e|e[:hi]-e[:lo]>=500}
      return [] if rows.length>1500
      counts=Hash.new(0)
      rows.each_with_index do |a,i|
        rows[(i+1)..-1].each do |b|
          next unless a[:layer]==b[:layer] && dot(a[:u],b[:u])>0.99999999
          width=(a[:c]-b[:c]).abs
          next unless width.between?(60,500) && [a[:hi],b[:hi]].min-[a[:lo],b[:lo]].max>=500
          counts[width.round]+=1
        end
        yield if block_given? && i%30==0
      end
      counts.sort_by{|width,count|[-count,width]}.first(8).map{|width,count|{width:width,count:count}}
    end
    def manual_wall(a,b,width,id)
      raise 'Điểm và độ dày không hợp lệ.' unless [a,b].all?{|p|p.is_a?(Array)&&p.length==2&&p.all?{|v|v.is_a?(Numeric)&&v.finite?&&v.abs<1e8}} && width.finite? && width.between?(30,2000)
      length=distance(a,b)
      raise 'Đoạn tường phải dài ít nhất 50 mm.' if length<50
      {a:a,b:b,width:width,id:id,length:length,layer:'Chỉ định trên bản vẽ',selected:true,warning:'Tim tường do người dùng xác nhận'}
    end
    def dot(a,b);a[0]*b[0]+a[1]*b[1];end
    def sub(a,b);[a[0]-b[0],a[1]-b[1]];end
    def distance(a,b);Math.hypot(a[0]-b[0],a[1]-b[1]);end
    def canonical(edge)
      a,b=edge[:a],edge[:b];d=sub(b,a);l=Math.hypot(*d);return nil if l<0.1
      u=d.map{|v|v/l};u=u.map{|v|-v} if u[0]<-1e-8 || (u[0].abs<1e-8 && u[1]<0)
      n=[-u[1],u[0]];lo,hi=[dot(a,u),dot(b,u)].minmax
      {u:u,n:n,c:dot(a,n),lo:lo,hi:hi,layer:edge[:layer]}
    end
    # Merge ONLY contiguous collinear fragments. Never bridge a door opening.
    def consolidate(edges,tol)
      groups={}
      edges.each do |e|
        q=canonical(e);next unless q
        angle=Math.atan2(q[:u][1],q[:u][0]);key=[q[:layer],(angle*100000).round,(q[:c]/tol).round]
        (groups[key]||=[]) << q
      end
      groups.values.flat_map do |rows|
        merged=[]
        rows.sort_by{|q|q[:lo]}.each do |q|
          if !merged.empty? && q[:lo]<=merged.last[:hi]+tol
            merged.last[:hi]=[merged.last[:hi],q[:hi]].max
          else
            merged << q.dup
          end
        end
        merged
      end
    end
    def xy(u,n,s,c);[u[0]*s+n[0]*c,u[1]*s+n[1]*c];end
    def recognize(edges,opts)
      tol=opts[:tolerance];widths=opts[:widths];rows=consolidate(edges,tol)
      raise 'Quá 3000 nét sau lọc. Chọn riêng lớp tường hoặc một mặt bằng.' if rows.length>3000
      candidates=[];seen={}
      rows.each_with_index do |a,i|
        ((i+1)...rows.length).each do |j|
          b=rows[j];next unless a[:layer]==b[:layer]
          next unless dot(a[:u],b[:u])>0.99999999
          w=(a[:c]-b[:c]).abs
          next unless widths.any?{|v|(w-v).abs<=tol}
          # Thickness must remain consistent at both ends, not diverging lines.
          blo,bhi=[xy(b[:u],b[:n],b[:lo],b[:c]),xy(b[:u],b[:n],b[:hi],b[:c])]
          next if [blo,bhi].any?{|p|((dot(p,a[:n])-a[:c]).abs-w).abs>tol}
          lo=[a[:lo],dot(blo,a[:u])].max;hi=[a[:hi],dot(bhi,a[:u])].min
          next if hi-lo<opts[:min_length]
          c=(a[:c]+b[:c])/2.0
          p=xy(a[:u],a[:n],lo,c);q=xy(a[:u],a[:n],hi,c)
          key=[p,q].flatten.map{|x|(x/tol).round} + [(w/tol).round]
          next if seen[key];seen[key]=true
          candidates << {a:p,b:q,width:w,layer:a[:layer],selected:true,u:a[:u],n:a[:n],c:c,lo:lo,hi:hi,limit_lo:[a[:lo],dot(blo,a[:u])].min,limit_hi:[a[:hi],dot(bhi,a[:u])].max}
        end
        yield(i.to_f/[rows.length,1].max) if block_given? && i%20==0
      end
      raise 'Quá 800 đoạn tường nghi vấn. Lọc lại lớp CAD để tránh nhầm hatch.' if candidates.length>800
      # Ambiguous multiple parallel pairs need explicit review, not automatic build.
      candidates.each_with_index do |a,i|
        candidates[(i+1)..-1].each do |b|
          u=sub(a[:b],a[:a]);l=Math.hypot(*u);u=u.map{|v|v/l};n=[-u[1],u[0]]
          v=sub(b[:b],b[:a]);vl=Math.hypot(*v);next unless dot(u,v).abs/vl>0.999999
          delta=dot(sub(b[:a],a[:a]),n).abs
          r=[dot(sub(b[:a],a[:a]),u),dot(sub(b[:b],a[:a]),u)].minmax
          if delta<(a[:width]+b[:width])/2.0-tol && [l,r[1]].min-[0,r[0]].max>tol
            a[:selected]=b[:selected]=false;a[:warning]=b[:warning]='Nhiều cặp nét chồng nhau — chọn lại'
          end
        end
      end
      # Close perpendicular corners only within the extents of original CAD lines.
      # Parallel gaps (doors) are never bridged.
      candidates.each do |a|
        next unless a[:selected]
        candidates.each do |b|
          next if a.equal?(b) || !b[:selected] || dot(a[:u],b[:u]).abs>1e-7
          den=a[:n][0]*b[:n][1]-a[:n][1]*b[:n][0]
          next if den.abs<1e-8
          p=[(a[:c]*b[:n][1]-a[:n][1]*b[:c])/den,(a[:n][0]*b[:c]-a[:c]*b[:n][0])/den]
          t=dot(p,a[:u]);v=dot(p,b[:u])
          next unless [ (v-b[:lo]).abs, (v-b[:hi]).abs ].min <= a[:width]+tol
          if (t-a[:lo]).abs<=b[:width]+tol
            a[:lo]=[a[:lo],[a[:limit_lo],t-b[:width]/2].max].min
          elsif (t-a[:hi]).abs<=b[:width]+tol
            a[:hi]=[a[:hi],[a[:limit_hi],t+b[:width]/2].min].max
          end
        end
        a[:a]=xy(a[:u],a[:n],a[:lo],a[:c]);a[:b]=xy(a[:u],a[:n],a[:hi],a[:c])
      end
      candidates.each_with_index{|c,i|c[:id]=i;c[:length]=distance(c[:a],c[:b])}
      candidates
    end
    def polygon_area(points)
      points.each_with_index.sum{|p,i|q=points[(i+1)%points.length];p[0]*q[1]-q[0]*p[1]}/2.0
    end
    def cross(a,b,c)
      (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    end
    def simple_polygon?(p)
      p.each_index do |i|
        a,b=p[i],p[(i+1)%p.length]
        ((i+1)...p.length).each do |j|
          next if j==i+1 || (i==0 && j==p.length-1)
          c,d=p[j],p[(j+1)%p.length]
          return false if cross(a,b,c)*cross(a,b,d)<0 && cross(c,d,a)*cross(c,d,b)<0
        end
      end
      true
    end
    def inside_outline?(p,poly)
      inside=false
      poly.each_with_index do |a,i|
        b=poly[(i+1)%poly.length]
        return true if cross(a,b,p).abs<1e-6 && p[0].between?(*[a[0],b[0]].minmax) && p[1].between?(*[a[1],b[1]].minmax)
        if (a[1]>p[1]) != (b[1]>p[1])
          x=a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1])
          inside=!inside if p[0]<x
        end
      end
      inside
    end
    # Orthogonal L/T profiles, also when rotated relative to model axes.
    def corner_profile(poly,tolerance)
      q=poly.dup
      loop do
        index=q.each_index.find{|i|a=q[(i-1)%q.length];b=q[i];c=q[(i+1)%q.length];cross(a,b,c).abs<1e-7 && dot(sub(b,a),sub(c,b))>0}
        break unless index && q.length>4
        q.delete_at(index)
      end
      return nil unless [6,8].include?(q.length)
      vectors=q.each_index.map{|i|sub(q[(i+1)%q.length],q[i])}
      lengths=vectors.map{|v|Math.hypot(*v)}
      return nil if lengths.min<1
      return nil unless vectors.each_index.all?{|i|dot(vectors[i],vectors[(i+1)%q.length]).abs/(lengths[i]*lengths[(i+1)%q.length])<1e-6}
      reflex=q.each_index.select{|i|cross(q[(i-1)%q.length],q[i],q[(i+1)%q.length])<0}
      shape=nil
      shape='L' if q.length==6 && reflex.length==1
      if q.length==8 && reflex.length==2
        gap=(reflex[0]-reflex[1]).abs
        shape='T' if [gap,8-gap].min==3
      end
      return nil unless shape
      # Ends of each arm have two convex vertices; their edge length is thickness.
      ends=q.each_index.select{|i|!reflex.include?(i)&&!reflex.include?((i+1)%q.length)}.map{|i|lengths[i]}.select{|l|l.between?(60,500)}
      return nil unless ends.length>=(shape=='L' ? 2 : 3)
      width=ends.min
      return nil unless lengths.max>=500 && lengths.max/width>=3
      {shape:shape,width:width}
    end
    # Exact closed components only; no inferred closure across openings.
    def closed_outlines(edges,roles,opts)
      adjacency=Hash.new{|h,k|h[k]=[]};points={};unique={}
      edges.each_with_index do |e,id|
        next unless ['Tường','Chưa rõ'].include?(roles[e[:layer]])
        a,b=[e[:a],e[:b]].map{|p|[e[:layer],(p[0]*100).round,(p[1]*100).round]}
        next if a==b
        key=[a,b].sort;next if unique[key];unique[key]=true
        points[a]=e[:a];points[b]=e[:b]
        adjacency[a]<<[b,id];adjacency[b]<<[a,id]
      end
      adjacency.each{|k,list|list.sort_by!{|q,id|Math.atan2(points[q][1]-points[k][1],points[q][0]-points[k][0])}}
      visited={};result=[];used=[]
      directed=adjacency.flat_map{|k,list|list.map{|q,id|[k,q]}}
      directed.each_with_index do |(first,second),iteration|
        yield if block_given? && iteration%100==0
        next if visited[[first,second]]
        keys=[];ids=[];from,to=first,second;closed=false
        loop do
          break if visited[[from,to]]
          visited[[from,to]]=true;keys<<from
          list=adjacency[to];at=list.index{|q,id|q==from}
          ids<<list[at][1]
          nxt=list[(at-1)%list.length][0]
          from,to=to,nxt
          if from==first && to==second;closed=true;break;end
          break if keys.length>512
        end
        next unless closed && keys.length.between?(4,128) && keys.uniq.length==keys.length
        poly=keys.map{|k|points[k]}
        next unless polygon_area(poly)>0.01
        next unless simple_polygon?(poly)
        area=polygon_area(poly);next if area.abs<1
        # Minimum oriented bounding rectangle, measured from source geometry.
        boxes=poly.each_index.map do |i|
          d=sub(poly[(i+1)%poly.length],poly[i]);length=Math.hypot(*d);next if length<0.01
          u=d.map{|v|v/length};n=[-u[1],u[0]];x=poly.map{|p|dot(p,u)}.minmax;y=poly.map{|p|dot(p,n)}.minmax
          [ (x[1]-x[0])*(y[1]-y[0]),u,n,x,y ]
        end.compact
        box=boxes.min_by(&:first);box_area,u,n,x,y=box
        length,width=[x[1]-x[0],y[1]-y[0]].max,[x[1]-x[0],y[1]-y[0]].min
        corner=corner_profile(poly,opts[:tolerance])
        next unless corner || width.between?(60,500) && length>=[opts[:min_length],500].max && length/width>=4 && area.abs/box_area>=0.65
        width=corner[:width] if corner
        poly.reverse! if area<0
        a=xy(u,n,x[0],(y[0]+y[1])/2);b=xy(u,n,x[1],(y[0]+y[1])/2)
        trusted=roles[first[0]]=='Tường'
        result<<{a:a,b:b,width:width,length:length,layer:first[0],outline:poly,shape:corner && corner[:shape],selected:trusted,warning:trusted ? (corner ? "Đường bao #{corner[:shape]} — giữ góc vuông và phần lõm" : 'Đường bao kín — giữ biên CAD') : 'Đường bao nghi là tường — cần xác nhận lớp'}
        used.concat(ids)
        raise 'Quá 800 đường bao. Chọn riêng mặt bằng cần dựng.' if result.length>800
      end
      [result,used]
    end
    def footprint(c)
      return c[:outline] if c[:outline]
      d=sub(c[:b],c[:a]);l=Math.hypot(*d);n=[-d[1]/l*c[:width]/2,d[0]/l*c[:width]/2]
      a,b=c[:a],c[:b]
      [[a[0]-n[0],a[1]-n[1]],[b[0]-n[0],b[1]-n[1]],[b[0]+n[0],b[1]+n[1]],[a[0]+n[0],a[1]+n[1]]]
    end
  end
end
