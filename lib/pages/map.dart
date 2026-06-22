import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class MapPage extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final String? placeName;

  const MapPage({super.key, this.latitude, this.longitude, this.placeName});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  static const ll.LatLng _xayaboury = ll.LatLng(19.2524, 101.7117);

  ll.LatLng? _currentLocation;
  bool _showInfo = false;

  bool get _hasPlace => widget.latitude != null && widget.longitude != null;
  ll.LatLng get _placeLatLng => ll.LatLng(
        widget.latitude ?? _xayaboury.latitude,
        widget.longitude ?? _xayaboury.longitude,
      );

  @override
  void initState() {
    super.initState();
    if (_hasPlace) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showInfo = true);
      });
    }
    _initLocation();
  }

  // ── ขอและดึงตำแหน่งปัจจุบัน ──
  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('กรุณาอนุญาตให้แอปเข้าถึงตำแหน่งเพื่อนำทาง'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ถูกปฏิเสธถาวร ไปตั้งค่าให้สิทธิ์ด้วยตนเอง'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = ll.LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {
      debugPrint('GPS Error: $e');
      // ไม่ต้องแจ้งเตือน เพราะอาจไม่จำเป็น
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (_currentLocation == null) {
      await _initLocation();
    }
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
    }
  }

  // ── เปิด Google Maps พร้อมเส้นทางจากตำแหน่งปัจจุบัน ──
  Future<void> _openGoogleMapsNavigation() async {
    if (widget.latitude == null || widget.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบพิกัดปลายทาง')),
      );
      return;
    }

    // ถ้ายังไม่มีตำแหน่งปัจจุบัน ให้ลองขอใหม่
    if (_currentLocation == null) {
      await _initLocation();
    }

    String originParam = '';
    if (_currentLocation != null) {
      originParam =
          'origin=${_currentLocation!.latitude},${_currentLocation!.longitude}';
    } else {
      // ใช้ "current+location" เพื่อให้ Google Maps ใช้ GPS ของเบราว์เซอร์/ระบบ
      originParam = 'origin=current+location';
    }

    final destParam =
        'destination=${widget.latitude},${widget.longitude}';

    final Uri url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&$originParam'
      '&$destParam'
      '&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // ถ้าไม่มีแอปฯ ให้ลองเปิดในเบราว์เซอร์
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.platformDefault);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถเปิดแผนที่ได้ กรุณาติดตั้ง Google Maps'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _hasPlace ? (widget.placeName ?? 'ແຜນທີ່') : 'ແຜນທີ່ແຂວງໄຊຍະບູລີ',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: _hasPlace
            ? [
                IconButton(
                  icon: const Icon(Icons.navigation),
                  tooltip: 'ນຳທາງ Google Maps',
                  onPressed: _openGoogleMapsNavigation,
                ),
              ]
            : null,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _hasPlace ? _placeLatLng : _xayaboury,
              initialZoom: _hasPlace ? 14 : 10,
              onTap: (_, __) {
                if (_showInfo) setState(() => _showInfo = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.abc_new',
              ),
              MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  if (_hasPlace)
                    Marker(
                      point: _placeLatLng,
                      width: 180,
                      height: 90,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => setState(() => _showInfo = !_showInfo),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showInfo)
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.placeName ?? 'ສະຖານທີ່',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      'Lat: ${widget.latitude!.toStringAsFixed(5)}, '
                                      'Lng: ${widget.longitude!.toStringAsFixed(5)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            const Icon(Icons.location_pin,
                                color: Colors.red, size: 36),
                          ],
                        ),
                      ),
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

          // ปุ่มซูมและตำแหน่ง
          Positioned(
            right: 16,
            bottom: _hasPlace ? 100 : 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    );
                  },
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: _goToCurrentLocation,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // ปุ่มนำทางด้านล่าง
          if (_hasPlace)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: _openGoogleMapsNavigation,
                icon: const Icon(Icons.navigation),
                label: Text('ນຳທາງໄປ "${widget.placeName ?? 'ສະຖານທີ່'}"'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}