// place_detail.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place_model.dart';
import '../models/comment_model.dart';
import '../ci/comment_service.dart';
import '../routes/map.dart';
import '../admin/admin_add_place.dart';

class PlaceDetailPage extends StatefulWidget {
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
  // ── Image ──
  int _currentImageIndex = 0;
  late PageController _pageController;

  // ── Comment ──
  final CommentService _commentService = CommentService();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isReplying = false;
  String? _replyingToCommentId;
  String? _replyingToUserName;
  
  // ── Reply Expansion ──
  final Set<String> _expandedReplies = {};

  // ── Reaction ──
  final Map<String, String> _userReactions = {}; // commentId -> reaction
  final Map<String, Map<String, int>> _reactionCounts = {}; // commentId -> {reaction: count}

  // ── Stream ──
  late final Stream<DocumentSnapshot> _placeStream;

  // Reaction Emojis
  static const List<Map<String, dynamic>> _reactions = [
    {'emoji': '👍', 'label': 'ຊອບ'},
    {'emoji': '❤️', 'label': 'ຮັກ'},
    {'emoji': '😂', 'label': 'ຂີ້ຫົວ'},
    {'emoji': '😮', 'label': 'ຕົກໃຈ'},
    {'emoji': '😢', 'label': 'ເສົ້າ'},
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _placeStream = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.placeId)
        .snapshots();
    _loadReactions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  // ── Load Reactions from Firebase ──
  void _loadReactions() {
    FirebaseFirestore.instance
        .collection('places')
        .doc(widget.placeId)
        .collection('comments')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('reactions')) {
          final reactions = Map<String, int>.from(data['reactions'] ?? {});
          _reactionCounts[doc.id] = reactions;
        }
      }
      if (mounted) setState(() {});
    });
  }

  // ── Methods ──
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

  // ── Reaction Methods ──
  Future<void> _toggleReaction(String commentId, String emoji) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final commentRef = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.placeId)
        .collection('comments')
        .doc(commentId);

    final doc = await commentRef.get();
    if (!doc.exists) return;

    final data = doc.data()!;
    Map<String, int> reactions = Map<String, int>.from(data['reactions'] ?? {});
    String? currentReaction = _userReactions[commentId];

    // If same reaction, remove it (toggle off)
    if (currentReaction == emoji) {
      reactions[emoji] = (reactions[emoji] ?? 1) - 1;
      if (reactions[emoji] == 0) reactions.remove(emoji);
      _userReactions.remove(commentId);
    } else {
      // Remove old reaction if exists
      if (currentReaction != null) {
        reactions[currentReaction] = (reactions[currentReaction] ?? 1) - 1;
        if (reactions[currentReaction] == 0) reactions.remove(currentReaction);
      }
      // Add new reaction
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      _userReactions[commentId] = emoji;
    }

    await commentRef.update({'reactions': reactions});
    _reactionCounts[commentId] = reactions;
    if (mounted) setState(() {});
  }

  Future<void> _showReactionPicker(String commentId, Offset position) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          position,
          position,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        ..._reactions.map((reaction) => PopupMenuItem<String>(
          value: reaction['emoji'],
          child: Row(
            children: [
              Text(reaction['emoji'], style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(reaction['label']),
            ],
          ),
        )),
        const PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('ລຶບຄວາມຮູ້ສຶກ'),
            ],
          ),
        ),
      ],
      elevation: 8,
    );

    if (result != null) {
      if (result == 'remove') {
        await _removeReaction(commentId);
      } else {
        await _toggleReaction(commentId, result);
      }
    }
  }

  Future<void> _removeReaction(String commentId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final commentRef = FirebaseFirestore.instance
        .collection('places')
        .doc(widget.placeId)
        .collection('comments')
        .doc(commentId);

    final doc = await commentRef.get();
    if (!doc.exists) return;

    final data = doc.data()!;
    Map<String, int> reactions = Map<String, int>.from(data['reactions'] ?? {});
    String? currentReaction = _userReactions[commentId];

    if (currentReaction != null) {
      reactions[currentReaction] = (reactions[currentReaction] ?? 1) - 1;
      if (reactions[currentReaction] == 0) reactions.remove(currentReaction);
      _userReactions.remove(commentId);
      await commentRef.update({'reactions': reactions});
      _reactionCounts[commentId] = reactions;
      if (mounted) setState(() {});
    }
  }

  // ── Comment Methods ──
  void _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    try {
      if (_isReplying && _replyingToCommentId != null) {
        await _commentService.addReply(
          widget.placeId,
          _replyingToCommentId!,
          text,
        );
        setState(() {
          _isReplying = false;
          _replyingToCommentId = null;
          _replyingToUserName = null;
        });
      } else {
        await _commentService.addComment(widget.placeId, text);
      }
      _commentController.clear();
      _commentFocusNode.unfocus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteComment(String placeId, String commentId, {String? replyId}) {
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
              await _commentService.deleteComment(placeId, commentId, replyId: replyId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ລົບຄຳເຫັນສຳເລັດ')),
                );
              }
            },
            child: const Text('ຢືນຢັນ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _cancelReply() {
    setState(() {
      _isReplying = false;
      _replyingToCommentId = null;
      _replyingToUserName = null;
    });
  }

  void _toggleReplies(String commentId) {
    setState(() {
      if (_expandedReplies.contains(commentId)) {
        _expandedReplies.remove(commentId);
      } else {
        _expandedReplies.add(commentId);
      }
    });
  }

  // ── Build Reaction Widget ──
  Widget _buildReactions(String commentId) {
    final reactions = _reactionCounts[commentId] ?? {};
    final currentUser = FirebaseAuth.instance.currentUser;
    final userReaction = _userReactions[commentId];

    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sort reactions by count
    final sortedReactions = reactions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Get top 3 reactions
    final topReactions = sortedReactions.take(3).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...topReactions.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                entry.key,
                style: const TextStyle(fontSize: 14),
              ),
            );
          }),
          if (reactions.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                '+${reactions.length - 3}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ),
          const SizedBox(width: 4),
          Text(
            '${reactions.values.reduce((a, b) => a + b)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ── Build Comment Widgets (Facebook Style) ──
  Widget _buildCommentItem(Comment comment, {required String placeId}) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == comment.userId;
    final isAdmin = currentUser?.email == 'admin_app@travel.com' ||
        currentUser?.email == 'admin_app';
    final isLiked = comment.likes.contains(currentUser?.uid);
    final hasReplies = comment.replies.isNotEmpty;
    final isExpanded = _expandedReplies.contains(comment.id);
    final hasReaction = _userReactions.containsKey(comment.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundImage: comment.userPhotoUrl.isNotEmpty
                ? NetworkImage(comment.userPhotoUrl)
                : const AssetImage('assets/default.jpg') as ImageProvider,
            child: comment.userPhotoUrl.isEmpty
                ? const Icon(Icons.person, size: 20, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Comment Bubble (Facebook style)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User Name
                      Text(
                        comment.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Comment Text
                      Text(
                        comment.text,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // Show Reactions
                if (_reactionCounts.containsKey(comment.id) && 
                    (_reactionCounts[comment.id]?.isNotEmpty ?? false))
                  _buildReactions(comment.id),
                const SizedBox(height: 4),
                // Action Buttons (Facebook style)
                Row(
                  children: [
                    // Like Button (เปลี่ยนเป็นปุ่มกดค้างแสดง Reaction)
                    GestureDetector(
                      onLongPress: () {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final position = box.localToGlobal(Offset.zero);
                        _showReactionPicker(comment.id, position);
                      },
                      onTap: () {
                        // ถ้ามี Reaction อยู่แล้ว ให้ลบ
                        if (hasReaction) {
                          _removeReaction(comment.id);
                        } else {
                          // ถ้าไม่มี ให้ใช้ Like (👍)
                          _toggleReaction(comment.id, '👍');
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            hasReaction 
                                ? Icons.emoji_emotions 
                                : Icons.thumb_up_alt_outlined,
                            size: 14,
                            color: hasReaction ? Colors.blue : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          if (hasReaction)
                            Text(
                              _userReactions[comment.id] ?? '',
                              style: const TextStyle(fontSize: 14),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Reply Button
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isReplying = true;
                          _replyingToCommentId = comment.id;
                          _replyingToUserName = comment.userName;
                        });
                        _commentFocusNode.requestFocus();
                      },
                      child: Text(
                        'ຕອບ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Time Ago
                    Text(
                      comment.timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                    const Spacer(),
                    // Delete Button
                    if (isOwner || isAdmin)
                      GestureDetector(
                        onTap: () => _deleteComment(placeId, comment.id),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                // ── Replies Section ──
                if (hasReplies) ...[
                  const SizedBox(height: 4),
                  // Show/Hide Replies Button
                  GestureDetector(
                    onTap: () => _toggleReplies(comment.id),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpanded
                              ? 'ເຊື່ອງຄຳຕອບ'
                              : '${comment.replies.length} ຄຳຕອບ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Reply List
                  if (isExpanded) ...[
                    const SizedBox(height: 6),
                    ...comment.replies.map(
                      (reply) => _buildReplyItem(
                        reply,
                        placeId: placeId,
                        commentId: comment.id,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(
    Comment reply, {
    required String placeId,
    required String commentId,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == reply.userId;
    final isAdmin = currentUser?.email == 'admin_app@travel.com' ||
        currentUser?.email == 'admin_app';
    final isLiked = reply.likes.contains(currentUser?.uid);
    final hasReaction = _userReactions.containsKey(reply.id);

    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundImage: reply.userPhotoUrl.isNotEmpty
                ? NetworkImage(reply.userPhotoUrl)
                : const AssetImage('assets/default.jpg') as ImageProvider,
            child: reply.userPhotoUrl.isEmpty
                ? const Icon(Icons.person, size: 16, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reply Bubble (Facebook style)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reply.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        reply.text,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // Show Reactions for reply
                if (_reactionCounts.containsKey(reply.id) && 
                    (_reactionCounts[reply.id]?.isNotEmpty ?? false))
                  _buildReactions(reply.id),
                const SizedBox(height: 2),
                // Action Buttons
                Row(
                  children: [
                    // Like Button (เปลี่ยนเป็น Reaction)
                    GestureDetector(
                      onLongPress: () {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final position = box.localToGlobal(Offset.zero);
                        _showReactionPicker(reply.id, position);
                      },
                      onTap: () {
                        if (hasReaction) {
                          _removeReaction(reply.id);
                        } else {
                          _toggleReaction(reply.id, '👍');
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            hasReaction 
                                ? Icons.emoji_emotions 
                                : Icons.thumb_up_alt_outlined,
                            size: 12,
                            color: hasReaction ? Colors.blue : Colors.grey[600],
                          ),
                          const SizedBox(width: 2),
                          if (hasReaction)
                            Text(
                              _userReactions[reply.id] ?? '',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Time Ago
                    Text(
                      reply.timeAgo,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                    const Spacer(),
                    // Delete Button
                    if (isOwner || isAdmin)
                      GestureDetector(
                        onTap: () => _deleteComment(
                          placeId,
                          commentId,
                          replyId: reply.id,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Main Build ──
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _placeStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.teal),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              title: const Text('ບໍ່ພົບຂໍ້ມູນ'),
            ),
            body: const Center(
              child: Text('ສະຖານທີ່ຖືກລົບແລ້ວ ຫຼືບໍ່ພົບຂໍ້ມູນ'),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final place = Place.fromMap(widget.placeId, data);
        final images = _getAllImages(place);

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
                // ── Image Slideshow ──
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
                                    index,
                                    images,
                                  ),
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
                                        child: Icon(
                                          Icons.broken_image,
                                          size: 80,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : const SizedBox(
                              height: 260,
                              child: Center(
                                child: Icon(Icons.broken_image, size: 80),
                              ),
                            ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            "${_currentImageIndex + 1} / ${images.length}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                // ── Thumbnails ──
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
                                        spreadRadius: 1,
                                      )
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
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      color: Colors.teal.withOpacity(0.15),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // ── Info ──
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            place.district,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "ລາຍລະອຽດ",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(place.description),
                      const SizedBox(height: 24),

                      // ── Map Preview ──
                      const Text(
                        "ຕຳແໜ່ງສະຖານທີ່",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                                    place.latitude,
                                    place.longitude,
                                  ),
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
                                          place.latitude,
                                          place.longitude,
                                        ),
                                        width: 40,
                                        height: 40,
                                        child: const Icon(
                                          Icons.location_pin,
                                          color: Colors.red,
                                          size: 40,
                                        ),
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

                      // ── Extra Places ──
                      if (place.extraPlaces != null &&
                          place.extraPlaces!.isNotEmpty) ...[
                        const Text(
                          "ຂໍ້ມູນອື່ນໆ",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                        left: Radius.circular(12),
                                      ),
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
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            )
                                          : Container(
                                              width: 90,
                                              height: 90,
                                              color: Colors.grey.shade200,
                                              child: const Icon(
                                                Icons.image_not_supported,
                                                color: Colors.grey,
                                              ),
                                            ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              extra.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (extra.description.isNotEmpty)
                                              Text(
                                                extra.description,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: const [
                                                Icon(
                                                  Icons.directions,
                                                  color: Colors.teal,
                                                  size: 16,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'ນຳທາງໄປຈຸດນີ້',
                                                  style: TextStyle(
                                                    color: Colors.teal,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
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

                      // ── Add to Plan Button ──
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

                      // ═══════════════════════════════════════════════════
                      // ── COMMENT SECTION (Facebook Style) ──
                      // ═══════════════════════════════════════════════════
                      const SizedBox(height: 24),
                      const Divider(thickness: 1),
                      const SizedBox(height: 12),
                      
                      // Comment Header
                      Row(
                        children: [
                          const Text(
                            'ຄຳເຫັນ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('places')
                                .doc(widget.placeId)
                                .collection('comments')
                                .snapshots(),
                            builder: (context, snapshot) {
                              final count = snapshot.data?.docs.length ?? 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$count ຄຳເຫັນ',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Comment Input (Facebook Style) ──
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Avatar
                            StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseAuth.instance.currentUser != null
                                  ? FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(FirebaseAuth.instance.currentUser!.uid)
                                      .snapshots()
                                  : const Stream.empty(),
                              builder: (context, snapshot) {
                                String photoUrl = '';
                                if (snapshot.hasData && snapshot.data!.exists) {
                                  final data = snapshot.data!.data()
                                      as Map<String, dynamic>?;
                                  photoUrl = data?['photoURL'] ?? '';
                                }
                                if (photoUrl.isEmpty &&
                                    FirebaseAuth.instance.currentUser != null) {
                                  photoUrl = FirebaseAuth
                                      .instance.currentUser?.photoURL ?? '';
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundImage: photoUrl.isNotEmpty
                                        ? NetworkImage(photoUrl)
                                        : const AssetImage('assets/default.jpg')
                                            as ImageProvider,
                                    child: photoUrl.isEmpty
                                        ? const Icon(
                                            Icons.person,
                                            color: Colors.grey,
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Reply indicator
                                  if (_isReplying)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.reply,
                                            size: 12,
                                            color: Colors.blue,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'ຕອບກັບ @$_replyingToUserName',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _cancelReply,
                                            child: const Icon(
                                              Icons.close,
                                              size: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  TextField(
                                    controller: _commentController,
                                    focusNode: _commentFocusNode,
                                    decoration: InputDecoration(
                                      hintText: _isReplying
                                          ? 'ຕອບກັບ @$_replyingToUserName...'
                                          : 'ຂຽນຄຳເຫັນ...',
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      hintStyle: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 14,
                                      ),
                                    ),
                                    maxLines: null,
                                    textInputAction: TextInputAction.newline,
                                    onSubmitted: (_) => _sendComment(),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: Colors.blue,
                              ),
                              onPressed: _sendComment,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── List Comments ──
                      StreamBuilder<List<Comment>>(
                        stream: _commentService.getComments(widget.placeId),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: Colors.teal,
                                ),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  'ເກີດຂໍ້ຜິດພາດ: ${snapshot.error}',
                                ),
                              ),
                            );
                          }

                          final comments = snapshot.data ?? [];

                          if (comments.isEmpty) {
                            return Center(
                              child: Container(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 50,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'ຍັງບໍ່ມີຄຳເຫັນ',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ເປັນຄົນທຳອິດທີ່ສະແດງຄວາມຄິດເຫັນ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              return _buildCommentItem(
                                comment,
                                placeId: widget.placeId,
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 32),
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
  State<FullscreenImageViewer> createState() =>
      _FullscreenImageViewerState();
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${_currentIndex + 1} / ${widget.images.length}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}