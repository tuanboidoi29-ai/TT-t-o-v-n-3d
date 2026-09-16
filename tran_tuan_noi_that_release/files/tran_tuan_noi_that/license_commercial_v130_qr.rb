# encoding: UTF-8
# TRẦN TUẤN - LICENSE COMMERCIAL V1.3.0
# - OWNER cấu hình ngân hàng/QR trực tiếp trong bảng quản lý.
# - Khách bấm MUA nhận QR chuyển khoản đúng số tiền + mã thanh toán.
# - Không hard-code số tài khoản trong RBZ; dữ liệu nằm trên server.

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.3.0'.freeze

    unless method_defined?(:tt_dialog_html_before_commercial_v130)
      alias_method :tt_dialog_html_before_commercial_v130, :dialog_html
    end

    unless method_defined?(:tt_owner_admin_html_before_commercial_v130)
      alias_method :tt_owner_admin_html_before_commercial_v130, :owner_admin_html
    end

    # ------------------------------------------------------------
    # KHÁCH: bổ sung khối QR vào cửa sổ thanh toán hiện có.
    # ------------------------------------------------------------
    def dialog_html
      html = tt_dialog_html_before_commercial_v130

      hook = <<~'JS'
        const ttRenderPaymentV130 = window.renderPayment;
        window.renderPayment = p => {
          ttRenderPaymentV130(p);
          const old = document.getElementById('ttQrPaymentV130');
          if (old) old.remove();
          if (!p || p.ok !== true || !p.payment || p.already_active === true) return;

          const pay = p.payment || {};
          const box = document.getElementById('paymentBox');
          if (!box) return;

          const wrap = document.createElement('div');
          wrap.id = 'ttQrPaymentV130';
          wrap.style.marginTop = '14px';
          wrap.style.paddingTop = '14px';
          wrap.style.borderTop = '1px solid #f97316';

          if (pay.qr_enabled === true && pay.qr_image_url) {
            const title = document.createElement('div');
            title.textContent = 'QUÉT QR ĐỂ THANH TOÁN';
            title.style.fontWeight = '800';
            title.style.color = '#34d399';
            title.style.marginBottom = '10px';
            wrap.appendChild(title);

            const layout = document.createElement('div');
            layout.style.display = 'flex';
            layout.style.gap = '14px';
            layout.style.alignItems = 'flex-start';
            layout.style.flexWrap = 'wrap';

            const img = document.createElement('img');
            img.src = String(pay.qr_image_url);
            img.alt = 'QR chuyển khoản';
            img.style.width = '230px';
            img.style.maxWidth = '100%';
            img.style.background = '#fff';
            img.style.borderRadius = '10px';
            img.style.padding = '7px';
            layout.appendChild(img);

            const info = document.createElement('div');
            info.style.flex = '1';
            info.style.minWidth = '220px';

            const rows = [
              ['Ngân hàng', pay.bank_name || pay.bank_id || '-'],
              ['Số tài khoản', pay.account_number || '-'],
              ['Chủ tài khoản', pay.account_name || '-'],
              ['Số tiền', money(pay.amount_vnd)],
              ['Nội dung', pay.transfer_content || pay.request_code || '-']
            ];
            rows.forEach(row => {
              const line = document.createElement('div');
              line.style.marginBottom = '8px';
              const b = document.createElement('b');
              b.textContent = row[0] + ': ';
              const span = document.createElement('span');
              span.textContent = String(row[1]);
              if (row[0] === 'Nội dung') {
                span.style.color = '#fbbf24';
                span.style.fontWeight = '800';
              }
              line.appendChild(b);
              line.appendChild(span);
              info.appendChild(line);
            });

            const copyBtn = document.createElement('button');
            copyBtn.className = 'dark';
            copyBtn.textContent = 'SAO CHÉP NỘI DUNG';
            copyBtn.onclick = () => copyText(String(pay.transfer_content || pay.request_code || ''), copyBtn);
            info.appendChild(copyBtn);
            layout.appendChild(info);
            wrap.appendChild(layout);

            const note = document.createElement('div');
            note.className = 'note';
            note.style.marginTop = '10px';
            note.textContent = 'Chuyển đúng số tiền và đúng nội dung. Sau khi OWNER xác nhận giao dịch, bấm KIỂM TRA THANH TOÁN để mở chức năng.';
            wrap.appendChild(note);
          } else {
            const note = document.createElement('div');
            note.className = 'note';
            note.textContent = 'QR thanh toán chưa được OWNER cấu hình. Hãy gửi Mã thanh toán cho TRẦN TUẤN để được hướng dẫn thanh toán.';
            wrap.appendChild(note);
          }
          box.appendChild(wrap);
        };
      JS

      marker = "document.addEventListener('DOMContentLoaded',()=>sketchup.ready());"
      html.include?(marker) ? html.sub(marker, hook + "\n" + marker) : html
    end

    # ------------------------------------------------------------
    # OWNER: thêm cấu hình ngân hàng/QR ngay trong dashboard.
    # ------------------------------------------------------------
    def owner_admin_html
      html = tt_owner_admin_html_before_commercial_v130

      payment_box = <<~'HTML'
        <div class="box" id="paymentConfigV130">
          <div class="title">CÀI ĐẶT THANH TOÁN QR</div>
          <div class="grid">
            <div class="card"><div class="small muted">BANK ID / MÃ NGÂN HÀNG</div><input id="payBankId" placeholder="VD: VCB, MB, OCB" style="width:100%;margin-top:6px"></div>
            <div class="card"><div class="small muted">TÊN NGÂN HÀNG</div><input id="payBankName" placeholder="Tên hiển thị" style="width:100%;margin-top:6px"></div>
            <div class="card"><div class="small muted">SỐ TÀI KHOẢN</div><input id="payAccountNumber" placeholder="Số tài khoản nhận tiền" style="width:100%;margin-top:6px"></div>
            <div class="card"><div class="small muted">CHỦ TÀI KHOẢN</div><input id="payAccountName" placeholder="Tên chủ tài khoản" style="width:100%;margin-top:6px"></div>
            <div class="card"><div class="small muted">TIỀN TỐ NỘI DUNG</div><input id="payNotePrefix" value="TT" maxlength="24" style="width:100%;margin-top:6px"></div>
            <div class="card"><label><input id="payQrEnabled" type="checkbox"> BẬT QR CHO KHÁCH</label><div class="small muted" style="margin-top:8px">Chỉ bật sau khi đã nhập đủ ngân hàng, số tài khoản và chủ tài khoản.</div></div>
          </div>
          <div class="row" style="margin-top:10px"><button class="green" onclick="savePaymentConfigV130()">LƯU CÀI ĐẶT THANH TOÁN</button><span id="payConfigState" class="muted">-</span></div>
        </div>
      HTML

      price_marker = '<div class="box"><div class="title">GIÁ CHỨC NĂNG</div>'
      html = html.sub(price_marker, payment_box + price_marker) if html.include?(price_marker)

      hook = <<~'JS'
        function savePaymentConfigV130(){
          const bankId = document.getElementById('payBankId').value.trim();
          const bankName = document.getElementById('payBankName').value.trim();
          const accountNumber = document.getElementById('payAccountNumber').value.trim();
          const accountName = document.getElementById('payAccountName').value.trim();
          const notePrefix = document.getElementById('payNotePrefix').value.trim() || 'TT';
          const qrEnabled = document.getElementById('payQrEnabled').checked === true;
          if (qrEnabled && (!bankId || !accountNumber || !accountName)) {
            alert('Muốn bật QR cần nhập đủ BANK ID, Số tài khoản và Chủ tài khoản.');
            return;
          }
          act({action:'set_payment_config',bank_id:bankId,bank_name:bankName,account_number:accountNumber,account_name:accountName,note_prefix:notePrefix,qr_enabled:qrEnabled});
        }

        const ttRenderAdminV130 = window.renderAdmin;
        window.renderAdmin = d => {
          ttRenderAdminV130(d);
          if (!d || d.ok !== true) return;
          const c = d.config || {};
          const setv = (id,v) => { const n=document.getElementById(id); if(n) n.value = v == null ? '' : String(v); };
          setv('payBankId', c.payment_bank_id);
          setv('payBankName', c.payment_bank_name);
          setv('payAccountNumber', c.payment_account_number);
          setv('payAccountName', c.payment_account_name);
          setv('payNotePrefix', c.payment_note_prefix || 'TT');
          const enabled = document.getElementById('payQrEnabled');
          if (enabled) enabled.checked = c.payment_qr_enabled === true;
          const st = document.getElementById('payConfigState');
          if (st) {
            const ready = !!c.payment_bank_id && !!c.payment_account_number && !!c.payment_account_name;
            st.textContent = (c.payment_qr_enabled === true && ready) ? 'QR ĐANG BẬT' : (ready ? 'ĐÃ NHẬP · QR ĐANG TẮT' : 'CHƯA CẤU HÌNH ĐỦ');
            st.className = (c.payment_qr_enabled === true && ready) ? 'ok' : 'warn';
          }
        };
      JS

      marker = "document.addEventListener('DOMContentLoaded',()=>sketchup.admin_ready());"
      html.include?(marker) ? html.sub(marker, hook + "\n" + marker) : html
    end
  end
end
