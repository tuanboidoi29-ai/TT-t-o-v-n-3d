# encoding: UTF-8
require 'sketchup.rb'
require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'fileutils'

module TTCuuCapNhat197
  extend self

  VERSION = '1.9.7'.freeze
  ROOT = Sketchup.find_support_file('Plugins')
  FILES = {
    'TranTuanNoiThat.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/db11ef483cd89bb763c5d696006753a1734b9162/tran_tuan_noi_that_release/files/TranTuanNoiThat.rb',
    'tran_tuan_noi_that/bootstrap.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/6b4f615515b0cf26139ef6ec9ed221809a3deb43/tran_tuan_noi_that_release/files/tran_tuan_noi_that/bootstrap.rb',
    'tran_tuan_noi_that/updater.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/ea637081c81837e20bca2482a2e46133de670cce/tran_tuan_noi_that_release/files/tran_tuan_noi_that/updater.rb',
    'tran_tuan_noi_that/round_smooth_fix.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/65088c9def05413ed6c48d0917f007c311c9bd28/tran_tuan_noi_that_release/files/tran_tuan_noi_that/round_smooth_fix.rb'
  }.freeze

  def run
    backup_root = File.join(ROOT, 'tran_tuan_noi_that', 'backup', "rescue_197_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    FILES.each do |relative, url|
      target = File.join(ROOT, relative)
      if File.file?(target)
        backup = File.join(backup_root, relative)
        FileUtils.mkdir_p(File.dirname(backup))
        FileUtils.cp(target, backup)
      end
      bytes = fetch_with_fallback(url)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, bytes)
    end

    Sketchup.write_default('TRẦN TUẤN NỘI THẤT', 'installed_version', VERSION)

    begin
      load File.join(ROOT, 'tran_tuan_noi_that', 'bootstrap.rb')
      fix = File.join(ROOT, 'tran_tuan_noi_that', 'round_smooth_fix.rb')
      load fix if File.file?(fix)
    rescue StandardError => e
      puts "[TT RESCUE 1.9.7] #{e.class}: #{e.message}"
    end

    UI.messagebox("Cứu cập nhật thành công: #{VERSION}\nĐã sửa lỗi execution expired.\nBo Cong Khối: V2.2.4\nKhông cần khởi động lại SketchUp.")
    true
  rescue StandardError => e
    UI.messagebox("Cứu cập nhật 1.9.7 thất bại:\n#{e.class}: #{e.message}")
    false
  end

  def fetch_with_fallback(raw_url)
    errors = []
    [raw_url, raw_to_api(raw_url)].compact.each do |url|
      begin
        body = http_get(url)
        return decode_api(body) if URI.parse(url).host == 'api.github.com'
        return body
      rescue StandardError => e
        errors << "#{URI.parse(url).host}: #{e.message}"
      end
    end
    raise "Không tải được file từ GitHub.\n#{errors.join("\n")}"
  end

  def raw_to_api(url)
    uri = URI.parse(url)
    return nil unless uri.host == 'raw.githubusercontent.com'
    parts = uri.path.sub(%r{\A/}, '').split('/')
    return nil if parts.length < 4
    owner, repo, ref = parts.shift, parts.shift, parts.shift
    path = parts.join('/')
    "https://api.github.com/repos/#{owner}/#{repo}/contents/#{path}?ref=#{URI.encode_www_form_component(ref)}"
  end

  def http_get(url, limit = 4)
    raise 'Quá nhiều lần chuyển hướng.' if limit <= 0
    uri = URI.parse(url)
    req = Net::HTTP::Get.new(uri.request_uri)
    req['User-Agent'] = 'TranTuanNoiThat-Rescue/1.9.7'
    req['Cache-Control'] = 'no-cache, no-store, max-age=0'
    if uri.host == 'api.github.com'
      req['Accept'] = 'application/vnd.github+json'
      req['X-GitHub-Api-Version'] = '2022-11-28'
    end
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 6) { |http| http.request(req) }
    if res.is_a?(Net::HTTPRedirection)
      return http_get(URI.join(uri, res['location']).to_s, limit - 1)
    end
    raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    res.body
  end

  def decode_api(body)
    data = JSON.parse(body)
    if data.is_a?(Hash) && data['content'] && data['encoding'].to_s.downcase == 'base64'
      Base64.decode64(data['content'].to_s)
    else
      body
    end
  end
end

TTCuuCapNhat197.run
