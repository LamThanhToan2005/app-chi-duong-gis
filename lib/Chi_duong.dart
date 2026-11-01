import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart'; // Thư viện phục vụ tương tác phần cứng định vị GPS của điện thoại

class DirectionScreen extends StatefulWidget {
  final List<Map<String, dynamic>> pointData;       // Danh sách các địa điểm tĩnh để chọn trong Dropdown
  final List<List<LatLng>> backgroundRoutes;       // Mạng lưới các đường dẫn dùng để xây dựng đồ thị tìm đường

  const DirectionScreen({super.key, required this.pointData, required this.backgroundRoutes});

  @override
  State<DirectionScreen> createState() => _DirectionScreenState();
}

class _DirectionScreenState extends State<DirectionScreen> {
  final MapController _mapController = MapController();
  Map<String, dynamic>? startPoint; // Điểm xuất phát (Tên địa điểm + Tọa độ LatLng)
  Map<String, dynamic>? endPoint;   // Điểm đích đến (Tên địa điểm + Tọa độ LatLng)
  String distanceResult = "";       // Chuỗi kết quả hiển thị khoảng cách tính toán (m hoặc km)
  List<LatLng> calculatedPath = []; // Mảng chứa chuỗi các điểm nối liền tạo nên đường đi ngắn nhất sau khi chạy thuật toán

  bool isNavigatingMode = false;    // Biến chuyển đổi trạng thái giao diện: Thường <-> Chế độ giả lập dẫn đường Google Maps
  bool isFetchingGPS = false;       // Trạng thái đang tải quét cập nhật vị trí từ chip GPS của máy thiết bị

  /// Hàm phụ trợ tính toán khoảng cách thực tế (theo đơn vị Mét) giữa hai tọa độ địa lý
  double _getDistanceMeter(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, p1, p2);
  }

  /// Hàm chuyển tọa độ LatLng thành chuỗi định dạng Chuẩn String làm Key duy nhất đại diện cho Đỉnh (Node) của đồ thị
  String _toNodeKey(LatLng point) {
    return "${point.latitude.toStringAsFixed(6)}_${point.longitude.toStringAsFixed(6)}";
  }

  // --- HÀM LẤY VỊ TRÍ GPS HIỆN TẠI CỦA THIẾT BỊ ---
  Future<void> _layViTriGPS() async {
    setState(() {
      isFetchingGPS = true; // Bật vòng xoay chờ tải vị trí GPS
    });

    bool serviceEnabled;
    LocationPermission permission;

    // 1. Kiểm tra xem thiết bị của người dùng đã bật tính năng định vị (GPS) hay chưa
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng bật GPS trên thiết bị!')));
      setState(() => isFetchingGPS = false);
      return;
    }

    // 2. Kiểm tra trạng thái cấp quyền truy cập vị trí của ứng dụng
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission(); // Xin quyền nếu chưa được cấp
      if (permission == LocationPermission.denied) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn đã từ chối quyền truy cập vị trí.')));
        setState(() => isFetchingGPS = false);
        return;
      }
    }
    // Trường hợp người dùng khóa quyền vĩnh viễn trong Cài đặt hệ thống
    if (permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quyền GPS bị từ chối vĩnh viễn trong cài đặt.')));
      setState(() => isFetchingGPS = false);
      return;
    }

    // 3. Lấy tọa độ GPS thực tế của điện thoại với độ chính xác cao nhất (High Accuracy)
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    setState(() {
      // Gán điểm xuất phát là vị trí GPS hiện tại của người dùng
      startPoint = {
        'name': 'Vị trí hiện tại của bạn',
        'latlng': LatLng(position.latitude, position.longitude)
      };
      isFetchingGPS = false; // Tắt trạng thái quét GPS
    });

    // Nếu người dùng đã chọn sẵn điểm đích đến trước đó, tự động kích hoạt tính năng tìm đường luôn
    if (endPoint != null) {
      xuLyTimDuong();
    } else {
      // Nếu chưa có điểm đến, chỉ di chuyển camera bản đồ tập trung vào vị trí người dùng
      _mapController.move(LatLng(position.latitude, position.longitude), 17.5);
    }
  }

  // --- THUẬT TOÁN TÌM ĐƯỜNG ĐI NGẮN NHẤT DIJKSTRA ---
  void xuLyTimDuong() {
    // Ràng buộc kiểm tra điều kiện đầu vào phải đầy đủ cả 2 đầu điểm đi và đến
    if (startPoint == null || endPoint == null) return;

    final LatLng startLatLng = startPoint!['latlng'];
    final LatLng endLatLng = endPoint!['latlng'];

    // Nếu cơ sở dữ liệu đường nền trống, không có căn cứ để chạy thuật toán tìm kiếm đường đi
    if (widget.backgroundRoutes.isEmpty) {
      setState(() {
        distanceResult = "Không có dữ liệu đường đi để tính toán.";
        calculatedPath = [startLatLng, endLatLng];
      });
      return;
    }

    // Khởi tạo các cấu trúc dữ liệu đồ thị:
    Map<String, LatLng> nodePoints = {};
    Map<String, Map<String, double>> graph = {};

    // BƯỚC 1: Duyệt qua tất cả các đoạn tọa độ trong hệ thống đường nền để xây dựng đồ thị hai chiều
    for (var route in widget.backgroundRoutes) {
      for (int i = 0; i < route.length - 1; i++) {
        LatLng p1 = route[i];
        LatLng p2 = route[i + 1];
        String k1 = _toNodeKey(p1);
        String k2 = _toNodeKey(p2);

        nodePoints[k1] = p1;
        nodePoints[k2] = p2;

        double distance = _getDistanceMeter(p1, p2); // Trọng số cạnh là độ dài thực giữa 2 điểm kề nhau
        graph.putIfAbsent(k1, () => {})[k2] = distance;
        graph.putIfAbsent(k2, () => {})[k1] = distance;
      }
    }

    // BƯỚC 2: Tìm kiếm Đỉnh thực tế nằm trong mạng lưới đường gần với Vị trí GPS / Điểm chọn của người dùng nhất
    String? startNodeKey, endNodeKey;
    double minStartDist = double.infinity, minEndDist = double.infinity;

    for (var entry in nodePoints.entries) {
      // Tìm đỉnh đường bộ gần điểm xuất phát nhất
      double dStart = _getDistanceMeter(startLatLng, entry.value);
      if (dStart < minStartDist) { minStartDist = dStart; startNodeKey = entry.key; }

      // Tìm đỉnh đường bộ gần đích đến nhất
      double dEnd = _getDistanceMeter(endLatLng, entry.value);
      if (dEnd < minEndDist) { minEndDist = dEnd; endNodeKey = entry.key; }
    }

    // Nếu không tìm thấy đỉnh tương ứng phù hợp, dừng hàm xử lý
    if (startNodeKey == null || endNodeKey == null) {
      setState(() => calculatedPath = [startLatLng, endLatLng]);
      return;
    }

    // BƯỚC 3: CÀI ĐẶT THUẬT TOÁN DIJKSTRA TRUYỀN THỐNG
    Map<String, double> distances = {for (var k in nodePoints.keys) k: double.infinity}; // Mảng lưu khoảng cách tối ưu tới các đỉnh
    Map<String, String?> predecessors = {}; // Mảng lưu vết đỉnh đi trước để phục vụ truy vết đường đi ngược lại
    distances[startNodeKey] = 0; // Đỉnh bắt đầu luôn có khoảng cách bằng 0
    Set<String> unvisited = Set.from(nodePoints.keys); // Tập hợp các đỉnh chưa được duyệt qua

    while (unvisited.isNotEmpty) {
      String? u;
      double minDistance = double.infinity;
      // Tìm đỉnh 'u' có khoảng cách nhỏ nhất trong tập hợp các đỉnh chưa duyệt qua
      for (var node in unvisited) {
        if (distances[node]! < minDistance) { minDistance = distances[node]!; u = node; }
      }

      // Nếu không tìm thêm được đỉnh thích hợp hoặc đã chạm tới Đích đến thì ngắt vòng lặp tìm kiếm
      if (u == null || u == endNodeKey || minDistance == double.infinity) break;
      unvisited.remove(u); // Đánh dấu đỉnh u đã được duyệt xong

      // Cập nhật lại khoảng cách cho toàn bộ các đỉnh láng giềng kề cạnh với đỉnh 'u'
      var neighbors = graph[u] ?? {};
      for (var v in neighbors.keys) {
        if (!unvisited.contains(v)) continue; // Bỏ qua nếu đỉnh láng giềng này đã được duyệt trước đó
        double alt = distances[u]! + neighbors[v]!; // Khoảng cách đề xuất mới = Khoảng cách u + Đoạn đường từ u sang v
        if (alt < distances[v]!) {
          distances[v] = alt; // Cập nhật lại khoảng cách ngắn hơn tối ưu hơn
          predecessors[v] = u; // Lưu lại dấu vết đường đi
        }
      }
    }

    // BƯỚC 4: TRUY VẾT TẠO KẾT QUẢ ĐƯỜNG ĐI MẢNG TUYẾN ĐƯỜNG
    List<LatLng> pathResult = [];
    if (distances[endNodeKey] != double.infinity) {
      String? current = endNodeKey;
      while (current != null) {
        pathResult.add(nodePoints[current]!);
        current = predecessors[current];
      }
      pathResult = pathResult.reversed.toList(); // Đảo ngược mảng để thu được chuỗi đường đi xuôi từ Điểm Đầu -> Điểm Cuối

      // KỸ THUẬT NỐI ĐIỂM: Tự động bổ sung nối tọa độ thực tế của người dùng/đích đến vào đồ thị đường bộ gần nhất
      if (pathResult.first != startLatLng) pathResult.insert(0, startLatLng);
      if (pathResult.last != endLatLng) pathResult.add(endLatLng);
    } else {
      pathResult = [startLatLng, endLatLng];
    }

    // BƯỚC 5: TÍNH TỔNG CHIỀU DÀI TOÀN BỘ TUYẾN ĐƯỜNG ĐÃ TÌM ĐƯỢC
    double totalLength = 0;
    for (int i = 0; i < pathResult.length - 1; i++) {
      totalLength += _getDistanceMeter(pathResult[i], pathResult[i + 1]);
    }

    // Cập nhật giao diện hiển thị kết quả đo đạc khoảng cách chi tiết đến người dùng
    setState(() {
      calculatedPath = pathResult;
      distanceResult = totalLength >= 1000
          ? "Tuyến đường: ${(totalLength / 1000).toStringAsFixed(2)} km" // Định dạng đổi sang Km nếu >= 1000 mét
          : "Tuyến đường: ${totalLength.toStringAsFixed(0)} mét";
    });

    // Tự động di chuyển tâm màn hình bản đồ về trung điểm của hành trình tìm thấy để người dùng dễ nhìn tổng quan bao quát
    _mapController.move(
      LatLng((startLatLng.latitude + endLatLng.latitude) / 2, (startLatLng.longitude + endLatLng.longitude) / 2),
      16.5,
    );
  }

  /// Hàm kích hoạt chế độ mô phỏng dẫn đường thời gian thực (HUD giống Google Maps)
  void _batDauChiDuong() {
    if (calculatedPath.isEmpty) return;
    setState(() => isNavigatingMode = true); // Chuyển giao diện sang layout HUD chỉ đường gọn gàng hơn
    _mapController.move(calculatedPath.first, 19.0); // Di chuyển zoom cận cảnh mức độ cao 19.0 vào điểm xuất phát hành trình
  }

  @override
  Widget build(BuildContext context) {
    // Nếu chưa lấy được danh sách dữ liệu điểm từ widget cha truyền xuống, hiển thị thông báo chờ tải
    if (widget.pointData.isEmpty) {
      return const Center(child: Text("Đang tải dữ liệu điểm..."));
    }

    // TRANG ẢNH ẨN CHẾ ĐỘ DẪN ĐƯỜNG MÔ PHỎNG (NAVIGATION HUD MODE COPIED GOOGLE MAPS)
    if (isNavigatingMode) {
      return Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(initialCenter: LatLng(12.2680, 109.2015), initialZoom: 19.0),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.ntu.navigation'),
              PolylineLayer(
                polylines: [
                  for (var route in widget.backgroundRoutes) Polyline(points: route, color: Colors.grey.withOpacity(0.3), strokeWidth: 3.5),
                  Polyline(points: calculatedPath, color: Colors.blue[800]!, strokeWidth: 7.0),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (startPoint != null) Marker(point: startPoint!['latlng'], child: const Icon(Icons.my_location, color: Colors.blue, size: 40)),
                  if (endPoint != null) Marker(point: endPoint!['latlng'], child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 45, bottom: 20, left: 20, right: 20),
              decoration: BoxDecoration(color: Colors.green[700], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]),
              child: Row(
                children: [
                  const Icon(Icons.turn_right_rounded, color: Colors.white, size: 40),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Đi về hướng ${endPoint != null ? endPoint!['name'] : 'đích đến'}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                        Text("Tổng khoảng cách: $distanceResult", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30, right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () {
                setState(() => isNavigatingMode = false);
                if (calculatedPath.isNotEmpty) {
                  _mapController.move(calculatedPath.first, 16.5);
                }
              },
              child: const Icon(Icons.close, color: Colors.white, size: 30),
            ),
          )
        ],
      );
    }

    // GIAO DIỆN CHỨC NĂNG TÌM ĐƯỜNG TRẠNG THÁI THƯỜNG (CHƯA VÀO ĐIỀU HƯỚNG HUD)
    List<Marker> mapMarkers = [];
    if (startPoint != null) mapMarkers.add(Marker(point: startPoint!['latlng'], width: 45, height: 45, child: const Icon(Icons.my_location, color: Colors.blue, size: 40)));
    if (endPoint != null) mapMarkers.add(Marker(point: endPoint!['latlng'], width: 45, height: 45, child: const Icon(Icons.location_on, color: Colors.red, size: 42)));

    List<Polyline> mapPolylines = [];
    for (var routePoints in widget.backgroundRoutes) {
      if (routePoints.isNotEmpty) mapPolylines.add(Polyline(points: routePoints, color: Colors.grey.withOpacity(0.35), strokeWidth: 3.0));
    }
    if (calculatedPath.isNotEmpty && startPoint != null && endPoint != null) {
      mapPolylines.add(Polyline(points: calculatedPath, color: Colors.blue[700]!, strokeWidth: 6.0));
    }

    return Column(
      children: [
        // --- PHẦN TRÊN: BẢN ĐỒ KHÔNG GIAN ---
        Expanded(
          flex: 4,
          child: FlutterMap(
            mapController: _mapController,
            options: const MapOptions(initialCenter: LatLng(12.2680, 109.2015), initialZoom: 16.5),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.ntu.navigation'),
              PolylineLayer(polylines: mapPolylines),
              MarkerLayer(markers: mapMarkers),
            ],
          ),
        ),

        // --- PHẦN DƯỚI: KHUNG ĐIỀU KHIỂN CHỌN ĐỊA ĐIỂM ---
        Expanded(
          flex: 3,
          child: Container(
            color: Colors.white,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: Text("ĐIỀU HƯỚNG BẢN ĐỒ NTU", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                  const SizedBox(height: 15),

                  const Text("Điểm bắt đầu:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Map<String, dynamic>>(
                              value: (startPoint != null && widget.pointData.any((item) => item['name'] == startPoint!['name']))
                                  ? widget.pointData.firstWhere((item) => item['name'] == startPoint!['name'])
                                  : null,
                              hint: Text(startPoint != null ? startPoint!['name'] : "Chọn vị trí xuất phát"),
                              isExpanded: true,
                              items: widget.pointData.map((item) => DropdownMenuItem<Map<String, dynamic>>(value: item, child: Text(item['name'], overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (value) {
                                setState(() => startPoint = value);
                                xuLyTimDuong(); // Kích hoạt chạy lại Dijkstra
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue[200]!)),
                        child: IconButton(
                          icon: isFetchingGPS
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location, color: Colors.blue),
                          onPressed: isFetchingGPS ? null : _layViTriGPS,
                          tooltip: 'Lấy vị trí của tôi',
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Text("Điểm kết thúc:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        value: (endPoint != null && widget.pointData.any((item) => item['name'] == endPoint!['name']))
                            ? widget.pointData.firstWhere((item) => item['name'] == endPoint!['name'])
                            : null,
                        hint: const Text("Chọn vị trí đến"),
                        isExpanded: true,
                        items: widget.pointData.map((item) => DropdownMenuItem<Map<String, dynamic>>(value: item, child: Text(item['name'], overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (value) {
                          setState(() => endPoint = value);
                          xuLyTimDuong(); // Kích hoạt chạy lại Dijkstra
                        },
                      ),
                    ),
                  ),

                  if (startPoint != null && endPoint != null && calculatedPath.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.blue.withOpacity(0.05),
                      elevation: 0,
                      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.blue.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(distanceResult, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _batDauChiDuong,
                        icon: const Icon(Icons.directions, color: Colors.white),
                        label: const Text("Bắt đầu chỉ đường", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}