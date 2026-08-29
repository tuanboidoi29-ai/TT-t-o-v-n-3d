# TT Drawer Bottom/Hau modes v1.3.6
# Quy tac: Tat Hau = 4 thanh; Lot = day lot vao 4 thanh theo offset; Phu = day phu theo bien ngoai 4 thanh.
module TranTuan
  module TaoVan
    module Drawer
      class TwoPointTool
        private
        def create(p2)
          d=measure(@p1,p2)
          return UI.messagebox("Không đủ không gian. Vùng R #{Drawer.mm_text(d[:w])} × C #{Drawer.mm_text(d[:h])} × S #{Drawer.mm_text(d[:d])}") if d.values_at(:dw,:dh,:dd).any?{|v|v<=0}
          m=Sketchup.active_model
          m.start_operation('TT - Tạo ngăn kéo AUTO',true)
          begin
            xmin,xmax,zmin,zmax=normalized_region(@p1,p2)
            x=xmin+Drawer.mm(@cfg['rail_gap'].to_f)
            rw=Drawer.mm(d[:dw]); rd=Drawer.mm(d[:dd])
            y=Drawer.mm(@cfg['gap_front'].to_f); y-=rd if @outward
            z=zmin+Drawer.mm(@cfg['gap_bottom'].to_f)
            rh=Drawer.mm(d[:dh]); t=Drawer.mm(d[:wall_t].to_f)
            bt=Drawer.mm(@cfg['bottom_t'].to_f)
            iw=rw-2*t
            raise 'Chiều rộng không đủ cho 2 hông 17,5 mm.' if iw<=0

            g=m.entities.add_group
            g.name='TT - Ngăn kéo AUTO'
            add_part(g,'Hông trái',x,y,z,t,rd,rh)
            add_part(g,'Hông phải',x+rw-t,y,z,t,rd,rh)
            add_part(g,'Thành trước',x+t,y,z,iw,t,rh)
            add_part(g,'Thành sau',x+t,y+rd-t,z,iw,t,rh)

            # TẮT HẬU: chỉ 4 thành, không tạo đáy/hậu.
            # LỌT: đáy lọt vào cả 4 thành theo offset từ mép ngoài.
            # PHỦ: đáy phủ theo toàn bộ biên ngoài của cả 4 thành (offset 0).
            unless @back_mode == :none
              edge=(@cfg['back_edge_offset'].to_f).clamp(0.0, [rw.to_mm, rd.to_mm].min/2.0)
              if @back_mode == :lọt
                bx=x+Drawer.mm(edge); by=y+Drawer.mm(edge)
                bw=rw-Drawer.mm(edge*2.0); bd=rd-Drawer.mm(edge*2.0)
                raise 'Offset Hậu lọt quá lớn.' if bw<=0 || bd<=0
              else
                bx=x; by=y; bw=rw; bd=rd
              end

              # Offset cao độ tính từ MẶT DƯỚI của 4 thành.
              lift=Drawer.mm(@cfg['back_bottom_offset'].to_f)
              bottom_z=z+lift-bt
              add_part(g,'Tấm đáy',bx,by,bottom_z,bw,bd,bt)
            end

            g.transform!(@frame)
            g.set_attribute(DICT,'don_vi','mm')
            g.set_attribute(DICT,'do_day_4_thanh_mm',d[:wall_t])
            g.set_attribute(DICT,'do_day_day_mm',@cfg['bottom_t'])
            g.set_attribute(DICT,'khe_tach_day_mm',@back_mode==:lọt ? @cfg['back_edge_offset'].to_f : 0.0)
            g.set_attribute(DICT,'ten_thanh_sau','Thành sau')
            g.set_attribute(DICT,'che_do_hau',back_mode_name)
            g.set_attribute(DICT,'hau_offset_mep_mm',@cfg['back_edge_offset'])
            g.set_attribute(DICT,'hau_offset_day_mm',@cfg['back_bottom_offset'])
            g.set_attribute(DICT,'hau_la_tam_day',true)
            m.commit_operation
            reset
            Sketchup.active_model.select_tool(self)
            status('ĐÃ TẠO NGĂN KÉO → CLICK ĐIỂM 1 TIẾP THEO')
          rescue=>e
            m.abort_operation rescue nil
            UI.messagebox("Không thể tạo ngăn kéo:\n#{e.message}")
          end
        end
      end
    end
  end
end
