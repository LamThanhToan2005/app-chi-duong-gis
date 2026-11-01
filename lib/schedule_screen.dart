import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'subject_model.dart';
import 'schedule_service.dart';

class ScheduleScreen extends StatefulWidget {
  final List<Map<String, dynamic>> pointData;
  final Function(Map<String, dynamic>) onNavigateToRoom;
  final Function(Map<String, dynamic>) onShowOnMap;

  const ScheduleScreen({
    super.key,
    required this.pointData,
    required this.onNavigateToRoom,
    required this.onShowOnMap,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ScheduleService _scheduleService = ScheduleService();

  List<Subject> _subjectsList = [];
  bool _isLoading = false;
  String _loadingStatusText = "";

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _loadCachedSchedule(); // 🚀 Tải siêu tốc lịch học từ bộ nhớ đệm khi mở trang
  }

  // 🚀 Hàm tải lịch học cũ lưu Offline (không cần cào lại)
  Future<void> _loadCachedSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('cached_schedule');
    if (cachedData != null) {
      List<dynamic> decodedList = jsonDecode(cachedData);
      setState(() {
        _subjectsList = decodedList.map((item) => Subject.fromMap(item)).toList();
      });
    }
  }

  // 🚀 Hàm lưu lịch học vào bộ nhớ sau khi lấy thành công từ Web
  Future<void> _saveScheduleToCache(List<Subject> subjects) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> jsonList = subjects.map((sub) => {
      'name': sub.name,
      'room': sub.room,
      'dayOfWeek': sub.dayOfWeek,
      'lesson': sub.lesson,
    }).toList();
    await prefs.setString('cached_schedule', jsonEncode(jsonList));
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _usernameController.text = prefs.getString('ntu_username') ?? '';
      _passwordController.text = prefs.getString('ntu_password') ?? '';
    });
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ntu_username', _usernameController.text);
    await prefs.setString('ntu_password', _passwordController.text);
  }

  // --- LỌC LỊCH HỌC NGÀY MAI ---
  List<Subject> _getTomorrowSubjects() {
    if (_subjectsList.isEmpty) return [];

    DateTime now = DateTime.now();
    int tomorrowWeekday = now.weekday + 1;
    if (tomorrowWeekday > 7) tomorrowWeekday = 1;

    String mapDay(int day) {
      if (day == 1) return "Chủ nhật";
      return "Thứ ${day}";
    }

    String tomorrowStr = mapDay(tomorrowWeekday);
    return _subjectsList.where((subject) => subject.dayOfWeek.toLowerCase().contains(tomorrowStr.toLowerCase())).toList();
  }

  void _syncSchedule() {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vui lòng nhập Mã SV và Mật khẩu!")));
      return;
    }

    _saveCredentials();

    setState(() {
      _isLoading = true;
      _loadingStatusText = "Đang kết nối cổng thông tin NTU...";
    });

    _scheduleService.fetchNTUSchedule(
      username: _usernameController.text,
      password: _passwordController.text,
      onSuccess: (subjects) {
        setState(() {
          _subjectsList = subjects;
          _isLoading = false;
          _loadingStatusText = "";
        });

        _saveScheduleToCache(subjects); // 🚀 LƯU VÀO CACHE CHO LẦN SAU DÙNG TẠI ĐÂY

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đồng bộ thành công ${_subjectsList.length} môn học!")),
        );
      },
      onError: (errorMessage) {
        setState(() {
          _isLoading = false;
          _loadingStatusText = "";
        });
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Đồng bộ thất bại"),
            content: Text(errorMessage),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Đóng"))],
          ),
        );
      },
    );
  }

  // Xử lý tìm kiếm tọa độ phòng học và chuyển sang Map/Direction
  void _handleAction(String roomName, bool isMapFocus) {
    if (widget.pointData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chưa có dữ liệu bản đồ.")));
      return;
    }

    String roomCleaned = roomName.trim().toUpperCase();
    var matchPoint = widget.pointData.firstWhere(
          (point) => point['name'].toString().toUpperCase() == roomCleaned,
      orElse: () => <String, dynamic>{},
    );

    if (matchPoint.isNotEmpty) {
      if (isMapFocus) {
        widget.onShowOnMap(matchPoint);
      } else {
        widget.onNavigateToRoom(matchPoint);
      }
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Phòng học chưa số hóa"),
          content: Text("Hệ thống chưa tìm thấy tọa độ phòng [$roomName] trên hệ thống đường dẫn. Xin hãy cập nhật thêm file JSON!"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Subject> tomorrowSubjects = _getTomorrowSubjects();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. CARD ĐĂNG NHẬP NTU
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_circle, color: Colors.blue),
                      SizedBox(width: 10),
                      Text("Tài khoản Sinh viên", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                        labelText: "Mã Sinh Viên",
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: "Mật khẩu Cổng thông tin",
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
                    ),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _syncSchedule,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[800],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("Đồng bộ Thời khóa biểu", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (_loadingStatusText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Center(child: Text(_loadingStatusText, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic))),
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. KHU VỰC HIỂN THỊ LỊCH HỌC NGÀY MAI
          const Text("Lịch học ngày mai:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          if (_subjectsList.isEmpty)
            Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(Icons.event_busy, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      Text("Chưa có dữ liệu lịch học", style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
            )
          else if (tomorrowSubjects.isEmpty)
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text("Thông báo: Ngày mai bạn KHÔNG CÓ LỊCH HỌC!", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            )
          else
            ...tomorrowSubjects.map((sub) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.blue.withOpacity(0.3))),
              elevation: 0,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: const Icon(Icons.class_, color: Colors.blue),
                ),
                title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Tiết: ${sub.lesson} | Phòng: ${sub.room}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.map_rounded, color: Colors.blue),
                      tooltip: "Xem trên Bản đồ",
                      onPressed: () => _handleAction(sub.room, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.assistant_direction_rounded, color: Colors.green),
                      tooltip: "Chỉ đường đến phòng",
                      onPressed: () => _handleAction(sub.room, false),
                    ),
                  ],
                ),
              ),
            )),

          const Divider(height: 30),

          // 3. TOÀN BỘ LỊCH HỌC
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Tất cả môn học:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              if (_subjectsList.isNotEmpty) Text("Tổng cộng: ${_subjectsList.length} môn", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),

          if (_subjectsList.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _subjectsList.length,
              itemBuilder: (context, index) {
                var sub = _subjectsList[index];
                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(sub.dayOfWeek, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text("Tiết: ${sub.lesson} | Phòng: ${sub.room}", style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.map_rounded, color: Colors.blue),
                          onPressed: () => _handleAction(sub.room, true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.assistant_direction_rounded, color: Colors.green),
                          onPressed: () => _handleAction(sub.room, false),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}