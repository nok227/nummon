import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http; 
import 'dart:convert';
import '../models/place_model.dart';
import 'place_detail.dart';
import '../widgets/story.dart';
import '../models/api_Cloudinary.dart'; 

class HomePage extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onMenuPressed;
  final Function(Place) onAddToPlan;
  final VoidCallback onProfilePressed;

  const HomePage({
    super.key,
    required this.scrollController,
    required this.onMenuPressed,
    required this.onAddToPlan,
    required this.onProfilePressed,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool isLoading = true;
  bool isAdmin = false;
  bool _isClearingAll = false;
  bool _isSearchVisible = false;

  // ── Search ──────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");

  // ── Firestore stream ────────────────────────────────────────────────────────
  late final Stream<QuerySnapshot> _placesStream;

  // ── Pagination (Facebook-style) ────────────────────────────────────────────
  static const int _pageSize = 8;                 
  final List<QueryDocumentSnapshot> _docs = [];   
  DocumentSnapshot? _lastDoc;                      
  bool _hasMore = true;                            
  bool _isFetchingMore = false;                    

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();

    _placesStream = FirebaseFirestore.instance
        .collection('places')
        .orderBy('name')
        .snapshots();

    _loadFirstPage();

    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  // ── Pagination helpers ─────────────────────────────────────────────────────

  Future<void> _loadFirstPage() async {
    if (mounted) setState(() => isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('places')
          .orderBy('name')
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      setState(() {
        _docs
          ..clear()
          ..addAll(snap.docs);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == _pageSize;
        isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isFetchingMore || _lastDoc == null) return;
    setState(() => _isFetchingMore = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('places')
          .orderBy('name')
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
        _hasMore = snap.docs.length == _pageSize;
        _isFetchingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }

  void _onScroll() {
    final ctrl = widget.scrollController;
    if (ctrl.position.pixels >= ctrl.position.maxScrollExtent * 0.9) {
      _loadNextPage();
    }
  }

  void _checkAdminStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && (user.email == 'admin_app@travel.com' || user.email == 'admin_app')) {
      setState(() => isAdmin = true);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _clearAllDataAndImages() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🚨 คຳເຕືອນอันตະລาย 🚨"),
        content: const Text("ທ່ານຕ້ອງການລົບສະຖານທີ່ທັງໝົດ ແລະ ຮູບພາບທັງໝົດໃນ Cloudinary ແທ้ຫຼືບໍ່? ຂໍ້ມູນຈະຫາຍໄປຕະຫຼອດການ!"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ຍົກເລີກ"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); 
              setState(() => _isClearingAll = true); 
              
              try {
                final querySnapshot = await FirebaseFirestore.instance.collection('places').get();
                
                for (var doc in querySnapshot.docs) {
                  final data = doc.data();
                  List<String> urlsToDelete = [];
                  
                  if (data['imageUrl'] != null) urlsToDelete.add(data['imageUrl']);
                  if (data['imageUrls'] != null) {
                    urlsToDelete.addAll((data['imageUrls'] as List).map((e) => e.toString()));
                  }

                  for (String url in urlsToDelete) {
                    await _deleteFromCloudinary(url);
                  }
                  
                  await FirebaseFirestore.instance.collection('places').doc(doc.id).delete();
                }

                _showSnackBar("ລ້າງຂໍ້ມູນທັງໝົດສຳເລັດແລ້ວ!", isError: false);
              } catch (e) {
                _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e", isError: true);
              } finally {
                setState(() => _isClearingAll = false); 
              }
            },
            child: const Text("ຢືນຢັນການລົບທັງໝົດ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromCloudinary(String url) async {
    try {
      if (!url.contains("cloudinary.com")) return;
      
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isEmpty) return;

      final lastSegment = segments.last; 
      final publicId = lastSegment.split('.').first; 

      String cloudName = CloudinaryConfig.cloudName; 
      String apiKey = CloudinaryConfig.apiKey;
      String apiSecret = CloudinaryConfig.apiSecret; 

      final String basicAuth = 'Basic ${base64Encode(utf8.encode('$apiKey:$apiSecret'))}';

      final response = await http.post(
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/destroy'),
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'public_id': publicId,
        },
      );

      if (response.statusCode != 200) {
        print("Failed to delete image from Cloudinary: ${response.body}");
      }
    } catch (e) {
      print("Cloudinary delete error: $e");
    }
  }

  void _deletePlace(String id, String name) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ ຢືນຢັນການລົບ"),
        content: Text("ທ່ານຕ້ອງການລົບສະຖານທີ່ \"$name\" ແທ้ຫຼືບໍ່?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('places').doc(id).delete();
              _showSnackBar("ລົບ \"$name\" ສຳເລັດ", isError: false);
            },
            child: const Text("ລົບຂໍ້ມູນ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openArrangeImagesSheet(Place place) {
    final List<String> images = List.from(place.imageUrls ?? []);
    if (images.isEmpty && place.imageUrl.isNotEmpty) {
      images.add(place.imageUrl);
    }
    double currentAlignmentY = place.imageAlignmentY;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "↕️ ຈັດຕຳແໜ່ງ ແລະ ເລື່ອນພາບປົກ",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 12),
                    const Text("ຕົວຢ່າງການສະແດງຜົນພາບປົก (Crop ຕຳແໜ່ງ):", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Center(
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            place.imageUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment(0, currentAlignmentY),
                            errorBuilder: (c, e, s) => Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text("🔝 ເທິງ", style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: currentAlignmentY,
                            min: -1.0,
                            max: 1.0,
                            activeColor: Colors.teal,
                            onChanged: (val) {
                              setModalState(() {
                                currentAlignmentY = val;
                              });
                            },
                          ),
                        ),
                        const Text("🔙 ລຸ່ມ", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const Divider(),
                    const Text(
                      "🔄 ຈັດລຽງລໍາດັບຮູບພາບ (ຍ້າຍຂຶ້ນ/ລົງ)",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    images.isEmpty
                        ? const Center(child: Text("ບໍ່ມີຮູບພາບໃຫ້ຈັດຕຳແໜ່ງ"))
                        : Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: images.length,
                              itemBuilder: (context, index) {
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(images[index], width: 50, height: 50, fit: BoxFit.cover),
                                    ),
                                    title: Text("ຮູບພາບທີ ${index + 1}"),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (index > 0)
                                          IconButton(
                                            icon: const Icon(Icons.arrow_upward, color: Colors.teal),
                                            onPressed: () {
                                              setModalState(() {
                                                final temp = images[index];
                                                images[index] = images[index - 1];
                                                images[index - 1] = temp;
                                              });
                                            },
                                          ),
                                        if (index < images.length - 1)
                                          IconButton(
                                            icon: const Icon(Icons.arrow_downward, color: Colors.teal),
                                            onPressed: () {
                                              setModalState(() {
                                                final temp = images[index];
                                                images[index] = images[index + 1];
                                                images[index + 1] = temp;
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          await FirebaseFirestore.instance
                              .collection('places')
                              .doc(place.id)
                              .update({
                            'imageUrls': images,
                            'imageAlignmentY': currentAlignmentY,
                            if (images.isNotEmpty) 'imageUrl': images.first
                          });
                          _showSnackBar("ຈັດຮຽງຕຳແໜ່ງຮູບພາບ ແລະ ຕຳແໜ່ງເລື່ອນພາບສຳເລັດແລ້ວ!");
                        } catch (e) {
                          _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e", isError: true);
                        }
                      },
                      child: const Text("ບັນທຶກຕຳແໜ່ງໃໝ່"),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openSelectCoverSheet(Place place) {
    final List<String> images = place.imageUrls ?? [];
    if (images.isEmpty && place.imageUrl.isNotEmpty) {
      images.add(place.imageUrl);
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "📸 ເለືອກຮູບພາບປົກໃຫມ່",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
              ),
              const SizedBox(height: 12),
              images.isEmpty
                  ? const Center(child: Text("ບໍ່ມີຮູບພາບໃຫ້ເລືອກ"))
                  : SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          final isCurrentCover = images[index] == place.imageUrl;
                          return GestureDetector(
                            onTap: () async {
                              Navigator.pop(context);
                              try {
                                await FirebaseFirestore.instance
                                    .collection('places')
                                    .doc(place.id)
                                    .update({'imageUrl': images[index]});
                                _showSnackBar("ป່ຽນຮູບພາບປົກສຳເລັດແລ້ວ!");
                              } catch (e) {
                                _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e", isError: true);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 120,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCurrentCover ? Colors.teal : Colors.grey.shade300,
                                  width: isCurrentCover ? 3 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(images[index], fit: BoxFit.cover),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[200], 
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: widget.scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 30),
                  decoration: const BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.vertical(bottom: Radius.circular(32))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                            onPressed: widget.onMenuPressed,
                          ),
                          Row(
                            children: [
                              if (isAdmin)
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz, color: Colors.white, size: 28),
                                  tooltip: "ເມນູຈັດການ",
                                  onSelected: (value) {
                                    if (value == 'clear_all') {
                                      _clearAllDataAndImages();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'clear_all',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_forever, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('ລ້າງຂໍ້ມູນທັງໝົດ'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              if (isAdmin) const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(
                                  _isSearchVisible ? Icons.close : Icons.search,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isSearchVisible = !_isSearchVisible;
                                    if (!_isSearchVisible) {
                                      _searchController.clear(); 
                                      _searchQueryNotifier.value = ""; 
                                    }
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              StreamBuilder<DocumentSnapshot>(
                                stream: currentUser != null
                                    ? FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(currentUser.uid)
                                        .snapshots()
                                    : const Stream.empty(),
                                builder: (context, snapshot) {
                                  String photoUrl = '';
                                  String displayName = '';

                                  if (snapshot.hasData && snapshot.data!.exists) {
                                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                                    photoUrl = data?['photoURL'] ?? '';
                                    displayName = data?['displayName'] ?? '';
                                  }

                                  if (photoUrl.isEmpty && currentUser != null) {
                                    photoUrl = currentUser.photoURL ?? '';
                                  }
                                  if (displayName.isEmpty && currentUser != null) {
                                    displayName = currentUser.displayName ?? currentUser.email ?? '';
                                  }

                                  return GestureDetector(
                                    onTap: widget.onProfilePressed,
                                    child: Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundImage: photoUrl.isNotEmpty
                                              ? NetworkImage(photoUrl)
                                              : const AssetImage('assets/default.jpg') as ImageProvider,
                                          child: photoUrl.isEmpty
                                              ? const Icon(Icons.person, color: Colors.grey)
                                              : null,
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: const BoxDecoration(
                                              color: Colors.greenAccent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "ຊອກຫາສະຖານທີ່ໃໝ່ໆ",
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      if (_isSearchVisible) ...[
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
                          ),
                          child: TextField(
                            controller: _searchController, 
                            onChanged: (value) => _searchQueryNotifier.value = value.trim(),
                            decoration: const InputDecoration(
                              hintText: "ຄົ້ນຫາສະຖານທີ່ ຫຼື ຈຸດທ່ອງທ່ຽວຍ່ອຍ...",
                              prefixIcon: Icon(Icons.search, color: Colors.teal),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const StorySection(),

                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 20, bottom: 8),
                  child: Text(
                    "ສະຖານທີ່ຍອດນິຍົມ",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                
                if (isLoading)
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 3,
                    itemBuilder: (context, index) => Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10), 
                        elevation: 0,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Container(color: Colors.white),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(height: 16, width: 200, color: Colors.white),
                                  const SizedBox(height: 8),
                                  Container(height: 12, width: 120, color: Colors.white),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ValueListenableBuilder<String>(
                    valueListenable: _searchQueryNotifier,
                    builder: (context, searchQuery, _) {
                      final filteredDocs = _docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = (data['name'] ?? '').toString().toLowerCase();
                        final district = (data['district'] ?? '').toString().toLowerCase();
                        final q = searchQuery.toLowerCase();
                        return name.contains(q) || district.contains(q);
                      }).toList();

                      if (_docs.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text("ບໍ່ມີຂໍ້ມູນສະຖານທີ່"),
                          ),
                        );
                      }

                      if (filteredDocs.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              "ບໍ່ພົບສະຖານທີ່ທີ່ທ່ານຄົ້ນຫາ",
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredDocs.length + (_hasMore && searchQuery.isEmpty ? 1 : 0),
                            itemBuilder: (context, index) {
                              
                              if (index == filteredDocs.length) {
                                return Shimmer.fromColors(
                                  baseColor: Colors.grey[300]!,
                                  highlightColor: Colors.grey[100]!,
                                  child: Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Container(color: Colors.white),
                                    ),
                                  ),
                                );
                              }

                              final data = filteredDocs[index].data() as Map<String, dynamic>;
                              final place = Place.fromMap(filteredDocs[index].id, data);

                              return GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PlaceDetailPage(
                                      place: place,
                                      onAddToPlan: widget.onAddToPlan,
                                    ),
                                  ),
                                ),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 10), 
                                  elevation: 0.5, 
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), 
                                  color: Colors.white,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Stack(
                                        children: [
                                          AspectRatio(
                                            aspectRatio: 16 / 9,
                                            child: Image.network(
                                              place.imageUrl,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              alignment: Alignment(0, place.imageAlignmentY),
                                              cacheWidth: 1000, 
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) return child;
                                                return Shimmer.fromColors(
                                                  baseColor: Colors.grey[300]!,
                                                  highlightColor: Colors.grey[100]!,
                                                  child: Container(color: Colors.white),
                                                );
                                              },
                                              errorBuilder: (c, e, s) => Container(
                                                color: Colors.grey[300],
                                                child: const Icon(Icons.image, size: 50),
                                              ),
                                            ),
                                          ),
                                          if ((place.imageUrls?.length ?? 0) > 1)
                                            Positioned(
                                              bottom: 12,
                                              right: 12,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: Colors.black,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.photo_library, color: Colors.white, size: 14),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      '${place.imageUrls!.length}',
                                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          if (isAdmin)
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: PopupMenuButton<String>(
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                  color: Colors.white,
                                                  size: 28,
                                                  shadows: [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
                                                ),
                                                onSelected: (value) {
                                                  if (value == 'arrange_images') {
                                                    _openArrangeImagesSheet(place);
                                                  } else if (value == 'set_cover') {
                                                    _openSelectCoverSheet(place);
                                                  } else {
                                                    _deletePlace(place.id, place.name);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  const PopupMenuItem(
                                                    value: 'arrange_images',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.swap_vert, color: Colors.teal),
                                                        SizedBox(width: 8),
                                                        Text('ຈັດຕຳແໜ່ງຮູບພາບ'),
                                                      ],
                                                    ),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'set_cover',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.add_photo_alternate, color: Colors.blue),
                                                        SizedBox(width: 8),
                                                        Text('ຕັ້ງເປັນຮູບໜ້າປົກ'),
                                                      ],
                                                    ),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete, color: Colors.red),
                                                        SizedBox(width: 8),
                                                        Text('ລົບ', style: TextStyle(color: Colors.red)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              place.name,
                                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on, size: 15, color: Colors.redAccent),
                                                const SizedBox(width: 4),
                                                Text(
                                                  place.district,
                                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),   
                        ],
                      );    
                    },
                  ),   
              ],
            ),
          ),
          if (_isClearingAll)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.teal),
                    SizedBox(height: 16),
                    Text(
                      "ກຳລັງລົບຂໍ້ມູນທັງໝົດ...",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}