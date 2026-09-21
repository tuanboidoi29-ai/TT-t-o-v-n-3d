# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module TamPro
    extend self

    VERSION = '1.9.116'.freeze
    EPS = 0.001
    QUICK_NAMES = ['Trái', 'Phải', 'Trên', 'Dưới', 'Trước', 'Sau'].freeze

    def model
      Sketchup.active_model
    end

    def valid_object?(entity)
      entity && entity.valid? &&
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
    rescue StandardError
      false
    end

    def selected_objects
      model.selection.to_a.select { |entity| valid_object?(entity) }
    end

    def selected_faces
      model.selection.to_a.select { |entity| entity.is_a?(Sketchup::Face) && entity.valid? }
    end

    def entity_name(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s.strip : ''
      if name.empty? && entity.is_a?(Sketchup::ComponentInstance)
        name = entity.definition.name.to_s.strip
      end
      name.empty? ? '(Chưa đặt tên)' : name
    rescue StandardError
      '(Chưa đặt tên)'
    end

    def definition_bounds(entity)
      entity.definition.bounds
    rescue StandardError
      nil
    end

    # SketchUp Length * Numeric remains a Length. Convert that Length to mm.
    # Do not call to_f before to_mm because it drops the Length type.
    def local_dimensions_mm(entity)
      bounds = definition_bounds(entity)
      return nil unless bounds && bounds.valid?
      tr = entity.transformation
      scales = [tr.xaxis.length, tr.yaxis.length, tr.zaxis.length]
      lengths = [
        bounds.width * scales[0],
        bounds.height * scales[1],
        bounds.depth * scales[2]
      ]
      lengths.map { |length| length.to_mm.to_f }
    rescue StandardError => error
      warn "[TT TamPro dimensions] #{error.class}: #{error.message}"
      nil
    end

    def thickness_info(entity)
      dims = local_dimensions_mm(entity)
      return nil unless dims && dims.length == 3
      return nil unless dims.all? { |value| value.finite? && value > EPS }
      axis = (0..2).min_by { |index| dims[index] }
      { axis: axis, thickness: dims[axis], dims: dims }
    end

    def scan_objects
      result = []
      seen_entities = {}
      expanded_definitions = {}
      stack = [model.entities]

      until stack.empty?
        entities = stack.pop
        entities.each do |entity|
          next unless valid_object?(entity)
          key = entity.respond_to?(:persistent_id) ? entity.persistent_id.to_i : entity.entityID.to_i
          next if seen_entities[key]
          seen_entities[key] = true
          result << entity

          definition = entity.definition rescue nil
          next unless definition
          definition_key = definition.object_id
          next if expanded_definitions[definition_key]
          expanded_definitions[definition_key] = true
          stack << definition.entities
        end
      end
      result
    end

    def format_mm(value)
      format('%.2f', value.to_f).sub(/\.00\z/, '').sub(/(\.\d)0\z/, '\\1')
    end

    def selection_payload
      objects = selected_objects
      {
        objects: objects.length,
        groups: objects.count { |entity| entity.is_a?(Sketchup::Group) },
        components: objects.count { |entity| entity.is_a?(Sketchup::ComponentInstance) },
        faces: selected_faces.length,
        names: objects.first(12).map { |entity| entity_name(entity) }
      }
    end

    def ensure_selection_observer
      current_model = model
      if @observer_model != current_model
        begin
          @observer_model.selection.remove_observer(@selection_observer) if @observer_model && @selection_observer
        rescue StandardError
        end
        @selection_observer = SelectionWatcher.new
        current_model.selection.add_observer(@selection_observer)
        @observer_model = current_model
      end
      true
    rescue StandardError => error
      warn "[TT TamPro observer] #{error.class}: #{error.message}"
      false
    end

    def dialog_visible?(dialog)
      dialog && dialog.visible?
    rescue StandardError
      false
    end

    def selection_changed
      payload = JSON.generate(selection_payload)
      [@dialog_thickness, @dialog_rename, @dialog_convert].each do |dialog|
        next unless dialog_visible?(dialog)
        dialog.execute_script("TT.setSelection(#{payload});")
      rescue StandardError
      end
    end

    # ----------------------------------------------------------------------
    # 1. TÌM TẤM / SỬA ĐỘ DÀY
    # ----------------------------------------------------------------------

    def thickness_rows(scope)
      pool = scope.to_s == 'selection' ? selected_objects : scan_objects
      pool.map do |entity|
        info = thickness_info(entity)
        next unless info
        {
          entity: entity,
          thickness: info[:thickness],
          dims: info[:dims],
          name: entity_name(entity),
          type: entity.is_a?(Sketchup::Group) ? 'Group' : 'Component'
        }
      end.compact
    end

    def thickness_values
      thickness_rows('model').map { |row| (row[:thickness] * 10.0).round / 10.0 }.uniq.sort
    end

    def find_matches(scope, target_mm, tolerance)
      target = target_mm.to_f
      tol = [tolerance.to_f.abs, 0.01].max
      thickness_rows(scope).select { |row| (row[:thickness] - target).abs <= tol }
    end

    def highlight_matches(matches)
      selection = model.selection
      selection.clear
      added = 0
      matches.each do |row|
        begin
          selection.add(row[:entity])
          added += 1 if selection.include?(row[:entity])
        rescue StandardError
        end
      end
      if added > 0
        model.active_view.zoom(selection) rescue nil
        model.active_view.invalidate rescue nil
      end
      added
    end

    def change_thickness(entities, new_mm)
      target = new_mm.to_f
      raise 'Độ dày mới phải lớn hơn 0 mm.' unless target > EPS

      model.start_operation('TT - Đổi độ dày tấm', true)
      changed = 0

      entities.each do |entity|
        next unless valid_object?(entity)
        info = thickness_info(entity)
        next unless info

        current = info[:thickness].to_f
        next if current <= EPS
        ratio = target / current
        next unless ratio.finite? && ratio > EPS

        bounds = definition_bounds(entity)
        next unless bounds

        axis = info[:axis]
        sx = axis == 0 ? ratio : 1.0
        sy = axis == 1 ? ratio : 1.0
        sz = axis == 2 ? ratio : 1.0
        scaling = Geom::Transformation.scaling(bounds.min, sx, sy, sz)
        entity.transformation = entity.transformation * scaling
        changed += 1
      end

      model.commit_operation
      changed
    rescue StandardError
      model.abort_operation rescue nil
      raise
    end

    def send_thickness_scan
      return unless dialog_visible?(@dialog_thickness)
      values = thickness_values
      @dialog_thickness.execute_script("TT.setThicknesses(#{JSON.generate(values)});")
      selection_changed
    rescue StandardError => error
      notify(@dialog_thickness, "Quét độ dày lỗi: #{error.message}", 'error')
    end

    def find_thickness_action(scope, target, tolerance)
      matches = find_matches(scope, target, tolerance)
      added = highlight_matches(matches)
      message = if matches.empty?
        "Không tìm thấy tấm dày #{format_mm(target)} mm."
      elsif added == matches.length
        "Tìm thấy #{matches.length} tấm. Đã chọn và zoom các tấm tìm được."
      else
        "Tìm thấy #{matches.length} tấm; chọn trực tiếp được #{added} tấm trong ngữ cảnh hiện tại. Các tấm lồng sâu vẫn được tính."
      end
      notify(@dialog_thickness, message, matches.empty? ? 'warn' : 'ok')
      send_thickness_scan
    rescue StandardError => error
      notify(@dialog_thickness, error.message, 'error')
    end

    def apply_thickness_action(scope, target, tolerance, new_value)
      matches = find_matches(scope, target, tolerance)
      if matches.empty?
        notify(@dialog_thickness, 'Không có tấm phù hợp để đổi độ dày.', 'warn')
        return
      end
      changed = change_thickness(matches.map { |row| row[:entity] }, new_value.to_f)
      notify(@dialog_thickness, "Đã đổi #{changed}/#{matches.length} tấm sang #{format_mm(new_value)} mm. Ctrl+Z hoàn tác một lần.", 'ok')
      send_thickness_scan
      selection_changed
    rescue StandardError => error
      notify(@dialog_thickness, error.message, 'error')
    end

    def find_and_edit_thickness
      ensure_selection_observer
      if dialog_visible?(@dialog_thickness)
        @dialog_thickness.bring_to_front
        send_thickness_scan
        return
      end

      @dialog_thickness = UI::HtmlDialog.new(
        dialog_title: 'TT - TÌM TẤM / SỬA ĐỘ DÀY',
        preferences_key: 'TranTuanNoiThat.TamPro.Thickness.104',
        scrollable: true,
        resizable: true,
        width: 620,
        height: 620,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog_thickness.set_html(thickness_html)
      @dialog_thickness.add_action_callback('ready') { |_ctx| send_thickness_scan }
      @dialog_thickness.add_action_callback('scan') { |_ctx| send_thickness_scan }
      @dialog_thickness.add_action_callback('find') do |_ctx, scope, target, tolerance|
        find_thickness_action(scope, target, tolerance)
      end
      @dialog_thickness.add_action_callback('apply') do |_ctx, scope, target, tolerance, new_value|
        apply_thickness_action(scope, target, tolerance, new_value)
      end
      @dialog_thickness.set_on_closed { @dialog_thickness = nil }
      @dialog_thickness.show
    rescue StandardError => error
      UI.messagebox("Không mở được Tìm tấm / Sửa độ dày:\n#{error.message}")
    end

    # ----------------------------------------------------------------------
    # 2. ĐỔI TÊN
    # ----------------------------------------------------------------------

    def apply_rename(base, prefix, suffix, numbering)
      targets = selected_objects
      raise 'Hãy chọn ít nhất một Group/Component trong SketchUp.' if targets.empty?

      base = base.to_s.strip
      prefix = prefix.to_s
      suffix = suffix.to_s
      use_number = numbering == true || numbering.to_s == 'true'

      model.start_operation('TT - Đổi tên tấm', true)
      targets.each_with_index do |entity, index|
        core = base.empty? ? entity_name(entity) : base
        core = '' if core == '(Chưa đặt tên)'
        serial = use_number && targets.length > 1 ? format('_%02d', index + 1) : ''
        new_name = "#{prefix}#{core}#{serial}#{suffix}".strip
        new_name = "Đối tượng#{serial}" if new_name.empty?
        entity.name = new_name
      end
      model.commit_operation

      notify(@dialog_rename, "Đã đổi tên #{targets.length} đối tượng. Ctrl+Z hoàn tác một lần.", 'ok')
      selection_changed
    rescue StandardError => error
      model.abort_operation rescue nil
      notify(@dialog_rename, error.message, 'error')
    end

    def rename_objects
      ensure_selection_observer
      if dialog_visible?(@dialog_rename)
        @dialog_rename.bring_to_front
        selection_changed
        return
      end

      @dialog_rename = UI::HtmlDialog.new(
        dialog_title: 'TT - ĐỔI TÊN TẤM / GROUP / COMPONENT',
        preferences_key: 'TranTuanNoiThat.TamPro.Rename.104',
        scrollable: true,
        resizable: true,
        width: 620,
        height: 610,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog_rename.set_html(rename_html)
      @dialog_rename.add_action_callback('ready') { |_ctx| selection_changed }
      @dialog_rename.add_action_callback('apply') do |_ctx, base, prefix, suffix, numbering|
        apply_rename(base, prefix, suffix, numbering)
      end
      @dialog_rename.set_on_closed { @dialog_rename = nil }
      @dialog_rename.show
    rescue StandardError => error
      UI.messagebox("Không mở được Đổi tên:\n#{error.message}")
    end

    # ----------------------------------------------------------------------
    # 3. CHUYỂN ĐỔI GROUP / COMPONENT / FACE
    # ----------------------------------------------------------------------

    def parent_entities(entity)
      parent = entity.parent
      return parent.entities if parent.respond_to?(:entities)
      return parent if parent.is_a?(Sketchup::Entities)
      model.active_entities
    rescue StandardError
      model.active_entities
    end

    def copy_instance_properties(source, target)
      target.name = source.name if target.respond_to?(:name=) && source.respond_to?(:name)
      target.layer = source.layer if target.respond_to?(:layer=) && source.respond_to?(:layer)
      target.material = source.material if target.respond_to?(:material=) && source.respond_to?(:material)
      target.hidden = source.hidden? if target.respond_to?(:hidden=) && source.respond_to?(:hidden?)
      dictionaries = source.attribute_dictionaries if source.respond_to?(:attribute_dictionaries)
      if dictionaries
        dictionaries.each do |dictionary|
          dictionary.each_pair { |key, value| target.set_attribute(dictionary.name, key, value) }
        end
      end
      target
    rescue StandardError
      target
    end

    def component_to_group(instance)
      entities = parent_entities(instance)
      transform = instance.transformation
      group = entities.add_group
      inner = group.entities.add_instance(instance.definition, Geom::Transformation.new)
      inner.explode
      group.transformation = transform
      copy_instance_properties(instance, group)
      instance.erase!
      group
    end

    def convert_component_to_group
      targets = model.selection.to_a.select { |entity| entity.is_a?(Sketchup::ComponentInstance) && entity.valid? }
      raise 'Hãy Ctrl chọn ít nhất một Component trong SketchUp.' if targets.empty?

      model.start_operation('TT - Component sang Group', true)
      created = targets.map { |instance| component_to_group(instance) }.compact
      model.selection.clear
      created.each { |entity| model.selection.add(entity) rescue nil }
      model.commit_operation
      notify(@dialog_convert, "Đã chuyển #{created.length} Component → Group. Ctrl+Z hoàn tác.", 'ok')
      selection_changed
    rescue StandardError => error
      model.abort_operation rescue nil
      notify(@dialog_convert, error.message, 'error')
    end

    def convert_group_to_component
      targets = model.selection.to_a.select { |entity| entity.is_a?(Sketchup::Group) && entity.valid? }
      raise 'Hãy Ctrl chọn ít nhất một Group trong SketchUp.' if targets.empty?

      model.start_operation('TT - Group sang Component', true)
      created = targets.map do |group|
        old_name = group.name.to_s
        instance = group.to_component
        instance.name = old_name unless old_name.empty?
        instance
      end.compact
      model.selection.clear
      created.each { |entity| model.selection.add(entity) rescue nil }
      model.commit_operation
      notify(@dialog_convert, "Đã chuyển #{created.length} Group → Component. Ctrl+Z hoàn tác.", 'ok')
      selection_changed
    rescue StandardError => error
      model.abort_operation rescue nil
      notify(@dialog_convert, error.message, 'error')
    end

    def convert_face_to_group
      active = model.active_entities
      faces = selected_faces.select do |face|
        begin
          active.include?(face)
        rescue StandardError
          true
        end
      end
      raise 'Hãy chọn ít nhất một Face trong ngữ cảnh đang mở.' if faces.empty?

      items = faces.flat_map { |face| [face] + face.edges }.uniq
      model.start_operation('TT - Face sang Group', true)
      group = active.add_group(items)
      group.name = 'Face Group'
      model.selection.clear
      model.selection.add(group)
      model.commit_operation
      notify(@dialog_convert, 'Đã chuyển Face → Group. Ctrl+Z hoàn tác.', 'ok')
      selection_changed
    rescue StandardError => error
      model.abort_operation rescue nil
      notify(@dialog_convert, error.message, 'error')
    end

    def convert_objects
      ensure_selection_observer
      if dialog_visible?(@dialog_convert)
        @dialog_convert.bring_to_front
        selection_changed
        return
      end

      @dialog_convert = UI::HtmlDialog.new(
        dialog_title: 'TT - CHUYỂN ĐỔI ĐỐI TƯỢNG',
        preferences_key: 'TranTuanNoiThat.TamPro.Convert.104',
        scrollable: true,
        resizable: true,
        width: 560,
        height: 520,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog_convert.set_html(convert_html)
      @dialog_convert.add_action_callback('ready') { |_ctx| selection_changed }
      @dialog_convert.add_action_callback('component_to_group') { |_ctx| convert_component_to_group }
      @dialog_convert.add_action_callback('group_to_component') { |_ctx| convert_group_to_component }
      @dialog_convert.add_action_callback('face_to_group') { |_ctx| convert_face_to_group }
      @dialog_convert.set_on_closed { @dialog_convert = nil }
      @dialog_convert.show
    rescue StandardError => error
      UI.messagebox("Không mở được Chuyển đổi:\n#{error.message}")
    end

    def notify(dialog, message, kind = 'ok')
      if dialog_visible?(dialog)
        dialog.execute_script("TT.notice(#{JSON.generate(message.to_s)}, #{JSON.generate(kind.to_s)});")
      else
        UI.messagebox(message.to_s)
      end
    rescue StandardError
      UI.messagebox(message.to_s) rescue nil
    end

    def common_css
      <<~CSS
        *{box-sizing:border-box}
        body{font-family:Arial,sans-serif;margin:0;background:#f3f5f7;color:#222}
        .top{padding:14px;background:#fff;border-bottom:1px solid #ddd;position:sticky;top:0;z-index:2}
        h2{margin:0 0 8px;font-size:18px}
        .content{padding:14px}
        .card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:12px}
        .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:8px 0}
        label{font-size:13px;font-weight:bold}
        input,select{padding:8px;border:1px solid #bbb;border-radius:6px;min-width:110px}
        input.wide{flex:1;min-width:220px}
        button{border:0;border-radius:6px;padding:9px 12px;cursor:pointer;background:#2d6cdf;color:#fff;font-weight:bold}
        button.green{background:#18864b} button.orange{background:#c96a14} button.gray{background:#666}
        .selection{font-size:13px;line-height:1.5;background:#eef5ff;border:1px solid #cddfff;border-radius:6px;padding:9px}
        .notice{padding:9px;border-radius:6px;margin-top:8px;font-size:13px;display:none;white-space:pre-wrap}
        .notice.ok{display:block;background:#e8f6ee;color:#165c36}
        .notice.warn{display:block;background:#fff3d8;color:#785000}
        .notice.error{display:block;background:#fdeaea;color:#8c2222}
        .hint{font-size:12px;color:#666;line-height:1.45}
        .quick button{background:#5b6573;padding:7px 9px}
      CSS
    end

    def common_js
      <<~JS
        const TT={
          selection:{objects:0,groups:0,components:0,faces:0,names:[]},
          setSelection(d){
            this.selection=d||{};
            const el=document.getElementById('selection');
            if(el){
              const names=(d.names||[]).map(x=>esc(x)).join(', ');
              el.innerHTML='<b>Đang chọn:</b> '+(d.objects||0)+' Group/Component · '+(d.faces||0)+' Face'
                +(names ? '<br><span>'+names+'</span>' : '');
            }
          },
          notice(message,kind){
            const el=document.getElementById('notice');
            if(!el)return;
            el.className='notice '+(kind||'ok');
            el.textContent=message||'';
          }
        };
        function esc(s){return String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}
      JS
    end

    def thickness_html
      css = common_css
      js = common_js
      <<~HTML
        <!doctype html><html><head><meta charset="UTF-8"><style>#{css}</style></head>
        <body>
          <div class="top"><h2>1. TÌM TẤM / SỬA ĐỘ DÀY</h2><div id="selection" class="selection">Đang đọc Selection…</div></div>
          <div class="content">
            <div class="card">
              <div class="row"><label>Phạm vi</label>
                <select id="scope"><option value="model">Toàn model</option><option value="selection">Các tấm đang chọn</option></select>
                <button class="gray" onclick="sketchup.scan()">Quét lại</button>
              </div>
              <div class="row"><label>Độ dày cần tìm</label><select id="target"></select><span>mm</span></div>
              <div class="row"><label>Sai số</label><input id="tol" type="number" value="0.15" step="0.05" min="0.01"><span>mm</span></div>
              <div class="row"><button onclick="findNow()">TÌM + ZOOM</button></div>
            </div>
            <div class="card">
              <div class="row"><label>Độ dày mới</label><input id="newT" type="number" value="17.5" step="0.1" min="0.1"><span>mm</span></div>
              <button class="orange" onclick="applyNow()">ĐỔI ĐỘ DÀY HÀNG LOẠT</button>
              <div class="hint">Bạn có thể để bảng mở, Ctrl chọn/bỏ chọn các tấm trực tiếp trong SketchUp rồi chọn phạm vi “Các tấm đang chọn”.</div>
            </div>
            <div id="notice" class="notice"></div>
          </div>
          <script>#{js}
            TT.setThicknesses=function(values){
              const sel=document.getElementById('target');
              const old=sel.value;
              sel.innerHTML=(values||[]).map(v=>'<option value="'+v+'">'+v+'</option>').join('');
              if([...sel.options].some(o=>o.value===old)) sel.value=old;
              else if([...sel.options].some(o=>o.value==='17.5')) sel.value='17.5';
            };
            function vals(){return [document.getElementById('scope').value,document.getElementById('target').value,document.getElementById('tol').value];}
            function findNow(){const v=vals();sketchup.find(v[0],v[1],v[2]);}
            function applyNow(){const v=vals();sketchup.apply(v[0],v[1],v[2],document.getElementById('newT').value);}
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body></html>
      HTML
    end

    def rename_html
      css = common_css
      js = common_js
      quick = QUICK_NAMES.map { |name| %(<button onclick="quick('#{name}')">#{name}</button>) }.join
      <<~HTML
        <!doctype html><html><head><meta charset="UTF-8"><style>#{css}</style></head>
        <body>
          <div class="top"><h2>2. ĐỔI TÊN TẤM / GROUP / COMPONENT</h2><div id="selection" class="selection">Ctrl chọn các Group/Component trực tiếp trong SketchUp.</div></div>
          <div class="content">
            <div class="card">
              <div class="row"><label>Tên mới</label><input id="base" class="wide" type="text" placeholder="Để trống = giữ tên hiện tại"></div>
              <div class="row"><label>Tiền tố</label><input id="prefix" class="wide" type="text" placeholder="VD: BẾP_"></div>
              <div class="row"><label>Hậu tố</label><input id="suffix" class="wide" type="text" placeholder="VD: _TRÁI"></div>
              <div class="row"><label><input id="numbering" type="checkbox"> Tự đánh số _01, _02… khi chọn nhiều</label></div>
              <div class="row quick"><span class="hint">Tên nhanh:</span>#{quick}</div>
              <button class="green" onclick="applyRename()">ÁP DỤNG CHO CÁC ĐỐI TƯỢNG ĐANG CHỌN</button>
            </div>
            <div class="hint">Bảng không khóa SketchUp. Giữ Ctrl để tích/bỏ tích nhiều Group/Component rồi bấm Áp dụng. Ctrl+Z hoàn tác cả lượt.</div>
            <div id="notice" class="notice"></div>
          </div>
          <script>#{js}
            function quick(v){document.getElementById('base').value=v;}
            function applyRename(){
              sketchup.apply(
                document.getElementById('base').value,
                document.getElementById('prefix').value,
                document.getElementById('suffix').value,
                document.getElementById('numbering').checked
              );
            }
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body></html>
      HTML
    end

    def convert_html
      css = common_css
      js = common_js
      <<~HTML
        <!doctype html><html><head><meta charset="UTF-8"><style>#{css}</style></head>
        <body>
          <div class="top"><h2>3. CHUYỂN ĐỔI ĐỐI TƯỢNG</h2><div id="selection" class="selection">Ctrl chọn trực tiếp trong SketchUp.</div></div>
          <div class="content">
            <div class="card">
              <button onclick="sketchup.component_to_group()">COMPONENT → GROUP</button>
              <div class="hint">Chọn một hoặc nhiều Component rồi bấm nút.</div>
            </div>
            <div class="card">
              <button class="green" onclick="sketchup.group_to_component()">GROUP → COMPONENT</button>
              <div class="hint">Chọn một hoặc nhiều Group rồi bấm nút.</div>
            </div>
            <div class="card">
              <button class="orange" onclick="sketchup.face_to_group()">FACE → GROUP</button>
              <div class="hint">Chui vào đúng Group/Component nếu Face nằm bên trong, chọn Face rồi bấm nút.</div>
            </div>
            <div id="notice" class="notice"></div>
          </div>
          <script>#{js}
            window.addEventListener('load',()=>sketchup.ready());
          </script>
        </body></html>
      HTML
    end

    # ----------------------------------------------------------------------
    # COMMANDS / MENU / TOOLBAR
    # ----------------------------------------------------------------------

    def icon_path(name)
      File.join(__dir__, 'icons', "#{name}.svg")
    end

    def commands
      return @commands if @commands

      find_cmd = UI::Command.new('Tìm tấm / Sửa độ dày') { find_and_edit_thickness }
      find_cmd.tooltip = 'Tìm tấm / Sửa độ dày'
      find_cmd.status_bar_text = 'Quét Group/Component, tìm theo độ dày và đổi độ dày hàng loạt.'

      rename_cmd = UI::Command.new('Đổi tên tấm / Group') { rename_objects }
      rename_cmd.tooltip = 'Đổi tên tấm / Group'
      rename_cmd.status_bar_text = 'Để bảng mở và Ctrl chọn nhiều Group/Component trực tiếp trong model.'

      convert_cmd = UI::Command.new('Chuyển đổi Group / Component') { convert_objects }
      convert_cmd.tooltip = 'Chuyển đổi Group / Component'
      convert_cmd.status_bar_text = 'Component → Group, Group → Component, Face → Group.'

      {
        find: ['tam_find', find_cmd],
        rename: ['tam_rename', rename_cmd],
        convert: ['tam_convert', convert_cmd]
      }.each_value do |icon_name, command|
        icon = icon_path(icon_name)
        if File.file?(icon)
          command.small_icon = icon
          command.large_icon = icon
        end
      end

      @commands = { find: find_cmd, rename: rename_cmd, convert: convert_cmd }
    end

    def add_menu_items(menu)
      return true if @menu_installed
      return false unless menu
      menu.add_separator rescue nil
      commands.each_value { |command| menu.add_item(command) }
      @menu_installed = true
      true
    rescue StandardError => error
      warn "[TranTuanNoiThat::TamPro] menu: #{error.class}: #{error.message}"
      false
    end

    def add_toolbar_items(toolbar)
      return true if @toolbar_installed
      return false unless toolbar
      menu_commands = commands
      toolbar.add_separator rescue nil
      menu_commands.each_value { |command| toolbar.add_item(command) }
      @toolbar_installed = true
      true
    rescue StandardError => error
      warn "[TranTuanNoiThat::TamPro] toolbar: #{error.class}: #{error.message}"
      false
    end

    def reset_ui_flags!
      @menu_installed = false
      @toolbar_installed = false
      true
    end

    class SelectionWatcher < Sketchup::SelectionObserver
      def onSelectionBulkChange(_selection)
        TamPro.selection_changed
      end

      def onSelectionAdded(_selection, _entity)
        TamPro.selection_changed
      end

      def onSelectionCleared(_selection)
        TamPro.selection_changed
      end

      def onSelectionRemoved(_selection, _entity)
        TamPro.selection_changed
      end

      if method_defined?(:onSelectionRemoved)
        alias_method :onSelectedRemoved, :onSelectionRemoved
      end
    end
  end
end
