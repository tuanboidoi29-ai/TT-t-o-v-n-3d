# encoding: UTF-8
require 'sketchup.rb'

module TranTuanNoiThat
  module DonDimLine
    extend self

    NAME = 'TT - Dọn DIM + Line'
    VERSION = '1.0.4'

    DIM_KEYWORDS = [
      'dim', 'dimension', 'dimensions', 'kich thuoc', 'kích thước',
      'cote', 'cotation', 'annotation', 'annotations', 'anno'
    ].freeze

    def model
      Sketchup.active_model
    end

    # Nhận DIM native của SketchUp, kể cả khi nằm sâu trong Group/Component.
    def dimension_entity?(entity)
      return false unless entity && entity.valid?
      return true if defined?(Sketchup::DimensionLinear) && entity.is_a?(Sketchup::DimensionLinear)
      return true if defined?(Sketchup::DimensionRadial) && entity.is_a?(Sketchup::DimensionRadial)
      return true if defined?(Sketchup::DimensionAngular) && entity.is_a?(Sketchup::DimensionAngular)

      begin
        entity.typename.to_s.start_with?('Dimension')
      rescue
        false
      end
    end

    def normalize_name(value)
      value.to_s.downcase.tr('_-', '  ').gsub(/\s+/, ' ').strip
    rescue
      value.to_s
    end

    def dim_keyword?(value)
      text = normalize_name(value)
      return false if text.empty?
      DIM_KEYWORDS.any? do |word|
        w = normalize_name(word)
        text == w || text.start_with?("#{w} ") || text.end_with?(" #{w}") || text.include?(" #{w} ")
      end
    end

    def entity_layer_name(entity)
      return '' unless entity.respond_to?(:layer) && entity.layer
      entity.layer.name.to_s
    rescue
      ''
    end

    # Group/Component DIM cứng thường mang tên/tag DIM, DIMENSION, KICH THUOC...
    def named_dimension_container?(entity)
      return false unless entity && entity.valid?
      names = []
      names << entity.name.to_s if entity.respond_to?(:name)
      names << entity_layer_name(entity)
      if entity.is_a?(Sketchup::ComponentInstance)
        names << entity.definition.name.to_s if entity.definition
      elsif entity.is_a?(Sketchup::Group)
        begin
          names << entity.entities.parent.name.to_s if entity.entities.respond_to?(:parent)
        rescue
        end
      end
      names.any? { |name| dim_keyword?(name) }
    rescue
      false
    end

    def text_entity?(entity)
      defined?(Sketchup::Text) && entity.is_a?(Sketchup::Text)
    end

    # Kiểm tra Group chỉ chứa dữ liệu chú thích (line/text/dim), không có Face.
    # Đây là dạng thường gặp khi DIM đã bị explode / import từ CAD thành "DIM cứng".
    def annotation_only_container?(container, depth = 0)
      return false if depth > 12
      entities = if container.is_a?(Sketchup::Group)
                   container.entities
                 elsif container.is_a?(Sketchup::ComponentInstance)
                   container.definition.entities
                 else
                   return false
                 end

      has_content = false
      has_text_or_dim = false

      entities.each do |entity|
        next unless entity && entity.valid?

        if dimension_entity?(entity)
          has_content = true
          has_text_or_dim = true
          next
        end

        if text_entity?(entity)
          has_content = true
          has_text_or_dim = true
          next
        end

        if entity.is_a?(Sketchup::Face)
          return false
        end

        if entity.is_a?(Sketchup::Edge)
          has_content = true
          next
        end

        if defined?(Sketchup::ConstructionLine) && entity.is_a?(Sketchup::ConstructionLine)
          has_content = true
          next
        end

        if defined?(Sketchup::ConstructionPoint) && entity.is_a?(Sketchup::ConstructionPoint)
          has_content = true
          next
        end

        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          if named_dimension_container?(entity) || annotation_only_container?(entity, depth + 1)
            has_content = true
            has_text_or_dim = true
            next
          end
          return false
        end

        # Gặp loại hình học khác => không đoán là DIM để tránh xóa nhầm.
        return false
      end

      has_content && has_text_or_dim
    rescue
      false
    end

    def hard_dimension_container?(entity)
      return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      named_dimension_container?(entity) || annotation_only_container?(entity)
    end

    def line_thua?(entity)
      return false unless entity && entity.valid?
      return true if defined?(Sketchup::ConstructionLine) && entity.is_a?(Sketchup::ConstructionLine)
      return false unless entity.is_a?(Sketchup::Edge)
      # Chỉ xóa Edge không tham gia tạo Face để không phá tường/cửa.
      entity.faces.empty?
    end

    def dimension_annotation_entity?(entity)
      return false unless entity && entity.valid?
      return true if dimension_entity?(entity)

      # Text/line nằm trên Tag DIM cũng được xem là chú thích DIM cứng.
      if dim_keyword?(entity_layer_name(entity))
        return true if text_entity?(entity)
        return true if entity.is_a?(Sketchup::Edge) && entity.faces.empty?
        return true if defined?(Sketchup::ConstructionLine) && entity.is_a?(Sketchup::ConstructionLine)
        return true if defined?(Sketchup::ConstructionPoint) && entity.is_a?(Sketchup::ConstructionPoint)
      end

      false
    rescue
      false
    end

    def container?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end
    def contents(e)
      e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    end
    def protected_geometry?(container, depth=0)
      return true if depth>64
      contents(container).any? do |e|
        e.valid? && (e.is_a?(Sketchup::Face) || (e.respond_to?(:locked?) && e.locked?) || (container?(e) && protected_geometry?(e,depth+1)))
      end
    end
    def cleanup(entities, stats, loose, depth=0, inherited_dim=false, keep_roots=false)
      raise 'Group lồng quá 64 cấp; đã hủy lượt dọn.' if depth>64
      entities.to_a.each do |e|
        next unless e && e.valid?
        next if e.respond_to?(:locked?) && e.locked?
        if container?(e)
          is_dim=inherited_dim || named_dimension_container?(e)
          if is_dim && !keep_roots && !protected_geometry?(e)
            e.erase!;stats[:groups]+=1
          else
            # Isolate before editing nested definitions, including copied Groups.
            e.make_unique
            cleanup(contents(e),stats,loose,depth+1,is_dim,false)
          end
        elsif dimension_entity?(e)
          e.erase!;stats[:native]+=1
        elsif dimension_annotation_entity?(e) || (inherited_dim && (text_entity?(e) || line_thua?(e)))
          e.erase!;stats[:hard]+=1
        elsif loose && line_thua?(e)
          e.erase!;stats[:lines]+=1
        end
      end
    end
    def run
      m=model;roots=m.selection.to_a
      choices=UI.inputbox(['Phạm vi','Xóa thêm nét rời không tạo mặt'],[roots.empty? ? 'Toàn ngữ cảnh hiện tại' : 'Vùng chọn','Không'],['Vùng chọn|Toàn ngữ cảnh hiện tại','Không|Có'],NAME)
      return unless choices
      if choices[0]=='Vùng chọn' && roots.empty?
        UI.messagebox('Chọn đối tượng cần dọn trước.');return
      end
      selected=choices[0]=='Vùng chọn'
      roots=m.active_entities.to_a unless selected
      stats={native:0,hard:0,groups:0,lines:0}
      m.start_operation(NAME,true)
      begin
        cleanup(roots,stats,choices[1]=='Có',0,false,selected)
        m.commit_operation
      rescue StandardError=>e
        m.abort_operation;UI.messagebox("Đã hủy lượt dọn: #{e.message}");return
      end
      UI.messagebox("Đã dọn:\nDIM SketchUp: #{stats[:native]}\nNhóm DIM cứng: #{stats[:groups]}\nNét/chữ DIM: #{stats[:hard]}\nNét rời: #{stats[:lines]}\nCtrl+Z hoàn tác toàn bộ lượt dọn.")
    end
  end
end
