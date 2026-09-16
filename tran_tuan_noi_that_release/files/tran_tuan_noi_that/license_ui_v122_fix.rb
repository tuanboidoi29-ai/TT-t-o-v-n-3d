# encoding: UTF-8
# TRẦN TUẤN - LICENSE UI V1.2.2 HOTFIX
# Sửa JavaScript bị vỡ do onclick lồng dấu nháy trong heredoc Ruby.

module TranTuanNoiThat
  module License
    extend self

    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = '1.2.2'.freeze

    unless method_defined?(:tt_dialog_html_owner_v121)
      alias_method :tt_dialog_html_owner_v121, :dialog_html
    end

    def dialog_html
      html = tt_dialog_html_owner_v121

      # Sau khi heredoc Ruby được render, các chuỗi onclick cũ mất escape và làm
      # toàn bộ JavaScript ngừng parse. Thay bằng data-* hoặc &quot; để không còn
      # quote đơn lồng trong JS string quote đơn.
      html = html.gsub(
        %q{onclick="buy(''+d.requested_feature+'')"},
        %q{data-slug="'+d.requested_feature+'" onclick="buy(this.dataset.slug)"}
      )

      html = html.gsub(
        %q{onclick="buy(''+String(x.slug||'')+'')"},
        %q{data-slug="'+String(x.slug||'')+'" onclick="buy(this.dataset.slug)"}
      )

      html = html.gsub(
        %q{onclick="copyText(el('paymentCode').textContent,this)"},
        %q{onclick="copyText(document.getElementById(&quot;paymentCode&quot;).textContent,this)"}
      )

      html = html.gsub(
        %q{onclick="sketchup.check_payment(el('paymentCode').textContent)"},
        %q{onclick="sketchup.check_payment(document.getElementById(&quot;paymentCode&quot;).textContent)"}
      )

      html
    end
  end
end
