import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ── ປະເພດ Map Layer ──
enum MapLayerType { normal, satellite, terrain, hybrid }

extension MapLayerExtension on MapLayerType {
  String get label {
    switch (this) {
      case MapLayerType.normal:
        return 'ປົກກະຕິ';
      case MapLayerType.satellite:
        return 'ດາວທຽມ';
      case MapLayerType.terrain:
        return 'ພູດອຍ';
      case MapLayerType.hybrid:
        return 'ປະສົມ';
    }
  }

  IconData get icon {
    switch (this) {
      case MapLayerType.normal:
        return Icons.map_outlined;
      case MapLayerType.satellite:
        return Icons.satellite_alt;
      case MapLayerType.terrain:
        return Icons.terrain;
      case MapLayerType.hybrid:
        return Icons.layers;
    }
  }

  String get tileUrl {
    switch (this) {
      case MapLayerType.normal:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapLayerType.satellite:
      case MapLayerType.hybrid:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapLayerType.terrain:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
    }
  }

  String? get overlayUrl {
    if (this == MapLayerType.hybrid) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    return null;
  }

  String get attribution {
    switch (this) {
      case MapLayerType.normal:
        return 'OpenStreetMap contributors';
      case MapLayerType.satellite:
      case MapLayerType.hybrid:
        return 'Esri, DigitalGlobe, GeoEye | OSM contributors';
      case MapLayerType.terrain:
        return 'OpenTopoMap | OSM contributors';
    }
  }
}

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

  MapLayerType _currentLayer = MapLayerType.normal;
  bool _showLayerPanel = false;

  List<ll.LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  StreamSubscription<Position>? _positionStreamSubscription;

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
      // ถ้ามีพิกัดและได้ตำแหน่งแล้ว ให้คำนวณเส้นทาง
      if (_hasPlace && _currentLocation != null) {
        _calculateRoute();
      }
    });
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = ll.LatLng(pos.latitude, pos.longitude);
      });
      // ถ้ามีพิกัดและเพิ่งได้ตำแหน่ง ให้คำนวณเส้นทาง
      if (_hasPlace && mounted) {
        _calculateRoute();
      }
    } catch (e) {
      debugPrint('GPS Error: $e');
    }
  }

  void _startLocationTracking() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = ll.LatLng(position.latitude, position.longitude);
        });
        // 🔁 เมื่อตำแหน่งเปลี่ยนแปลง ให้คำนวณเส้นทางใหม่ (ถ้ามีสถานที่)
        if (_hasPlace && mounted) {
          _calculateRoute();
        }
      }
    });
  }

  Future<void> _calculateRoute() async {
    if (_currentLocation == null || !_hasPlace) return;
    setState(() => _isLoadingRoute = true);

    final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '${_currentLocation!.longitude},${_currentLocation!.latitude};'
        '${_placeLatLng.longitude},${_placeLatLng.latitude}'
        '?overview=full&geometries=geojson');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List coordinates = data['routes'][0]['geometry']['coordinates'];
          setState(() {
            _routePoints = coordinates
                .map((coord) =>
                    ll.LatLng(coord[1].toDouble(), coord[0].toDouble()))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Routing Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('ບໍ່ສາມາດຄຳນວນເສັ້ນທາງໄດ້: $e'),
              backgroundColor: Colors.red),
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

  Widget _buildLayerPanel() {
    return Positioned(
      right: 16,
      bottom: 200,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _showLayerPanel
            ? Card(
                key: const ValueKey('panel'),
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: MapLayerType.values.map((layer) {
                      final selected = _currentLayer == layer;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _currentLayer = layer;
                            _showLayerPanel = false;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                selected ? Colors.teal.withOpacity(0.15) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(layer.icon,
                                  size: 20,
                                  color:
                                      selected ? Colors.teal : Colors.black54),
                              const SizedBox(width: 8),
                              Text(
                                layer.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color:
                                      selected ? Colors.teal : Colors.black87,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.check,
                                    size: 16, color: Colors.teal),
                              ]
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('hidden')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layer = _currentLayer;

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
                if (_showLayerPanel) setState(() => _showLayerPanel = false);
              },
            ),
            children: [
              // ── Base Tile Layer ──
              TileLayer(
                urlTemplate: layer.tileUrl,
                userAgentPackageName: 'com.example.abc_new',
              ),

              // ── Overlay Hybrid ──
              if (layer.overlayUrl != null)
                Opacity(
                  opacity: 0.55,
                  child: TileLayer(
                    urlTemplate: layer.overlayUrl!,
                    userAgentPackageName: 'com.example.abc_new',
                  ),
                ),

              // ── เส้นทาง ──
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

              // ── Markers ──
              MarkerLayer(
                markers: [
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
                            BoxShadow(color: Colors.black38, blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                  if (_hasPlace)
                    Marker(
                      point: _placeLatLng,
                      width: 40, // ✅ เปลี่ยนจาก 180
                      height: 40, // ✅ เปลี่ยนจาก 90
                      // ❌ ลบ alignment: Alignment.topCenter ออก (หรือตั้งเป็น center)
                      child: GestureDetector(
                        onTap: () => setState(() => _showInfo = !_showInfo),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // หมุดหลัก
                            const Icon(Icons.location_pin,
                                color: Colors.red, size: 40),
                            // Info bubble แสดงเมื่อกด (แสดงเหนือหมุด)
                            if (_showInfo)
                              Positioned(
                                bottom: 42, // อยู่เหนือหมุด
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: Offset(0, 2))
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.placeName ?? 'ສະຖານທີ່',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        'Lat: ${widget.latitude!.toStringAsFixed(5)}, Lng: ${widget.longitude!.toStringAsFixed(5)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              RichAttributionWidget(
                attributions: [TextSourceAttribution(layer.attribution)],
              ),
            ],
          ),

          // ── Loading ──
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
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.teal)),
                        SizedBox(width: 12),
                        Text('ກຳລັງຄຳນວນເສັ້ນທາງ...',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          _buildLayerPanel(),

          // ── ปุ่มควบคุม ──
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'layer_toggle',
                  backgroundColor: _showLayerPanel ? Colors.teal : Colors.white,
                  foregroundColor: _showLayerPanel ? Colors.white : Colors.teal,
                  onPressed: () =>
                      setState(() => _showLayerPanel = !_showLayerPanel),
                  child: Icon(_currentLayer.icon),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.teal,
                  onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1),
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
