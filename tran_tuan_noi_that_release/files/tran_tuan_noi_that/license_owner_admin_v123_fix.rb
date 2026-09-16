# encoding: UTF-8
# TRẦN TUẤN - OWNER ADMIN V1.2.3 HOTFIX
# Sửa JavaScript của bảng OWNER bị vỡ do onclick lồng dấu nháy.
# Thêm timeout để không bao giờ treo ở "Đang tải..." vô hạn.

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.2.3'.freeze

    unless method_defined?(:tt_owner_admin_html_before_v123)
      alias_method :tt_owner_admin_html_before_v123, :owner_admin_html
    end

    unless method_defined?(:tt_run_admin_async_before_v123)
      alias_method :tt_run_admin_async_before_v123, :run_admin_async
    end

    def owner_admin_html
      html = tt_owner_admin_html_before_v123

      # Sau khi Ruby render heredoc, các chuỗi \' bên trong JavaScript string
      # bị mất escape và biến thành onclick="fn(''+value+'')", làm Chromium
      # dừng parse toàn bộ script. Chuyển sang data-* để không lồng quote nữa.
      replacements = {
        %q{onclick="savePrice(''+esc(p.slug)+'')"} =>
          %q{data-slug="'+esc(p.slug)+'" onclick="savePrice(this.dataset.slug)"},

        %q{onclick="payment(''+esc(x.request_code)+'',true)"} =>
          %q{data-code="'+esc(x.request_code)+'" onclick="payment(this.dataset.code,true)"},

        %q{onclick="payment(''+esc(x.request_code)+'',false)"} =>
          %q{data-code="'+esc(x.request_code)+'" onclick="payment(this.dataset.code,false)"},

        %q{onclick="entitlement(''+esc(m.machine_code)+'',''+esc(p.slug)+'','+(!on)+')"} =>
          %q{data-machine="'+esc(m.machine_code)+'" data-slug="'+esc(p.slug)+'" data-next="'+(!on)+'" onclick="entitlement(this.dataset.machine,this.dataset.slug,this.dataset.next===&quot;true&quot;)"},

        %q{onclick="machineStatus(''+esc(m.machine_code)+'','active')"} =>
          %q{data-machine="'+esc(m.machine_code)+'" data-status="active" onclick="machineStatus(this.dataset.machine,this.dataset.status)"},

        %q{onclick="machineStatus(''+esc(m.machine_code)+'','pending')"} =>
          %q{data-machine="'+esc(m.machine_code)+'" data-status="pending" onclick="machineStatus(this.dataset.machine,this.dataset.status)"},

        %q{onclick="machineStatus(''+esc(m.machine_code)+'','blocked')"} =>
          %q{data-machine="'+esc(m.machine_code)+'" data-status="blocked" onclick="machineStatus(this.dataset.machine,this.dataset.status)"}
      }

      replacements.each { |from, to| html = html.gsub(from, to) }
      html
    end

    def run_admin_async(payload = { 'action' => 'dashboard' })
      return false if @admin_syncing

      @admin_syncing = true
      @admin_pending = :waiting
      request = payload.is_a?(Hash) ? payload.dup : { 'action' => 'dashboard' }
      started_at = Time.now

      Thread.new do
        begin
          @admin_pending = admin_post_raw(request)
        rescue StandardError => error
          @admin_pending = {
            'ok' => false,
            'error' => 'network_error',
            'message' => "#{error.class}: #{error.message}"
          }
        end
      end

      @admin_poll_timer = UI.start_timer(0.20, true) do
        if @admin_pending == :waiting
          if Time.now - started_at >= 15.0
            UI.stop_timer(@admin_poll_timer) if @admin_poll_timer
            @admin_pending = nil
            @admin_syncing = false
            render_owner_admin(
              'ok' => false,
              'error' => 'timeout',
              'message' => 'Máy chủ quản lý không phản hồi sau 15 giây. Hãy bấm LÀM MỚI để thử lại.'
            )
          end
          next
        end

        UI.stop_timer(@admin_poll_timer) if @admin_poll_timer
        result = @admin_pending
        @admin_pending = nil
        @admin_syncing = false
        render_owner_admin(result)
        sync_now(nil) if result.is_a?(Hash) && result['ok'] == true && request['action'].to_s != 'dashboard'
      end
      true
    rescue StandardError => error
      @admin_pending = nil
      @admin_syncing = false
      puts "[TT Owner Admin V1.2.3 async] #{error.class}: #{error.message}"
      render_owner_admin(
        'ok' => false,
        'error' => 'client_error',
        'message' => "#{error.class}: #{error.message}"
      )
      false
    end
  end
end
