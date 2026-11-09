# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - NCStudio G-code exporter
# Conservative first release: exports closed, horizontal top-face contours from selected Groups/Components.
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module GCodeExport
    extend self

    MM = 1.0 / 25.4
    DEFAULTS = {
      'tool_diameter' => 6.0,
      'spindle' => 18000,
      'feed' => 2500,
      'plunge' => 600,
      'depth' => 9.0,
      'stepdown' => 3.0,
      'safe_z' => 5.0
    }.freeze

    def mm(value)
      value.to_f * 25.4
    end

    def collect_faces(entities, transform, output)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Face)
          normal = entity.normal.transform(transform)
          next unless normal.z > 0.999
          loops = [entity.outer_loop] + entity.loops.reject(&:outer?)
          loop_points = loops.map do |loop|
            loop.vertices.map { |vertex| vertex.position.transform(transform) }
          end
          outer_points = loop_points.first
          next if outer_points.length < 3
          z_values = outer_points.map(&:z)
          next unless (z_values.max - z_values.min).abs < 0.001
          output << [z_values.sum / z_values.length, loop_points]
        elsif entity.is_a?(Sketchup::Group)
          collect_faces(entity.entities, transform * entity.transformation, output)
        elsif entity.is_a?(Sketchup::ComponentInstance)
          collect_faces(entity.definition.entities, transform * entity.transformation, output)
        end
      end
    end

    def selected_contours(model)
      roots = model.selection.to_a.select { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
      raise 'Hãy chọn ít nhất một Group hoặc Component chứa tấm ván.' if roots.empty?

      contours = []
      roots.each do |root|
        faces = []
        entities = root.is_a?(Sketchup::Group) ? root.entities : root.definition.entities
        collect_faces(entities, root.transformation, faces)
        raise "Không tìm thấy mặt phẳng ngang hợp lệ trong: #{root.name}." if faces.empty?
        top_z = faces.map(&:first).max
        top_faces = faces.select { |face| (face[0] - top_z).abs < 0.001 }
        top_faces.each do |_z, loops|
          loops.each do |points|
            contours << points if points.length >= 3
          end
        end
      end
      contours
    end

    def default_config
      keys = %w[tool_diameter spindle feed plunge depth stepdown safe_z]
      keys.each_with_object({}) do |key, hash|
        hash[key] = TranTuanNoiThat.setting("gcode_#{key}", DEFAULTS[key]).to_f
      end
    end

    def validate_config(raw)
      cfg = {}
      DEFAULTS.each do |key, fallback|
        value = Float(raw[key] || fallback) rescue nil
        raise "Thông số #{key} không hợp lệ." unless value && value > 0
        cfg[key] = value
      end
      raise 'Bước xuống dao phải nhỏ hơn hoặc bằng chiều sâu cắt.' if cfg['stepdown'] > cfg['depth']
      raise 'Đường kính dao phải lớn hơn 0.' if cfg['tool_diameter'] <= 0
      cfg.each { |key, value| TranTuanNoiThat.save_setting("gcode_#{key}", value) }
      cfg
    end

    def simulation_moves(contours, cfg)
      points = contours.flatten
      min_x = points.map(&:x).min
      min_y = points.map(&:y).min
      passes = []
      z = cfg['stepdown']
      while z < cfg['depth'] - 0.0001
        passes << z
        z += cfg['stepdown']
      end
      passes << cfg['depth']
      moves = []
      contours.each do |contour|
        xy = contour.map { |point| [mm(point.x - min_x), mm(point.y - min_y)] }
        next if xy.length < 3
        passes.each do |cut_depth|
          moves << { type: 'rapid', z: cfg['safe_z'], x: xy[0][0], y: xy[0][1] }
          moves << { type: 'plunge', z: -cut_depth, x: xy[0][0], y: xy[0][1] }
          xy[1..-1].each { |x, y| moves << { type: 'cut', z: -cut_depth, x: x, y: y } }
          moves << { type: 'cut', z: -cut_depth, x: xy[0][0], y: xy[0][1] }
          moves << { type: 'rapid', z: cfg['safe_z'], x: xy[0][0], y: xy[0][1] }
        end
      end
      cut_length = 0.0
      rapid_length = 0.0
      plunge_distance = 0.0
      previous = nil
      moves.each do |move|
        if previous
          dx = move[:x].to_f - previous[:x].to_f
          dy = move[:y].to_f - previous[:y].to_f
          distance = Math.sqrt(dx * dx + dy * dy)
          cut_length += distance if move[:type] == 'cut'
          rapid_length += distance if move[:type] == 'rapid'
        end
        plunge_distance += move[:z].to_f.abs if move[:type] == 'plunge'
        previous = move
      end
      {
        moves: moves,
        length: mm(points.map(&:x).max - min_x),
        width: mm(points.map(&:y).max - min_y),
        passes: passes,
        metrics: {
          contour_count: contours.length,
          vertex_count: contours.inject(0) { |sum, contour| sum + contour.length },
          cut_length: cut_length,
          rapid_length: rapid_length,
          plunge_distance: plunge_distance,
          rapid_count: moves.count { |move| move[:type] == 'rapid' },
          linear_count: moves.count { |move| move[:type] == 'cut' || move[:type] == 'plunge' }
        }
      }
    end

    def html
      <<~HTML
        <!doctype html><html lang="vi"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{box-sizing:border-box}body{margin:0;background:#f3f6f4;color:#1d2922;font:13px Arial,sans-serif}
        header{background:#176b3a;color:#fff;padding:13px 17px;display:flex;justify-content:space-between;align-items:center}
        header b{font-size:17px}header span{font-size:11px;opacity:.85}
        .wrap{padding:12px;display:grid;grid-template-columns:285px 1fr;gap:12px}
        .panel{background:#fff;border:1px solid #dce6df;border-radius:9px;padding:12px;min-width:0}
        h3{font-size:13px;margin:0 0 10px;color:#176b3a}
        .fields{display:grid;grid-template-columns:1fr 1fr;gap:8px}
        label{display:block;font-size:11px;color:#526258}input{width:100%;padding:7px;margin-top:4px;border:1px solid #cbd8cf;border-radius:5px;font-size:13px}
        .field-full{grid-column:1/-1}.hint{font-size:10px;color:#718077;margin-top:8px;line-height:1.45}
        canvas{width:100%;height:330px;background:#f9fbfa;border:1px solid #dce6df;border-radius:6px;display:block}
        .stats{display:flex;gap:7px;flex-wrap:wrap;margin:9px 0}.stat{background:#eef5f0;border-radius:5px;padding:7px 9px;flex:1;min-width:90px}
        .stat small{display:block;color:#627168;font-size:10px}.stat b{font-size:13px}
        .controls{display:flex;gap:6px;flex-wrap:wrap;margin-top:9px}button{border:0;border-radius:5px;padding:8px 11px;background:#176b3a;color:#fff;font-weight:600;cursor:pointer}
        button.secondary{background:#e5eee8;color:#245437}button.export{background:#174f9b}button:disabled{opacity:.45;cursor:not-allowed}
        input[type=range]{padding:0}#status{font-size:11px;color:#516257;margin-top:8px;min-height:15px}
        .warning{background:#fff5df;border:1px solid #efd69c;border-radius:6px;padding:9px;margin-top:10px;color:#76521a;font-size:11px;line-height:1.45}
        #ncpreview{width:100%;height:230px;margin-top:8px;padding:10px;border:1px solid #cbd8cf;border-radius:6px;background:#101a14;color:#d7f4df;font:11px/1.5 Consolas,monospace;white-space:pre;overflow:auto;resize:vertical}
        .legend{display:flex;gap:12px;font-size:10px;color:#607066;margin-top:7px}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px}
        @media(max-width:720px){.wrap{grid-template-columns:1fr}canvas{height:270px}}
        </style></head><body>
        <header><div><b>TRẦN TUẤN · CNC NCStudio</b><br><span>THIẾT LẬP · MÔ PHỎNG · XUẤT CHƯƠNG TRÌNH</span></div><span>v1.9.317</span></header>
        <div class="wrap">
          <section class="panel">
            <h3>THÔNG SỐ GIA CÔNG</h3>
            <div class="fields">
              <label>Dao Ø (mm)<input id="tool_diameter" type="number" min="0.1" step="0.1"></label>
              <label>Trục chính (RPM)<input id="spindle" type="number" min="1"></label>
              <label>Chạy XY (mm/phút)<input id="feed" type="number" min="1"></label>
              <label>Xuống Z (mm/phút)<input id="plunge" type="number" min="1"></label>
              <label>Chiều sâu (mm)<input id="depth" type="number" min="0.1" step="0.1"></label>
              <label>Bước xuống (mm)<input id="stepdown" type="number" min="0.1" step="0.1"></label>
              <label class="field-full">Z an toàn (mm)<input id="safe_z" type="number" min="0.1" step="0.1"></label>
            </div>
            <div class="hint">G54: góc dưới-trái · X: chiều dài · Y: chiều rộng · Z âm · G21 / G90. Thay đổi thông số rồi nhấn “Cập nhật mô phỏng”.</div>
            <div class="warning"><b>CẢNH BÁO AN TOÀN</b><br>Bản thử nghiệm hiện chạy đường tâm biên dạng, chưa bù bán kính dao. Chưa xác minh va chạm, đồ gá, chiều sâu phôi và mã M riêng của máy. Không đưa thẳng ra máy thật.</div>
          </section>
          <section class="panel">
            <h3>MÔ PHỎNG ĐƯỜNG CHẠY DAO 2D</h3>
            <canvas id="view" width="1000" height="560"></canvas>
            <div class="legend"><span><i class="dot" style="background:#16834a"></i>Đường cắt</span><span><i class="dot" style="background:#9aa9a0"></i>Chạy nhanh</span><span><i class="dot" style="background:#e04b36"></i>Vị trí dao</span></div>
            <div class="stats">
              <div class="stat"><small>KÍCH THƯỚC VÙNG</small><b id="size">-</b></div>
              <div class="stat"><small>SỐ LỚP CẮT</small><b id="passes">-</b></div>
              <div class="stat"><small>LỆNH CHUYỂN ĐỘNG</small><b id="count">-</b></div>
              <div class="stat"><small>ĐỘ SÂU HIỆN TẠI</small><b id="znow">-</b></div>
            </div>
            <div class="stats">
              <div class="stat"><small>ĐƯỜNG CẮT XY</small><b id="cutlength">-</b></div>
              <div class="stat"><small>CHẠY NHANH XY</small><b id="raplength">-</b></div>
              <div class="stat"><small>HÀNH TRÌNH XUỐNG Z</small><b id="plungelength">-</b></div>
              <div class="stat"><small>ĐIỂM BIÊN 2D</small><b id="vertices">-</b></div>
            </div>
            <input id="progress" type="range" min="0" max="1" value="0">
            <div class="controls">
              <button id="play">▶ Chạy mô phỏng</button><button id="pause" class="secondary">Ⅱ Tạm dừng</button>
              <button id="reset" class="secondary">↺ Chạy lại</button><button id="rebuild" class="secondary">Cập nhật mô phỏng</button>
              <button id="export" class="export">Xuất tệp .NC</button>
            </div><div id="status">Đang nạp dữ liệu hình học…</div>
            <h3 style="margin-top:15px">CHI TIẾT G-CODE SẼ XUẤT</h3>
            <div class="hint">Nội dung bên dưới được tạo từ cùng dữ liệu đường chạy dao đang mô phỏng. Có thể rà soát từng lệnh G00/G01, tọa độ X/Y/Z và tốc độ F trước khi lưu .NC.</div>
            <textarea id="ncpreview" readonly spellcheck="false"></textarea>
          </section>
        </div>
        <script>
        const DATA=__DATA__;
        const ids=['tool_diameter','spindle','feed','plunge','depth','stepdown','safe_z'];
        const $=id=>document.getElementById(id);let moves=DATA.moves||[],index=0,timer=null,scaleInfo=null;
        const canvas=$('view'),ctx=canvas.getContext('2d');
        function cfg(){const o={};ids.forEach(k=>o[k]=Number($(k).value));return o}
        function send(action,payload){if(window.sketchup&&window.sketchup[action])window.sketchup[action](JSON.stringify(payload||{}))}
        function stop(){if(timer){clearInterval(timer);timer=null}}
        function mapPoint(x,y){return [scaleInfo.ox+x*scaleInfo.s,scaleInfo.oy+scaleInfo.h-y*scaleInfo.s]}
        function draw(){
          const w=canvas.width,h=canvas.height;ctx.clearRect(0,0,w,h);ctx.fillStyle='#f9fbfa';ctx.fillRect(0,0,w,h);
          const pad=55, sx=(w-pad*2)/Math.max(DATA.length,1),sy=(h-pad*2)/Math.max(DATA.width,1);
          const s=Math.min(sx,sy);scaleInfo={s,ox:(w-DATA.length*s)/2,h:(h+DATA.width*s)/2};
          ctx.strokeStyle='#aab8af';ctx.lineWidth=2;ctx.strokeRect(scaleInfo.ox,scaleInfo.h-DATA.width*s,DATA.length*s,DATA.width*s);
          ctx.fillStyle='#63736a';ctx.font='15px Arial';ctx.fillText('G54  X0 Y0',scaleInfo.ox,scaleInfo.h+24);
          let last=null;
          for(let i=0;i<=Math.min(index,moves.length-1);i++){
            const m=moves[i];if(!m)continue;const p=mapPoint(m.x,m.y);
            if(last&&m.type!=='rapid'){ctx.strokeStyle='#16834a';ctx.lineWidth=2.3;ctx.beginPath();ctx.moveTo(last[0],last[1]);ctx.lineTo(p[0],p[1]);ctx.stroke();}
            else if(last&&m.type==='rapid'){ctx.strokeStyle='#aab6ae';ctx.setLineDash([5,5]);ctx.beginPath();ctx.moveTo(last[0],last[1]);ctx.lineTo(p[0],p[1]);ctx.stroke();ctx.setLineDash([]);}
            last=p;
          }
          if(moves.length){const m=moves[Math.min(index,moves.length-1)],p=mapPoint(m.x,m.y);ctx.fillStyle='#e04b36';ctx.beginPath();ctx.arc(p[0],p[1],8,0,Math.PI*2);ctx.fill();$('znow').textContent=m.z.toFixed(2)+' mm';}
          else $('znow').textContent='-';
          $('progress').max=Math.max(moves.length-1,1);$('progress').value=index;
          $('status').textContent='Tiến trình: '+(moves.length?Math.round(index/Math.max(moves.length-1,1)*100):0)+'% · Bước '+(index+1)+'/'+moves.length;
        }
        function renderDetails(sim){
          const m=sim.metrics||{};
          $('cutlength').textContent=Number(m.cut_length||0).toFixed(1)+' mm';
          $('raplength').textContent=Number(m.rapid_length||0).toFixed(1)+' mm';
          $('plungelength').textContent=Number(m.plunge_distance||0).toFixed(1)+' mm';
          $('vertices').textContent=Number(m.vertex_count||0);
          $('ncpreview').value=sim.gcode_text||'Chưa có dữ liệu G-code.';
        }
        window.loadSimulation=function(sim){DATA.moves=sim.moves;DATA.length=sim.length;DATA.width=sim.width;DATA.passes=sim.passes;moves=sim.moves;index=0;$('size').textContent=sim.length.toFixed(1)+' × '+sim.width.toFixed(1)+' mm';$('passes').textContent=sim.passes.length;$('count').textContent=moves.length;renderDetails(sim);draw();$('status').textContent='Đã cập nhật đường chạy dao và nội dung G-code. Chạy mô phỏng lại để kiểm tra.';};
        function play(){if(!moves.length)return;stop();if(index>=moves.length-1)index=0;timer=setInterval(()=>{index=Math.min(index+1,moves.length-1);draw();if(index>=moves.length-1)stop()},35)}
        function rebuild(){stop();send('update_config',cfg())}
        $('play').onclick=play;$('pause').onclick=stop;$('reset').onclick=()=>{stop();index=0;draw()};
        $('progress').oninput=e=>{stop();index=Number(e.target.value);draw()};
        $('rebuild').onclick=rebuild;$('export').onclick=()=>{stop();if(index<moves.length-1){$('status').textContent='Hãy chạy hết mô phỏng trước khi xuất tệp.';return}send('export_nc',cfg())};
        ids.forEach(k=>$(k).addEventListener('change',()=>{$('status').textContent='Có thông số mới. Nhấn Cập nhật mô phỏng.'}));
        ids.forEach(k=>$(k).value=DATA.config[k]);
        $('size').textContent=DATA.length.toFixed(1)+' × '+DATA.width.toFixed(1)+' mm';
        $('passes').textContent=DATA.passes.length;$('count').textContent=moves.length;
        renderDetails(DATA);draw();$('status').textContent='Đã nạp '+DATA.contours+' đường bao. Chạy mô phỏng để kiểm tra trình tự.';
        </script></body></html>
      HTML
    end

    def show_dialog
      model = Sketchup.active_model
      @contours = selected_contours(model)
      @dialog.close if @dialog && @dialog.visible?
      cfg = default_config
      sim = simulation_moves(@contours, cfg)
      preview_gcode = gcode(@contours, cfg)[0]
      payload = sim.merge(config: cfg, contours: @contours.length, gcode_text: preview_gcode)
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - CNC NCStudio',
        preferences_key: 'TranTuanNoiThat_GCode_NCStudio',
        scrollable: true, resizable: true, width: 1050, height: 720,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html.sub('__DATA__', JSON.generate(payload)))
      @dialog.add_action_callback('update_config') do |_context, json|
        begin
          new_cfg = validate_config(JSON.parse(json))
          sim_data = simulation_moves(@contours, new_cfg)
          sim_data[:gcode_text] = gcode(@contours, new_cfg)[0]
          @dialog.execute_script("window.loadSimulation(#{JSON.generate(sim_data)})") if @dialog
        rescue StandardError => error
          UI.messagebox("Thông số chưa hợp lệ: #{error.message}")
        end
      end
      @dialog.add_action_callback('export_nc') do |_context, json|
        begin
          new_cfg = validate_config(JSON.parse(json))
          gcode_text, length, width, pass_count = gcode(@contours, new_cfg)
          path = UI.savepanel('Lưu chương trình NCStudio', '', 'TT_NCStudio.NC')
          if path
            path += '.NC' unless path.downcase.end_with?('.nc')
            File.open(path, 'wb') { |file| file.write(gcode_text.encode('UTF-8')) }
            UI.messagebox("Đã tạo tệp NC:\n#{path}\nKích thước: #{format('%.1f', length)} × #{format('%.1f', width)} mm\nSố lớp: #{pass_count}\n\nBắt buộc mô phỏng bằng phần mềm CNC và chạy thử không tải.")
          end
        rescue StandardError => error
          UI.messagebox("Không thể xuất G-code: #{error.class}: #{error.message}")
        end
      end
      @dialog.show
    rescue StandardError => error
      UI.messagebox("Không thể mở giao diện CNC: #{error.class}: #{error.message}")
    end

    def gcode(contours, cfg)
      points = contours.flatten
      min_x = points.map(&:x).min
      min_y = points.map(&:y).min
      max_x = points.map(&:x).max
      max_y = points.map(&:y).max
      raise 'Kích thước phôi không hợp lệ.' if max_x <= min_x || max_y <= min_y

      lines = []
      lines << '(TRẦN TUẤN - NCStudio)'
      lines << '(G54: bottom-left | X: length | Y: width | Z: negative)'
      lines << '(UNITS: mm | ABSOLUTE | TOOLPATH: 2D CONTOUR CENTERLINE - NO TOOL RADIUS COMPENSATION)'
      lines << 'G21'
      lines << 'G17'
      lines << 'G90'
      lines << 'G54'
      lines << 'G94'
      lines << "M03 S#{cfg['spindle'].round}"
      lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
      lines << "G00 X0.000 Y0.000"
      depth = cfg['stepdown']
      passes = []
      while depth < cfg['depth'] - 0.0001
        passes << depth
        depth += cfg['stepdown']
      end
      passes << cfg['depth']
      contours.each_with_index do |contour, contour_index|
        xy = contour.map { |p| [mm(p.x - min_x), mm(p.y - min_y)] }
        next if xy.length < 3
        perimeter = xy.each_with_index.inject(0.0) do |sum, (point, index)|
          following = xy[(index + 1) % xy.length]
          dx = following[0] - point[0]
          dy = following[1] - point[1]
          sum + Math.sqrt(dx * dx + dy * dy)
        end
        lines << "(CONTOUR #{contour_index + 1} | POINTS #{xy.length} | PERIMETER #{format('%.3f', perimeter)} MM)"
        passes.each do |cut_depth|
          lines << "(PASS Z-#{format('%.3f', cut_depth)})"
          lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
          lines << "G00 X#{format('%.3f', xy[0][0])} Y#{format('%.3f', xy[0][1])}"
          lines << "G01 Z-#{format('%.3f', cut_depth)} F#{cfg['plunge'].round}"
          xy[1..-1].each do |x, y|
            lines << "G01 X#{format('%.3f', x)} Y#{format('%.3f', y)} F#{cfg['feed'].round}"
          end
          lines << "G01 X#{format('%.3f', xy[0][0])} Y#{format('%.3f', xy[0][1])} F#{cfg['feed'].round}"
          lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
        end
      end
      lines << 'M05'
      lines << "G00 Z#{format('%.3f', cfg['safe_z'])}"
      lines << 'M30'
      [lines.join("\n") + "\n", mm(max_x - min_x), mm(max_y - min_y), passes.length]
    end

    def run
      show_dialog
    rescue StandardError => error
      UI.messagebox("Xuất G-code thất bại:\n#{error.class}: #{error.message}")
    end
  end
end
