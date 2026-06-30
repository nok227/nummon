import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place_model.dart';
import 'place_detail.dart';
import '../routes/map.dart';
import '../ci/comment_service.dart';
import '../models/comment_model.dart';
import '../ci/reaction_picker.dart';
import '../models/emoji_storage.dart';

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

  final CommentService _commentService = CommentService();

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

  final CommentService _commentService = CommentService();
  
  // Comment state
  bool _isCommentExpanded = false;
  bool _hasOpenedComments = false;
  
  // Reply state
  String? _replyingToCommentId;
  String? _replyingToUserName;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  
  // Expanded replies
  final Map<String, bool> _expandedReplies = {};
  
  // Reaction
  String _selectedReaction = '';
  final LayerLink _layerLink = LayerLink();
  
  // Comment input
  late final TextEditingController _commentController;
  late final FocusNode _commentFocusNode;
  
  // Streams
  late final Stream<List<Comment>> _commentsStream;
  late final Stream<int> _commentCountStream;
  late final Stream<int> _reactionCountStream;
  late final Stream<QuerySnapshot> _recentReactionsStream;

  OverlayEntry? _reactionOverlayEntry;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
    _commentFocusNode = FocusNode();
    
    // Use postId as placeId for comments
    final placeId = widget.postId;
    
    _commentsStream = _commentService.getComments(placeId);
    _commentCountStream = FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
        .collection('comments')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
    _reactionCountStream = FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
        .collection('reactions')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
    _recentReactionsStream = FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
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
                postId: widget.postId,
                placeId: widget.postId,
                layerLink: _layerLink,
                onEmojiSelected: (emoji) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      if (_selectedReaction == emoji) {
                        _selectedReaction = '';
                      } else {
                        _selectedReaction = emoji;
                      }
                    });
                    _saveReaction();
                  });
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
                postId: widget.postId,
                placeId: widget.postId,
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

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUserName = null;
      _replyController.clear();
      _replyFocusNode.unfocus();
    });
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _replyingToCommentId == null) return;

    try {
      await _commentService.addReply(
        widget.postId,
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

  void _toggleReplies(String commentId) {
    setState(() {
      _expandedReplies[commentId] = !(_expandedReplies[commentId] ?? false);
    });
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    try {
      await _commentService.addComment(widget.postId, text);
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
              await _commentService
                  .deleteComment(widget.postId, commentId, replyId: replyId);
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
          .doc(widget.postId)
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
          .doc(widget.postId)
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

  // ─── Build Comment Item ───
  Widget _buildCommentItem(Comment comment) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == comment.userId;
    final isAdmin = currentUser?.email == 'admin_app@travel.com' ||
        currentUser?.email == 'admin_app';

    final isReplying = _replyingToCommentId == comment.id;
    final isRepliesExpanded = _expandedReplies[comment.id] ?? false;
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
                              Padding(
                                padding: const EdgeInsets.only(right: 26),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        comment.userName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 16,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              CompositedTransformTarget(
                                link: commentLayerLink,
                                child: GestureDetector(
                                  onLongPress: () {
                                    _showCommentReactionPicker(
                                      context,
                                      commentLayerLink,
                                      comment.id,
                                      (emoji) {
                                        FirebaseFirestore.instance
                                            .collection('places')
                                            .doc(widget.postId)
                                            .collection('reactions')
                                            .doc(currentUser?.uid)
                                            .set({
                                          'reaction': emoji,
                                          'userId': currentUser?.uid,
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                        setState(() {});
                                      },
                                    );
                                  },
                                  onTap: () {
                                    _commentService.toggleLike(
                                      widget.postId,
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Reply input
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
          // Replies
          StreamBuilder<List<Comment>>(
            stream: _commentService
                .getRepliesStream(widget.postId, comment.id),
            builder: (context, snapshot) {
              final replies = snapshot.data ?? [];
              final hasReplies = replies.isNotEmpty;

              if (!hasReplies) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(left: 44, top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                                _commentService
                                                    .toggleLike(
                                                  widget.postId,
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

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays} ວັນກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ບໍ່ດົນມານີ້';
  }

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid ?? '';
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
    final isLiked = _selectedReaction.isNotEmpty;

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
                                      latitude: latitude ?? 0.0,
                                      longitude: longitude ?? 0.0,
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

          // ─── Reaction Count ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

          // ─── Reaction + Comment Buttons ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                            const SizedBox(width: 4),
                            Text(
                              'ຄວາມຄິດເຫັນ',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700]),
                            ),
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

          const SizedBox(height: 4),

          // ─── Comment Section ───
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

                  // ─── Comment Input ───
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

// ─── UserAllPostsPage (ต้อง import CommentService ด้วย) ───
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
                              return _UserPostCard(
                                key: ValueKey(postId),
                                postData: data,
                                postId: postId,
                                onAddToPlan: onAddToPlan,
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