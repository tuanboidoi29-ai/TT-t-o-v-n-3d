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
      return 'Tường' if s =~ /wall|tuong|masonry/
      return 'Cột (kiểm tra)' if s =~ /column|cot|pillar/
      'Chưa phân loại'
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
    def footprint(c)
      d=sub(c[:b],c[:a]);l=Math.hypot(*d);n=[-d[1]/l*c[:width]/2,d[0]/l*c[:width]/2]
      a,b=c[:a],c[:b]
      [[a[0]-n[0],a[1]-n[1]],[b[0]-n[0],b[1]-n[1]],[b[0]+n[0],b[1]+n[1]],[a[0]+n[0],a[1]+n[1]]]
    end
  end
end
