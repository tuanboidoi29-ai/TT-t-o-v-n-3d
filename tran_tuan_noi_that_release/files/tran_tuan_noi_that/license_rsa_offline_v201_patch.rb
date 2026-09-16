# encoding: UTF-8
# TRẦN TUẤN - LICENSE RSA OFFLINE V2.0.1 COMMERCIAL PATCH
# Một mã RSA theo MÃ MÁY mở toàn bộ hệ thống.

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.0.1'.freeze

    remove_const(:ZALO) if const_defined?(:ZALO, false)
    ZALO = '0338162946'.freeze
    remove_const(:BANK_NAME) if const_defined?(:BANK_NAME, false)
    BANK_NAME = 'KienlongBank'.freeze
    remove_const(:BANK_ACCOUNT) if const_defined?(:BANK_ACCOUNT, false)
    BANK_ACCOUNT = '0338162946'.freeze
    remove_const(:BANK_OWNER) if const_defined?(:BANK_OWNER, false)
    BANK_OWNER = 'TRẦN ĐÌNH TUẤN'.freeze

    # Giữ 360d để các mã cũ đã phát hành không bị vô hiệu hóa,
    # nhưng không còn hiển thị/bán gói này trong giao diện mới.
    remove_const(:PLANS) if const_defined?(:PLANS, false)
    PLANS = {
      '90d' => { 'label' => '90 ngày', 'days' => 90, 'price_vnd' => 50_000 },
      '180d' => { 'label' => '180 ngày', 'days' => 180, 'price_vnd' => 100_000 },
      '360d' => { 'label' => '360 ngày (mã cũ)', 'days' => 360, 'price_vnd' => 120_000 },
      'lifetime' => { 'label' => 'Vĩnh viễn', 'days' => nil, 'price_vnd' => 200_000 }
    }.freeze

    SALE_PLAN_IDS = %w[90d 180d lifetime].freeze unless const_defined?(:SALE_PLAN_IDS, false)

    def dialog_html
      <<~HTML
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8">
          <style>
            *{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:14px Arial}
            .head{padding:18px 22px;background:linear-gradient(135deg,#ea580c,#c2410c)}
            h1{margin:0;font-size:21px}.sub{margin-top:5px;font-size:12px;opacity:.94}
            .body{padding:17px}.box{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:14px;margin-bottom:12px}
            .label{font-size:11px;color:#94a3b8;margin-bottom:5px}.code{font:700 20px Consolas,monospace;letter-spacing:1px;color:#fb923c;word-break:break-all}
            .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
            button{border:0;border-radius:8px;padding:9px 12px;font-weight:700;cursor:pointer}.orange{background:#f97316;color:white}.green{background:#059669;color:white}.dark{background:#334155;color:white}.red{background:#b91c1c;color:white}
            .ok{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}.warn{color:#fbbf24;font-weight:700}.muted{color:#94a3b8}.price{color:#fbbf24;font-weight:800}
            .plans{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:9px}.plan{background:#111827;border:1px solid #374151;border-radius:9px;padding:10px;text-align:center}.plan b{display:block;margin-bottom:5px}
            .info{display:grid;grid-template-columns:150px 1fr;gap:8px 10px;line-height:1.45}.note{font-size:12px;color:#94a3b8;line-height:1.55}
            textarea{width:100%;min-height:120px;resize:vertical;background:#0b1220;color:#f8fafc;border:1px solid #475569;border-radius:8px;padding:10px;font:12px Consolas,monospace;margin-top:8px}
            @media(max-width:560px){.plans{grid-template-columns:1fr}.info{grid-template-columns:1fr}}
          </style>
        </head>
        <body>
          <div class="head">
            <h1>TRẦN TUẤN · KÍCH HOẠT BẢN QUYỀN</h1>
            <div class="sub">1 MÃ BẢN QUYỀN MỞ TOÀN BỘ HỆ THỐNG · KHÓA THEO MÁY · RSA OFFLINE</div>
          </div>
          <div class="body">
            <div class="box">
              <div class="label">MÃ MÁY</div>
              <div id="machineCode" class="code">-</div>
              <div class="row"><button class="dark" onclick="copyValue('machineCode',this)">SAO CHÉP MÃ MÁY</button></div>
            </div>

            <div class="box">
              <b>MUA BẢN QUYỀN</b>
              <div class="note" style="margin-top:7px">Kết bạn Zalo <b>0338162946</b> → gửi <b>MÃ MÁY</b> → nhận <b>MÃ KÍCH HOẠT</b>.</div>
              <div class="plans">
                <div class="plan"><b>90 NGÀY</b><span class="price">50.000đ</span></div>
                <div class="plan"><b>180 NGÀY</b><span class="price">100.000đ</span></div>
                <div class="plan"><b>VĨNH VIỄN</b><span class="price">200.000đ</span></div>
              </div>
            </div>

            <div class="box">
              <b>THÔNG TIN CHUYỂN KHOẢN</b>
              <div class="info" style="margin-top:10px">
                <span>Ngân hàng</span><b id="bankName">KienlongBank</b>
                <span>Số tài khoản</span><b id="bankAccount">0338162946</b>
                <span>Chủ tài khoản</span><b id="bankOwner">TRẦN ĐÌNH TUẤN</b>
                <span>Nội dung CK</span><b id="transferNote" class="code" style="font-size:14px">-</b>
              </div>
              <div class="row"><button class="dark" onclick="copyValue('bankAccount',this)">SAO CHÉP STK</button><button class="dark" onclick="copyValue('transferNote',this)">SAO CHÉP NỘI DUNG CK</button></div>
            </div>

            <div class="box">
              <b>TRẠNG THÁI BẢN QUYỀN</b>
              <div id="licenseState" class="warn" style="margin-top:8px">CHƯA KÍCH HOẠT</div>
              <div id="licenseMeta" class="note" style="margin-top:6px"></div>
            </div>

            <div class="box">
              <div class="label">NHẬP MÃ KÍCH HOẠT RSA</div>
              <textarea id="activationCode" placeholder="Dán mã TTRSA2... do TRẦN TUẤN cấp"></textarea>
              <div class="row"><button class="green" onclick="activateNow()">KÍCH HOẠT TOÀN BỘ HỆ THỐNG</button><button class="red" onclick="clearNow()">XÓA MÃ ĐANG LƯU</button></div>
            </div>

            <div class="note">Mã kích hoạt được ký RSA và gắn với đúng Mã máy. Sao chép RBZ hoặc mã kích hoạt sang máy khác sẽ không mở được hệ thống.</div>
          </div>
          <script>
            const el=id=>document.getElementById(id);
            function copyValue(id,btn){const text=el(id).textContent||el(id).value||'';const t=document.createElement('textarea');t.value=text;document.body.appendChild(t);t.select();try{document.execCommand('copy');if(btn){const old=btn.textContent;btn.textContent='ĐÃ SAO CHÉP';setTimeout(()=>btn.textContent=old,1200);}}catch(e){}document.body.removeChild(t);}
            function activateNow(){sketchup.activate_code(el('activationCode').value||'');}
            function clearNow(){if(confirm('Xóa mã kích hoạt đang lưu trên máy này?'))sketchup.clear_code();}
            window.renderLicense=d=>{
              d=d||{};
              el('machineCode').textContent=d.machine_code||'-';
              el('bankName').textContent=d.bank_name||'KienlongBank';
              el('bankAccount').textContent=d.bank_account||'0338162946';
              el('bankOwner').textContent=d.bank_owner||'TRẦN ĐÌNH TUẤN';
              el('transferNote').textContent=d.transfer_note||d.machine_code||'-';
              const active=!!d.active;
              const state=el('licenseState');
              state.textContent=active?'ĐÃ KÍCH HOẠT · TOÀN BỘ HỆ THỐNG':'CHƯA KÍCH HOẠT';
              state.className=active?'ok':'warn';
              let meta='';
              if(active){meta='Gói: '+String(d.plan_label||d.plan||'-');if(d.lifetime){meta+=' · VĨNH VIỄN';}else{meta+=' · Còn '+String(d.remaining_days==null?'-':d.remaining_days)+' ngày';if(d.expires_at)meta+=' · Hết hạn: '+String(d.expires_at);}}
              else if(d.status_message){meta=String(d.status_message);}
              el('licenseMeta').textContent=meta;
            };
            document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
          </script>
        </body></html>
      HTML
    end
  end
end
