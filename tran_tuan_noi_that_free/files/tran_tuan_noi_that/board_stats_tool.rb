# encoding: UTF-8
require 'json'

module TranTuanNoiThat
  module BoardStatsTool
    extend self

    MAX_ROWS = 30_000

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def child_entities(entity)
      entity.definition.entities
    end

    def path_key(path)
      path.map(&:persistent_id).join('/')
    end

    def path_transform(path)
      path.inject(Geom::Transformation.new) { |tr, entity| tr * entity.transformation }
    end

    def dimensions_mm(entity, path)
      bounds = entity.definition.bounds
      tr = path_transform(path)
      [
        bounds.width  * tr.xaxis.length,
        bounds.height * tr.yaxis.length,
        bounds.depth  * tr.zaxis.length
      ].map { |value| value.to_mm.abs.round(2) }
    end

    def leaf_board?(entity)
      nested = child_entities(entity).any? { |child| container?(child) && child.valid? }
      geometry = child_entities(entity).any? { |child| child.is_a?(Sketchup::Face) || child.is_a?(Sketchup::Edge) }
      !nested && geometry
    end

    def board_row(path)
      entity = path.last
      dims = dimensions_mm(entity, path)
      sorted = dims.sort.reverse
      {
        path_id: path_key(path),
        name: entity.name.to_s,
        tag: entity.layer.name.to_s,
        type: entity.is_a?(Sketchup::Group) ? 'Group' : 'Component',
        length: sorted[0].to_f.round(2),
        width: sorted[1].to_f.round(2),
        thickness: sorted[2].to_f.round(2),
        dims: dims
      }
    end

    def signature(row)
      [
        row[:name].to_s,
        row[:tag].to_s,
        row[:length].round(1),
        row[:width].round(1),
        row[:thickness].round(1)
      ].join('|')
    end

    def show
      if @dialog && @dialog.visible? && @model == Sketchup.active_model
        @dialog.bring_to_front
        return
      end

      close
      @model = Sketchup.active_model
      @paths = {}
      @groups = {}
      @rows = []
      @generation = 0

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN – THỐNG KÊ VÁN',
        preferences_key: 'TT.BoardStats.260',
        width: 1120,
        height: 760,
        resizable: true,
        scrollable: true,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      @dialog.add_action_callback('ready') { |_ctx| scan(false) }
      @dialog.add_action_callback('scan') { |_ctx, all| scan(all == true) }
      @dialog.add_action_callback('find') { |_ctx, id| find_group(id.to_s) }
      @dialog.add_action_callback('select_all_instances') { |_ctx, id| select_group_instances(id.to_s) }
      @dialog.set_on_closed { close(false) }
      @dialog.show
      true
    rescue StandardError => error
      UI.messagebox("Không mở được Thống Kê Ván:\n#{error.message}")
      false
    end

    def close(close_dialog = true)
      @generation = (@generation || 0) + 1
      UI.stop_timer(@timer) if @timer
      @timer = nil
      if close_dialog && @dialog
        @dialog.close rescue nil
      end
      @dialog = nil if close_dialog
      @busy = false
      true
    rescue StandardError
      @busy = false
      true
    end

    def ensure_model
      raise 'Model đã thay đổi. Đóng và mở lại Thống Kê Ván.' unless Sketchup.active_model == @model
    end

    def send_js(fn, data)
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("#{fn}(#{JSON.generate(data)});")
    end

    def scan(all = false)
      ensure_model
      @generation += 1
      generation = @generation
      @busy = true
      UI.stop_timer(@timer) if @timer

      prefix = all ? [] : (@model.active_path || [])
      selected = all ? [] : @model.selection.to_a.select { |entity| container?(entity) }

      roots =
        if selected.empty?
          source = all ? @model.entities : @model.active_entities
          source.select { |entity| container?(entity) }.map { |entity| prefix + [entity] }
        else
          selected.map { |entity| prefix + [entity] }
        end

      queue = roots
      @paths = {}
      raw_rows = []
      visited = {}

      send_js('scanState', {busy: true, message: 'Đang quét ván…'})

      tick = nil
      tick = proc do
        begin
          next if generation != @generation
          ensure_model

          160.times do
            path = queue.pop
            break unless path
            next unless path.all?(&:valid?)

            id = path_key(path)
            next if visited[id]
            visited[id] = true

            entity = path.last
            if leaf_board?(entity)
              raise 'Vượt 30.000 tấm. Hãy quét theo từng cụm.' if raw_rows.length >= MAX_ROWS
              row = board_row(path)
              raw_rows << row
              @paths[id] = path
            else
              raise 'Cấu trúc lồng quá 64 cấp.' if path.length >= 64
              child_entities(entity).each do |child|
                next unless container?(child) && child.valid?
                next if path.any? { |parent| parent.definition == child.definition }
                queue << path + [child]
              end
            end
          end

          if queue.empty?
            @timer = nil
            @busy = false
            publish(raw_rows)
          else
            send_js('scanState', {busy: true, message: "Đã nhận #{raw_rows.length} tấm…"})
            @timer = UI.start_timer(0.01, false, &tick)
          end
        rescue StandardError => error
          @busy = false
          @timer = nil
          send_js('scanState', {busy: false, message: 'Quét chưa hoàn tất'})
          send_js('showError', error.message)
        end
      end

      tick.call
      true
    rescue StandardError => error
      @busy = false
      send_js('showError', error.message)
      false
    end

    def publish(raw_rows)
      grouped = {}
      raw_rows.each do |row|
        key = signature(row)
        entry = (grouped[key] ||= {
          id: key,
          name: row[:name],
          tag: row[:tag],
          length: row[:length],
          width: row[:width],
          thickness: row[:thickness],
          qty: 0,
          paths: []
        })
        entry[:qty] += 1
        entry[:paths] << row[:path_id]
      end

      @groups = grouped
      @rows = grouped.values.map do |entry|
        area = entry[:length] * entry[:width] * entry[:qty] / 1_000_000.0
        {
          id: entry[:id],
          name: entry[:name],
          tag: entry[:tag],
          length: entry[:length],
          width: entry[:width],
          thickness: entry[:thickness],
          qty: entry[:qty],
          area_m2: area.round(3)
        }
      end.sort_by { |row| [row[:thickness], row[:name].downcase, -row[:length], -row[:width]] }

      total_qty = @rows.sum { |row| row[:qty] }
      total_area = @rows.sum { |row| row[:area_m2] }
      thickness = @rows.group_by { |row| row[:thickness].round(1) }.map do |value, list|
        {value: value, qty: list.sum { |row| row[:qty] }}
      end.sort_by { |item| item[:value] }

      send_js('setStats', {
        rows: @rows,
        summary: {
          total_qty: total_qty,
          total_types: @rows.length,
          total_area_m2: total_area.round(3),
          thickness: thickness
        }
      })
      send_js('scanState', {busy: false, message: "Quét xong #{total_qty} tấm · #{@rows.length} loại."})
      true
    end

    def first_valid_path(group_id)
      group = @groups[group_id]
      raise 'Dòng thống kê không còn tồn tại. Quét lại.' unless group
      path_id = Array(group[:paths]).find do |id|
        path = @paths[id]
        path && path.all?(&:valid?)
      end
      raise 'Các tấm của dòng này đã thay đổi. Quét lại.' unless path_id
      @paths[path_id]
    end

    def find_group(group_id)
      ensure_model
      raise 'Đợi quét xong.' if @busy
      path = first_valid_path(group_id)
      raise 'Tấm hoặc nhóm cha đang khóa.' if path.any?(&:locked?)

      parent = path[0...-1]
      @model.active_path = parent.empty? ? nil : parent
      @model.selection.clear
      @model.selection.add(path.last)
      @model.active_view.zoom(@model.selection)
      @model.active_view.invalidate
      true
    rescue StandardError => error
      send_js('showError', error.message)
      false
    end

    def select_group_instances(group_id)
      ensure_model
      raise 'Đợi quét xong.' if @busy
      group = @groups[group_id]
      raise 'Dòng thống kê không còn tồn tại. Quét lại.' unless group

      paths = Array(group[:paths]).map { |id| @paths[id] }.compact.select { |path| path.all?(&:valid?) }
      raise 'Không còn tấm hợp lệ.' if paths.empty?

      parents = paths.map { |path| path[0...-1].map(&:persistent_id) }.uniq
      if parents.length == 1
        parent = paths.first[0...-1]
        @model.active_path = parent.empty? ? nil : parent
        @model.selection.clear
        paths.each { |path| @model.selection.add(path.last) unless path.last.locked? }
        @model.active_view.zoom(@model.selection) unless @model.selection.empty?
      else
        find_group(group_id)
        send_js('notice', 'Các tấm nằm ở nhiều Group cha. Đã zoom tới một tấm đại diện.')
      end
      true
    rescue StandardError => error
      send_js('showError', error.message)
      false
    end

    def html
      <<~'HTML'
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TT – Thống Kê Ván</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:14px Arial,sans-serif}
.top{padding:16px 18px;background:#f97316;color:#fff}.top h1{margin:0 0 4px;font-size:22px}.top p{margin:0}
.wrap{padding:14px}.bar{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:10px}
button,input{font:inherit}button{border:0;border-radius:6px;background:#334155;color:#fff;padding:9px 12px;cursor:pointer}.primary{background:#ea580c}button:disabled{opacity:.45}
input{padding:9px;border:1px solid #475569;border-radius:6px;background:#111827;color:#fff;min-width:280px}
.stats{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.stats span{padding:9px 12px;border-radius:7px;background:#172033;border:1px solid #334155}
.panel{background:#172033;border:1px solid #334155;border-radius:9px;padding:12px}.table-wrap{height:500px;overflow:auto;border:1px solid #334155;border-radius:7px}
table{border-collapse:collapse;width:100%;font-size:13px}th{position:sticky;top:0;background:#1e293b;z-index:1}th,td{padding:8px 7px;border-bottom:1px solid #334155;text-align:left}
tr:hover{background:#1e293b}.muted{color:#94a3b8;font-size:12px}.err{color:#fca5a5;min-height:20px}.ok{color:#86efac}
.thick{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}.pill{padding:6px 9px;background:#0b1220;border-radius:999px;border:1px solid #334155}
.num{text-align:right}.name{font-weight:bold;color:#fdba74}
</style>
</head>
<body>
<div class="top">
  <h1>THỐNG KÊ VÁN</h1>
  <p>Chức năng riêng chỉ để quét và thống kê ván. Không đổi tên đối tượng.</p>
</div>
<div class="wrap">
  <div class="bar">
    <button id="scan" class="primary" onclick="scan(false)">QUÉT VÙNG ĐANG CHỌN</button>
    <button id="scan-all" onclick="scan(true)">QUÉT TOÀN MODEL</button>
    <input id="filter" type="text" placeholder="Tìm tên, Tag, độ dày…" oninput="render()">
  </div>
  <div id="message" class="ok">Chưa quét.</div>
  <div id="error" class="err"></div>
  <div id="stats" class="stats"></div>
  <div id="thickness" class="thick"></div>

  <section class="panel">
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Tên ván</th><th>Tag/Layer</th><th class="num">Dài</th><th class="num">Rộng</th><th class="num">Dày</th><th class="num">SL</th><th class="num">m²</th><th>Tìm</th></tr>
        </thead>
        <tbody id="rows"></tbody>
      </table>
    </div>
    <p class="muted">Dài/Rộng/Dày lấy từ kích thước thực của Group/Component và scale hiện tại. Dày = cạnh nhỏ nhất; Dài/Rộng là hai cạnh còn lại. Các hình không phải dạng tấm nên kiểm tra lại.</p>
  </section>
</div>
<script>
let rows=[];
const el=id=>document.getElementById(id);
function showError(s){el('error').textContent=s||''}
function notice(s){el('message').textContent=s||''}
function scan(all){showError('');sketchup.scan(all)}
function scanState(s){el('message').textContent=s.message||'';document.querySelectorAll('#scan,#scan-all').forEach(b=>b.disabled=!!s.busy)}
function filtered(){let q=el('filter').value.trim().toLocaleLowerCase();return rows.filter(r=>!q||[r.name,r.tag,r.thickness].join(' ').toLocaleLowerCase().includes(q))}
function fmt(v,d=1){return Number(v||0).toFixed(d)}
function render(){
  let body=el('rows');body.innerHTML='';
  filtered().forEach(r=>{
    let tr=document.createElement('tr');
    let vals=[r.name||'(Không tên)',r.tag||'Untagged',fmt(r.length),fmt(r.width),fmt(r.thickness),r.qty,fmt(r.area_m2,3)];
    vals.forEach((v,i)=>{let td=document.createElement('td');td.textContent=v;if(i>=2)td.className='num';if(i===0)td.className='name';tr.appendChild(td)});
    let td=document.createElement('td');
    let b=document.createElement('button');b.textContent='Tìm';b.onclick=()=>sketchup.find(r.id);td.appendChild(b);
    let all=document.createElement('button');all.textContent='Chọn SL';all.style.marginLeft='5px';all.onclick=()=>sketchup.select_all_instances(r.id);td.appendChild(all);
    tr.appendChild(td);body.appendChild(tr)
  })
}
function setStats(data){
  rows=data.rows||[];
  let s=data.summary||{};
  el('stats').innerHTML='';
  ['Tổng số tấm: '+(s.total_qty||0),'Số loại: '+(s.total_types||0),'Tổng diện tích: '+fmt(s.total_area_m2,3)+' m²'].forEach(t=>{let n=document.createElement('span');n.textContent=t;el('stats').appendChild(n)});
  el('thickness').innerHTML='';
  (s.thickness||[]).forEach(x=>{let p=document.createElement('span');p.className='pill';p.textContent=fmt(x.value)+' mm · '+x.qty+' tấm';el('thickness').appendChild(p)});
  render()
}
window.addEventListener('load',()=>sketchup.ready())
</script>
</body>
</html>
      HTML
    end
  end
end
