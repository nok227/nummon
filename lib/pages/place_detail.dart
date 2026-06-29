import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_model.dart';
import '../routes/map.dart';
import '../admin/admin_add_place.dart';

class PlaceDetailPage extends StatefulWidget {
  // รับแค่ placeId แล้วฟัง stream เองเพื่อ realtime update
  final String placeId;
  final Function(Place) onAddToPlan;

  const PlaceDetailPage({
    super.key,
    required this.placeId,
    required this.onAddToPlan,
  });

  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  int _currentImageIndex = 0;
  late PageController _pageController;

  // Stream จาก Firestore เพื่อรับข้อมูลใหม่ทันที
  late final Stream<DocumentSnapshot> _placeStream;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _placeStream = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.placeId)
        .snapshots();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onThumbnailTap(int index) {
    setState(() => _currentImageIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _openFullscreenImageViewer(int initialIndex, List<String> images) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenImageViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  // เปิดหน้า Admin Edit — StreamBuilder จะ rebuild อัตโนมัติเมื่อ Firestore อัปเดต
  void _openEditPage(Place place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminAddPlacePage(
          scrollController: ScrollController(),
          editPlace: place,
        ),
      ),
    );
  }

  List<String> _getAllImages(Place place) {
    final urls = place.imageUrls;
    if (urls != null && urls.isNotEmpty) return urls;
    if (place.imageUrl.isNotEmpty) return [place.imageUrl];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _placeStream,
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.teal),
            ),
          );
        }

        // Error or deleted
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              title: const Text('ບໍ່ພົບຂໍ້ມູນ'),
            ),
            body: const Center(
                child: Text('ສະຖານທີ່ຖືກລົບແລ້ວ ຫຼືບໍ່ພົບຂໍ້ມູນ')),
          );
        }

        // ສ້າງ Place ຈາກ snapshot ທຸກຄັ້ງທີ່ Firestore ອັບເດດ
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final place = Place.fromMap(widget.placeId, data);
        final images = _getAllImages(place);

        // Reset page index ถ้าจำนวนรูปลดลง
        if (_currentImageIndex >= images.length && images.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _currentImageIndex = 0);
              _pageController.jumpToPage(0);
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(place.name),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'edit') _openEditPage(place);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Colors.teal, size: 20),
                        SizedBox(width: 10),
                        Text('ແກ້ໄຂຂໍ້ມູນ'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Image slideshow ──────────────────────────────────────
                Stack(
                  children: [
                    SizedBox(
                      height: 260,
                      child: images.isNotEmpty
                          ? PageView.builder(
                              controller: _pageController,
                              itemCount: images.length,
                              onPageChanged: (index) =>
                                  setState(() => _currentImageIndex = index),
                              itemBuilder: (context, index) {
                                final isFirstImage = index == 0 &&
                                    images[index] == place.imageUrl;
                                return GestureDetector(
                                  onTap: () => _openFullscreenImageViewer(
                                      index, images),
                                  child: Image.network(
                                    images[index],
                                    width: double.infinity,
                                    height: 260,
                                    fit: BoxFit.cover,
                                    alignment: isFirstImage
                                        ? Alignment(0, place.imageAlignmentY)
                                        : Alignment.center,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const SizedBox(
                                      height: 260,
                                      child: Center(
                                          child: Icon(Icons.broken_image,
                                              size: 80)),
                                    ),
                                  ),
                                );
                              },
                            )
                          : const SizedBox(
                              height: 260,
                              child: Center(
                                  child: Icon(Icons.broken_image, size: 80)),
                            ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            "${_currentImageIndex + 1} / ${images.length}",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),

                // ── Thumbnails ────────────────────────────────────────────
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
                          onTap: () => _onThumbnailTap(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 72,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.teal
                                    : Colors.grey.shade300,
                                width: isSelected ? 2.5 : 1.5,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                          color: Colors.teal.withOpacity(0.3),
                                          blurRadius: 4,
                                          spreadRadius: 1)
                                    ]
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
                                    errorBuilder: (c, e, s) => const Icon(
                                        Icons.broken_image,
                                        color: Colors.grey),
                                  ),
                                  if (isSelected)
                                    Container(
                                        color: Colors.teal.withOpacity(0.15)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // ── Info ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 4),
                          Text(place.district,
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text("ລາຍລະອຽດ",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(place.description),
                      const SizedBox(height: 24),

                      // ── ແຜນທີ່ preview ──────────────────────────────────
                      const Text("ຕຳແໜ່ງສະຖານທີ່",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MapPage(
                                latitude: place.latitude,
                                longitude: place.longitude,
                                placeName: place.name,
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
                              absorbing: true,
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: ll.LatLng(
                                      place.latitude, place.longitude),
                                  initialZoom: 14,
                                  interactionOptions:
                                      const InteractionOptions(
                                    flags: InteractiveFlag.none,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'com.example.abc_new',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: ll.LatLng(
                                            place.latitude, place.longitude),
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

                      // ── ຈຸດທ່ອງທ່ຽວຍ່ອຍ ─────────────────────────────────
                      if (place.extraPlaces != null &&
                          place.extraPlaces!.isNotEmpty) ...[
                        const Text("ຂໍ້ມູນອື່ນໆ",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: place.extraPlaces!.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final extra = place.extraPlaces![index];
                            final extraImages = extra.allImages;
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MapPage(
                                      latitude: extra.latitude,
                                      longitude: extra.longitude,
                                      placeName: extra.name,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                              left: Radius.circular(12)),
                                      child: extraImages.isNotEmpty
                                          ? Image.network(
                                              extraImages.first,
                                              width: 90,
                                              height: 90,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) =>
                                                  Container(
                                                    width: 90,
                                                    height: 90,
                                                    color: Colors.grey.shade200,
                                                    child: const Icon(
                                                        Icons.broken_image,
                                                        color: Colors.grey),
                                                  ),
                                            )
                                          : Container(
                                              width: 90,
                                              height: 90,
                                              color: Colors.grey.shade200,
                                              child: const Icon(
                                                  Icons.image_not_supported,
                                                  color: Colors.grey),
                                            ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(extra.name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15)),
                                            const SizedBox(height: 4),
                                            if (extra.description.isNotEmpty)
                                              Text(
                                                extra.description,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey),
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: const [
                                                Icon(Icons.directions,
                                                    color: Colors.teal,
                                                    size: 16),
                                                SizedBox(width: 4),
                                                Text('ນຳທາງໄປຈຸດນີ້',
                                                    style: TextStyle(
                                                        color: Colors.teal,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── ປຸ່ມເພີ່ມເຂົ້າແຜນ ────────────────────────────────
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: () {
                          widget.onAddToPlan(place);
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
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Fullscreen Image Viewer
// ────────────────────────────────────────────────────────────────────────────
class FullscreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullscreenImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Center(
                  child: Image.network(
                    widget.images[index],
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${_currentIndex + 1} / ${widget.images.length}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}