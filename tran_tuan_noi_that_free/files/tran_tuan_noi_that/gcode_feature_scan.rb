# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - CNC feature scan (read-only classification)
# Detects horizontal profile levels for review; deliberately does not create NC moves.
module TranTuanNoiThat
  module GCodeFeatureScanPatch
    def selected_geometry(model)
      data = super
      profiles = Array(data[:scan_profiles])
      profiles.each do |profile|
        points = Array(profile[:points])
        next if points.length < 3
        area2 = 0.0
        perimeter = 0.0
        points.each_with_index do |point, index|
          following = points[(index + 1) % points.length]
          area2 += point[0].to_f * following[1].to_f - following[0].to_f * point[1].to_f
          dx = following[0].to_f - point[0].to_f
          dy = following[1].to_f - point[1].to_f
          perimeter += Math.sqrt(dx * dx + dy * dy)
        end
        profile[:area_mm2] = (area2.abs * 0.5).round(2)
        profile[:perimeter_mm] = perimeter.round(2)
        profile[:point_count] = points.length
        profile[:feature_type] =
          if profile[:z].to_f.abs < 0.01
            'Biên dạng mặt chuẩn trên'
          elsif profile[:z].to_f < -0.01
            'Ứng viên đáy hốc / bậc'
          else
            'Mặt ngang khác'
          end
        profile[:review_required] = true
      end
      data[:scan_level_count] = profiles.map { |p| p[:z].to_f.round(2) }.uniq.length
      data
    end

    def html
      source = super
      source = source.sub(
        '<canvas id="view3d" width="1200" height="650"></canvas>',
        '<canvas id="view3d" width="1200" height="650"></canvas><div class="panel" style="margin-top:10px"><div class="viewtitle"><h3>NHẬN DIỆN BIÊN DẠNG GIA CÔNG</h3><span class="hint">Quét nhiều cao độ · chỉ phân loại tham khảo</span></div><div id="featureSummary" class="stats"></div><div id="featureList" style="max-height:220px;overflow:auto;font-size:11px"></div><div class="warning">Các mặt thấp hơn mặt chuẩn được đánh dấu là ứng viên đáy hốc/bậc, chưa khẳng định là túi gia công. Chưa đưa các ứng viên này vào G-code tự động.</div></div>'
      )
      script = <<~JS
        function renderFeatureScan(){
          const profiles=DATA.scan_profiles||[];
          const levels=[...new Set(profiles.map(p=>Number(p.z||0).toFixed(2)))].sort((a,b)=>Number(b)-Number(a));
          const area=profiles.reduce((s,p)=>s+Number(p.area_mm2||0),0);
          const summary=$('featureSummary');
          summary.innerHTML='<div class="stat"><small>BIÊN DẠNG QUÉT</small><b>'+profiles.length+'</b></div>'+
            '<div class="stat"><small>CẤP CAO ĐỘ Z</small><b>'+levels.length+'</b></div>'+
            '<div class="stat"><small>MẶT NGANG ĐÃ QUÉT</small><b>'+(DATA.scan_face_count||0)+'</b></div>'+
            '<div class="stat"><small>TỔNG DIỆN TÍCH ĐƯỜNG BAO</small><b>'+area.toFixed(1)+' mm²</b></div>';
          const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
          $('featureList').innerHTML='<table style="width:100%;border-collapse:collapse"><thead><tr style="text-align:left;background:#eef5f0"><th style="padding:6px"># / Chi tiết</th><th>Z (mm)</th><th>Phân loại</th><th>Diện tích</th><th>Chu vi</th><th>Điểm</th></tr></thead><tbody>'+
            profiles.slice(0,200).map((p,i)=>'<tr style="border-bottom:1px solid #e5ece7"><td style="padding:6px">'+(i+1)+' · '+esc(p.name)+'</td><td>'+Number(p.z||0).toFixed(2)+'</td><td>'+esc(p.feature_type||'Biên dạng ngang')+'</td><td>'+Number(p.area_mm2||0).toFixed(1)+'</td><td>'+Number(p.perimeter_mm||0).toFixed(1)+'</td><td>'+Number(p.point_count||p.points.length)+'</td></tr>').join('')+
            '</tbody></table>'+(profiles.length>200?'<div class="hint">Đang hiển thị 200 / '+profiles.length+' biên dạng để giữ giao diện nhẹ.</div>':'');
        }
      JS
      source = source.sub('const DATA=__DATA__;', "const DATA=__DATA__;\n#{script}")
      source = source.sub('renderDetails(DATA);draw();draw3d();', 'renderDetails(DATA);renderFeatureScan();draw();draw3d();')
      source.gsub('v1.9.319', 'v1.9.320')
    end
  end

  unless GCodeExport.singleton_class.ancestors.include?(GCodeFeatureScanPatch)
    GCodeExport.singleton_class.prepend(GCodeFeatureScanPatch)
  end
end
