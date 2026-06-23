import 'dart:async';
import 'dart:convert'; // ເພີ່ມສຳລັບແປງ JSON
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; // ໃຊ້ສຳລັບ Call API ຄຳນວນເສັ້ນທາງ

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
  
  // ── ຕົວແປເພີ່ມເຕີມສຳລັບລະບົບນຳທາງ ──
  List<ll.LatLng> _routePoints = []; // ເກັບຈຸດພິກັດເພື່ອແຕ້ມເສັ້ນທາງ
  bool _isLoadingRoute = false;
  StreamSubscription<Position>? _positionStreamSubscription; // ສຳລັບຕິດຕາມ GPS Real-time

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
    _initLocation().then((_) {
      // ຖ້າມີສະຖານທີ່ປາຍທາງ ໃຫ້ຄຳນວນເສັ້ນທາງທັນທີຫຼັງຈາກໄດ້ GPS ປັດຈຸບັນ
      if (_hasPlace && _currentLocation != null) {
        _calculateRoute();
      }
    });
    _startLocationTracking(); // ເລີ່ມຕິດຕາມຕຳແໜ່ງຜູ້ໃຊ້ແບບ Real-time
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel(); // ຍົກເລີກການຕິດຕາມ GPS ເມື່ອອອກຈາກໜ້າ
    super.dispose();
  }

  // ── ຂໍສິດ ແລະ ດຶງຕຳແໜ່ງປັດຈຸບັນຄັ້ງທຳອິດ ──
  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = ll.LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {
      debugPrint('GPS Error: $e');
    }
  }

  // ── ຕິດຕາມຕຳແໜ່ງຜູ້ໃຊ້ແບບເຄື່ອນທີ່ (Real-time Tracking) ──
  void _startLocationTracking() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // ອັບເດດທຸກໆການເຄື່ອນທີ່ 10 ແມັດ
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = ll.LatLng(position.latitude, position.longitude);
        });
        // ສາມາດໃສ່ຟັງຊັນຄຳນວນເສັ້ນທາງໃໝ່ໄດ້ຖ້າຜູ້ໃຊ້ຂັບລົດອອກນອກເສັ້ນທາງ
      }
    });
  }

  // ── ຟັງຊັນ Call API OSRM ເພື່ອຄຳນວນເສັ້ນທາງ ──
  Future<void> _calculateRoute() async {
    if (_currentLocation == null || !_hasPlace) return;

    setState(() => _isLoadingRoute = true);

    // OSRM ຮອງຮັບ Format: {longitude},{latitude};{longitude},{latitude}
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_currentLocation!.longitude},${_currentLocation!.latitude};'
        '${_placeLatLng.longitude},${_placeLatLng.latitude}'
        '?overview=full&geometries=geojson'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List coordinates = data['routes'][0]['geometry']['coordinates'];
          
          setState(() {
            _routePoints = coordinates
                .map((coord) => ll.LatLng(coord[1].toDouble(), coord[0].toDouble()))
                .toList();
          });
        }
      } else {
        throw Exception('ຄຳນວນເສັ້ນທາງບໍ່ສຳເລັດ');
      }
    } catch (e) {
      debugPrint('Routing Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ບໍ່ສາມາດຄຳນວນເສັ້ນທາງໄດ້: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
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
              
              // ── 1. ແຕ້ມເສັ້ນທາງ (Polyline Layer) ──
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: Colors.blue.shade700,
                      borderColor: Colors.blue.shade900,
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  // ມາກເກີ ຕຳແໜ່ງປັດຈຸບັນຂອງຜູ້ໃຊ້ (ຈະເຄື່ອນທີ່ຕາມ GPS ຕົວຈິງ)
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 25,
                      height: 25,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  
                  // ມາກເກີ ຈຸດໝາຍປາຍທາງ
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.placeName ?? 'ສະຖານທີ່',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      'Lat: ${widget.latitude!.toStringAsFixed(5)}, Lng: ${widget.longitude!.toStringAsFixed(5)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            const Icon(Icons.location_pin, color: Colors.red, size: 36),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),

          // Loading Indicator ຕອນຄຳນວນເສັ້ນທາງ
          if (_isLoadingRoute)
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)),
                        SizedBox(width: 12),
                        Text('ກຳລັງຄຳນວນເສັ້ນທາງ...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ປຸ່ມຄວບຄຸມ Zoom / My Location
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
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
                if (_hasPlace && _routePoints.isEmpty && !_isLoadingRoute) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'retry_route',
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    onPressed: _calculateRoute,
                    child: const Icon(Icons.route),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}