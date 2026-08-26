# TT - TẠO VÁN - VISION HOT UPDATE
module TranTuan
  module TaoVan
    module VisionUpdate
      OFFICIAL_MANIFEST='https://raw.githubusercontent.com/tuanboidoi29-ai/TT-t-o-v-n-3d/main/update.json'.freeze
      class << self
        def run
          current=current_version
          data=fetch_manifest(OFFICIAL_MANIFEST)
          latest=data['version'].to_s.strip
          if latest.empty?
            UI.messagebox('update.json không có version hợp lệ.')
            return
          end
          if version_newer?(latest,current)
            notes=data['notes'].to_s
            return unless UI.messagebox("Có Vision mới!\n\nHiện tại: #{current}\nMới nhất: #{latest}\n\n#{notes}\n\nBạn có muốn cập nhật không?",MB_YESNO)==IDYES
            install_update(data)
          else
            UI.messagebox("Bạn đang dùng Vision mới nhất: #{current}.\n\nMáy chủ: #{latest}")
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
        def utf8_text(v)
          s=v.to_s.dup
          s.force_encoding(Encoding::UTF_8)
          raise 'Chuỗi cập nhật không phải UTF-8 hợp lệ.' unless s.valid_encoding?
          s
        end
        def fetch_manifest(url)
          require 'json'; require 'net/http'; require 'uri'
          uri=URI.parse(utf8_text(url))
          req=Net::HTTP::Get.new(utf8_text(uri.request_uri))
          req['Cache-Control']='no-cache, no-store, max-age=0'; req['Pragma']='no-cache'; req['User-Agent']='TT-TaoVan-VisionUpdater/1.2.2'
          h=Net::HTTP.new(utf8_text(uri.host),uri.port); h.use_ssl=(uri.scheme=='https'); h.open_timeout=8; h.read_timeout=12
          r=h.request(req); raise "HTTP #{r.code}" unless r.code.to_i==200
          body=r.body.to_s.dup
          if body.bytesize >= 3 && body.getbyte(0)==0xEF && body.getbyte(1)==0xBB && body.getbyte(2)==0xBF
            body=body.byteslice(3..-1)
          end
          body.force_encoding(Encoding::UTF_8)
          raise 'Manifest không phải UTF-8 hợp lệ.' unless body.valid_encoding?
          data=JSON.parse(body); raise 'Manifest không phải JSON object.' unless data.is_a?(Hash); data
        end
        def version_newer?(remote,current)
          a=remote.to_s.split('.').map{|x|x.to_i}; b=current.to_s.split('.').map{|x|x.to_i}; n=[a.length,b.length].max
          a.fill(0,a.length...n); b.fill(0,b.length...n); (a<=>b)==1
        end
        def install_update(data)
          require 'digest'; require 'net/http'; require 'uri'
          url=utf8_text(data['rbz_url']); expected=utf8_text(data['sha256']).downcase
          raise 'Thiếu rbz_url.' if url.empty?; raise 'Thiếu sha256.' if expected.empty?
          tmp=File.join(Dir.tmpdir,'tt_tao_van_update.rbz')
          download_binary(url,tmp)
          actual=Digest::SHA256.file(tmp).hexdigest.downcase
          raise 'SHA-256 không khớp. Hủy cập nhật.' unless actual==expected
          hot_install(tmp,utf8_text(data['version']))
        ensure
          File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
        end
        def download_binary(url,tmp)
          uri=URI.parse(utf8_text(url))
          req=Net::HTTP::Get.new(utf8_text(uri.request_uri))
          req['Cache-Control']='no-cache, no-store, max-age=0'; req['Pragma']='no-cache'; req['User-Agent']='TT-TaoVan-VisionUpdater/1.2.2'
          http=Net::HTTP.new(utf8_text(uri.host),uri.port); http.use_ssl=(uri.scheme=='https'); http.open_timeout=10; http.read_timeout=60
          response=http.request(req)
          code=response.code.to_i
          raise "HTTP #{code} khi tải RBZ." unless code==200
          File.binwrite(tmp,response.body.to_s.b)
          raise 'RBZ tải về rỗng.' unless File.file?(tmp) && File.size(tmp)>0
          true
        end
        def hot_install(archive,remote_version)
          require 'fileutils'
          root=TranTuan::TaoVan::ROOT
          backup=File.join(Dir.tmpdir,"TT_TaoVan_backup_#{Time.now.to_i}_#{rand(1_000_000)}")
          FileUtils.cp_r(root,backup)
          begin
            raise 'SketchUp không hỗ trợ install_from_archive.' unless Sketchup.respond_to?(:install_from_archive)
            Sketchup.install_from_archive(archive,false)
            vp=File.join(root,'version.txt')
            raise 'RBZ mới không có version.txt.' unless File.file?(vp)
            installed=File.read(vp,encoding:'UTF-8').strip
            raise "Version sau cài đặt không khớp: #{installed} != #{remote_version}" unless installed==remote_version
            reload_plugin_files(root)
            UI.messagebox("Đã cập nhật Vision #{remote_version}.\n\nCode mới đã được HOT RELOAD ngay trong SketchUp.\nKhông cần khởi động lại SketchUp.")
          rescue => error
            begin
              FileUtils.rm_rf(root); FileUtils.cp_r(backup,root)
              reload_plugin_files(root)
            rescue => rb
              raise "Hot Update lỗi: #{error.message}\nRollback lỗi: #{rb.message}"
            end
            raise "Hot Update lỗi; đã rollback.\n#{error.message}"
          ensure
            FileUtils.rm_rf(backup) if File.exist?(backup)
          end
        end
        def reload_plugin_files(root)
          begin
            Sketchup.active_model.select_tool(nil)
          rescue
          end
          files=%w[core.rb box.rb drawer.rb main.rb]
          files.each do |name|
            path=File.join(root,name)
            load(path) if File.file?(path)
          end
          up=File.join(root,'update.rb')
          load(up) if File.file?(up)
          true
        end
      end
    end
  end
end
