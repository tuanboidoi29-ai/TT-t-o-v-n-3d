# encoding: UTF-8
require 'net/http'; require 'uri'; require 'json'; require 'base64'; require 'tmpdir'; require 'securerandom'; require 'thread'

module TranTuanNoiThat
  module ChatGPTConnect
    extend self
    API='https://api.openai.com/v1/responses'.freeze
    MODEL='gpt-5'.freeze

    def show
      build unless @dlg
      @dlg.show
      sync
    rescue => e
      UI.messagebox("TT – ChatGPT Connect:\n#{e.message}")
    end

    def close
      @dlg.close if @dlg
      @dlg=nil
    rescue
      nil
    end

    def build
      @dlg=UI::HtmlDialog.new(dialog_title:'TT – CHATGPT CONNECT',preferences_key:'TT.ChatGPT',scrollable:true,resizable:true,width:720,height:680,min_width:540,min_height:500,style:UI::HtmlDialog::STYLE_DIALOG)
      @dlg.set_html(html)
      @dlg.set_on_closed{@dlg=nil}
      @dlg.add_action_callback('ready'){sync}
      @dlg.add_action_callback('clear'){|_| @history=[]; js('clearChat()')}
      @dlg.add_action_callback('quick'){|_,a| quick(a.to_s)}
      @dlg.add_action_callback('test'){|_,j| request(j,true)}
      @dlg.add_action_callback('send'){|_,j| request(j,false)}
    end

    def html
      <<~HTML
      <!doctype html><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:13px Arial;height:100vh;display:flex;flex-direction:column}.h{padding:14px;background:#f97316;color:#fff}.h b{font-size:18px}.cfg,.opt,.q,.c{padding:9px 11px;background:#111827;border-bottom:1px solid #334155;display:flex;gap:7px;align-items:center;flex-wrap:wrap}input,textarea{background:#0b1220;color:#fff;border:1px solid #475569;border-radius:7px;padding:8px}.key{flex:1;min-width:240px}.model{width:150px}button{border:0;border-radius:7px;padding:8px 10px;font-weight:bold;cursor:pointer;background:#334155;color:#fff}.go{background:#ea580c}.ok{background:#166534}#m{flex:1;overflow:auto;padding:12px}.msg{padding:9px 11px;border-radius:10px;margin:7px 0;white-space:pre-wrap;line-height:1.4}.u{background:#c2410c;margin-left:12%}.a{background:#1e293b;margin-right:12%}.s{background:#0b1220;color:#94a3b8}.c{margin-top:auto;border-top:1px solid #334155}.c textarea{flex:1;min-height:70px;resize:vertical}.st{float:right;font-size:11px}
      </style><div class="h"><b>TT – CHATGPT CONNECT</b><span id="st" class="st">Sẵn sàng</span><div>TRẦN TUẤN NỘI THẤT · SketchUp ↔ OpenAI</div></div>
      <div class="cfg"><input id="k" class="key" type="password" placeholder="OPENAI_API_KEY – không lưu vào file"><input id="mo" class="model" value="gpt-5"><button class="ok" onclick="test()">KIỂM TRA</button></div>
      <div class="opt"><label><input id="ctx" type="checkbox" checked> Model/selection</label><label><input id="view" type="checkbox"> Ảnh Viewport</label><button onclick="sketchup.clear()">XÓA CHAT</button></div>
      <div id="m"><div class="msg s">Nhập API key hoặc đặt biến môi trường OPENAI_API_KEY. API key chỉ giữ trong phiên SketchUp.</div></div>
      <div class="q"><button onclick="q('board')">Vẽ Ván</button><button onclick="q('drawer')">Ngăn Kéo</button><button onclick="q('box')">BOX</button><button onclick="q('grain')">Xoay Vân</button><button onclick="q('stats')">Thống Kê</button><button onclick="q('layout')">Layout</button><button onclick="q('settings')">Cài Đặt</button><button onclick="q('update')">Cập Nhật</button></div>
      <div class="c"><textarea id="p" placeholder="Hỏi ChatGPT về model SketchUp hiện tại..."></textarea><button class="go" onclick="send()">GỬI</button></div>
      <script>
      let busy=false,$=x=>document.getElementById(x);function add(c,t){let d=document.createElement('div');d.className='msg '+c;d.textContent=t;$('m').appendChild(d);$('m').scrollTop=$('m').scrollHeight}function data(msg){return JSON.stringify({api_key:$('k').value,model:$('mo').value,context:$('ctx').checked,viewport:$('view').checked,message:msg||''})}function wait(v){busy=v;$('st').textContent=v?'Đang gửi...':'Sẵn sàng'}function send(){if(busy)return;let t=$('p').value.trim();if(!t)return;add('u',t);$('p').value='';wait(true);sketchup.send(data(t))}function test(){if(busy)return;wait(true);sketchup.test(data())}function q(a){sketchup.quick(a)}function reply(t,ok){wait(false);add(ok?'a':'s',t);$('st').textContent=ok?'Đã kết nối':'Lỗi'}function clearChat(){$('m').innerHTML='<div class="msg s">Đã xóa hội thoại.</div>'}function cfg(x){$('mo').value=x.model||'gpt-5';if(x.env)$('k').placeholder='Đang dùng OPENAI_API_KEY từ môi trường'}$('p').onkeydown=e=>{if(e.ctrlKey&&e.key==='Enter'){e.preventDefault();send()}};document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      </script>
      HTML
    end

    def sync
      js("cfg(#{JSON.generate({model:(@model||MODEL),env:!ENV['OPENAI_API_KEY'].to_s.empty?})})")
    end

    def request(raw,test=false)
      d=JSON.parse(raw.to_s) rescue {}
      key=d['api_key'].to_s.strip; key=@key.to_s if key.empty?; key=ENV['OPENAI_API_KEY'].to_s.strip if key.empty?
      return reply('Chưa có API key OpenAI.',false) if key.empty?
      model=d['model'].to_s.strip; model=MODEL if model.empty?; @key=key; @model=model
      msg=test ? 'Chỉ trả lời: Kết nối TT – ChatGPT thành công.' : d['message'].to_s.strip
      return reply('Nội dung đang trống.',false) if msg.empty?
      ctx=(!test && d['context']) ? context : nil
      img=(!test && d['viewport']) ? viewport : nil
      hist=(@history||[]).last(10); prompt=build_prompt(hist,msg,ctx)
      worker=proc do
        r=api(key,model,prompt,img,test); t=text(r); raise 'OpenAI không trả về nội dung.' if t.empty?; [t,true]
      end
      async(worker) do |t,ok|
        if ok && !test
          @history||=[]; @history << ['user',msg] << ['assistant',t]; @history=@history.last(10)
        end
        reply(t,ok)
      end
    rescue => e
      reply(e.message,false)
    end

    def async(worker,&done)
      q=Queue.new; timer=nil
      timer=UI.start_timer(0.1,true) do
        begin
          r=q.pop(true); UI.stop_timer(timer); done.call(r[0].to_s,!!r[1])
        rescue ThreadError
        end
      end
      Thread.new do
        begin q << worker.call
        rescue => e; q << [friendly(e),false]
        end
      end
    end

    def api(key,model,prompt,img,test)
      uri=URI(API); c=[{'type'=>'input_text','text'=>prompt}]; c << {'type'=>'input_image','image_url'=>img,'detail'=>'auto'} if img
      b={'model'=>model,'input'=>[{'role'=>'user','content'=>c}],'store'=>false}
      b['instructions']=instructions unless test
      req=Net::HTTP::Post.new(uri.request_uri); req['Authorization']="Bearer #{key}"; req['Content-Type']='application/json'; req['X-Client-Request-Id']=SecureRandom.uuid; req.body=JSON.generate(b)
      res=Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:8,read_timeout:90){|h|h.request(req)}
      j=JSON.parse(res.body.to_s); raise(j.dig('error','message').to_s.empty? ? "HTTP #{res.code}" : j.dig('error','message')) unless res.is_a?(Net::HTTPSuccess); j
    end

    def text(r)
      Array(r['output']).flat_map{|i| i['type']=='message' ? Array(i['content']).select{|c|c['type']=='output_text'}.map{|c|c['text'].to_s} : []}.join("\n").strip
    end

    def instructions
      'Bạn là trợ lý kỹ thuật trong plugin SketchUp TRẦN TUẤN NỘI THẤT. Trả lời tiếng Việt, ngắn gọn, dựa vào dữ liệu model/selection được gửi. Không nói đã sửa model nếu chỉ tư vấn. Khi cần thao tác, chỉ rõ nút công cụ phù hợp trong cửa sổ.'
    end

    def build_prompt(hist,msg,ctx)
      a=[]; a << "DỮ LIỆU SKETCHUP:\n#{JSON.pretty_generate(ctx)}" if ctx; hist.each{|r,t|a << "#{r=='assistant' ? 'ChatGPT' : 'Người dùng'}: #{t}"}; a << "Người dùng: #{msg}"; a.join("\n\n")
    end

    def context
      m=Sketchup.active_model; s=m.selection.to_a; b=m.bounds
      {'plugin'=>TranTuanNoiThat.current_version,'sketchup'=>Sketchup.version.to_s,'model'=>m.title.to_s,'entities'=>m.entities.length,'selection_count'=>s.length,'selection'=>s.first(20).map{|e|{'type'=>(e.typename rescue e.class.name),'name'=>(e.name.to_s rescue ''),'tag'=>(e.layer.name.to_s rescue ''),'size_mm'=>dims((e.bounds rescue nil))}},'model_size_mm'=>dims(b)}
    rescue => e
      {'error'=>e.message}
    end

    def dims(b)
      b ? [b.width.to_mm.round(1),b.height.to_mm.round(1),b.depth.to_mm.round(1)] : nil
    rescue
      nil
    end

    def viewport
      p=File.join(Dir.tmpdir,"tt_gpt_#{Process.pid}_#{Time.now.to_i}.png"); Sketchup.active_model.active_view.write_image(filename:p,width:1024,height:768,antialias:true,transparent:false); return nil unless File.file?(p); "data:image/png;base64,#{Base64.strict_encode64(File.binread(p))}"
    ensure
      File.delete(p) if defined?(p) && p && File.file?(p)
    end

    def quick(a)
      case a
      when 'board' then Board.activate
      when 'drawer' then Drawer.activate
      when 'box' then Box.show_dialog
      when 'grain' then Grain.activate
      when 'stats' then RenameTool.show
      when 'layout' then LayoutStats.show
      when 'settings' then Settings.show
      when 'update' then Updater.check(true)
      else UI.beep
      end
    rescue => e
      UI.messagebox("Không mở được công cụ:\n#{e.message}")
    end

    def js(code); @dlg.execute_script(code) if @dlg; end
    def reply(t,ok); js("reply(#{JSON.generate(t.to_s)},#{ok ? 'true':'false'})"); end
    def friendly(e); e.is_a?(Net::OpenTimeout)||e.is_a?(Net::ReadTimeout) ? 'Kết nối OpenAI quá thời gian.' : e.message.to_s; end
  end
end
