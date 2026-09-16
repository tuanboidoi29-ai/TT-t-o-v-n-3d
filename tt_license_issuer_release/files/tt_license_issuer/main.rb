# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'digest'
require 'open3'
Sketchup.require 'tt_license_issuer/signer'

module TTLicenseIssuer
  extend self

  VERSION = '1.1.0'.freeze
  PREF_KEY = 'TT_LICENSE_ISSUER_OWNER'.freeze
  OWNER_MACHINE_CODE = 'TT-5ACF-3BBC-FCC6'.freeze

  def windows_machine_guid
    return '' unless RUBY_PLATFORM =~ /mswin|mingw/i
    stdout, = Open3.capture3('reg query "HKLM\\SOFTWARE\\Microsoft\\Cryptography" /v MachineGuid')
    line = stdout.to_s.lines.find { |item| item =~ /MachineGuid/i }
    line ? line.strip.split(/\s+/).last.to_s.strip : ''
  rescue StandardError
    ''
  end

  def owner_machine_code
    raw = windows_machine_guid.to_s.strip
    raw = [ENV['COMPUTERNAME'], ENV['USERNAME'], RUBY_PLATFORM].compact.join('|') if raw.empty?
    digest = Digest::SHA256.hexdigest("TRANTUAN|#{raw}").upcase
    "TT-#{digest[0, 4]}-#{digest[4, 4]}-#{digest[8, 4]}"
  rescue StandardError
    'TT-0000-0000-0000'
  end

  def owner_authorized?
    owner_machine_code == OWNER_MACHINE_CODE
  end

  def guard_owner!
    return true if owner_authorized?
    raise "TRANTUAN-NOIITHAT-ADM chỉ được phép chạy trên máy OWNER #{OWNER_MACHINE_CODE}. Máy hiện tại: #{owner_machine_code}."
  end

  def key_path
    Sketchup.read_default(PREF_KEY, 'private_key_path', '').to_s
  end

  def save_key_path(path)
    Sketchup.write_default(PREF_KEY, 'private_key_path', path.to_s)
  end

  def current_key_state
    guard_owner!
    path = key_path
    return { ok: false, path: '', message: 'Chưa chọn khóa riêng RSA.' } if path.empty?
    key = Signer.load_private_key(path)
    {
      ok: true,
      path: path,
      fingerprint: Signer.public_fingerprint(key),
      message: 'Khóa RSA OWNER hợp lệ.'
    }
  rescue StandardError => error
    { ok: false, path: key_path, message: error.message }
  end

  def choose_key
    guard_owner!
    start_dir = key_path
    start_dir = File.dirname(start_dir) unless start_dir.empty?
    start_dir = Dir.home if start_dir.empty? || !Dir.exist?(start_dir)
    path = UI.openpanel('Chọn khóa riêng RSA OWNER', start_dir, 'PEM Files|*.pem||')
    return nil unless path
    key = Signer.load_private_key(path)
    save_key_path(path)
    {
      ok: true,
      path: path,
      fingerprint: Signer.public_fingerprint(key),
      message: 'Đã nạp khóa RSA OWNER.'
    }
  rescue StandardError => error
    { ok: false, path: (defined?(path) ? path.to_s : ''), message: error.message }
  end

  def generate(machine_code, plan)
    guard_owner!
    key = Signer.load_private_key(key_path)
    Signer.generate(machine_code, plan, key)
  rescue StandardError => error
    { 'ok' => false, 'error' => error.message }
  end

  def show
    unless owner_authorized?
      UI.messagebox("TRANTUAN-NOIITHAT-ADM đã khóa theo máy OWNER.\n\nMáy được phép: #{OWNER_MACHINE_CODE}\nMáy hiện tại: #{owner_machine_code}")
      return false
    end

    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      render_state
      return true
    end

    @dialog = UI::HtmlDialog.new(
      dialog_title: 'TRANTUAN-NOIITHAT-ADM - CẤP MÃ BẢN QUYỀN',
      preferences_key: 'TTLicenseIssuerOwnerV110',
      scrollable: true,
      resizable: true,
      width: 720,
      height: 760,
      style: UI::HtmlDialog::STYLE_DIALOG
    )
    @dialog.set_html(html)
    @dialog.add_action_callback('ready') { |_ctx| render_state }
    @dialog.add_action_callback('choose_key') do |_ctx|
      result = choose_key
      render_key_state(result || current_key_state)
    end
    @dialog.add_action_callback('generate_code') do |_ctx, machine, plan|
      render_result(generate(machine, plan))
    end
    @dialog.show
    true
  rescue StandardError => error
    UI.messagebox("Không mở được TRANTUAN-NOIITHAT-ADM:\n#{error.message}")
    false
  end

  def render_state
    return false unless @dialog && @dialog.visible?
    render_key_state(current_key_state)
    plans = Signer::PLANS.map do |slug, info|
      { slug: slug, label: info['label'], price_vnd: info['price_vnd'] }
    end
    payload = {
      owner_machine: owner_machine_code,
      expected_owner_machine: OWNER_MACHINE_CODE,
      authorized: owner_authorized?
    }
    @dialog.execute_script("window.setOwner(#{JSON.generate(payload)})")
    @dialog.execute_script("window.setPlans(#{JSON.generate(plans)})")
    true
  rescue StandardError => error
    puts "[TT License Issuer render_state] #{error.class}: #{error.message}"
    false
  end

  def render_key_state(state)
    return false unless @dialog && @dialog.visible?
    @dialog.execute_script("window.renderKey(#{JSON.generate(state || {})})")
    true
  end

  def render_result(result)
    return false unless @dialog && @dialog.visible?
    @dialog.execute_script("window.renderResult(#{JSON.generate(result || {})})")
    true
  end

  def install_ui
    return true if @ui_installed
    @ui_installed = true

    command = UI::Command.new('TRANTUAN-NOIITHAT-ADM') { show }
    icon = File.join(__dir__, 'issuer.svg')
    if File.file?(icon)
      command.small_icon = icon
      command.large_icon = icon
    end
    command.tooltip = 'TRANTUAN-NOIITHAT-ADM'
    command.status_bar_text = 'OWNER: nhập Mã máy khách, chọn 90/180 ngày hoặc Vĩnh viễn và cấp mã RSA.'

    UI.menu('Extensions').add_item(command)
    @toolbar = UI::Toolbar.new('TRANTUAN-NOIITHAT-ADM')
    @toolbar.add_item(command)
    @toolbar.restore
    @toolbar.show
    true
  end

  def html
    <<~HTML
      <!doctype html>
      <html lang="vi">
      <head>
        <meta charset="utf-8">
        <style>
          *{box-sizing:border-box} body{margin:0;background:#0f172a;color:#e5e7eb;font:14px Arial}
          .head{padding:18px 22px;background:linear-gradient(135deg,#0f766e,#115e59)}
          h1{margin:0;font-size:21px}.sub{margin-top:5px;font-size:12px;opacity:.9}
          .body{padding:18px}.box{background:#1e293b;border:1px solid #334155;border-radius:12px;padding:14px;margin-bottom:12px}
          .title{font-weight:800;margin-bottom:9px}.label{font-size:11px;color:#94a3b8;margin-bottom:5px}
          input,select,textarea{width:100%;background:#0f172a;color:#f8fafc;border:1px solid #475569;border-radius:8px;padding:10px}
          textarea{height:155px;resize:vertical;font:12px Consolas,monospace}
          button{border:0;border-radius:8px;padding:10px 13px;font-weight:700;cursor:pointer}
          .green{background:#059669;color:white}.orange{background:#ea580c;color:white}.dark{background:#334155;color:white}
          .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}.row>*{flex:1}.row button{flex:0 0 auto}
          .ok{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}.warn{color:#fbbf24}.muted{color:#94a3b8}
          .meta{display:grid;grid-template-columns:145px 1fr;gap:7px 10px;margin-top:10px}.code{font:700 15px Consolas,monospace;color:#fb923c}
          .note{font-size:12px;line-height:1.5;color:#94a3b8}
        </style>
      </head>
      <body>
        <div class="head"><h1>TRANTUAN-NOIITHAT-ADM</h1><div class="sub">Máy OWNER · cấp 1 mã RSA mở toàn bộ hệ thống cho khách</div></div>
        <div class="body">
          <div class="box">
            <div class="title">KHÓA MÁY OWNER</div>
            <div id="ownerState" class="warn">Đang kiểm tra...</div>
            <div id="ownerMachine" class="code" style="margin-top:6px">-</div>
          </div>

          <div class="box">
            <div class="title">KHÓA KÝ RSA OWNER</div>
            <div id="keyStatus" class="warn">Đang kiểm tra...</div>
            <div id="keyPath" class="note" style="margin-top:6px"></div>
            <div class="row"><button class="dark" onclick="sketchup.choose_key()">CHỌN FILE KHÓA RSA</button></div>
          </div>

          <div class="box">
            <div class="title">CẤP MÃ KÍCH HOẠT TOÀN HỆ THỐNG</div>
            <div class="label">MÃ MÁY KHÁCH</div>
            <input id="machine" placeholder="TT-XXXX-XXXX-XXXX" autocomplete="off">
            <div class="label" style="margin-top:10px">THỜI HẠN</div>
            <select id="plan"></select>
            <div class="row"><button class="orange" onclick="generateCode()">TẠO MÃ KÍCH HOẠT</button></div>
          </div>

          <div id="resultBox" class="box" style="display:none">
            <div class="title">MÃ KÍCH HOẠT</div>
            <div id="resultState" class="ok"></div>
            <div class="meta">
              <b>Mã máy</b><span id="outMachine" class="code">-</span>
              <b>Gói</b><span id="outPlan">-</span>
              <b>Hết hạn</b><span id="outExpiry">-</span>
            </div>
            <textarea id="activation" readonly></textarea>
            <div class="row"><button class="green" onclick="copyActivation(this)">SAO CHÉP MÃ KÍCH HOẠT</button></div>
          </div>

          <div class="note">Bảo vệ 2 lớp: RBZ ADM chỉ chạy trên Mã máy OWNER <b>TT-5ACF-3BBC-FCC6</b>, đồng thời private key RSA không nằm trong RBZ/GitHub. Hãy giữ file private key riêng trên máy OWNER và sao lưu ngoại tuyến.</div>
        </div>

        <script>
          const el=id=>document.getElementById(id);
          const money=v=>Number(v||0).toLocaleString('vi-VN')+'đ';

          window.setOwner=s=>{
            const ok=!!(s&&s.authorized);el('ownerState').textContent=ok?'MÁY OWNER HỢP LỆ':'MÁY KHÔNG ĐƯỢC PHÉP';el('ownerState').className=ok?'ok':'bad';el('ownerMachine').textContent=String((s&&s.owner_machine)||'-');
          };

          window.setPlans=items=>{
            const p=el('plan');p.innerHTML='';
            (items||[]).forEach(x=>{const o=document.createElement('option');o.value=x.slug;o.textContent=x.label+' · '+money(x.price_vnd);p.appendChild(o);});
          };

          window.renderKey=s=>{
            const ok=!!(s&&s.ok);el('keyStatus').textContent=ok?'KHÓA RSA HỢP LỆ':String((s&&s.message)||'Chưa chọn khóa RSA');el('keyStatus').className=ok?'ok':'bad';el('keyPath').textContent=String((s&&s.path)||'');
          };

          function generateCode(){sketchup.generate_code(el('machine').value.trim(),el('plan').value);}

          window.renderResult=r=>{
            const box=el('resultBox');box.style.display='block';
            if(!r||r.ok!==true){el('resultState').textContent=String((r&&r.error)||'Không tạo được mã kích hoạt.');el('resultState').className='bad';el('activation').value='';el('outMachine').textContent='-';el('outPlan').textContent='-';el('outExpiry').textContent='-';return;}
            el('resultState').textContent='TẠO MÃ THÀNH CÔNG';el('resultState').className='ok';
            el('outMachine').textContent=r.machine_code||'-';el('outPlan').textContent=(r.plan_label||r.plan||'-')+' · '+money(r.price_vnd);el('outExpiry').textContent=r.lifetime?'VĨNH VIỄN':String(r.expires_at||'-');el('activation').value=r.activation_code||'';
          };

          function copyActivation(btn){const t=el('activation');t.focus();t.select();try{document.execCommand('copy');const old=btn.textContent;btn.textContent='ĐÃ SAO CHÉP';setTimeout(()=>btn.textContent=old,1200);}catch(e){}}
          document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
        </script>
      </body></html>
    HTML
  end
end

TTLicenseIssuer.install_ui
