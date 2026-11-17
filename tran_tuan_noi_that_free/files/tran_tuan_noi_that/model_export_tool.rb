# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XUẤT DỮ LIỆU / KIỂM TRA MODEL
require 'sketchup.rb'
require 'json'
require 'net/http'
require 'uri'
require 'securerandom'
require 'time'
require 'fileutils'

module TranTuanNoiThat
  module ModelExport
    extend self

    API_URL = 'https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-model-api'.freeze
    WEB_URL = 'https://tt-kiem-tra-tam-web.vercel.app/'.freeze
    DICT = 'TT_ModelExport'.freeze
    MAX_TRIANGLES_TOTAL = 12000
    MAX_TRIANGLES_PER_OBJECT = 2500

    def model
      Sketchup.active_model
    end

    def model_uid
      m = model
      value = m.get_attribute(DICT, 'model_uid').to_s
      if value.empty?
        value = SecureRandom.uuid
        m.set_attribute(DICT, 'model_uid', value)
      end
      value
    end

    def entity_uid(entity)
      value = entity.get_attribute(DICT, 'uid').to_s
      if value.empty?
        value = SecureRandom.uuid
        entity.set_attribute(DICT, 'uid', value)
      end
      value
    end

    def visible_entity?(entity)
      return false if entity.respond_to?(:hidden?) && entity.hidden?
      return false if entity.respond_to?(:layer) && entity.layer && entity.layer.respond_to?(:visible?) && !entity.layer.visible?
      true
    rescue StandardError
      true
    end

    def top_level_objects
      m = model
      return [] unless m
      m.entities.to_a.select do |entity|
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
          entity.valid? && visible_entity?(entity)
      end
    end

    def rgb_hex(material, fallback = '#B8C7D9')
      return fallback unless material && material.respond_to?(:color) && material.color
      c = material.color
      format('#%02X%02X%02X', c.red.to_i, c.green.to_i, c.blue.to_i)
    rescue StandardError
      fallback
    end

    def material_name(entity)
      material = entity.material
      if !material && entity.respond_to?(:definition)
        entity.definition.entities.each do |child|
          next unless child.is_a?(Sketchup::Face)
          material = child.material || child.back_material
          break if material
        end
      end
      material ? material.display_name.to_s : ''
    rescue StandardError
      ''
    end

    def entity_name(entity)
      value = entity.name.to_s.strip
      value = entity.definition.name.to_s.strip if value.empty? && entity.respond_to?(:definition)
      value.empty? ? (entity.is_a?(Sketchup::Group) ? 'Group' : 'Component') : value
    rescue StandardError
      'Đối tượng SketchUp'
    end

    def bounds_corners(entity)
      b = entity.bounds
      8.times.map do |i|
        p = b.corner(i)
        [(p.x.to_f * 25.4).round(2), (p.y.to_f * 25.4).round(2), (p.z.to_f * 25.4).round(2)]
      end
    end

    def bounds_dimensions(entity)
      b = entity.bounds
      [(b.width.to_f * 25.4).round(1), (b.depth.to_f * 25.4).round(1), (b.height.to_f * 25.4).round(1)]
    end

    def mesh_triangles(instance, parent_transform, output, limit, inherited_material = nil)
      return output if output.length >= limit
      transform = parent_transform * instance.transformation
      inherited = instance.material || inherited_material
      instance.definition.entities.each do |child|
        break if output.length >= limit
        if child.is_a?(Sketchup::Face)
          begin
            mesh = child.mesh(0)
            points = mesh.points
            face_material = child.material || child.back_material || inherited
            color = rgb_hex(face_material)
            mesh.polygons.each do |polygon|
              break if output.length >= limit
              indices = polygon.map { |index| index.abs - 1 }.select { |index| index >= 0 && index < points.length }
              next if indices.length < 3
              base = transform * points[indices[0]]
              (1...(indices.length - 1)).each do |i|
                break if output.length >= limit
                p2 = transform * points[indices[i]]
                p3 = transform * points[indices[i + 1]]
                output << {
                  'v' => [
                    [(base.x.to_f * 25.4).round(2), (base.y.to_f * 25.4).round(2), (base.z.to_f * 25.4).round(2)],
                    [(p2.x.to_f * 25.4).round(2), (p2.y.to_f * 25.4).round(2), (p2.z.to_f * 25.4).round(2)],
                    [(p3.x.to_f * 25.4).round(2), (p3.y.to_f * 25.4).round(2), (p3.z.to_f * 25.4).round(2)]
                  ],
                  'c' => color
                }
              end
            end
          rescue StandardError
            next
          end
        elsif child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          mesh_triangles(child, transform, output, limit, inherited)
        end
      end
      output
    rescue StandardError
      output
    end

    def scan_model
      m = model
      raise 'Không có model SketchUp đang mở.' unless m
      objects = top_level_objects
      raise 'Không tìm thấy Group/Component đang hiển thị trong model.' if objects.empty?

      changed = false
      m.start_operation('Quét dữ liệu model', true)
      begin
        model_uid
        objects.each { |entity| entity_uid(entity) }
        m.commit_operation
        changed = true
      rescue StandardError
        m.abort_operation rescue nil
        raise
      end

      remaining = MAX_TRIANGLES_TOTAL
      records = objects.each_with_index.map do |entity, index|
        cap = [remaining, MAX_TRIANGLES_PER_OBJECT].min
        triangles = cap > 0 ? mesh_triangles(entity, Geom::Transformation.new, [], cap) : []
        remaining -= triangles.length
        {
          'uid' => entity_uid(entity),
          'persistent_id' => (entity.persistent_id rescue nil),
          'name' => entity_name(entity),
          'type' => entity.is_a?(Sketchup::Group) ? 'Group' : 'Component',
          'tag' => (entity.layer.name.to_s rescue ''),
          'material' => material_name(entity),
          'dimensions' => bounds_dimensions(entity),
          'corners' => bounds_corners(entity),
          'triangles' => triangles,
          'triangle_count' => triangles.length,
          'geometry_limited' => (triangles.length >= cap && remaining <= 0)
        }
      end

      {
        'model_uid' => model_uid,
        'model_name' => model_title,
        'scanned_at' => Time.now.utc.iso8601,
        'object_count' => records.length,
        'triangle_count' => records.inject(0) { |sum, item| sum + item['triangle_count'].to_i },
        'objects' => records.map { |r| r.reject { |k, _| k == 'triangles' } },
        'model3d' => records
      }
    end

    def model_title
      m = model
      path = m && m.path.to_s
      return File.basename(path, File.extname(path)) unless path.empty?
      m && m.title.to_s.empty? ? 'SketchUp Model' : m.title.to_s
    rescue StandardError
      'SketchUp Model'
    end

    def share_settings
      m = model
      {
        'share_id' => m.get_attribute(DICT, 'share_id').to_s,
        'write_key' => m.get_attribute(DICT, 'write_key').to_s,
        'project_login' => m.get_attribute(DICT, 'project_login').to_s
      }
    end

    def persist_share_settings(share_id, write_key, login)
      m = model
      m.start_operation('Lưu cấu hình đồng bộ Model', true)
      begin
        m.set_attribute(DICT, 'share_id', share_id)
        m.set_attribute(DICT, 'write_key', write_key)
        m.set_attribute(DICT, 'project_login', login)
        m.commit_operation
      rescue StandardError
        m.abort_operation rescue nil
        raise
      end
    end

    def sync_to_web(login, password)
      m = model
      raise 'Không có model SketchUp đang mở.' unless m
      login = login.to_s.strip
      password = password.to_s
      raise 'Tên dự án phải có ít nhất 3 ký tự.' if login.length < 3

      settings = share_settings
      share_id = settings['share_id']
      write_key = settings['write_key']
      share_id = SecureRandom.hex(12) if share_id.empty?
      write_key = SecureRandom.hex(32) if write_key.empty?
      persist_share_settings(share_id, write_key, login)

      scanned = scan_model
      payload = {
        'model_uid' => scanned['model_uid'],
        'model_name' => scanned['model_name'],
        'objects' => scanned['objects'],
        'model3d' => scanned['model3d'],
        'panels' => [],
        'labels' => []
      }
      body = {
        'action' => 'sync',
        'share_id' => share_id,
        'write_key' => write_key,
        'project_login' => login,
        'password' => password,
        'model_uid' => scanned['model_uid'],
        'model_name' => scanned['model_name'],
        'payload' => payload
      }
      response = post_json(API_URL, body)
      raise api_error(response) unless response['ok'] && response['saved']

      {
        'share_id' => share_id,
        'model_name' => scanned['model_name'],
        'object_count' => scanned['object_count'],
        'triangle_count' => scanned['triangle_count'],
        'revision' => (response.dig('model', 'revision') rescue nil),
        'url' => WEB_URL + '?id=' + URI.encode_www_form_component(share_id)
      }
    end

    def post_json(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 20
      http.read_timeout = 90
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = JSON.generate(body)
      response = http.request(request)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise 'Máy chủ trả về dữ liệu không hợp lệ.'
    rescue StandardError => e
      raise "Không kết nối được máy chủ đồng bộ: #{e.class}: #{e.message}"
    end

    def api_error(response)
      code = response['error'].to_s
      detail = response['detail'].to_s
      messages = {
        'invalid_write_key' => 'Khóa ghi dữ liệu không hợp lệ.',
        'forbidden' => 'Khóa đồng bộ không khớp với model đã lưu.',
        'project_login_exists' => 'Tên dự án này đã được sử dụng. Hãy đổi tên đăng nhập dự án.',
        'password_required' => 'Lần đồng bộ đầu tiên cần đặt mật khẩu để bảo vệ link web.',
        'password_too_short' => 'Mật khẩu phải có ít nhất 4 ký tự.',
        'project_login_too_short' => 'Tên dự án phải có ít nhất 3 ký tự.',
        'invalid_share_id' => 'Mã chia sẻ model không hợp lệ.'
      }
      messages[code] || (detail.empty? ? "Máy chủ từ chối đồng bộ (#{code})." : detail)
    end

    def export_json
      data = scan_model
      path = UI.savepanel('Xuất dữ liệu kiểm tra Model', '', 'model_kiem_tra.json')
      return false unless path
      File.write(path, JSON.pretty_generate(data), mode: 'w:UTF-8')
      UI.messagebox("Đã xuất #{data['object_count']} đối tượng ra tệp JSON.")
      true
    rescue StandardError => e
      UI.messagebox("Không xuất được dữ liệu Model:\n#{e.class}: #{e.message}")
      false
    end

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return true
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'XUẤT DỮ LIỆU - KIỂM TRA MODEL',
        preferences_key: 'TranTuanNoiThat.ModelExport',
        scrollable: true, resizable: true,
        width: 1040, height: 760, min_width: 760, min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      @dialog.add_action_callback('model_scan') do |_context|
        begin
          result = scan_model
          @dialog.execute_script("window.TTModelExport.receiveScan(#{JSON.generate(result).gsub('</', '<\\/')})")
        rescue StandardError => e
          @dialog.execute_script("window.TTModelExport.showError(#{e.message.to_s.to_json})")
        end
      end
      @dialog.add_action_callback('model_sync') do |_context, login, password|
        begin
          result = sync_to_web(login, password)
          @dialog.execute_script("window.TTModelExport.synced(true, #{JSON.generate(result).gsub('</', '<\\/')})")
        rescue StandardError => e
          @dialog.execute_script("window.TTModelExport.synced(false, #{e.message.to_s.to_json})")
        end
      end
      @dialog.add_action_callback('model_export_json') { |_context| export_json }
      @dialog.add_action_callback('model_open_web') do |_context|
        settings = share_settings
        if settings['share_id'].empty?
          UI.messagebox('Hãy đồng bộ Model lên Web trước.')
        else
          UI.openURL(WEB_URL + '?id=' + URI.encode_www_form_component(settings['share_id']))
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
      true
    rescue StandardError => e
      UI.messagebox("Không mở được chức năng xuất dữ liệu Model:\n#{e.class}: #{e.message}")
      false
    end

    def close
      @dialog.close if @dialog
      @dialog = nil
    rescue StandardError
      nil
    end

    def html
      <<~HTML
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <style>
      *{box-sizing:border-box}body{margin:0;background:#f3f6fa;color:#202a36;font:14px Segoe UI,Arial}header{padding:18px 22px;background:#fff;border-bottom:1px solid #dce3eb;display:flex;justify-content:space-between;align-items:center;gap:12px}h1{font-size:20px;margin:0}.muted{color:#718096;font-size:12px}.wrap{padding:16px;max-width:1300px;margin:auto}.panel{background:#fff;border:1px solid #dfe5ed;border-radius:11px;padding:14px;margin-bottom:12px}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.field{display:block;font-size:12px;color:#59677a;margin-bottom:5px}input{width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:7px;font:inherit}.btn{border:0;border-radius:7px;padding:10px 14px;background:#24384f;color:#fff;cursor:pointer;font-weight:700}.green{background:#137b50}.blue{background:#245fc4}.light{background:#e9eef5;color:#25364b}.btn:disabled{opacity:.55;cursor:wait}.stats{display:flex;gap:8px;flex-wrap:wrap}.stat{background:#f2f5f9;border-radius:8px;padding:8px 12px}.stat b{display:block;font-size:19px}.tablewrap{overflow:auto;max-height:340px}table{width:100%;border-collapse:collapse;font-size:12px}th,td{padding:9px;border-bottom:1px solid #e7ecf2;text-align:left;white-space:nowrap}th{background:#f7f9fc;position:sticky;top:0}.link{overflow-wrap:anywhere;color:#1458ad}.notice{padding:10px;border-radius:8px;background:#eef5ff;color:#31517b;font-size:12px;line-height:1.5}.status{margin-top:9px;font-size:12px;white-space:pre-wrap}.ok{color:#087344}.bad{color:#b42318}@media(max-width:720px){.grid{grid-template-columns:1fr}header{align-items:flex-start;flex-direction:column}}
      </style></head><body>
      <header><div><h1>XUẤT DỮ LIỆU - KIỂM TRA MODEL</h1><div class="muted">Quét Group / Component · Đồng bộ Model lên Web · Tạo QR riêng từng đối tượng</div></div><div class="row"><button class="btn light" onclick="sketchup.model_export_json()">Xuất JSON</button><button class="btn blue" onclick="sketchup.model_open_web()">Mở Web</button></div></header>
      <main class="wrap">
        <section class="panel">
          <div class="row" style="justify-content:space-between"><div><b>1. QUÉT MODEL</b><div class="muted">Quét các Group / Component đang hiển thị ở cấp model. Mỗi đối tượng có mã định danh riêng.</div></div><button id="scanBtn" class="btn green" onclick="scan()">QUÉT MODEL</button></div>
          <div id="stats" class="stats" style="margin-top:12px"><div class="stat"><b id="count">0</b><span class="muted">Đối tượng</span></div><div class="stat"><b id="triangles">0</b><span class="muted">Mặt tam giác 3D</span></div></div>
          <div class="tablewrap" style="margin-top:12px"><table><thead><tr><th>TÊN ĐỐI TƯỢNG</th><th>LOẠI</th><th>KÍCH THƯỚC (mm)</th><th>TAG</th><th>VẬT LIỆU</th><th>MÃ ĐỊNH DANH</th></tr></thead><tbody id="objects"><tr><td colspan="6" class="muted">Bấm QUÉT MODEL để đọc dữ liệu.</td></tr></tbody></table></div>
        </section>
        <section class="panel">
          <b>2. ĐỒNG BỘ VÀ XUẤT LINK XEM MODEL TRÊN WEB</b>
          <p class="muted">Lần đầu đồng bộ, đặt tên dự án và mật khẩu. Các lần sau dùng lại tên dự án; mật khẩu chỉ cần nhập khi tạo dự án mới hoặc muốn đổi mật khẩu. Link web và QR yêu cầu đăng nhập để bảo vệ model.</p>
          <div class="grid">
            <div><label class="field">TÊN ĐĂNG NHẬP DỰ ÁN</label><input id="login" autocomplete="username" placeholder="VD: tuan-noi-that-01"></div>
            <div><label class="field">MẬT KHẨU WEB (tối thiểu 4 ký tự)</label><input id="password" type="password" autocomplete="new-password" placeholder="Chỉ nhập khi tạo dự án / đổi mật khẩu"></div>
          </div>
          <div class="row" style="margin-top:12px"><button id="syncBtn" class="btn green" onclick="sync()">ĐỒNG BỘ MODEL & TẠO LINK</button><span class="muted">Model sẽ được cập nhật theo lần đồng bộ mới nhất.</span></div>
          <div id="result" class="status"></div>
          <div id="linkBox" class="notice" style="display:none;margin-top:10px"><b>LINK XEM MODEL</b><div id="webLink" class="link"></div><div class="row" style="margin-top:8px"><button class="btn light" onclick="copyLink()">Sao chép link</button><button class="btn blue" onclick="openLink()">Mở trang xem</button></div></div>
        </section>
        <section class="notice">Lưu ý: Sau khi đồng bộ, hãy lưu file SKP để giữ mã dự án và mã định danh đối tượng. Trình xem Web hiển thị hình học 3D đã quét, danh sách đối tượng và QR riêng từng đối tượng. Cần Internet khi đồng bộ và khi mở Web.</section>
      </main>
      <script>
      var lastLink='';
      function scan(){document.getElementById('scanBtn').disabled=true;document.getElementById('objects').innerHTML='<tr><td colspan="6">Đang quét model...</td></tr>';sketchup.model_scan()}
      function receiveScan(d){document.getElementById('scanBtn').disabled=false;document.getElementById('count').textContent=d.object_count||0;document.getElementById('triangles').textContent=d.triangle_count||0;var rows=d.objects||[];document.getElementById('objects').innerHTML=rows.map(function(o){return '<tr><td>'+esc(o.name)+'</td><td>'+esc(o.type)+'</td><td>'+esc((o.dimensions||[]).join(' × '))+'</td><td>'+esc(o.tag)+'</td><td>'+esc(o.material)+'</td><td>'+esc(o.uid)+'</td></tr>'}).join('')||'<tr><td colspan="6">Không có đối tượng.</td></tr>';document.getElementById('result').textContent='Đã quét '+(d.object_count||0)+' đối tượng.';document.getElementById('result').className='status ok'}
      function showError(s){document.getElementById('scanBtn').disabled=false;document.getElementById('result').textContent=s;document.getElementById('result').className='status bad'}
      function sync(){var login=document.getElementById('login').value.trim(),password=document.getElementById('password').value;if(!login)return showError('Nhập tên đăng nhập dự án.');document.getElementById('syncBtn').disabled=true;document.getElementById('result').textContent='Đang quét hình học và đồng bộ lên Web...';document.getElementById('result').className='status';sketchup.model_sync(login,password)}
      function synced(ok,d){document.getElementById('syncBtn').disabled=false;if(!ok){showError(d);return}lastLink=d.url;document.getElementById('password').value='';document.getElementById('linkBox').style.display='block';document.getElementById('webLink').textContent=d.url;document.getElementById('result').textContent='Đã đồng bộ '+d.object_count+' đối tượng · '+d.triangle_count+' tam giác · Revision '+d.revision;document.getElementById('result').className='status ok'}
      function copyLink(){if(!lastLink)return;var t=document.createElement('textarea');t.value=lastLink;document.body.appendChild(t);t.select();document.execCommand('copy');t.remove();document.getElementById('result').textContent='Đã sao chép link.'}
      function openLink(){if(lastLink)sketchup.model_open_web()}
      function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
      window.TTModelExport={receiveScan:receiveScan,showError:showError,synced:synced};
      </script></body></html>
      HTML
    end
  end
end
