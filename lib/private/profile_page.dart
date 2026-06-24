import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'edit_profile_page.dart';
import 'add_highlight_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? user;
  Map<String, dynamic>? userData;
  List<dynamic> highlights = [];
  bool _isUploading = false;
  final TextEditingController _editContentController = TextEditingController();
  
  // ตัวดักฟังข้อมูลผู้ใช้งานแบบ Real-time
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _listenToUserData();
  }

  // ดึงข้อมูลผู้ใช้แบบ Real-time เพื่อให้ข้อมูลไฮไลต์และโปรไฟล์อัปเดตอัตโนมัติ
  void _listenToUserData() {
    user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          setState(() {
            userData = doc.data();
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
    _userSubscription?.cancel(); // คืน Memory ป้องกันข้อมูลรั่วไหล
    _editContentController.dispose();
    super.dispose();
  }

  // สำหรับดูรูปเดี่ยวๆ เช่น รูปโปรไฟล์ หรือ หน้าปก
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
                    width: 200, height: 200, color: Colors.grey[800],
                    child: const Icon(Icons.broken_image, color: Colors.white, size: 50),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40, right: 20,
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
          left: 16, right: 16, top: 16,
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

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ອອກຈາກລະບົບ"),
        content: const Text("ທ່ານຕ້ອງການອອກຈາກລະບົບແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text("ຢືນຢັນ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final photoUrl = userData!['photoURL'] ?? user?.photoURL ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=300';
    final coverUrl = userData!['coverURL'] ?? 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600';
    final displayName = userData!['displayName'] ?? user?.displayName ?? user?.email ?? 'User';
    final bio = userData!['bio'] ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[200], // เปลี่ยนพื้นหลังหลักเป็นเทาอ่อนแบบ Facebook
      appBar: AppBar(
        title: const Text("ໂޕຣໄຟລ໌"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EditProfilePage()),
            ),
            tooltip: "ແກ້ໄຂໂພຣໄຟລ໌",
          ),
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
                        onLongPress: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilePage()));
                        },
                        child: Stack(
                          children: [
                            Container(
                              height: 200, width: double.infinity,
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
                          onTap: () => _showImagePreview(photoUrl, title: "ຮູບໂປຣໄຟລ໌"),
                          onLongPress: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilePage()));
                          },
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 54, backgroundColor: Colors.white,
                                child: CircleAvatar(
                                  radius: 50, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
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
                                          begin: Alignment.bottomCenter, end: Alignment.center,
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          h['title'] ?? '',
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
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
                  if (user != null)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user!.uid)
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
                              return Container(
                                width: 100,
                                margin: const EdgeInsets.only(right: 10),
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: imageUrl.isNotEmpty
                                          ? Image.network(
                                              imageUrl,
                                              width: 100, height: 100,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Container(
                                                width: 100, height: 100, color: Colors.grey[300],
                                                child: const Icon(Icons.image_not_supported, color: Colors.grey),
                                              ),
                                            )
                                          : Container(
                                              width: 100, height: 100, color: Colors.grey[300],
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

            // ─── โพสต์ที่แชร์ (สไตล์ Facebook) ───
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: const Text("ໂພສຕ໌ທີ່ແຊຣ໌", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (user != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('user_posts')
                    .where('userId', isEqualTo: user!.uid)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      color: Colors.white,
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      child: const Center(child: Text("ທ່ານຍັງບໍ່ໄດ້ແຊຣ໌ໂພສຕ໌ໃດເລີຍ", style: TextStyle(color: Colors.grey))),
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
                      final placeName = data['placeName'] ?? '';
                      final images = (data['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
                      final likedBy = List<String>.from(data['likedBy'] ?? []);
                      final likes = data['likes'] ?? 0;
                      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                      final isMine = data['userId'] == user!.uid;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.white, // ปรับการ์ดให้ชิดขอบและใช้พื้นสีขาวแบบ Facebook
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Avatar + Name + Time + 3 Dots
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
                                  // เมนู 3 จุดไข่ปลา
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
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: const [
                                              Icon(Icons.edit, color: Colors.blue, size: 20),
                                              SizedBox(width: 8),
                                              Text('ແກ້ໄຂໂພສຕ໌'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: const [
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

                            // 📍 Place Name (ถ้ามี)
                            if (placeName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                child: Text("📍 $placeName", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.teal, fontSize: 13)),
                              ),

                            // Post Title
                            if (title.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),

                            // Post Content (Text)
                            if (content.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                child: Text(content, style: const TextStyle(fontSize: 15, height: 1.3)),
                              ),

                            // Post Images (แบบเลื่อนแนวนอนเต็มความกว้างขึน)
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
                                            fit: BoxFit.cover
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                            // Likes Count Indicator Bar
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

                            // Bottom Actions Bar (Like Button เหมือน Facebook)
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
                                            likedBy.contains(user!.uid) ? Icons.favorite : Icons.favorite_border, 
                                            color: likedBy.contains(user!.uid) ? Colors.red : Colors.grey[600],
                                            size: 22,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'ຖືກໃຈ', 
                                            style: TextStyle(
                                              color: likedBy.contains(user!.uid) ? Colors.red : Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14
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

// ─── คลาสสำหรับดูรูปในโพสแบบเต็มจอ และ สามารถเลื่อนซ้าย-ขวาได้ ───
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
          return InteractiveViewer( // เพิ่มอนุญาตให้ซูมรูปเข้า-ออกได้
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

// ─── Highlight Viewer Page ───
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
              top: 10, left: 10, right: 10,
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
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold,
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