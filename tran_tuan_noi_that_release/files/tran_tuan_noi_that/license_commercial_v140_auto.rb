# encoding: UTF-8
# TRẦN TUẤN - LICENSE COMMERCIAL V1.4.0
# - SePay webhook tự đánh dấu giao dịch license PAID khi đúng mã + đúng số tiền.
# - SketchUp tự kiểm tra thanh toán nền mỗi 8 giây, không chặn UI.
# - Khi PAID: tự đồng bộ quyền, không cần cài lại RBZ.

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.4.0'.freeze

    unless method_defined?(:tt_show_dialog_before_commercial_v140)
      alias_method :tt_show_dialog_before_commercial_v140, :show_dialog
    end

    unless method_defined?(:tt_dialog_html_before_commercial_v140)
      alias_method :tt_dialog_html_before_commercial_v140, :dialog_html
    end

    def show_dialog(feature = nil)
      result = tt_show_dialog_before_commercial_v140(feature)
      bind_auto_payment_callback_v140
      result
    end

    def bind_auto_payment_callback_v140
      return false unless @dialog
      dialog_id = @dialog.object_id
      return true if @auto_payment_bound_dialog_id_v140 == dialog_id

      @auto_payment_bound_dialog_id_v140 = dialog_id
      @dialog.add_action_callback('auto_check_payment') do |_ctx, request_code|
        auto_check_payment_async_v140(request_code)
      end
      true
    rescue StandardError => error
      puts "[TT License V1.4.0 bind] #{error.class}: #{error.message}"
      false
    end

    def auto_check_payment_async_v140(request_code)
      code = request_code.to_s.strip.upcase
      return false if code.empty?
      return false if @auto_payment_syncing_v140

      @auto_payment_syncing_v140 = true
      @auto_payment_pending_v140 = :waiting
      @auto_payment_code_v140 = code
      started_at = Time.now

      Thread.new do
        begin
          @auto_payment_pending_v140 = check_payment_request(code)
        rescue StandardError => error
          @auto_payment_pending_v140 = {
            'ok' => false,
            'error' => 'network_error',
            'message' => "#{error.class}: #{error.message}"
          }
        end
      end

      @auto_payment_timer_v140 = UI.start_timer(0.20, true) do
        if @auto_payment_pending_v140 == :waiting
          if Time.now - started_at >= 12.0
            UI.stop_timer(@auto_payment_timer_v140) if @auto_payment_timer_v140
            @auto_payment_pending_v140 = nil
            @auto_payment_syncing_v140 = false
            auto_payment_state_v140('Mất kết nối tạm thời · hệ thống sẽ thử lại.', 'warn')
          end
          next
        end

        UI.stop_timer(@auto_payment_timer_v140) if @auto_payment_timer_v140
        result = @auto_payment_pending_v140
        @auto_payment_pending_v140 = nil
        @auto_payment_syncing_v140 = false

        payment = result.is_a?(Hash) && result['payment'].is_a?(Hash) ? result['payment'] : {}
        status = payment['status'].to_s

        if result.is_a?(Hash) && result['ok'] == true && status == 'paid'
          @last_payment = result
          render_payment(result)
          auto_payment_state_v140('ĐÃ NHẬN THANH TOÁN · ĐANG MỞ QUYỀN...', 'ok')
          background_sync
        elsif result.is_a?(Hash) && result['ok'] == true
          auto_payment_state_v140('Đang chờ giao dịch ngân hàng...', 'wait')
        else
          auto_payment_state_v140('Chưa kiểm tra được · sẽ tự thử lại.', 'warn')
        end
      end
      true
    rescue StandardError => error
      @auto_payment_pending_v140 = nil
      @auto_payment_syncing_v140 = false
      puts "[TT License V1.4.0 auto payment] #{error.class}: #{error.message}"
      auto_payment_state_v140('Lỗi kiểm tra nền · có thể bấm KIỂM TRA THANH TOÁN thủ công.', 'warn')
      false
    end

    def auto_payment_state_v140(message, kind = 'wait')
      return false unless @dialog && @dialog.visible?
      payload = { message: message.to_s, kind: kind.to_s }
      @dialog.execute_script("window.ttAutoPaymentStateV140 && window.ttAutoPaymentStateV140(#{JSON.generate(payload)})")
      true
    rescue StandardError => error
      puts "[TT License V1.4.0 state] #{error.class}: #{error.message}"
      false
    end

    def dialog_html
      html = tt_dialog_html_before_commercial_v140

      hook = <<~'JS'
        let ttPaymentPollTimerV140 = null;
        let ttPaymentPollCodeV140 = '';
        let ttPaymentPollCountV140 = 0;

        window.ttStopPaymentPollingV140 = function(message){
          if (ttPaymentPollTimerV140) {
            clearInterval(ttPaymentPollTimerV140);
            ttPaymentPollTimerV140 = null;
          }
          ttPaymentPollCodeV140 = '';
          ttPaymentPollCountV140 = 0;
          if (message) window.ttAutoPaymentStateV140({message:message,kind:'wait'});
        };

        window.ttAutoPaymentStateV140 = function(data){
          const box = document.getElementById('paymentBox');
          if (!box) return;
          let state = document.getElementById('ttAutoPaymentStateV140');
          if (!state) {
            state = document.createElement('div');
            state.id = 'ttAutoPaymentStateV140';
            state.style.marginTop = '10px';
            state.style.padding = '9px 10px';
            state.style.borderRadius = '8px';
            state.style.fontWeight = '700';
            box.appendChild(state);
          }
          const kind = String((data && data.kind) || 'wait');
          state.textContent = String((data && data.message) || '');
          state.style.background = kind === 'ok' ? '#052e2b' : (kind === 'warn' ? '#422006' : '#172554');
          state.style.color = kind === 'ok' ? '#34d399' : (kind === 'warn' ? '#fbbf24' : '#93c5fd');
          state.style.border = '1px solid ' + (kind === 'ok' ? '#10b981' : (kind === 'warn' ? '#a16207' : '#2563eb'));
        };

        window.ttStartPaymentPollingV140 = function(code){
          code = String(code || '').trim().toUpperCase();
          if (!code) return;
          if (ttPaymentPollTimerV140 && ttPaymentPollCodeV140 === code) return;
          window.ttStopPaymentPollingV140();
          ttPaymentPollCodeV140 = code;
          ttPaymentPollCountV140 = 0;
          window.ttAutoPaymentStateV140({message:'Đang tự kiểm tra thanh toán...',kind:'wait'});

          ttPaymentPollTimerV140 = setInterval(function(){
            ttPaymentPollCountV140 += 1;
            if (ttPaymentPollCountV140 > 75) {
              window.ttStopPaymentPollingV140('Tạm dừng tự kiểm tra. Có thể bấm KIỂM TRA THANH TOÁN để kiểm tra lại.');
              return;
            }
            if (window.sketchup && sketchup.auto_check_payment) sketchup.auto_check_payment(code);
          }, 8000);
        };

        const ttRenderPaymentV140 = window.renderPayment;
        window.renderPayment = function(p){
          ttRenderPaymentV140(p);
          if (!p || p.ok !== true || p.already_active === true) return;
          const pay = p.payment || {};
          const status = String(pay.status || 'pending');
          const code = String(pay.request_code || '').trim().toUpperCase();
          if (status === 'paid') {
            window.ttStopPaymentPollingV140();
            window.ttAutoPaymentStateV140({message:'ĐÃ THANH TOÁN · quyền đang được đồng bộ tự động.',kind:'ok'});
          } else if (status === 'pending' && code) {
            window.ttStartPaymentPollingV140(code);
          }
        };
      JS

      marker = "document.addEventListener('DOMContentLoaded',()=>sketchup.ready());"
      html.include?(marker) ? html.sub(marker, hook + "\n" + marker) : html
    end
  end
end
