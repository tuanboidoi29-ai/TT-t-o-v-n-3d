# TT NGAN KEO - depth detection fix 1.3.3
module TranTuan
  module TaoVan
    module Drawer
      class TwoPointTool
        def depth_from_region(a,b)
          xmin,xmax,zmin,zmax=normalized_region(a,b)
          center=Geom::Point3d.new((xmin+xmax)*0.5,0,(zmin+zmax)*0.5).transform(@frame)
          dir=unit(@frame.yaxis)
          start=center + dir.clone.tap{|v| v.length=0.5.mm}
          hits=[]
          64.times do
            hit=Sketchup.active_model.raytest([start,dir])
            break unless hit && hit[0].is_a?(Geom::Point3d)
            hp=hit[0]; dist=center.distance(hp).to_mm
            break if dist <= 0.01
            hits << dist unless hits.any?{|v|(v-dist).abs < 0.05}
            start=hp + dir.clone.tap{|v| v.length=0.5.mm}
          end
          hits.sort!
          # Neu tia cat thanh/hau sau, cap mat cuoi la mat trong + mat ngoai.
          depth = hits.length >= 2 ? hits[-2] : hits[-1].to_f
          depth=0.0 if depth < 0.0
          depth
        rescue
          0.0
        end
        alias_method :measure_before_depth_fix_133, :measure unless method_defined?(:measure_before_depth_fix_133)
        def measure(a,b)
          r=measure_before_depth_fix_133(a,b)
          r[:d]=depth_from_region(a,b)
          r[:dd]=r[:d]-@cfg['depth_reserve'].to_f-@cfg['gap_front'].to_f
          r
        end
      end
    end
  end
end
