import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> pointDataFromServer; // Nhận danh sách điểm từ file home.dart
  final List<List<LatLng>> routeDataFromServer;       // Nhận danh sách các con đường từ file home.dart
  final bool isLoadingFromServer;                    // Nhận trạng thái loading từ server
  final Map<String, dynamic>? focusPoint;

  const MapScreen({
    super.key,
    required this.pointDataFromServer,
    required this.routeDataFromServer,
    required this.isLoadingFromServer,
    this.focusPoint,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController(); // Bộ điều khiển bản đồ (dùng để di chuyển camera zoom, pan)
  LatLng? selectedPoint; // Lưu trữ tọa độ của địa điểm đang được người dùng bấm chọn
  String? selectedName;  // Lưu trữ tên của địa điểm đang được người dùng bấm chọn

  // Khai báo tọa độ trung tâm mặc định (Đại học Nha Trang) để định vị bản đồ lúc mở lên
  final LatLng mapCenter = const LatLng(12.2680, 109.2015);

  //HÀM NÀY: Lắng nghe xem khi nào từ màn hình lịch học gửi vị trí sang thì tự nhảy bản đồ tới đó
  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusPoint != null && widget.focusPoint != oldWidget.focusPoint) {
      // Đợi bản đồ ổn định cấu trúc rồi tự động click chọn tiêu điểm phòng học
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onPointSelected(widget.focusPoint!);
      });
    }
  }

  // Hàm xử lý sự kiện khi người dùng click chọn một địa điểm trong danh sách hoặc trên bản đồ
  void _onPointSelected(Map<String, dynamic> item) {
    setState(() {
      selectedPoint = item['latlng'];
      selectedName = item['name'];
    });
    // Di chuyển tâm bản đồ mượt mà đến vị trí được chọn và tăng độ Zoom lên 17.5 để nhìn rõ hơn
    _mapController.move(selectedPoint!, 18);
  }

  @override
  Widget build(BuildContext context) {
    // Nếu ứng dụng đang tải dữ liệu từ Supabase, hiển thị vòng tròn tiến trình (Loading) giữa màn hình
    if (widget.isLoadingFromServer) {
      return const Center(child: CircularProgressIndicator());
    }

    // 1. BIẾN ĐỔI DỮ LIỆU TỪ SERVER THÀNH CÁC ĐƯỜNG POLYLINE ĐỂ VẼ LÊN BẢN ĐỒ
    List<Polyline> backgroundPolylines = widget.routeDataFromServer.map((points) {
      return Polyline(
        points: points,
        color: Colors.grey.withOpacity(0.5), // Đường nền có màu xám trong suốt nhẹ
        strokeWidth: 3.5, // Độ dày đường vẽ nét
      );
    }).toList();

    // 2. TẠO DANH SÁCH CÁC MARKER GHIM VỊ TRÍ ĐỊA ĐIỂM
    List<Marker> allMarkers = widget.pointDataFromServer.map((item) {
      // Kiểm tra xem Marker hiện tại có đang trùng với điểm được người dùng click chọn hay không
      final isSelected = selectedPoint == item['latlng'];

      return Marker(
        point: item['latlng'],
        // Nếu được chọn, nới rộng kích thước Marker để chứa khung hiển thị tên địa điểm phía trên
        width: isSelected ? 160 : 40,
        height: isSelected ? 85 : 40,
        child: GestureDetector(
          onTap: () => _onPointSelected(item), // Click trực tiếp vào marker trên bản đồ
          child: isSelected
              ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Khung bong bóng màu trắng hiển thị tên địa điểm khi Marker được chọn
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                  ],
                ),
                child: Text(
                  item['name'],
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center,
                  maxLines: 2, // Giới hạn tối đa 2 dòng, quá ký tự tự động hiển thị dấu '...'
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Ghim định vị màu ĐỎ khi được lựa chọn
              const Icon(Icons.location_on, color: Colors.red, size: 36),
            ],
          )
              : const Icon(Icons.location_on, color: Colors.blue, size: 28), // Mặc định ghim màu XANH
        ),
      );
    }).toList();

    return Column(
      children: [
        // --- PHẦN 1: KHU VỰC HIỂN THỊ BẢN ĐỒ (Chiếm tỉ lệ 4 phần) ---
        Expanded(
          flex: 4,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 16.5,
            ),
            children: [
              // Lớp nền bản đồ OpenStreetMap công cộng
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ntu.pointcheck',
              ),
              PolylineLayer(polylines: backgroundPolylines), // Đè lớp mạng lưới đường lên
              MarkerLayer(markers: allMarkers),              // Đè lớp ghim địa điểm lên trên cùng
            ],
          ),
        ),

        // --- PHẦN 2: KHU VỰC DANH SÁCH ĐỊA ĐIỂM DƯỚI ĐÁY MÀN HÌNH (Chiếm tỉ lệ 3 phần) ---
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.0),
                  child: Text(
                      "DANH SÁCH ĐỊA ĐIỂM NTU",
                      style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                ),
                const Divider(height: 1), // Đường kẻ phân cách thanh tiêu đề công cụ
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.pointDataFromServer.length,
                    separatorBuilder: (context, index) => const Divider(height: 1), // Đường kẻ giữa các dòng danh sách
                    itemBuilder: (context, index) {
                      final item = widget.pointDataFromServer[index];
                      final isSelected = selectedPoint == item['latlng'];

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Colors.blue.withOpacity(0.08), // Đổi nền dòng thành xanh nhạt khi được chọn
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? Colors.blue : Colors.grey[200],
                          child: Text(
                              "${index + 1}", // Hiển thị số thứ tự tăng dần
                              style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 13)
                          ),
                        ),
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          "Tọa độ: ${item['latlng'].latitude.toStringAsFixed(5)}, ${item['latlng'].longitude.toStringAsFixed(5)}",
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null, // Hiện dấu tích xanh khi chọn
                        onTap: () => _onPointSelected(item), // Click chọn dòng sẽ cập nhật vị trí bản đồ tương ứng
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}