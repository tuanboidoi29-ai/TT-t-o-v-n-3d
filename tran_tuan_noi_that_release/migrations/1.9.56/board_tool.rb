# encoding: UTF-8
# TRẦN TUẤN NỘI THẤT 1.9.56 - PROTECTED MIGRATION
# File chuyển đổi này tự thay thế bằng loader bảo vệ sau khi chạy thành công.
require 'json'
require 'zlib'
require 'openssl'
require 'digest'
require 'securerandom'
require 'fileutils'
require 'base64'

module TTProtectedMigration1956
  extend self
  VERSION = '1.9.56'.freeze
  SUPPORT_ROOT = __dir__.freeze
  PLUGIN_ROOT = File.dirname(SUPPORT_ROOT).freeze
  SOURCE_PATHS = ["TT_TranTuan_UpdateLoader.rb", "TranTuanNoiThat/board_tool.rb", "TranTuanNoiThat/bootstrap.rb", "TranTuanNoiThat/box_tool.rb", "TranTuanNoiThat/drawer_tool.rb", "TranTuanNoiThat/grain_align_fix.rb", "TranTuanNoiThat/grain_material_fix.rb", "TranTuanNoiThat/grain_production_v350.rb", "TranTuanNoiThat/grain_production_v350_hotfix.rb", "TranTuanNoiThat/grain_reload_v351_fix.rb", "TranTuanNoiThat/grain_standard_2440_fix.rb", "TranTuanNoiThat/grain_tool.rb", "TranTuanNoiThat/grain_tool_part1.inc", "TranTuanNoiThat/grain_tool_part2.inc", "TranTuanNoiThat/grain_tool_part3.inc", "TranTuanNoiThat/layout_stats_tool.rb", "TranTuanNoiThat/layout_stats_v030_patch.rb", "TranTuanNoiThat/layout_stats_v040_compat.rb", "TranTuanNoiThat/layout_stats_v040_patch.rb", "TranTuanNoiThat/layout_stats_v050_stable_preview.rb", "TranTuanNoiThat/layout_stats_v060_compact_scope.rb", "TranTuanNoiThat/layout_stats_v070_export_split.rb", "TranTuanNoiThat/layout_stats_v080_five_pages.rb", "TranTuanNoiThat/layout_stats_v081_cut_offset_fix.rb", "TranTuanNoiThat/layout_stats_v090_technical_dim.rb", "TranTuanNoiThat/license_commercial_v130_qr.rb", "TranTuanNoiThat/license_commercial_v140_auto.rb", "TranTuanNoiThat/license_manager.rb", "TranTuanNoiThat/license_owner_admin_v120.rb", "TranTuanNoiThat/license_owner_admin_v121_fix.rb", "TranTuanNoiThat/license_owner_admin_v123_fix.rb", "TranTuanNoiThat/license_payment_v110.rb", "TranTuanNoiThat/license_ui_v122_fix.rb", "TranTuanNoiThat/round_smooth_fix.rb", "TranTuanNoiThat/round_tool.rb", "TranTuanNoiThat/settings.rb", "TranTuanNoiThat/stretch_auto_scan_fix.rb", "TranTuanNoiThat/stretch_auto_scope_fix.rb", "TranTuanNoiThat/stretch_detail_fix.rb", "TranTuanNoiThat/stretch_mode_tool.rb", "TranTuanNoiThat/updater.rb", "TranTuanNoiThat.rb"].freeze
  A = [136, 105, 198, 104, 33, 213, 123, 236, 57, 169, 71, 75, 149, 58, 137, 38, 62, 143, 188, 30, 74, 31, 185, 110, 132, 195, 94, 203, 46, 65, 92, 227].freeze
  B = [205, 123, 161, 62, 95, 134, 84, 198, 37, 80, 236, 118, 152, 157, 10, 172, 196, 2, 15, 86, 138, 38, 172, 125, 62, 136, 32, 178, 217, 86, 129, 152].freeze
  PATCH_PARTS = [".tt_migration_1956/patch_01.ttx", ".tt_migration_1956/patch_02.ttx", ".tt_migration_1956/patch_03.ttx", ".tt_migration_1956/patch_04.ttx", ".tt_migration_1956/patch_05.ttx"].freeze

  def secure_equal?(a,b)
    return false unless a && b && a.bytesize == b.bytesize
    r=0; a.bytes.zip(b.bytes) { |x,y| r |= (x ^ y) }; r == 0
  end

  def migration_key
    @migration_key ||= A.zip(B).map { |x,y| x ^ y }.pack('C*')
  end

  def patches
    return @patches if @patches
    encoded=PATCH_PARTS.map { |rel| File.binread(File.join(SUPPORT_ROOT,rel)) }.join
    raw=Base64.strict_decode64(encoded)
    raise 'Sai gói chuyển đổi.' unless raw.byteslice(0,8) == 'TTMIG156'.b
    iv=raw.byteslice(8,16); tag=raw.byteslice(24,32); ct=raw.byteslice(56,raw.bytesize-56)
    auth=Digest::SHA256.digest(migration_key + 'TT-MIG-1956')
    expected=OpenSSL::HMAC.digest('SHA256',auth,iv+ct)
    raise 'Gói chuyển đổi đã bị sửa.' unless secure_equal?(expected,tag)
    cipher=OpenSSL::Cipher.new('aes-256-cbc'); cipher.decrypt; cipher.key=migration_key; cipher.iv=iv
    comp=cipher.update(ct)+cipher.final
    data=JSON.parse(Zlib::Inflate.inflate(comp).force_encoding('UTF-8'))
    raise 'Sai phiên bản chuyển đổi.' unless data['version'].to_s == VERSION
    @patches=data['patches'] || {}
  end

  def read_existing(rel)
    p=File.join(PLUGIN_ROOT,rel)
    raise "Thiếu source cần chuyển đổi: #{rel}" unless File.file?(p)
    s=File.binread(p).force_encoding('UTF-8')
    raise "Source UTF-8 lổi: #{rel}" unless s.valid_encoding?
    s
  end

  def collect_sources
    patch=patches
    out={}
    SOURCE_PATHS.each do |rel|
      code=patch.key?(rel) ? patch[rel].to_s : read_existing(rel)
      out[rel]=code
    end
    out
  end

  def runtime_code(masked,mask)
    <<~RUBY
      # encoding: UTF-8
      # TRẦN TUẤN NỘI THẤT - PROTECTED RELEASE RUNTIME V2
      require 'json'
      require 'zlib'
      require 'openssl'
      require 'digest'
      module TranTuanNoiThat
        module Protected
          extend self
          FORMAT=2
          SUPPORT_ROOT=__dir__.freeze
          PLUGIN_ROOT=File.dirname(SUPPORT_ROOT).freeze
          PAYLOAD=File.join(SUPPORT_ROOT,'tt_runtime.dat').freeze
          MANIFEST=File.join(SUPPORT_ROOT,'tt_release.manifest').freeze
          A=#{masked.inspect}.freeze
          B=#{mask.inspect}.freeze
          def master_key; @master_key ||= A.zip(B).map { |x,y| x ^ y }.pack('C*').freeze; end
          def key(label); Digest::SHA256.digest(master_key + label); end
          def secure_equal?(a,b); return false unless a && b && a.bytesize==b.bytesize; r=0; a.bytes.zip(b.bytes){|x,y| r|=(x^y)}; r==0; end
          def fail_lock!(m); begin; UI.messagebox("TRẦN TUẤN NỘI THẤT - BẢN RELEASE ĐÃ KHÓA\n\n"+m.to_s); rescue StandardError; end; raise SecurityError,m.to_s; end
          def verify_manifest!
            return true if @manifest_verified
            raw=File.binread(MANIFEST); sig,json=raw.split("\n",2); fail_lock!('Thiếu dữ liệu kiểm tra toàn vẹn.') unless sig && json
            exp=OpenSSL::HMAC.hexdigest('SHA256',key('TT-MANIFEST-V2'),json); fail_lock!('Manifest đã bị thay đổi.') unless secure_equal?(exp,sig.strip)
            data=JSON.parse(json); (data['files']||{}).each do |rel,sha|
              path=File.expand_path(File.join(PLUGIN_ROOT,rel)); root=PLUGIN_ROOT.end_with?(File::SEPARATOR) ? PLUGIN_ROOT : PLUGIN_ROOT+File::SEPARATOR
              fail_lock!("Đường dẫn không hợp lệ: \#{rel}") unless path==PLUGIN_ROOT || path.start_with?(root)
              fail_lock!("Thiếu file: \#{rel}") unless File.file?(path)
              got=Digest::SHA256.file(path).hexdigest; fail_lock!("File đã bị sửa: \#{rel}") unless secure_equal?(got,sha.to_s)
            end
            @manifest_verified=true
          end
          def bundle
            return @bundle if @bundle
            verify_manifest!; raw=File.binread(PAYLOAD); fail_lock!('Payload không hợp lệ.') if raw.bytesize<56
            magic=raw.byteslice(0,8); iv=raw.byteslice(8,16); tag=raw.byteslice(24,32); ct=raw.byteslice(56,raw.bytesize-56)
            fail_lock!('Sai định dạng payload.') unless magic=='TTLOCK20'.b
            exp=OpenSSL::HMAC.digest('SHA256',key('TT-AUTH-V2'),magic+iv+ct); fail_lock!('Payload đã bị sửa hoặc hỏng.') unless secure_equal?(exp,tag)
            c=OpenSSL::Cipher.new('aes-256-cbc'); c.decrypt; c.key=key('TT-ENC-V2'); c.iv=iv
            data=JSON.parse(Zlib::Inflate.inflate(c.update(ct)+c.final).force_encoding('UTF-8')); fail_lock!('Sai phiên bản gói bảo vệ.') unless data['format'].to_i==FORMAT
            @bundle=data['sources']||{}
          rescue SecurityError; raise
          rescue StandardError => e; fail_lock!("Không thể mở mã chương trình: \#{e.message}")
          end
          def source(name); code=bundle[name.to_s]; fail_lock!("Thiếu module bảo vệ: \#{name}") unless code.is_a?(String); code.dup.force_encoding('UTF-8'); end
          def source_filename(name); File.expand_path(File.join(PLUGIN_ROOT,name.to_s)); end
          def load_source(name,bind=TOPLEVEL_BINDING); eval(source(name),bind,source_filename(name),1); true; end
        end
      end
    RUBY
  end

  def wrapper_for(rel)
    if rel.start_with?('TranTuanNoiThat/')
      "# encoding: UTF-8\nrequire File.join(__dir__, 'protected_runtime') unless defined?(TranTuanNoiThat::Protected)\nTranTuanNoiThat::Protected.load_source(#{rel.inspect})\n"
    else
      "# encoding: UTF-8\nrequire File.join(__dir__, 'TranTuanNoiThat', 'protected_runtime') unless defined?(TranTuanNoiThat::Protected)\nTranTuanNoiThat::Protected.load_source(#{rel.inspect})\n"
    end
  end

  def run
    sources=collect_sources
    master=SecureRandom.random_bytes(32); mask=SecureRandom.random_bytes(32); masked=master.bytes.zip(mask.bytes).map{|a,b|a^b}
    enc_key=Digest::SHA256.digest(master+'TT-ENC-V2'); auth_key=Digest::SHA256.digest(master+'TT-AUTH-V2'); man_key=Digest::SHA256.digest(master+'TT-MANIFEST-V2')
    plain=JSON.generate({'format'=>2,'product'=>'TRẦN TUẤN NỘI THẤT','version'=>VERSION,'sources'=>sources})
    comp=Zlib::Deflate.deflate(plain,Zlib::BEST_COMPRESSION)
    c=OpenSSL::Cipher.new('aes-256-cbc'); c.encrypt; c.key=enc_key; iv=SecureRandom.random_bytes(16); c.iv=iv; ct=c.update(comp)+c.final
    magic='TTLOCK20'.b; tag=OpenSSL::HMAC.digest('SHA256',auth_key,magic+iv+ct); payload=magic+iv+tag+ct
    runtime=runtime_code(masked,mask.bytes)

    # Write payload/runtime first, then wrappers. Source fragments .inc are removed.
    File.binwrite(File.join(SUPPORT_ROOT,'tt_runtime.dat'),payload)
    File.binwrite(File.join(SUPPORT_ROOT,'protected_runtime.rb'),runtime.encode('UTF-8'))
    SOURCE_PATHS.each do |rel|
      path=File.join(PLUGIN_ROOT,rel)
      if rel.end_with?('.inc')
        FileUtils.rm_f(path)
      else
        FileUtils.mkdir_p(File.dirname(path)); File.binwrite(path,wrapper_for(rel).encode('UTF-8'))
      end
    end

    files={}
    SOURCE_PATHS.reject{|r|r.end_with?('.inc')}.each do |rel|
      p=File.join(PLUGIN_ROOT,rel); files[rel]=Digest::SHA256.file(p).hexdigest
    end
    %w[TranTuanNoiThat/protected_runtime.rb TranTuanNoiThat/tt_runtime.dat].each do |rel|
      files[rel]=Digest::SHA256.file(File.join(PLUGIN_ROOT,rel)).hexdigest
    end
    mj=JSON.generate({'format'=>2,'product'=>'TRẦN TUẤN NỘI THẤT','version'=>VERSION,'mode'=>'PROTECTED_RELEASE','files'=>files})
    sig=OpenSSL::HMAC.hexdigest('SHA256',man_key,mj)
    File.binwrite(File.join(SUPPORT_ROOT,'tt_release.manifest'),sig+"\n"+mj)
    # Remove updater backups because they can contain plaintext source.
    FileUtils.rm_rf(File.join(SUPPORT_ROOT,'backup'))
    FileUtils.rm_rf(File.join(SUPPORT_ROOT,'.tt_migration_1956'))

    if ENV['TT_MIGRATION_TEST']=='1'
      puts "TT migration test OK: #{sources.size} sources, #{files.size} protected files"
      return true
    end
    load File.join(SUPPORT_ROOT,'board_tool.rb')
    true
  end
end

begin
  TTProtectedMigration1956.run
rescue Exception => e
  begin
    UI.messagebox("TRẦN TUẤN NỘI THẤT - Không thể khóa/cập nhật 1.9.56:\n#{e.class}: #{e.message}")
  rescue StandardError
    warn "TT 1.9.56 migration failed: #{e.class}: #{e.message}"
  end
  raise
end
