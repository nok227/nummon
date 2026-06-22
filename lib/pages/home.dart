import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place_model.dart';
import 'place_detail.dart';
import '../widgets/story.dart';

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
  String _searchQuery = "";
  bool _isSearchVisible = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => isLoading = false);
    });
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

  void _deletePlace(String id, String name) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ ຢືນຢັນການລົບ"),
        content: Text("ທ່ານຕ້ອງການລົບສະຖານທີ່ \"$name\" ແທ້ຫຼືບໍ່?"),
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

  void _openEditPlaceSheet(Place place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => EditPlaceSheet(place: place),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        controller: widget.scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Banner
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
                          IconButton(
                            icon: Icon(
                              _isSearchVisible ? Icons.close : Icons.search,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () {
                              setState(() {
                                _isSearchVisible = !_isSearchVisible;
                                if (!_isSearchVisible) _searchQuery = "";
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          // ═══ ใช้ StreamBuilder ดึงโปรไฟล์จริง ═══
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

                              // ถ้ายังไม่มีใน Firestore ให้ใช้จาก Auth
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
                                          // border: Border.all(color: Colors.red, width: 2), // ✅ เปลี่ยนเป็นสีแดง
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
                  const SizedBox(height: 25),
                  Text(
                    isAdmin ? "ສະບາຍດີ, Admin 🛠️" : "ສະບາຍດີ, ນັກທ່ອງທ່ຽວ 👋",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                        onChanged: (value) => setState(() => _searchQuery = value.trim()),
                        decoration: const InputDecoration(
                          hintText: "ຄົ້ນຫາສະຖານທີ່ ຫຼື ເມືອງ...",
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

            // Story Section
            const StorySection(),

            // Places Section
            const Padding(
              padding: EdgeInsets.only(left: 20, top: 24, bottom: 12),
              child: Text(
                "ສະຖານທີ່ຍອດນິຍົມ",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            if (isLoading)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 2,
                itemBuilder: (context, index) => Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(height: 240, color: Colors.white),
                  ),
                ),
              )
            else
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('places').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text("ບໍ່ມີຂໍ້ມູນສະຖານທີ່"),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  final filteredDocs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final district = (data['district'] ?? '').toString().toLowerCase();
                    final query = _searchQuery.toLowerCase();
                    return name.contains(query) || district.contains(query);
                  }).toList();

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

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final data = filteredDocs[index].data() as Map<String, dynamic>;
                      final place = Place(
                        id: filteredDocs[index].id,
                        name: data['name'] ?? '',
                        district: data['district'] ?? '',
                        description: data['description'] ?? '',
                        imageUrl: data['imageUrl'] ?? '',
                        imageUrls: (data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [],
                        latitude: double.tryParse(data['latitude'].toString()) ?? 0.0,
                        longitude: double.tryParse(data['longitude'].toString()) ?? 0.0,
                      );

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
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                    child: Image.network(
                                      place.imageUrl,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(
                                        height: 180,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image, size: 50),
                                      ),
                                    ),
                                  ),
                                  if ((place.imageUrls?.length ?? 0) > 1)
                                    Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.photo_library, color: Colors.white, size: 12),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${place.imageUrls!.length}',
                                              style: const TextStyle(color: Colors.white, fontSize: 11),
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
      onSelected: (value) => value == 'edit'
          ? _openEditPlaceSheet(place)
          : _deletePlace(place.id, place.name),
      itemBuilder: (context) => [

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
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      place.name,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on, size: 14, color: Colors.red),
                                        const SizedBox(width: 4),
                                        Text(
                                          place.district,
                                          style: const TextStyle(color: Colors.grey, fontSize: 13),
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
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─── EditPlaceSheet ─── (ไม่มีการเปลี่ยนแปลง)
class EditPlaceSheet extends StatefulWidget {
  final Place place;
  const EditPlaceSheet({super.key, required this.place});

  @override
  State<EditPlaceSheet> createState() => _EditPlaceSheetState();
}

class _EditPlaceSheetState extends State<EditPlaceSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _districtController;
  late TextEditingController _descController;
  late TextEditingController _imageUrlController;
  late TextEditingController _imageUrlsController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.place.name);
    _districtController = TextEditingController(text: widget.place.district);
    _descController = TextEditingController(text: widget.place.description);
    _imageUrlController = TextEditingController(text: widget.place.imageUrl);
    _imageUrlsController = TextEditingController(
      text: widget.place.imageUrls?.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _districtController.dispose();
    _descController.dispose();
    _imageUrlController.dispose();
    _imageUrlsController.dispose();
    super.dispose();
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      List<String> imageUrls = [];
      if (_imageUrlsController.text.trim().isNotEmpty) {
        imageUrls = _imageUrlsController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      await FirebaseFirestore.instance.collection('places').doc(widget.place.id).update({
        'name': _nameController.text.trim(),
        'district': _districtController.text.trim(),
        'description': _descController.text.trim(),
        'imageUrl': _imageUrlController.text.trim(),
        'imageUrls': imageUrls,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ອັບເດດຂໍ້ມູນສຳເລັດ!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ເກີດຂໍ້ຜິດພາດ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "🛠️ ແກ້ໄຂຂໍ້ມູນສະຖານທີ່",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "ຊື່ສະຖານທີ່"),
                validator: (v) => v!.isEmpty ? "ກະລຸນາປ້ອນຊື່" : null,
              ),
              TextFormField(
                controller: _districtController,
                decoration: const InputDecoration(labelText: "ເມືອງ / ແຂວງ"),
                validator: (v) => v!.isEmpty ? "ກະລຸນາປ້ອນເມືອງ" : null,
              ),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: "ລາຍລະອຽດ"),
                validator: (v) => v!.isEmpty ? "ກະລຸນາປ້ອນລາຍລະອຽດ" : null,
              ),
              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(labelText: "Link ຮູບພາບປົກ (URL)"),
                validator: (v) => v!.isEmpty ? "ກະລຸນາປ້ອນ URL" : null,
              ),
              TextFormField(
                controller: _imageUrlsController,
                decoration: const InputDecoration(
                  labelText: "ຮູບພາບທັງໝົດ (ແຍກດ້ວຍ ,)",
                  hintText: "https://... , https://...",
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: _saveData,
                      child: const Text("ບັນທຶກ"),
                    ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}