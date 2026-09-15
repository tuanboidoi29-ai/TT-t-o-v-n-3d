# encoding: UTF-8
module TranTuanNoiThat
  # Layout load order bắt buộc:
  # base -> V0.3.0 -> compat giữ Method gốc -> V0.4.0 -> compat nâng VERSION 0.4.1
  layout_compat = File.join(ROOT, 'layout_stats_v040_compat.rb')
  layout_patch_v040 = File.join(ROOT, 'layout_stats_v040_patch.rb')
  load layout_compat if File.file?(layout_compat)
  load layout_patch_v040 if File.file?(layout_patch_v040)
  load layout_compat if File.file?(layout_compat)

  remove_const(:VERSION) if const_defined?(:VERSION, false)
  VERSION = '1.9.32'.freeze

  module Settings
    extend self
    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(dialog_title: 'TRẦN TUẤN - CÀI ĐẶT CHUNG', preferences_key: 'TranTuanNoiThat.Settings', scrollable: true, resizable: true, width: 540, height: 700, style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(TranTuanNoiThat::ROOT, 'ui', 'settings.html'))
      @dialog.add_action_callback('ready') { |_ctx| sync }
      @dialog.add_action_callback('save') do |_ctx, json|
        data = JSON.parse(json)
        thickness = data['thickness'].to_f
        raise 'Độ dày phải lớn hơn 0.' unless thickness > 0
        TranTuanNoiThat.save_setting('thickness', thickness)
        TranTuanNoiThat.save_setting('auto_update', !!data['auto_update'])
        TranTuanNoiThat.save_setting('update_channel', data['channel'].to_s)
        %w[board box drawer round grain layout_stats].each do |feature|
          TranTuanNoiThat.save_setting("feature_#{feature}", !!data["feature_#{feature}"])
        end
        TranTuanNoiThat.refresh_feature_commands
        notify('Đã lưu và áp dụng bật/tắt tính năng.', 'ok')
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
        channel: TranTuanNoiThat.setting('update_channel', 'stable'),
        feature_board: TranTuanNoiThat.feature_enabled?(:board),
        feature_box: TranTuanNoiThat.feature_enabled?(:box),
        feature_drawer: TranTuanNoiThat.feature_enabled?(:drawer),
        feature_round: TranTuanNoiThat.feature_enabled?(:round),
        feature_grain: TranTuanNoiThat.feature_enabled?(:grain),
        feature_layout_stats: TranTuanNoiThat.feature_enabled?(:layout_stats)
      }
      @dialog.execute_script("window.setSettings(#{JSON.generate(payload)})")
    end

    def notify(message, kind = 'ok')
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("window.notice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind)})")
    end
  end
end
