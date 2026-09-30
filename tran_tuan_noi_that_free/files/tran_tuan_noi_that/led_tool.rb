# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require 'fileutils'

module TranTuanNoiThat
  module LedTool
    extend self

    VERSION = '1.4.7'.freeze
    KEY = 'TT_LED'.freeze
    DATA_DIR = File.join(TranTuanNoiThat::ROOT, 'data', 'led_tool').freeze
    PRESET_FILE = File.join(DATA_DIR, 'presets.json').freeze
    DEFAULT_PRESET = 'LED 10MM'.freeze
    DEFAULTS = {
      'name'=>'LED 10MM',
      'end_clearance'=>20.0,
      'edge_offset'=>30.0,
      'groove_width'=>10.0,
      'groove_length'=>0.0,
      'quantity'=>1,
      'spacing'=>50.0,
      'led_color'=>'#ffe08a',
      'brightness'=>100.0,
      'light_distance'=>80.0,
      'light_spread'=>40.0,
      'simulate'=>true,
      'cnc'=>true,
      'cnc_instance'=>'ABF_RANHLED',
      'cnc_tag'=>'ABF_ranhled'
    }.freeze

    def ensure_data
      FileUtils.mkdir_p(DATA_DIR)
      true
    end

    def normalize_instance(value)
      text = value.to_s.strip.upcase.gsub(/[^A-Z0-9_]+/,'_').gsub(/_+/,'_').sub(/\A_+/,'').sub(/_+\z/,'')
      text = 'RANHLED' if text.empty?
      text = 'ABF_' + text unless text.start_with?('ABF_')
      text
    end

    def normalize_tag(value)
      text = value.to_s.strip.gsub(/[^A-Za-z0-9_]+/,'_').gsub(/_+/,'_').sub(/\A_+/,'').sub(/_+\z/,'')
      text = 'ranhled' if text.empty?
      text = 'ABF_' + text unless text.downcase.start_with?('abf_')
      text
    end

    def normalize_color(value)
      text = value.to_s.strip
      text = '#ffd86a' unless text.match?(/\A#[0-9a-fA-F]{6}\z/)
      text.downcase
    end

    def normalize(raw)
      source = DEFAULTS.merge((raw || {}).transform_keys(&:to_s))
      out = source.dup
      out['name'] = source['name'].to_s.strip
      out['name'] = DEFAULTS['name'] if out['name'].empty?
      out['end_clearance'] = [[source['end_clearance'].to_f,0.0].max,5000.0].min
      out['edge_offset'] = [[source['edge_offset'].to_f,0.0].max,5000.0].min
      out['groove_width'] = [[source['groove_width'].to_f,0.5].max,200.0].min
      out['groove_length'] = [[source['groove_length'].to_f,0.0].max,100_000.0].min
      out['quantity'] = [[source['quantity'].to_i,1].max,20].min
      out['spacing'] = [[source['spacing'].to_f,0.0].max,5000.0].min
      out['led_color'] = normalize_color(source['led_color'])
      out['brightness'] = [[source['brightness'].to_f,0.0].max,200.0].min
      out['light_distance'] = [[source['light_distance'].to_f,0.0].max,1000.0].min
      out['light_spread'] = [[source['light_spread'].to_f,0.0].max,500.0].min
      out['simulate'] = source['simulate'] == true || source['simulate'].to_s == 'true' || source['simulate'].to_s == '1'
      out['cnc'] = source['cnc'] == true || source['cnc'].to_s == 'true' || source['cnc'].to_s == '1'
      out['cnc_instance'] = normalize_instance(source['cnc_instance'])
      out['cnc_tag'] = normalize_tag(source['cnc_tag'])
      out
    end

    def settings
      raw = Sketchup.read_default(KEY,'settings','{}')
      parsed = JSON.parse(raw.to_s)
      normalize(parsed)
    rescue StandardError
      DEFAULTS.dup
    end

    def save_settings(raw)
      clean = normalize(raw)
      Sketchup.write_default(KEY,'settings',JSON.generate(clean))
      clean
    end

    def custom_presets
      return {} unless File.file?(PRESET_FILE)
      data = JSON.parse(File.read(PRESET_FILE,encoding:'UTF-8'))
      return {} unless data.is_a?(Hash)
      data.each_with_object({}) do |(name,value),memo|
        memo[name.to_s] = normalize(value) if value.is_a?(Hash)
      rescue StandardError
        nil
      end
    rescue StandardError
      {}
    end

    def presets
      {DEFAULT_PRESET=>DEFAULTS.dup}.merge(custom_presets)
    end

    def save_preset(name, raw)
      clean = normalize(raw)
      title = name.to_s.strip
      title = clean['name'] if title.empty?
      raise 'Tên mẫu LED không được để trống.' if title.empty?
      rows = custom_presets
      rows[title] = clean.merge('name'=>title)
      ensure_data
      File.write(PRESET_FILE,JSON.pretty_generate(rows),encoding:'UTF-8')
      title
    end

    def delete_preset(name)
      title = name.to_s
      raise 'Không xóa mẫu mặc định LED 10MM.' if title == DEFAULT_PRESET
      rows = custom_presets
      rows.delete(title)
      ensure_data
      File.write(PRESET_FILE,JSON.pretty_generate(rows),encoding:'UTF-8')
      true
    end

    def groove_plan(length_mm,width_mm,raw,side = :min)
      opts = normalize(raw)
      length = length_mm.to_f
      width = width_mm.to_f
      raise 'Mặt phải có chiều dài và chiều rộng lớn hơn 0.' unless length > 0 && width > 0

      end_gap = opts['end_clearance']
      groove_w = opts['groove_width']
      edge = opts['edge_offset']
      available_l = length - 2.0*end_gap
      available_w = width - edge - groove_w
      raise 'Cách 2 đầu quá lớn so với chiều dài mặt.' unless available_l > 0
      raise 'Cách mép ngoài + độ rộng rãnh vượt quá chiều rộng mặt.' unless available_w >= -1.0e-6

      requested = opts['groove_length']
      groove_l = requested > 0 ? [requested,available_l].min : available_l
      u0 = end_gap + (available_l-groove_l)/2.0
      u1 = u0 + groove_l
      if side.to_sym == :max
        v1 = width - edge
        v0 = v1 - groove_w
      else
        v0 = edge
        v1 = v0 + groove_w
      end
      {
        u0:u0,u1:u1,v0:v0,v1:v1,
        length:groove_l,width:groove_w,
        side:side.to_sym,auto_length:requested <= 0
      }
    end

    def groove_plans(length_mm,width_mm,raw,side = :min)
      opts = normalize(raw)
      base = groove_plan(length_mm,width_mm,opts,side)
      count = opts['quantity']
      gap = opts['spacing']
      groove_w = base[:width]
      total_width = count*groove_w + (count-1)*gap
      required = opts['edge_offset'] + total_width
      if required > width_mm.to_f + 1.0e-6
        raise "Số lượng #{count} rãnh + khoảng cách giữa vượt bề rộng mặt."
      end

      Array.new(count) do |index|
        shift = index*(groove_w+gap)
        plan = base.dup
        if side.to_sym == :max
          plan[:v0] = base[:v0]-shift
          plan[:v1] = base[:v1]-shift
        else
          plan[:v0] = base[:v0]+shift
          plan[:v1] = base[:v1]+shift
        end
        plan[:index] = index
        plan[:count] = count
        plan[:spacing] = gap
        plan
      end
    end

    def color_from_hex(hex, alpha = 255)
      text = normalize_color(hex).delete_prefix('#')
      Sketchup::Color.new(text[0,2].to_i(16),text[2,2].to_i(16),text[4,2].to_i(16),alpha)
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def target_entities(target)
      target.respond_to?(:entities) ? target.entities : target.definition.entities
    end

    def entity_reference_id(entity)
      return entity.persistent_id if entity.respond_to?(:persistent_id)
      return entity.entityID if entity.respond_to?(:entityID)
      entity.object_id
    rescue StandardError
      entity.object_id
    end

    def operation_setting_name(tag_name)
      tag_name.to_s.sub(/\AABF_/,'').tr('_',' ').downcase.strip
    end

    def ensure_tag(model,name)
      model.layers[name] || model.layers.add(name)
    end

    def point_uv(origin,u,v,uu,vv,normal = nil,normal_offset = 0.0)
      n = normal || Geom::Vector3d.new(0,0,0)
      Geom::Point3d.new(
        origin.x + u.x*uu + v.x*vv + n.x*normal_offset,
        origin.y + u.y*uu + v.y*vv + n.y*normal_offset,
        origin.z + u.z*uu + v.z*vv + n.z*normal_offset
      )
    end

    def analyze_face(face)
      verts = face.outer_loop.vertices.map(&:position)
      raise 'Face cần ít nhất 3 đỉnh.' if verts.length < 3
      pairs = verts.each_with_index.map { |point,index| [point,verts[(index+1)%verts.length]] }
      a,b = pairs.max_by { |p,q| p.distance(q) }
      u = a.vector_to(b)
      raise 'Không xác định được trục dài của mặt.' if u.length <= 1.0e-9
      u = u.normalize
      normal = face.normal
      normal = normal.normalize
      v = normal.cross(u)
      raise 'Không xác định được trục ngang của mặt.' if v.length <= 1.0e-9
      v = v.normalize
      origin = verts.first
      us = verts.map { |p| origin.vector_to(p).dot(u) }
      vs = verts.map { |p| origin.vector_to(p).dot(v) }
      min_u,max_u = us.minmax
      min_v,max_v = vs.minmax
      len = max_u-min_u
      wid = max_v-min_v

      if wid > len
        u,v = v,u
        min_u,max_u = vs.minmax
        min_v,max_v = us.minmax
        len,wid = wid,len
      end
      {
        origin:origin,u:u,v:v,normal:normal,
        min_u:min_u,max_u:max_u,min_v:min_v,max_v:max_v,
        length_mm:len.to_f*25.4,width_mm:wid.to_f*25.4
      }
    end

    def local_rect(analysis,plan,normal_offset_mm = 0.0, width_scale = 1.0)
      center_v = (plan[:v0]+plan[:v1])/2.0
      half = plan[:width]*width_scale/2.0
      v0 = center_v-half
      v1 = center_v+half
      base_u = analysis[:min_u].to_f*25.4
      base_v = analysis[:min_v].to_f*25.4
      uu0 = (base_u+plan[:u0]).mm
      uu1 = (base_u+plan[:u1]).mm
      vv0 = (base_v+v0).mm
      vv1 = (base_v+v1).mm
      off = normal_offset_mm.to_f.mm
      [
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu0,vv0,analysis[:normal],off),
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu1,vv0,analysis[:normal],off),
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu1,vv1,analysis[:normal],off),
        point_uv(analysis[:origin],analysis[:u],analysis[:v],uu0,vv1,analysis[:normal],off)
      ]
    end

    def find_host_face(target, local_points)
      target_entities(target).grep(Sketchup::Face).select do |face|
        begin
          local_points.all? { |point| point.distance_to_plane(face.plane).abs <= 0.2.mm }
        rescue StandardError
          false
        end
      end.max_by { |face| face.area.to_f }
    end

    def face_entities(host_face,target)
      parent = host_face.respond_to?(:parent) ? host_face.parent : nil
      return parent if parent && parent.respond_to?(:add_line) && parent.respond_to?(:grep)
      target_entities(target)
    end

    def heal_profile_face(entities,edges,points,instance_name,tag_name)
      # Ép loop CNC trở thành biên thật thuộc Face của tấm.
      # add_line đơn thuần đôi khi để lại loose edge đồng phẳng, Aspire/ABF không nhận.
      edges.each do |edge|
        begin
          edge.find_faces if edge.respond_to?(:find_faces)
        rescue StandardError
          nil
        end
      end

      attached = edges.all? do |edge|
        edge.respond_to?(:faces) && !edge.faces.empty?
      end
      profile_faces = edges.flat_map { |edge| edge.respond_to?(:faces) ? edge.faces : [] }.compact.uniq
      loop_face = profile_faces.find do |face|
        begin
          face_edges = face.edges.to_a
          edges.all? { |edge| face_edges.include?(edge) }
        rescue StandardError
          false
        end
      end

      unless attached && loop_face
        begin
          face = entities.add_face(points)
          if face && (!face.respond_to?(:valid?) || face.valid?)
            face.set_attribute(KEY,'role','led_profile_face')
            face.set_attribute(KEY,'cnc_name',instance_name)
            face.set_attribute(KEY,'cnc_tag',tag_name)
            face.set_attribute('ABF','instance',instance_name)
            face.set_attribute('ABF','instance-name',instance_name)
            face.set_attribute('ABF','is-cnced-face',true)
            face.edges.each do |edge|
              edge.set_attribute(KEY,'role','led_cnc_edge')
              edge.set_attribute(KEY,'cnc_name',instance_name)
              edge.set_attribute(KEY,'cnc_tag',tag_name)
              edge.set_attribute('ABF','instance',instance_name)
              edge.set_attribute('ABF','instance-name',instance_name)
            end
          end
        rescue StandardError
          nil
        end

        edges.each do |edge|
          begin
            edge.find_faces if edge.respond_to?(:find_faces)
          rescue StandardError
            nil
          end
        end
      end

      attached = edges.all? do |edge|
        edge.respond_to?(:faces) && !edge.faces.empty?
      end
      profile_faces = edges.flat_map { |edge| edge.respond_to?(:faces) ? edge.faces : [] }.compact.uniq
      loop_face = profile_faces.find do |face|
        begin
          face_edges = face.edges.to_a
          edges.all? { |edge| face_edges.include?(edge) }
        rescue StandardError
          false
        end
      end

      raise "Biên dạng #{tag_name} chưa ăn vào Face thật của tấm." unless attached
      raise "Biên dạng #{tag_name} chưa tạo được loop Face kín thật." unless loop_face

      # Face nhỏ bên trong loop được giữ lại: đây là phần mặt rãnh thật,
      # giúp biên CNC tồn tại như topology của chính tấm, không phải line rời.
      profile_faces.each do |face|
        begin
          face.set_attribute('ABF','is-cnced-face',true)
          face.set_attribute(KEY,'led_profile_boundary',true)
          face.set_attribute(KEY,'cnc_name',instance_name)
          face.set_attribute(KEY,'cnc_tag',tag_name)
          face.set_attribute('ABF','instance',instance_name)
          face.set_attribute('ABF','instance-name',instance_name)
        rescue StandardError
          nil
        end
      end
      profile_faces
    end

    def add_abf_profile(target,host_face,points,opts,profile_index = 0,profile_count = 1)
      model = Sketchup.active_model
      instance_name = normalize_instance(opts['cnc_instance'])
      tag_name = normalize_tag(opts['cnc_tag'])
      tag = ensure_tag(model,tag_name)
      tag.visible = true if tag.respond_to?(:visible=)
      entities = face_entities(host_face,target)

      # QUY TẮC CỐ ĐỊNH:
      # Biên dạng rãnh LED phải nằm trực tiếp trong hình học của Group/Component.
      # Không tạo Group con cho CNC.
      raise 'Face gia công không hợp lệ.' unless host_face && host_face.valid?
      host_face.set_attribute('ABF','is-cnced-face',true)
      target.set_attribute(KEY,'led_face_direct',true)

      edges = points.each_with_index.map do |point,index|
        nxt = points[(index+1) % points.length]
        edge = entities.add_line(point,nxt)
        raise "Không tạo được cạnh CNC rãnh LED số #{index+1}." unless edge && edge.valid?
        edge.layer = tag
        edge.set_attribute('ABF','is-cutting-lines',true)
        edge.set_attribute('ABF','is-intersect',true)
        edge.set_attribute('ABF','setting-name',operation_setting_name(instance_name))
        edge.set_attribute('ABF','operation-name',instance_name)
        edge.set_attribute('ABF','instance',instance_name)
        edge.set_attribute('ABF','instance-name',instance_name)
        edge.set_attribute('ABF','tag-name',tag_name)
        edge.set_attribute('ABF','intersect-group-b-id',entity_reference_id(target))
        edge.set_attribute(KEY,'role','led_cnc_edge')
        edge.set_attribute(KEY,'name',opts['name'])
        edge.set_attribute(KEY,'cnc_name',instance_name)
        edge.set_attribute(KEY,'cnc_instance',instance_name)
        edge.set_attribute(KEY,'cnc_tag',tag_name)
        edge.set_attribute(KEY,'groove_width_mm',opts['groove_width'])
        edge.set_attribute(KEY,'closed_loop',true)
        edge.set_attribute(KEY,'profile_index',profile_index)
        edge.set_attribute(KEY,'profile_count',profile_count)
        edge.set_attribute(KEY,'spacing_mm',opts['spacing'])
        edge
      end.compact.uniq

      raise "Biên dạng #{tag_name} phải có đúng 4 Edge kín." unless edges.length == 4

      # BẮT BUỘC: 4 Edge phải trở thành topology thật của Face, không được là loose edge.
      profile_faces = heal_profile_face(entities,edges,points,instance_name,tag_name)

      # Đánh dấu lại tất cả Face cùng mặt phẳng sau khi split/heal.
      refreshed_face = find_host_face(target,points)
      refreshed_face.set_attribute('ABF','is-cnced-face',true) if refreshed_face && refreshed_face.valid?

      edges.each do |edge|
        edge.set_attribute(KEY,'embedded_face_count',edge.faces.length) if edge.respond_to?(:faces)
      end
      target.set_attribute(KEY,'led_profile_face_count',profile_faces.length)
      target.set_attribute('ABF','is-board',true)
      target.set_attribute('ABF','ranh_led',true)
      target.set_attribute('ABF','instance',instance_name)
      target.set_attribute('ABF','instance-name',instance_name)
      target.set_attribute('ABF','tag-name',tag_name)
      target.set_attribute(KEY,'cnc_name',instance_name)
      target.set_attribute(KEY,'cnc_instance',instance_name)
      target.set_attribute(KEY,'cnc_tag',tag_name)
      target.set_attribute(KEY,'led_profile_embedded',true)
      target.set_attribute(KEY,'led_profile_grouped',false)
      target.set_attribute(KEY,'led_last_profile_count',profile_count)
      target.set_attribute(KEY,'led_last_cnc_edge_count',profile_count*4)
      edges
    end

    def midpoint(a,b)
      Geom::Point3d.new(
        (a.x+b.x)/2.0,
        (a.y+b.y)/2.0,
        (a.z+b.z)/2.0
      )
    end

    def unit_vector(vector,fallback = nil)
      return vector.normalize if vector.respond_to?(:normalize) && vector.length > 1.0e-9
      return fallback.normalize if fallback && fallback.respond_to?(:normalize) && fallback.length > 1.0e-9
      Geom::Vector3d.new(1,0,0)
    end

    def shift_point(point,vector,distance)
      direction = unit_vector(vector)
      Geom::Point3d.new(
        point.x + direction.x*distance,
        point.y + direction.y*distance,
        point.z + direction.z*distance
      )
    end

    def reverse_vector(vector)
      Geom::Vector3d.new(-vector.x.to_f,-vector.y.to_f,-vector.z.to_f)
    end

    # Hướng hắt luôn vuông góc với thanh LED và đi VÀO TRONG từ mép đang bám.
    # side=:min  -> +V ; side=:max -> -V.
    # Vì V nằm trên chính mặt gia công nên LED dọc/ngang tự xoay hướng sáng theo mặt.
    def light_direction(analysis,plan)
      direction = plan[:side].to_sym == :max ? reverse_vector(analysis[:v]) : analysis[:v]
      unit_vector(direction)
    end

    # Ưu tiên ánh sáng CHIẾU XUỐNG theo Model -Z.
    # Nếu thanh LED chạy gần song song với Z (LED dọc), chiếu thuần -Z sẽ
    # song song với chính thanh LED và quầng sáng bị suy biến. Khi đó thêm
    # thành phần hắt ra khỏi mặt để vẫn thấy vầng sáng nhưng hướng tổng thể
    # vẫn đi xuống.
    def light_direction_world(analysis,_plan,transform)
      down = Geom::Vector3d.new(0,0,-1)
      along = analysis[:u].transform(transform)
      along = unit_vector(along,Geom::Vector3d.new(1,0,0))
      parallel = along.dot(down).abs

      return down if parallel < 0.90

      normal = analysis[:normal].transform(transform)
      normal = unit_vector(normal,Geom::Vector3d.new(0,1,0))
      mixed = Geom::Vector3d.new(
        down.x*0.82 + normal.x*0.58,
        down.y*0.82 + normal.y*0.58,
        down.z*0.82 + normal.z*0.58
      )
      unit_vector(mixed,down)
    end

    # Vầng sáng mịn: chia thành nhiều dải alpha giảm dần.
    # cast_direction là hướng hắt thật trên mặt (không cố định Model -Z).
    def light_geometry(world_rect,raw,cast_direction = nil)
      opts = normalize(raw)
      return {levels:[],bands:[],beam_quads:[],direction:nil} unless opts['simulate']
      raise 'Cần 4 điểm rãnh LED để mô phỏng ánh sáng.' unless world_rect && world_rect.length == 4

      source_a = midpoint(world_rect[0],world_rect[3])
      source_b = midpoint(world_rect[1],world_rect[2])
      along = unit_vector(source_a.vector_to(source_b))
      cast = unit_vector(cast_direction || Geom::Vector3d.new(0,0,-1))

      distance = opts['light_distance'].mm
      spread = opts['light_spread'].mm
      brightness = opts['brightness']/100.0
      band_count = 72
      previous_a = source_a
      previous_b = source_b
      levels = []
      bands = []

      1.upto(band_count) do |index|
        fraction = index.to_f / band_count
        end_expand = spread * fraction
        center_a = shift_point(source_a,cast,distance*fraction)
        center_b = shift_point(source_b,cast,distance*fraction)
        current_a = shift_point(center_a,along,-end_expand)
        current_b = shift_point(center_b,along,end_expand)

        # 72 lớp + easing mượt để ánh vàng sáng tan mềm dần xuống dưới.
        falloff = (1.0-fraction)**2.25
        soft_edge = 0.86 + 0.14*Math.cos(fraction*Math::PI/2.0)
        alpha = [[(184.0*brightness*falloff*soft_edge).round,0].max,225].min
        bands << {
          fraction:fraction,
          alpha:alpha,
          points:[previous_a,previous_b,current_b,current_a]
        }
        levels << {
          fraction:fraction,
          alpha:alpha,
          line:[current_a,current_b]
        }
        previous_a = current_a
        previous_b = current_b
      end

      {
        levels:levels,
        bands:bands,
        beam_quads:bands,
        direction:cast
      }
    end

    def ensure_material(model,name,color,alpha)
      mats = model.materials
      material = mats[name] || mats.add(name)
      material.color = color if material.respond_to?(:color=)
      material.alpha = alpha if material.respond_to?(:alpha=)
      material
    end

    def add_triangle_face(entities,a,b,c)
      face = entities.add_face(a,b,c)
      return face if face && (!face.respond_to?(:valid?) || face.valid?)
      nil
    rescue StandardError
      nil
    end

    # Không dùng Face 4 điểm cho ánh sáng vì transform/scale của Group/Component
    # có thể tạo sai số rất nhỏ và SketchUp báo "Points are not planar".
    # Mỗi quad được tách thành 2 tam giác; 3 điểm luôn xác định một mặt phẳng.
    def add_safe_quad_faces(entities,points)
      return [] unless points && points.length == 4
      faces = []
      first = add_triangle_face(entities,points[0],points[1],points[2])
      second = add_triangle_face(entities,points[0],points[2],points[3])
      faces << first if first
      faces << second if second
      faces
    end

    def add_led_simulation(world_rect,target_tr,analysis,plan,opts,profile_index = 0,profile_count = 1)
      return nil unless opts['simulate']
      model = Sketchup.active_model
      group = model.active_entities.add_group
      group.name = "TT_LED_MO_PHONG_#{opts['name']}_#{profile_index+1}"
      group.layer = ensure_tag(model,'TT_LED_MO_PHONG')
      group.set_attribute(KEY,'role','led_simulation')
      group.set_attribute(KEY,'host_id',entity_reference_id(target_tr[:target]))
      group.set_attribute(KEY,'profile_index',profile_index)
      group.set_attribute(KEY,'profile_count',profile_count)
      group.set_attribute(KEY,'led_color',opts['led_color'])
      group.set_attribute(KEY,'brightness_percent',opts['brightness'])
      group.set_attribute(KEY,'light_distance_mm',opts['light_distance'])
      group.set_attribute(KEY,'light_spread_mm',opts['light_spread'])
      group.set_attribute(KEY,'light_side',plan[:side].to_s)

      active_inv = begin
        model.edit_transform.inverse
      rescue StandardError
        Geom::Transformation.new
      end

      direction = light_direction_world(analysis,plan,target_tr[:transform])
      geometry = light_geometry(world_rect,opts,direction)

      # Tim LED vàng sáng. Dùng 2 tam giác để không phát sinh "Points are not planar".
      core_pts = world_rect.map { |point| point.transform(active_inv) }
      core_faces = add_safe_quad_faces(group.entities,core_pts)
      core_mat = ensure_material(
        model,
        "TT_LED_CORE_#{opts['led_color'].delete_prefix('#')}",
        Sketchup::Color.new(255,250,222),
        [[opts['brightness']/100.0,0.0].max,1.0].min
      )
      core_faces.each do |face|
        face.material = core_mat
        face.back_material = core_mat if face.respond_to?(:back_material=)
        face.edges.each { |edge| edge.hidden = true if edge.respond_to?(:hidden=) }
      end

      # 72 dải trong suốt nối tiếp nhau tạo ánh vàng sáng mịn, không dùng quad 4 điểm.
      geometry[:bands].each_with_index do |band,index|
        next if band[:alpha] <= 0
        pts = band[:points].map { |point| point.transform(active_inv) }
        faces = add_safe_quad_faces(group.entities,pts)
        next if faces.empty?
        mat = ensure_material(
          model,
          "TT_LED_GLOW_#{opts['led_color'].delete_prefix('#')}_#{profile_index}_#{index}_#{band[:alpha]}",
          color_from_hex(opts['led_color']),
          band[:alpha]/255.0
        )
        faces.each do |face|
          face.material = mat
          face.back_material = mat if face.respond_to?(:back_material=)
          face.edges.each { |edge| edge.hidden = true if edge.respond_to?(:hidden=) }
        end
      end
      group
    end

    def send_dialog_state
      return unless @dialog && @dialog.visible?
      payload = {
        settings: @active_tool ? @active_tool.options : settings,
        presets: presets,
        selected: @current_preset.to_s
      }
      @dialog.execute_script("TTLED.load(#{JSON.generate(payload)})")
    rescue StandardError => error
      puts "[TT LED dialog state] #{error.class}: #{error.message}"
    end

    def send_detected(info)
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("TTLED.detected(#{JSON.generate(info || {})})")
    rescue StandardError
      nil
    end

    def dialog_html
      <<~'HTML'
      <!doctype html><html lang="vi"><head><meta charset="utf-8">
      <style>
      *{box-sizing:border-box}body{margin:0;font:13px Arial,sans-serif;background:#eef9f1;color:#234633}
      .head{background:#2f8f5b;color:#fff;padding:13px 16px;position:sticky;top:0;z-index:5}.head h2{margin:0;font-size:18px}.head small{opacity:.9}
      .layout{display:grid;grid-template-columns:220px 1fr;gap:10px;padding:10px}.panel{background:#dff4e7;border:1px solid #abd7ba;border-radius:10px;padding:11px}
      .left{min-height:500px}.title{font-weight:bold;color:#246b43;margin-bottom:8px}.preset{width:100%;text-align:left;margin:4px 0;padding:9px;border:1px solid #9cc9d9;background:#f6fff8;border-radius:7px;cursor:pointer}
      .preset.active{background:#bfeccc;border-color:#57ad75;font-weight:bold}.grid{display:grid;grid-template-columns:170px 1fr 44px;gap:7px;align-items:center}
      input,select{width:100%;padding:7px;border:1px solid #9bc8aa;border-radius:6px;background:white}input[type=checkbox]{width:auto}input[type=color]{height:35px;padding:2px}
      button{border:0;border-radius:7px;padding:9px 11px;background:#2f8f5b;color:white;font-weight:bold;cursor:pointer}.gray{background:#607d8b}.red{background:#b84b4b}.row{display:flex;gap:7px;margin-top:9px}.row button{flex:1}
      .detect{background:#f8fff9;border:1px dashed #7fbd94;padding:9px;border-radius:7px;margin-bottom:10px;line-height:1.55}.hint{font-size:12px;color:#52705e;line-height:1.5}
      .lightbox{margin-top:10px;background:#173326;border:1px solid #7fbd94;border-radius:8px;padding:8px}.lightbox canvas{display:block;width:100%;height:180px;border-radius:6px;background:#111812}.lightlabel{color:#e7f7ec;font-size:12px;margin-bottom:6px}.color-presets{display:flex;gap:6px;flex-wrap:wrap;margin:7px 0}.color-presets button{padding:6px 8px;font-size:11px;flex:0 0 auto}.createbtn{background:#e08b19;color:#fff;font-size:14px}.pickbtn{background:#168650;color:#fff;font-size:14px}
      #notice{min-height:20px;margin-top:8px;font-size:12px}.ok{color:#166534}.err{color:#a61b1b}
      </style></head><body>
      <div class="head"><h2>TẠO LED</h2><small>CHỌN TIẾP DIỆN → rê vào Face của Group/Component → preview rãnh + ánh sáng → click tạo liên tục</small></div>
      <div class="layout">
        <div class="panel left"><div class="title">MẪU ĐÃ LƯU</div><div id="presets"></div>
          <div class="row"><button onclick="savePreset()">LƯU MẪU</button></div>
          <div class="row"><button class="red" onclick="deletePreset()">XÓA MẪU</button></div>
          <div class="hint" style="margin-top:10px">Chọn mẫu bên trái: thông số và preview áp dụng ngay.</div>
        </div>
        <div class="panel">
          <div class="title">THÔNG SỐ RÃNH LED</div>
          <div class="detect"><b>TIẾP DIỆN ĐANG RÀ:</b> <span id="target">Chưa nhận</span><br><b>Kích thước mặt:</b> <span id="dims">-</span><br><b>Rãnh preview:</b> <span id="groove">-</span></div>
          <div class="grid">
            <label>Tên mẫu / rãnh</label><input id="name"><span></span>
            <label>Cách 2 đầu</label><input id="end_clearance" type="number" min="0" step="0.5"><span>mm</span>
            <label>Cách mép ngoài</label><input id="edge_offset" type="number" min="0" step="0.5"><span>mm</span>
            <label>Độ rộng rãnh LED</label><input id="groove_width" type="number" min="0.5" step="0.5"><span>mm</span>
            <label>Chiều dài rãnh</label><input id="groove_length" type="number" min="0" step="1"><span>mm</span>
            <label>Số lượng rãnh</label><input id="quantity" type="number" min="1" max="20" step="1"><span>cái</span>
            <label>Khoảng cách giữa</label><input id="spacing" type="number" min="0" step="1"><span>mm</span>
            <label>Màu LED mô phỏng</label><input id="led_color" type="color"><span></span>
            <div class="color-presets" style="grid-column:1/-1">
              <button type="button" onclick="setLedColor('#ffbd59')">VÀNG ẤM</button>
              <button type="button" onclick="setLedColor('#ffe08a')">VÀNG SÁNG</button>
              <button type="button" onclick="setLedColor('#fff0c2')">TRẮNG ẤM</button>
              <button type="button" class="gray" onclick="setLedColor('#ffffff')">TRẮNG</button>
            </div>
            <label>Độ sáng LED</label><input id="brightness" type="range" min="0" max="200" step="5"><span id="brightness_value">100%</span>
            <label>Khoảng hắt sáng</label><input id="light_distance" type="range" min="0" max="500" step="5"><span id="light_distance_value">80mm</span>
            <label>Độ loang ánh sáng</label><input id="light_spread" type="range" min="0" max="200" step="5"><span id="light_spread_value">40mm</span>
            <label>Mô phỏng ánh sáng</label><input id="simulate" type="checkbox"><span></span>
            <label>Chế độ CNC</label><input id="cnc" type="checkbox"><span></span>
            <label>INSTANCE CNC</label><input id="cnc_instance"><span>ABF_RANHLED</span>
            <label>TAG CNC</label><input id="cnc_tag"><span>ABF_ranhled</span>
          </div>
          <div class="hint" style="margin-top:7px"><b>Chiều dài = 0</b> → AUTO lấy chiều dài mặt trừ Cách 2 đầu. <b>Khoảng cách giữa</b> là khoảng hở giữa 2 rãnh. Rê chuột gần mép nào thì rãnh tự bám mép đó.</div>
          <div class="lightbox">
            <div class="lightlabel"><b>PREVIEW ÁNH SÁNG LED</b> · <span id="light_direction_label">CHIẾU XUỐNG · Model -Z</span></div>
            <canvas id="light_preview" width="500" height="180"></canvas>
          </div>
          <div class="row">
            <button onclick="apply()">CẬP NHẬT PREVIEW</button>
            <button class="pickbtn" onclick="chooseContact()">CHỌN TIẾP DIỆN · TẠO LIÊN TỤC</button>
          </div>
          <div id="notice"></div>
          <div class="hint" style="margin-top:9px"><b>CNC:</b> 4 Edge kín thật được tạo <b>trực tiếp vào Face/hình học của Group/Component</b> và bắt buộc heal/split vào Face thật, không tạo Group CNC con. Edge mang <b>INSTANCE mặc định ABF_RANHLED</b> và <b>Tag mặc định ABF_ranhled</b> (đổi tên được), có <code>ABF/is-cutting-lines=true</code>. Mô phỏng ánh sáng là lớp riêng và không làm bẩn dữ liệu CNC.</div>
        </div>
      </div>
      <script>
      const ids=['name','end_clearance','edge_offset','groove_width','groove_length','quantity','spacing','led_color','brightness','light_distance','light_spread','simulate','cnc','cnc_instance','cnc_tag'];let selected='';let detectedInfo={side:'max',orientation:'vertical'};
      const TTLED={
        state:{},
        load(data){this.state=data||{};selected=data.selected||'';this.renderPresets(data.presets||{});this.fill(data.settings||{});},
        fill(s){ids.forEach(id=>{let e=document.getElementById(id);if(!e)return;if(e.type==='checkbox')e.checked=!!s[id];else if(s[id]!==undefined)e.value=s[id]});syncRanges();drawLightPreview();},
        values(){let o={};ids.forEach(id=>{let e=document.getElementById(id);o[id]=e.type==='checkbox'?e.checked:((e.type==='number'||e.type==='range')?Number(e.value):e.value)});return o;},
        renderPresets(rows){let box=document.getElementById('presets');box.innerHTML='';Object.keys(rows).sort().forEach(name=>{let b=document.createElement('button');b.className='preset'+(name===selected?' active':'');b.textContent=name;b.onclick=()=>{selected=name;sketchup.load_preset(name)};box.appendChild(b)})},
        detected(info){detectedInfo=info||detectedInfo;target.textContent=info.target||'Chưa nhận';dims.textContent=info.length?Math.round(info.length*10)/10+' × '+Math.round(info.width*10)/10+' mm':'-';groove.textContent=info.groove_length?((info.quantity||1)+' rãnh · '+Math.round(info.groove_length*10)/10+' × '+Math.round(info.groove_width*10)/10+' mm'):'-';drawLightPreview();},
        notice(msg,bad){let n=document.getElementById('notice');n.textContent=msg||'';n.className=bad?'err':'ok'}
      };
      function syncRanges(){
        brightness_value.textContent=Math.round(Number(brightness.value)||0)+'%';
        light_distance_value.textContent=Math.round(Number(light_distance.value)||0)+'mm';
        light_spread_value.textContent=Math.round(Number(light_spread.value)||0)+'mm';
        drawLightPreview();
      }
      function rgb(hex){
        let h=(hex||'#ffd86a').replace('#','');return [parseInt(h.slice(0,2),16)||255,parseInt(h.slice(2,4),16)||216,parseInt(h.slice(4,6),16)||106]
      }
      function rgba(c,a){return 'rgba('+c[0]+','+c[1]+','+c[2]+','+a+')'}
      function drawLightPreview(){
        let canvas=document.getElementById('light_preview');if(!canvas)return;
        let ctx=canvas.getContext('2d'),W=canvas.width,H=canvas.height,c=rgb(led_color.value),bright=Math.max(0,Number(brightness.value)||0)/100;
        ctx.clearRect(0,0,W,H);
        let bg=ctx.createLinearGradient(0,0,0,H);bg.addColorStop(0,'#17231b');bg.addColorStop(1,'#0d120f');ctx.fillStyle=bg;ctx.fillRect(0,0,W,H);
        if(!simulate.checked){ctx.fillStyle='#9dc5aa';ctx.font='13px Arial';ctx.fillText('Mô phỏng ánh sáng đang tắt',16,24);return}
        light_direction_label.textContent=(detectedInfo.orientation==='vertical'?'LED DỌC · HẮT XUỐNG + RA MẶT':'CHIẾU XUỐNG · Model -Z');
        let distance=Math.max(35,Math.min(H-54,(Number(light_distance.value)||0)*0.22+35));
        let spread=Math.max(10,Math.min(110,(Number(light_spread.value)||0)*0.42+10));
        let count=Math.max(1,Math.min(6,Number(quantity.value)||1));
        let gap=Math.max(38,Math.min(82,(Number(spacing.value)||0)*0.25+38));
        let center=W/2-(count-1)*gap/2;
        ctx.strokeStyle='rgba(255,255,255,.13)';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(18,34);ctx.lineTo(W-18,34);ctx.stroke();
        for(let n=0;n<count;n++){
          let x=center+n*gap,y=36,y2=Math.min(H-12,y+distance);
          let halfTop=24,halfBottom=halfTop+spread;
          let grad=ctx.createLinearGradient(0,y,0,y2);
          grad.addColorStop(0,rgba([255,250,220],Math.min(.72,.46*bright)));
          grad.addColorStop(.08,rgba(c,Math.min(.58,.36*bright)));
          grad.addColorStop(.25,rgba(c,Math.min(.38,.22*bright)));
          grad.addColorStop(.50,rgba(c,Math.min(.19,.105*bright)));
          grad.addColorStop(.76,rgba(c,Math.min(.07,.038*bright)));
          grad.addColorStop(1,rgba(c,0));
          ctx.save();ctx.globalCompositeOperation='screen';ctx.fillStyle=grad;
          ctx.beginPath();ctx.moveTo(x-halfTop,y);ctx.lineTo(x+halfTop,y);ctx.lineTo(x+halfBottom,y2);ctx.lineTo(x-halfBottom,y2);ctx.closePath();ctx.fill();
          ctx.restore();
          [24,16,10,6,3,1].forEach((lw,i)=>{
            ctx.save();ctx.strokeStyle=rgba(c,Math.min(1,(.10+(5-i)*.095)*bright));ctx.lineWidth=lw;ctx.shadowBlur=34+spread*.34;ctx.shadowColor=rgba([255,221,120],.82);
            ctx.beginPath();ctx.moveTo(x-halfTop,y);ctx.lineTo(x+halfTop,y);ctx.stroke();ctx.restore();
          });
          ctx.save();ctx.strokeStyle=rgba([255,249,214],Math.min(1,.92*bright));ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(x-halfTop,y);ctx.lineTo(x+halfTop,y);ctx.stroke();ctx.restore();
        }
        ctx.fillStyle='rgba(255,255,255,.42)';ctx.font='12px Arial';ctx.fillText('Ánh LED vàng sáng · mờ dần xuống dưới',16,H-10);
      }
      function setLedColor(hex){led_color.value=hex;drawLightPreview();apply()}
      function chooseContact(){sketchup.select_contact(JSON.stringify(TTLED.values()))}
      function startContinuous(){chooseContact()}
      function apply(){syncRanges();sketchup.update(JSON.stringify(TTLED.values()))}
      function savePreset(){let v=TTLED.values();sketchup.save_preset(v.name||'LED',JSON.stringify(v))}
      function deletePreset(){if(!selected){TTLED.notice('Chưa chọn mẫu để xóa.',true);return}sketchup.delete_preset(selected)}
      let timer=null;ids.forEach(id=>document.addEventListener('DOMContentLoaded',()=>{let e=document.getElementById(id);if(!e)return;e.addEventListener('input',()=>{clearTimeout(timer);timer=setTimeout(apply,180)});e.addEventListener('change',apply)}));
      document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      </script></body></html>
      HTML
    end

    def show_dialog(tool = nil)
      @active_tool = tool if tool
      unless @dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title:'Tạo LED',
          preferences_key:'TT_LED_TOOL',
          scrollable:true,resizable:true,width:760,height:620,
          style:UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_html(dialog_html)
        @dialog.add_action_callback('ready') { send_dialog_state }
        @dialog.add_action_callback('update') do |_ctx,json|
          clean = save_settings(JSON.parse(json.to_s))
          @active_tool.update_options(clean) if @active_tool
          send_dialog_state
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('load_preset') do |_ctx,name|
          row = presets[name.to_s]
          raise 'Không tìm thấy mẫu LED.' unless row
          @current_preset = name.to_s
          clean = save_settings(row)
          @active_tool.update_options(clean) if @active_tool
          send_dialog_state
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('save_preset') do |_ctx,name,json|
          clean = save_settings(JSON.parse(json.to_s))
          @current_preset = save_preset(name,clean)
          @active_tool.update_options(clean) if @active_tool
          send_dialog_state
          @dialog.execute_script("TTLED.notice('Đã lưu mẫu LED.',false)")
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('delete_preset') do |_ctx,name|
          delete_preset(name)
          @current_preset = ''
          send_dialog_state
          @dialog.execute_script("TTLED.notice('Đã xóa mẫu LED.',false)")
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        start_contact = proc do |json|
          clean = save_settings(JSON.parse(json.to_s))
          tool = Tool.new(clean)
          @active_tool = tool
          Sketchup.active_model.select_tool(tool)
          @dialog.execute_script("TTLED.notice('ĐÃ BẬT CHỌN TIẾP DIỆN · rê vào Group/Component để preview · click tạo và tiếp tục.',false)")
          send_dialog_state
        end
        @dialog.add_action_callback('select_contact') do |_ctx,json|
          start_contact.call(json)
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.add_action_callback('start_continuous') do |_ctx,json|
          start_contact.call(json)
        rescue StandardError => error
          @dialog.execute_script("TTLED.notice(#{JSON.generate(error.message)},true)")
        end
        @dialog.set_on_closed { @dialog = nil }
      end
      @dialog.show
      send_dialog_state
      @dialog
    end

    def activate
      tool = Tool.new(settings)
      @active_tool = tool
      Sketchup.active_model.select_tool(tool)
      show_dialog(tool)
      tool
    end

    class Tool
      attr_reader :options

      def initialize(options)
        @model = Sketchup.active_model
        @options = LedTool.normalize(options)
        @target = nil
        @target_tr = Geom::Transformation.new
        @face = nil
        @analysis = nil
        @plan = nil
        @plans = []
        @side = :min
        @last_detect_key = nil
      end

      def activate
        Sketchup.set_status_text('TẠO LED · CHỌN TIẾP DIỆN · rê vào Face Group/Component · CLICK tạo · tiếp tục tự động',SB_PROMPT)
      end

      def deactivate(view)
        view.invalidate if view
      end

      def resume(view)
        Sketchup.set_status_text('TẠO LED · CHỌN TIẾP DIỆN · rê mặt để preview · CLICK tạo liên tục',SB_PROMPT)
        view.invalidate
      end

      def onCancel(_reason,view)
        @model.select_tool(nil)
        view.invalidate
      end

      def update_options(raw)
        @options = LedTool.normalize(raw)
        rebuild_plan
        @model.active_view.invalidate
      rescue StandardError => error
        @plan = nil
        @plans = []
        LedTool.send_detected(error:error.message)
      end

      def onMouseMove(_flags,x,y,view)
        pick(view,x,y)
        if @target && @analysis && @plan
          target_name = @target.respond_to?(:name) && !@target.name.to_s.empty? ? @target.name.to_s : @target.class.name.split('::').last
          view.tooltip = "TIẾP DIỆN: #{target_name} · #{@analysis[:length_mm].round(1)} × #{@analysis[:width_mm].round(1)} mm · click tạo LED"
        else
          view.tooltip = 'CHỌN TIẾP DIỆN · rê vào Face của Group/Component'
        end
        view.invalidate
      rescue StandardError => error
        clear_pick
        Sketchup.set_status_text("TẠO LED: #{error.message}",SB_PROMPT)
      end

      def onLButtonDown(_flags,x,y,view)
        pick(view,x,y)
        return UI.beep unless @target && @face && @analysis && @plan
        create_led
        view.invalidate
      rescue StandardError => error
        UI.messagebox("Tạo LED:\n#{error.message}")
      end

      def draw(view)
        return unless @analysis && @plan && @target && @plans && !@plans.empty?

        # Highlight tiếp diện đang nhận để người dùng biết chính xác mặt sẽ gia công.
        if @face && (!@face.respond_to?(:valid?) || @face.valid?)
          face_points = @face.outer_loop.vertices.map { |vertex| vertex.position.transform(@target_tr) }
          if face_points.length >= 3
            begin
              view.drawing_color = Sketchup::Color.new(145,225,180,52)
            rescue ArgumentError
              view.drawing_color = Sketchup::Color.new(145,225,180)
            end
            view.draw(GL_POLYGON,face_points) if defined?(GL_POLYGON)
            view.drawing_color = Sketchup::Color.new(57,170,105)
            view.line_width = 2
            view.draw(GL_LINE_LOOP,face_points)
          end
        end

        brightness_alpha = [[(230*@options['brightness']/100.0).round,0].max,255].min
        @plans.each_with_index do |plan,index|
          base = preview_world_rect(plan,0.55,1.0)
          view.line_width = 2
          view.drawing_color = LedTool.color_from_hex(@options['led_color'],brightness_alpha)
          view.draw(GL_QUADS,base) if defined?(GL_QUADS)
          view.draw(GL_LINE_LOOP,base)

          if @options['simulate'] && defined?(GL_QUADS)
            direction = LedTool.light_direction_world(@analysis,plan,@target_tr)
            light = LedTool.light_geometry(base,@options,direction)
            light[:bands].each do |band|
              next if band[:alpha] <= 0
              view.drawing_color = LedTool.color_from_hex(@options['led_color'],band[:alpha])
              view.draw(GL_QUADS,band[:points])
            end

            # Mũi tên hướng sáng dùng đúng vector của quầng sáng thật.
            if index == 0 && defined?(GL_LINES)
              source_a = LedTool.midpoint(base[0],base[3])
              source_b = LedTool.midpoint(base[1],base[2])
              source = LedTool.midpoint(source_a,source_b)
              arrow_len = [[@options['light_distance'].to_f,40.0].max,180.0].min.mm
              tip = LedTool.shift_point(source,direction,arrow_len)
              along = LedTool.unit_vector(source_a.vector_to(source_b))
              wing = [arrow_len*0.16,18.mm].min
              back = LedTool.shift_point(tip,direction,-wing)
              left = LedTool.shift_point(back,along,wing*0.55)
              right = LedTool.shift_point(back,LedTool.reverse_vector(along),wing*0.55)
              view.drawing_color = LedTool.color_from_hex(@options['led_color'],245)
              view.line_width = 3
              view.draw(GL_LINES,[source,tip,tip,left,tip,right])
            end
          end

          if view.respond_to?(:draw_text) && index == 0
            center = base[0].vector_to(base[2])
            label_point = Geom::Point3d.new(base[0].x+center.x*0.5,base[0].y+center.y*0.5,base[0].z+center.z*0.5)
            view.draw_text(label_point,"LED #{@plans.length} × #{@plan[:length].round(1)} × #{@plan[:width].round(1)} mm")
          end
        end
      rescue StandardError => error
        puts "[TT LED draw] #{error.class}: #{error.message}"
      end

      private

      def clear_pick
        @target = @face = @analysis = @plan = nil
        @plans = []
        @target_tr = Geom::Transformation.new
        notify_detected
      end

      def pick(view,x,y)
        ph = view.pick_helper
        ph.do_pick(x,y)
        found = nil
        ph.count.times do |index|
          path = ph.path_at(index)
          next unless path
          face = path.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
          next unless face
          containers = path.select { |entity| LedTool.container?(entity) }
          if containers.empty? && @model.active_path && !@model.active_path.empty?
            containers = [@model.active_path.last].select { |entity| LedTool.container?(entity) }
          end
          next if containers.empty?
          target = containers.last
          tr = begin
            @model.edit_transform
          rescue StandardError
            Geom::Transformation.new
          end
          path.each do |entity|
            tr = tr * entity.transformation if LedTool.container?(entity)
            break if entity.equal?(target)
          end
          found = [target,tr,face]
          break
        end
        return clear_pick unless found
        @target,@target_tr,@face = found
        @analysis = LedTool.analyze_face(@face)
        begin
          world_normal = @analysis[:normal].transform(@target_tr)
          if world_normal.dot(view.camera.direction) > 0
            @analysis[:normal] = @analysis[:normal].reverse
          end
        rescue StandardError
          nil
        end
        choose_side(view,x,y)
        rebuild_plan
        notify_detected
      end

      def choose_side(view,x,y)
        world_origin = @analysis[:origin].transform(@target_tr)
        world_normal = @analysis[:normal].transform(@target_tr)
        hit = Geom.intersect_line_plane(view.pickray(x,y),[world_origin,world_normal])
        return unless hit
        local = hit.transform(@target_tr.inverse)
        vv = @analysis[:origin].vector_to(local).dot(@analysis[:v])
        mid = (@analysis[:min_v]+@analysis[:max_v])/2.0
        @side = vv <= mid ? :min : :max
      rescue StandardError
        @side = :min
      end

      def rebuild_plan
        unless @analysis
          @plan = nil
          @plans = []
          return
        end
        @plans = LedTool.groove_plans(@analysis[:length_mm],@analysis[:width_mm],@options,@side)
        @plan = @plans.first
      end

      def notify_detected
        info = if @analysis && @plan && @target
          {
            target:(@target.name.to_s.empty? ? @target.class.name.split('::').last : @target.name.to_s),
            length:@analysis[:length_mm],width:@analysis[:width_mm],
            groove_length:@plan[:length],groove_width:@plan[:width],
            quantity:@plans.length,spacing:@options['spacing'],
            side:@plan[:side].to_s,
            orientation:begin
              world_u = @analysis[:u].transform(@target_tr)
              world_u.z.abs >= [world_u.x.abs,world_u.y.abs].max ? 'vertical' : 'horizontal'
            rescue StandardError
              'vertical'
            end
          }
        else
          {}
        end
        key = info.to_s
        return if key == @last_detect_key
        @last_detect_key = key
        LedTool.send_detected(info)
      end

      def preview_world_rect(plan,offset_mm,width_scale)
        LedTool.local_rect(@analysis,plan,offset_mm,width_scale).map { |point| point.transform(@target_tr) }
      end

      def create_led
        model = @model
        model.start_operation('TT - Tạo LED',true)
        started = true
        target = @target
        if target.respond_to?(:definition) && target.respond_to?(:make_unique)
          instances = target.definition.respond_to?(:instances) ? target.definition.instances : []
          target.make_unique if instances && instances.length > 1
        end

        plans = LedTool.groove_plans(@analysis[:length_mm],@analysis[:width_mm],@options,@side)
        raise 'Không có rãnh LED hợp lệ để tạo.' if plans.empty?

        plans.each_with_index do |plan,index|
          local_points = LedTool.local_rect(@analysis,plan,0.0,1.0)
          # BẮT BUỘC tìm lại Face trong chính target hiện tại, đặc biệt sau Make Unique.
          host_face = LedTool.find_host_face(target,local_points)
          raise "Không tìm lại được Face bên trong Group/Component cho rãnh #{index+1}." unless host_face && host_face.valid?

          if @options['cnc']
            LedTool.add_abf_profile(target,host_face,local_points,@options,index,plans.length)
          end

          if @options['simulate']
            world_rect = LedTool.local_rect(@analysis,plan,0.65,1.0).map { |point| point.transform(@target_tr) }
            LedTool.add_led_simulation(
              world_rect,
              {target:target,transform:@target_tr},
              @analysis,
              plan,
              @options,
              index,
              plans.length
            )
          end
        end

        target.set_attribute(KEY,'name',@options['name'])
        target.set_attribute(KEY,'end_clearance_mm',@options['end_clearance'])
        target.set_attribute(KEY,'edge_offset_mm',@options['edge_offset'])
        target.set_attribute(KEY,'groove_width_mm',@options['groove_width'])
        target.set_attribute(KEY,'groove_length_mm',plans.first[:length])
        target.set_attribute(KEY,'quantity',plans.length)
        target.set_attribute(KEY,'spacing_mm',@options['spacing'])
        target.set_attribute(KEY,'led_color',@options['led_color'])
        target.set_attribute(KEY,'brightness_percent',@options['brightness'])
        target.set_attribute(KEY,'light_distance_mm',@options['light_distance'])
        target.set_attribute(KEY,'light_spread_mm',@options['light_spread'])
        target.set_attribute(KEY,'cnc_enabled',@options['cnc'])

        model.commit_operation
        started = false

        # Giữ tool ở trạng thái AUTO để click tạo liên tục.
        @plans = plans
        @plan = plans.first
        Sketchup.set_status_text(
          "Đã tạo #{plans.length} rãnh LED · #{@plan[:length].round(1)} × #{@plan[:width].round(1)} mm · tiếp tục rà/click",
          SB_PROMPT
        )
      rescue StandardError
        model.abort_operation if started
        raise
      end
    end
  end
end
