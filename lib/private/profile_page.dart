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
import '../auth/login_screen.dart';
import '../ci/comment_service.dart';
import '../models/comment_model.dart';
import '../ci/reaction_picker.dart';
import '../models/emoji_storage.dart';
import '../models/place_model.dart';

import '../chats/inquiry_button.dart';
import '../chats/chat_list_screen.dart';

class ProfilePage extends StatefulWidget {
  final String? targetUserId;
  final Function(Place)? onAddToPlan;

  const ProfilePage({
    super.key, 
    this.targetUserId,
    this.onAddToPlan,
  });

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

  void _defaultOnAddToPlan(Place place) {
    debugPrint('Add to plan: ${place.name}');
  }

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

  // ─── Widget สำหรับไอคอนแชทพร้อม Badge ───
  Widget _buildChatIconWithBadge() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Icon(Icons.chat_bubble_outline, color: Colors.white);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        int totalUnread = 0;
        
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
            final userUnread = unreadCounts[currentUser.uid] as int? ?? 0;
            totalUnread += userUnread;
          }
        }

        return Stack(
          children: [
            const Icon(Icons.chat_bubble_outline, color: Colors.white),
            if (totalUnread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    totalUnread > 99 ? '99+' : '$totalUnread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ─── Widget สำหรับปุ่ม Inquiry พร้อม Badge ───
  Widget _buildInquiryButtonWithBadge(String targetId, String displayName, String photoUrl) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return InquiryButton(
        targetUserId: targetId,
        targetName: displayName,
        targetPhotoUrl: photoUrl,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        int unreadWithThisUser = 0;
        
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final participants = List<String>.from(data['participants'] ?? []);
            if (participants.contains(targetId) && participants.contains(currentUser.uid)) {
              final unreadCounts = Map<String, dynamic>.from(data['unreadCounts'] ?? {});
              unreadWithThisUser = (unreadCounts[currentUser.uid] ?? 0).toInt();
              break;
            }
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            InquiryButton(
              targetUserId: targetId,
              targetName: displayName,
              targetPhotoUrl: photoUrl,
            ),
            if (unreadWithThisUser > 0)
              Positioned(
                right: -4,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    unreadWithThisUser > 99 ? '99+' : '$unreadWithThisUser',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
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
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
      await FirebaseAuth.instance.signOut();
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

    final photoUrl = userData!['photoUrl'] ?? userData!['photoURL'] ?? '';
    final coverUrl = userData!['coverUrl'] ?? userData!['coverURL'] ?? '../assets/default.jpg';
    final displayName = userData!['displayName'] ?? 'User';
    final bio = userData!['bio'] ?? '';
    
    final onAddToPlan = widget.onAddToPlan ?? _defaultOnAddToPlan;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("ໂພຣໄຟລ໌"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (!isMe && targetId != null)
            IconButton(
              icon: _buildChatIconWithBadge(),
              onPressed: () {
                final inquiryBtn = InquiryButton(
                  targetUserId: targetId!,
                  targetName: displayName,
                  targetPhotoUrl: photoUrl,
                );
                inquiryBtn.openChat(context);
              },
              tooltip: 'ສົ່ງຂໍ້ຄວາມ',
            ),
          if (isMe)
            IconButton(
              icon: _buildChatIconWithBadge(),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChatListScreen()),
                );
              },
              tooltip: 'ແຊດຂອງທ່ານ',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'edit' && isMe) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EditProfilePage()),
                );
              } else if (value == 'logout' && isMe) {
                _logout();
              } else if (value == 'chat' && !isMe && targetId != null) {
                final inquiryBtn = InquiryButton(
                  targetUserId: targetId!,
                  targetName: displayName,
                  targetPhotoUrl: photoUrl,
                );
                inquiryBtn.openChat(context);
              }
            },
            itemBuilder: (BuildContext context) => [
              if (isMe)
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.blue, size: 20),
                      SizedBox(width: 12),
                      Text('ແກ້ໄຂໂພຣໄຟລ໌', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              if (!isMe)
                PopupMenuItem<String>(
                  value: 'chat',
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, color: Colors.teal, size: 20),
                      const SizedBox(width: 12),
                      Text('ສົ່ງຂໍ້ຄວາມຫາ $displayName', style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              if (isMe)
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red, size: 20),
                      SizedBox(width: 12),
                      Text('ອອກຈາກລະບົບ', style: TextStyle(fontSize: 14, color: Colors.red)),
                    ],
                  ),
                ),
            ],
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

                  // ─── ปุ่มแชทพร้อม Badge ───
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!isMe && targetId != null) ...[
                          Expanded(
                            child: _buildInquiryButtonWithBadge(targetId!, displayName, photoUrl),
                          ),
                        ],
                      ],
                    ),
                  ),
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

            // ─── ໂພສຕ໌ທີ່ແຊຣ໌ ───
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

                  final posts = snapshot.data!.docs.toList();
                  posts.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime = aData['createdAt'] as Timestamp?;
                    final bTime = bData['createdAt'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: posts.length,
                    itemBuilder: (context, index) {
                      final data = posts[index].data() as Map<String, dynamic>;
                      final postId = posts[index].id;
                      data['id'] = postId;
                      
                      return _UserPostCard(
                        key: ValueKey(postId),
                        postData: data,
                        postId: postId,
                        onAddToPlan: onAddToPlan,
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
}

// ─── User Post Card ───
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
  
  bool _isCommentExpanded = false;
  bool _hasOpenedComments = false;
  
  String? _replyingToCommentId;
  String? _replyingToUserName;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  
  final Map<String, bool> _expandedReplies = {};
  
  String _selectedReaction = '';
  final LayerLink _layerLink = LayerLink();
  
  late final TextEditingController _commentController;
  late final FocusNode _commentFocusNode;
  
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
                                    : '',
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

// ─── Image Grid Helper ───
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

// ─── Highlight Viewer ───
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

// ─── UserAllPostsPage ───
class UserAllPostsPage extends StatelessWidget {
  final String userId;
  final Function(Place) onAddToPlan;

  const UserAllPostsPage({
    super.key,
    required this.userId,
    required this.onAddToPlan,
  });

  @override
  Widget build(BuildContext context) {
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