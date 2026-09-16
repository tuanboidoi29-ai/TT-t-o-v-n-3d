# encoding: UTF-8
# TRẦN TUẤN - OWNER ADMIN V1.2.1 HOTFIX
# Không wrap window.renderLicense. Giữ nguyên JS Payment V1.1.0 đã ổn định.

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.2.1'.freeze

    # refresh_dialog của License Manager V1.0.2 là nguồn render chính.
    unless method_defined?(:tt_refresh_dialog_before_owner_v121)
      alias_method :tt_refresh_dialog_before_owner_v121, :refresh_dialog
    end

    # Bỏ hoàn toàn hook JS của V1.2.0. Chỉ chèn HTML launcher tĩnh vào
    # đúng UI Payment V1.1.0 rồi Ruby tự bật/tắt launcher sau refresh.
    def dialog_html
      html = tt_dialog_html_payment_v110
      launcher = <<~HTML
        <div id="ownerAdminLauncher" class="box" style="display:none;border-color:#10b981">
          <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">
            <div>
              <b style="color:#34d399">QUYỀN QUẢN LÝ OWNER</b>
              <div class="note" style="margin-top:5px">Quản lý khách hàng, giá bán, thanh toán và quyền từng chức năng.</div>
            </div>
            <button class="green" onclick="sketchup.owner_admin_open()">MỞ QUẢN LÝ</button>
          </div>
        </div>
      HTML

      marker = '<div class="note">Chức năng chưa mua'
      return html unless html.include?(marker)
      html.sub(marker, launcher + marker)
    end

    def refresh_dialog(payload_override = nil)
      result = tt_refresh_dialog_before_owner_v121(payload_override)
      return result unless @dialog && @dialog.visible?

      payload = normalize_payload(payload_override || cache)
      show_owner = owner_admin?(payload)
      js = <<~JS
        (function(){
          var box = document.getElementById('ownerAdminLauncher');
          if (box) box.style.display = #{show_owner ? "'block'" : "'none'"};
        })();
      JS
      @dialog.execute_script(js)
      result
    rescue StandardError => error
      puts "[TT Owner Admin V1.2.1 UI] #{error.class}: #{error.message}"
      result
    end
  end
end
