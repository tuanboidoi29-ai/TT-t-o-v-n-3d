# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - XUẤT LAYOUT + THỐNG KÊ VÁN
# V0.1.0 - A3 ngang, preview thống kê, trang phối cảnh + tự chia trang bảng ván.

module TranTuanNoiThat
  module LayoutStats
    extend self

    VERSION = '0.1.0'.freeze
    GRAIN_DICT = 'TT_GRAIN'.freeze
    ABF_GRAIN_DICT = 'TT_ABF_GRAIN'.freeze
    MM_PER_INCH = 25.4
    A3_W = 420.0 / MM_PER_INCH
    A3_H = 297.0 / MM_PER_INCH
    ROWS_PER_PAGE = 22

    @dialog = nil
    @stats = nil

    def show
      @stats = build_stats
      if @dialog && @dialog.visible?
        sync_dialog
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - XUẤT LAYOUT + THỐNG KÊ VÁN',
        preferences_key: 'TranTuanNoiThat.LayoutStats',
        scrollable: true,
        resizable: true,
        width: 980,
        height: 700,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('ready') { |_ctx| sync_dialog }
      @dialog.add_action_callback('refresh') do |_ctx|
        @stats = build_stats
        sync_dialog
      end
      @dialog.add_action_callback('export_layout') do |_ctx|
        begin
          @stats = build_stats
          if @stats[:rows].empty?
            UI.messagebox('Không tìm thấy tấm ván hợp lệ để thống kê.')
            next
          end
          export_layout(@stats)
          sync_dialog
        rescue StandardError => error
          UI.messagebox("Xuất LayOut thất bại:\n#{error.message}")
          puts "[TT LayoutStats export] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(8).join("\n")}"
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    rescue StandardError => error
      UI.messagebox("Không mở được Xuất Layout + Thống Kê Ván:\n#{error.message}")
    end

    def build_stats
      model = Sketchup.active_model
      roots = model.selection.to_a.select { |e| container?(e) && e.valid? }
      selected = !roots.empty?
      roots = model.active_entities.to_a.select { |e| container?(e) && e.valid? } unless selected

      records = []
      base_tr = model.edit_transform || Geom::Transformation.new
      roots.each do |entity|
        scan_entity(entity, base_tr, nil, records)
      end

      grouped = {}
      records.each do |record|
        key = [
          record[:name].to_s,
          record[:length_mm].round(1),
          record[:width_mm].round(1),
          record[:thickness_mm].round(1),
          record[:material].to_s,
          record[:grain].to_s
        ]
        row = grouped[key]
        if row
          row[:qty] += 1
          row[:area_m2] += record[:area_m2]
        else
          grouped[key] = record.merge(qty: 1)
        end
      end

      rows = grouped.values.sort_by do |r|
        [r[:material].to_s.downcase, r[:name].to_s.downcase, -r[:length_mm], -r[:width_mm]]
      end
      rows.each_with_index { |row, index| row[:stt] = index + 1 }

      {
        rows: rows,
        total_pieces: rows.inject(0) { |sum, row| sum + row[:qty].to_i },
        total_types: rows.length,
        total_area_m2: rows.inject(0.0) { |sum, row| sum + row[:area_m2].to_f },
        scope: selected ? 'ĐỐI TƯỢNG ĐANG CHỌN' : 'TOÀN BỘ CONTEXT HIỆN TẠI',
        source_count: records.length,
        generated_at: Time.now.strftime('%d/%m/%Y %H:%M')
      }
    end

    def scan_entity(entity, parent_tr, inherited_material, out)
      return unless entity && entity.valid? && container?(entity)

      tr = parent_tr * entity.transformation
      ents = child_entities(entity)
      return unless ents

      children = ents.to_a.select { |child| container?(child) && child.valid? }
      dims = dimensions_mm(entity, tr)
      own_material = entity.material || inherited_material
      board = dims && board_dimensions?(dims) && (children.empty? || board_name_hint?(entity))

      if board
        out << build_record(entity, ents, dims, own_material)
        return
      end

      children.each do |child|
        scan_entity(child, tr, own_material, out)
      end
    rescue StandardError => error
      puts "[TT LayoutStats scan] #{error.class}: #{error.message}"
    end

    def build_record(entity, ents, dims, inherited_material)
      sorted = dims.sort
      thickness = sorted[0]
      width = sorted[1]
      length = sorted[2]
      material = material_name(entity, ents, inherited_material)
      grain = grain_name(entity)
      name = part_name(entity)
      name = format('Ván %.0fx%.0fx%.1f', length, width, thickness) if name.empty?

      {
        name: name,
        length_mm: length,
        width_mm: width,
        thickness_mm: thickness,
        material: material,
        grain: grain,
        area_m2: (length * width) / 1_000_000.0
      }
    end

    def board_dimensions?(dims)
      sorted = dims.sort
      return false unless sorted.length == 3
      max_t = if defined?(TranTuanNoiThat::Grain) && TranTuanNoiThat::Grain.respond_to?(:max_thickness_mm)
                TranTuanNoiThat::Grain.max_thickness_mm.to_f
              else
                80.0
              end
      sorted[0] >= 0.5 && sorted[0] <= [max_t, 120.0].max && sorted[1] >= 20.0 && sorted[2] >= 20.0
    end

    def dimensions_mm(entity, tr)
      definition = entity.respond_to?(:definition) ? entity.definition : nil
      return nil unless definition
      bounds = definition.bounds
      return nil unless bounds && bounds.valid?

      scales = [tr.xaxis.length, tr.yaxis.length, tr.zaxis.length]
      [
        bounds.width.to_f * scales[0] * MM_PER_INCH,
        bounds.height.to_f * scales[1] * MM_PER_INCH,
        bounds.depth.to_f * scales[2] * MM_PER_INCH
      ]
    rescue StandardError
      nil
    end

    def part_name(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s.strip : ''
      if name.empty? && entity.respond_to?(:definition) && entity.definition
        name = entity.definition.name.to_s.strip
      end
      name
    rescue StandardError
      ''
    end

    def board_name_hint?(entity)
      text = part_name(entity).downcase
      normalized = begin
        text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').tr('đ', 'd')
      rescue StandardError
        text
      end
      !!(normalized =~ /(\bvan\b|\btam\b|abf_|panel|shelf|door|canh|hoi|dot|day|noc)/)
    end

    def material_name(entity, ents, inherited_material)
      from_grain = entity.get_attribute(GRAIN_DICT, 'material_name', '').to_s.strip rescue ''
      return from_grain unless from_grain.empty?

      material = entity.material || inherited_material
      return material_display_name(material) if material

      counts = Hash.new(0)
      ents.grep(Sketchup::Face).each do |face|
        [face.material, face.back_material].compact.each { |mat| counts[mat] += 1 }
      end
      pair = counts.max_by { |_mat, count| count }
      pair ? material_display_name(pair[0]) : '—'
    rescue StandardError
      '—'
    end

    def material_display_name(material)
      return '—' unless material
      value = material.respond_to?(:display_name) ? material.display_name.to_s : material.name.to_s
      value.empty? ? '—' : value
    rescue StandardError
      '—'
    end

    def grain_name(entity)
      axis = entity.get_attribute(GRAIN_DICT, 'grain_axis', '').to_s rescue ''
      sign = entity.get_attribute(GRAIN_DICT, 'grain_sign', 1).to_i rescue 1
      locked = entity.get_attribute(GRAIN_DICT, 'locked', false) == true rescue false
      if axis.empty?
        axis = entity.get_attribute(ABF_GRAIN_DICT, 'grain_axis', '').to_s rescue ''
      end
      return '—' if axis.empty?
      "#{axis}#{sign < 0 ? '-' : '+'}#{locked ? ' • KHÓA' : ''}"
    rescue StandardError
      '—'
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def child_entities(entity)
      definition = entity.respond_to?(:definition) ? entity.definition : nil
      definition ? definition.entities : nil
    end

    def sync_dialog
      return unless @dialog && @dialog.visible?
      @stats ||= build_stats
      payload = {
        version: VERSION,
        scope: @stats[:scope],
        total_pieces: @stats[:total_pieces],
        total_types: @stats[:total_types],
        total_area_m2: @stats[:total_area_m2].round(3),
        generated_at: @stats[:generated_at],
        rows: @stats[:rows].map do |row|
          {
            stt: row[:stt],
            name: row[:name],
            length_mm: row[:length_mm].round(1),
            width_mm: row[:width_mm].round(1),
            thickness_mm: row[:thickness_mm].round(1),
            qty: row[:qty],
            material: row[:material],
            grain: row[:grain],
            area_m2: row[:area_m2].round(3)
          }
        end
      }
      @dialog.execute_script("window.renderStats(#{JSON.generate(payload)})")
    end

    def dialog_html
      <<~HTML
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;background:#111827;color:#e5e7eb;font:14px Arial}.head{padding:20px 24px;background:linear-gradient(135deg,#f97316,#c2410c)}h1{margin:0;font-size:22px}.sub{margin-top:5px;opacity:.9}.body{padding:18px}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:14px}.card{background:#1f2937;border:1px solid #374151;border-radius:10px;padding:12px}.n{font-size:22px;font-weight:bold;color:#fdba74}.k{font-size:11px;color:#9ca3af;margin-top:3px}.scope{margin:10px 0;color:#fbbf24}.tablewrap{max-height:420px;overflow:auto;border:1px solid #374151;border-radius:9px}table{width:100%;border-collapse:collapse;background:#111827}th{position:sticky;top:0;background:#374151;color:#fff;padding:8px;border:1px solid #4b5563;font-size:12px}td{padding:7px;border:1px solid #374151;font-size:12px}td.num{text-align:right;white-space:nowrap}.empty{padding:30px;text-align:center;color:#fca5a5}.buttons{display:flex;gap:10px;margin-top:15px}button{padding:11px 16px;border:0;border-radius:8px;font-weight:bold;cursor:pointer}.primary{background:#f97316;color:#fff}.dark{background:#374151;color:#fff}.note{margin-top:10px;font-size:12px;color:#9ca3af;line-height:1.5}
        </style></head><body><div class="head"><h1>XUẤT LAYOUT + THỐNG KÊ VÁN</h1><div class="sub">TRẦN TUẤN NỘI THẤT · V<span id="ver">-</span> · A3 NGANG</div></div><div class="body">
        <div class="cards"><div class="card"><div class="n" id="pieces">0</div><div class="k">TỔNG SỐ TẤM</div></div><div class="card"><div class="n" id="types">0</div><div class="k">LOẠI TẤM</div></div><div class="card"><div class="n" id="area">0</div><div class="k">TỔNG m²</div></div><div class="card"><div class="n" id="rows">0</div><div class="k">DÒNG THỐNG KÊ</div></div></div>
        <div class="scope" id="scope">-</div><div class="tablewrap"><table><thead><tr><th>STT</th><th>TÊN TẤM</th><th>DÀI</th><th>RỘNG</th><th>DÀY</th><th>SL</th><th>VẬT LIỆU</th><th>VÂN</th><th>m²</th></tr></thead><tbody id="body"></tbody></table><div class="empty" id="empty" style="display:none">Không tìm thấy tấm ván hợp lệ.</div></div>
        <div class="buttons"><button class="primary" onclick="sketchup.export_layout()">XUẤT LAYOUT</button><button class="dark" onclick="sketchup.refresh()">QUÉT LẠI</button><button class="dark" onclick="window.close()">ĐÓNG</button></div>
        <div class="note">Có Group/Component đang chọn → chỉ thống kê vùng chọn. Không chọn → quét toàn bộ context hiện tại. File LayOut tạo trang phối cảnh + tự chia nhiều trang bảng thống kê khi cần.</div></div>
        <script>
        const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        window.renderStats=d=>{ver.textContent=d.version;pieces.textContent=d.total_pieces;types.textContent=d.total_types;area.textContent=Number(d.total_area_m2).toFixed(3);rows.textContent=d.rows.length;scope.textContent='PHẠM VI: '+d.scope+' · '+d.generated_at;const tb=document.getElementById('body');tb.innerHTML='';empty.style.display=d.rows.length?'none':'block';d.rows.forEach(r=>{const tr=document.createElement('tr');tr.innerHTML=`<td class="num">${r.stt}</td><td>${esc(r.name)}</td><td class="num">${Number(r.length_mm).toFixed(1)}</td><td class="num">${Number(r.width_mm).toFixed(1)}</td><td class="num">${Number(r.thickness_mm).toFixed(1)}</td><td class="num">${r.qty}</td><td>${esc(r.material)}</td><td>${esc(r.grain)}</td><td class="num">${Number(r.area_m2).toFixed(3)}</td>`;tb.appendChild(tr)})};
        document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
        </script></body></html>
      HTML
    end

    def export_layout(stats)
      ensure_layout_api!
      model = Sketchup.active_model
      skp_path = ensure_model_saved(model)
      return false unless skp_path

      default_name = File.basename(skp_path, File.extname(skp_path)) + '_TT_LAYOUT.layout'
      layout_path = UI.savepanel('Xuất LayOut + Thống Kê Ván', File.dirname(skp_path), default_name)
      return false unless layout_path
      layout_path += '.layout' unless File.extname(layout_path).downcase == '.layout'

      doc = Layout::Document.new
      setup_a3(doc)
      layer = doc.layers.first
      layer.name = 'TRẦN TUẤN - NỘI THẤT' if layer.respond_to?(:name=)

      add_overview_page(doc, layer, model, skp_path, stats)
      add_statistics_pages(doc, layer, stats)

      version = if defined?(Layout::Document::VERSION_2022)
                  Layout::Document::VERSION_2022
                else
                  Layout::Document::VERSION_CURRENT
                end
      doc.save(layout_path, version)

      answer = UI.messagebox(
        "Đã xuất LayOut thành công.\n\n#{layout_path}\n\nTổng: #{stats[:total_pieces]} tấm · #{format('%.3f', stats[:total_area_m2])} m²\n\nMở ngay trong LayOut?",
        MB_YESNO
      )
      Sketchup.send_to_layout(layout_path) if answer == IDYES
      true
    end

    def ensure_layout_api!
      unless defined?(Layout) && defined?(Layout::Document) && defined?(Layout::SketchUpModel)
        raise 'Máy này không có LayOut Ruby API. Cần SketchUp Pro/LayOut 2018 trở lên.'
      end
    end

    def ensure_model_saved(model)
      path = model.path.to_s
      if path.empty?
        home = ENV['USERPROFILE'] || ENV['HOME'] || Dir.pwd
        folder = File.directory?(File.join(home, 'Desktop')) ? File.join(home, 'Desktop') : home
        path = UI.savepanel('Lưu mô hình SKP trước khi xuất LayOut', folder, 'TRANTUAN_MODEL.skp')
        return nil unless path
        path += '.skp' unless File.extname(path).downcase == '.skp'
        model.save(path)
      else
        model.save
      end
      raise 'Không lưu được file SKP hiện tại.' unless File.file?(model.path.to_s)
      model.path.to_s
    end

    def setup_a3(doc)
      info = doc.page_info
      info.width = A3_W
      info.height = A3_H
      margin = 10.0 / MM_PER_INCH
      info.left_margin = margin
      info.right_margin = margin
      info.top_margin = margin
      info.bottom_margin = margin
      info.show_margins = true
      info.print_margins = false
      info.output_resolution = Layout::PageInfo::RESOLUTION_HIGH
      doc.units = Layout::Document::DECIMAL_MILLIMETERS
      doc.precision = 0.1
    end

    def add_overview_page(doc, layer, model, skp_path, stats)
      page = doc.pages.first
      page.name = '01 - TỔNG THỂ'
      add_text(doc, layer, page, 'TRẦN TUẤN NỘI THẤT · PHỐI CẢNH TỔNG THỂ', 0.45, 0.30, 15.55, 0.55, 20, true, orange)
      add_text(doc, layer, page, "#{File.basename(skp_path)} · #{stats[:scope]}", 0.45, 0.82, 15.55, 0.35, 9.5, false, gray)

      bounds = Geom::Bounds2d.new(0.55, 1.25, 15.40, 8.60)
      viewport = Layout::SketchUpModel.new(skp_path, bounds)
      viewport.render_mode = Layout::SketchUpModel::HYBRID_RENDER
      viewport.display_background = false
      viewport.preserve_scale_on_resize = false
      scene_index = selected_scene_index(model)
      viewport.current_scene = scene_index + 1 if scene_index
      doc.add_entity(viewport, layer, page)

      summary = "THỐNG KÊ NHANH: #{stats[:total_pieces]} TẤM · #{stats[:total_types]} LOẠI · #{format('%.3f', stats[:total_area_m2])} m² · #{stats[:generated_at]}"
      add_text(doc, layer, page, summary, 0.55, 10.25, 15.40, 0.45, 11, true, dark)
      add_text(doc, layer, page, 'Trang thống kê chi tiết nằm ở các trang tiếp theo.', 0.55, 10.72, 15.40, 0.35, 9, false, gray)
    end

    def add_statistics_pages(doc, layer, stats)
      chunks = stats[:rows].each_slice(ROWS_PER_PAGE).to_a
      chunks = [[]] if chunks.empty?

      chunks.each_with_index do |chunk, page_index|
        page_number = page_index + 2
        page = doc.pages.add(format('%02d - THỐNG KÊ VÁN%s', page_number, page_index.zero? ? '' : " #{page_index + 1}"))
        add_text(doc, layer, page, 'BẢNG THỐNG KÊ VÁN', 0.45, 0.28, 15.55, 0.50, 19, true, orange)
        subtitle = "#{stats[:scope]} · #{stats[:total_pieces]} tấm · #{format('%.3f', stats[:total_area_m2])} m² · Trang #{page_index + 1}/#{chunks.length}"
        add_text(doc, layer, page, subtitle, 0.45, 0.80, 15.55, 0.35, 9.5, false, gray)
        add_stats_table(doc, layer, page, chunk)
        add_text(doc, layer, page, "TRẦN TUẤN NỘI THẤT · #{stats[:generated_at]}", 0.45, 11.08, 15.55, 0.30, 8.5, false, gray)
      end
    end

    def add_stats_table(doc, layer, page, rows)
      headers = ['STT', 'TÊN TẤM', 'DÀI', 'RỘNG', 'DÀY', 'SL', 'VẬT LIỆU', 'VÂN', 'm²']
      height = [9.55, 0.42 * (rows.length + 1)].min
      height = 1.0 if height < 1.0
      table = Layout::Table.new(Geom::Bounds2d.new(0.42, 1.25, 15.68, height), rows.length + 1, headers.length)

      headers.each_with_index do |value, column|
        table[0, column].data = table_text(value, true)
      end

      rows.each_with_index do |row, index|
        values = [
          row[:stt].to_s,
          row[:name].to_s,
          format_mm(row[:length_mm]),
          format_mm(row[:width_mm]),
          format_mm(row[:thickness_mm]),
          row[:qty].to_i.to_s,
          row[:material].to_s,
          row[:grain].to_s,
          format('%.3f', row[:area_m2].to_f)
        ]
        values.each_with_index do |value, column|
          table[index + 1, column].data = table_text(value, false)
        end
      end

      begin
        widths = [0.55, 4.05, 1.20, 1.20, 0.95, 0.65, 3.45, 1.20, 1.05]
        widths.each_with_index { |width, index| table.get_column(index).width = width }
      rescue StandardError
        nil
      end

      doc.add_entity(table, layer, page)
    end

    def table_text(text, header)
      value = text.to_s
      value = ' ' if value.empty?
      item = Layout::FormattedText.new(value, Geom::Point2d.new(0, 0), Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
      style = item.style(0)
      style.font_family = 'Arial'
      style.font_size = header ? 9.0 : 8.5
      style.text_bold = header
      style.text_color = header ? Sketchup::Color.new(255, 255, 255) : dark
      if header
        style.solid_filled = true
        style.fill_color = Sketchup::Color.new(194, 65, 12)
      end
      item.apply_style(style, 0, value.length)
      item
    rescue StandardError
      Layout::FormattedText.new(value, Geom::Point2d.new(0, 0), Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
    end

    def add_text(doc, layer, page, text, x, y, width, height, font_size, bold, color)
      value = text.to_s
      entity = Layout::FormattedText.new(value, Geom::Bounds2d.new(x, y, width, height))
      style = entity.style(0)
      style.font_family = 'Arial'
      style.font_size = font_size.to_f
      style.text_bold = !!bold
      style.text_color = color
      entity.apply_style(style, 0, value.length)
      doc.add_entity(entity, layer, page)
      entity
    rescue StandardError => error
      puts "[TT LayoutStats text] #{error.class}: #{error.message}"
      nil
    end

    def selected_scene_index(model)
      selected = model.pages.selected_page
      return nil unless selected
      index = nil
      model.pages.each_with_index do |page, i|
        if page == selected
          index = i
          break
        end
      end
      index
    rescue StandardError
      nil
    end

    def format_mm(value)
      n = value.to_f
      ((n - n.round).abs < 0.05) ? n.round.to_s : format('%.1f', n)
    end

    def orange; Sketchup::Color.new(234, 88, 12); end
    def dark; Sketchup::Color.new(31, 41, 55); end
    def gray; Sketchup::Color.new(107, 114, 128); end
  end
end
