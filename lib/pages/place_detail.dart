import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/place_model.dart';
import 'map.dart';

class PlaceDetailPage extends StatefulWidget {
  final Place place;
  final Function(Place) onAddToPlan;

  const PlaceDetailPage({
    super.key,
    required this.place,
    required this.onAddToPlan,
  });

  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  int _currentImageIndex = 0;

  List<String> get _allImages {
    final urls = widget.place.imageUrls;
    if (urls != null && urls.isNotEmpty) return urls;
    if (widget.place.imageUrl.isNotEmpty) return [widget.place.imageUrl];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final images = _allImages;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place.name),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // รูปหลัก
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Image.network(
                images.isNotEmpty ? images[_currentImageIndex] : '',
                key: ValueKey(_currentImageIndex),
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  height: 260,
                  child: Center(child: Icon(Icons.broken_image, size: 80)),
                ),
              ),
            ),

            // Thumbnail strip
            if (images.length > 1)
              Container(
                height: 78,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _currentImageIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _currentImageIndex = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.teal : Colors.grey.shade300,
                            width: isSelected ? 2.5 : 1.5,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: Colors.teal.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)]
                              : [],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                images[index],
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.grey),
                              ),
                              if (isSelected)
                                Container(color: Colors.teal.withOpacity(0.15)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ข้อมูลสถานที่
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.place.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 20),
                      const SizedBox(width: 4),
                      Text(widget.place.district,
                          style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("ລາຍລະອຽດ",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(widget.place.description ?? "ບໍ່ມີລາຍລະອຽດສະຖານທີ່ໃນຕອນນີ້"),
                  const SizedBox(height: 24),

                  // ── แผนที่แสดงตำแหน่ง (ใช้ FlutterMap) ──
                  const Text("ຕຳແໜ່ງສະຖານທີ່",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapPage(
                            latitude: widget.place.latitude,
                            longitude: widget.place.longitude,
                            placeName: widget.place.name,
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: AbsorbPointer(
                          absorbing: true, // ปิดการโต้ตอบ
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: ll.LatLng(
                                  widget.place.latitude, widget.place.longitude),
                              initialZoom: 14,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none, // ปิดทุกการโต้ตอบ
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.abc_new',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: ll.LatLng(
                                        widget.place.latitude, widget.place.longitude),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.location_pin,
                                        color: Colors.red, size: 40),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      widget.onAddToPlan(widget.place);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("ເພີ່ມເຂົ້າໃນແຜນ"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}