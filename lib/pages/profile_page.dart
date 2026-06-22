import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      if (doc.exists) {
        setState(() {
          userData = doc.data();
          highlights = userData?['highlights'] ?? [];
        });
      } else {
        setState(() => userData = {});
      }
    }
  }

  // ─── ฟังก์ชันแสดงรูปภาพใหญ่ (Preview) ───
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
                    return Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: MediaQuery.of(context).size.height * 0.7,
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
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
            if (title != null && title.isNotEmpty)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black54,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Like / Unlike ───
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

  // ─── แก้ไขโพสต์ ───
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
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("ອັບເດດໂພສຕ໌ສຳເລັດ"), backgroundColor: Colors.green),
                  );
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

  // ─── ลบโพสต์ ───
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("ລົບໂພສຕ໌ແລ້ວ"), backgroundColor: Colors.red),
              );
            },
            child: const Text("ລົບ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── ออกจากระบบ ───
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("ໂປຣໄຟລ໌"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EditProfilePage()),
            ).then((_) => _loadData()),
            tooltip: "ແກ້ໄຂໂປຣໄຟລ໌",
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
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Cover image (คลิกเพื่อดูใหญ่, ค้างเพื่อเปลี่ยน)
                GestureDetector(
                  onTap: () => _showImagePreview(coverUrl, title: "ຮູບພື້ນຫຼັງ"),
                  onLongPress: () {
                    // ไปหน้า EditProfile เพื่อเปลี่ยน
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const EditProfilePage()),
                    ).then((_) => _loadData());
                  },
                  child: Stack(
                    children: [
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          image: coverUrl.isNotEmpty
                              ? DecorationImage(image: NetworkImage(coverUrl), fit: BoxFit.cover)
                              : null,
                          color: Colors.grey[300],
                        ),
                        child: coverUrl.isEmpty
                            ? const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey)
                            : null,
                      ),
                      if (coverUrl.isNotEmpty)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: const [
                                Icon(Icons.visibility, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text("ເບິ່ງ", style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Profile photo (คลิกเพื่อดูใหญ่, ค้างเพื่อเปลี่ยน)
                Positioned(
                  bottom: -50,
                  child: GestureDetector(
                    onTap: () => _showImagePreview(photoUrl, title: "ຮູບໂປຣໄຟລ໌"),
                    onLongPress: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const EditProfilePage()),
                      ).then((_) => _loadData());
                    },
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
                        if (_isUploading)
                          const Positioned.fill(
                            child: Center(
                              child: CircularProgressIndicator(color: Colors.teal),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.teal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.visibility, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),

            // ─── User Info ───
            Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (bio.isNotEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(bio, style: const TextStyle(color: Colors.grey))),
            const Divider(),

            // ─── Highlights ───
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
                    ).then((_) => _loadData()),
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
                  final h = highlights[index] as Map<String, dynamic>;
                  return GestureDetector(
                    onTap: () => _showImagePreview(h['coverImage'], title: h['title']),
                    child: Container(
                      width: 80,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(image: NetworkImage(h['coverImage']), fit: BoxFit.cover),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Text(h['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),

            // ─── โพสต์ที่แชร์ ───
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text("ໂພສຕ໌ທີ່ແຊຣ໌", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (user != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('user_posts')
                    .where('userId', isEqualTo: user!.uid)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text("ທ່ານຍັງບໍ່ໄດ້ແຊຣ໌ໂພສຕ໌ໃດເລີຍ", style: TextStyle(color: Colors.grey)),
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

                      final content = data['content'] ?? '';
                      final placeName = data['placeName'] ?? '';
                      final images = (data['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
                      final likedBy = List<String>.from(data['likedBy'] ?? []);
                      final likes = data['likes'] ?? 0;
                      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                      final isMine = data['userId'] == user!.uid;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (placeName.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        "📍 $placeName",
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (createdAt != null)
                                    Text(
                                      _formatTimeAgo(createdAt),
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (content.isNotEmpty)
                                Text(content, style: const TextStyle(fontSize: 15)),
                              const SizedBox(height: 8),
                              if (images.isNotEmpty)
                                SizedBox(
                                  height: 120,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: images.length > 4 ? 4 : images.length,
                                    itemBuilder: (context, i) {
                                      return GestureDetector(
                                        onTap: () => _showImagePreview(images[i], title: placeName),
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(images[i], width: 120, height: 120, fit: BoxFit.cover),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      likedBy.contains(user!.uid) ? Icons.favorite : Icons.favorite_border,
                                      color: likedBy.contains(user!.uid) ? Colors.red : Colors.grey,
                                    ),
                                    onPressed: () => _toggleLike(postId, likedBy, likes),
                                  ),
                                  Text('$likes', style: const TextStyle(fontSize: 14)),
                                  const Spacer(),
                                  if (isMine) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _editPost(data),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deletePost(postId),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
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

  // Helper: แสดงเวลาที่ผ่านมา
  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }
}