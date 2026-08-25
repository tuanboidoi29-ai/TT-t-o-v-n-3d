# TT - TẠO VÁN - VISION HOT UPDATE
module TranTuan
  module TaoVan
    module VisionUpdate
      OFFICIAL_MANIFEST='https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/update.json'.freeze
      class << self
        def run
          current=current_version; data=fetch_manifest(OFFICIAL_MANIFEST)
          latest=data['version'].to_s.strip
          if latest.empty?; UI.messagebox('update.json không có version hợp lệ.'); return end
          if version_newer?(latest,current)
            notes=data['notes'].to_s
            return unless UI.messagebox("Có Vision mới!\n\nHiện tại: #{current}\nMới nhất: #{latest}\n\n#{notes}\n\nBạn có muốn cập nhật không?",MB_YESNO)==IDYES
            install_update(data)
          else
            UI.messagebox("Bạn đang dùng Vision mới nhất: #{current}.")
          end
        rescue => e
          UI.messagebox("Cập nhật Vision thất bại:\n#{e.message}")
        end
        private
        def current_version
          p=File.join(TranTuan::TaoVan::ROOT,'version.txt')
          return File.read(p,encoding:'UTF-8').strip if File.file?(p)
          '0.0.0'
        end
        def fetch_manifest(url)
          require 'json'; require 'net/http'; uri=URI.parse(url); req=Net::HTTP::Get.new(uri.request_uri); req['Cache-Control']='no-cache'; req['Pragma']='no-cache'; h=Net::HTTP.new(uri.host,uri.port); h.use_ssl=(uri.scheme=='https'); h.open_timeout=8; h.read_timeout=12; r=h.request(req); raise "HTTP #{r.code}" unless r.code.to_i==200; JSON.parse(r.body)
        end
        def version_newer?(r,l)
          a=r.to_s.split('.').map(&:to_i); b=l.to_s.split('.').map(&:to_i); n=[a.length,b.length].max; a.fill(0,a.length...n); b.fill(0,b.length...n); (a<=>b)==1
        end
        def install_update(data)
          require 'open-uri'; require 'digest'; url=data['rbz_url'].to_s; expected=data['sha256'].to_s.downcase; raise 'Thiếu rbz_url.' if url.empty?; raise 'Thiếu sha256.' if expected.empty?
          tmp=File.join(Dir.tmpdir,'tt_tao_van_update.rbz')
          URI.open(url,'rb',open_timeout:10,read_timeout:60){|io|File.binwrite(tmp,io.read)}
          actual=Digest::SHA256.file(tmp).hexdigest.downcase; raise 'SHA-256 không khớp. Hủy cập nhật.' unless actual==expected
          hot_install(tmp,data['version'].to_s)
        ensure
          File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
        end
        def hot_install(archive,remote_version)
          require 'fileutils'; root=TranTuan::TaoVan::ROOT; backup=File.join(Dir.tmpdir,"TT_TaoVan_backup_#{Time.now.to_i}_#{rand(1_000_000)}"); FileUtils.cp_r(root,backup)
          begin
            raise 'SketchUp không hỗ trợ install_from_archive.' unless Sketchup.respond_to?(:install_from_archive)
            Sketchup.install_from_archive(archive,false)
            vp=File.join(root,'version.txt'); raise 'RBZ mới không có version.txt.' unless File.file?(vp); installed=File.read(vp,encoding:'UTF-8').strip; raise "Version sau cài đặt không khớp: #{installed} != #{remote_version}" unless installed==remote_version
            load(File.join(root,'update.rb')); load(File.join(root,'core.rb')); load(File.join(root,'main.rb'))
            UI.messagebox("Đã cập nhật Vision #{remote_version}.\n\nMenu + Toolbar + Icon + chức năng mới đã được nạp.\nKhông cần khởi động lại SketchUp.")
          rescue => error
            begin
              FileUtils.rm_rf(root); FileUtils.cp_r(backup,root); load(File.join(root,'update.rb')); load(File.join(root,'core.rb')); load(File.join(root,'main.rb'))
            rescue => rb
              raise "Hot Update lỗi: #{error.message}\nRollback lỗi: #{rb.message}"
            end
            raise "Hot Update lỗi; đã rollback.\n#{error.message}"
          ensure
            FileUtils.rm_rf(backup) if File.exist?(backup)
          end
        end
      end
    end
  end
end
