// home.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/place_model.dart';
import '../models/comment_model.dart';
import '../ci/comment_service.dart';
import 'place_detail.dart';
import '../widgets/story.dart';
import '../models/api_Cloudinary.dart';
import '../models/emoji_storage.dart';
import '../ci/reaction_picker.dart';

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
  bool isAdmin = false;
  bool _isClearingAll = false;
  bool _isSearchVisible = false;

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>("");

  final CommentService _commentService = CommentService();

  late final Stream<QuerySnapshot> _placesStream;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();

    _placesStream = FirebaseFirestore.instance
        .collection('places')
        .orderBy('name')
        .snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  void _checkAdminStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null &&
        (user.email == 'admin_app@travel.com' || user.email == 'admin_app')) {
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
        title: const Text("🚨 ຄຳເຕືອນ 🚨"),
        content: const Text(
            "ທ່ານຕ້ອງການລົບສະຖານທີ່ທັງໝົດ ແລະ ຮູບພາບທັງໝົດໃນ Cloudinary ແທ້ຫຼືບໍ່? ຂໍ້ມູນຈະຫາຍໄປຕະຫຼອດການ!"),
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
                final querySnapshot =
                    await FirebaseFirestore.instance.collection('places').get();
                for (var doc in querySnapshot.docs) {
                  final data = doc.data();
                  List<String> urlsToDelete = [];
                  if (data['imageUrl'] != null)
                    urlsToDelete.add(data['imageUrl']);
                  if (data['imageUrls'] != null) {
                    urlsToDelete.addAll(
                        (data['imageUrls'] as List).map((e) => e.toString()));
                  }
                  for (String url in urlsToDelete) {
                    await _deleteFromCloudinary(url);
                  }
                  await FirebaseFirestore.instance
                      .collection('places')
                      .doc(doc.id)
                      .delete();
                }
                _showSnackBar("ລ້າງຂໍ້ມູນທັງໝົດສຳເລັດແລ້ວ!");
              } catch (e) {
                _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e", isError: true);
              } finally {
                setState(() => _isClearingAll = false);
              }
            },
            child: const Text("ຢືນຢັນການລົບທັງໝົດ",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
      final String basicAuth =
          'Basic ${base64Encode(utf8.encode('${CloudinaryConfig.apiKey}:${CloudinaryConfig.apiSecret}'))}';
      final response = await http.post(
        Uri.parse(
            'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/image/destroy'),
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: {'public_id': publicId},
      );
      if (response.statusCode != 200) {
        debugPrint("Failed to delete: ${response.body}");
      }
    } catch (e) {
      debugPrint("Cloudinary delete error: $e");
    }
  }

  void _deletePlace(String id, String name) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ ຢືນຢັນການລົບ"),
        content: Text("ທ່ານຕ້ອງການລົບສະຖານທີ່ \"$name\" ແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ຍົກເລີກ"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('places')
                  .doc(id)
                  .delete();
              _showSnackBar("ລົບ \"$name\" ສຳເລັດ");
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("↕️ ຈັດຕຳແໜ່ງ ແລະ ເລື່ອນພາບປົກ",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal)),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.teal, width: 2)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(place.imageUrl,
                              fit: BoxFit.cover,
                              alignment: Alignment(0, currentAlignmentY)),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Text("🔝 ເທິງ", style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: currentAlignmentY,
                            min: -1.0,
                            max: 1.0,
                            activeColor: Colors.teal,
                            onChanged: (val) =>
                                setModalState(() => currentAlignmentY = val),
                          ),
                        ),
                        const Text("🔙 ລຸ່ມ", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const Divider(),
                    const Text("🔄 ຈັດລຽງລໍາດັບຮູບພາບ (ຍ້າຍຂຶ້ນ/ລົງ)",
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    images.isEmpty
                        ? const Center(child: Text("ບໍ່ມີຮູບພາບໃຫ້ຈັດຕຳແໜ່ງ"))
                        : Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: images.length,
                              itemBuilder: (context, index) {
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(images[index],
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover),
                                    ),
                                    title: Text("ຮູບພາບທີ ${index + 1}"),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (index > 0)
                                          IconButton(
                                            icon: const Icon(Icons.arrow_upward,
                                                color: Colors.teal),
                                            onPressed: () => setModalState(() {
                                              final temp = images[index];
                                              images[index] = images[index - 1];
                                              images[index - 1] = temp;
                                            }),
                                          ),
                                        if (index < images.length - 1)
                                          IconButton(
                                            icon: const Icon(
                                                Icons.arrow_downward,
                                                color: Colors.teal),
                                            onPressed: () => setModalState(() {
                                              final temp = images[index];
                                              images[index] = images[index + 1];
                                              images[index + 1] = temp;
                                            }),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          await FirebaseFirestore.instance
                              .collection('places')
                              .doc(place.id)
                              .update({
                            'imageUrls': images,
                            'imageAlignmentY': currentAlignmentY,
                            if (images.isNotEmpty) 'imageUrl': images.first,
                          });
                          _showSnackBar("ຈັດຮຽງຕຳແໜ່ງຮູບພາບສຳເລັດແລ້ວ!");
                        } catch (e) {
                          _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e", isError: true);
                        }
                      },
                      child: const Text("ບັນທຶກຕຳແໜ່ງໃໝ່"),
                    ),
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
    final List<String> images = List.from(place.imageUrls ?? []);
    if (images.isEmpty && place.imageUrl.isNotEmpty) {
      images.add(place.imageUrl);
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("📸 ເລືອກຮູບພາບປົກໃໝ່",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal)),
              const SizedBox(height: 12),
              images.isEmpty
                  ? const Center(child: Text("ບໍ່ມີຮູບພາບໃຫ້ເລືອກ"))
                  : SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        itemBuilder: (context, index) {
                          final isCurrentCover =
                              images[index] == place.imageUrl;
                          return GestureDetector(
                            onTap: () async {
                              Navigator.pop(context);
                              try {
                                await FirebaseFirestore.instance
                                    .collection('places')
                                    .doc(place.id)
                                    .update({'imageUrl': images[index]});
                                _showSnackBar("ປ່ຽນຮູບພາບປົກສຳເລັດແລ້ວ!");
                              } catch (e) {
                                _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e",
                                    isError: true);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 120,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: isCurrentCover
                                        ? Colors.teal
                                        : Colors.grey.shade300,
                                    width: isCurrentCover ? 3 : 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(images[index],
                                    fit: BoxFit.cover),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
          StreamBuilder<QuerySnapshot>(
            stream: _placesStream,
            builder: (context, snapshot) {
              final List<Place> allPlaces = [];
              if (snapshot.hasData) {
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  allPlaces.add(Place.fromMap(doc.id, data));
                }
              }

              return SingleChildScrollView(
                controller: widget.scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(
                          top: 60, left: 20, right: 20, bottom: 20),
                      decoration: const BoxDecoration(
                        color: Colors.teal,
                        borderRadius:
                            BorderRadius.vertical(bottom: Radius.circular(32)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.menu,
                                    color: Colors.white, size: 28),
                                onPressed: widget.onMenuPressed,
                              ),
                              Row(
                                children: [
                                  if (isAdmin)
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_horiz,
                                          color: Colors.white, size: 28),
                                      tooltip: "ເມນູຈັດການ",
                                      onSelected: (value) {
                                        if (value == 'clear_all')
                                          _clearAllDataAndImages();
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'clear_all',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_forever,
                                                  color: Colors.red),
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
                                        _isSearchVisible
                                            ? Icons.close
                                            : Icons.search,
                                        color: Colors.white,
                                        size: 28),
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
                                  GestureDetector(
                                    onTap: widget.onProfilePressed,
                                    child: Stack(
                                      children: [
                                        StreamBuilder<DocumentSnapshot>(
                                          stream: currentUser != null
                                              ? FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(currentUser.uid)
                                                  .snapshots()
                                              : const Stream.empty(),
                                          builder: (context, snapshot) {
                                            String photoUrl = '';
                                            if (snapshot.hasData &&
                                                snapshot.data!.exists) {
                                              final data = snapshot.data!.data()
                                                  as Map<String, dynamic>?;
                                              photoUrl =
                                                  data?['photoURL'] ?? '';
                                            }
                                            return CircleAvatar(
                                              radius: 22,
                                              backgroundImage: photoUrl
                                                      .isNotEmpty
                                                  ? NetworkImage(photoUrl)
                                                  : const AssetImage(
                                                          'assets/default.jpg')
                                                      as ImageProvider,
                                            );
                                          },
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: const BoxDecoration(
                                                  color: Colors.greenAccent,
                                                  shape: BoxShape.circle)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_isSearchVisible) ...[
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) =>
                                    _searchQueryNotifier.value = value.trim(),
                                decoration: const InputDecoration(
                                  hintText: "ຄົ້ນຫາສະຖານທີ່...",
                                  prefixIcon:
                                      Icon(Icons.search, color: Colors.teal),
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const StorySection(),
                    const Padding(
                      padding: EdgeInsets.only(left: 16, top: 20, bottom: 0),
                      child: Text("ສະຖານທີ່ຍອດນິຍົມ",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        allPlaces.isEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 3,
                        itemBuilder: (context, index) => Shimmer.fromColors(
                          baseColor: Colors.grey[300]!,
                          highlightColor: Colors.grey[100]!,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Container(color: Colors.white)),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Container(
                                      height: 16,
                                      width: 200,
                                      color: Colors.white),
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
                          final filteredPlaces = allPlaces.where((place) {
                            if (searchQuery.isEmpty) return true;
                            final q = searchQuery.toLowerCase();
                            return place.name.toLowerCase().contains(q) ||
                                place.district.toLowerCase().contains(q);
                          }).toList();

                          if (allPlaces.isEmpty) {
                            return const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text("ບໍ່ມີຂໍ້ມູນສະຖານທີ່")));
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredPlaces.length,
                            itemBuilder: (context, index) {
                              final place = filteredPlaces[index];
                              return PostCard(
                                key: ValueKey(place.id),
                                place: place,
                                isAdmin: isAdmin,
                                onAddToPlan: widget.onAddToPlan,
                                commentService: _commentService,
                                onDeletePlace: _deletePlace,
                                onArrangeImages: _openArrangeImagesSheet,
                                onSetCover: _openSelectCoverSheet,
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              );
            },
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
                    Text("ກຳລັງລົບຂໍ້ມູນທັງໝົດ...",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// ✅ PostCard Widget
// ==========================================
class PostCard extends StatefulWidget {
  final Place place;
  final bool isAdmin;
  final Function(Place) onAddToPlan;
  final CommentService commentService;
  final Function(String, String) onDeletePlace;
  final Function(Place) onArrangeImages;
  final Function(Place) onSetCover;

  const PostCard({
    super.key,
    required this.place,
    required this.isAdmin,
    required this.onAddToPlan,
    required this.commentService,
    required this.onDeletePlace,
    required this.onArrangeImages,
    required this.onSetCover,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isCommentExpanded = false;
  bool _hasOpenedComments = false;

  // ✅ ตัวแปรสำหรับ Reply
  String? _replyingToCommentId;
  String? _replyingToUserName;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();

  // ✅ ตัวแปรสำหรับขยาย Replies
  final Map<String, bool> _expandedReplies = {};

  String _selectedReaction = '';
  final LayerLink _layerLink = LayerLink();

  late final TextEditingController _commentController;
  late final FocusNode _commentFocusNode;

  late final Stream<List<Comment>> _commentsStream;
  late final Stream<int> _reactionCountStream;
  late final Stream<int> _commentCountStream;
  late final Stream<QuerySnapshot> _recentReactionsStream;

  OverlayEntry? _reactionOverlayEntry;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
    _commentFocusNode = FocusNode();

    _commentsStream = widget.commentService.getComments(widget.place.id);

    _reactionCountStream = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.place.id)
        .collection('reactions')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);

    _commentCountStream = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.place.id)
        .collection('comments')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);

    _recentReactionsStream = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.place.id)
        .collection('reactions')
        .orderBy('updatedAt', descending: true)
        .snapshots();

    _loadReaction();
  }

  @override
  void dispose() {
    _dismissReactionOverlay();
    _commentController.dispose();
    _commentFocusNode.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  void _dismissReactionOverlay() {
    if (_reactionOverlayEntry != null) {
      _reactionOverlayEntry!.remove();
      _reactionOverlayEntry = null;
    }
  }

void _showReactionPicker(BuildContext context) {
  _dismissReactionOverlay();

  _reactionOverlayEntry = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          GestureDetector(
            onTap: _dismissReactionOverlay,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
          Positioned(
            child: ReactionPicker(
              postId: widget.place.id,
              placeId: widget.place.id,
              layerLink: _layerLink,
              onEmojiSelected: (emoji) {
                // ✅ เลือกอีโมจิ
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    if (_selectedReaction == emoji) {
                      _selectedReaction = '';
                    } else {
                      _selectedReaction = emoji;
                    }
                  });
                  _saveReaction(); // ✅ บันทึกทันที
                });
                // ✅ ปิด picker
                _dismissReactionOverlay();
              },
              onDismiss: _dismissReactionOverlay,
            ),
          ),
        ],
      );
    },
  );

  Overlay.of(context).insert(_reactionOverlayEntry!);
}

  // ✅ ฟังก์ชันเริ่มการตอบกลับ
  void _startReply(String commentId, String userName) {
    setState(() {
      if (_replyingToCommentId == commentId) {
        _replyingToCommentId = null;
        _replyingToUserName = null;
        _replyController.clear();
      } else {
        _replyingToCommentId = commentId;
        _replyingToUserName = userName;
        _replyController.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _replyFocusNode.requestFocus();
        });
      }
    });
  }

  // ✅ ฟังก์ชันยกเลิกการตอบกลับ
  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUserName = null;
      _replyController.clear();
      _replyFocusNode.unfocus();
    });
  }

  // ✅ ฟังก์ชันส่ง Reply
  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _replyingToCommentId == null) return;

    try {
      await widget.commentService.addReply(
        widget.place.id,
        _replyingToCommentId!,
        text,
      );
      _replyController.clear();
      _cancelReply();
      if (mounted) {
        _showSnackBar('ຕອບກັບສຳເລັດແລ້ວ');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('ເກີດຂໍ້ຜິດພາດ: $e', isError: true);
      }
    }
  }

  // ✅ ฟังก์ชันสลับขยาย Replies
  void _toggleReplies(String commentId) {
    setState(() {
      _expandedReplies[commentId] = !(_expandedReplies[commentId] ?? false);
    });
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    try {
      await widget.commentService.addComment(widget.place.id, text);
      _commentController.clear();
      _commentFocusNode.unfocus();
      if (mounted) {
        _showSnackBar('ສົ່ງຄຳເຫັນສຳເລັດ');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('ເກີດຂໍ້ຜິດພາດ: $e', isError: true);
      }
    }
  }

  void _deleteComment(String commentId, {String? replyId}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ ຢືນຢັນການລົບ'),
        content: const Text('ທ່ານຕ້ອງການລົບຄຳເຫັນນີ້ແທ້ຫຼືບໍ່?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await widget.commentService
                  .deleteComment(widget.place.id, commentId, replyId: replyId);
              if (mounted) {
                _showSnackBar('ລົບຄຳເຫັນສຳເລັດ');
              }
            },
            child: const Text('ຢືນຢັນ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReaction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.place.id)
          .collection('reactions')
          .doc(user.uid)
          .set({
        'reaction': _selectedReaction,
        'userId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Save reaction error: $e');
    }
  }

  Future<void> _loadReaction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.place.id)
          .collection('reactions')
          .doc(user.uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        final reaction = data['reaction'] as String?;
        if (reaction != null && reaction.isNotEmpty) {
          setState(() {
            _selectedReaction = reaction;
          });
        }
      }
    } catch (e) {
      debugPrint('Load reaction error: $e');
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

  // ✅ Widget ปุ่ม Like พร้อม Reaction Picker
  Widget _buildLikeButton({
    required bool isLiked,
    required int likeCount,
    required VoidCallback onTap,
    required bool isComment,
    required LayerLink layerLink,
    required VoidCallback onLongPress,
  }) {
    return CompositedTransformTarget(
      link: layerLink,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: onTap,
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: child,
                );
              },
              child: Icon(
                isLiked ? Icons.thumb_up : Icons.thumb_up_off_alt_outlined,
                key: ValueKey(isLiked),
                size: isComment ? 14 : 12,
                color: isLiked ? Colors.blue[700] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: isComment ? 12 : 10,
                fontWeight: FontWeight.w500,
                color: isLiked ? Colors.blue[700] : Colors.grey[700],
              ),
              child: Text(isLiked ? 'ຖືກໃຈແລ້ວ' : 'ຖືກໃຈ'),
            ),
            if (likeCount > 0) ...[
              const SizedBox(width: 4),
              Icon(Icons.thumb_up,
                  size: isComment ? 11 : 9, color: Colors.blue[600]),
              const SizedBox(width: 2),
              Text(
                '$likeCount',
                style: TextStyle(
                  fontSize: isComment ? 11 : 9,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ✅ Reaction Picker สำหรับคอมเมนต์
// ✅ Reaction Picker สำหรับคอมเมนต์ (แบบปลอดภัย)
  void _showCommentReactionPicker(BuildContext context, LayerLink link,
      String commentId, Function(String) onEmojiSelected) {
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                overlayEntry?.remove();
                overlayEntry = null;
              },
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
            Positioned(
              child: ReactionPicker(
                postId: widget.place.id,
                placeId: widget.place.id,
                layerLink: link,
                onEmojiSelected: (emoji) {
                  onEmojiSelected(emoji);
                  overlayEntry?.remove();
                  overlayEntry = null;
                },
                onDismiss: () {
                  overlayEntry?.remove();
                  overlayEntry = null;
                },
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  Widget _buildCommentItem(Comment comment) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == comment.userId;
    final isAdmin = currentUser?.email == 'admin_app@travel.com' ||
        currentUser?.email == 'admin_app';

    final isReplying = _replyingToCommentId == comment.id;
    final isRepliesExpanded = _expandedReplies[comment.id] ?? false;

    // ✅ LayerLink สำหรับ Reaction Picker ของคอมเมนต์
    final commentLayerLink = LayerLink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: comment.userPhotoUrl.isNotEmpty
                    ? NetworkImage(comment.userPhotoUrl)
                    : const AssetImage('assets/default.jpg') as ImageProvider,
                child: comment.userPhotoUrl.isEmpty
                    ? const Icon(Icons.person, size: 18, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ กล่องข้อความ + เวลาอยู่ขวาบน
                    Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 🛠️ โค้ดที่แก้ไขแล้ว
                              Padding(
                                // เว้นพื้นที่ด้านขวาไว้ประมาณ 24-28 เพื่อไม่ให้เวลาชิดหรือมุดเข้าไปใต้ปุ่มไข่ปลา
                                padding: const EdgeInsets.only(right: 26),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      // ห่อชื่อผู้ใช้ด้วย Expanded เพื่อป้องกันกรณีชื่อยาวเกินไปแล้วดันเวลาทะลุจอ
                                      child: Text(
                                        comment.userName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow
                                            .ellipsis, // หากชื่อยาวเกินจะตัดเป็น ...
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // ✅ เวลาอยู่ด้านขวาบน (จะขยับซ้ายหลบปุ่มไข่ปลาให้พอดี)
                                    Text(
                                      comment.timeAgo,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500]),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                comment.text,
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),

                        // ✅ ปุ่มลบ (ไข่ปลา 3 จุด) ด้านขวาบน
                        if (isOwner || isAdmin)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  size: 18, color: Colors.grey),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onSelected: (value) {
                                if (value == 'delete') {
                                  _deleteComment(comment.id);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete,
                                          color: Colors.red, size: 16),
                                      SizedBox(width: 8),
                                      Text('ລົບ',
                                          style: TextStyle(
                                              color: Colors.red, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // ✅ แถวด้านล่าง: ถูกใจ (มี Reaction Picker) + ตอบกลับ
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 16,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // ✅ ปุ่มถูกใจพร้อม Reaction Picker (เหมือนด้านนอก)
                              CompositedTransformTarget(
                                link: commentLayerLink,
                                child: GestureDetector(
                                  onLongPress: () {
                                    _showCommentReactionPicker(
                                      context,
                                      commentLayerLink,
                                      comment.id,
                                      (emoji) {
                                        // ✅ บันทึก reaction ลง Firestore
                                        FirebaseFirestore.instance
                                            .collection('places')
                                            .doc(widget.place.id)
                                            .collection('reactions')
                                            .doc(currentUser?.uid)
                                            .set({
                                          'reaction': emoji,
                                          'userId': currentUser?.uid,
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                        setState(() {
                                          // ✅ อัปเดต UI
                                        });
                                      },
                                    );
                                  },
                                  onTap: () {
                                    // ✅ กดสั้น = Like ธรรมดา (toggle)
                                    widget.commentService.toggleLike(
                                      widget.place.id,
                                      comment.id,
                                      false,
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        transitionBuilder: (child, animation) {
                                          return ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          );
                                        },
                                        child: Icon(
                                          comment.likes
                                                  .contains(currentUser?.uid)
                                              ? Icons.thumb_up
                                              : Icons.thumb_up_off_alt_outlined,
                                          key: ValueKey(comment.likes
                                              .contains(currentUser?.uid)),
                                          size: 14,
                                          color: comment.likes
                                                  .contains(currentUser?.uid)
                                              ? Colors.blue[700]
                                              : Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      AnimatedDefaultTextStyle(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: comment.likes
                                                  .contains(currentUser?.uid)
                                              ? Colors.blue[700]
                                              : Colors.grey[700],
                                        ),
                                        child: Text(
                                          comment.likes
                                                  .contains(currentUser?.uid)
                                              ? 'ຖືກໃຈແລ້ວ'
                                              : 'ຖືກໃຈ',
                                        ),
                                      ),
                                      if (comment.likes.isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.thumb_up,
                                            size: 11, color: Colors.blue[600]),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${comment.likes.length}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  _startReply(comment.id, comment.userName);
                                },
                                child: Text(
                                  isReplying ? 'ຍົກເລີກ' : 'ຕອບກັບ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isReplying
                                        ? Colors.red
                                        : Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // ✅ ฝั่งขวาเหลือไว้สำหรับจำนวน reaction (ถ้ามี)
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('places')
                                .doc(widget.place.id)
                                .collection('reactions')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ✅ Input ตอบกลับ
          if (isReplying) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(left: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.reply, size: 14, color: Colors.teal),
                      const SizedBox(width: 4),
                      Text(
                        'ຕອບກັບ @${_replyingToUserName ?? ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.teal[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          focusNode: _replyFocusNode,
                          decoration: const InputDecoration(
                            hintText: 'ພິມຄຳຕອບກັບ...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          onSubmitted: (_) => _sendReply(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send,
                            color: Colors.teal, size: 20),
                        onPressed: _sendReply,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.grey, size: 20),
                        onPressed: _cancelReply,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // ✅ Replies (โหลดแบบ Real-time)
          StreamBuilder<List<Comment>>(
            stream: widget.commentService
                .getRepliesStream(widget.place.id, comment.id),
            builder: (context, snapshot) {
              final replies = snapshot.data ?? [];
              final hasReplies = replies.isNotEmpty;

              if (!hasReplies) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(left: 44, top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ ปุ่มขยาย Replies
                    GestureDetector(
                      onTap: () => _toggleReplies(comment.id),
                      child: Row(
                        children: [
                          Icon(
                            isRepliesExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${replies.length} ການຕອບກັບ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ✅ แสดง replies เมื่อขยาย
                    if (isRepliesExpanded)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: replies.length,
                        itemBuilder: (context, rIndex) {
                          final reply = replies[rIndex];
                          final isReplyOwner = currentUser?.uid == reply.userId;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundImage: reply.userPhotoUrl.isNotEmpty
                                      ? NetworkImage(reply.userPhotoUrl)
                                      : const AssetImage('assets/default.jpg')
                                          as ImageProvider,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Stack(
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.only(
                                                left: 10,
                                                top: 6,
                                                bottom: 6,
                                                right: 32),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(reply.userName,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 11)),
                                                    Text(reply.timeAgo,
                                                        style: TextStyle(
                                                            fontSize: 9,
                                                            color: Colors
                                                                .grey[500])),
                                                  ],
                                                ),
                                                const SizedBox(height: 1),
                                                Text(reply.text,
                                                    style: const TextStyle(
                                                        fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          if (isReplyOwner || isAdmin)
                                            Positioned(
                                              top: 2,
                                              right: 2,
                                              child: PopupMenuButton<String>(
                                                icon: const Icon(
                                                    Icons.more_vert,
                                                    size: 16,
                                                    color: Colors.grey),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onSelected: (value) {
                                                  if (value == 'delete') {
                                                    _deleteComment(comment.id,
                                                        replyId: reply.id);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete,
                                                            color: Colors.red,
                                                            size: 14),
                                                        SizedBox(width: 6),
                                                        Text('ລົບ',
                                                            style: TextStyle(
                                                                color:
                                                                    Colors.red,
                                                                fontSize: 12)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 4, top: 2, right: 4),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                widget.commentService
                                                    .toggleLike(
                                                  widget.place.id,
                                                  comment.id,
                                                  true,
                                                  replyId: reply.id,
                                                );
                                              },
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    reply.likes.contains(
                                                            currentUser?.uid)
                                                        ? Icons.thumb_up
                                                        : Icons
                                                            .thumb_up_off_alt_outlined,
                                                    size: 12,
                                                    color: reply.likes.contains(
                                                            currentUser?.uid)
                                                        ? Colors.blue[700]
                                                        : Colors.grey[600],
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    reply.likes.contains(
                                                            currentUser?.uid)
                                                        ? 'ຖືກໃຈແລ້ວ'
                                                        : 'ຖືກໃຈ',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: reply.likes
                                                              .contains(
                                                                  currentUser
                                                                      ?.uid)
                                                          ? Colors.blue[700]
                                                          : Colors.grey[700],
                                                    ),
                                                  ),
                                                  if (reply
                                                      .likes.isNotEmpty) ...[
                                                    const SizedBox(width: 4),
                                                    Icon(Icons.thumb_up,
                                                        size: 9,
                                                        color:
                                                            Colors.blue[600]),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '${reply.likes.length}',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLiked = _selectedReaction.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0.5,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========== ຮູບພາບ ==========
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlaceDetailPage(
                        placeId: widget.place.id,
                        onAddToPlan: widget.onAddToPlan,
                      ),
                    ),
                  ),
                  child: Image.network(
                    widget.place.imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    alignment: Alignment(0, widget.place.imageAlignmentY),
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
              ),
              if ((widget.place.imageUrls?.length ?? 0) > 1)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.photo_library,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          '${widget.place.imageUrls!.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.isAdmin)
                Positioned(
                  top: 4,
                  right: 4,
                  child: PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 28,
                      shadows: [
                        Shadow(
                            color: Colors.black54,
                            blurRadius: 6,
                            offset: Offset(0, 2))
                      ],
                    ),
                    onSelected: (value) {
                      if (value == 'arrange_images') {
                        widget.onArrangeImages(widget.place);
                      } else if (value == 'set_cover') {
                        widget.onSetCover(widget.place);
                      } else {
                        widget.onDeletePlace(
                            widget.place.id, widget.place.name);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'arrange_images',
                        child: Row(children: [
                          Icon(Icons.swap_vert, color: Colors.teal),
                          SizedBox(width: 8),
                          Text('ຈັດຕຳແໜ່ງຮູບພາບ'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'set_cover',
                        child: Row(children: [
                          Icon(Icons.add_photo_alternate, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('ຕັ້ງເປັນຮູບໜ້າປົກ'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('ລົບ', style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // ========== ຊື່ສະຖານທີ່ ==========
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlaceDetailPage(
                        placeId: widget.place.id,
                        onAddToPlan: widget.onAddToPlan,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.place.name,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 15, color: Colors.redAccent),
                          const SizedBox(width: 4),
                          Text(widget.place.district,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ========== ຈຳນວນ Reaction ==========
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StreamBuilder<int>(
              stream: _reactionCountStream,
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return Row(
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                );
              },
            ),
          ),

          // ========== ປຸ່ມກົດ Reaction + Comment ==========
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ປຸ່ມ Reaction
                    CompositedTransformTarget(
                      link: _layerLink,
                      child: GestureDetector(
                        onLongPress: () {
                          _showReactionPicker(context);
                        },
                        onTap: () {
                          if (_selectedReaction.isNotEmpty) {
                            setState(() {
                              _selectedReaction = '';
                            });
                            _saveReaction();
                          } else {
                            _showReactionPicker(context);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 0),
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              if (_selectedReaction.isNotEmpty)
                                Text(_selectedReaction,
                                    style: const TextStyle(fontSize: 20))
                              else
                                const Icon(Icons.thumb_up_alt_outlined,
                                    color: Colors.grey, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                _selectedReaction.isNotEmpty
                                    ? EmojiStorage.getLabel(_selectedReaction)
                                    : 'ຖືກໃຈ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      isLiked ? Colors.blue : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 20),

                    // ປຸ່ມ Comment
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isCommentExpanded = !_isCommentExpanded;
                          if (_isCommentExpanded) {
                            _hasOpenedComments = true;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 0),
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            const Icon(Icons.comment_outlined,
                                color: Colors.grey, size: 20),
                            if (!_hasOpenedComments) ...[
                              const SizedBox(width: 6),
                              StreamBuilder<int>(
                                stream: _commentCountStream,
                                builder: (context, snapshot) {
                                  final count = snapshot.data ?? 0;
                                  if (count == 0)
                                    return const SizedBox.shrink();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ສະແດງອີ່ໂມຈິ 3 ອັນຫຼ້າສຸດ
                StreamBuilder<QuerySnapshot>(
                  stream: _recentReactionsStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                      return const SizedBox.shrink();

                    final allReactions = snapshot.data!.docs
                        .map((doc) =>
                            (doc.data() as Map<String, dynamic>)['reaction']
                                as String? ??
                            '')
                        .where((emoji) => emoji.isNotEmpty)
                        .toList();

                    if (allReactions.isEmpty) return const SizedBox.shrink();

                    final uniqueEmojis = allReactions.toSet().take(3).toList();

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: uniqueEmojis.map((emoji) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child:
                              Text(emoji, style: const TextStyle(fontSize: 16)),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ========== ສ່ວນສະແດງຄວາມຄິດເຫັນ (Comment Section) ==========
          if (_isCommentExpanded) ...[
            const Divider(height: 4, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  StreamBuilder<List<Comment>>(
                    stream: _commentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              color: Colors.teal,
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'ເກີດຂໍ້ຜິດພາດ: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final comments = snapshot.data ?? [];

                      if (comments.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'ຍັງບໍ່ມີຄຳເຫັນ',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          return _buildCommentItem(comments[index]);
                        },
                      );
                    },
                  ),

                  const Divider(height: 16, thickness: 0.5),

                  // ຊ່ອງພິມຄອມເມັ້ນ
                  Row(
                    children: [
                      StreamBuilder<DocumentSnapshot>(
                        stream: currentUser != null
                            ? FirebaseFirestore.instance
                                .collection('users')
                                .doc(currentUser.uid)
                                .snapshots()
                            : const Stream.empty(),
                        builder: (context, snapshot) {
                          String photoUrl = '';
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>?;
                            photoUrl = data?['photoURL'] ?? '';
                          }
                          if (photoUrl.isEmpty && currentUser != null) {
                            photoUrl = currentUser.photoURL ?? '';
                          }
                          return CircleAvatar(
                            radius: 18,
                            backgroundImage: photoUrl.isNotEmpty
                                ? NetworkImage(photoUrl)
                                : const AssetImage('assets/default.jpg')
                                    as ImageProvider,
                            child: photoUrl.isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.grey, size: 18)
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  focusNode: _commentFocusNode,
                                  decoration: const InputDecoration(
                                    hintText: 'ສະແດງຄຳເຫັນ...',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                  ),
                                  maxLines: null,
                                  textInputAction: TextInputAction.newline,
                                  onSubmitted: (_) => _sendComment(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send,
                                    color: Colors.teal, size: 20),
                                onPressed: _sendComment,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
