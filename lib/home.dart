import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import 'Chi_duong.dart';
import 'Trang_chu.dart';
import 'schedule_screen.dart';

class Menu extends StatefulWidget {
  const Menu({super.key});

  @override
  State<Menu> createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  int currentIndex = 0;
  List<Map<String, dynamic>> sharedPointData = [];
  List<List<LatLng>> sharedRouteData = [];
  bool isLoadingData = true;
  Map<String, dynamic>? selectedRoomFromSchedule;

  @override
  void initState() {
    super.initState();
    taiTatCaDuLieu();
  }

  Future<void> taiTatCaDuLieu() async {
    try {
      // 1. 🌟 ĐỌC DỮ LIỆU ĐỊA ĐIỂM TỪ FILE LOCAL: asset/ViTri.json
      List<Map<String, dynamic>> tempPoints = [];
      try {
        String viTriString = await rootBundle.loadString('asset/ViTri.json');
        final pointRes = jsonDecode(viTriString);

        if (pointRes != null && pointRes['features'] != null) {
          for (var feature in pointRes['features']) {
            var geometry = feature['geometry'];
            var properties = feature['properties'];
            if (geometry != null && geometry['coordinates'] != null) {
              tempPoints.add({
                'name': properties['name'] ?? 'Không tên',
                // Chú ý: GeoJSON thường lưu tọa độ theo dạng [Kinh độ (lng), Vĩ độ (lat)]
                'latlng': LatLng(geometry['coordinates'][1], geometry['coordinates'][0]),
              });
            }
          }
        }
      } catch (e) {
        debugPrint("Lỗi khi đọc file ViTri.json: $e");
      }

      // 2. 🌟 ĐỌC DỮ LIỆU ĐƯỜNG ĐI TỪ FILE LOCAL: asset/ntu_duong.json
      List<List<LatLng>> tempRoutes = [];
      try {
        String jsonString = await rootBundle.loadString('asset/ntu_duong.json');
        final routeRes = jsonDecode(jsonString);

        // Hỗ trợ cả 2 định dạng: FeatureCollection và GeometryCollection
        var items = routeRes['features'] ?? routeRes['geometries'];
        if (items != null) {
          for (var item in items) {
            // Nếu là Feature thì lấy geometry ở trong, nếu là GeometryCollection thì bản thân item chính là geometry
            var geometry = item['geometry'] ?? item;

            if (geometry != null && geometry['coordinates'] != null) {
              String type = geometry['type'] ?? '';

              if (type == 'LineString') {
                List<LatLng> points = [];
                for (var coord in geometry['coordinates']) {
                  points.add(LatLng(coord[1], coord[0]));
                }
                if (points.isNotEmpty) tempRoutes.add(points);
              }
              else if (type == 'MultiLineString') {
                for (var line in geometry['coordinates']) {
                  List<LatLng> points = [];
                  for (var coord in line) {
                    points.add(LatLng(coord[1], coord[0]));
                  }
                  if (points.isNotEmpty) tempRoutes.add(points);
                }
              }
            }
          }
        } else if (routeRes is List) {
          // Đề phòng trường hợp json chỉ là Array thô sơ [[[lng,lat], [lng,lat]]]
          for (var route in routeRes) {
            if (route is List) {
              List<LatLng> points = [];
              for (var coord in route) {
                if (coord is List && coord.length >= 2) {
                  points.add(LatLng(coord[1], coord[0]));
                }
              }
              if (points.isNotEmpty) tempRoutes.add(points);
            }
          }
        }
      } catch (assetError) {
        debugPrint("Lỗi khi đọc file ntu_duong.json: $assetError");
      }

      // Cập nhật State để UI render lại bản đồ
      setState(() {
        sharedPointData = tempPoints;
        sharedRouteData = tempRoutes;
        isLoadingData = false;
      });

      debugPrint("Đã tải xong: ${sharedPointData.length} địa điểm và ${sharedRouteData.length} tuyến đường từ Local.");
    } catch (e) {
      debugPrint("Lỗi tổng quát khi tải dữ liệu Local: $e");
      setState(() => isLoadingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      MapScreen(
        pointDataFromServer: sharedPointData,
        routeDataFromServer: sharedRouteData,
        isLoadingFromServer: isLoadingData,
        focusPoint: selectedRoomFromSchedule,
      ),
      DirectionScreen(
        pointData: sharedPointData,
        backgroundRoutes: sharedRouteData,
      ),
      ScheduleScreen(
        pointData: sharedPointData,
        onNavigateToRoom: (destinationPoint) {
          setState(() {
            currentIndex = 1;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Đã chọn đích đến: [${destinationPoint['name']}] từ lịch học!"),
              backgroundColor: Colors.green[700],
            ),
          );
        },
        onShowOnMap: (destinationPoint) {
          setState(() {
            selectedRoomFromSchedule = destinationPoint;
            currentIndex = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Đang định vị phòng học: [${destinationPoint['name']}] trên bản đồ!"),
              backgroundColor: Colors.blue[700],
            ),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentIndex == 0 ? "Bản đồ ĐH Nha Trang" : (currentIndex == 1 ? "Tìm đường đi" : "Lịch học sinh viên"),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[800],
      ),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.blue[800],
          onTap: (value) {
            if (value < pages.length) {
              setState(() => currentIndex = value);
            }
          },
          items: const [
            BottomNavigationBarItem(label: "Bản đồ", icon: Icon(Icons.map_rounded)),
            BottomNavigationBarItem(label: "Chỉ đường", icon: Icon(Icons.approval_rounded)),
            BottomNavigationBarItem(label: "Lịch học", icon: Icon(Icons.calendar_month_rounded)),
          ]),
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
    );
  }
}