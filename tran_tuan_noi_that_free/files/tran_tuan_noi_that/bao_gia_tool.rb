# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT - BẢNG BÁO GIÁ
# Tích hợp từ file baogia.rb do người dùng cung cấp.
# Giữ nguyên công thức tính của nguồn:
# - m² / m³ = Dài x Rộng x Cao (mm³ / 1e9) x Số lượng
# - m và các ĐVT khác = Số lượng
#
# Chức năng:
# - Thêm/xóa hạng mục
# - Lưu/Mở JSON
# - Chiết khấu, VAT, tổng cộng
# - Lưu ngân hàng / ĐVT
# - QR VietQR
# - Xuất PDF bằng Edge/Chrome headless
# - Chia sẻ PDF qua Zalo
# - Chỉ mở khi người dùng gọi, không tự chạy lúc SketchUp khởi động.

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'cgi'
require 'net/http'
require 'uri'
require 'base64'
require 'openssl'

module TranTuanNoiThat
  module BaoGiaTool
    extend self

    VERSION = '1.9.144'.freeze
    ROOT = File.join(TranTuanNoiThat::ROOT, 'data', 'bao_gia').freeze

    DEFAULT_DVT = [
      'Bộ','Cái','Chiếc','Tấm','Ván','m','m²','m³',
      'kg','g','L','Hộp','Công','Giờ','Ngày','Lần','Set','Khác'
    ].freeze

    BANK_CODES = {
      'VIETCOMBANK'=>'VCB','VCB'=>'VCB',
      'BIDV'=>'BIDV',
      'VIETINBANK'=>'CTG','CTG'=>'CTG',
      'AGRIBANK'=>'AGRIBANK',
      'MB BANK'=>'MB','MBANK'=>'MB','MBBANK'=>'MB','MB'=>'MB',
      'TECHCOMBANK'=>'TCB','TCB'=>'TCB',
      'ACB'=>'ACB',
      'VPBANK'=>'VPB','VPB'=>'VPB',
      'TPBANK'=>'TPB','TPB'=>'TPB',
      'SACOMBANK'=>'STB','STB'=>'STB',
      'HDBANK'=>'HDB','HDB'=>'HDB',
      'VIB'=>'VIB',
      'SHB'=>'SHB',
      'EXIMBANK'=>'EIB','EIB'=>'EIB',
      'MSB'=>'MSB',
      'OCB'=>'OCB',
      'LPBANK'=>'LPB','LPB'=>'LPB',
      'NAM A BANK'=>'NAB','NAMABANK'=>'NAB','NAB'=>'NAB',
      'BAC A BANK'=>'BAB','BACABANK'=>'BAB','BAB'=>'BAB',
      'ABBANK'=>'ABB','AB BANK'=>'ABB',
      'NCB'=>'NCB',
      'KIENLONGBANK'=>'KLB','KLB'=>'KLB',
      'VIETABANK'=>'VAB','VAB'=>'VAB',
      'SEABANK'=>'SEAB','SEAB'=>'SEAB',
      'PVCOMBANK'=>'PVCB','PVCB'=>'PVCB',
      'BAOVIETBANK'=>'BVB','BVB'=>'BVB',
      'SAIGONBANK'=>'SGB','SGB'=>'SGB',
      'LIO BANK'=>'LIOBANK','LIOBANK'=>'LIOBANK','LIO'=>'LIOBANK'
    }.freeze

    def ensure_data
      FileUtils.mkdir_p(ROOT)
    end

    def read_json(name, fallback)
      ensure_data
      path = File.join(ROOT, name)
      return fallback unless File.file?(path)
      JSON.parse(File.read(path, encoding: 'UTF-8'))
    rescue StandardError
      fallback
    end

    def write_json(name, value)
      ensure_data
      File.write(File.join(ROOT, name), JSON.pretty_generate(value), encoding: 'UTF-8')
      true
    rescue StandardError => error
      UI.messagebox("Không thể lưu dữ liệu:\n#{error.message}")
      false
    end

    def dvt
      values = read_json('don_vi_tinh.json', DEFAULT_DVT)
      values.is_a?(Array) && !values.empty? ? values.map(&:to_s).uniq : DEFAULT_DVT
    end

    def bank
      value = read_json('ngan_hang.json', {})
      value.is_a?(Hash) ? value : {}
    end

    def num(value)
      return value.to_f if value.is_a?(Numeric)
      text = value.to_s.strip.gsub(/\s+/, '')
      return 0.0 if text.empty?

      if text.include?('.') && text.include?(',')
        if text.rindex(',') > text.rindex('.')
          text = text.delete('.').tr(',', '.')
        else
          text = text.delete(',')
        end
      elsif text.include?(',')
        pieces = text.split(',')
        text = if pieces.length == 2 && pieces[1].length <= 2
          pieces[0].delete('.') + '.' + pieces[1]
        else
          text.delete(',')
        end
      elsif text.include?('.')
        pieces = text.split('.')
        text = text.delete('.') if pieces.length > 2 ||
          (pieces.length == 2 && pieces[1].length == 3 && pieces[0].length <= 3)
      end
      Float(text)
    rescue StandardError
      0.0
    end

    def money(value)
      number = num(value).round
      number.to_s.reverse.scan(/.{1,3}/).join('.').reverse + ' ₫'
    end

    def safe(value)
      CGI.escapeHTML(value.to_s)
    end

    def new_row
      {
        'hang_muc'=>'',
        'mo_ta'=>'',
        'dvt'=>'m²',
        'dai'=>'',
        'rong'=>'',
        'cao'=>'',
        'so_luong'=>'1',
        'don_gia'=>'0'
      }
    end

    # Giữ nguyên công thức trong file baogia.rb nguồn.
    def calc_row(row)
      length = num(row['dai'])
      width  = num(row['rong'])
      height = num(row['cao'])
      qty    = num(row['so_luong'])

      case row['dvt'].to_s
      when 'm²', 'm³'
        (length * width * height / 1_000_000_000.0) * qty
      when 'm'
        qty
      else
        qty
      end
    end

    def totals(data)
      subtotal = Array(data['rows']).inject(0.0) do |sum, row|
        sum + calc_row(row) * num(row['don_gia'])
      end
      discount = subtotal * num(data['chiet_khau']) / 100.0
      after_discount = subtotal - discount
      vat = after_discount * num(data['vat']) / 100.0
      [subtotal, discount, vat, after_discount + vat]
    end

    def parse(text)
      data = JSON.parse(text.to_s)
      data['rows'] = [] unless data['rows'].is_a?(Array)
      data
    rescue StandardError
      {'rows'=>[]}
    end

    def bank_id(name)
      input = name.to_s.strip
      return '' if input.empty?
      key = input.upcase.gsub(/\s+/, ' ')
      BANK_CODES.each do |candidate, value|
        return value if candidate.upcase == key
      end
      input
    end

    def qr_url(data, amount)
      bank = bank_id(data['bankName'])
      account = data['accountNo'].to_s.strip.gsub(/\s+/, '')
      return '' if bank.empty? || account.empty?

      info = data['transferNote'].to_s.strip
      info = data['ma_bao_gia'].to_s.strip if info.empty?
      owner = data['accountName'].to_s.strip

      query = [
        "amount=#{CGI.escape(amount.round.to_s)}",
        "addInfo=#{CGI.escape(info[0, 50])}",
        "accountName=#{CGI.escape(owner)}"
      ]
      "https://img.vietqr.io/image/#{CGI.escape(bank)}-#{CGI.escape(account)}-compact2.jpg?#{query.join('&')}"
    end

    def fetch_qr_data_uri(data, amount)
      url = qr_url(data, amount)
      return '' if url.empty?

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      response = http.get(uri.request_uri)
      return '' unless response.is_a?(Net::HTTPSuccess)

      content_type = response['content-type'].to_s.split(';').first
      return '' unless content_type.include?('image')
      "data:#{content_type};base64,#{Base64.strict_encode64(response.body)}"
    rescue StandardError
      ''
    end

    def save_quote(text)
      data = parse(text)
      default = data['ma_bao_gia'].to_s.strip
      default = "BaoGia_#{Time.now.strftime('%Y%m%d_%H%M%S')}" if default.empty?
      path = UI.savepanel('Lưu báo giá', nil, "#{default}.json")
      return false unless path

      File.write(path, JSON.pretty_generate(data), encoding: 'UTF-8')
      UI.messagebox("Đã lưu báo giá:\n#{path}")
      true
    rescue StandardError => error
      UI.messagebox("Lỗi lưu báo giá:\n#{error.message}")
      false
    end

    def open_quote(dialog)
      path = UI.openpanel('Mở báo giá', nil, 'JSON|*.json||')
      return false unless path

      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      dialog.execute_script("window.TT_BG_LOAD(#{JSON.generate(data)});")
      true
    rescue StandardError => error
      UI.messagebox("Lỗi mở báo giá:\n#{error.message}")
      false
    end

    def save_bank(text)
      data = JSON.parse(text.to_s)
      write_json('ngan_hang.json', data)
      UI.messagebox('Đã lưu thông tin ngân hàng.')
      true
    rescue StandardError => error
      UI.messagebox("Lỗi lưu ngân hàng:\n#{error.message}")
      false
    end

    def save_dvt(text)
      values = JSON.parse(text.to_s)
      values = DEFAULT_DVT unless values.is_a?(Array)
      values = values.map(&:to_s).map(&:strip).reject(&:empty?).uniq
      values = DEFAULT_DVT if values.empty?
      write_json('don_vi_tinh.json', values)
      UI.messagebox('Đã lưu danh sách ĐVT.')
      true
    rescue StandardError => error
      UI.messagebox("Lỗi lưu ĐVT:\n#{error.message}")
      false
    end

    def open_qr(url)
      UI.openURL(url.to_s) unless url.to_s.empty?
    rescue StandardError => error
      UI.messagebox("Không mở được QR:\n#{error.message}")
    end

    def printable_html(data, qr)
      subtotal, discount, vat, total = totals(data)

      rows = Array(data['rows']).each_with_index.map do |raw, index|
        row = new_row.merge(raw)
        computed = calc_row(row)
        <<~ROW
          <tr>
            <td>#{index + 1}</td>
            <td>#{safe(row['hang_muc'])}</td>
            <td>#{safe(row['mo_ta'])}</td>
            <td>#{safe(row['dvt'])}</td>
            <td>#{safe(row['dai'])}</td>
            <td>#{safe(row['rong'])}</td>
            <td>#{safe(row['cao'])}</td>
            <td>#{safe(row['so_luong'])}</td>
            <td>#{format('%.3f', computed)}</td>
            <td>#{money(row['don_gia'])}</td>
            <td>#{money(computed * num(row['don_gia']))}</td>
          </tr>
        ROW
      end.join

      qr_html = if qr.empty?
        '<div class="qrbox"><b>QR CHUYỂN KHOẢN</b><p>Không tạo được QR. Kiểm tra ngân hàng và số tài khoản.</p></div>'
      else
        <<~QR
          <div class="qrbox">
            <div><b>QR CHUYỂN KHOẢN</b><br><img src="#{qr}" class="qrimg"></div>
            <div class="qrinfo">
              <b>Ngân hàng:</b> #{safe(data['bankName'])}<br>
              <b>Số TK:</b> #{safe(data['accountNo'])}<br>
              <b>Chủ TK:</b> #{safe(data['accountName'])}<br>
              <b>Nội dung:</b> #{safe(data['transferNote'])}<br>
              <b>Số tiền:</b> #{money(total)}
            </div>
          </div>
        QR
      end

      <<~HTML
        <!doctype html>
        <html lang="vi"><head><meta charset="utf-8">
        <title>Báo giá #{safe(data['ma_bao_gia'])}</title>
        <style>
          body{font-family:Arial,sans-serif;margin:28px;color:#222}
          h1{text-align:center}
          table{width:100%;border-collapse:collapse;font-size:11px}
          th,td{border:1px solid #999;padding:5px}
          th{background:#eee}
          .sum{width:360px;margin-left:auto}
          .qrbox{margin-top:20px;border:1px solid #888;padding:15px;display:flex;gap:25px;align-items:center;page-break-inside:avoid}
          .qrimg{width:220px;height:220px}
          .qrinfo{line-height:1.8}
        </style></head><body>
        <h1>BẢNG BÁO GIÁ NỘI THẤT</h1>
        <p><b>Mã:</b> #{safe(data['ma_bao_gia'])} &nbsp; <b>Ngày:</b> #{safe(data['ngay'])}</p>
        <p><b>Khách hàng:</b> #{safe(data['khach_hang'])} &nbsp; <b>Điện thoại:</b> #{safe(data['dien_thoai'])}</p>
        <p><b>Địa chỉ:</b> #{safe(data['dia_chi'])}</p>
        <table>
          <tr><th>STT</th><th>Hạng mục</th><th>Mô tả</th><th>ĐVT</th><th>Dài</th><th>Rộng</th><th>Cao</th><th>SL</th><th>SL tính giá</th><th>Đơn giá</th><th>Thành tiền</th></tr>
          #{rows}
        </table>
        <div class="sum">
          <p>Tạm tính: <b>#{money(subtotal)}</b></p>
          <p>Chiết khấu: <b>#{money(discount)}</b></p>
          <p>VAT: <b>#{money(vat)}</b></p>
          <h2>TỔNG CỘNG: #{money(total)}</h2>
        </div>
        #{qr_html}
        </body></html>
      HTML
    end

    def export_pdf(text)
      data = parse(text)
      _subtotal, _discount, _vat, total = totals(data)
      qr = fetch_qr_data_uri(data, total)
      html = printable_html(data, qr)

      default = data['ma_bao_gia'].to_s.strip
      default = "BaoGia_#{Time.now.strftime('%Y%m%d_%H%M%S')}" if default.empty?
      pdf = UI.savepanel('Chọn nơi lưu PDF', nil, "#{default}.pdf")
      return false unless pdf

      dir = File.dirname(pdf)
      stem = File.basename(pdf, '.pdf')
      html_path = File.join(dir, "#{stem}_print.html")
      File.write(html_path, html, encoding: 'UTF-8')

      candidates = [
        File.join(ENV['PROGRAMFILES'].to_s, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        File.join(ENV['PROGRAMFILES(X86)'].to_s, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        File.join(ENV['PROGRAMFILES'].to_s, 'Google', 'Chrome', 'Application', 'chrome.exe'),
        File.join(ENV['PROGRAMFILES(X86)'].to_s, 'Google', 'Chrome', 'Application', 'chrome.exe')
      ]
      executable = candidates.find { |candidate| File.file?(candidate) }

      if executable
        uri = 'file:///' + html_path.gsub('\\', '/')
        command = "\"#{executable}\" --headless --disable-gpu --no-sandbox --print-to-pdf=\"#{pdf}\" \"#{uri}\""
        system(command)
      end

      if File.file?(pdf) && File.size(pdf) > 0
        @last_pdf_path = pdf
        UI.messagebox("Đã xuất PDF có QR chuyển khoản:\n#{pdf}")
        true
      else
        @last_pdf_path = nil
        UI.messagebox("Không tự tạo được PDF.\nHTML đã được tạo:\n#{html_path}\n\nHãy mở HTML và nhấn Ctrl+P để lưu PDF.")
        UI.openURL('file:///' + html_path.gsub('\\', '/'))
        false
      end
    rescue StandardError => error
      UI.messagebox("Lỗi xuất PDF:\n#{error.message}")
      false
    end

    def share_zalo(text)
      export_pdf(text)
      path = @last_pdf_path.to_s
      return false if path.empty? || !File.file?(path)

      begin
        UI.openURL('zalo://')
      rescue StandardError
        UI.openURL('https://chat.zalo.me/')
      end

      begin
        system(%Q{explorer.exe /select,"#{path.gsub('/', '\\')}"})
      rescue StandardError
      end

      UI.messagebox("Đã mở Zalo và chọn file PDF trong Explorer.\nKéo file PDF vào cuộc trò chuyện Zalo để gửi.")
      true
    rescue StandardError => error
      UI.messagebox("Lỗi chia sẻ Zalo:\n#{error.message}")
      false
    end

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TRẦN TUẤN - Bảng Báo Giá',
        preferences_key: 'TranTuanNoiThat.BaoGia.128',
        scrollable: true,
        resizable: true,
        width: 1180,
        height: 820,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      @dialog.add_action_callback('bg_save') { |_ctx, payload| save_quote(payload) }
      @dialog.add_action_callback('bg_open') { |_ctx| open_quote(@dialog) }
      @dialog.add_action_callback('bg_bank') { |_ctx, payload| save_bank(payload) }
      @dialog.add_action_callback('bg_dvt') { |_ctx, payload| save_dvt(payload) }
      @dialog.add_action_callback('bg_qr') { |_ctx, url| open_qr(url) }
      @dialog.add_action_callback('bg_pdf') { |_ctx, payload| export_pdf(payload) }
      @dialog.add_action_callback('bg_zalo') { |_ctx, payload| share_zalo(payload) }

      @dialog.set_html(dialog_html)
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
      @dialog.center
    rescue StandardError => error
      UI.messagebox("Không mở được Bảng Báo Giá:\n#{error.message}")
    end

    def dialog_html
      bank_data = bank
      units = JSON.generate(dvt)
      <<~'HTML'.sub('__DVT__', units)
        <!doctype html>
        <html lang="vi"><head><meta charset="utf-8">
        <style>
          *{box-sizing:border-box}
          body{margin:0;background:#eef2f5;font-family:Arial;color:#222}
          .wrap{padding:14px}.head,.card{background:#fff;border-radius:10px;padding:14px;margin-bottom:12px}
          .head{background:#111827;color:#fff}.head h2{margin:0}
          .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
          label{font-size:12px;font-weight:bold;display:block;margin-bottom:4px}
          input,select{width:100%;padding:8px;border:1px solid #bbb;border-radius:6px}
          button{padding:9px 12px;border:0;border-radius:6px;cursor:pointer;font-weight:bold}
          .bar{display:flex;gap:7px;flex-wrap:wrap}.dark{background:#111827;color:#fff}.blue{background:#1d4ed8;color:#fff}
          .green{background:#166534;color:#fff}.gray{background:#e5e7eb}.red{background:#b42318;color:#fff}
          .tablebox{overflow:auto}table{border-collapse:collapse;width:100%;min-width:1200px}
          th,td{border:1px solid #bbb;padding:5px}th{background:#eee;font-size:11px}
          td input,td select{padding:6px}.mini{width:78px;margin:2px}.calc{text-align:right;white-space:nowrap}
          .sum{max-width:400px;margin-left:auto}.sum p{display:flex;justify-content:space-between}
          .big{font-size:20px;border-top:2px solid #111;padding-top:8px}
          .pay{display:grid;grid-template-columns:1fr 260px;gap:15px}
          .qr{min-height:260px;border:1px dashed #999;background:#fff;display:flex;align-items:center;justify-content:center;text-align:center}
          .qr img{width:235px;height:235px}
          .status{padding:9px;border-radius:6px;background:#dcfce7;color:#166534;margin-bottom:10px}
          .err{background:#fee2e2;color:#991b1b}
        </style></head><body><div class="wrap">
          <div class="head"><h2>TRẦN TUẤN — BẢNG BÁO GIÁ</h2><small>Lưu/Mở · QR · PDF · Zalo</small></div>
          <div id="status" class="status">Đang khởi tạo...</div>

          <div class="card"><div class="grid">
            <div><label>Mã báo giá</label><input id="ma"></div>
            <div><label>Ngày</label><input id="ngay"></div>
            <div><label>Khách hàng</label><input id="khach"></div>
            <div><label>Điện thoại</label><input id="phone"></div>
            <div><label>Địa chỉ</label><input id="address"></div>
            <div><label>Người lập</label><input id="maker"></div>
            <div><label>Chiết khấu %</label><input id="discount" value="0"></div>
            <div><label>VAT %</label><input id="vat" value="0"></div>
          </div></div>

          <div class="card">
            <div class="bar">
              <button id="add" class="dark">＋ THÊM HẠNG MỤC</button>
              <button id="save" class="blue">💾 LƯU</button>
              <button id="open" class="gray">📂 MỞ</button>
              <button id="pdf" class="green">📄 XUẤT PDF</button>
              <button id="zalo" class="blue">💬 ZALO</button>
            </div>
            <div class="tablebox"><table>
              <thead><tr>
                <th>STT</th><th>Hạng mục</th><th>Mô tả</th><th>ĐVT</th>
                <th>Dài</th><th>Rộng</th><th>Cao</th><th>SL</th>
                <th>SL tính giá</th><th>Đơn giá</th><th>Thành tiền</th><th>Xóa</th>
              </tr></thead>
              <tbody id="rows"></tbody>
            </table></div>
          </div>

          <div class="card"><div class="sum">
            <p><span>Tạm tính</span><b id="sub">0 ₫</b></p>
            <p><span>Chiết khấu</span><b id="dis">0 ₫</b></p>
            <p><span>VAT</span><b id="vatmoney">0 ₫</b></p>
            <p class="big"><span>TỔNG CỘNG</span><b id="total">0 ₫</b></p>
          </div></div>

          <div class="card"><h3>THÔNG TIN CHUYỂN KHOẢN</h3>
            <div class="pay">
              <div><div class="grid">
                <div><label>Ngân hàng</label><input id="bank"></div>
                <div><label>Số tài khoản</label><input id="account"></div>
                <div><label>Chủ tài khoản</label><input id="owner"></div>
                <div><label>Chi nhánh</label><input id="branch"></div>
                <div style="grid-column:span 2"><label>Nội dung chuyển khoản</label><input id="note"></div>
              </div><br><button id="saveBank" class="green">💾 LƯU NGÂN HÀNG</button></div>
              <div class="qr" id="qr"><span>Nhập ngân hàng + số tài khoản để tạo QR</span></div>
            </div>
          </div>

          <div class="card"><h3>ĐƠN VỊ TÍNH</h3>
            <div class="bar"><input id="newDvt" placeholder="Nhập ĐVT mới" style="max-width:250px">
            <button id="addDvt" class="gray">＋ THÊM</button>
            <button id="saveDvt" class="green">💾 LƯU ĐVT</button></div>
          </div>
        </div>

        <script>
        (function(){
          'use strict';
          var rows=[];
          var dvt=__DVT__;

          function $(id){return document.getElementById(id);}
          function status(text,error){var el=$('status');el.className='status'+(error?' err':'');el.textContent=text;}
          function num(v){
            var s=String(v==null?'':v).replace(/\s/g,'').trim(); if(!s)return 0;
            if(s.indexOf('.')>=0&&s.indexOf(',')>=0){
              if(s.lastIndexOf(',')>s.lastIndexOf('.'))s=s.replace(/\./g,'').replace(',','.');
              else s=s.replace(/,/g,'');
            }else if(s.indexOf(',')>=0){
              var a=s.split(',');
              s=(a.length===2&&a[1].length<=2)?a[0].replace(/\./g,'')+'.'+a[1]:s.replace(/,/g,'');
            }else if(s.indexOf('.')>=0){
              var b=s.split('.');
              if(b.length>2||(b.length===2&&b[1].length===3&&b[0].length<=3))s=s.replace(/\./g,'');
            }
            var n=Number(s); return isFinite(n)?n:0;
          }
          function money(v){return Math.round(num(v)).toLocaleString('vi-VN')+' ₫';}
          function rowDefault(){return {hang_muc:'',mo_ta:'',dvt:'m²',dai:'',rong:'',cao:'',so_luong:'1',don_gia:'0'};}
          function calc(r){
            var d=num(r.dai),w=num(r.rong),h=num(r.cao),q=num(r.so_luong);
            if(r.dvt==='m²'||r.dvt==='m³')return d*w*h/1000000000*q;
            if(r.dvt==='m')return q;
            return q;
          }
          function field(value,placeholder,onchange){
            var x=document.createElement('input');
            x.value=value==null?'':value;x.placeholder=placeholder||'';
            x.addEventListener('input',onchange);return x;
          }
          function render(){
            var body=$('rows');body.innerHTML='';
            rows.forEach(function(r,i){
              r=Object.assign(rowDefault(),r);rows[i]=r;
              var tr=document.createElement('tr');
              var td=document.createElement('td');td.textContent=i+1;tr.appendChild(td);

              function addInput(key,ph,cls){
                var cell=document.createElement('td');
                var input=field(r[key],ph,function(){r[key]=input.value;totals();});
                if(cls)input.className=cls;cell.appendChild(input);tr.appendChild(cell);
              }
              addInput('hang_muc','');
              addInput('mo_ta','');

              td=document.createElement('td');
              var select=document.createElement('select');
              dvt.forEach(function(unit){
                var option=document.createElement('option');
                option.value=unit;option.textContent=unit;option.selected=unit===r.dvt;
                select.appendChild(option);
              });
              select.addEventListener('change',function(){r.dvt=select.value;render();});
              td.appendChild(select);tr.appendChild(td);

              addInput('dai','mm','mini');
              addInput('rong','mm','mini');
              addInput('cao','mm','mini');
              addInput('so_luong','SL','mini');

              td=document.createElement('td');td.className='calc';td.textContent=calc(r).toFixed(3);tr.appendChild(td);
              addInput('don_gia','0');

              td=document.createElement('td');td.className='calc';td.textContent=money(calc(r)*num(r.don_gia));tr.appendChild(td);

              td=document.createElement('td');
              var del=document.createElement('button');del.className='red';del.textContent='X';
              del.onclick=function(){rows.splice(i,1);render();};
              td.appendChild(del);tr.appendChild(td);
              body.appendChild(tr);
            });
            totals();
          }
          function totals(){
            var sub=0;
            rows.forEach(function(r){sub+=calc(r)*num(r.don_gia);});
            var discount=sub*num($('discount').value)/100;
            var after=sub-discount;
            var vat=after*num($('vat').value)/100;
            $('sub').textContent=money(sub);
            $('dis').textContent=money(discount);
            $('vatmoney').textContent=money(vat);
            $('total').textContent=money(after+vat);
            updateQr();
          }
          function collect(){
            return {
              ma_bao_gia:$('ma').value,ngay:$('ngay').value,
              khach_hang:$('khach').value,dien_thoai:$('phone').value,
              dia_chi:$('address').value,nguoi_lap:$('maker').value,
              chiet_khau:$('discount').value,vat:$('vat').value,
              bankName:$('bank').value,accountNo:$('account').value,
              accountName:$('owner').value,branch:$('branch').value,
              transferNote:$('note').value,rows:rows
            };
          }
          function bankId(name){
            var s=String(name||'').trim().toUpperCase().replace(/\s+/g,' ');
            var map={'VCB':'VCB','VIETCOMBANK':'VCB','BIDV':'BIDV','CTG':'CTG','VIETINBANK':'CTG',
              'AGRIBANK':'AGRIBANK','MB':'MB','MBBANK':'MB','MB BANK':'MB','TCB':'TCB','TECHCOMBANK':'TCB',
              'ACB':'ACB','VPB':'VPB','VPBANK':'VPB','TPB':'TPB','TPBANK':'TPB','STB':'STB','SACOMBANK':'STB',
              'HDB':'HDB','HDBANK':'HDB','VIB':'VIB','SHB':'SHB','EIB':'EIB','EXIMBANK':'EIB','MSB':'MSB',
              'OCB':'OCB','LPB':'LPB','LPBANK':'LPB','KLB':'KLB','KIENLONGBANK':'KLB','LIO':'LIOBANK',
              'LIO BANK':'LIOBANK','LIOBANK':'LIOBANK'};
            return map[s]||s;
          }
          function updateQr(){
            var bank=bankId($('bank').value),account=$('account').value.replace(/\s/g,'');
            if(!bank||!account){$('qr').innerHTML='<span>Nhập ngân hàng + số tài khoản để tạo QR</span>';return;}
            var sub=0;rows.forEach(function(r){sub+=calc(r)*num(r.don_gia);});
            var dis=sub*num($('discount').value)/100,after=sub-dis,vat=after*num($('vat').value)/100,total=after+vat;
            var note=$('note').value||$('ma').value||'THANH TOAN';
            var owner=$('owner').value||'';
            var url='https://img.vietqr.io/image/'+encodeURIComponent(bank)+'-'+encodeURIComponent(account)+'-compact2.jpg?amount='+Math.round(total)+'&addInfo='+encodeURIComponent(note.slice(0,50))+'&accountName='+encodeURIComponent(owner);
            $('qr').innerHTML='';
            var img=document.createElement('img');img.src=url;img.alt='QR VietQR';img.onclick=function(){sketchup.bg_qr(url);};
            img.onerror=function(){$('qr').innerHTML='<span>Không tải được QR. Kiểm tra ngân hàng / mạng.</span>';};
            $('qr').appendChild(img);
          }
          function addRow(){rows.push(rowDefault());render();}
          function addDvt(){
            var value=$('newDvt').value.trim();if(!value)return;
            if(dvt.indexOf(value)<0)dvt.push(value);$('newDvt').value='';render();
          }

          window.TT_BG_LOAD=function(data){
            $('ma').value=data.ma_bao_gia||'';$('ngay').value=data.ngay||'';
            $('khach').value=data.khach_hang||'';$('phone').value=data.dien_thoai||'';
            $('address').value=data.dia_chi||'';$('maker').value=data.nguoi_lap||'';
            $('discount').value=data.chiet_khau||'0';$('vat').value=data.vat||'0';
            $('bank').value=data.bankName||'';$('account').value=data.accountNo||'';
            $('owner').value=data.accountName||'';$('branch').value=data.branch||'';
            $('note').value=data.transferNote||'';rows=Array.isArray(data.rows)?data.rows:[];
            render();status('Đã mở báo giá.');
          };

          $('add').onclick=addRow;
          $('save').onclick=function(){sketchup.bg_save(JSON.stringify(collect()));};
          $('open').onclick=function(){sketchup.bg_open();};
          $('pdf').onclick=function(){sketchup.bg_pdf(JSON.stringify(collect()));};
          $('zalo').onclick=function(){sketchup.bg_zalo(JSON.stringify(collect()));};
          $('saveBank').onclick=function(){sketchup.bg_bank(JSON.stringify({bankName:$('bank').value,accountNo:$('account').value,accountName:$('owner').value,branch:$('branch').value,transferNote:$('note').value}));};
          $('addDvt').onclick=addDvt;
          $('saveDvt').onclick=function(){sketchup.bg_dvt(JSON.stringify(dvt));};

          ['discount','vat','bank','account','owner','note'].forEach(function(id){
            $(id).addEventListener('input',totals);
          });

          window.onerror=function(message,source,line){status('Lỗi JavaScript dòng '+line+': '+message,true);};

          $('ngay').value=new Date().toISOString().slice(0,10);
          $('ma').value='BG-'+new Date().toISOString().slice(0,19).replace(/[-:T]/g,'');
          addRow();
          status('Sẵn sàng.');
        })();
        </script></body></html>
      HTML
      .sub("value=\"#{safe(bank_data['bankName'])}\"", "value=\"#{safe(bank_data['bankName'])}\"")
      .sub('<input id="bank">', "<input id=\"bank\" value=\"#{safe(bank_data['bankName'])}\">")
      .sub('<input id="account">', "<input id=\"account\" value=\"#{safe(bank_data['accountNo'])}\">")
      .sub('<input id="owner">', "<input id=\"owner\" value=\"#{safe(bank_data['accountName'])}\">")
      .sub('<input id="branch">', "<input id=\"branch\" value=\"#{safe(bank_data['branch'])}\">")
      .sub('<input id="note">', "<input id=\"note\" value=\"#{safe(bank_data['transferNote'])}\">")
    end
  end
end
