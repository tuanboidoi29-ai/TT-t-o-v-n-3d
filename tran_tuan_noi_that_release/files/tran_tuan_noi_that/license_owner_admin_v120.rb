# encoding: UTF-8
require 'json'
require 'net/http'
require 'uri'

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.2.0'.freeze

    ADMIN_ENDPOINT = 'https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-license-admin'.freeze unless const_defined?(:ADMIN_ENDPOINT, false)

    unless method_defined?(:tt_dialog_html_payment_v110)
      alias_method :tt_dialog_html_payment_v110, :dialog_html
    end
    unless method_defined?(:tt_show_dialog_payment_v110)
      alias_method :tt_show_dialog_payment_v110, :show_dialog
    end

    def owner_admin?(payload = cache)
      payload.is_a?(Hash) && payload['owner'] == true && payload['machine_status'].to_s == 'active'
    rescue StandardError
      false
    end

    def dialog_html
      html = tt_dialog_html_payment_v110
      launcher = <<~HTML
        <div id="ownerAdminLauncher" class="box" style="display:none;border-color:#10b981">
          <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">
            <div><b style="color:#34d399">QUYỀN QUẢN LÝ OWNER</b><div class="note" style="margin-top:5px">Quản lý khách hàng, giá bán, thanh toán và quyền từng chức năng.</div></div>
            <button class="green" onclick="sketchup.owner_admin_open()">MỞ QUẢN LÝ</button>
          </div>
        </div>
      HTML
      html = html.sub('<div class="note">Chức năng chưa mua', launcher + '<div class="note">Chức năng chưa mua')

      hook = <<~JS
        const ttRenderLicenseV120 = window.renderLicense;
        window.renderLicense = d => {
          ttRenderLicenseV120(d);
          const launch = document.getElementById('ownerAdminLauncher');
          if (launch) launch.style.display = d && d.owner ? 'block' : 'none';
        };
      JS
      html.sub("document.addEventListener('DOMContentLoaded',()=>sketchup.ready());", hook + "\ndocument.addEventListener('DOMContentLoaded',()=>sketchup.ready());")
    end

    def show_dialog(feature = nil)
      tt_show_dialog_payment_v110(feature)
      bind_owner_admin_callback
    end

    def bind_owner_admin_callback
      return false unless @dialog
      dialog_id = @dialog.object_id
      return true if @owner_admin_bound_dialog_id == dialog_id
      @owner_admin_bound_dialog_id = dialog_id
      @dialog.add_action_callback('owner_admin_open') do |_ctx|
        payload = sync_now(nil) || cache
        if owner_admin?(payload)
          show_owner_admin
        else
          UI.messagebox('Chỉ máy OWNER đang ACTIVE mới có quyền quản lý.')
        end
      end
      true
    rescue StandardError => error
      puts "[TT Owner Admin bind] #{error.class}: #{error.message}"
      false
    end

    def admin_post_raw(payload)
      uri = URI.parse(ADMIN_ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req['Cache-Control'] = 'no-cache, no-store'
      req['X-TT-Request'] = "#{Time.now.to_i}-#{rand(1_000_000)}"
      body = payload.is_a?(Hash) ? payload.dup : {}
      body['machine_code'] = machine_code
      body['plugin_version'] = TranTuanNoiThat.current_version.to_s
      req.body = JSON.generate(body)
      response = http.request(req)
      text = response.body.to_s
      parsed = text.empty? ? {} : JSON.parse(text)
      unless response.is_a?(Net::HTTPSuccess)
        parsed['ok'] = false unless parsed.key?('ok')
        parsed['http_status'] = response.code.to_i
      end
      parsed
    rescue StandardError => error
      { 'ok' => false, 'error' => 'network_error', 'message' => "#{error.class}: #{error.message}" }
    end

    def run_admin_async(payload = { 'action' => 'dashboard' })
      return false if @admin_syncing
      @admin_syncing = true
      @admin_pending = :waiting
      request = payload.is_a?(Hash) ? payload.dup : { 'action' => 'dashboard' }

      Thread.new do
        begin
          @admin_pending = admin_post_raw(request)
        rescue StandardError => error
          @admin_pending = { 'ok' => false, 'error' => 'network_error', 'message' => "#{error.class}: #{error.message}" }
        end
      end

      @admin_poll_timer = UI.start_timer(0.20, true) do
        next if @admin_pending == :waiting
        UI.stop_timer(@admin_poll_timer) if @admin_poll_timer
        result = @admin_pending
        @admin_pending = nil
        @admin_syncing = false
        render_owner_admin(result)
        sync_now(nil) if result.is_a?(Hash) && result['ok'] == true && request['action'].to_s != 'dashboard'
      end
      true
    rescue StandardError => error
      @admin_syncing = false
      puts "[TT Owner Admin async] #{error.class}: #{error.message}"
      false
    end

    def show_owner_admin
      unless owner_admin?
        UI.messagebox('Máy này chưa có quyền OWNER.')
        return false
      end
      if @admin_dialog && @admin_dialog.visible?
        @admin_dialog.bring_to_front
        run_admin_async('action' => 'dashboard')
        return true
      end

      @admin_dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - QUẢN LÝ BẢN QUYỀN',
        preferences_key: 'TranTuanNoiThat.OwnerAdminV120',
        scrollable: true,
        resizable: true,
        width: 980,
        height: 820,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @admin_dialog.set_html(owner_admin_html)
      @admin_dialog.add_action_callback('admin_ready') { |_ctx| run_admin_async('action' => 'dashboard') }
      @admin_dialog.add_action_callback('admin_refresh') { |_ctx| run_admin_async('action' => 'dashboard') }
      @admin_dialog.add_action_callback('admin_action') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          run_admin_async(data)
        rescue StandardError => error
          render_owner_admin('ok' => false, 'error' => 'invalid_action', 'message' => error.message)
        end
      end
      @admin_dialog.show
      true
    rescue StandardError => error
      puts "[TT Owner Admin show] #{error.class}: #{error.message}"
      UI.messagebox("Không mở được Quản Lý OWNER:\n#{error.message}")
      false
    end

    def render_owner_admin(payload)
      return unless @admin_dialog && @admin_dialog.visible?
      data = payload.is_a?(Hash) ? payload : { 'ok' => false, 'error' => 'invalid_response' }
      @admin_dialog.execute_script("window.renderAdmin(#{JSON.generate(data)})")
    rescue StandardError => error
      puts "[TT Owner Admin UI] #{error.class}: #{error.message}"
    end

    def owner_admin_html
      <<~HTML
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:13px Arial}.head{padding:16px 20px;background:linear-gradient(135deg,#059669,#047857);position:sticky;top:0;z-index:4}.head h1{margin:0;font-size:20px}.sub{font-size:12px;margin-top:4px;opacity:.9}.body{padding:15px}.box{background:#1e293b;border:1px solid #334155;border-radius:11px;padding:13px;margin-bottom:12px}.title{font-weight:800;font-size:14px;margin-bottom:10px;color:#f8fafc}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}.card{background:#111827;border:1px solid #334155;border-radius:9px;padding:10px}.ok{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}.warn{color:#fbbf24;font-weight:700}.muted{color:#94a3b8}.code{font:700 13px Consolas,monospace;color:#fb923c}.paycode{font:700 13px Consolas,monospace;color:#fbbf24}button{border:0;border-radius:7px;padding:7px 10px;font-weight:700;cursor:pointer}.green{background:#059669;color:white}.orange{background:#ea580c;color:white}.red{background:#dc2626;color:white}.dark{background:#334155;color:white}.blue{background:#2563eb;color:white}input,select{background:#0f172a;color:#e5e7eb;border:1px solid #475569;border-radius:6px;padding:7px}.price{width:115px;text-align:right}.machine{margin-top:8px;border-top:1px solid #334155;padding-top:10px}.chips{display:flex;gap:5px;flex-wrap:wrap;margin-top:7px}.chip{font-size:11px;padding:5px 7px;border-radius:6px;background:#334155;color:#cbd5e1}.chip.on{background:#065f46;color:#d1fae5}.chip.free{background:#1d4ed8;color:#dbeafe}.error{display:none;background:#450a0a;border:1px solid #ef4444;color:#fecaca;border-radius:8px;padding:9px;margin-bottom:10px}.payment{display:grid;grid-template-columns:1.1fr .8fr .8fr .8fr auto;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid #334155}.payment:last-child{border:0}.small{font-size:11px}.toolbar{display:flex;justify-content:space-between;gap:8px;align-items:center;flex-wrap:wrap}.busy{display:none;color:#fbbf24;font-weight:700}</style></head><body>
        <div class="head"><h1>TRẦN TUẤN · QUẢN LÝ OWNER</h1><div class="sub">Quản lý thương mại trực tiếp từ SketchUp</div></div>
        <div class="body">
          <div class="toolbar"><div><span id="serverState" class="muted">Đang tải...</span> <span id="busy" class="busy">ĐANG XỬ LÝ...</span></div><button class="dark" onclick="refreshAdmin()">LÀM MỚI</button></div>
          <div id="adminError" class="error"></div>
          <div class="box"><div class="title">CHẾ ĐỘ THƯƠNG MẠI</div><div class="row"><b>Trạng thái:</b><span id="enforcementState">-</span><button id="enforcementBtn" class="orange" onclick="toggleEnforcement()">-</button><span class="muted">Vẽ Ván + BOX đang là FREE 0đ.</span></div></div>
          <div class="box"><div class="title">GIÁ CHỨC NĂNG</div><div id="products" class="grid"></div></div>
          <div class="box"><div class="title">THANH TOÁN CHỜ XÁC NHẬN</div><div id="payments"></div></div>
          <div class="box"><div class="title">MÁY KHÁCH & QUYỀN</div><div id="machines"></div></div>
        </div>
        <script>
        const el=id=>document.getElementById(id);let ADMIN=null;
        const money=v=>v==null?'Chưa định giá':Number(v).toLocaleString('vi-VN')+' đ';
        const esc=s=>String(s==null?'':s).replace(/[&<>\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[c]));
        function act(o){el('busy').style.display='inline';sketchup.admin_action(JSON.stringify(o));}
        function refreshAdmin(){el('busy').style.display='inline';sketchup.admin_refresh();}
        function toggleEnforcement(){const cur=!!(ADMIN&&ADMIN.config&&ADMIN.config.commercial_enforcement===true);if(cur&&!confirm('Tắt chế độ thương mại?'))return;if(!cur&&!confirm('Bật chế độ thương mại? Các chức năng trả phí chưa mua sẽ bị khóa.'))return;act({action:'set_enforcement',value:!cur});}
        function savePrice(slug){const v=el('price_'+slug).value.trim();act({action:'set_price',product_slug:slug,amount_vnd:v===''?null:Number(v)});}
        function machineStatus(code,status){if(status==='blocked'&&!confirm('Khóa máy '+code+' ?'))return;act({action:'set_machine_status',target_machine_code:code,status:status});}
        function entitlement(code,slug,on){act({action:on?'grant':'revoke',target_machine_code:code,product_slug:slug});}
        function payment(code,paid){if(paid&&!confirm('Xác nhận đã nhận tiền cho '+code+' ?'))return;act({action:paid?'mark_paid':'cancel_payment',request_code:code});}
        function activeMap(){const m={};(ADMIN.entitlements||[]).forEach(e=>{if(e.status==='active'){m[e.machine_id+'|'+e.product_id]=true;}});return m;}
        window.renderAdmin=d=>{
          el('busy').style.display='none';
          const er=el('adminError');if(!d||d.ok!==true){er.style.display='block';er.textContent='Lỗi quản lý: '+String((d&&d.error)||'unknown')+(d&&d.message?' · '+d.message:'');return;}er.style.display='none';ADMIN=d;
          el('serverState').textContent='OWNER '+String(d.owner_machine||'')+' · '+new Date().toLocaleTimeString('vi-VN');
          const en=!!(d.config&&d.config.commercial_enforcement===true);el('enforcementState').textContent=en?'ĐANG BẬT':'CHƯA BẬT';el('enforcementState').className=en?'ok':'warn';el('enforcementBtn').textContent=en?'TẮT THƯƠNG MẠI':'BẬT THƯƠNG MẠI';el('enforcementBtn').className=en?'red':'green';
          const products=d.products||[];const prodBy={};products.forEach(p=>prodBy[p.id]=p);const pp=el('products');pp.innerHTML='';products.forEach(p=>{const c=document.createElement('div');c.className='card';const free=Number(p.price_vnd)===0;c.innerHTML='<div><b>'+esc(p.name)+'</b> <span class="muted">('+esc(p.slug)+')</span></div><div class="row" style="margin-top:8px"><input id="price_'+esc(p.slug)+'" class="price" type="number" min="0" step="1000" value="'+(p.price_vnd==null?'':Number(p.price_vnd))+'"><span>đ</span><button class="blue" onclick="savePrice(\''+esc(p.slug)+'\')">LƯU GIÁ</button>'+(free?'<span class="chip free">FREE</span>':'')+'</div>';pp.appendChild(c);});
          const machineBy={};(d.machines||[]).forEach(m=>machineBy[m.id]=m);const pay=el('payments');pay.innerHTML='';const pending=(d.payments||[]).filter(x=>x.status==='pending');if(!pending.length){pay.innerHTML='<div class="muted">Không có thanh toán đang chờ.</div>';}pending.forEach(x=>{const m=machineBy[x.machine_id]||{};const p=prodBy[x.product_id]||{};const r=document.createElement('div');r.className='payment';r.innerHTML='<div><span class="paycode">'+esc(x.request_code)+'</span><div class="small muted">'+esc(m.machine_code||'')+'</div></div><div>'+esc(p.name||'')+'</div><div class="warn">'+money(x.amount_vnd)+'</div><div class="small muted">'+esc(x.created_at||'')+'</div><div class="row"><button class="green" onclick="payment(\''+esc(x.request_code)+'\',true)">ĐÃ NHẬN TIỀN</button><button class="dark" onclick="payment(\''+esc(x.request_code)+'\',false)">HỦY</button></div>';pay.appendChild(r);});
          const amap=activeMap();const ms=el('machines');ms.innerHTML='';(d.machines||[]).forEach(m=>{const box=document.createElement('div');box.className='machine';const owner=String(m.owner_note||'').toUpperCase().startsWith('OWNER');let chips='';products.forEach(p=>{const on=!!amap[m.id+'|'+p.id];const free=Number(p.price_vnd)===0;chips+='<button class="chip '+(on?'on ':'')+(free?'free':'')+'" '+(owner?'disabled':'onclick="entitlement(\''+esc(m.machine_code)+'\',\''+esc(p.slug)+'\','+(!on)+')"')+'>'+esc(p.name)+' · '+(on?'MỞ':'KHÓA')+'</button>';});box.innerHTML='<div class="row"><span class="code">'+esc(m.machine_code)+'</span>'+(owner?'<span class="chip on">OWNER</span>':'')+'<span class="'+(m.status==='active'?'ok':m.status==='blocked'?'bad':'warn')+'">'+esc(m.status)+'</span><span class="muted">v'+esc(m.last_plugin_version||'-')+'</span></div><div class="row" style="margin-top:7px">'+(owner?'':'<button class="green" onclick="machineStatus(\''+esc(m.machine_code)+'\',\'active\')">ACTIVE</button><button class="dark" onclick="machineStatus(\''+esc(m.machine_code)+'\',\'pending\')">PENDING</button><button class="red" onclick="machineStatus(\''+esc(m.machine_code)+'\',\'blocked\')">KHÓA MÁY</button>')+'<span class="small muted">Lần cuối: '+esc(m.last_seen_at||m.created_at||'-')+'</span></div><div class="chips">'+chips+'</div>';ms.appendChild(box);});
        };
        document.addEventListener('DOMContentLoaded',()=>sketchup.admin_ready());
        </script></body></html>
      HTML
    end
  end
end
