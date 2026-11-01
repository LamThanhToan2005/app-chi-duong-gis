class Subject {
  final String name;       // Tên môn học (Ví dụ: Kỹ thuật lập trình)
  final String room;       // Phòng học (Ví dụ: G3.202)
  final String dayOfWeek;  // Thứ mấy trong tuần (Ví dụ: Thứ 3)
  final String lesson;     // Tiết học (Ví dụ: Tiết 1 - 3)

  Subject({
    required this.name,
    required this.room,
    required this.dayOfWeek,
    required this.lesson,
  });

  // Chuyển đổi dữ liệu Map nhận được từ JavaScript chạy trên Web sang đối tượng Dart
  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      name: map['name'] ?? 'Không rõ tên môn',
      room: map['room'] ?? 'Không rõ phòng học',
      dayOfWeek: map['dayOfWeek'] ?? '',
      lesson: map['lesson'] ?? '',
    );
  }
}