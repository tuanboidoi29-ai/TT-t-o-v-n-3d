# encoding: UTF-8
module TranTuanNoiThat
  module Settings
    extend self
    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(dialog_title: 'TRẦN TUẤN - CÀI ĐẶT CHUNG', preferences_key: 'TranTuanNoiThat.Settings', scrollable: true, resizable: true, width: 520, height: 570, style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(TranTuanNoiThat::ROOT, 'ui', 'settings.html'))
      @dialog.add_action_callback('ready') { |_ctx| sync }
      @dialog.add_action_callback('save') do |_ctx, json|
        data = JSON.parse(json)
        thickness = data['thickness'].to_f
        raise 'Độ dày phải lớn hơn 0.' unless thickness > 0
        TranTuanNoiThat.save_setting('thickness', thickness)
        TranTuanNoiThat.save_setting('auto_update', !!data['auto_update'])
        TranTuanNoiThat.save_setting('update_channel', data['channel'].to_s)
        notify('Đã lưu cài đặt chung.', 'ok')
      rescue StandardError => error
        notify(error.message, 'error')
      end
      @dialog.add_action_callback('check_update') { |_ctx| TranTuanNoiThat::Updater.check(true) }
      @dialog.add_action_callback('reload') do |_ctx|
        ok = TranTuanNoiThat.reload_runtime
        notify(ok ? 'Đã nạp lại hệ thống.' : 'Nạp lại thất bại.', ok ? 'ok' : 'error')
      end
      @dialog.show
    end

    def sync
      payload = {
        version: TranTuanNoiThat.current_version,
        thickness: TranTuanNoiThat.setting('thickness', 18.0),
        auto_update: TranTuanNoiThat.setting('auto_update', true),
        channel: TranTuanNoiThat.setting('update_channel', 'stable')
      }
      @dialog.execute_script("window.setSettings(#{JSON.generate(payload)})")
    end

    def notify(message, kind = 'ok')
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("window.notice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind)})")
    end
  end
end
