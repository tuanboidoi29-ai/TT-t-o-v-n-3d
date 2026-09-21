# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  module TamPro
    extend self

    VERSION = '1.9.102'.freeze
    EPS = 0.001

    def model
      Sketchup.active_model
    end

    def valid_object?(entity)
      entity && entity.valid? &&
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
    rescue StandardError
      false
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

    def local_dimensions_mm(entity)
      bounds = definition_bounds(entity)
      return nil unless bounds && bounds.valid?
      tr = entity.transformation
      scale = [tr.xaxis.length, tr.yaxis.length, tr.zaxis.length]
      [bounds.width, bounds.height, bounds.depth].each_with_index.map do |len, index|
        (len.to_f * scale[index].to_f).to_mm
      end
    rescue StandardError
      nil
    end

    def thickness_info(entity)
      dims = local_dimensions_mm(entity)
      return nil unless dims && dims.all? { |v| v.finite? && v > EPS }
      axis = (0..2).min_by { |i| dims[i] }
      { axis: axis, thickness: dims[axis], dims: dims }
    end

    def scan_objects
      result = []
      seen_entities = {}
      seen_definitions = {}
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
          dkey = definition.object_id
          next if seen_definitions[dkey]
          seen_definitions[dkey] = true
          stack << definition.entities
        end
      end
      result
    end

    def selected_objects
      model.selection.to_a.select { |e| valid_object?(e) }
    end

    def format_mm(value)
      format('%.2f', value.to_f).sub(/\.00\z/, '').sub(/(\.\d)0\z/, '\\1')
    end

    def find_and_edit_thickness
      all = scan_objects
      rows = all.map { |e| [e, thickness_info(e)] }.select { |_e, info| info }
      if rows.empty?
        UI.messagebox('Không tìm thấy Group/Component có kích thước hợp lệ trong model.')
        return
      end

      selected = selected_objects
      source_default = selected.empty? ? 'Toàn model' : 'Đang chọn'
      values = rows.map { |_e, info| (info[:thickness] * 10.0).round / 10.0 }.uniq.sort
      default_thickness = values.include?(17.5) ? 17.5 : values.first
      list_thickness = values.map { |v| format_mm(v) }.join('|')

      prompts = ['Phạm vi', 'Độ dày cần tìm (mm)', 'Độ dày mới (mm, 0 = chỉ tìm)', 'Sai số nhận diện (mm)']
      defaults = [source_default, default_thickness, 0.0, 0.15]
      lists = ['Đang chọn|Toàn model', list_thickness, '', '']
      answer = UI.inputbox(prompts, defaults, lists, 'TT - Tìm tấm / Sửa độ dày')
      return unless answer

      scope, target_mm, new_mm, tolerance = answer
      target_mm = target_mm.to_f
      new_mm = new_mm.to_f
      tolerance = [tolerance.to_f.abs, 0.01].max
      pool = scope.to_s == 'Đang chọn' ? selected_objects : all

      matches = pool.select do |entity|
        info = thickness_info(entity)
        info && (info[:thickness] - target_mm).abs <= tolerance
      end

      if matches.empty?
        UI.messagebox("Không tìm thấy tấm dày #{format_mm(target_mm)} mm trong phạm vi đã chọn.")
        return
      end

      highlight_entities(matches)

      if new_mm > EPS
        changed = change_thickness(matches, new_mm)
        UI.messagebox("Đã đổi độ dày #{changed}/#{matches.length} tấm sang #{format_mm(new_mm)} mm.\nCó thể Ctrl+Z để hoàn tác.")
      else
        UI.messagebox("Đã tìm thấy #{matches.length} tấm dày #{format_mm(target_mm)} mm.\nCác đối tượng chọn được đã được highlight trong SketchUp.")
      end
    rescue StandardError => error
      UI.messagebox("Lỗi Tìm tấm / Sửa độ dày:\n#{error.message}")
    end

    def highlight_entities(entities)
      selection = model.selection
      selection.clear
      entities.each do |entity|
        begin
          selection.add(entity)
        rescue StandardError
        end
      end
      model.active_view.zoom(selection) unless selection.empty?
      true
    rescue StandardError
      false
    end

    def change_thickness(entities, new_mm)
      model.start_operation('TT - Đổi độ dày tấm', true)
      changed = 0
      entities.each do |entity|
        info = thickness_info(entity)
        next unless info
        current = info[:thickness].to_f
        next if current <= EPS
        ratio = new_mm.to_f / current
        next unless ratio.finite? && ratio > EPS

        bounds = definition_bounds(entity)
        next unless bounds
        axis = info[:axis]
        sx = axis == 0 ? ratio : 1.0
        sy = axis == 1 ? ratio : 1.0
        sz = axis == 2 ? ratio : 1.0
        local_scale = Geom::Transformation.scaling(bounds.min, sx, sy, sz)
        entity.transformation = entity.transformation * local_scale
        changed += 1
      end
      model.commit_operation
      changed
    rescue StandardError
      model.abort_operation rescue nil
      raise
    end

    def rename_objects
      targets = selected_objects
      if targets.empty?
        UI.messagebox('Hãy chọn một hoặc nhiều Group/Component. Giữ Ctrl trong SketchUp để chọn nhiều đối tượng.')
        return
      end

      prompts = ['Tên mới', 'Tiền tố', 'Hậu tố', 'Đánh số khi chọn nhiều']
      defaults = [targets.length == 1 ? entity_name(targets.first) : '', '', '', 'Có']
      lists = ['', '', '', 'Có|Không']
      answer = UI.inputbox(prompts, defaults, lists, 'TT - Đổi tên tấm / Group / Component')
      return unless answer

      base, prefix, suffix, numbering = answer
      base = base.to_s.strip
      prefix = prefix.to_s
      suffix = suffix.to_s
      use_number = numbering.to_s == 'Có' && targets.length > 1

      model.start_operation('TT - Đổi tên tấm', true)
      targets.each_with_index do |entity, index|
        core = base.empty? ? entity_name(entity) : base
        core = '' if core == '(Chưa đặt tên)'
        serial = use_number ? format('_%02d', index + 1) : ''
        name = "#{prefix}#{core}#{serial}#{suffix}".strip
        name = "Đối tượng#{serial}" if name.empty?
        entity.name = name
      end
      model.commit_operation
      UI.messagebox("Đã đổi tên #{targets.length} đối tượng. Có thể Ctrl+Z để hoàn tác.")
    rescue StandardError => error
      model.abort_operation rescue nil
      UI.messagebox("Lỗi đổi tên:\n#{error.message}")
    end

    def parent_entities(entity)
      parent = entity.parent
      return parent.entities if parent.respond_to?(:entities)
      model.active_entities
    rescue StandardError
      model.active_entities
    end

    def copy_instance_properties(source, target)
      target.name = source.name if target.respond_to?(:name=) && source.respond_to?(:name)
      target.layer = source.layer if target.respond_to?(:layer=) && source.respond_to?(:layer)
      target.material = source.material if target.respond_to?(:material=) && source.respond_to?(:material)
      target.hidden = source.hidden? if target.respond_to?(:hidden=) && source.respond_to?(:hidden?)
      if source.respond_to?(:attribute_dictionaries) && source.attribute_dictionaries
        source.attribute_dictionaries.each do |dict|
          dict.each_pair { |key, value| target.set_attribute(dict.name, key, value) }
        end
      end
      target
    rescue StandardError
      target
    end

    def component_to_group(instance)
      entities = parent_entities(instance)
      group = entities.add_group
      inner = group.entities.add_instance(instance.definition, IDENTITY)
      inner.explode
      group.transformation = instance.transformation
      copy_instance_properties(instance, group)
      instance.erase!
      group
    end

    def convert_objects
      selection = model.selection.to_a
      counts = {
        component: selection.count { |e| e.is_a?(Sketchup::ComponentInstance) },
        group: selection.count { |e| e.is_a?(Sketchup::Group) },
        face: selection.count { |e| e.is_a?(Sketchup::Face) }
      }
      if counts.values.sum.zero?
        UI.messagebox('Hãy chọn Component, Group hoặc Face cần chuyển đổi.')
        return
      end

      actions = 'Component → Group|Group → Component|Face → Group'
      message = "Đang chọn: #{counts[:component]} Component · #{counts[:group]} Group · #{counts[:face]} Face"
      answer = UI.inputbox(['Kiểu chuyển đổi', 'Thông tin'], ['Component → Group', message], [actions, ''], 'TT - Chuyển đổi đối tượng')
      return unless answer
      action = answer[0].to_s

      model.start_operation("TT - #{action}", true)
      created = []

      case action
      when 'Component → Group'
        selection.select { |e| e.is_a?(Sketchup::ComponentInstance) && e.valid? }.each do |instance|
          created << component_to_group(instance)
        end
      when 'Group → Component'
        selection.select { |e| e.is_a?(Sketchup::Group) && e.valid? }.each do |group|
          old_name = group.name.to_s
          instance = group.to_component
          instance.name = old_name unless old_name.empty?
          created << instance
        end
      when 'Face → Group'
        faces = selection.select { |e| e.is_a?(Sketchup::Face) && e.valid? }
        active = model.active_entities
        faces = faces.select { |face| face.parent == active }
        unless faces.empty?
          items = faces.flat_map { |face| [face] + face.edges }.uniq
          group = active.add_group(items)
          group.name = 'Face Group'
          created << group
        end
      end

      model.selection.clear
      created.each { |entity| model.selection.add(entity) if entity && entity.valid? rescue nil }
      model.commit_operation
      UI.messagebox("Đã chuyển đổi #{created.length} đối tượng. Có thể Ctrl+Z để hoàn tác.")
    rescue StandardError => error
      model.abort_operation rescue nil
      UI.messagebox("Lỗi chuyển đổi:\n#{error.message}")
    end

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
      rename_cmd.status_bar_text = 'Đổi tên một hoặc nhiều Group/Component, hỗ trợ tiền tố/hậu tố/đánh số.'

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
      toolbar.add_separator rescue nil
      commands.each_value { |command| toolbar.add_item(command) }
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
  end
end
