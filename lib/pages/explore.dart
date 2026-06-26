import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place_model.dart';
import 'place_detail.dart';
import '../routes/map.dart';

class ExplorePage extends StatefulWidget {
  final ScrollController scrollController;
  final Function(Place) onAddToPlan;

  const ExplorePage({
    super.key,
    required this.scrollController,
    required this.onAddToPlan,
  });

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  static const int _pageSize = 10;
  final List<QueryDocumentSnapshot> _docs = [];
  final Map<String, QueryDocumentSnapshot> _latestPerUser = {};
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _initialLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final ctrl = widget.scrollController;
    if (ctrl.position.pixels >= ctrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    Query query = FirebaseFirestore.instance
        .collection('user_posts')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_lastDoc != null) {
      query = query.startAfterDocument(_lastDoc!);
    }

    final snap = await query.get();
    if (!mounted) return;

    if (snap.docs.isEmpty) {
      setState(() {
        _hasMore = false;
        _isLoading = false;
        _initialLoaded = true;
      });
      return;
    }

    final newDocs = snap.docs;
    _lastDoc = newDocs.last;

    for (final doc in newDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final uid = data['userId'] as String? ?? '';
      if (uid.isEmpty) continue;
      if (!_latestPerUser.containsKey(uid)) {
        _latestPerUser[uid] = doc;
        _docs.add(doc);
      }
    }

    setState(() {
      _isLoading = false;
      _initialLoaded = true;
      if (snap.docs.length < _pageSize) _hasMore = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _docs.clear();
      _latestPerUser.clear();
      _lastDoc = null;
      _hasMore = true;
      _initialLoaded = false;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF3F8),
      appBar: AppBar(
        title: const Text(
          'ສຳຫຼວດປະສົບການ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: !_initialLoaded
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _docs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.explore_off, size: 72, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        "ຍັງບໍ່ມີໂພສຕ໌ໃດໃນຕອນນີ້",
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: Colors.teal,
                  onRefresh: _refresh,
                  child: ListView.builder(
                    controller: widget.scrollController,
                    cacheExtent: 1200,
                    addAutomaticKeepAlives: true,
                    addRepaintBoundaries: true,
                    itemCount: _docs.length + (_isLoading || _hasMore ? 1 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      if (index == _docs.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2)),
                        );
                      }
                      final doc = _docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return _UserPostCard(
                        key: ValueKey(doc.id),
                        postData: data,
                        postId: doc.id,
                        onAddToPlan: widget.onAddToPlan,
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── ฟังก์ชันเปิดดูรูปภาพเต็มจอ ───
void _showImagePreview(BuildContext context, List<String> images, int initialIndex) {
  final PageController pageController = PageController(initialPage: initialIndex);
  showDialog(
    context: context,
    builder: (context) {
      int currentIndex = initialIndex;
      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.85,
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: images.length,
                      onPageChanged: (index) => setState(() => currentIndex = index),
                      itemBuilder: (context, i) {
                        return InteractiveViewer(
                          maxScale: 4.0,
                          child: Image.network(images[i], fit: BoxFit.contain),
                        );
                      },
                    ),
                  ),
                ),
                if (images.length > 1)
                  Positioned(
                    top: 45, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: Text('${currentIndex + 1} / ${images.length}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                Positioned(
                  top: 40, right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
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

// ─── Image Grid ───
Widget _buildFacebookImageGrid(BuildContext context, List<String> images) {
  if (images.isEmpty) return const SizedBox.shrink();

  if (images.length == 1) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: InkWell(
        onTap: () => _showImagePreview(context, images, 0),
        child: Image.network(
          images[0],
          fit: BoxFit.cover,
          cacheWidth: 800,
          errorBuilder: (c, e, s) => Container(
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  if (images.length == 2) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showImagePreview(context, images, 0),
              child: Image.network(images[0], fit: BoxFit.cover, cacheWidth: 500),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: InkWell(
              onTap: () => _showImagePreview(context, images, 1),
              child: Image.network(images[1], fit: BoxFit.cover, cacheWidth: 500),
            ),
          ),
        ],
      ),
    );
  }

  return AspectRatio(
    aspectRatio: 16 / 10,
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: () => _showImagePreview(context, images, 0),
            child: Image.network(images[0], fit: BoxFit.cover, cacheWidth: 600),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showImagePreview(context, images, 1),
                  child: Image.network(images[1], fit: BoxFit.cover, cacheWidth: 400),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: InkWell(
                  onTap: () => _showImagePreview(context, images, 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(images[2], fit: BoxFit.cover, cacheWidth: 400),
                      if (images.length > 3)
                        Container(
                          color: Colors.black54,
                          child: Center(
                            child: Text(
                              '+${images.length - 2}',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─── การ์ดโพสต์ (พร้อม KeepAlive) ───
class _UserPostCard extends StatefulWidget {
  final Map<String, dynamic> postData;
  final String postId;
  final Function(Place) onAddToPlan;

  const _UserPostCard({
    super.key,
    required this.postData,
    required this.postId,
    required this.onAddToPlan,
  });

  @override
  State<_UserPostCard> createState() => _UserPostCardState();
}

class _UserPostCardState extends State<_UserPostCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }

  Future<void> _toggleLike(String currentUserId, List<String> likedBy) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('user_posts').doc(widget.postId);
    if (likedBy.contains(currentUserId)) {
      await docRef.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([currentUserId]),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([currentUserId]),
      });
    }
  }

  // 🔧 ฟังก์ชันช่วยอ่านพิกัดจาก postData
  (double? lat, double? lng) _extractLatLng(Map<String, dynamic> data) {
    if (data['location'] is GeoPoint) {
      final geo = data['location'] as GeoPoint;
      return (geo.latitude, geo.longitude);
    }
    double? lat;
    double? lng;
    if (data['latitude'] != null) lat = (data['latitude'] as num).toDouble();
    if (data['longitude'] != null) lng = (data['longitude'] as num).toDouble();
    if (lat == null && data['lat'] != null) lat = (data['lat'] as num).toDouble();
    if (lng == null && data['lng'] != null) lng = (data['lng'] as num).toDouble();
    return (lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final postData = widget.postData;
    final userName = postData['userName'] ?? 'ນັກທ່ອງທ່ຽວ';
    final userAvatar = postData['userAvatar'] ?? '';
    final userId = postData['userId'] ?? '';
    final title = postData['title'] ?? '';
    final content = postData['content'] ?? '';
    final placeName = postData['placeName'] ?? '';
    final images = (postData['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final createdAt = (postData['createdAt'] as Timestamp?)?.toDate();
    final likedBy = List<String>.from(postData['likedBy'] ?? []);
    final likes = postData['likes'] ?? 0;

    // 🔧 ใช้ฟังก์ชันดึงพิกัด
    final (latitude, longitude) = _extractLatLng(postData);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserAllPostsPage(userId: userId, onAddToPlan: widget.onAddToPlan),
                      ),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.teal[100]),
                    child: ClipOval(
                      child: userAvatar.isNotEmpty
                          ? Image.network(userAvatar, fit: BoxFit.cover, cacheWidth: 120)
                          : Center(child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserAllPostsPage(userId: userId, onAddToPlan: widget.onAddToPlan),
                            ),
                          );
                        },
                        child: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      Row(
                        children: [
                          if (createdAt != null) ...[
                            Text(_formatTimeAgo(createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 4),
                            Icon(Icons.public, size: 12, color: Colors.grey[600]),
                          ],
                          if (placeName.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const Text('•', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MapPage(
                                      latitude: latitude,
                                      longitude: longitude,
                                      placeName: placeName,
                                    ),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on, size: 12, color: Colors.teal),
                                  const SizedBox(width: 2),
                                  Text(
                                    placeName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.teal,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                if (content.isNotEmpty)
                  Text(content, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (images.isNotEmpty)
            _buildFacebookImageGrid(context, images),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.pinkAccent),
                  child: const Icon(Icons.favorite, size: 10, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text('$likes ຖືກໃຈ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          InkWell(
            onTap: () => _toggleLike(currentUserId, likedBy),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    likedBy.contains(currentUserId) ? Icons.favorite : Icons.favorite_border,
                    color: likedBy.contains(currentUserId) ? Colors.pinkAccent : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ຖືກໃຈ',
                    style: TextStyle(
                      color: likedBy.contains(currentUserId) ? Colors.pinkAccent : Colors.grey[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── หน้า UserAllPostsPage (โปรไฟล์ของคนอื่น) ───
class UserAllPostsPage extends StatelessWidget {
  final String userId;
  final Function(Place) onAddToPlan;

  const UserAllPostsPage({
    super.key,
    required this.userId,
    required this.onAddToPlan,
  });

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }

  Future<void> _toggleLike(String postId, List<String> likedBy, String currentUserId) async {
    if (currentUserId.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('user_posts').doc(postId);
    if (likedBy.contains(currentUserId)) {
      await docRef.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([currentUserId]),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([currentUserId]),
      });
    }
  }

  // 🔧 ฟังก์ชันช่วยอ่านพิกัด
  (double? lat, double? lng) _extractLatLng(Map<String, dynamic> data) {
    if (data['location'] is GeoPoint) {
      final geo = data['location'] as GeoPoint;
      return (geo.latitude, geo.longitude);
    }
    double? lat;
    double? lng;
    if (data['latitude'] != null) lat = (data['latitude'] as num).toDouble();
    if (data['longitude'] != null) lng = (data['longitude'] as num).toDouble();
    if (lat == null && data['lat'] != null) lat = (data['lat'] as num).toDouble();
    if (lng == null && data['lng'] != null) lng = (data['lng'] as num).toDouble();
    return (lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.teal)));
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final displayName = userData['displayName'] ?? 'ນັກທ່ອງທ່ຽວ';
        final photoUrl = userData['photoURL'] ?? '';
        final coverUrl = userData['coverURL'] ?? '';
        final bio = userData['bio'] ?? '';
        final highlights = userData['highlights'] ?? [];

        return Scaffold(
          backgroundColor: const Color(0xFFEFF3F8),
          appBar: AppBar(
            title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('user_posts')
                .where('userId', isEqualTo: userId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, postsSnapshot) {
              if (postsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.teal));
              }
              final posts = postsSnapshot.data?.docs ?? [];

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              GestureDetector(
                                onTap: coverUrl.isNotEmpty
                                    ? () => _showImagePreview(context, [coverUrl], 0)
                                    : null,
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    color: const Color(0xFFCFE8E5),
                                    child: coverUrl.isNotEmpty
                                        ? Image.network(coverUrl, fit: BoxFit.cover, cacheWidth: 800)
                                        : const Icon(Icons.image, size: 42, color: Colors.teal),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: -50,
                                child: GestureDetector(
                                  onTap: photoUrl.isNotEmpty
                                      ? () => _showImagePreview(context, [photoUrl], 0)
                                      : null,
                                  child: Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 4))
                                      ]
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Container(
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.teal[100]),
                                      child: ClipOval(
                                        child: photoUrl.isNotEmpty
                                            ? Image.network(photoUrl, fit: BoxFit.cover, cacheWidth: 250)
                                            : Center(child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.teal))),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 60),
                          Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          if (bio.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 32, right: 32),
                              child: Text(bio, style: TextStyle(color: Colors.grey[700], fontSize: 14), textAlign: TextAlign.center),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  if (highlights.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Text("ໄຮໄລທ໌", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                            SizedBox(
                              height: 90,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: highlights.length,
                                itemBuilder: (context, index) {
                                  final h = Map<String, dynamic>.from(highlights[index]);
                                  return Container(
                                    width: 70,
                                    margin: const EdgeInsets.symmetric(horizontal: 5),
                                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey[300]!, width: 2)),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(35),
                                      child: Image.network(h['coverImage'] ?? '', fit: BoxFit.cover, cacheWidth: 150),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (highlights.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // ─── Completed Places ───
                  SliverToBoxAdapter(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Text("✅ ສະຖານທີ່ໆທ່ຽວແລ້ວ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                          ),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(userId)
                                .collection('plans')
                                .where('status', isEqualTo: 'completed')
                                .orderBy('addedAt', descending: true)
                                .snapshots(),
                            builder: (context, planSnapshot) {
                              if (!planSnapshot.hasData || planSnapshot.data!.docs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Text("ຍັງບໍ່ມີສະຖານທີ່ໆທ່ຽວແລ້ວ", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                );
                              }
                              final completedPlaces = planSnapshot.data!.docs;
                              return SizedBox(
                                height: 110,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: completedPlaces.length,
                                  itemBuilder: (context, index) {
                                    final data = completedPlaces[index].data() as Map<String, dynamic>;
                                    final imageUrl = data['imageUrl'] ?? '';
                                    final pName = data['placeName'] ?? '';

                                    double? pLat;
                                    double? pLng;
                                    if (data['location'] is GeoPoint) {
                                      pLat = (data['location'] as GeoPoint).latitude;
                                      pLng = (data['location'] as GeoPoint).longitude;
                                    } else {
                                      if (data['latitude'] != null) pLat = (data['latitude'] as num).toDouble();
                                      if (data['longitude'] != null) pLng = (data['longitude'] as num).toDouble();
                                    }

                                    return InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => MapPage(
                                              latitude: pLat,
                                              longitude: pLng,
                                              placeName: pName,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: 90,
                                        margin: const EdgeInsets.only(right: 10),
                                        child: Column(
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: imageUrl.isNotEmpty
                                                  ? Image.network(imageUrl, width: 90, height: 75, fit: BoxFit.cover, cacheWidth: 150)
                                                  : Container(width: 90, height: 75, color: Colors.grey[300], child: const Icon(Icons.place, color: Colors.orange)),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(pName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
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
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // ─── Posts ───
                  posts.isEmpty
                      ? const SliverFillRemaining(
                          child: Center(child: Text('ຍັງບໍ່ມີໂພສຕ໌', style: TextStyle(color: Colors.grey))),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final data = posts[index].data() as Map<String, dynamic>;
                              final postId = posts[index].id;
                              final title = data['title'] ?? '';
                              final content = data['content'] ?? '';
                              final placeName = data['placeName'] ?? '';
                              final images = (data['images'] as List?)?.map((e) => e.toString()).toList() ?? [];
                              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                              final likedBy = List<String>.from(data['likedBy'] ?? []);
                              final likes = data['likes'] ?? 0;

                              final (postLat, postLng) = _extractLatLng(data);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: Colors.white,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.teal[100]),
                                            child: ClipOval(
                                              child: photoUrl.isNotEmpty
                                                  ? Image.network(photoUrl, fit: BoxFit.cover, cacheWidth: 100)
                                                  : const Icon(Icons.person, size: 18, color: Colors.teal),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                Row(
                                                  children: [
                                                    if (createdAt != null) ...[
                                                      Text(_formatTimeAgo(createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                                                      const SizedBox(width: 4),
                                                      Icon(Icons.public, size: 11, color: Colors.grey[500]),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (placeName.isNotEmpty)
                                            InkWell(
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
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: Colors.teal[50], borderRadius: BorderRadius.circular(8)),
                                                child: Text("📍 $placeName", style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                            )
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (title.isNotEmpty)
                                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          if (content.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(content, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.35)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    if (images.isNotEmpty)
                                      _buildFacebookImageGrid(context, images),

                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.pinkAccent),
                                            child: const Icon(Icons.favorite, size: 9, color: Colors.white),
                                          ),
                                          const SizedBox(width: 4),
                                          Text('$likes ຖືກໃຈ', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    InkWell(
                                      onTap: () => _toggleLike(postId, likedBy, currentUserId),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              likedBy.contains(currentUserId) ? Icons.favorite : Icons.favorite_border,
                                              color: likedBy.contains(currentUserId) ? Colors.pinkAccent : Colors.grey[600],
                                              size: 20,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('ຖືກໃຈ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            childCount: posts.length,
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              );
            },
          ),
        );
      },
    );
  }
}