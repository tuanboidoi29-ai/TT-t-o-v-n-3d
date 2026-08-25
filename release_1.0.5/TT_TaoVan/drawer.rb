module TranTuan
  module TaoVan
    module Drawer
      module_function
      def start
        prompts=['Rộng phủ bì (mm)','Sâu phủ bì (mm)','Cao phủ bì (mm)','Độ dày ván (mm)','Khe hở trái/phải (mm)','Khe hở trước/sau (mm)','Độ dày đáy (mm)','Đáy cách đáy hông (mm)']
        input=UI.inputbox(prompts,[600,450,150,18,2,2,9,0],'TT - Tạo ngăn kéo tùy chỉnh'); return unless input
        w,d,h,t,gl,gf,bt,bo=input.map(&:to_f)
        if [w,d,h,t,bt].any?{|v|!v.finite?||v<=0} || gl<0 || gf<0 || bo<0; UI.messagebox('Thông số không hợp lệ.'); return end
        iw=w-2*t-2*gl; id=d-2*t-2*gf
        if iw<=0 || id<=0 || h<=t; UI.messagebox('Kích thước không đủ so với độ dày ván/khe hở.'); return end
        model=Sketchup.active_model; model.start_operation('TT - Tạo ngăn kéo',true)
        begin
          outer=model.entities.add_group; outer.name='TT - Ngăn kéo'
          add=lambda do |name,x,y,z,sx,sy,sz|
            g=outer.entities.add_group; g.name=name; pts=[Geom::Point3d.new(x,y,z),Geom::Point3d.new(x+sx,y,z),Geom::Point3d.new(x+sx,y+sy,z),Geom::Point3d.new(x,y+sy,z)]; g.entities.add_face(pts).pushpull(sz); g
          end
          add.call('Đáy',t+gl,t+gf,bo,iw,id,bt); add.call('Hông trái',0,0,0,t,d,h); add.call('Hông phải',w-t,0,0,t,d,h); add.call('Mặt trước',t,0,0,iw+2*gl,t,h); add.call('Mặt sau',t,d-t,0,iw+2*gl,t,h)
          outer.set_attribute('TT_TaoVan','loai','ngan_keo'); outer.set_attribute('TT_TaoVan','rong_mm',w); outer.set_attribute('TT_TaoVan','sau_mm',d); outer.set_attribute('TT_TaoVan','cao_mm',h); outer.set_attribute('TT_TaoVan','day_mm',t); outer.set_attribute('TT_TaoVan','day_da_mm',bt)
          model.commit_operation; model.selection.clear; model.selection.add(outer); UI.messagebox("Đã tạo ngăn kéo #{w.to_i} × #{d.to_i} × #{h.to_i} mm.")
        rescue=>e; model.abort_operation; UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}") end
      end
    end
  end
end
