import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'edit_profile_page.dart';
import 'add_highlight_page.dart';
import '../routes/map.dart';
import '../auth/login_screen.dart'; // 🔹 import หน้า Login

class ProfilePage extends StatefulWidget {
  final String? targetUserId;
  const ProfilePage({super.key, this.targetUserId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? user;
  Map<String, dynamic>? userData;
  List<dynamic> highlights = [];
  bool _isUploading = false;
  final TextEditingController _editContentController = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _userSubscription;

  String? targetId;
  bool isMe = true;

  @override
  void initState() {
    super.initState();
    _listenToUserData();
  }

  void _listenToUserData() {
    user = FirebaseAuth.instance.currentUser;
    targetId = widget.targetUserId ?? user?.uid;
    isMe = (user?.uid == targetId);

    if (targetId != null) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(targetId)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          setState(() {
            userData = doc.data();
            print('📦 ProfilePage userData keys: ${userData?.keys}');
            highlights = userData?['highlights'] ?? [];
          });
        } else if (mounted) {
          setState(() {
            userData = {};
            highlights = [];
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _editContentController.dispose();
    super.dispose();
  }

  void _showImagePreview(String imageUrl, {String? title}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: MediaQuery.of(context).size.width * 0.95,
                  height: MediaQuery.of(context).size.height * 0.8,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                  errorBuilder: (c, e, s) => Container(
                    width: 200,
                    height: 200,
                    color: Colors.grey[800],
                    child: const Icon(Icons.broken_image, color: Colors.white, size: 50),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(String postId, List<String> likedBy, int currentLikes) async {
    final uid = user?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('user_posts').doc(postId);
    if (likedBy.contains(uid)) {
      await docRef.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([uid]),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([uid]),
      });
    }
  }

  void _editPost(Map<String, dynamic> postData) {
    _editContentController.text = postData['content'] ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("ແກ້ໄຂໂພສຕ໌", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _editContentController,
              maxLines: 4,
              decoration: const InputDecoration(hintText: "ແກ້ໄຂຂໍ້ຄວາມ...", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final newContent = _editContentController.text.trim();
                if (newContent.isNotEmpty) {
                  await FirebaseFirestore.instance.collection('user_posts').doc(postData['id']).update({
                    'content': newContent,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("ອັບເດດໂພສຕ໌ສຳເລັດ"), backgroundColor: Colors.green),
                    );
                  }
                }
              },
              child: const Text("ບັນທຶກ"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePost(String postId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ລົບໂພສຕ໌?"),
        content: const Text("ທ່ານຕ້ອງການລົບໂພສຕ໌ນີ້ແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('user_posts').doc(postId).delete();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("ລົບໂພສຕ໌ແລ້ວ"), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text("ລົບ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteHighlight(Map<String, dynamic> highlightData) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ລົບໄຮໄລທ໌?"),
        content: const Text("ທ່ານຕ້ອງການລົບໄຮໄລທ໌ນີ້ແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (targetId != null) {
                await FirebaseFirestore.instance.collection('users').doc(targetId).update({
                  'highlights': FieldValue.arrayRemove([highlightData]),
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("ລົບໄຮໄລທ໌ສຳເລັດ"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("ລົບ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 🔧 ฟังก์ชัน Logout ที่ปรับปรุงให้เคลียร์ Google และนำทางไปหน้า Login
  void _logout() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ອອກຈາກລະບົບ"),
        content: const Text("ທ່ານຕ້ອງການອອກຈາກລະບົບແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ຍົກເລີກ"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ຢືນຢັນ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    if (mounted) Navigator.pop(context);

    try {
      // 1. Sign out from Google (ถ้าใช้)
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }

      // 2. Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      // 3. นำทางไปหน้า Login และล้าง Stack ทั้งหมด
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ອອກຈາກລະບົບສຳເລັດ"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Logout error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ເກີດຂໍ້ຜິດພາດ: ${e.toString()}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ✅ รองรับทั้ง photoUrl และ photoURL
    final photoUrl = userData!['photoUrl'] ??
        userData!['photoURL'] ??
        'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=300';

    // ✅ รองรับทั้ง coverUrl และ coverURL
    final coverUrl = userData!['coverUrl'] ??
        userData!['coverURL'] ??
        'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600';

    final displayName = userData!['displayName'] ?? 'User';
    final bio = userData!['bio'] ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("ໂພຣໄຟລ໌"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (isMe)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EditProfilePage()),
              ),
              tooltip: "ແກ້ໄຂໂພຣໄຟລ໌",
            ),
          if (isMe)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: "ອອກຈາກລະບົບ",
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ─── Cover + Profile Photo ───
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _showImagePreview(coverUrl, title: "ຮູບພື້ນຫຼັງ"),
                        onLongPress: isMe
                            ? () {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilePage()));
                              }
                            : null,
                        child: Stack(
                          children: [
                            Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                image: coverUrl.isNotEmpty ? DecorationImage(image: NetworkImage(coverUrl), fit: BoxFit.cover) : null,
                                color: Colors.grey[300],
                              ),
                              child: coverUrl.isEmpty ? const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey) : null,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: -50,
                        child: GestureDetector(
                          onTap: () => _showImagePreview(photoUrl, title: "ຮູບໂພຣໄຟລ໌"),
                          onLongPress: isMe
                              ? () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilePage()));
                                }
                              : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 54,
                                backgroundColor: Colors.white,
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                  child: photoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                                ),
                              ),
                              if (_isUploading) Positioned.fill(child: const Center(child: CircularProgressIndicator(color: Colors.teal))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),

                  // ─── User Info ───
                  Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (bio.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(bio, style: const TextStyle(color: Colors.grey))),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ─── Highlights ───
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("ໄຮໄລທ໌", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (isMe)
                          IconButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const AddHighlightPage()),
                            ),
                            icon: const Icon(Icons.add_box),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: highlights.length,
                      itemBuilder: (context, index) {
                        final h = Map<String, dynamic>.from(highlights[index]);
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => HighlightViewerPage(highlight: h)),
                            );
                          },
                          child: Container(
                            width: 80,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(color: Colors.grey[300]!, width: 2),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(h['coverImage'] ?? '', fit: BoxFit.cover),
                                    Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.black54, Colors.transparent],
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.center,
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          h['title'] ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    if (isMe)
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onSelected: (value) {
                                            if (value == 'delete') {
                                              _deleteHighlight(h);
                                            }
                                          },
                                          itemBuilder: (BuildContext context) => [
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete, color: Colors.red, size: 16),
                                                  SizedBox(width: 8),
                                                  Text('ລົບໄຮໄລທ໌', style: TextStyle(color: Colors.red, fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ─── ສະຖານທີ່ໆທ່ຽວແລ້ວ ───
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text("✅ ສະຖານທີ່ໆທ່ຽວແລ້ວ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                  ),
                  if (targetId != null)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(targetId)
                          .collection('plans')
                          .where('status', isEqualTo: 'completed')
                          .orderBy('addedAt', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text("ຍັງບໍ່ມີສະຖານທີ່ໆທ່ຽວແລ້ວ", style: TextStyle(color: Colors.grey)),
                          );
                        }
                        final completedPlaces = snapshot.data!.docs;
                        return SizedBox(
                          height: 130,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: completedPlaces.length,
                            itemBuilder: (context, index) {
                              final data = completedPlaces[index].data() as Map<String, dynamic>;
                              final imageUrl = data['imageUrl'] ?? '';
                              final placeName = data['placeName'] ?? '';

                              double? pLat;
                              double? pLng;
                              if (data['location'] is GeoPoint) {
                                pLat = (data['location'] as GeoPoint).latitude;
                                pLng = (data['location'] as GeoPoint).longitude;
                              } else {
                                var latVal = data['latitude'] ?? data['lat'];
                                var lngVal = data['longitude'] ?? data['lng'];
                                if (latVal != null) pLat = double.tryParse(latVal.toString());
                                if (lngVal != null) pLng = double.tryParse(lngVal.toString());
                              }

                              return InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MapPage(
                                        latitude: pLat,
                                        longitude: pLng,
                                        placeName: placeName,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 10),
                                  child: Column(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: imageUrl.isNotEmpty
                                            ? Image.network(
                                                imageUrl,
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) => Container(
                                                  width: 100,
                                                  height: 100,
                                                  color: Colors.grey[300],
                                                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                                ),
                                              )
                                            : Container(
                                                width: 100,
                                                height: 100,
                                                color: Colors.grey[300],
                                                child: const Icon(Icons.place, color: Colors.orange, size: 36),
                                              ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        placeName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ─── โพสต์ที่แชร์ ───
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: const Text("ໂພສຕ໌ທີ່ແຊຣ໌", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (targetId != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('user_posts')
                    .where('userId', isEqualTo: targetId)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      color: Colors.white,
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      child: const Center(child: Text("ຍັງບໍ່ມີໂພສຕ໌", style: TextStyle(color: Colors.grey))),
                    );
                  }

                  final posts = snapshot.data!.docs;
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final data = posts[index].data() as Map<String, dynamic>;
                      final postId = posts[index].id;

                      data['id'] = postId;

                      final title = data['title'] ?? '';
                      final content = data['content'] ?? '';
                      final placeName = data['placeName'] ?? data['locationName'] ?? '';
                      final images = (data['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
                      final likedBy = List<String>.from(data['likedBy'] ?? []);
                      final likes = data['likes'] ?? 0;
                      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                      final isMine = data['userId'] == user?.uid;

                      double? postLat;
                      double? postLng;
                      if (data['location'] is GeoPoint) {
                        postLat = (data['location'] as GeoPoint).latitude;
                        postLng = (data['location'] as GeoPoint).longitude;
                      } else {
                        var latVal = data['latitude'] ?? data['lat'];
                        var lngVal = data['longitude'] ?? data['lng'];
                        if (latVal != null) postLat = double.tryParse(latVal.toString());
                        if (lngVal != null) postLng = double.tryParse(lngVal.toString());
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                    child: photoUrl.isEmpty ? const Icon(Icons.person) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (createdAt != null) ...[
                                              Text(_formatTimeAgo(createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              const SizedBox(width: 4),
                                              Icon(Icons.public, size: 12, color: Colors.grey[600]),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isMine)
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_horiz, color: Colors.grey[600]),
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _editPost(data);
                                        } else if (value == 'delete') {
                                          _deletePost(postId);
                                        }
                                      },
                                      itemBuilder: (BuildContext context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit, color: Colors.blue, size: 20),
                                              SizedBox(width: 8),
                                              Text('ແກ້ໄຂໂພສຕ໌'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.red, size: 20),
                                              SizedBox(width: 8),
                                              Text('ລົບໂພສຕ໌', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),

                            if (placeName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MapPage(
                                          latitude: postLat,
                                          longitude: postLng,
                                          placeName: placeName,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "📍 $placeName",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.teal,
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),

                            if (title.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),

                            if (content.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                child: Text(content, style: const TextStyle(fontSize: 15, height: 1.3)),
                              ),

                            if (images.isNotEmpty)
                              Container(
                                height: 260,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: images.length,
                                  itemBuilder: (context, i) {
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => PostImageViewerPage(
                                              images: images,
                                              initialIndex: i,
                                              title: placeName.isNotEmpty ? placeName : displayName,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.network(
                                            images[i],
                                            width: images.length == 1 ? MediaQuery.of(context).size.width - 24 : 280,
                                            height: 260,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  if (likes > 0) ...[
                                    const Icon(Icons.favorite, size: 16, color: Colors.red),
                                    const SizedBox(width: 4),
                                    Text('$likes', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                  ] else ...[
                                    Text('0 ຖືກໃຈ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),

                            const Divider(height: 1, thickness: 0.5),

                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _toggleLike(postId, likedBy, likes),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            user != null && likedBy.contains(user!.uid) ? Icons.favorite : Icons.favorite_border,
                                            color: user != null && likedBy.contains(user!.uid) ? Colors.red : Colors.grey[600],
                                            size: 22,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'ຖືກໃຈ',
                                            style: TextStyle(
                                              color: user != null && likedBy.contains(user!.uid) ? Colors.red : Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }
}

class PostImageViewerPage extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String title;

  const PostImageViewerPage({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<PostImageViewerPage> createState() => _PostImageViewerPageState();
}

class _PostImageViewerPageState extends State<PostImageViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.images.length > 1
              ? "${widget.title} (${_currentIndex + 1}/${widget.images.length})"
              : widget.title,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                widget.images[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HighlightViewerPage extends StatefulWidget {
  final Map<String, dynamic> highlight;
  const HighlightViewerPage({super.key, required this.highlight});

  @override
  State<HighlightViewerPage> createState() => _HighlightViewerPageState();
}

class _HighlightViewerPageState extends State<HighlightViewerPage> {
  int currentIndex = 0;
  late List<String> images;

  @override
  void initState() {
    super.initState();
    images = List<String>.from(widget.highlight['images'] ?? []);
    if (images.isEmpty && widget.highlight['coverImage'] != null) {
      images = [widget.highlight['coverImage']];
    }
  }

  void _next() {
    if (currentIndex < images.length - 1) {
      setState(() => currentIndex++);
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (currentIndex > 0) {
      setState(() => currentIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTapUp: (details) {
                final width = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < width * 0.3) {
                  _prev();
                } else {
                  _next();
                }
              },
              child: Center(
                child: Image.network(
                  images[currentIndex],
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (c, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                children: [
                  Row(
                    children: List.generate(images.length, (index) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          decoration: BoxDecoration(
                            color: index <= currentIndex ? Colors.white : Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          widget.highlight['title'] ?? 'Highlight',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                        onPressed: () => Navigator.pop(context),
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
  }
}