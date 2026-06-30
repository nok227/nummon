import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

// ── ປະເພດ Map Layer (ແຊ່ shared ກໍ່ໄດ້ ຫຼື copy ໄວ້ໃນໄຟລ໌ນີ້ກໍ່ໄດ້) ──
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

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static const ll.LatLng _initialPosition = ll.LatLng(19.2524, 101.7117);

  ll.LatLng _selectedLocation = _initialPosition;
  final MapController _mapController = MapController();

  MapLayerType _currentLayer = MapLayerType.normal;
  bool _showLayerPanel = false;

  Widget _buildLayerPanel() {
    return Positioned(
      right: 16,
      bottom: 160,
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
                              Icon(
                                layer.icon,
                                size: 20,
                                color: selected ? Colors.teal : Colors.black54,
                              ),
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
        title: const Text('ເລືອກພິກັດໃນແຜນທີ່',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 28),
            onPressed: () => Navigator.pop(context, _selectedLocation),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialPosition,
              initialZoom: 12,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedLocation = point;
                  if (_showLayerPanel) _showLayerPanel = false;
                });
              },
            ),
            children: [
              // ── Base Tile Layer ──
              TileLayer(
                urlTemplate: layer.tileUrl,
                userAgentPackageName: 'com.example.abc_new',
              ),

              // ── Overlay ສຳລັບ Hybrid ──
// ✅ ໃໝ່ — ໃຊ້ Opacity widget ຫຸ້ມ
              if (layer.overlayUrl != null)
                Opacity(
                  opacity: 0.55,
                  child: TileLayer(
                    urlTemplate: layer.overlayUrl!,
                    userAgentPackageName: 'com.example.abc_new',
                  ),
                ),

              // ── Marker ──
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation,
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Icon(Icons.location_pin,
                            color: Colors.red, size: 40),
                      ],
                    ),
                  ),
                ],
              ),

              RichAttributionWidget(
                attributions: [TextSourceAttribution(layer.attribution)],
              ),
            ],
          ),

          // ── ຄຳແນະນຳດ້ານເທິງ ──
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.teal),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ຈິ້ມເທິງແຜນທີ່ເພື່ອປັກໝຸດ ແລ້ວກົດ ✔️ ດ້ານເທິງຂວາເພື່ອບັນທຶກ',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── ສະແດງພິກັດ Real-time ──
          Positioned(
            bottom: 24,
            left: 16,
            right: 90,
            child: Card(
              color: Colors.teal[900],
              elevation: 6,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

          // ── Layer Panel ──
          _buildLayerPanel(),

          // ── ປຸ່ມ Layer Toggle ──
          Positioned(
            right: 16,
            bottom: 110,
            child: FloatingActionButton.small(
              heroTag: 'layer_toggle_picker',
              backgroundColor: _showLayerPanel ? Colors.teal : Colors.white,
              foregroundColor: _showLayerPanel ? Colors.white : Colors.teal,
              onPressed: () =>
                  setState(() => _showLayerPanel = !_showLayerPanel),
              child: Icon(_currentLayer.icon),
            ),
          ),
        ],
      ),
    );
  }
}
