import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'subject_model.dart';

class ScheduleService {
  HeadlessInAppWebView? _headlessWebView;

  Future<void> fetchNTUSchedule({
    required String username,
    required String password,
    required Function(List<Subject>) onSuccess,
    required Function(String) onError,
  }) async {
    _headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri("https://qldt.ntu.edu.vn/sinhvien/thoikhoabieu")),

      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        loadsImagesAutomatically: false,
      ),

      onLoadStop: (controller, url) async {
        String currentUrl = url.toString().toLowerCase();
        debugPrint("==== ĐANG TẢI TRANG: $currentUrl ====");

        // ĐĂNG NHẬP
        if (currentUrl.contains("login") || currentUrl.contains("account") || currentUrl.contains("dangnhap") || currentUrl == "https://qldt.ntu.edu.vn/") {
          await controller.evaluateJavascript(source: """
            setTimeout(function() {
              var userInp = document.getElementById('txtTaiKhoan') || document.querySelector('input[type="text"]');
              var passInp = document.getElementById('txtMatKhau') || document.querySelector('input[type="password"]');
              var btnBtn = document.getElementById('btnDangNhap') || document.querySelector('button[type="submit"]');
              
              if(userInp && passInp && btnBtn) {
                userInp.value = '$username';
                passInp.value = '$password';
                btnBtn.click();
              }
            }, 2500);
          """);
        }
        // BÓC TÁCH DỮ LIỆU
        else if (currentUrl.contains("thoikhoabieu")) {
          var rawJsonData = await controller.evaluateJavascript(source: """
            (function() {
              var listSubjects = [];
              
              // QUÉT THEO DẠNG LƯỚI / MA TRẬN (Như hình ảnh bạn gửi)
              var allTds = document.querySelectorAll('table td');
              var days = ["", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "Chủ nhật"];
              
              allTds.forEach(function(td) {
                  var txt = td.innerText.trim();
                  // Kiểm tra xem ô lưới có chứa thông tin phòng học hay không
                  if (txt.length > 10 && txt.toLowerCase().includes('phòng')) {
                      
                      // Cắt chuỗi theo từng dòng
                      var lines = txt.split('\\n').map(function(l) { return l.trim(); }).filter(function(l) { return l !== ''; });
                      
                      if(lines.length >= 3) {
                          var name = lines[0]; // Thường dòng đầu tiên là tên môn
                          var room = "Chưa rõ";
                          var lesson = "Chưa rõ";
                          var dayOfWeek = "Chưa rõ";
                          
                          // Lấy Thứ dựa vào chỉ số cột của bảng
                          var colIdx = td.cellIndex;
                          if (colIdx >= 1 && colIdx <= 7) {
                              dayOfWeek = days[colIdx];
                          }

                          // Tìm dòng chứa Phòng và Tiết
                          lines.forEach(function(line) {
                              var lineLower = line.toLowerCase();
                              if(lineLower.includes('phòng')) {
                                  var parts = line.split(':');
                                  if(parts.length > 1) room = parts[1].trim();
                              }
                              if(lineLower.includes('tiết')) {
                                  var parts = line.split(':');
                                  if(parts.length > 1) lesson = parts[1].trim();
                              }
                          });
                          
                          listSubjects.push({
                              'name': name,
                              'room': room,
                              'dayOfWeek': dayOfWeek,
                              'lesson': lesson
                          });
                      }
                  }
              });

              return JSON.stringify(listSubjects);
            })();
          """);

          debugPrint("-> JSON lấy được: $rawJsonData");

          if (rawJsonData != null && rawJsonData.toString() != "[]") {
            try {
              List<dynamic> decodedList = jsonDecode(rawJsonData.toString());
              List<Subject> processedSchedule = decodedList.map((item) => Subject.fromMap(item)).toList();
              onSuccess(processedSchedule);
            } catch (e) {
              onError("Lỗi cấu trúc: " + e.toString());
            }
          } else {
            // Đã đổi câu thông báo cho sát với thực tế
            onError("Lịch học tuần này của bạn đang trống (không có môn nào) hoặc mạng quá chậm. Hãy kiểm tra lại lịch học trên web!");
          }

          await _headlessWebView?.dispose();
          _headlessWebView = null;
        }
      },
    );

    await _headlessWebView?.run();
  }
}