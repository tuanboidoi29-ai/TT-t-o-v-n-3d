# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - LAYOUT STATS V0.4.0 PATCH
# XEM TRƯỚC TOÀN BỘ BỐ CỤC LAYOUT A3 NGAY TRONG BẢNG THỐNG KÊ.
# Bao gồm: Tổng thể, Trước, Trái, Phải, 3 mặt cắt, Line + X-Ray và TẤT CẢ trang thống kê.
# Chỉ cho phép xuất LayOut/PDF sau khi xem trước thành công.

module TranTuanNoiThat
  module LayoutStats
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '0.4.0'.freeze

    class << self
      unless method_defined?(:tt_v040_base_capture_inline_previews)
        alias_method :tt_v040_base_capture_inline_previews, :capture_inline_previews
      end

      # Giữ engine render 8 hình kỹ thuật của V0.3.0, sau đó ghép thêm
      # từng trang thống kê thật vào gallery xem trước.
      def capture_inline_previews(model, cut_offset_mm)
        items = tt_v040_base_capture_inline_previews(model, cut_offset_mm)
        stats = @stats || build_stats
        chunks = stats[:rows].each_slice(ROWS_PER_PAGE).to_a
        chunks = [[]] if chunks.empty?

        chunks.each_with_index do |chunk, index|
          page_no = 9 + index
          title = if index.zero?
                    format('%02d · THỐNG KÊ VÁN', page_no)
                  else
                    format('%02d · THỐNG KÊ VÁN %d', page_no, index + 1)
                  end
          items << {
            title: title,
            kind: 'stats',
            page_no: page_no,
            stats_page: index + 1,
            stats_pages: chunks.length,
            rows: chunk.map { |row| tt_preview_row(row) }
          }
        end
        items
      end

      def dialog_html
        <<~HTML
          <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:14px Arial}
          .head{padding:20px 24px;background:linear-gradient(135deg,#f97316,#c2410c)}
          h1{margin:0;font-size:22px}.sub{margin-top:5px;opacity:.94}.body{padding:18px}
          .cards{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin-bottom:14px}
          .card,.panel{background:#1f2937;border:1px solid #374151;border-radius:10px;padding:12px}
          .n{font-size:22px;font-weight:bold;color:#fdba74}.k{font-size:11px;color:#9ca3af;margin-top:3px}
          .scope{margin:10px 0;color:#fbbf24}.setup{display:grid;grid-template-columns:190px 1fr auto;gap:10px;align-items:end;margin:12px 0}
          label{display:block;color:#d1d5db;font-size:12px;margin-bottom:5px}
          input{width:100%;padding:10px;border-radius:7px;border:1px solid #4b5563;background:#111827;color:#fff}
          .previewstate{padding:10px 12px;border-radius:8px;background:#7c2d12;color:#fff;margin:12px 0;font-weight:bold}
          .previewstate.ok{background:#065f46}.gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-top:12px}
          .sheet{cursor:zoom-in}.paper{position:relative;width:100%;aspect-ratio:420/297;background:#fff;color:#111827;border:1px solid #6b7280;box-shadow:0 5px 18px #0008;overflow:hidden}
          .paperTop{height:12%;padding:2.3% 3%;border-bottom:1px solid #d1d5db;background:#fff}
          .paperTitle{font-size:clamp(9px,1.15vw,14px);font-weight:700;color:#c2410c;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
          .paperSub{font-size:clamp(6px,.78vw,9px);color:#6b7280;margin-top:1%}
          .viewport{height:72%;margin:1.8% 3%;border:1px solid #d1d5db;background:#f8fafc;display:flex;align-items:center;justify-content:center;overflow:hidden}
          .viewport img{width:100%;height:100%;object-fit:contain;background:#f8fafc}
          .paperFoot{position:absolute;left:3%;right:3%;bottom:2.2%;height:8%;border-top:1px solid #e5e7eb;padding-top:1.2%;font-size:clamp(6px,.75vw,9px);font-weight:700;color:#374151;display:flex;justify-content:space-between;gap:10px}
          .badge{display:inline-block;padding:2px 6px;border-radius:999px;background:#ffedd5;color:#9a3412;font-size:9px;white-space:nowrap}
          .statsPage{height:72%;margin:1.8% 3%;overflow:hidden}.statsPage table{width:100%;border-collapse:collapse;background:#fff;color:#111827;font-size:clamp(5px,.62vw,8px)}
          .statsPage th{position:static;background:#c2410c;color:#fff;padding:3px;border:1px solid #d1d5db;font-size:inherit}.statsPage td{padding:2.5px;border:1px solid #d1d5db;font-size:inherit;color:#111827}
          .statsPage td.r{text-align:right}.tablewrap{max-height:320px;overflow:auto;border:1px solid #374151;border-radius:9px;margin-top:14px}
          .tablewrap table{width:100%;border-collapse:collapse;background:#111827}.tablewrap th{position:sticky;top:0;background:#374151;color:#fff;padding:8px;border:1px solid #4b5563;font-size:12px}
          .tablewrap td{padding:7px;border:1px solid #374151;font-size:12px}.tablewrap td.num{text-align:right;white-space:nowrap}
          .buttons{display:flex;flex-wrap:wrap;gap:10px;margin-top:15px}button{padding:11px 16px;border:0;border-radius:8px;font-weight:bold;cursor:pointer}
          button:disabled{opacity:.35;cursor:not-allowed}.primary{background:#f97316;color:#fff}.green{background:#059669;color:#fff}.blue{background:#2563eb;color:#fff}.dark{background:#374151;color:#fff}
          .note{margin-top:10px;font-size:12px;color:#9ca3af;line-height:1.5}
          .modal{display:none;position:fixed;inset:0;z-index:999;background:#000c;padding:22px;align-items:center;justify-content:center}.modal.show{display:flex}
          .modalCard{width:min(96vw,1280px);max-height:94vh;overflow:auto;background:#111827;border:1px solid #4b5563;border-radius:12px;padding:14px;box-shadow:0 20px 60px #000}
          .modalBar{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;color:#fff;font-weight:bold}.modalClose{background:#374151;color:#fff;padding:7px 12px}
          .modalBody .paper{width:min(1180px,92vw);margin:auto}.modalBody .paperTitle{font-size:20px}.modalBody .paperSub{font-size:12px}.modalBody .paperFoot{font-size:11px}.modalBody .statsPage table{font-size:10px}
          @media(max-width:860px){.gallery{grid-template-columns:1fr}.cards{grid-template-columns:repeat(2,1fr)}.setup{grid-template-columns:1fr}}
          </style></head><body>
          <div class="head"><h1>XUẤT LAYOUT + THỐNG KÊ VÁN</h1>
          <div class="sub">TRẦN TUẤN NỘI THẤT · V<span id="ver">-</span> · XEM TRƯỚC TOÀN BỘ LAYOUT A3 NGAY TRONG BẢNG</div></div>
          <div class="body">

          <div class="cards">
            <div class="card"><div class="n" id="pieces">0</div><div class="k">TỔNG SỐ TẤM</div></div>
            <div class="card"><div class="n" id="types">0</div><div class="k">LOẠI TẤM</div></div>
            <div class="card"><div class="n" id="area">0</div><div class="k">TỔNG m²</div></div>
            <div class="card"><div class="n" id="rows">0</div><div class="k">DÒNG THỐNG KÊ</div></div>
            <div class="card"><div class="n" id="pages">0</div><div class="k">TỔNG TRANG LAYOUT</div></div>
          </div>

          <div class="scope" id="scope">-</div>

          <div class="panel"><b>CÀI ĐẶT + KIỂM TRA TRƯỚC KHI XUẤT</b>
            <div class="setup">
              <div><label>Khoảng cắt từ mặt ngoài (mm)</label><input id="cut" type="number" min="1" max="500" step="1" value="20"></div>
              <div class="note">Bấm xem trước để dựng toàn bộ trang: Tổng thể · Trước · Trái · Phải · Cắt trước · Cắt trái · Cắt phải · Line + X-Ray · tất cả trang thống kê.</div>
              <button class="green" onclick="previewInline()">XEM TRƯỚC LAYOUT</button>
            </div>
          </div>

          <div id="previewstate" class="previewstate">CHƯA XEM TRƯỚC · CHƯA ĐƯỢC XUẤT</div>

          <div class="panel"><b>XEM TRƯỚC TOÀN BỘ LAYOUT A3</b>
            <div class="note">Mọi trang nằm ngay trong bảng này. Bấm vào một trang để phóng lớn. Không mở LayOut/PDF bên ngoài.</div>
            <div id="gallery" class="gallery">
              <div class="sheet"><div class="paper"><div class="paperTop"><div class="paperTitle">CHƯA DỰNG LAYOUT</div><div class="paperSub">Bấm XEM TRƯỚC LAYOUT</div></div><div class="viewport">Chưa có nội dung</div></div></div>
            </div>
          </div>

          <div class="tablewrap"><table><thead><tr>
            <th>STT</th><th>TÊN TẤM</th><th>DÀI</th><th>RỘNG</th><th>DÀY</th><th>SL</th><th>VẬT LIỆU</th><th>VÂN</th><th>m²</th>
          </tr></thead><tbody id="body"></tbody></table></div>

          <div class="buttons">
            <button id="layoutBtn" class="primary" disabled onclick="sketchup.export_layout()">XUẤT LAYOUT</button>
            <button id="pdfBtn" class="blue" disabled onclick="sketchup.export_pdf()">XUẤT PDF</button>
            <button class="dark" onclick="sketchup.refresh()">QUÉT LẠI</button>
            <button class="dark" onclick="window.close()">ĐÓNG</button>
          </div>
          <div class="note"><b>Quy tắc:</b> chưa xem đủ Layout → không thể xuất. Sau khi mô hình/selection/camera thay đổi → phải xem trước lại.</div>
          </div>

          <div id="modal" class="modal" onclick="closeModal(event)"><div class="modalCard" onclick="event.stopPropagation()">
            <div class="modalBar"><span id="modalTitle">XEM TRƯỚC LAYOUT</span><button class="modalClose" onclick="closeModal()">ĐÓNG</button></div>
            <div id="modalBody" class="modalBody"></div>
          </div></div>

          <script>
          const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
          let lastStats=null;

          window.renderStats=d=>{
            lastStats=d; ver.textContent=d.version; pieces.textContent=d.total_pieces; types.textContent=d.total_types;
            area.textContent=Number(d.total_area_m2).toFixed(3); rows.textContent=d.rows.length; pages.textContent=d.page_count;
            cut.value=d.cut_offset_mm||20; scope.textContent='PHẠM VI: '+d.scope+' · '+d.generated_at;
            const tb=document.getElementById('body');tb.innerHTML='';
            d.rows.forEach(r=>{const tr=document.createElement('tr');tr.innerHTML=`<td class="num">${r.stt}</td><td>${esc(r.name)}</td><td class="num">${Number(r.length_mm).toFixed(1)}</td><td class="num">${Number(r.width_mm).toFixed(1)}</td><td class="num">${Number(r.thickness_mm).toFixed(1)}</td><td class="num">${r.qty}</td><td>${esc(r.material)}</td><td>${esc(r.grain)}</td><td class="num">${Number(r.area_m2).toFixed(3)}</td>`;tb.appendChild(tr)});
          };

          window.setPreviewState=(ok,msg)=>{
            const s=document.getElementById('previewstate');s.textContent=msg;s.className='previewstate'+(ok?' ok':'');
            layoutBtn.disabled=!ok;pdfBtn.disabled=!ok;
          };

          function viewSheet(item){
            const total=lastStats?`${lastStats.total_pieces} TẤM · ${lastStats.total_types} LOẠI · ${Number(lastStats.total_area_m2).toFixed(3)} m²`:'';
            return `<div class="paper"><div class="paperTop"><div class="paperTitle">TRẦN TUẤN NỘI THẤT · ${esc(item.title)}</div><div class="paperSub">A3 NGANG · ${esc(lastStats?.scope||'')}</div></div><div class="viewport"><img src="${item.image}"></div><div class="paperFoot"><span>${esc(total)}</span><span class="badge">A3 · ${esc(item.kind||'VIEW')}</span></div></div>`;
          }

          function statsSheet(item){
            let rowsHtml='';
            (item.rows||[]).forEach(r=>{rowsHtml+=`<tr><td class="r">${r.stt}</td><td>${esc(r.name)}</td><td class="r">${Number(r.length_mm).toFixed(0)}</td><td class="r">${Number(r.width_mm).toFixed(0)}</td><td class="r">${Number(r.thickness_mm).toFixed(1)}</td><td class="r">${r.qty}</td><td>${esc(r.material)}</td><td>${esc(r.grain)}</td><td class="r">${Number(r.area_m2).toFixed(3)}</td></tr>`});
            return `<div class="paper"><div class="paperTop"><div class="paperTitle">TRẦN TUẤN NỘI THẤT · ${esc(item.title)}</div><div class="paperSub">A3 NGANG · Trang thống kê ${item.stats_page}/${item.stats_pages}</div></div><div class="statsPage"><table><thead><tr><th>STT</th><th>TÊN TẤM</th><th>DÀI</th><th>RỘNG</th><th>DÀY</th><th>SL</th><th>VẬT LIỆU</th><th>VÂN</th><th>m²</th></tr></thead><tbody>${rowsHtml}</tbody></table></div><div class="paperFoot"><span>${lastStats?lastStats.total_pieces+' TẤM':''}</span><span class="badge">A3 · THỐNG KÊ</span></div></div>`;
          }

          window.renderLayoutPreview=d=>{
            cut.value=d.cut_offset_mm;const g=document.getElementById('gallery');g.innerHTML='';
            (d.items||[]).forEach((item,idx)=>{const e=document.createElement('div');e.className='sheet';e.dataset.title=item.title||('Trang '+(idx+1));e.innerHTML=item.kind==='stats'?statsSheet(item):viewSheet(item);e.onclick=()=>openModal(e);g.appendChild(e)});
          };

          function openModal(sheet){modalTitle.textContent=sheet.dataset.title||'XEM TRƯỚC LAYOUT';modalBody.innerHTML=sheet.querySelector('.paper').outerHTML;modal.classList.add('show')}
          function closeModal(){modal.classList.remove('show');modalBody.innerHTML=''}

          function previewInline(){setPreviewState(false,'ĐANG DỰNG TOÀN BỘ LAYOUT...');gallery.innerHTML='<div class="sheet"><div class="paper"><div class="viewport">ĐANG RENDER...</div></div></div>';sketchup.preview_inline(Number(cut.value));}
          cut.addEventListener('input',()=>setPreviewState(false,'THÔNG SỐ CẮT ĐÃ THAY ĐỔI · PHẢI XEM TRƯỚC LẠI'));
          document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
          </script></body></html>
        HTML
      end
    end
  end
end
