# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XOAY VÂN VÁN
# Tích hợp từ TT Grain PRO V3.2.0 SAFE GROUP / FLEX MATERIAL.
# Không explode/regroup, không đổi transform; Component chỉ make_unique khi áp dụng.

module TranTuanNoiThat
  module Grain
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '3.2.0'.freeze
    PREF = 'TranTuanNoiThat_Grain'.freeze
    DICT = 'TT_GRAIN'.freeze
    ABF  = 'TT_ABF_GRAIN'.freeze
    FACE_DICT = 'TT_GRAIN_FACE'.freeze
    TAB_KEY = 9
    ENTER_KEY = 13
    ALT_MASK = 8
    CTRL_MASK = defined?(COPY_MODIFIER_MASK) ? COPY_MODIFIER_MASK : 2
    AXES = [X_AXIS, Y_AXIS, Z_AXIS].freeze
    AXIS_NAMES = %w[X Y Z].freeze

    @dialog = nil
    @active_tool = nil

    def pref_number(key, fallback)
      v = Sketchup.read_default(PREF, key, fallback).to_f
      v > 0 ? v : fallback
    end

    def board_length_mm; pref_number('board_length_mm', 2440.0); end
    def board_width_mm; pref_number('board_width_mm', 1220.0); end
    def max_thickness_mm; pref_number('max_thickness_mm', 80.0); end
    def lock_mode
      v = Sketchup.read_default(PREF, 'lock_mode', 'auto').to_s
      %w[auto length width].include?(v) ? v : 'auto'
    end

    def save_settings(l, w, t, mode)
      l = [[l.to_f, 1.0].max, 10000.0].min
      w = [[w.to_f, 1.0].max, 10000.0].min
      t = [[t.to_f, 1.0].max, 500.0].min
      mode = %w[auto length width].include?(mode.to_s) ? mode.to_s : 'auto'
      Sketchup.write_default(PREF, 'board_length_mm', l)
      Sketchup.write_default(PREF, 'board_width_mm', w)
      Sketchup.write_default(PREF, 'max_thickness_mm', t)
      Sketchup.write_default(PREF, 'lock_mode', mode)
      @active_tool.receive_settings(l, w, t, mode) if @active_tool
    end

    def open_settings(tool = nil)
      @active_tool = tool if tool
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - KHỔ VÁN / HƯỚNG VÂN',
        preferences_key: 'TranTuanNoiThat.Grain',
        scrollable: false, resizable: false, width: 440, height: 520,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      l, w, t, m = board_length_mm, board_width_mm, max_thickness_mm, lock_mode
      @dialog.set_html(<<~HTML)
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;padding:20px;background:#151515;color:#f5f5f5;font:14px Arial}h2{margin:0 0 5px;color:#ff8a22}.sub{color:#aaa;margin-bottom:16px}.card{background:#222;border:1px solid #444;border-radius:9px;padding:14px;margin-bottom:12px}label{display:block;margin:10px 0 5px;font-weight:bold}input,select{width:100%;padding:10px;border:1px solid #555;border-radius:7px;background:#111;color:white}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.preset{background:#343434;color:#fff;border:0;padding:9px;border-radius:6px;cursor:pointer}.save{width:100%;padding:12px;border:0;border-radius:8px;background:#f47b20;color:#fff;font-weight:bold;cursor:pointer}.note{font-size:12px;color:#bbb;line-height:1.5}</style></head><body>
        <h2>XOAY VÂN VÁN</h2><div class="sub">Khổ tấm gốc dùng để AUTO nhận hướng vân.</div>
        <div class="card"><label>Chiều dài / hướng vân (mm)</label><input id="l" type="number" value="#{l}"><label>Chiều rộng (mm)</label><input id="w" type="number" value="#{w}"><label>Dày tối đa nhận ván (mm)</label><input id="t" type="number" value="#{t}"><div class="row" style="margin-top:10px"><button class="preset" onclick="p(2440,1220)">2440×1220</button><button class="preset" onclick="p(2800,1220)">2800×1220</button></div></div>
        <div class="card"><label>Luật AUTO</label><select id="m"><option value="auto">Theo khổ + cạnh hợp lý</option><option value="length">Khóa theo chiều DÀI chi tiết</option><option value="width">Khóa theo chiều RỘNG chi tiết</option></select></div>
        <button class="save" onclick="s()">LƯU THÔNG SỐ</button><div class="note" style="margin-top:12px">TAB: mở bảng này · TAB TAB: AUTO ↔ TỰ DO 4 HƯỚNG · Alt+Click: đảo 90° · Ctrl+Click: khóa/mở khóa.</div>
        <script>m.value=#{m.inspect};function p(a,b){l.value=a;w.value=b}function s(){sketchup.save(Number(l.value),Number(w.value),Number(t.value),m.value)}</script></body></html>
      HTML
      @dialog.add_action_callback('save') do |_ctx, ll, ww, tt, mm|
        save_settings(ll, ww, tt, mm)
        @dialog.close
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    end

    def activate
      tool = Tool.new
      @active_tool = tool
      Sketchup.active_model.select_tool(tool)
    end

    class Tool
      def initialize
        @model = Sketchup.active_model
        @view = @model.active_view
        @target = nil
        @target_tr = Geom::Transformation.new
        @face = nil
        @path = nil
        @material = nil
        @analysis = nil
        @free = false
        @free_axis = nil
        @free_sign = 1
        @last_tab = 0.0
        @tab_serial = 0
        @scan = nil
        receive_settings(Grain.board_length_mm, Grain.board_width_mm, Grain.max_thickness_mm, Grain.lock_mode)
      end

      def activate
        Grain.instance_variable_set(:@active_tool, self)
        Sketchup.vcb_label = 'Khổ / Vân'
        update_status
      end

      def deactivate(view); view.invalidate if view; end
      def resume(view); Grain.instance_variable_set(:@active_tool, self); update_status; view.invalidate; end

      def receive_settings(l, w, t, mode)
        @sheet_l, @sheet_w, @max_t = l.to_f, w.to_f, t.to_f
        @lock_mode = %w[auto length width].include?(mode.to_s) ? mode.to_s : 'auto'
        analyze_current
        @view.invalidate if @view
      end

      def onCancel(_reason, view)
        if @scan
          @scan = nil
          view.invalidate
        else
          @model.select_tool(nil)
        end
      end

      def onKeyDown(key, _repeat, flags, view)
        if @scan && key == ENTER_KEY
          apply_scan((flags & ALT_MASK) != 0)
          return
        end
        return unless key == TAB_KEY
        now = Time.now.to_f
        if @last_tab > 0 && now - @last_tab <= 0.36
          @tab_serial += 1
          @last_tab = 0
          @free = !@free
          @free_axis = nil
          analyze_current
          update_status
          view.invalidate
          return
        end
        @last_tab = now
        @tab_serial += 1
        serial = @tab_serial
        UI.start_timer(0.36, false) do
          if @tab_serial == serial && @last_tab > 0
            @last_tab = 0
            Grain.open_settings(self)
          end
        end
      rescue StandardError => e
        puts "[TT Grain key] #{e.class}: #{e.message}"
      end

      def onMouseMove(_flags, x, y, view)
        return if @scan
        pick(view, x, y)
        analyze_current
        choose_free(x, y, view) if @free
        update_status
        view.invalidate
      rescue StandardError => e
        clear_pick
        Sketchup.set_status_text("XOAY VÂN: #{e.message}", SB_PROMPT)
      end

      def onLButtonDown(flags, x, y, view)
        return if @scan
        pick(view, x, y)
        analyze_current
        return UI.beep unless @target && @analysis && @material
        return UI.beep unless textured?(@material)
        if (flags & CTRL_MASK) != 0
          toggle_lock
          return
        end
        if locked?
          UI.beep
          Sketchup.set_status_text('Vân đang KHÓA. Ctrl+Click để mở khóa.', SB_PROMPT)
          return
        end
        a = @analysis.dup
        a = swapped(a) if (flags & ALT_MASK) != 0 && !@free
        if @free && @free_axis
          a = force_axis(a, @free_axis, @free_sign)
        end
        apply_target(@target, @target_tr, @material, a, @free ? 'free' : ((flags & ALT_MASK) != 0 ? 'manual_swap' : 'auto'))
        @analysis = a
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Xoay Vân Ván:\n#{e.message}")
      end

      def onRButtonDown(_flags, _x, _y, view)
        @scan = build_scan
