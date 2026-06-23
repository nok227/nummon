import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_model.dart';
import 'place_detail.dart';

class ExplorePage extends StatelessWidget {
  final ScrollController scrollController;
  final Function(Place) onAddToPlan;

  const ExplorePage(
      {super.key, required this.scrollController, required this.onAddToPlan});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('ສຳຫຼວດປະສົບການ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_posts')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.teal));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.explore_off, size: 72, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text("ຍັງບໍ່ມີໂພສຕ໌ໃດໃນຕອນນີ້",
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            );
          }

          // --- ດຶງ post ລ່າສຸດຂອງແຕ່ລະ user ຄົນລະ 1 ---
          final allDocs = snapshot.data!.docs;
          final Map<String, QueryDocumentSnapshot> latestPerUser = {};
          for (final doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final uid = data['userId'] as String? ?? '';
            if (uid.isEmpty) continue;
            if (!latestPerUser.containsKey(uid)) {
              latestPerUser[uid] = doc; // ອັນທຳອິດ = ລ່າສຸດ (ສັ່ງ desc ແລ້ວ)
            }
          }
          final userLatestPosts = latestPerUser.values.toList();

          return ListView.builder(
            controller: scrollController,
            itemCount: userLatestPosts.length,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            itemBuilder: (context, index) {
              final doc = userLatestPosts[index];
              final data = doc.data() as Map<String, dynamic>;
              return _UserPostCard(
                postData: data,
                postId: doc.id,
                onAddToPlan: onAddToPlan,
              );
            },
          );
        },
      ),
    );
  }
}

// ── Card แสดงโพสล่าสุดของ userแต่ละคน ──
class _UserPostCard extends StatelessWidget {
  final Map<String, dynamic> postData;
  final String postId;
  final Function(Place) onAddToPlan;

  const _UserPostCard({
    required this.postData,
    required this.postId,
    required this.onAddToPlan,
  });

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }

  @override
  Widget build(BuildContext context) {
    final userName = postData['userName'] ?? 'ນັກທ່ອງທ່ຽວ';
    final userAvatar = postData['userAvatar'] ?? '';
    final userBackground = postData['userBackground'] ?? ''; // ดึงรูปพื้นหลังโปรไฟล์
    final userId = postData['userId'] ?? '';
    final title = postData['title'] ?? '';
    final content = postData['content'] ?? '';
    final placeName = postData['placeName'] ?? '';
    final images = (postData['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final createdAt = (postData['createdAt'] as Timestamp?)?.toDate();
    final likes = postData['likes'] ?? 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserAllPostsPage(
              userId: userId,
              userName: userName,
              userAvatar: userAvatar,
              userBackground: userBackground, // ส่งต่อไปยังหน้าโปรไฟล์รวม
              onAddToPlan: onAddToPlan,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: Avatar + ชื่อ + เวลา ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: userAvatar.isNotEmpty ? NetworkImage(userAvatar) : null,
                    backgroundColor: Colors.teal[100],
                    child: userAvatar.isEmpty
                        ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        if (placeName.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 12, color: Colors.teal),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(placeName,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.teal),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (createdAt != null)
                    Text(_formatTimeAgo(createdAt),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),

            // ── รูปภาพ (ถ้ามี) ──
            if (images.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.zero,
                  topRight: Radius.zero,
                ),
                child: Stack(
                  children: [
                    Image.network(
                      images[0],
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(
                        height: 200,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 8,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('+${images.length - 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // ── Title + Content ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ],
                ],
              ),
            ),

            // ── Footer: likes + ดูเพิ่มเติม ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.favorite_border, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('$likes', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const Spacer(),
                  Text('ເບິ່ງທັງໝົດ →',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.teal[700],
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── หน้าแสดงโพสทั้งหมดของ user คนนั้น ──
class UserAllPostsPage extends StatelessWidget {
  final String userId;
  final String userName;
  final String userAvatar;
  final String userBackground; // เพิ่มฟิลด์รับค่าพื้นหลังโปรไฟล์
  final Function(Place) onAddToPlan;

  const UserAllPostsPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.userBackground, // รับค่าพารามิเตอร์พื้นหลัง
    required this.onAddToPlan,
  });

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }

  // ปรับปรุงฟังก์ชันพรีวิวรูปภาพให้เลื่อนซ้าย-ขวาได้เหมือนหน้า Profile
  void _showImagePreview(BuildContext context, List<String> images, int initialIndex) {
    final PageController pageController = PageController(initialPage: initialIndex);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        int currentIndex = initialIndex;
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                children: [
                  // ใช้ PageView.builder เพื่อให้สไลด์เปลี่ยนรูปภาพซ้าย-ขวาได้
                  Center(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.8,
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: images.length,
                        onPageChanged: (index) {
                          setState(() {
                            currentIndex = index;
                          });
                        },
                        itemBuilder: (context, i) {
                          return InteractiveViewer( // ดึงนิ้วเพื่อซูมขยายเข้า-ออกได้ด้วย
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                images[i],
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                      child: CircularProgressIndicator(color: Colors.white));
                                },
                                errorBuilder: (c, e, s) => Container(
                                  width: 200,
                                  height: 200,
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.white, size: 50),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // แสดงตัวเลขกำกับตำแหน่งรูปภาพ (เช่น 1 / 3)
                  if (images.length > 1)
                    Positioned(
                      top: 45,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${currentIndex + 1} / ${images.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  // ปุ่มปิด Dialog
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_posts')
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator(color: Colors.teal)));
          }

          final posts = snapshot.data?.docs ?? [];

          return CustomScrollView(
            slivers: [
              // ── SliverAppBar แสดงพื้นหลังโปรไฟล์จริง ──
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // เช็คว่ามีรูปพื้นหลังโปรไฟล์บันทึกไว้หรือไม่ ถ้าไม่มีให้ใช้สี Gradient เดิม
                      userBackground.isNotEmpty
                          ? Image.network(
                              userBackground,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => Container(color: Colors.teal),
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF00897B), Color(0xFF004D40)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                      // แผ่นกรองสีดำจางๆ เพื่อป้องกันตัวหนังสือกลืนไปกับภาพพื้นหลัง
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.1),
                              Colors.black.withOpacity(0.5)
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      // Avatar + ชื่อ
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 33,
                                backgroundImage: userAvatar.isNotEmpty
                                    ? NetworkImage(userAvatar)
                                    : null,
                                backgroundColor: Colors.teal[100],
                                child: userAvatar.isEmpty
                                    ? Text(
                                        userName.isNotEmpty
                                            ? userName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            fontSize: 26,
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(userName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('${posts.length} ໂພສຕ໌',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13)),
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

              // ── โพสทั้งหมด ──
              posts.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.post_add, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('ຍັງບໍ່ມີໂພສຕ໌',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 16)),
                          ],
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final data =
                              posts[index].data() as Map<String, dynamic>;
                          final title = data['title'] ?? '';
                          final content = data['content'] ?? '';
                          final placeName = data['placeName'] ?? '';
                          final images = (data['images'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              [];
                          final createdAt =
                              (data['createdAt'] as Timestamp?)?.toDate();
                          final likes = data['likes'] ?? 0;
                          final likedBy =
                              List<String>.from(data['likedBy'] ?? []);

                          return Container(
                            margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Place + time
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                                  child: Row(
                                    children: [
                                      if (placeName.isNotEmpty) ...[
                                        const Icon(Icons.location_on,
                                            size: 14, color: Colors.teal),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(placeName,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.teal,
                                                  fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ] else
                                        const Spacer(),
                                      if (createdAt != null)
                                        Text(_formatTimeAgo(createdAt),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey)),
                                    ],
                                  ),
                                ),

                                // รูปภาพโพสต์บนหน้า Feed
                                if (images.isNotEmpty)
                                  SizedBox(
                                    height: 220,
                                    child: PageView.builder(
                                      itemCount: images.length,
                                      itemBuilder: (context, i) {
                                        return GestureDetector(
                                          onTap: () => _showImagePreview(
                                              context, images, i), // ส่งลิสต์และอินเด็กซ์เริ่มต้นเพื่อสไลด์ดูรูปได้
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.network(
                                                images[i],
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    Container(
                                                  color: Colors.grey[200],
                                                  child: const Icon(
                                                      Icons.broken_image,
                                                      size: 48,
                                                      color: Colors.grey),
                                                ),
                                              ),
                                              if (images.length > 1)
                                                Positioned(
                                                  bottom: 8,
                                                  right: 10,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black54,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Text(
                                                        '${i + 1}/${images.length}',
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 11)),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                // Title + Content
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 10, 14, 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (title.isNotEmpty)
                                        Text(title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                      if (content.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(content,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black87,
                                                height: 1.4)),
                                      ],
                                    ],
                                  ),
                                ),

                                // Likes
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 6, 14, 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        likedBy.isNotEmpty
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 18,
                                        color: Colors.pinkAccent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text('$likes ຖືກໃຈ',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54)),
                                    ],
                                  ),
                                ),

                                const Divider(height: 1),
                              ],
                            ),
                          );
                        },
                        childCount: posts.length,
                      ),
                    ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          );
        },
      ),
    );
  }
}