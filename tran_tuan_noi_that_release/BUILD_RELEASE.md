# Phát hành TRẦN TUẤN NỘI THẤT

Gói RBZ phải chứa trực tiếp `TranTuanNoiThat.rb` và thư mục `tran_tuan_noi_that/` ở cấp đầu tiên.

```bash
zip -r TRAN_TUAN_NOI_THAT_V1.7.1.rbz TranTuanNoiThat.rb tran_tuan_noi_that HUONG_DAN_TRAN_TUAN_NOI_THAT.txt
```

Mỗi bản mới cần cập nhật `VERSION`, `update.json`, SHA-256 từng file và tên RBZ. Updater sẽ sao lưu file hiện tại, kiểm tra mã SHA-256, thay file rồi nạp lại các module mà không cần khởi động SketchUp.
