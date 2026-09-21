# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module CamChot
    extend self

    VERSION = '1.9.112'.freeze
    DICT = 'TT_CAM_CHOT'.freeze

    DEFAULTS = {
      'cam_diameter' => 15.0,
      'cam_depth'    => 13.5,
      'b_offset'     => 34.0,
      'pin_diameter' => 8.0,
      'pin_depth'    => 12.0,
      'end_offset'   => 37.0,
      'count'        => 2
    }.freeze

    def model
      Sketchup.active_model
    end

    def setting_key(key)
      "cam_chot_#{key}"
    end

    def load_settings
      DEFAULTS.each_with_object({}) do |(key, value), out|
        saved = Sketchup.read_default(TranTuanNoiThat::NAME, setting_key(key), value)
        out[key] = key == 'count' ? saved.to_i : saved.to_f
      end
    end

    def save_settings(data)
      clean = sanitize_settings(data)
      clean.each { |key, value| Sketchup.write_default(TranTuanNoiThat::NAME, setting_key(key), value) }
      clean
    end

    def sanitize_settings(data)
      src = data.is_a?(Hash) ? data : {}
      out = {}
      DEFAULTS.each do |key, default|
        raw = src.key?(key) ? src[key] : default
        out[key] = key == 'count' ? raw.to_i : raw.to_f
      end
      out['cam_diameter'] = 15.0 unless out['cam_diameter'] > 0.0
      out['cam_depth'] = 13.5 unless out['cam_depth'] > 0.0
      out['b_offset'] = 34.0 unless out['b_offset'] > 0.0
      out['pin_diameter'] = 8.0 unless out['pin_diameter'] > 0.0
      out['pin_depth'] = 12.0 unless out['pin_depth'] > 0.0
      out['end_offset'] = 37.0 if out['end_offset'] < 0.0
      out['count'] = 2 if out['count'] < 1
      out['count'] = 20 if out['count'] > 20
      out
    end

    def show
      @tool ||= LinkTool.new
      @tool.reset_for_model(model, load_settings)

      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        model.select_tool(@tool)
        sync_dialog
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TT - LIÊN KẾT CAM - CHỐT',
        preferences_key: 'TranTuanNoiThat.CamChot.112',
        scrollable: true,
        resizable: true,
        width: 610,
        height: 690,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)

      @dialog.add_action_callback('ready') do |_ctx|
        sync_dialog
      end

      @dialog.add_action_callback('apply_settings') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          @tool.settings = sanitize_settings(data)
          @tool.invalidate
          sync_dialog
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('save_settings') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          @tool.settings = save_settings(data)
          @tool.invalidate
          sync_dialog
          notify('Đã lưu thông số CAM - CHỐT làm mặc định.', 'ok')
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('use_selection') do |_ctx|
        @tool.assign_from_selection
        sync_dialog
      end

      @dialog.add_action_callback('flip') do |_ctx|
        @tool.flip_cam_face
        sync_dialog
      end

      @dialog.add_action_callback('create') do |_ctx, json|
        begin
          data = JSON.parse(json.to_s)
          @tool.settings = sanitize_settings(data)
          @tool.create_link
          sync_dialog
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('abf_check') do |_ctx|
        @tool.abf_check
      end

      @dialog.add_action_callback('reset') do |_ctx|
        @tool.reset_picks
        sync_dialog
      end

      @dialog.set_on_closed do
        @dialog = nil
        begin
          model.select_tool(nil)
        rescue StandardError
        end
      end

      @dialog.show
      model.select_tool(@tool)
    rescue StandardError => error
      UI.messagebox("Không mở được Liên kết CAM - CHỐT:\n#{error.message}")
    end

    def sync_dialog
      return unless @dialog && @dialog.visible?
      state = @tool ? @tool.state_payload : {}
      @dialog.execute_script("TT.setState(#{JSON.generate(state)});")
    rescue StandardError => error
      warn "[TT CamChot sync] #{error.class}: #{error.message}"
    end

    def notify(message, kind = 'ok')
      if @dialog && @dialog.visible?
        @dialog.execute_script("TT.notice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind.to_s)});")
      else
        UI.messagebox(message.to_s)
      end
    rescue StandardError
      UI.messagebox(message.to_s) rescue nil
    end

    def dialog_html
      <<~HTML
        <!doctype html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            *{box-sizing:border-box}
            body{font-family:Arial,sans-serif;margin:0;background:#f2f4f7;color:#222}
            .top{padding:14px;background:#fff;border-bottom:1px solid #ddd;position:sticky;top:0;z-index:5}
            h2{margin:0 0 7px;font-size:18px}
            .state{font-size:13px;line-height:1.55;background:#eef5ff;border:1px solid #cbdfff;border-radius:7px;padding:9px}
            .content{padding:14px}
            .card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:12px}
            .grid{display:grid;grid-template-columns:1fr 110px 42px;gap:7px;align-items:center}
            .grid label{font-size:13px;font-weight:bold}
            input,select{width:100%;padding:8px;border:1px solid #bbb;border-radius:6px}
            .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
            button{border:0;border-radius:6px;padding:9px 12px;font-weight:bold;cursor:pointer;background:#2d6cdf;color:#fff}
            button.orange{background:#d86e16} button.green{background:#178a4b} button.gray{background:#66707e}
            button.preset{background:#8a5a12}
            .hint{font-size:12px;color:#626a74;line-height:1.5}
            .legend{display:flex;gap:14px;font-size:12px;margin-top:8px}
            .dot{display:inline-block;width:11px;height:11px;border-radius:50%;vertical-align:-1px;margin-right:4px}
            .cam{background:#f07a24}.pin{background:#1677d2}
            .notice{display:none;padding:9px;border-radius:6px;margin-top:10px;font-size:13px;white-space:pre-wrap}
            .notice.ok{display:block;background:#e7f6ee;color:#175f38}
            .notice.warn{display:block;background:#fff3d8;color:#805600}
            .notice.error{display:block;background:#fdeaea;color:#8d2323}
          </style>
        </head>
        <body>
          <div class="top">
            <h2>LIÊN KẾT CAM - CHỐT</h2>
            <div id="state" class="state">Click trực tiếp tấm CAM. Tool sẽ hiện các cạnh giao với tấm khác; click cạnh giao để tạo CAM.</div>
            <div class="legend">
              <span><span class="dot cam"></span>CAM</span>
              <span><span class="dot pin"></span>CHỐT</span>
            </div>
          </div>
          <div class="content">
            <div class="card">
              <div class="grid">
                <label>CAM Ø</label><input id="cam_diameter" type="number" value="15" step="0.1"><span>mm</span>
                <label>Sâu CAM</label><input id="cam_depth" type="number" value="13.5" step="0.1"><span>mm</span>
                <label>B - tâm CAM cách mép</label><input id="b_offset" type="number" value="34" step="1"><span>mm</span>
                <label>CHỐT Ø</label><input id="pin_diameter" type="number" value="8" step="0.1"><span>mm</span>
                <label>Sâu CHỐT</label><input id="pin_depth" type="number" value="12" step="0.1"><span>mm</span>
                <label>Cách hai đầu</label><input id="end_offset" type="number" value="37" step="1"><span>mm</span>
                <label>Số bộ</label><input id="count" type="number" value="2" min="1" max="20" step="1"><span>bộ</span>
              </div>
              <div class="row">
                <button class="preset" onclick="presetB(24)">B24</button>
                <button class="preset" onclick="presetB(34)">B34</button>
                <button onclick="applySettings()">Áp dụng xem trước</button>
                <button class="gray" onclick="saveSettings()">Lưu mặc định</button>
              </div>
            </div>

            <div class="card">
              <div class="row">
                <button onclick="sketchup.use_selection()">Dùng 2 tấm đang chọn</button>
                <button class="gray" onclick="sketchup.flip()">Đảo mặt CAM (TAB)</button>
                <button class="gray" onclick="sketchup.reset()">Chọn lại</button>
                <button class="orange" onclick="sketchup.abf_check()">Kiểm tra ABF CAM</button>
              </div>
              <div class="row">
                <button class="green" onclick="createLink()">TẠO LIÊN KẾT (ENTER)</button>
              </div>
              <div class="hint">
                Cách dùng: click tấm nhận CAM → tool tự hiện ngay preview ở cạnh giao gần nhất và tô tất cả cạnh giao trên View → rê sang cạnh khác để đổi preview → click cạnh để tạo CAM–CHỐT. TAB đảo mặt CAM. Liên kết được ghi trong chính tấm và theo tấm khi di chuyển/copy.
              </div>
            </div>

            <div id="notice" class="notice"></div>
          </div>
          <script>
            const TT={
              settings:{},
              setState(s){
                this.settings=s.settings||this.settings||{};
                for(const k of ['cam_diameter','cam_depth','b_offset','pin_diameter','pin_depth','end_offset','count']){
                  if(this.settings[k]!==undefined) document.getElementById(k).value=this.settings[k];
                }
                const cam=s.cam_name||'Chưa chọn';
                const pin=s.pin_name||'Chưa chọn';
                const joint=s.joint||'';
                document.getElementById('state').innerHTML=
                  '<b>Tấm CAM:</b> '+esc(cam)+'<br><b>Tấm CHỐT:</b> '+esc(pin)+
                  '<br><b>Mặt CAM:</b> '+(s.flip_cam?'Mặt đối diện':'Mặt mặc định')+
                  (joint?'<br><b>Preview:</b> '+esc(joint):'');
              },
              notice(msg,kind){
                const e=document.getElementById('notice');
                e.className='notice '+(kind||'ok'); e.textContent=msg||'';
              }
            };
            function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}
            function values(){
              const o={};
              for(const k of ['cam_diameter','cam_depth','b_offset','pin_diameter','pin_depth','end_offset','count']){
                o[k]=Number(document.getElementById(k).value);
              }
              return o;
            }
            function applySettings(){sketchup.apply_settings(JSON.stringify(values()));}
            function saveSettings(){sketchup.save_settings(JSON.stringify(values()));}
            function createLink(){sketchup.create(JSON.stringify(values()));}
            function presetB(v){document.getElementById('b_offset').value=v;applySettings();}
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body>
        </html>
      HTML
    end

    class LinkTool
      attr_accessor :settings

      def initialize
        @model = nil
        @cam = nil
        @pin = nil
        @hover = nil
        @contacts = []
        @hover_contact = nil
        @flip_cam = false
        @settings = DEFAULTS.dup
      end

      def reset_for_model(model, settings)
        if @model != model
          @cam = nil
          @pin = nil
          @hover = nil
          @contacts = []
          @hover_contact = nil
          @flip_cam = false
        end
        @model = model
        @settings = CamChot.sanitize_settings(settings)
        rebuild_contacts if @cam
        invalidate
      end

      def activate
        Sketchup.status_text = 'TT CAM-CHỐT: click tấm CAM → rê vào cạnh giao sáng → click cạnh để tạo · TAB đảo mặt CAM.'
        invalidate
      end

      def deactivate(view)
        view.invalidate if view
      end

      def onCancel(_reason, view)
        reset_picks
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        if @cam && @pin.nil?
          contact = pick_contact(view, x, y)
          picked = contact ? contact[:entity] : pick_container(view, x, y)
          previous_contact = @hover_contact
          @hover_contact = contact if contact
          changed = previous_contact != @hover_contact || picked != @hover
          @hover = picked
          if contact
            Sketchup.status_text = "Cạnh giao với #{display_name(contact[:entity])} · preview đang hiển thị · click để tạo CAM-CHỐT."
          elsif @hover_contact
            Sketchup.status_text = "Preview giữ ở cạnh giao hiện tại · rê lên cạnh xanh khác để đổi · click cạnh để tạo."
          else
            Sketchup.status_text = "Đã chọn tấm CAM · #{@contacts.length} cạnh giao hợp lệ."
          end
          view.invalidate if changed
          return
        end

        picked = pick_container(view, x, y)
        if picked != @hover
          @hover = picked
          view.invalidate
        end
      end

      def onLButtonDown(_flags, x, y, view)
        if @cam.nil?
          entity = pick_container(view, x, y)
          unless entity
            UI.beep
            Sketchup.status_text = 'Không bắt được tấm CAM.'
            return
          end
          @cam = entity
          @pin = nil
          @hover_contact = nil
          rebuild_contacts
          if @contacts.empty?
            CamChot.notify('Đã chọn tấm CAM nhưng chưa tìm thấy tấm nào giao/tiếp giáp vuông góc trong cùng ngữ cảnh.', 'warn')
          else
            @hover_contact = @contacts.min_by { |contact| contact[:gap].to_f }
            Sketchup.status_text = "Đã chọn tấm CAM · #{@contacts.length} cạnh giao · PREVIEW đang hiện ở cạnh gần nhất; rê sang cạnh khác để đổi."
          end
          CamChot.sync_dialog
          invalidate
          return
        end

        contact = pick_contact(view, x, y)
        unless contact
          entity = pick_container(view, x, y)
          contact = contact_for_entity(entity) if entity && entity != @cam
        end

        unless contact
          UI.beep
          Sketchup.status_text = 'Hãy click đúng cạnh giao đang được highlight.'
          return
        end

        @pin = contact[:entity]
        @hover_contact = contact
        CamChot.sync_dialog
        invalidate
        create_link
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when 9
          flip_cam_face
        when 13
          create_link
        when 27
          reset_picks
        end
        view.invalidate
      end

      def getMenu(menu)
        menu.add_item('Đảo mặt CAM (TAB)') { flip_cam_face }
        menu.add_item('Tạo liên kết (ENTER)') { create_link }
        menu.add_item('Chọn lại') { reset_picks }
      end

      def assign_from_selection
        objects = @model.selection.to_a.select do |entity|
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid?
        end
        objects = objects.select { |entity| active_entities.include?(entity) }

        if objects.empty?
          CamChot.notify('Hãy chọn ít nhất 1 tấm trong cùng ngữ cảnh hiện tại.', 'warn')
          return false
        end

        @cam = objects[0]
        @pin = objects[1] if objects.length > 1
        rebuild_contacts

        if @pin
          candidate = contact_for_entity(@pin)
          unless candidate
            @pin = nil
            CamChot.notify('Tấm thứ hai không tiếp giáp vuông góc với tấm CAM. Tool đã giữ tấm CAM và hiện các cạnh giao hợp lệ.', 'warn')
          end
        end

        CamChot.sync_dialog
        invalidate
        true
      end

      def flip_cam_face
        @flip_cam = !@flip_cam
        rebuild_contacts if @cam
        CamChot.sync_dialog
        invalidate
        true
      end

      def reset_picks
        @cam = nil
        @pin = nil
        @hover = nil
        @contacts = []
        @hover_contact = nil
        CamChot.sync_dialog
        invalidate
        true
      end

      def state_payload
        joint = ''
        if @cam && @pin
          begin
            layout = compute_layout(@cam, @pin)
            joint = "#{layout[:cam_points].length} bộ · B#{CamChot.format_number(@settings['b_offset'])}"
          rescue StandardError => error
            joint = error.message
          end
        elsif @cam
          joint = "#{@contacts.length} cạnh giao hợp lệ · click cạnh sáng để tạo"
        end
        {
          cam_name: @cam ? display_name(@cam) : nil,
          pin_name: @pin ? display_name(@pin) : nil,
          flip_cam: @flip_cam,
          joint: joint,
          settings: @settings
        }
      end

      def invalidate
        @model.active_view.invalidate if @model && @model.active_view
      rescue StandardError
      end

      def draw(view)
        draw_box(view, @hover, Sketchup::Color.new(120, 120, 120), 1) if @hover && @hover != @cam
        draw_box(view, @cam, Sketchup::Color.new(240, 122, 36), 3) if @cam
        draw_box(view, @pin, Sketchup::Color.new(22, 119, 210), 3) if @pin

        if @cam && @pin.nil?
          @contacts.each do |contact|
            hovered = contact.equal?(@hover_contact)
            view.line_width = hovered ? 7 : 4
            view.drawing_color = hovered ? Sketchup::Color.new(255, 210, 40) : Sketchup::Color.new(50, 210, 110)
            view.draw(GL_LINES, contact[:line])
            midpoint = Geom::Point3d.linear_combination(0.5, contact[:line][0], 0.5, contact[:line][1])
            view.draw_points(midpoint, hovered ? 10 : 7, 2, view.drawing_color)
          end

          if @hover_contact
            begin
              layout = compute_layout(@cam, @hover_contact[:entity])
              draw_layout_preview(view, layout)
            rescue StandardError
            end
          end
          return
        end

        return unless @cam && @pin
        layout = compute_layout(@cam, @pin)
        draw_layout_preview(view, layout)
      rescue StandardError => error
        Sketchup.status_text = "TT CAM-CHỐT: #{error.message}"
      end

      def draw_layout_preview(view, layout)
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(240, 122, 36)
        layout[:cam_points].each do |point|
          view.draw(GL_LINE_LOOP, circle_points(point, layout[:cam_face_normal], mm(@settings['cam_diameter']) / 2.0, 24))
          view.draw_points(point, 8, 2, Sketchup::Color.new(240, 122, 36))
        end

        view.drawing_color = Sketchup::Color.new(22, 119, 210)
        layout[:pin_points].each do |point|
          view.draw(GL_LINE_LOOP, circle_points(point, layout[:pin_face_normal], mm(@settings['pin_diameter']) / 2.0, 24))
          view.draw_points(point, 8, 2, Sketchup::Color.new(22, 119, 210))
        end

        view.line_width = 1
        layout[:cam_points].zip(layout[:pin_points]).each do |cam_point, pin_point|
          view.drawing_color = Sketchup::Color.new(245, 165, 80)
          view.draw(GL_LINES, [cam_point, pin_point])
        end
      end

      def create_link
        unless @cam && @pin
          CamChot.notify('Chưa chọn đủ tấm CAM và tấm CHỐT.', 'warn')
          return false
        end

        layout = compute_layout(@cam, @pin)
        @model.start_operation('TT - Liên kết CAM CHỐT', true)
        started = true

        make_unique_if_needed(@cam)
        make_unique_if_needed(@pin)
        layout = compute_layout(@cam, @pin)

        # ABF chuẩn: tất cả đường gia công phải nằm trong _ABF_cuttingLines
        # với tag ABF_cuttingLines và attribute ABF/is-cutting-lines=true.
        abf_layer = layer('ABF_cuttingLines')
        cam_stats_layer = layer('ABF_chotcamNK')
        link_id = "TTCC-#{Time.now.to_i}-#{rand(100000)}"

        ensure_abf_board_identity(@cam, layout[:cam_points].first, layout[:cam_face_normal])
        ensure_abf_board_identity(@pin, layout[:pin_points].first, layout[:pin_face_normal])

        layout[:cam_points].each_with_index do |point, index|
          add_marker(
            @cam,
            point,
            layout[:cam_face_normal],
            layout[:cam_inward],
            @settings['cam_diameter'],
            @settings['cam_depth'],
            abf_layer,
            'cam',
            link_id,
            index + 1
          )
          add_abf_cam_stat_marker(
            @cam,
            point,
            layout[:cam_face_normal],
            @settings['cam_diameter'],
            @settings['cam_depth'],
            cam_stats_layer,
            link_id,
            index + 1
          )
        end

        layout[:pin_points].each_with_index do |point, index|
          add_marker(
            @pin,
            point,
            layout[:pin_face_normal],
            layout[:pin_inward],
            @settings['pin_diameter'],
            @settings['pin_depth'],
            abf_layer,
            'chot',
            link_id,
            index + 1
          )
        end

        @model.commit_operation
        started = false

        count = layout[:cam_points].length
        CamChot.notify("Đã tạo #{count} bộ CAM - CHỐT theo cạnh giao. Liên kết nằm trong chính tấm nên đi theo ván khi di chuyển/copy; ABF cuttingLines + CAM marker được giữ. Ctrl+Z hoàn tác một lần.", 'ok')
        reset_picks
        true
      rescue StandardError => error
        @model.abort_operation if started rescue nil
        CamChot.notify("Không tạo được CAM - CHỐT:\n#{error.message}", 'error')
        false
      end

      def compute_layout(cam_entity = @cam, pin_entity = @pin)
        raise 'Tấm CAM không còn hợp lệ.' unless valid_container?(cam_entity)
        raise 'Tấm CHỐT không còn hợp lệ.' unless valid_container?(pin_entity)

        cam = board_frame(cam_entity)
        pin = board_frame(pin_entity)

        n_cam = cam[:normal]
        n_pin_raw = pin[:normal]
        dot = n_cam.dot(n_pin_raw).abs
        raise 'Hai tấm phải vuông góc với nhau.' if dot > 0.25

        direction = n_cam.cross(n_pin_raw)
        raise 'Không xác định được hướng giao hai tấm.' if direction.length < 0.001
        direction.normalize!

        n_pin = direction.cross(n_cam)
        n_pin.normalize!
        n_pin.reverse! if n_pin.dot(n_pin_raw) < 0.0

        cam_d = projection(cam[:corners], direction)
        cam_n = projection(cam[:corners], n_cam)
        cam_p = projection(cam[:corners], n_pin)
        pin_d = projection(pin[:corners], direction)
        pin_n = projection(pin[:corners], n_cam)
        pin_p = projection(pin[:corners], n_pin)

        overlap_min = [cam_d[0], pin_d[0]].max
        overlap_max = [cam_d[1], pin_d[1]].min
        raise 'Hai tấm không có vùng giao đủ để đặt liên kết.' unless overlap_max > overlap_min

        cam_center_p = scalar(cam[:center], n_pin)
        pin_surface_candidates = [pin_p[0], pin_p[1]]
        pin_surface = pin_surface_candidates.min_by { |value| (value - cam_center_p).abs }

        cam_edge_candidates = [cam_p[0], cam_p[1]]
        cam_edge = cam_edge_candidates.min_by { |value| (value - pin_surface).abs }
        contact_gap = interval_gap(cam_p, pin_p)
        raise 'Hai tấm chưa giao/tiếp giáp đủ gần.' if contact_gap > mm(5.0)
        inward_sign = (cam_edge - cam_p[0]).abs < (cam_edge - cam_p[1]).abs ? 1.0 : -1.0
        cam_housing_p = cam_edge + inward_sign * mm(@settings['b_offset'])

        if cam_housing_p <= cam_p[0] || cam_housing_p >= cam_p[1]
          raise "B#{CamChot.format_number(@settings['b_offset'])} vượt ra ngoài chiều rộng tấm CAM."
        end

        cam_face_s = @flip_cam ? cam_n[0] : cam_n[1]
        cam_face_sign = @flip_cam ? -1.0 : 1.0
        cam_mid_s = (cam_n[0] + cam_n[1]) / 2.0

        pin_face_sign = (pin_surface - pin_p[1]).abs < (pin_surface - pin_p[0]).abs ? 1.0 : -1.0
        pin_face_normal = scaled(n_pin, pin_face_sign)
        pin_inward = scaled(pin_face_normal, -1.0)
        cam_face_normal = scaled(n_cam, cam_face_sign)
        cam_inward = scaled(cam_face_normal, -1.0)

        positions = connector_positions(overlap_min, overlap_max, mm(@settings['end_offset']), @settings['count'].to_i)
        raise 'Không còn vị trí đặt CAM - CHỐT sau khi trừ khoảng cách hai đầu.' if positions.empty?

        cam_points = positions.map { |t| point_from_basis(direction, t, n_cam, cam_face_s, n_pin, cam_housing_p) }
        pin_points = positions.map { |t| point_from_basis(direction, t, n_cam, cam_mid_s, n_pin, pin_surface) }

        {
          cam_points: cam_points,
          pin_points: pin_points,
          cam_face_normal: cam_face_normal,
          cam_inward: cam_inward,
          pin_face_normal: pin_face_normal,
          pin_inward: pin_inward
        }
      end

      def rebuild_contacts
        @contacts = []
        @hover_contact = nil
        return @contacts unless valid_container?(@cam)

        active_entities.each do |entity|
          next unless valid_container?(entity)
          next if entity == @cam
          candidate = build_contact_candidate(@cam, entity)
          @contacts << candidate if candidate
        end
        @contacts
      rescue StandardError => error
        warn "[TT CamChot contacts] #{error.class}: #{error.message}"
        @contacts = []
      end

      def build_contact_candidate(cam_entity, pin_entity)
        cam = board_frame(cam_entity)
        pin = board_frame(pin_entity)

        n_cam = cam[:normal]
        n_pin_raw = pin[:normal]
        return nil if n_cam.dot(n_pin_raw).abs > 0.25

        direction = n_cam.cross(n_pin_raw)
        return nil if direction.length < 0.001
        direction.normalize!

        n_pin = direction.cross(n_cam)
        n_pin.normalize!
        n_pin.reverse! if n_pin.dot(n_pin_raw) < 0.0

        cam_d = projection(cam[:corners], direction)
        pin_d = projection(pin[:corners], direction)
        overlap_min = [cam_d[0], pin_d[0]].max
        overlap_max = [cam_d[1], pin_d[1]].min
        return nil if overlap_max - overlap_min < mm(10.0)

        cam_n = projection(cam[:corners], n_cam)
        cam_p = projection(cam[:corners], n_pin)
        pin_n = projection(pin[:corners], n_cam)
        pin_p = projection(pin[:corners], n_pin)

        # Nhận cả trường hợp chạm mép và trường hợp hai tấm giao/ăn vào nhau.
        gap = interval_gap(cam_p, pin_p)
        normal_gap = interval_gap(cam_n, pin_n)
        return nil if gap > mm(5.0)
        return nil if normal_gap > mm(5.0)

        cam_center_p = scalar(cam[:center], n_pin)
        pin_surface = [pin_p[0], pin_p[1]].min_by { |value| (value - cam_center_p).abs }
        cam_edge = [cam_p[0], cam_p[1]].min_by { |value| (value - pin_surface).abs }

        cam_mid_s = (cam_n[0] + cam_n[1]) / 2.0
        line = [
          point_from_basis(direction, overlap_min, n_cam, cam_mid_s, n_pin, pin_surface),
          point_from_basis(direction, overlap_max, n_cam, cam_mid_s, n_pin, pin_surface)
        ]

        # Chỉ nhận contact nếu bộ thông số hiện tại thật sự đặt được CAM.
        compute_layout(cam_entity, pin_entity)

        {
          entity: pin_entity,
          line: line,
          gap: gap
        }
      rescue StandardError
        nil
      end

      def contact_for_entity(entity)
        return nil unless entity
        @contacts.find { |contact| contact[:entity] == entity }
      end

      def pick_contact(view, x, y)
        return nil if @contacts.nil? || @contacts.empty?
        best = nil
        best_distance = 1.0e9

        @contacts.each do |contact|
          a = view.screen_coords(contact[:line][0])
          b = view.screen_coords(contact[:line][1])
          distance = screen_distance_to_segment(x.to_f, y.to_f, a.x.to_f, a.y.to_f, b.x.to_f, b.y.to_f)
          if distance < best_distance
            best_distance = distance
            best = contact
          end
        end

        best_distance <= 14.0 ? best : nil
      rescue StandardError
        nil
      end

      def interval_gap(a, b)
        a0, a1 = a
        b0, b1 = b
        return b0 - a1 if a1 < b0
        return a0 - b1 if b1 < a0
        0.0
      end

      def screen_distance_to_segment(px, py, ax, ay, bx, by)
        dx = bx - ax
        dy = by - ay
        length2 = dx * dx + dy * dy
        return Math.sqrt((px - ax) ** 2 + (py - ay) ** 2) if length2 <= 0.000001

        t = ((px - ax) * dx + (py - ay) * dy) / length2
        t = 0.0 if t < 0.0
        t = 1.0 if t > 1.0
        cx = ax + t * dx
        cy = ay + t * dy
        Math.sqrt((px - cx) ** 2 + (py - cy) ** 2)
      end

      def connector_positions(min_value, max_value, end_offset, count)
        length = max_value - min_value
        return [] if length <= 0.0
        n = [count.to_i, 1].max

        if n == 1
          return [(min_value + max_value) / 2.0]
        end

        start_value = min_value + end_offset
        end_value = max_value - end_offset
        if end_value <= start_value
          return [(min_value + max_value) / 2.0]
        end

        step = (end_value - start_value) / (n - 1).to_f
        Array.new(n) { |index| start_value + step * index }
      end

      def next_abf_board_index
        max_index = 0
        stack = [@model.entities]
        seen = {}
        until stack.empty?
          entities = stack.pop
          entities.each do |entity|
            next unless valid_container?(entity)
            key = entity.respond_to?(:persistent_id) ? entity.persistent_id.to_i : entity.entityID.to_i
            next if seen[key]
            seen[key] = true
            value = entity.get_attribute('ABF', 'board-index', 0).to_i
            max_index = value if value > max_index
            definition = entity.definition rescue nil
            stack << definition.entities if definition
          end
        end
        max_index + 1
      rescue StandardError
        Time.now.to_i % 1_000_000
      end

      def ensure_abf_board_identity(entity, near_world, face_normal_world)
        return false unless valid_container?(entity)

        unless entity.get_attribute('ABF', 'is-board', false) == true
          entity.set_attribute('ABF', 'is-board', true)
        end
        if entity.get_attribute('ABF', 'board-index', nil).nil?
          entity.set_attribute('ABF', 'board-index', next_abf_board_index)
        end
        entity.set_attribute('ABF', 'label-rotation', 0) if entity.get_attribute('ABF', 'label-rotation', nil).nil?

        definition = entity.definition
        definition.set_attribute('ABF', 'is-board', true)
        definition.set_attribute('ABF', 'has-cam-link', true)

        mark_labeled_face(entity, near_world, face_normal_world)
        true
      rescue StandardError => error
        warn "[TT CamChot ABF board] #{error.class}: #{error.message}"
        false
      end

      def mark_labeled_face(entity, near_world, normal_world)
        definition = entity.definition
        tr = full_transform(entity)
        inverse = tr.inverse
        target_local = near_world.transform(inverse)
        normal_local = normal_world.transform(inverse)
        normal_local.normalize! if normal_local.length > 0.000001

        faces = definition.entities.grep(Sketchup::Face)
        return false if faces.empty?

        # Ưu tiên mặt lớn có normal cùng trục với mặt CAM/CHỐT và gần điểm gia công.
        face = faces.min_by do |candidate|
          align = 1.0 - candidate.normal.dot(normal_local).abs
          center = candidate.bounds.center
          distance = center.distance(target_local)
          (align * 100000.0) + distance
        end
        face.set_attribute('ABF', 'is-labeled-face', true) if face
        !!face
      rescue StandardError
        false
      end

      def abf_cam_stats_root(entity, cam_layer)
        root = entity.definition.entities
        group = root.grep(Sketchup::Group).find do |candidate|
          candidate.valid? &&
            (candidate.name.to_s == 'CHOT_CAM' ||
             candidate.get_attribute('ABF', 'is-cam-set', false) == true)
        end

        unless group
          group = root.add_group
          group.name = 'CHOT_CAM'
        end

        group.layer = cam_layer if cam_layer
        group.set_attribute('ABF', 'is-cam-set', true)
        group.set_attribute('ABF', 'hardware-type', 'cam')
        group.set_attribute('ABF_chotcamNK', 'enabled', true)
        group.set_attribute(DICT, 'role', 'cam_set')
        group
      end

      def add_abf_cam_stat_marker(entity, center_world, normal_world, diameter_mm, depth_mm, cam_layer, link_id, index)
        root = abf_cam_stats_root(entity, cam_layer)
        board_world = full_transform(entity)
        marker_world = board_world * root.transformation
        inverse = marker_world.inverse

        marker = root.entities.add_group
        marker.name = "CHOT_CAM_#{index}"
        marker.layer = cam_layer if cam_layer

        center_local = center_world.transform(inverse)
        normal_local = normal_world.transform(inverse)
        normal_local.normalize! if normal_local.length > 0.000001

        # CAM chỉ là BIÊN DẠNG gia công: vòng tròn Edge/Curve, KHÔNG Face, KHÔNG PushPull.
        # Đặt đúng trên mặt CAM để khi ABF trải/nesting chỉ còn đường biên khoan.
        circle = marker.entities.add_circle(
          center_local,
          normal_local,
          diameter_mm.to_f.mm / 2.0,
          32
        )
        Array(circle).each do |edge|
          edge.layer = cam_layer if cam_layer
          edge.set_attribute('ABF', 'is-cam-outline', true)
          edge.set_attribute('ABF', 'hardware-type', 'cam')
          edge.set_attribute('ABF_chotcamNK', 'type', 'cam-outline')
          edge.set_attribute('ABF_chotcamNK', 'diameter_mm', diameter_mm.to_f)
          edge.set_attribute('ABF_chotcamNK', 'depth_mm', depth_mm.to_f)
          edge.set_attribute('ABF_chotcamNK', 'link_id', link_id.to_s)
        end

        marker.set_attribute('ABF', 'is-cam', true)
        marker.set_attribute('ABF', 'is-chot-cam', true)
        marker.set_attribute('ABF', 'hardware-type', 'cam')
        marker.set_attribute('ABF', 'diameter-mm', diameter_mm.to_f)
        marker.set_attribute('ABF', 'depth-mm', depth_mm.to_f)
        marker.set_attribute('ABF', 'link-id', link_id.to_s)
        marker.set_attribute('ABF', 'index', index.to_i)

        marker.set_attribute('ABF_chotcamNK', 'type', 'cam')
        marker.set_attribute('ABF_chotcamNK', 'diameter_mm', diameter_mm.to_f)
        marker.set_attribute('ABF_chotcamNK', 'depth_mm', depth_mm.to_f)
        marker.set_attribute('ABF_chotcamNK', 'count', 1)
        marker.set_attribute('ABF_chotcamNK', 'link_id', link_id.to_s)

        # Dynamic Attributes để các bản ABF đọc thuộc tính động vẫn thấy CAM.
        marker.set_attribute('dynamic_attributes', '_name', 'CHOT_CAM')
        marker.set_attribute('dynamic_attributes', 'abf_chotcamnk', 1)
        marker.set_attribute('dynamic_attributes', 'cam_diameter_mm', diameter_mm.to_f)
        marker.set_attribute('dynamic_attributes', 'cam_count', 1)

        # Tóm tắt trên tấm và definition.
        count = entity.get_attribute('ABF_chotcamNK', 'count', 0).to_i + 1
        [entity, entity.definition].each do |target|
          target.set_attribute('ABF_chotcamNK', 'enabled', true)
          target.set_attribute('ABF_chotcamNK', 'count', count)
          target.set_attribute('ABF_chotcamNK', 'cam_diameter_mm', diameter_mm.to_f)
          target.set_attribute('ABF', 'has-cam', true)
          target.set_attribute('ABF', 'cam-count', count)
          target.set_attribute('ABF', 'cam-diameter-mm', diameter_mm.to_f)
          target.set_attribute('dynamic_attributes', 'abf_chotcamnk', count)
          target.set_attribute('dynamic_attributes', 'cam_count', count)
          target.set_attribute('dynamic_attributes', 'cam_diameter_mm', diameter_mm.to_f)
        end

        marker
      end

      def abf_check
        boards = [@cam, @pin].compact
        if boards.empty?
          CamChot.notify('Chưa chọn tấm để kiểm tra ABF.', 'warn')
          return false
        end

        lines = boards.map do |entity|
          definition = entity.definition
          cutting = definition.entities.grep(Sketchup::Group).count do |group|
            group.name.to_s == '_ABF_cuttingLines' &&
              group.get_attribute('ABF', 'is-cutting-lines', false) == true
          end
          cams = definition.entities.grep(Sketchup::Group).sum do |group|
            if group.name.to_s == 'CHOT_CAM' || group.get_attribute('ABF', 'is-cam-set', false) == true
              group.entities.grep(Sketchup::Group).count do |marker_group|
                marker_group.get_attribute('ABF', 'is-cam', false) == true ||
                  marker_group.layer.name.to_s == 'ABF_chotcamNK'
              end
            else
              0
            end
          end
          labeled_faces = definition.entities.grep(Sketchup::Face).count do |face|
            face.get_attribute('ABF', 'is-labeled-face', false) == true
          end

          "#{display_name(entity)}: is-board=#{entity.get_attribute('ABF','is-board',false)} · board-index=#{entity.get_attribute('ABF','board-index','?')} · labeled-face=#{labeled_faces} · cuttingLines=#{cutting} · CAM=#{cams} · attrCAM=#{entity.get_attribute('ABF_chotcamNK','count',0)}"
        end

        CamChot.notify(lines.join("\n"), 'ok')
        true
      rescue StandardError => error
        CamChot.notify("Kiểm tra ABF lỗi: #{error.message}", 'error')
        false
      end

      def abf_cutting_group(entity, abf_layer)
        root = entity.definition.entities
        group = root.grep(Sketchup::Group).find do |candidate|
          next false unless candidate.valid?
          candidate.name.to_s == '_ABF_cuttingLines' ||
            candidate.get_attribute('ABF', 'is-cutting-lines', false) == true
        end

        unless group
          group = root.add_group
          group.name = '_ABF_cuttingLines'
        end

        group.layer = abf_layer if abf_layer
        group.set_attribute('ABF', 'is-cutting-lines', true)
        group.set_attribute(DICT, 'abf_bridge', true)
        group
      end

      def add_marker(entity, center_world, normal_world, inward_world, diameter_mm, depth_mm, tag, kind, link_id, index)
        abf_group = abf_cutting_group(entity, tag)

        # Chuyển world -> local của _ABF_cuttingLines, kể cả khi group ABF có transform.
        board_world = full_transform(entity)
        group_world = board_world * abf_group.transformation
        inverse = group_world.inverse
        entities = abf_group.entities

        points_world = circle_points(center_world, normal_world, mm(diameter_mm) / 2.0, 32)
        points_local = points_world.map { |point| point.transform(inverse) }

        # Vòng khoan thật: ABF mang theo khi flatten/nesting.
        edges = entities.add_edges(*(points_local + [points_local.first]))

        # Trục sâu khoan thật.
        axis_end_world = center_world + scaled(inward_world, mm(depth_mm))
        axis = entities.add_line(center_world.transform(inverse), axis_end_world.transform(inverse))

        all_edges = Array(edges)
        all_edges << axis if axis

        # Dấu tâm giúp nhìn thấy vị trí sau khi trải.
        u, v = plane_axes(normal_world)
        cross_size = [mm(diameter_mm) * 0.22, mm(2.5)].min
        [
          [center_world + scaled(u, -cross_size), center_world + scaled(u, cross_size)],
          [center_world + scaled(v, -cross_size), center_world + scaled(v, cross_size)]
        ].each do |a, b|
          edge = entities.add_line(a.transform(inverse), b.transform(inverse))
          all_edges << edge if edge
        end

        all_edges.compact.each do |edge|
          edge.layer = tag if tag

          # Metadata TT để biết đây là CAM hay CHỐT.
          edge.set_attribute(DICT, 'kind', kind)
          edge.set_attribute(DICT, 'link_id', link_id)
          edge.set_attribute(DICT, 'index', index)
          edge.set_attribute(DICT, 'diameter_mm', diameter_mm.to_f)
          edge.set_attribute(DICT, 'depth_mm', depth_mm.to_f)
          edge.set_attribute(DICT, 'b_offset_mm', @settings['b_offset'].to_f)

          # Metadata nằm trong dictionary ABF nhưng dùng namespace TT-* để
          # không đụng khóa nội bộ của ABF. ABF vẫn nhận nhóm cutting-lines chuẩn.
          edge.set_attribute('ABF', 'tt-machining', true)
          edge.set_attribute('ABF', 'tt-machining-kind', kind.to_s)
          edge.set_attribute('ABF', 'tt-diameter-mm', diameter_mm.to_f)
          edge.set_attribute('ABF', 'tt-depth-mm', depth_mm.to_f)
          edge.set_attribute('ABF', 'tt-link-id', link_id.to_s)
        end

        abf_group.set_attribute(DICT, "link_#{link_id}_#{kind}_#{index}", {
          'diameter_mm' => diameter_mm.to_f,
          'depth_mm' => depth_mm.to_f,
          'b_offset_mm' => @settings['b_offset'].to_f
        }.to_json)

        entity.set_attribute(DICT, "link_#{link_id}_#{kind}", {
          'count' => @settings['count'].to_i,
          'diameter_mm' => diameter_mm.to_f,
          'depth_mm' => depth_mm.to_f,
          'b_offset_mm' => @settings['b_offset'].to_f,
          'abf_cutting_lines' => true
        }.to_json)

        true
      end

      def layer(name)
        @model.layers[name] || @model.layers.add(name)
      end

      def make_unique_if_needed(entity)
        definition = entity.definition
        if definition && definition.instances.length > 1 && entity.respond_to?(:make_unique)
          entity.make_unique
        end
        entity
      end

      def board_frame(entity)
        bounds = entity.definition.bounds
        raise 'Tấm không có BoundingBox hợp lệ.' unless bounds && bounds.valid?

        tr = full_transform(entity)
        raw_axes = [tr.xaxis, tr.yaxis, tr.zaxis]
        lengths = raw_axes.map(&:length)
        dimensions = [bounds.width.to_f * lengths[0], bounds.height.to_f * lengths[1], bounds.depth.to_f * lengths[2]]
        axis_index = (0..2).min_by { |index| dimensions[index] }

        axis = raw_axes[axis_index].clone
        raise 'Tấm có phép biến đổi không hợp lệ.' if axis.length < 0.000001
        axis.normalize!

        {
          center: bounds.center.transform(tr),
          normal: axis,
          corners: (0..7).map { |index| bounds.corner(index).transform(tr) },
          thickness: dimensions[axis_index]
        }
      end

      def full_transform(entity)
        tr = Geom::Transformation.new
        Array(@model.active_path).each { |instance| tr = tr * instance.transformation }
        tr * entity.transformation
      end

      def active_entities
        @model.active_entities.to_a
      end

      def pick_container(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)
        path = helper.path_at(0)
        return nil unless path

        allowed = active_entities
        path.reverse.find do |entity|
          valid_container?(entity) && allowed.include?(entity)
        end
      rescue StandardError
        nil
      end

      def valid_container?(entity)
        entity && entity.valid? &&
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
      rescue StandardError
        false
      end

      def display_name(entity)
        name = entity.name.to_s.strip
        if name.empty? && entity.is_a?(Sketchup::ComponentInstance)
          name = entity.definition.name.to_s.strip
        end
        name.empty? ? (entity.is_a?(Sketchup::Group) ? 'Group' : 'Component') : name
      end

      def projection(points, axis)
        values = points.map { |point| scalar(point, axis) }
        [values.min, values.max]
      end

      def scalar(point, axis)
        point.x.to_f * axis.x.to_f + point.y.to_f * axis.y.to_f + point.z.to_f * axis.z.to_f
      end

      def point_from_basis(axis_a, scalar_a, axis_b, scalar_b, axis_c, scalar_c)
        Geom::Point3d.new(
          axis_a.x * scalar_a + axis_b.x * scalar_b + axis_c.x * scalar_c,
          axis_a.y * scalar_a + axis_b.y * scalar_b + axis_c.y * scalar_c,
          axis_a.z * scalar_a + axis_b.z * scalar_b + axis_c.z * scalar_c
        )
      end

      def scaled(vector, amount)
        Geom::Vector3d.new(vector.x * amount, vector.y * amount, vector.z * amount)
      end

      def mm(value)
        value.to_f.mm.to_f
      end

      def plane_axes(normal)
        reference = normal.z.abs < 0.85 ? Z_AXIS : X_AXIS
        u = normal.cross(reference)
        reference = Y_AXIS if u.length < 0.001
        u = normal.cross(reference) if u.length < 0.001
        u.normalize!
        v = normal.cross(u)
        v.normalize!
        [u, v]
      end

      def circle_points(center, normal, radius, segments)
        u, v = plane_axes(normal)
        Array.new(segments) do |index|
          angle = Math::PI * 2.0 * index.to_f / segments.to_f
          center + scaled(u, Math.cos(angle) * radius) + scaled(v, Math.sin(angle) * radius)
        end
      end

      def draw_box(view, entity, color, width)
        return unless valid_container?(entity)
        frame = board_frame(entity)
        corners = frame[:corners]
        pairs = [
          [0,1],[1,3],[3,2],[2,0],
          [4,5],[5,7],[7,6],[6,4],
          [0,4],[1,5],[2,6],[3,7]
        ]
        points = pairs.flat_map { |a, b| [corners[a], corners[b]] }
        view.drawing_color = color
        view.line_width = width
        view.draw(GL_LINES, points)
      rescue StandardError
      end
    end
  end
end

module TranTuanNoiThat
  module CamChot
    def self.format_number(value)
      text = format('%.2f', value.to_f)
      text.sub!(/\.00\z/, '')
      text.sub!(/(\.\d)0\z/, '\\1')
      text
    end
  end
end
