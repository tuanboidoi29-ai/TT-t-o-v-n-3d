# encoding: UTF-8
require 'sketchup.rb'
require 'net/http'
require 'uri'
require 'fileutils'
require 'tmpdir'

module TTCuuCapNhat194
  VERSION = '1.9.4'.freeze
  NAME = 'TRẦN TUẤN NỘI THẤT'.freeze
  FILES = {
    'TranTuanNoiThat.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/f2c3a9e4eb0fc8713ce3240ac097e46ec9d52e88/tran_tuan_noi_that_release/files/TranTuanNoiThat.rb',
    'tran_tuan_noi_that/bootstrap.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/abc4293036b2a639af281defd66248181b0f5b48/tran_tuan_noi_that_release/files/tran_tuan_noi_that/bootstrap.rb',
    'tran_tuan_noi_that/updater.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/a754d83bbd96dd7cedbb47b73a31869cbefdd486/tran_tuan_noi_that_release/files/tran_tuan_noi_that/updater.rb',
    'tran_tuan_noi_that/round_tool.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/3df27d64b0bcdede6b595d021105b3252325ee8e/tran_tuan_noi_that_release/files/tran_tuan_noi_that/round_tool.rb',
    'tran_tuan_noi_that/round_smooth_fix.rb' => 'https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/e72485b822029d188309dbfd7b09c542c6f32556/tran_tuan_noi_that_release/files/tran_tuan_noi_that/round_smooth_fix.rb'
  }.freeze

  module_function

  def get(url, limit = 5)
    raise 'Quá nhiều lần chuyển hướng.' if limit <= 0
    uri = URI.parse(url)
    raise 'Chỉ cho phép HTTPS.' unless uri.is_a?(URI::HTTPS)
    req = Net::HTTP::Get.new(uri.request_uri)
    req['User-Agent'] = 'TT-Cuu-Cap-Nhat/1.9.4'
    req['Cache-Control'] = 'no-cache, no-store, max-age=0'
    req['Pragma'] = 'no-cache'
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
    return get(URI.join(uri, res['location']).to_s, limit - 1) if res.is_a?(Net::HTTPRedirection)
    raise "Máy chủ trả về HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    res.body
  end

  def install
    plugins = File.expand_path(Sketchup.find_support_file('Plugins'))
    staging = Dir.mktmpdir('tt_rescue_194_')
    backup = File.join(plugins, 'tran_tuan_noi_that', 'backup', "rescue_#{Time.now.strftime('%Y%m%d_%H%M%S')}")

    FILES.each do |relative, url|
      data = get("#{url}?tt_rescue=#{Time.now.to_i}_#{rand(1_000_000)}")
      tmp = File.join(staging, relative)
      FileUtils.mkdir_p(File.dirname(tmp))
      File.binwrite(tmp, data)
    end

    FILES.each_key do |relative|
      src = File.join(staging, relative)
      dst = File.join(plugins, relative)
      if File.file?(dst)
        bak = File.join(backup, relative)
        FileUtils.mkdir_p(File.dirname(bak))
        FileUtils.cp(dst, bak)
      end
      FileUtils.mkdir_p(File.dirname(dst))
      FileUtils.cp(src, dst)
    end

    Sketchup.write_default(NAME, 'installed_version', VERSION)
    load File.join(plugins, 'tran_tuan_noi_that', 'bootstrap.rb')
    load File.join(plugins, 'tran_tuan_noi_that', 'round_smooth_fix.rb')
    UI.messagebox("Cứu cập nhật thành công: #{VERSION}.\nBo Cong Khối: V2.2.1.\nKhông cần khởi động lại SketchUp.")
    true
  rescue StandardError => error
    UI.messagebox("Cứu cập nhật thất bại:\n#{error.class}: #{error.message}")
    puts "[TT RESCUE 1.9.4] #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}" rescue nil
    false
  ensure
    FileUtils.remove_entry(staging) if staging && File.directory?(staging)
  end

  install
end
