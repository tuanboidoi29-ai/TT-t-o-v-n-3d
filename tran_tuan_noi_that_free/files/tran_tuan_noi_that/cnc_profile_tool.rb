# encoding: UTF-8
require 'sketchup.rb'
require 'json'

module TranTuanNoiThat
  module CNCProfileTool
    extend self

    LIBRARY_KEY = 'cnc_profile_library_v1'.freeze
    ACTIVE_KEY = 'cnc_profile_active_v1'.freeze
    DICT = 'TT_CNC_PROFILE'.freeze
    EPS = 1.0e-7
    SNAP_RADIUS_PX = 22.0

    DEFAULT_PROFILES = [
      {'id'=>'builtin_rect','name'=>'01 Chữ nhật','kind'=>'rectangle','width'=>500.0,'height'=>300.0,'edge_gap'=>30.0,'p1'=>0.0,'p2'=>0.0,'segments'=>32,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_round','name'=>'02 Bo 4 góc','kind'=>'rounded_rect','width'=>500.0,'height'=>300.0,'edge_gap'=>30.0,'p1'=>45.0,'p2'=>0.0,'segments'=>8,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_chamfer','name'=>'03 Vát 4 góc','kind'=>'chamfer_rect','width'=>500.0,'height'=>300.0,'edge_gap'=>30.0,'p1'=>55.0,'p2'=>0.0,'segments'=>4,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_capsule','name'=>'04 Viên thuốc','kind'=>'capsule','width'=>500.0,'height'=>180.0,'edge_gap'=>30.0,'p1'=>0.0,'p2'=>0.0,'segments'=>18,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_ellipse','name'=>'05 Oval','kind'=>'ellipse','width'=>500.0,'height'=>300.0,'edge_gap'=>30.0,'p1'=>0.0,'p2'=>0.0,'segments'=>48,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_arch','name'=>'06 Vòm trên','kind'=>'arch_top','width'=>500.0,'height'=>340.0,'edge_gap'=>30.0,'p1'=>120.0,'p2'=>0.0,'segments'=>24,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_double_arch','name'=>'07 Vòm hai đầu','kind'=>'double_arch','width'=>500.0,'height'=>340.0,'edge_gap'=>30.0,'p1'=>85.0,'p2'=>0.0,'segments'=>18,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_concave','name'=>'08 Lõm hai cạnh','kind'=>'concave_sides','width'=>500.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>55.0,'p2'=>0.0,'segments'=>18,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_wave2','name'=>'09 Sóng 2 nhịp','kind'=>'wave_top','width'=>520.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>38.0,'p2'=>2.0,'segments'=>40,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_wave3','name'=>'10 Sóng 3 nhịp','kind'=>'wave_top','width'=>520.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>32.0,'p2'=>3.0,'segments'=>48,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_ogee','name'=>'11 Ogee trên','kind'=>'ogee_top','width'=>520.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>45.0,'p2'=>0.0,'segments'=>40,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_slot_round','name'=>'12 Tay nắm oval','kind'=>'capsule','width'=>180.0,'height'=>45.0,'edge_gap'=>25.0,'p1'=>0.0,'p2'=>0.0,'segments'=>18,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_slot_rect','name'=>'13 Tay nắm bo góc','kind'=>'rounded_rect','width'=>180.0,'height'=>50.0,'edge_gap'=>25.0,'p1'=>14.0,'p2'=>0.0,'segments'=>6,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_diamond','name'=>'14 Kim cương','kind'=>'diamond','width'=>420.0,'height'=>300.0,'edge_gap'=>30.0,'p1'=>0.0,'p2'=>0.0,'segments'=>4,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_hex','name'=>'15 Lục giác','kind'=>'hexagon','width'=>440.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>0.0,'p2'=>0.0,'segments'=>6,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_oct','name'=>'16 Bát giác','kind'=>'octagon','width'=>460.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>65.0,'p2'=>0.0,'segments'=>8,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_shield','name'=>'17 Khiên','kind'=>'shield','width'=>440.0,'height'=>360.0,'edge_gap'=>30.0,'p1'=>90.0,'p2'=>0.0,'segments'=>12,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_quatrefoil','name'=>'18 Hoa 4 cánh','kind'=>'quatrefoil','width'=>360.0,'height'=>360.0,'edge_gap'=>30.0,'p1'=>55.0,'p2'=>0.0,'segments'=>64,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_step','name'=>'19 Góc giật cấp','kind'=>'panel_step','width'=>500.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>55.0,'p2'=>38.0,'segments'=>12,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true},
      {'id'=>'builtin_scallop','name'=>'20 Cánh sò trên','kind'=>'scallop_top','width'=>520.0,'height'=>320.0,'edge_gap'=>30.0,'p1'=>32.0,'p2'=>5.0,'segments'=>50,'fit'=>false,'rotation'=>0.0,'mirror'=>false,'builtin'=>true}
    ].freeze

    KIND_LABELS = {
      'rectangle' => ['Không dùng','Không dùng'],
      'rounded_rect' => ['Bán kính bo R (mm)','Không dùng'],
      'chamfer_rect' => ['Kích thước vát (mm)','Không dùng'],
      'capsule' => ['Không dùng','Không dùng'],
      'ellipse' => ['Không dùng','Không dùng'],
      'arch_top' => ['Độ vồng (mm)','Không dùng'],
      'double_arch' => ['Độ vồng (mm)','Không dùng'],
      'concave_sides' => ['Độ lõm (mm)','Không dùng'],
      'wave_top' => ['Biên độ sóng (mm)','Số nhịp sóng'],
      'ogee_top' => ['Biên độ Ogee (mm)','Không dùng'],
      'diamond' => ['Không dùng','Không dùng'],
      'hexagon' => ['Không dùng','Không dùng'],
      'octagon' => ['Kích thước vát (mm)','Không dùng'],
      'shield' => ['Độ nhọn đáy (mm)','Không dùng'],
      'quatrefoil' => ['Độ phồng cánh (mm)','Không dùng'],
      'panel_step' => ['Bậc ngang (mm)','Bậc đứng (mm)'],
      'scallop_top' => ['Độ võng (mm)','Số múi']
    }.freeze

    def library
      custom = []
      raw = Sketchup.read_default(TranTuanNoiThat::NAME, LIBRARY_KEY, '[]').to_s
      begin
        parsed = JSON.parse(raw)
        custom = parsed if parsed.is_a?(Array)
      rescue JSON::ParserError
        custom = []
      end

      defaults = DEFAULT_PROFILES.map { |profile| deep_copy(profile) }
      customs = custom.select { |profile| profile.is_a?(Hash) }.map do |profile|
        normalize_profile(profile, false)
      end
      defaults + customs
    end

    def save_custom_library(items)
      data = items.reject { |profile| profile['builtin'] }.map do |profile|
        normalize_profile(profile, false)
      end
      Sketchup.write_default(
        TranTuanNoiThat::NAME,
        LIBRARY_KEY,
        JSON.generate(data)
      )
    end

    def active_profile
      id = Sketchup.read_default(
        TranTuanNoiThat::NAME,
        ACTIVE_KEY,
        DEFAULT_PROFILES.first['id']
      ).to_s
      library.find { |profile| profile['id'].to_s == id } || library.first
    end

    def show_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        sync_dialog
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - TẠO BIÊN DẠNG CNC',
        preferences_key: 'TranTuanNoiThat.CNCProfile',
        scrollable: true,
        resizable: true,
        width: 920,
        height: 760,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      @dialog.set_html(dialog_html)
      @dialog.add_action_callback('ready') { |_ctx| sync_dialog }

      @dialog.add_action_callback('save_profile') do |_ctx, payload|
        begin
          data = JSON.parse(payload)
          profile = normalize_profile(data, false)
          items = library

          if data['builtin'] || profile['id'].to_s.start_with?('builtin_')
            profile['id'] = custom_id
          end
          profile['builtin'] = false

          index = items.index { |item| item['id'] == profile['id'] && !item['builtin'] }
          if index
            items[index] = profile
          else
            items << profile
          end

          save_custom_library(items)
          Sketchup.write_default(
            TranTuanNoiThat::NAME,
            ACTIVE_KEY,
            profile['id']
          )
          sync_dialog(profile['id'])
          notify('Đã lưu mẫu vào THƯ VIỆN CNC.', 'ok')
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('delete_profile') do |_ctx, profile_id|
        begin
          items = library
          target = items.find { |item| item['id'] == profile_id.to_s }
          raise 'Mẫu hệ thống không được xóa.' if target && target['builtin']

          custom = items.reject do |item|
            !item['builtin'] && item['id'].to_s == profile_id.to_s
          end
          save_custom_library(custom)
          sync_dialog(DEFAULT_PROFILES.first['id'])
          notify('Đã xóa mẫu tự tạo.', 'ok')
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.add_action_callback('reset_library') do |_ctx|
        Sketchup.write_default(
          TranTuanNoiThat::NAME,
          LIBRARY_KEY,
          '[]'
        )
        Sketchup.write_default(
          TranTuanNoiThat::NAME,
          ACTIVE_KEY,
          DEFAULT_PROFILES.first['id']
        )
        sync_dialog
        notify('Đã khôi phục 20 mẫu CNC mặc định.', 'ok')
      end

      @dialog.add_action_callback('use_profile') do |_ctx, payload|
        begin
          data = JSON.parse(payload)
          profile = normalize_profile(data, !!data['builtin'])
          Sketchup.write_default(
            TranTuanNoiThat::NAME,
            ACTIVE_KEY,
            profile['id']
          )
          activate_profile(profile)
          @dialog.close if @dialog && @dialog.visible?
        rescue StandardError => error
          notify(error.message, 'error')
        end
      end

      @dialog.show
    end

    def sync_dialog(selected_id = nil)
      return unless @dialog && @dialog.visible?
      selected_id ||= active_profile['id']
      payload = {
        'profiles' => library,
        'selected_id' => selected_id,
        'kind_labels' => KIND_LABELS,
        'kinds' => KIND_LABELS.keys
      }
      @dialog.execute_script(
        "window.ttLoad(#{JSON.generate(payload)})"
      )
    end

    def notify(message, kind = 'ok')
      return unless @dialog && @dialog.visible?
      @dialog.execute_script(
        "window.ttNotice(#{JSON.generate(message.to_s)},#{JSON.generate(kind)})"
      )
    end

    def normalize_profile(data, builtin = false)
      raise 'Dữ liệu biên dạng không hợp lệ.' unless data.is_a?(Hash)

      name = data['name'].to_s.strip
      name = 'Biên dạng CNC' if name.empty?

      kind = data['kind'].to_s
      kind = 'rectangle' unless KIND_LABELS.key?(kind)

      width = number(data['width'], 500.0, 5.0, 100_000.0)
      height = number(data['height'], 300.0, 5.0, 100_000.0)
      edge_gap = number(data['edge_gap'], 30.0, 0.0, 10_000.0)
      p1 = number(data['p1'], 0.0, -100_000.0, 100_000.0)
      p2 = number(data['p2'], 0.0, -100_000.0, 100_000.0)
      segments = number(data['segments'], 24.0, 4.0, 180.0).round
      rotation = number(data['rotation'], 0.0, -3600.0, 3600.0)
      offset_x = number(data['offset_x'], 0.0, -100_000.0, 100_000.0)
      offset_y = number(data['offset_y'], 0.0, -100_000.0, 100_000.0)

      id = data['id'].to_s.strip
      id = custom_id if id.empty?

      instance_name = data['instance_name'].to_s.strip
      instance_name = abf_name(name) if instance_name.empty?

      tag_name = data['tag_name'].to_s.strip
      tag_name = abf_name(name) if tag_name.empty?

      {
        'id' => id,
        'name' => name,
        'kind' => kind,
        'width' => width,
        'height' => height,
        'edge_gap' => edge_gap,
        'p1' => p1,
        'p2' => p2,
        'segments' => segments,
        'fit' => truthy?(data['fit']),
        'rotation' => rotation,
        'mirror' => truthy?(data['mirror']),
        'offset_x' => offset_x,
        'offset_y' => offset_y,
        'instance_name' => instance_name,
        'tag_name' => tag_name,
        'builtin' => !!builtin
      }
    end

    def abf_name(name)
      core = name.to_s.strip
      core = 'BIEN_DANG_CNC' if core.empty?
      core = core.gsub(/[\\\/:*?"<>|]+/, '_')
      core = core.gsub(/\s+/, '_')
      core = core.gsub(/_+/, '_')
      core = core.sub(/\A_+/, '').sub(/_+\z/, '')
      core = 'BIEN_DANG_CNC' if core.empty?
      core.start_with?('ABF_') ? core : "ABF_#{core}"
    end

    def number(value, fallback, min, max)
      number = Float(value)
      raise 'Thông số không hữu hạn.' unless number.finite?
      [[number, min].max, max].min
    rescue ArgumentError, TypeError
      fallback
    end

    def truthy?(value)
      value == true || value.to_s.downcase == 'true' || value.to_s == '1'
    end

    def custom_id
      "custom_#{Time.now.to_i}_#{rand(1_000_000)}"
    end

    def deep_copy(object)
      JSON.parse(JSON.generate(object))
    end

    def activate_profile(profile)
      # Không cần chọn Group/Component trước.
      # Chọn mẫu → DÙNG NGAY → rà trực tiếp Face; tool tự nhận Group chứa Face.
      Sketchup.active_model.select_tool(PlacementTool.new(profile))
      true
    end

    def build_paths(profile, width_mm, height_mm)
      width = [width_mm.to_f, 1.0].max
      height = [height_mm.to_f, 1.0].max
      kind = profile['kind'].to_s
      p1 = profile['p1'].to_f
      p2 = profile['p2'].to_f
      segments = [[profile['segments'].to_i, 4].max, 180].min

      points =
        case kind
        when 'rounded_rect'
          rounded_rect(width, height, p1, segments)
        when 'chamfer_rect'
          chamfer_rect(width, height, p1)
        when 'capsule'
          rounded_rect(width, height, [width, height].min / 2.0, segments)
        when 'ellipse'
          ellipse_points(width, height, [segments, 24].max)
        when 'arch_top'
          arch_top(width, height, p1, segments)
        when 'double_arch'
          double_arch(width, height, p1, segments)
        when 'concave_sides'
          concave_sides(width, height, p1, segments)
        when 'wave_top'
          wave_top(width, height, p1, p2, segments)
        when 'ogee_top'
          ogee_top(width, height, p1, segments)
        when 'diamond'
          diamond(width, height)
        when 'hexagon'
          hexagon(width, height)
        when 'octagon'
          octagon(width, height, p1)
        when 'shield'
          shield(width, height, p1, segments)
        when 'quatrefoil'
          quatrefoil(width, height, p1, [segments, 48].max)
        when 'panel_step'
          panel_step(width, height, p1, p2)
        when 'scallop_top'
          scallop_top(width, height, p1, p2, segments)
        else
          rectangle(width, height)
        end

      [{'closed'=>true, 'points'=>points}]
    end

    def rectangle(width, height)
      x = width / 2.0
      y = height / 2.0
      [[-x,-y],[x,-y],[x,y],[-x,y]]
    end

    def rounded_rect(width, height, radius, segments)
      x = width / 2.0
      y = height / 2.0
      r = [[radius.abs, [x,y].min].min, 0.1].max
      n = [[segments / 4, 2].max, 24].min
      points = []
      [
        [x-r,y-r,0.0,90.0],
        [-x+r,y-r,90.0,180.0],
        [-x+r,-y+r,180.0,270.0],
        [x-r,-y+r,270.0,360.0]
      ].each do |cx,cy,a0,a1|
        arc_points(cx,cy,r,r,a0,a1,n).each do |point|
          points << point unless points.last == point
        end
      end
      points
    end

    def chamfer_rect(width, height, cut)
      x = width / 2.0
      y = height / 2.0
      c = [[cut.abs, [x,y].min * 0.95].min, 0.1].max
      [
        [-x+c,-y],[x-c,-y],[x,-y+c],[x,y-c],
        [x-c,y],[-x+c,y],[-x,y-c],[-x,-y+c]
      ]
    end

    def ellipse_points(width, height, segments)
      rx = width / 2.0
      ry = height / 2.0
      n = [[segments, 16].max, 180].min
      (0...n).map do |index|
        angle = Math::PI * 2.0 * index / n
        [Math.cos(angle) * rx, Math.sin(angle) * ry]
      end
    end

    def arch_top(width, height, rise, segments)
      x = width / 2.0
      y = height / 2.0
      r = [[rise.abs, height * 0.8].min, 1.0].max
      top_base = y - r
      points = [[-x,-y],[x,-y],[x,top_base]]
      n = [[segments, 8].max, 90].min
      (0..n).each do |index|
        t = index.to_f / n
        xx = x - width * t
        yy = top_base + r * Math.sin(Math::PI * t)
        points << [xx,yy]
      end
      points << [-x,top_base]
      points
    end

    def double_arch(width, height, rise, segments)
      x = width / 2.0
      y = height / 2.0
      r = [[rise.abs, height * 0.4].min, 1.0].max
      n = [[segments, 8].max, 90].min
      points = []
      (0..n).each do |index|
        t = index.to_f / n
        xx = -x + width * t
        yy = -y + r * Math.sin(Math::PI * t)
        points << [xx,yy]
      end
      (0..n).each do |index|
        t = index.to_f / n
        xx = x - width * t
        yy = y - r * Math.sin(Math::PI * t)
        points << [xx,yy]
      end
      points
    end

    def concave_sides(width, height, depth, segments)
      x = width / 2.0
      y = height / 2.0
      d = [[depth.abs, width * 0.4].min, 1.0].max
      n = [[segments / 2, 6].max, 60].min
      points = [[-x,-y],[x,-y]]
      (0..n).each do |index|
        t = index.to_f / n
        yy = -y + height * t
        xx = x - d * Math.sin(Math::PI * t)
        points << [xx,yy]
      end
      points << [-x,y]
      (0..n).each do |index|
        t = index.to_f / n
        yy = y - height * t
        xx = -x + d * Math.sin(Math::PI * t)
        points << [xx,yy]
      end
      points
    end

    def wave_top(width, height, amplitude, count, segments)
      x = width / 2.0
      y = height / 2.0
      amp = [[amplitude.abs, height * 0.35].min, 1.0].max
      waves = [[count.abs.round, 1].max, 12].min
      n = [[segments, waves * 10].max, 160].min
      points = [[-x,-y],[x,-y],[x,y]]
      (0..n).each do |index|
        t = index.to_f / n
        xx = x - width * t
        yy = y - amp * 0.5 + amp * 0.5 * Math.cos(Math::PI * 2.0 * waves * t)
        points << [xx,yy]
      end
      points << [-x,y]
      points
    end

    def ogee_top(width, height, amplitude, segments)
      x = width / 2.0
      y = height / 2.0
      amp = [[amplitude.abs, height * 0.4].min, 1.0].max
      n = [[segments, 16].max, 120].min
      points = [[-x,-y],[x,-y],[x,y]]
      (0..n).each do |index|
        t = index.to_f / n
        xx = x - width * t
        yy = y - amp * Math.sin(Math::PI * 2.0 * t) * 0.5
        points << [xx,yy]
      end
      points << [-x,y]
      points
    end

    def diamond(width, height)
      x = width / 2.0
      y = height / 2.0
      [[0,-y],[x,0],[0,y],[-x,0]]
    end

    def hexagon(width, height)
      x = width / 2.0
      y = height / 2.0
      c = [width * 0.22, x * 0.8].min
      [[-x+c,-y],[x-c,-y],[x,0],[x-c,y],[-x+c,y],[-x,0]]
    end

    def octagon(width, height, cut)
      chamfer_rect(width, height, cut.to_f.zero? ? [width,height].min * 0.18 : cut)
    end

    def shield(width, height, tip, segments)
      x = width / 2.0
      y = height / 2.0
      depth = [[tip.abs, height * 0.45].min, 10.0].max
      n = [[segments / 2, 4].max, 40].min
      points = [[-x,y],[x,y],[x,-y+depth]]
      (0..n).each do |index|
        t = index.to_f / n
        angle = Math::PI * t
        xx = x * Math.cos(angle)
        yy = -y + depth * (1.0 - Math.sin(angle))
        points << [xx,yy]
      end
      points << [-x,-y+depth]
      points
    end

    def quatrefoil(width, height, bulge, segments)
      rx = width / 2.0
      ry = height / 2.0
      b = [[bulge.abs, [rx,ry].min * 0.8].min, 1.0].max
      n = [[segments, 32].max, 160].min
      (0...n).map do |index|
        angle = Math::PI * 2.0 * index / n
        radial = 1.0 + (b / [rx,ry].min) * 0.28 * Math.cos(4.0 * angle)
        [Math.cos(angle) * rx * radial, Math.sin(angle) * ry * radial]
      end
    end

    def panel_step(width, height, step_x, step_y)
      x = width / 2.0
      y = height / 2.0
      sx = [[step_x.abs, x * 0.45].min, 1.0].max
      sy = [[step_y.abs, y * 0.45].min, 1.0].max
      [
        [-x+sx,-y], [x-sx,-y], [x-sx,-y+sy], [x,-y+sy],
        [x,y-sy], [x-sx,y-sy], [x-sx,y], [-x+sx,y],
        [-x+sx,y-sy], [-x,y-sy], [-x,-y+sy], [-x+sx,-y+sy]
      ]
    end

    def scallop_top(width, height, amplitude, count, segments)
      x = width / 2.0
      y = height / 2.0
      amp = [[amplitude.abs, height * 0.35].min, 1.0].max
      lobes = [[count.abs.round, 1].max, 12].min
      n = [[segments, lobes * 10].max, 160].min
      points = [[-x,-y],[x,-y],[x,y]]
      (0..n).each do |index|
        t = index.to_f / n
        xx = x - width * t
        phase = (t * lobes) % 1.0
        yy = y - amp * Math.sin(Math::PI * phase)
        points << [xx,yy]
      end
      points << [-x,y]
      points
    end

    def arc_points(cx, cy, rx, ry, start_deg, end_deg, segments)
      (0..segments).map do |index|
        t = index.to_f / segments
        angle = (start_deg + (end_deg - start_deg) * t) * Math::PI / 180.0
        [cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry]
      end
    end

    class PlacementTool
      def initialize(profile)
        @profile = CNCProfileTool.deep_copy(profile)
        @hover = nil
        @ip = Sketchup::InputPoint.new
      end

      def activate
        @model = Sketchup.active_model
        @active_entities = @model.active_entities
        @edit_to_world = @model.edit_transform
        Sketchup.set_status_text(
          "CNC #{@profile['name']} · rà Face → tự nhận khổ ván + 9 điểm MÉP/TÂM/MÉP → preview → click đặt · TAB thư viện · ESC thoát.",
          SB_PROMPT
        )
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @hover = pick_face(view, x, y)
        view.invalidate
      rescue StandardError => error
        puts "[TT CNC move] #{error.class}: #{error.message}"
        @hover = nil
      end

      def onLButtonDown(_flags, _x, _y, view)
        return UI.beep unless @hover

        create_profile(@hover)
        @hover = nil
        Sketchup.set_status_text(
          "Đã đặt #{@profile['instance_name']} · tiếp tục rê Face khác để đặt · TAB thư viện · ESC thoát.",
          SB_PROMPT
        )
        view.invalidate
      rescue StandardError => error
        @model.abort_operation rescue nil
        UI.messagebox("TẠO BIÊN DẠNG CNC:\n#{error.message}")
      end

      def onKeyDown(key, repeat, _flags, _view)
        return false if repeat.to_i > 1
        if key == 9
          @model.select_tool(nil)
          CNCProfileTool.show_dialog
          return true
        end
        false
      end

      def onCancel(_reason, view)
        @model.select_tool(nil)
        view.invalidate
      end

      def deactivate(view)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end

      def draw(view)
        return unless @hover

        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(30, 130, 235)

        @hover[:world_paths].each do |path|
          points = path[:points]
          next if points.length < 2
          pairs = []
          points.each_cons(2) { |a,b| pairs.concat([a,b]) }
          pairs.concat([points.last, points.first]) if path[:closed]
          view.draw(GL_LINES, pairs) unless pairs.empty?
        end

        snap_points = @hover[:snap_points_world] || []
        unless snap_points.empty?
          view.draw_points(
            snap_points,
            6,
            2,
            Sketchup::Color.new(90, 190, 255)
          )
        end

        center = @hover[:center_world]
        view.draw_points(
          [center],
          10,
          2,
          Sketchup::Color.new(255, 150, 40)
        )

        if @hover[:snap_world]
          view.draw_points(
            [@hover[:snap_world]],
            12,
            2,
            Sketchup::Color.new(255, 210, 60)
          )
        end

        label = "#{@profile['name']} · CNC #{@hover[:width_mm].round(1)} × #{@hover[:height_mm].round(1)} mm"
        board_label = "KHỔ FACE #{@hover[:board_width_mm].round(1)} × #{@hover[:board_height_mm].round(1)} mm"
        snap_label = @hover[:snap_label] ? " · BẮT #{@hover[:snap_label]}" : ' · ĐẶT TỰ DO'
        view.draw_text(
          view.screen_coords(center),
          "#{label} · #{board_label}#{snap_label}"
        )
      rescue StandardError => error
        puts "[TT CNC draw] #{error.class}: #{error.message}"
      end

      def pick_face(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y, 8)
        return nil if helper.count <= 0

        0.upto([helper.count - 1, 14].min) do |index|
          path = helper.path_at(index)
          next unless path && !path.empty?

          face_index = path.rindex { |item| item.is_a?(Sketchup::Face) }
          next unless face_index

          # Tự lấy Group/Component gần Face nhất trong đường pick.
          # Không phụ thuộc selection và hỗ trợ cả Group lồng nhau.
          target_index = nil
          (face_index - 1).downto(0) do |path_index|
            item = path[path_index]
            if item.is_a?(Sketchup::Group) ||
               item.is_a?(Sketchup::ComponentInstance)
              target_index = path_index
              break
            end
          end
          next unless target_index

          target = path[target_index]
          next unless target.valid?
          next if target.respond_to?(:locked?) && target.locked?

          face = path[face_index]
          face_transform = helper.transformation_at(index) || Geom::Transformation.new
          face_world = @edit_to_world * face_transform
          target_world = world_transform_for_path(path, target_index)

          point_world = point_on_face(view, x, y, face, face_world)
          next unless point_world

          point_face = point_world.transform(face_world.inverse)
          classification = face.classify_point(point_face)
          valid_classes = [
            Sketchup::Face::PointInside,
            Sketchup::Face::PointOnFace,
            Sketchup::Face::PointOnEdge,
            Sketchup::Face::PointOnVertex
          ]
          next unless valid_classes.include?(classification)

          info = preview_info(
            target,
            face,
            target_world,
            face_world,
            point_world,
            view,
            x,
            y
          )
          return info if info
        end

        nil
      rescue StandardError => error
        puts "[TT CNC pick] #{error.class}: #{error.message}"
        nil
      end

      def world_transform_for_path(path, target_index)
        transform = @edit_to_world
        0.upto(target_index) do |index|
          item = path[index]
          if item.is_a?(Sketchup::Group) ||
             item.is_a?(Sketchup::ComponentInstance)
            transform *= item.transformation
          end
        end
        transform
      end

      def point_on_face(view, x, y, face, face_world)
        vertices = face.outer_loop.vertices.map do |vertex|
          vertex.position.transform(face_world)
        end
        plane = plane_from_points(vertices)
        return nil unless plane
        Geom.intersect_line_plane(view.pickray(x, y), plane)
      end

      def plane_from_points(points)
        return nil if points.length < 3
        origin = points.first
        (1...(points.length - 1)).each do |index|
          a = points[index] - origin
          b = points[index + 1] - origin
          normal = a.cross(b)
          next if normal.length < EPS
          return [origin, normal]
        end
        nil
      end

      def preview_info(
        target,
        face,
        target_world,
        face_world,
        point_world,
        view,
        mouse_x,
        mouse_y
      )
        world_vertices = face.outer_loop.vertices.map do |vertex|
          vertex.position.transform(face_world)
        end
        target_inverse = target_world.inverse
        target_vertices = world_vertices.map do |point|
          point.transform(target_inverse)
        end
        plane = plane_from_points(target_vertices)
        return nil unless plane

        normal = safe_unit(plane[1])
        return nil unless normal

        # Trục khổ ván luôn lấy từ Face thật, trước khi xoay/mirror biên dạng.
        board_u, board_v = face_axes(normal)
        return nil unless board_u && board_v

        values_u = target_vertices.map { |point| point_dot(point, board_u) }
        values_v = target_vertices.map { |point| point_dot(point, board_v) }
        min_u, max_u = values_u.minmax
        min_v, max_v = values_v.minmax

        board_width_mm = (max_u - min_u).to_mm
        board_height_mm = (max_v - min_v).to_mm
        return nil if board_width_mm <= 0.1 || board_height_mm <= 0.1

        # 9 điểm bắt: 4 góc + 4 trung điểm cạnh + tâm.
        snap_points = build_board_snap_points(
          target_vertices.first,
          board_u,
          board_v,
          min_u,
          max_u,
          min_v,
          max_v,
          target_world
        )
        snapped = nearest_snap_point(
          snap_points,
          view,
          mouse_x,
          mouse_y
        )

        anchor =
          if snapped
            snapped[:local]
          else
            point_world.transform(target_inverse)
          end

        # Hướng hình CNC có thể xoay/lật độc lập với hệ trục khổ ván.
        u_axis = board_u
        v_axis = board_v
        angle = @profile['rotation'].to_f * Math::PI / 180.0
        if angle.abs > EPS
          u_axis, v_axis = rotate_axes(u_axis, v_axis, angle)
        end
        if @profile['mirror']
          u_axis = u_axis.reverse
        end

        width_mm = @profile['width'].to_f
        height_mm = @profile['height'].to_f

        if @profile['fit']
          # Fit giữ đúng cơ chế cũ nhưng tâm luôn về tâm khổ Face.
          fit_u = target_vertices.map { |point| point_dot(point, u_axis) }
          fit_v = target_vertices.map { |point| point_dot(point, v_axis) }
          fit_min_u, fit_max_u = fit_u.minmax
          fit_min_v, fit_max_v = fit_v.minmax
          gap = @profile['edge_gap'].to_f

          width_mm = (fit_max_u - fit_min_u).to_mm - gap * 2.0
          height_mm = (fit_max_v - fit_min_v).to_mm - gap * 2.0
          return nil if width_mm <= 1.0 || height_mm <= 1.0

          anchor = point_from_uv(
            target_vertices.first,
            u_axis,
            v_axis,
            (fit_min_u + fit_max_u) / 2.0,
            (fit_min_v + fit_max_v) / 2.0
          )
          snapped = {
            :label => 'TÂM KHỔ VÁN · AUTO FIT',
            :local => anchor,
            :world => anchor.transform(target_world)
          }
        end

        anchor = anchor.offset(u_axis, @profile['offset_x'].to_f.mm)
        anchor = anchor.offset(v_axis, @profile['offset_y'].to_f.mm)

        raw_paths = CNCProfileTool.build_paths(
          @profile,
          width_mm,
          height_mm
        )

        local_paths = raw_paths.map do |path|
          points = path['points'].map do |xy|
            anchor
              .offset(u_axis, xy[0].to_f.mm)
              .offset(v_axis, xy[1].to_f.mm)
          end
          {
            :closed => path['closed'],
            :points => points
          }
        end

        world_paths = local_paths.map do |path|
          {
            :closed => path[:closed],
            :points => path[:points].map { |point| point.transform(target_world) }
          }
        end

        {
          :target => target,
          :face => face,
          :target_world => target_world,
          :local_paths => local_paths,
          :world_paths => world_paths,
          :center_world => anchor.transform(target_world),
          :width_mm => width_mm,
          :height_mm => height_mm,
          :board_width_mm => board_width_mm,
          :board_height_mm => board_height_mm,
          :snap_points_world => snap_points.map { |item| item[:world] },
          :snap_label => snapped && snapped[:label],
          :snap_world => snapped && snapped[:world]
        }
      end

      def point_from_uv(base, u_axis, v_axis, u_value, v_value)
        point = base.offset(
          u_axis,
          u_value - point_dot(base, u_axis)
        )
        point.offset(
          v_axis,
          v_value - point_dot(point, v_axis)
        )
      end

      def build_board_snap_points(
        base,
        u_axis,
        v_axis,
        min_u,
        max_u,
        min_v,
        max_v,
        target_world
      )
        mid_u = (min_u + max_u) / 2.0
        mid_v = (min_v + max_v) / 2.0

        us = [
          ['MÉP U-', min_u],
          ['TÂM U', mid_u],
          ['MÉP U+', max_u]
        ]
        vs = [
          ['MÉP V-', min_v],
          ['TÂM V', mid_v],
          ['MÉP V+', max_v]
        ]

        result = []
        us.each do |u_name, u_value|
          vs.each do |v_name, v_value|
            local = point_from_uv(
              base,
              u_axis,
              v_axis,
              u_value,
              v_value
            )
            label =
              if u_name == 'TÂM U' && v_name == 'TÂM V'
                'TÂM KHỔ VÁN'
              else
                "#{u_name} · #{v_name}"
              end

            result << {
              :label => label,
              :local => local,
              :world => local.transform(target_world)
            }
          end
        end
        result
      end

      def nearest_snap_point(points, view, mouse_x, mouse_y)
        best = nil
        best_distance = SNAP_RADIUS_PX

        points.each do |item|
          screen = view.screen_coords(item[:world])
          dx = screen.x.to_f - mouse_x.to_f
          dy = screen.y.to_f - mouse_y.to_f
          distance = Math.sqrt(dx * dx + dy * dy)
          next if distance > best_distance

          best_distance = distance
          best = item
        end

        best
      end

      def point_dot(point, axis)
        point.x * axis.x + point.y * axis.y + point.z * axis.z
      end

      def safe_unit(vector)
        return nil unless vector
        length = vector.length.to_f
        return nil unless length.finite? && length > EPS
        Geom::Vector3d.new(
          vector.x / length,
          vector.y / length,
          vector.z / length
        )
      rescue StandardError
        nil
      end

      def projected_axis(axis, normal)
        dot = axis.dot(normal)
        safe_unit(
          Geom::Vector3d.new(
            axis.x - normal.x * dot,
            axis.y - normal.y * dot,
            axis.z - normal.z * dot
          )
        )
      end

      def face_axes(normal)
        x = Geom::Vector3d.new(1,0,0)
        y = Geom::Vector3d.new(0,1,0)
        z = Geom::Vector3d.new(0,0,1)

        u = projected_axis(x, normal)
        u ||= projected_axis(y, normal)
        return nil unless u

        v = safe_unit(normal.cross(u))
        return nil unless v

        z_projected = projected_axis(z, normal)
        if z_projected && v.dot(z_projected) < 0.0
          u = u.reverse
          v = v.reverse
        end

        [u, v]
      end

      def rotate_axes(u_axis, v_axis, angle)
        cosine = Math.cos(angle)
        sine = Math.sin(angle)
        u = Geom::Vector3d.new(
          u_axis.x * cosine + v_axis.x * sine,
          u_axis.y * cosine + v_axis.y * sine,
          u_axis.z * cosine + v_axis.z * sine
        )
        v = Geom::Vector3d.new(
          -u_axis.x * sine + v_axis.x * cosine,
          -u_axis.y * sine + v_axis.y * cosine,
          -u_axis.z * sine + v_axis.z * cosine
        )
        [safe_unit(u), safe_unit(v)]
      end

      def create_profile(info)
        target = info[:target]
        raise 'Group/Component đích đã bị xóa.' unless target && target.valid?

        started = false
        @model.start_operation('TT - Tạo Biên Dạng CNC', true)
        started = true

        if target.definition.instances.length > 1 &&
           target.respond_to?(:make_unique)
          target.make_unique
        end

        # Tạo Curve/Line TRỰC TIẾP trong entities của Group/Component chứa Face.
        # Không sinh thêm Group con.
        entities = target.definition.entities

        tag_name = @profile['tag_name'].to_s.strip
        tag_name = CNCProfileTool.abf_name(@profile['name']) if tag_name.empty?
        layer = @model.layers.add(tag_name)

        created_edges = []

        info[:local_paths].each do |path|
          points = path[:points]
          next if points.length < 2

          curve_points = points.dup
          curve_points << points.first if path[:closed]

          edges = entities.add_curve(curve_points)
          raise 'Không tạo được Curve CNC.' if !edges || edges.empty?

          edges.each do |edge|
            next unless edge && edge.valid?

            edge.layer = layer
            edge.set_attribute(DICT, 'profile_id', @profile['id'].to_s)
            edge.set_attribute(DICT, 'profile_name', @profile['name'].to_s)
            edge.set_attribute(DICT, 'instance_name', @profile['instance_name'].to_s)
            edge.set_attribute(DICT, 'tag_name', tag_name)
            edge.set_attribute(DICT, 'profile_json', JSON.generate(@profile))
            edge.set_attribute(DICT, 'welded_curve', true)
            edge.set_attribute(DICT, 'line_only', true)
            created_edges << edge
          end
        end

        raise 'Không tạo được đường CNC.' if created_edges.empty?

        @model.commit_operation
        started = false
        UI.beep
        created_edges
      rescue StandardError
        @model.abort_operation if started
        raise
      end
    end

    def dialog_html
      <<~'HTML'
        <!doctype html>
        <html lang="vi">
        <head>
          <meta charset="utf-8">
          <style>
            *{box-sizing:border-box}
            :root{--bg:#06182d;--panel:#0b2748;--panel2:#0a213c;--blue:#1677e8;--blue2:#45a2ff;--white:#f7fbff;--muted:#b9d8f5;--border:#2d6ea7}
            body{margin:0;background:var(--bg);color:var(--white);font:13px Arial,"Segoe UI",sans-serif}
            .head{padding:16px 18px;background:linear-gradient(135deg,#0a4f9b,#147ce5);border-bottom:1px solid #51a9ff}
            h1{margin:0;font-size:19px}.sub{margin-top:5px;color:#d5ebff}
            .wrap{display:grid;grid-template-columns:300px 1fr;gap:12px;padding:12px;height:680px}
            .panel{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:12px;min-height:0}
            .left{display:flex;flex-direction:column}
            .search{width:100%;padding:9px;border:1px solid #3f7fb5;border-radius:7px;background:#071d35;color:#fff;margin-bottom:8px}
            #list{overflow:auto;flex:1;padding-right:3px}
            .item{display:flex;gap:8px;align-items:center;padding:9px;border:1px solid #244f74;border-radius:8px;margin-bottom:6px;background:#09223f;cursor:pointer}
            .item:hover,.item.active{background:#123d68;border-color:#61b3ff}.item b{font-size:12px}.badge{margin-left:auto;font-size:10px;color:#b9d8f5}
            .right{display:grid;grid-template-columns:1fr 280px;gap:12px;min-height:0}
            .form{overflow:auto;padding-right:4px}
            .preview{background:#071d35;border:1px solid #2d6ea7;border-radius:9px;padding:10px;height:max-content}
            canvas{width:100%;height:260px;background:#06182d;border:1px solid #214e77;border-radius:7px}
            label{display:block;color:#cfe8ff;margin:7px 0 4px}
            input,select{width:100%;padding:8px;background:#071d35;color:#fff;border:1px solid #3f7fb5;border-radius:6px}
            .row{display:grid;grid-template-columns:1fr 1fr;gap:8px}
            .check{display:flex;align-items:center;gap:8px;margin:8px 0;color:#fff}.check input{width:auto}
            .buttons{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}
            button{padding:10px;border:1px solid #53aaff;border-radius:7px;background:linear-gradient(180deg,#2188f3,#0c63be);color:#fff;font-weight:bold;cursor:pointer}
            button.secondary{background:#0b3158}.danger{background:#6f2740!important;border-color:#b45878!important}
            .use{grid-column:1/-1;font-size:14px;padding:13px;background:linear-gradient(180deg,#2c96ff,#0b65c2)}
            .notice{display:none;margin-top:8px;padding:8px;border-radius:6px}.notice.ok{display:block;background:#0d4f55}.notice.error{display:block;background:#6c2639}
            .hint{color:#b9d8f5;line-height:1.45;font-size:12px;margin-top:8px}
            .title{font-weight:bold;color:#8dccff;margin-bottom:8px}
          </style>
        </head>
        <body>
          <div class="head">
            <h1>TẠO BIÊN DẠNG CNC</h1>
            <div class="sub">Thư viện mẫu · preview · tạo Curve/Line trực tiếp trên Face trong Group/Component · không Group con</div>
          </div>
          <div class="wrap">
            <div class="panel left">
              <input id="search" class="search" placeholder="Tìm mẫu CNC..." oninput="renderList()">
              <div id="list"></div>
              <div class="buttons">
                <button class="secondary" onclick="newCopy()">TẠO MẪU MỚI</button>
                <button class="secondary" onclick="resetLib()">KHÔI PHỤC MẪU</button>
              </div>
            </div>

            <div class="right">
              <div class="panel form">
                <div class="title">THÔNG SỐ BIÊN DẠNG</div>
                <label>Tên mẫu</label><input id="name">
                <div class="row">
                  <div><label>Instance / Group</label><input id="instance_name" placeholder="ABF_..."></div>
                  <div><label>Tag</label><input id="tag_name" placeholder="ABF_..."></div>
                </div>
                <label>Loại biên dạng</label><select id="kind" onchange="updateKind();drawPreview()"></select>
                <div class="row">
                  <div><label>Dài / Rộng X (mm)</label><input id="width" type="number" step="1" oninput="drawPreview()"></div>
                  <div><label>Cao Y (mm)</label><input id="height" type="number" step="1" oninput="drawPreview()"></div>
                </div>
                <div class="row">
                  <div><label>Cách mép (mm)</label><input id="edge_gap" type="number" step="1"></div>
                  <div><label>Số đoạn mịn</label><input id="segments" type="number" min="4" max="180" step="1" oninput="drawPreview()"></div>
                </div>
                <label class="check"><input id="fit" type="checkbox"> Tự khít theo Face = kích thước Face trừ 2 × cách mép</label>
                <div class="row">
                  <div><label id="p1_label">Thông số 1</label><input id="p1" type="number" step="1" oninput="drawPreview()"></div>
                  <div><label id="p2_label">Thông số 2</label><input id="p2" type="number" step="1" oninput="drawPreview()"></div>
                </div>
                <div class="row">
                  <div><label>Offset X (mm)</label><input id="offset_x" type="number" step="1"></div>
                  <div><label>Offset Y (mm)</label><input id="offset_y" type="number" step="1"></div>
                </div>
                <div class="row">
                  <div><label>Góc xoay (°)</label><input id="rotation" type="number" step="1" oninput="drawPreview()"></div>
                  <label class="check"><input id="mirror" type="checkbox" onchange="drawPreview()"> Lật ngang</label>
                </div>
                <div class="buttons">
                  <button onclick="saveProfile()">LƯU VÀO THƯ VIỆN</button>
                  <button id="delete_btn" class="danger" onclick="deleteProfile()">XÓA MẪU TỰ TẠO</button>
                  <button class="use" onclick="useProfile()">✓ DÙNG NGAY → RA FACE CLICK ĐỂ ĐẶT</button>
                </div>
                <div id="notice" class="notice"></div>
                <div class="hint">Không cần chọn Group trước. Chọn mẫu → DÙNG NGAY → rà Face; hệ thống tự nhận Group/Component chứa Face và tạo Curve/Line weld TRỰC TIẾP trong chính Group đó, không tạo Group con.</div>
              </div>

              <div class="preview">
                <div class="title">PREVIEW MÔ PHỎNG</div>
                <canvas id="canvas" width="520" height="520"></canvas>
                <div class="hint">Màu xanh: đường CNC sẽ tạo. Tâm preview tương ứng vị trí click trên Face. Khi bật “Tự khít Face”, cách mép sẽ quyết định kích thước thực.</div>
              </div>
            </div>
          </div>

          <script>
            let DATA={profiles:[],selected_id:null,kind_labels:{},kinds:[]};
            let current=null;

            const $=id=>document.getElementById(id);
            function clone(o){return JSON.parse(JSON.stringify(o))}
            function abfName(s){
              let n=(s||'BIEN DANG CNC').trim().replace(/[\\\/:*?"<>|]+/g,'_').replace(/\s+/g,'_').replace(/_+/g,'_');
              return n.startsWith('ABF_')?n:'ABF_'+n;
            }

            window.ttLoad=d=>{
              DATA=d;
              $('kind').innerHTML=DATA.kinds.map(k=>'<option value="'+k+'">'+k+'</option>').join('');
              selectById(DATA.selected_id||DATA.profiles[0]?.id);
              renderList();
            };
            window.ttNotice=(m,k)=>{
              const n=$('notice');n.textContent=m;n.className='notice '+k;
            };

            function renderList(){
              const q=$('search').value.toLowerCase().trim();
              $('list').innerHTML=DATA.profiles.filter(p=>!q||p.name.toLowerCase().includes(q)).map(p=>{
                const active=current&&p.id===current.id?' active':'';
                return '<div class="item'+active+'" onclick="selectById(\''+p.id+'\')"><input type="radio" '+(current&&p.id===current.id?'checked':'')+'><b>'+escapeHtml(p.name)+'</b><span class="badge">'+(p.builtin?'MẪU':'TỰ LƯU')+'</span></div>';
              }).join('');
            }

            function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
            function selectById(id){
              const p=DATA.profiles.find(x=>x.id===id)||DATA.profiles[0];
              if(!p)return;
              current=clone(p);
              fill(current);renderList();drawPreview();
            }
            function fill(p){
              ['name','instance_name','tag_name','kind','width','height','edge_gap','segments','p1','p2','offset_x','offset_y','rotation'].forEach(id=>{
                $(id).value=p[id]??(id==='offset_x'||id==='offset_y'?0:'');
              });
              $('fit').checked=!!p.fit;$('mirror').checked=!!p.mirror;
              $('delete_btn').disabled=!!p.builtin;
              updateKind();
            }
            function read(){
              const p=current?clone(current):{};
              p.name=$('name').value.trim()||'Biên dạng CNC';
              p.instance_name=$('instance_name').value.trim()||abfName(p.name);
              p.tag_name=$('tag_name').value.trim()||abfName(p.name);
              p.kind=$('kind').value;
              ['width','height','edge_gap','segments','p1','p2','offset_x','offset_y','rotation'].forEach(id=>p[id]=Number($(id).value||0));
              p.fit=$('fit').checked;p.mirror=$('mirror').checked;
              return p;
            }
            function updateKind(){
              const labels=DATA.kind_labels[$('kind').value]||['Thông số 1','Thông số 2'];
              $('p1_label').textContent=labels[0];$('p2_label').textContent=labels[1];
            }
            function saveProfile(){sketchup.save_profile(JSON.stringify(read()))}
            function deleteProfile(){if(current&&!current.builtin)sketchup.delete_profile(current.id)}
            function resetLib(){sketchup.reset_library()}
            function useProfile(){sketchup.use_profile(JSON.stringify(read()))}
            function newCopy(){
              const p=read();p.id='';p.builtin=false;p.name='Mẫu CNC mới';p.instance_name='ABF_Mau_CNC_moi';p.tag_name='ABF_Mau_CNC_moi';current=p;fill(p);renderList();drawPreview();
            }

            function roundedRect(w,h,r,n){
              const x=w/2,y=h/2; r=Math.max(.1,Math.min(Math.abs(r),x,y)); n=Math.max(2,Math.min(24,Math.floor(n/4)||2));
              let pts=[];[[x-r,y-r,0,90],[-x+r,y-r,90,180],[-x+r,-y+r,180,270],[x-r,-y+r,270,360]].forEach(a=>{
                for(let i=0;i<=n;i++){const q=(a[2]+(a[3]-a[2])*i/n)*Math.PI/180;pts.push([a[0]+Math.cos(q)*r,a[1]+Math.sin(q)*r])}
              });return pts;
            }
            function shape(p){
              let w=Math.max(5,Number(p.width)||500),h=Math.max(5,Number(p.height)||300),x=w/2,y=h/2,n=Math.max(12,Math.min(160,Number(p.segments)||32)),a=Math.abs(Number(p.p1)||0),b=Math.abs(Number(p.p2)||0),pts=[];
              switch(p.kind){
                case'rounded_rect':return roundedRect(w,h,a,n);
                case'chamfer_rect':{let c=Math.max(.1,Math.min(a,x*.95,y*.95));return [[-x+c,-y],[x-c,-y],[x,-y+c],[x,y-c],[x-c,y],[-x+c,y],[-x,y-c],[-x,-y+c]]}
                case'capsule':return roundedRect(w,h,Math.min(x,y),n);
                case'ellipse':for(let i=0;i<n;i++){let q=2*Math.PI*i/n;pts.push([Math.cos(q)*x,Math.sin(q)*y])}return pts;
                case'arch_top':{let r=Math.max(1,Math.min(a,h*.8)),base=y-r;pts=[[-x,-y],[x,-y],[x,base]];for(let i=0;i<=n;i++){let t=i/n;pts.push([x-w*t,base+r*Math.sin(Math.PI*t)])}return pts}
                case'diamond':return [[0,-y],[x,0],[0,y],[-x,0]];
                case'hexagon':{let c=w*.22;return [[-x+c,-y],[x-c,-y],[x,0],[x-c,y],[-x+c,y],[-x,0]]}
                case'octagon':{let c=Math.max(1,Math.min(a||Math.min(w,h)*.18,x*.9,y*.9));return [[-x+c,-y],[x-c,-y],[x,-y+c],[x,y-c],[x-c,y],[-x+c,y],[-x,y-c],[-x,-y+c]]}
                case'panel_step':{let sx=Math.min(a||40,x*.45),sy=Math.min(b||30,y*.45);return [[-x+sx,-y],[x-sx,-y],[x-sx,-y+sy],[x,-y+sy],[x,y-sy],[x-sx,y-sy],[x-sx,y],[-x+sx,y],[-x+sx,y-sy],[-x,y-sy],[-x,-y+sy],[-x+sx,-y+sy]]}
                default:return [[-x,-y],[x,-y],[x,y],[-x,y]];
              }
            }
            function drawPreview(){
              if(!current)return;
              const p=read(),c=$('canvas'),ctx=c.getContext('2d'),W=c.width,H=c.height;ctx.clearRect(0,0,W,H);
              ctx.fillStyle='#06182d';ctx.fillRect(0,0,W,H);
              ctx.strokeStyle='#244f74';ctx.lineWidth=1;ctx.setLineDash([6,6]);ctx.beginPath();ctx.moveTo(W/2,20);ctx.lineTo(W/2,H-20);ctx.moveTo(20,H/2);ctx.lineTo(W-20,H/2);ctx.stroke();ctx.setLineDash([]);
              let pts=shape(p);if(!pts.length)return;
              let xs=pts.map(q=>q[0]),ys=pts.map(q=>q[1]),minx=Math.min(...xs),maxx=Math.max(...xs),miny=Math.min(...ys),maxy=Math.max(...ys),scale=.82*Math.min(W/(maxx-minx||1),H/(maxy-miny||1));
              ctx.save();ctx.translate(W/2,H/2);ctx.rotate((Number(p.rotation)||0)*Math.PI/180);ctx.scale(p.mirror?-1:1,-1);ctx.strokeStyle='#45a2ff';ctx.lineWidth=4;ctx.beginPath();pts.forEach((q,i)=>{let X=q[0]*scale,Y=q[1]*scale;i?ctx.lineTo(X,Y):ctx.moveTo(X,Y)});ctx.closePath();ctx.stroke();ctx.restore();
              ctx.fillStyle='#ff9b35';ctx.beginPath();ctx.arc(W/2,H/2,5,0,Math.PI*2);ctx.fill();
            }
            document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
          </script>
        </body>
        </html>
      HTML
    end
  end
end
