# encoding: UTF-8
module TranTuanNoiThat
  # Grain V3.4.1 phải nạp sau base/material/alignment để cố định tuyệt đối 1 map = 2440x1220
  # và giải phóng material từng bị bake xuống Face.
  grain_patch_v341 = File.join(ROOT, 'grain_standard_2440_fix.rb')
  load grain_patch_v341 if File.file?(grain_patch_v341)

  # Layout load order bắt buộc:
  # base -> V0.3.0 -> compat -> V0.4.0 -> compat -> V0.5.0 -> V0.6.0 -> V0.7.0.
  layout_compat = File.join(ROOT, 'layout_stats_v040_compat.rb')
  layout_patch_v040 = File.join(ROOT, 'layout_stats_v040_patch.rb')
  layout_patch_v050 = File.join(ROOT, 'layout_stats_v050_stable_preview.rb')
  layout_patch_v060 = File.join(ROOT, 'layout_stats_v060_compact_scope.rb')
  layout_patch_v070 = File.join(ROOT, 'layout_stats_v070_export_split.rb')
  load layout_compat if File.file?(layout_compat)
  load layout_patch_v040 if File.file?(layout_patch_v040)
  load layout_compat if File.file?(layout_compat)
  load layout_patch_v050 if File.file?(layout_patch_v050)
  load layout_patch_v060 if File.file?(layout_patch_v060)
  load layout_patch_v070 if File.file?(layout_patch_v070)

  remove_const(:VERSION) if const_defined?(:VERSION, false)
  VERSION = '1.9.39'.freeze

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
