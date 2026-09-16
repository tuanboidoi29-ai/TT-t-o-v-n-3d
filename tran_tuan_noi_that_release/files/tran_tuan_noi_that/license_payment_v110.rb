# encoding: UTF-8
require 'json'
require 'net/http'
require 'uri'

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.1.0'.freeze

    PAYMENT_ENDPOINT = 'https://vnvkmxqgbnmirsgdgfzm.supabase.co/functions/v1/tt-license-payment'.freeze unless const_defined?(:PAYMENT_ENDPOINT, false)

    PAYMENT_ERRORS = {
      'price_not_configured' => 'Chức năng này chưa được cấu hình giá bán.',
      'machine_not_registered' => 'Mã máy chưa được đăng ký trên máy chủ.',
      'machine_blocked' => 'Mã máy đang bị khóa.',
      'product_not_found' => 'Không tìm thấy chức năng trên máy chủ.',
      'payment_not_found' => 'Không tìm thấy yêu cầu thanh toán.',
      'invalid_machine_code' => 'Mã máy không hợp lệ.',
      'server_error' => 'Máy chủ thanh toán đang lỗi. Vui lòng thử lại.'
    }.freeze

    def payment_post(payload)
      uri = URI.parse(PAYMENT_ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 8

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req['Cache-Control'] = 'no-cache, no-store'
      req['X-TT-Request'] = "#{Time.now.to_i}-#{rand(1_000_000)}"
      req.body = JSON.generate(payload)

      response = http.request(req)
      body = response.body.to_s
      parsed = body.empty? ? {} : JSON.parse(body)
      parsed['http_status'] = response.code.to_i unless response.is_a?(Net::HTTPSuccess)
      parsed
    rescue StandardError => error
      { 'ok' => false, 'error' => 'network_error', 'message' => "#{error.class}: #{error.message}" }
    end

    def create_payment_request(feature)
      slug = feature.to_s.strip.downcase
      return { 'ok' => false, 'error' => 'product_not_found' } unless FEATURE_NAMES.key?(slug.to_sym)

      payment_post(
        'action' => 'create',
        'machine_code' => machine_code,
        'product_slug' => slug,
        'plugin_version' => TranTuanNoiThat.current_version.to_s
      )
    end

    def check_payment_request(request_code)
      payment_post(
        'action' => 'status',
        'machine_code' => machine_code,
        'request_code' => request_code.to_s.strip.upcase,
        'plugin_version' => TranTuanNoiThat.current_version.to_s
      )
    end

    def payment_message(payload)
      return '' if payload.is_a?(Hash) && payload['ok'] == true
      code = payload.is_a?(Hash) ? payload['error'].to_s : ''
      return PAYMENT_ERRORS[code] if PAYMENT_ERRORS.key?(code)
      return 'Không kết nối được máy chủ thanh toán.' if code == 'network_error'
      code.empty? ? 'Không tạo được yêu cầu thanh toán.' : "Lỗi thanh toán: #{code}"
    end

    def render_payment(payload)
      return unless @dialog && @dialog.visible?
      data = payload.is_a?(Hash) ? payload.dup : {}
      data['friendly_error'] = payment_message(data)
      @dialog.execute_script("window.renderPayment(#{JSON.generate(data)})")
    rescue StandardError => error
      puts "[TT License Payment UI] #{error.class}: #{error.message}"
    end

    def show_dialog(feature = nil)
      @requested_feature = feature && feature.to_sym
      if @dialog && @dialog.visible?
        refresh_dialog
        background_sync if cache.empty? || stale?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - BẢN QUYỀN & THANH TOÁN',
        preferences_key: 'TranTuanNoiThat.LicensePaymentV110',
        scrollable: true,
        resizable: true,
        width: 640,
        height: 800,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)

      @dialog.add_action_callback('ready') do |_ctx|
        refresh_dialog
        background_sync if cache.empty? || stale?
      end

      @dialog.add_action_callback('check') do |_ctx|
        payload = sync_now(@requested_feature)
        UI.beep unless payload
      end

      @dialog.add_action_callback('buy_feature') do |_ctx, slug|
        result = create_payment_request(slug)
        @last_payment = result
        render_payment(result)
        if result['already_active'] == true
          sync_now(slug.to_s.to_sym)
        end
      end

      @dialog.add_action_callback('check_payment') do |_ctx, request_code|
        result = check_payment_request(request_code)
        @last_payment = result
        render_payment(result)
        payment = result['payment'].is_a?(Hash) ? result['payment'] : {}
        if result['ok'] == true && payment['status'].to_s == 'paid'
          sync_now(@requested_feature)
        end
      end

      @dialog.show
    end

    def dialog_html
      <<~HTML
        <!doctype html>
        <html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;background:#111827;color:#e5e7eb;font:14px Arial}.head{padding:18px 22px;background:linear-gradient(135deg,#f97316,#c2410c)}h1{margin:0;font-size:21px}.sub{margin-top:5px;font-size:12px;opacity:.9}.body{padding:18px}.box{background:#1f2937;border:1px solid #374151;border-radius:12px;padding:14px;margin-bottom:12px}.label{font-size:11px;color:#9ca3af;margin-bottom:5px}.code{font:700 21px Consolas,monospace;letter-spacing:1px;color:#fb923c}.paycode{font:700 18px Consolas,monospace;color:#fbbf24}.row{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}button{border:0;border-radius:8px;padding:9px 12px;font-weight:700;cursor:pointer}.orange{background:#f97316;color:#fff}.dark{background:#374151;color:#fff}.green{background:#059669;color:#fff}.buy{background:#ea580c;color:#fff;padding:7px 10px;font-size:12px}.ok{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}.muted{color:#9ca3af}.owner{display:inline-block;background:#065f46;color:#d1fae5;border:1px solid #10b981;border-radius:999px;padding:4px 9px;font-weight:700;margin-left:7px}.feature{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 0;border-bottom:1px solid #374151}.feature:last-child{border-bottom:0}.fmain{min-width:0;flex:1}.fname{font-weight:700}.fmeta{font-size:12px;margin-top:4px}.price{color:#fbbf24}.note{font-size:12px;color:#9ca3af;line-height:1.5}.empty{padding:12px 0;color:#fbbf24}.error{display:none;background:#450a0a;border:1px solid #ef4444;color:#fecaca;border-radius:9px;padding:10px;margin-bottom:12px;white-space:pre-wrap}.payment{display:none;border:1px solid #f97316}.payment h3{margin:0 0 10px;color:#fb923c}.pgrid{display:grid;grid-template-columns:145px 1fr;gap:7px 10px}.success{background:#052e2b;border-color:#10b981}</style></head><body>
        <div class="head"><h1>TRẦN TUẤN · BẢN QUYỀN & THANH TOÁN</h1><div class="sub">Chỉ sử dụng MÃ MÁY · mua quyền theo từng chức năng</div></div>
        <div class="body">
          <div id="errorBox" class="error"></div>
          <div class="box"><div class="label">MÃ MÁY</div><div id="machineCode" class="code">-</div><div class="row"><button class="dark" onclick="copyText(el('machineCode').textContent,this)">SAO CHÉP MÃ</button><button class="orange" onclick="sketchup.check()">KIỂM TRA KÍCH HOẠT</button></div></div>
          <div id="requestedBox" class="box" style="display:none"></div>
          <div id="paymentBox" class="box payment"></div>
          <div class="box"><div><b>Trạng thái máy:</b> <span id="machineStatus">-</span><span id="ownerBadge"></span></div><div style="margin-top:6px"><b>Đồng bộ:</b> <span id="syncTime">-</span></div><div style="margin-top:6px"><b>Quyền:</b> <span id="rightsCount">0/0</span></div><div style="margin-top:6px"><b>Chế độ thương mại:</b> <span id="commercialMode">-</span></div></div>
          <div class="box"><b>QUYỀN CHỨC NĂNG</b><div id="featureList" style="margin-top:8px"></div></div>
          <div class="note">Chức năng chưa mua sẽ có nút MUA / THANH TOÁN. Sau khi giao dịch được xác nhận, bấm KIỂM TRA THANH TOÁN hoặc KIỂM TRA KÍCH HOẠT để mở quyền ngay, không cần cài lại RBZ.</div>
        </div>
        <script>
        const el=id=>document.getElementById(id);
        const money=v=>v==null?'Chưa cấu hình giá':Number(v).toLocaleString('vi-VN')+' đ';
        function copyText(value,btn){const t=document.createElement('textarea');t.value=value||'';t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();try{document.execCommand('copy');if(btn){const old=btn.textContent;btn.textContent='ĐÃ SAO CHÉP';setTimeout(()=>btn.textContent=old,1200);}}catch(e){}document.body.removeChild(t);}
        function statusText(v){if(v==='active')return 'ACTIVE · ĐÃ KÍCH HOẠT';if(v==='pending')return 'CHỜ KÍCH HOẠT';if(v==='blocked')return 'ĐÃ KHÓA';return String(v||'CHƯA ĐỒNG BỘ').toUpperCase();}
        function buy(slug){if(slug)sketchup.buy_feature(slug);}
        window.renderLicense=d=>{
          el('machineCode').textContent=d.machine_code||'-';
          el('machineStatus').textContent=statusText(d.machine_status);
          el('machineStatus').className=d.machine_status==='active'?'ok':(d.machine_status==='blocked'?'bad':'muted');
          el('syncTime').textContent=d.synced_at||'-';
          el('commercialMode').textContent=d.enforcement?'ĐANG BẬT':'CHƯA BẬT';
          el('commercialMode').className=d.enforcement?'ok':'muted';
          el('ownerBadge').innerHTML=d.owner?'<span class="owner">OWNER</span>':'';
          el('rightsCount').textContent=String(d.allowed_count||0)+'/'+String(d.feature_count||0);

          const eb=el('errorBox');
          if(d.error){eb.style.display='block';eb.textContent='Lỗi đồng bộ: '+d.error;}else{eb.style.display='none';eb.textContent='';}

          const r=el('requestedBox');
          if(d.requested_feature){
            r.style.display='block';
            r.innerHTML='<b>'+d.requested_name+'</b><div style="margin-top:7px" class="'+(d.requested_allowed?'ok':'bad')+'">'+(d.requested_allowed?'ĐÃ KÍCH HOẠT':'CHƯA ĐƯỢC KÍCH HOẠT')+'</div><div class="price" style="margin-top:5px">Giá: '+money(d.requested_price)+'</div>'+(d.requested_allowed?'':'<div class="row"><button class="buy" onclick="buy(\''+d.requested_feature+'\')">MUA / THANH TOÁN</button></div>');
          }else{r.style.display='none';}

          let items=[];
          if(d.features&&typeof d.features==='object'&&!Array.isArray(d.features)){items=Object.keys(d.features).map(k=>Object.assign({slug:k},d.features[k]||{}));}
          if(items.length===0&&Array.isArray(d.feature_list)){items=d.feature_list;}
          const list=el('featureList');list.innerHTML='';
          if(items.length===0){const x=document.createElement('div');x.className='empty';x.textContent=d.error?'Không tải được danh sách quyền. Xem lỗi phía trên.':'Chưa tải được danh sách quyền. Hãy bấm KIỂM TRA KÍCH HOẠT.';list.appendChild(x);return;}
          items.forEach(x=>{
            const row=document.createElement('div');row.className='feature';
            const state=x.allowed?'ĐÃ MỞ':'KHÓA';
            const price=money(x.price_vnd);
            row.innerHTML='<div class="fmain"><div class="fname">'+String(x.name||x.slug||'Chức năng')+'</div><div class="fmeta '+(x.allowed?'ok':'bad')+'">'+state+' · <span class="price">'+price+'</span></div></div>'+(x.allowed?'':'<button class="buy" onclick="buy(\''+String(x.slug||'')+'\')">MUA</button>');
            list.appendChild(row);
          });
        };

        window.renderPayment=p=>{
          const box=el('paymentBox');box.className='box payment';box.style.display='block';
          if(!p||p.ok!==true){
            box.innerHTML='<h3>THANH TOÁN</h3><div class="bad">'+String((p&&p.friendly_error)||'Không tạo được yêu cầu thanh toán.')+'</div>';
            return;
          }
          if(p.already_active===true){box.className='box payment success';box.innerHTML='<h3>ĐÃ KÍCH HOẠT</h3><div class="ok">Chức năng này đã có quyền sử dụng.</div>';return;}
          const pay=p.payment||{};const prod=p.product||{};
          const st=String(pay.status||'pending');
          if(st==='paid')box.className='box payment success';
          box.innerHTML='<h3>YÊU CẦU THANH TOÁN</h3><div class="pgrid"><b>Chức năng</b><span>'+String(prod.name||prod.slug||'-')+'</span><b>Số tiền</b><span class="price">'+money(pay.amount_vnd!=null?pay.amount_vnd:prod.price_vnd)+'</span><b>Mã thanh toán</b><span id="paymentCode" class="paycode">'+String(pay.request_code||'-')+'</span><b>Trạng thái</b><span class="'+(st==='paid'?'ok':'muted')+'">'+(st==='paid'?'ĐÃ THANH TOÁN':'CHỜ THANH TOÁN')+'</span></div><div class="row"><button class="dark" onclick="copyText(el(\'paymentCode\').textContent,this)">SAO CHÉP MÃ THANH TOÁN</button><button class="green" onclick="sketchup.check_payment(el(\'paymentCode\').textContent)">KIỂM TRA THANH TOÁN</button></div>';
        };
        document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
        </script></body></html>
      HTML
    end
  end
end
