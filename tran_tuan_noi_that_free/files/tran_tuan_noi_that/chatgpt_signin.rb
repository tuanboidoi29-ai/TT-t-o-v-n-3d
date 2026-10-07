# encoding: UTF-8
require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'securerandom'
require 'socket'
require 'openssl'
require 'digest'
require 'fileutils'
require 'time'

module TranTuanNoiThat
  module ChatGPTConnect
    extend self

    alias_method :tt_api_key_request, :request

    SIWC_AUTH = 'https://auth.openai.com/api/accounts/authorize'.freeze unless const_defined?(:SIWC_AUTH, false)
    SIWC_TOKEN = 'https://auth.openai.com/api/accounts/oauth/token'.freeze unless const_defined?(:SIWC_TOKEN, false)
    SIWC_JWKS = 'https://auth.openai.com/.well-known/jwks.json'.freeze unless const_defined?(:SIWC_JWKS, false)
    SIWC_RESOURCE = 'https://api.openai.com/v1'.freeze unless const_defined?(:SIWC_RESOURCE, false)
    SIWC_SCOPE = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct'.freeze unless const_defined?(:SIWC_SCOPE, false)
    SIWC_DIRECT = 'chatgpt.tokens.use.direct'.freeze unless const_defined?(:SIWC_DIRECT, false)

    def build
      @dlg = UI::HtmlDialog.new(dialog_title:'TT – CHATGPT CONNECT',preferences_key:'TT.ChatGPT',scrollable:true,resizable:true,width:730,height:690,min_width:540,min_height:500,style:UI::HtmlDialog::STYLE_DIALOG)
      @dlg.set_html(html)
      @dlg.set_on_closed { @dlg = nil }
      @dlg.add_action_callback('ready') { sync }
      @dlg.add_action_callback('signin') { |_c, fresh| siwc_sign_in(fresh.to_s == 'true') }
      @dlg.add_action_callback('signout') { siwc_sign_out }
      @dlg.add_action_callback('clear') { @history=[]; js('clearChat()') }
      @dlg.add_action_callback('quick') { |_c,a| quick(a.to_s) }
      @dlg.add_action_callback('test') { |_c,j| request(j,true) }
      @dlg.add_action_callback('send') { |_c,j| request(j,false) }
    end

    def html
      <<~HTML
      <!doctype html><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{margin:0;background:#0f172a;color:#e5e7eb;font:13px Arial;height:100vh;display:flex;flex-direction:column}.h{padding:14px;background:#f97316;color:#fff}.h b{font-size:18px}.row,.q,.c{padding:9px 11px;background:#111827;border-bottom:1px solid #334155;display:flex;gap:7px;align-items:center;flex-wrap:wrap}.login{margin:10px;padding:11px;background:#172033;border:1px solid #334155;border-radius:10px}.login .row{padding:0;background:none;border:0}.muted{color:#94a3b8;font-size:12px;margin-top:7px}.badge{padding:4px 8px;border-radius:999px;background:#334155}.on{color:#86efac}.off{color:#fca5a5}input,textarea{background:#0b1220;color:#fff;border:1px solid #475569;border-radius:7px;padding:8px}#model{width:190px}.key{width:100%}button{border:0;border-radius:7px;padding:8px 10px;font-weight:bold;cursor:pointer;background:#334155;color:#fff}.loginbtn{background:#111;border:1px solid #64748b}.go{background:#ea580c}.danger{background:#7f1d1d}#m{flex:1;overflow:auto;padding:12px}.msg{padding:9px 11px;border-radius:10px;margin:7px 0;white-space:pre-wrap;line-height:1.4}.u{background:#c2410c;margin-left:12%}.a{background:#1e293b;margin-right:12%}.s{background:#0b1220;color:#94a3b8}.c{margin-top:auto;border-top:1px solid #334155}.c textarea{flex:1;min-height:70px;resize:vertical}details{margin:0 10px 10px;background:#111827;border:1px solid #334155;border-radius:8px}summary{padding:8px 10px;cursor:pointer}.adv{padding:0 10px 10px}.st{float:right;font-size:11px}
      </style><div class="h"><b>TT – CHATGPT CONNECT</b><span id="st" class="st">Sẵn sàng</span><div>TRẦN TUẤN NỘI THẤT · SketchUp ↔ ChatGPT</div></div>
      <div class="login"><div class="row"><button class="loginbtn" onclick="signin(false)">Continue with ChatGPT</button><button onclick="signin(true)">ĐỔI TÀI KHOẢN</button><span id="conn" class="badge off">Chưa kết nối</span><span id="email"></span><button class="danger" onclick="sketchup.signout()">ĐĂNG XUẤT</button></div><div class="muted">Đăng nhập ChatGPT chính thức. Khi tài khoản được cấp quyền dùng ChatGPT plan, không cần API key. Plugin không đọc lịch sử ChatGPT.</div></div>
      <div class="row"><span>Model:</span><input id="model" value=""><label><input id="ctx" type="checkbox" checked> Model/selection</label><label><input id="view" type="checkbox"> Ảnh Viewport</label><button onclick="sketchup.clear()">XÓA CHAT</button></div>
      <details><summary>API key dự phòng</summary><div class="adv"><input id="key" class="key" type="password" placeholder="OPENAI_API_KEY – chỉ dùng nếu chưa đăng nhập ChatGPT"></div></details>
      <div id="m"><div class="msg s">Ưu tiên Continue with ChatGPT. API key chỉ là phương án dự phòng.</div></div>
      <div class="q"><button onclick="q('board')">Vẽ Ván</button><button onclick="q('drawer')">Ngăn Kéo</button><button onclick="q('box')">BOX</button><button onclick="q('grain')">Xoay Vân</button><button onclick="q('stats')">Thống Kê</button><button onclick="q('layout')">Layout</button><button onclick="q('settings')">Cài Đặt</button><button onclick="q('update')">Cập Nhật</button></div>
      <div class="c"><textarea id="p" placeholder="Hỏi ChatGPT về model SketchUp hiện tại..."></textarea><button class="go" onclick="send()">GỬI</button></div>
      <script>
      let busy=false,$=x=>document.getElementById(x);function add(c,t){let d=document.createElement('div');d.className='msg '+c;d.textContent=t;$('m').appendChild(d);$('m').scrollTop=$('m').scrollHeight}function data(msg){return JSON.stringify({api_key:$('key').value,model:$('model').value,context:$('ctx').checked,viewport:$('view').checked,message:msg||''})}function wait(v,t){busy=v;$('st').textContent=t||(v?'Đang xử lý...':'Sẵn sàng')}function send(){if(busy)return;let t=$('p').value.trim();if(!t)return;add('u',t);$('p').value='';wait(true,'Đang gửi...');sketchup.send(data(t))}function signin(f){if(busy)return;wait(true,'Đang mở đăng nhập...');sketchup.signin(f?'true':'false')}function q(a){sketchup.quick(a)}function reply(t,ok){wait(false);add(ok?'a':'s',t);$('st').textContent=ok?'Đã kết nối':'Lỗi'}function oauth(t,ok){wait(false);add(ok?'a':'s',t)}function clearChat(){$('m').innerHTML='<div class="msg s">Đã xóa hội thoại.</div>'}function state(x){$('conn').textContent=x.connected?'Đã kết nối ChatGPT':'Chưa kết nối';$('conn').className='badge '+(x.connected?'on':'off');$('email').textContent=x.email||'';if(x.model)$('model').value=x.model;if(x.env)$('key').placeholder='Đang có OPENAI_API_KEY từ môi trường'}$('p').onkeydown=e=>{if(e.ctrlKey&&e.key==='Enter'){e.preventDefault();send()}};document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      </script>
      HTML
    end

    def sync
      p = siwc_load
      js("state(#{JSON.generate({connected: siwc_connected?(p), email:p['email'].to_s, model:@siwc_model.to_s, env:!ENV['OPENAI_API_KEY'].to_s.empty?})})")
    end

    def siwc_sign_in(fresh=false)
      return oauth_notice('Đăng nhập đang chạy.',false) if @siwc_busy
      @siwc_busy=true
      p=fresh ? {} : siwc_load
      host=siwc_host_id
      state=siwc_token(24); nonce=siwc_token(24); verifier=siwc_token(48); challenge=siwc_b64(Digest::SHA256.digest(verifier))
      server=TCPServer.new('127.0.0.1',0); redirect="http://127.0.0.1:#{server.addr[1]}/auth/callback"
      cid=p['client_id'].to_s.empty? ? 'dynamic_agent_client' : p['client_id'].to_s
      params={'response_type'=>'code','client_id'=>cid,'redirect_uri'=>redirect,'scope'=>SIWC_SCOPE,'resource'=>SIWC_RESOURCE,'state'=>state,'nonce'=>nonce,'code_challenge_method'=>'S256','code_challenge'=>challenge,'ext_agent_host_id'=>host}
      if cid=='dynamic_agent_client'; params['agent_name_hint']='TRẦN TUẤN NỘI THẤT'; else params['id_token_hint']=p['id_token'].to_s unless p['id_token'].to_s.empty?; params['login_hint']=p['email'].to_s unless p['email'].to_s.empty?; end
      UI.openURL(SIWC_AUTH+'?'+URI.encode_www_form(params)); oauth_notice('Trình duyệt đã mở. Hãy đăng nhập ChatGPT và cấp quyền.',true)
      async(proc do
        cb=siwc_callback(server,state,cid); td=siwc_form({'grant_type'=>'authorization_code','client_id'=>cb['client_id'],'code'=>cb['code'],'code_verifier'=>verifier,'redirect_uri'=>redirect,'resource'=>SIWC_RESOURCE}); id=siwc_verify(td.fetch('id_token'),cb['client_id'],nonce); scopes=(td['scope']||cb['scope']).to_s.split(/s+/); raise 'Bạn chưa cấp quyền dùng ChatGPT plan.' unless scopes.include?(SIWC_DIRECT)
        np={'email'=>id['email'].to_s,'sub'=>id['sub'].to_s,'client_id'=>cb['client_id'],'id_token'=>td['id_token'].to_s,'access_token'=>td['access_token'].to_s,'refresh_token'=>td['refresh_token'].to_s,'expires_in'=>td['expires_in'].to_i,'scope'=>scopes,'saved_at'=>Time.now.utc.iso8601}; raise 'OpenAI không trả access token/refresh token.' if np['access_token'].empty?||np['refresh_token'].empty?; siwc_save(np); @siwc_model=siwc_model(np['access_token']); np
      end) do |result,ok|
        @siwc_busy=false; sync; ok ? oauth_notice("Đã kết nối ChatGPT #{result['email']}. Không cần API key.",true) : oauth_notice(result.to_s,false)
      end
    rescue => e
      @siwc_busy=false; begin server.close if server&&!server.closed? rescue nil end; oauth_notice(e.message,false)
    end

    def siwc_callback(server,expected_state,requested_cid)
      raise 'Hết thời gian chờ đăng nhập.' unless IO.select([server],nil,nil,180)
      c=server.accept; first=c.gets.to_s; while (line=c.gets); break if line=="
"||line=="
"; end
      target=first.split(' ')[1].to_s; u=URI.parse("http://127.0.0.1#{target}"); q=URI.decode_www_form(u.query.to_s).to_h
      raise 'Callback đăng nhập không hợp lệ.' unless u.path=='/auth/callback'&&siwc_compare(q['state'].to_s,expected_state)
      raise(q['error_description']||q['error']) unless q['error'].to_s.empty?; raise 'Thiếu authorization code.' if q['code'].to_s.empty?
      cid=q['client_id'].to_s; cid=requested_cid if cid.empty?&&requested_cid!='dynamic_agent_client'; raise 'Thiếu client_id.' if cid.empty?||cid=='dynamic_agent_client'; raise 'client_id không khớp.' if requested_cid!='dynamic_agent_client'&&cid!=requested_cid
      body='<meta charset="utf-8"><h2>TRẦN TUẤN NỘI THẤT</h2><p>Đăng nhập thành công. Có thể đóng cửa sổ và quay lại SketchUp.</p>'; c.write("HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: #{body.bytesize}
Connection: close

#{body}")
      {'code'=>q['code'],'client_id'=>cid,'scope'=>q['scope']}
    ensure
      begin c.close if c&&!c.closed? rescue nil end; begin server.close if server&&!server.closed? rescue nil end
    end

    def siwc_form(params)
      u=URI(SIWC_TOKEN); r=Net::HTTP::Post.new(u.request_uri); r.set_form_data(params); x=Net::HTTP.start(u.host,u.port,use_ssl:true,open_timeout:8,read_timeout:30){|h|h.request(r)}; j=JSON.parse(x.body.to_s) rescue {}; raise(j.dig('error','message')||j['error_description']||j['error']||"HTTP #{x.code}") unless x.is_a?(Net::HTTPSuccess); j
    end

    def siwc_verify(jwt,cid,nonce)
      a=jwt.to_s.split('.'); raise 'ID token không hợp lệ.' unless a.length==3; h=JSON.parse(siwc_decode(a[0])); p=JSON.parse(siwc_decode(a[1])); raise 'ID token không dùng RS256.' unless h['alg']=='RS256'
      u=URI(SIWC_JWKS); x=Net::HTTP.start(u.host,u.port,use_ssl:true,open_timeout:8,read_timeout:30){|n|n.get(u.request_uri)}; keys=JSON.parse(x.body)['keys']; k=keys.find{|z|z['kid'].to_s==h['kid'].to_s}; raise 'Không tìm thấy khóa OpenAI.' unless k
      seq=OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(OpenSSL::BN.new(siwc_decode(k['n']),2)),OpenSSL::ASN1::Integer(OpenSSL::BN.new(siwc_decode(k['e']),2))]); rsa=OpenSSL::PKey::RSA.new(seq.to_der); raise 'Chữ ký ID token không hợp lệ.' unless rsa.verify(OpenSSL::Digest::SHA256.new,siwc_decode(a[2]),a[0]+'.'+a[1])
      aud=p['aud'].is_a?(Array) ? p['aud'].map(&:to_s) : [p['aud'].to_s]; raise 'ID token sai issuer/audience/nonce.' unless p['iss']=='https://auth.openai.com'&&aud.include?(cid)&&siwc_compare(p['nonce'].to_s,nonce); raise 'ID token đã hết hạn.' if p['exp'].to_i<=Time.now.to_i-30; p
    end

    def request(raw,test=false)
      p=siwc_load; return tt_api_key_request(raw,test) unless siwc_connected?(p)
      d=JSON.parse(raw.to_s) rescue {}; msg=test ? 'Chỉ trả lời: Kết nối TT – ChatGPT thành công.' : d['message'].to_s.strip; return reply('Nội dung đang trống.',false) if msg.empty?
      ctx=(!test&&d['context']) ? context : nil; img=(!test&&d['viewport']) ? viewport : nil; hist=(@history||[]).last(10); prompt=build_prompt(hist,msg,ctx); wanted=d['model'].to_s.strip
      async(proc do
        profile=siwc_access_profile; model=wanted.empty? ? (@siwc_model||=siwc_model(profile['access_token'])) : wanted; siwc_stream(profile['access_token'],model,prompt,img,test)
      end) do |text,ok|
        if ok&&!test; @history||=[]; @history<<['user',msg]<<['assistant',text]; @history=@history.last(10); end
        reply(ok ? "#{text}

[Dùng gói ChatGPT]" : text,ok)
      end
    rescue => e; reply(e.message,false); end

    def siwc_stream(token,model,prompt,img,test)
      u=URI('https://api.openai.com/v1/responses'); content=[{'type'=>'input_text','text'=>prompt}]; content<<{'type'=>'input_image','image_url'=>img,'detail'=>'auto'} if img; b={'model'=>model,'input'=>[{'role'=>'user','content'=>content}],'store'=>false,'stream'=>true}; b['instructions']=instructions unless test
      r=Net::HTTP::Post.new(u.request_uri); r['Authorization']="Bearer #{token}"; r['Content-Type']='application/json'; r['Accept']='text/event-stream'; r.body=JSON.generate(b); x=Net::HTTP.start(u.host,u.port,use_ssl:true,open_timeout:8,read_timeout:120){|h|h.request(r)}; raise siwc_error(x) unless x.is_a?(Net::HTTPSuccess)
      out=''; done=false; x.body.to_s.each_line{|line|next unless line.start_with?('data:'); s=line.sub(/Adata:s*/,'').strip; next if s.empty?||s=='[DONE]'; e=JSON.parse(s) rescue {}; out<<e['delta'].to_s if e['type']=='response.output_text.delta'; done=true if e['type']=='response.completed'; raise(e.dig('response','error','message')||'OpenAI response.failed') if e['type']=='response.failed'}; raise 'Luồng OpenAI chưa hoàn tất.' unless done; raise 'OpenAI không trả nội dung.' if out.strip.empty?; out.strip
    end

    def siwc_access_profile
      p=siwc_load; raise 'Chưa đăng nhập ChatGPT.' unless siwc_connected?(p); saved=Time.parse(p['saved_at'].to_s) rescue Time.at(0); return p if p['expires_in'].to_i<=0||Time.now<(saved+p['expires_in'].to_i-90)
      d=siwc_form({'grant_type'=>'refresh_token','client_id'=>p['client_id'],'refresh_token'=>p['refresh_token'],'resource'=>SIWC_RESOURCE}); p['access_token']=d['access_token'].to_s; p['refresh_token']=d['refresh_token'].to_s unless d['refresh_token'].to_s.empty?; p['id_token']=d['id_token'].to_s unless d['id_token'].to_s.empty?; p['expires_in']=d['expires_in'].to_i; p['scope']=d['scope'].to_s.split(/s+/) unless d['scope'].to_s.empty?; p['saved_at']=Time.now.utc.iso8601; raise 'Không refresh được phiên ChatGPT.' if p['access_token'].empty?; siwc_save(p); p
    end

    def siwc_model(token)
      u=URI('https://api.openai.com/v1/models'); r=Net::HTTP::Get.new(u.request_uri); r['Authorization']="Bearer #{token}"; x=Net::HTTP.start(u.host,u.port,use_ssl:true,open_timeout:8,read_timeout:30){|h|h.request(r)}; raise siwc_error(x) unless x.is_a?(Net::HTTPSuccess); j=JSON.parse(x.body); a=j['models'].is_a?(Array) ? j['models'] : Array(j['data']); visible=a.select{|m|m['visibility'].nil?||m['visibility']=='list'}; slug=(visible.first||a.first||{})['slug']||(visible.first||a.first||{})['id']; raise 'Không có model khả dụng trong gói ChatGPT.' if slug.to_s.empty?; slug.to_s
    end

    def siwc_sign_out
      p=siwc_load; return oauth_notice('Chưa có tài khoản ChatGPT.',false) if p.empty?; %w[access_token refresh_token id_token saved_at].each{|k|p[k]=''}; p['scope']=[]; p['expires_in']=0; siwc_save(p); @siwc_model=nil; @history=[]; sync; oauth_notice('Đã đăng xuất cục bộ. Có thể thu hồi quyền ứng dụng trong ChatGPT Settings.',true)
    end

    def siwc_path; base=ENV['LOCALAPPDATA'].to_s; base=File.expand_path('~') if base.empty?; File.join(base,'TranTuanNoiThat','chatgpt_auth.json'); end
    def siwc_load; File.file?(siwc_path) ? (JSON.parse(File.binread(siwc_path)) rescue {}) : {}; end
    def siwc_save(p); FileUtils.mkdir_p(File.dirname(siwc_path)); t=siwc_path+".tmp#{Process.pid}"; File.open(t,'wb',0600){|f|f.write(JSON.generate(p))}; File.chmod(0600,t) rescue nil; FileUtils.mv(t,siwc_path); File.chmod(0600,siwc_path) rescue nil; end
    def siwc_connected?(p); p.is_a?(Hash)&&!p['access_token'].to_s.empty?&&Array(p['scope']).map(&:to_s).include?(SIWC_DIRECT); end
    def siwc_host_id; h=TranTuanNoiThat.setting('chatgpt_host_id','').to_s; if h.empty?; h="urn:uuid:#{SecureRandom.uuid}"; TranTuanNoiThat.save_setting('chatgpt_host_id',h); end; h; end
    def siwc_token(n); siwc_b64(SecureRandom.random_bytes(n)); end
    def siwc_b64(v); Base64.urlsafe_encode64(v).delete('='); end
    def siwc_decode(v); s=v.to_s.tr('-_','+/'); s+='='*((4-s.length%4)%4); Base64.decode64(s); end
    def siwc_compare(a,b); return false unless a.bytesize==b.bytesize; n=0; a.bytes.zip(b.bytes){|x,y|n|=x^y}; n==0; end
    def siwc_error(x); j=JSON.parse(x.body.to_s) rescue {}; (j.dig('error','message')||j['detail']||j.dig('error','code')||"HTTP #{x.code}").to_s; end
    def oauth_notice(t,ok); js("oauth(#{JSON.generate(t.to_s)},#{ok ? 'true':'false'})"); sync; true; end
  end
end
