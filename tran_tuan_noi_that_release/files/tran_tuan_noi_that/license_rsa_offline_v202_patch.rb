# encoding: UTF-8
# TRẦN TUẤN - LICENSE RSA OFFLINE V2.0.2
# Không dùng confirm/UI.messagebox trong luồng bản quyền để tránh kẹt focus SketchUp.

require 'json'

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '2.0.2'.freeze

    unless method_defined?(:tt_dialog_html_v201)
      alias_method :tt_dialog_html_v201, :dialog_html
    end

    def tt_notice(message, kind = 'info', timeout_ms = 4500)
      return false unless @dialog && @dialog.visible?
      js = "window.ttNotice && window.ttNotice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind.to_s)}, #{timeout_ms.to_i});"
      @dialog.execute_script(js)
      true
    rescue StandardError => error
      puts "[TT RSA notice] #{error.class}: #{error.message}"
      false
    end

    def close_license_dialog
      dialog = @dialog
      @dialog = nil
      dialog.close if dialog && dialog.respond_to?(:close)
      true
    rescue StandardError => error
      puts "[TT RSA close] #{error.class}: #{error.message}"
      false
    end

    def show_dialog(_feature = nil)
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        refresh_dialog
        return true
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - KÍCH HOẠT BẢN QUYỀN RSA',
        preferences_key: 'TranTuanNoiThat.RSAOfflineV202',
        scrollable: true,
        resizable: true,
        width: 700,
        height: 800,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('ready') { |_ctx| refresh_dialog }
      @dialog.add_action_callback('activate_code') do |_ctx, code|
        begin
          activate(code)
          refresh_dialog
          tt_notice('Kích hoạt bản quyền thành công.', 'ok', 4500)
        rescue StandardError => error
          @last_error = error.message
          refresh_dialog(invalid_state(error.message))
          tt_notice(error.message, 'error', 7000)
        end
      end
      @dialog.add_action_callback('clear_code') do |_ctx|
        if clear_activation
          refresh_dialog
          tt_notice('Đã xóa mã kích hoạt trên máy này.', 'warn', 4500)
        else
          tt_notice('Không xóa được mã kích hoạt.', 'error', 7000)
        end
      end
      @dialog.add_action_callback('close_dialog') { |_ctx| close_license_dialog }
      @dialog.set_on_closed { @dialog = nil } if @dialog.respond_to?(:set_on_closed)
      @dialog.show
      true
    rescue StandardError => error
      puts "[TT RSA show] #{error.class}: #{error.message}"
      Sketchup.status_text = "Không mở được bảng Bản Quyền: #{error.message}" if defined?(Sketchup)
      false
    end

    def dialog_html
      html = tt_dialog_html_v201

      html = html.sub(
        '</style>',
        '.ttnotice{display:none;position:sticky;top:0;z-index:50;margin:0 0 12px;padding:10px 42px 10px 12px;border-radius:9px;border:1px solid #475569;background:#111827;box-shadow:0 8px 24px rgba(0,0,0,.25)}.ttnotice.ok{display:block;border-color:#10b981;color:#d1fae5;background:#052e2b}.ttnotice.warn{display:block;border-color:#f59e0b;color:#fef3c7;background:#451a03}.ttnotice.error{display:block;border-color:#ef4444;color:#fee2e2;background:#450a0a}.ttnotice.info{display:block;border-color:#3b82f6;color:#dbeafe;background:#172554}.ttnotice button{position:absolute;right:7px;top:6px;padding:4px 8px;background:transparent;color:inherit;border:0;font-size:18px}.closebar{display:flex;justify-content:flex-end;margin-top:12px}</style>'
      )

      html = html.sub(
        '<div class="body">',
        '<div class="body"><div id="ttNotice" class="ttnotice"><span id="ttNoticeText"></span><button type="button" onclick="ttCloseNotice()">×</button></div>'
      )

      html = html.gsub('onclick="clearNow()"', 'onclick="clearNow(this)"')

      old_clear = %q{function clearNow(){if(confirm('Xóa mã kích hoạt đang lưu trên máy này?'))sketchup.clear_code();}}
      new_clear = %q{let ttClearArmed=false,ttClearTimer=null;function ttResetClear(btn){ttClearArmed=false;if(ttClearTimer){clearTimeout(ttClearTimer);ttClearTimer=null;}if(btn)btn.textContent='XÓA MÃ ĐANG LƯU';}function clearNow(btn){if(!ttClearArmed){ttClearArmed=true;if(btn)btn.textContent='BẤM LẠI ĐỂ XÓA';ttNotice('Nhấn lại nút XÓA MÃ trong 4 giây để xác nhận.','warn',4000);ttClearTimer=setTimeout(()=>ttResetClear(btn),4000);return;}ttResetClear(btn);sketchup.clear_code();}}
      html = html.gsub(old_clear, new_clear)

      hook = %q{function ttCloseNotice(){const n=el('ttNotice');if(n){n.className='ttnotice';n.style.display='none';}if(window.ttNoticeTimer){clearTimeout(window.ttNoticeTimer);window.ttNoticeTimer=null;}}window.ttNotice=(msg,kind,timeout)=>{const n=el('ttNotice'),t=el('ttNoticeText');if(!n||!t)return;t.textContent=String(msg||'');n.className='ttnotice '+String(kind||'info');n.style.display='block';if(window.ttNoticeTimer)clearTimeout(window.ttNoticeTimer);const ms=Number(timeout||4500);if(ms>0)window.ttNoticeTimer=setTimeout(ttCloseNotice,ms);};document.addEventListener('keydown',e=>{if(e.key==='Escape'){sketchup.close_dialog();}});}
      hook = hook.sub(/;\}\z/, ';')
      html = html.sub('const el=id=>document.getElementById(id);', 'const el=id=>document.getElementById(id);' + hook)

      html = html.sub(
        '<div class="note">Mã kích hoạt được ký RSA và gắn với đúng Mã máy. Sao chép RBZ hoặc mã kích hoạt sang máy khác sẽ không mở được hệ thống.</div>',
        '<div class="note">Mã kích hoạt được ký RSA và gắn với đúng Mã máy. Sao chép RBZ hoặc mã kích hoạt sang máy khác sẽ không mở được hệ thống.</div><div class="closebar"><button class="dark" onclick="sketchup.close_dialog()">ĐÓNG</button></div>'
      )

      html
    end
  end
end
