import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  // พิกัดเริ่มต้น: แขวงไชยะบุลี
  static const ll.LatLng _initialPosition = ll.LatLng(19.2524, 101.7117);

  ll.LatLng _selectedLocation = _initialPosition;
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ເລືອກພິກັດໃນແຜນທີ່',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 28),
            onPressed: () {
              Navigator.pop(context, _selectedLocation);
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          // แผนที่แบบโต้ตอบ
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialPosition,
              initialZoom: 12,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedLocation = point;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.abc_new',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // คำแนะนำด้านบน
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.teal),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ວິທີເລືອກ: ຈິ້ມເທິງແຜນທີ່ເພື່ອປັກໝຸດ ແລ້ວກົດປຸ່ມ ✔️ ດ້ານເທິງຂວາເພື່ອບັນທຶກ',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // แสดงพิกัด实时
          Positioned(
            bottom: 24,
            left: 16,
            right: 90,
            child: Card(
              color: Colors.teal[900],
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  'Latitude: ${_selectedLocation.latitude.toStringAsFixed(6)}\nLongitude: ${_selectedLocation.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}