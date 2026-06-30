import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:crypto/crypto.dart';
import 'package:video_compress/video_compress.dart';
import '../models/api_Cloudinary.dart';
import 'story_preview_page.dart';
import '../private/profile_page.dart';
// ✅ เพิ่ม import สำหรับแชท
import '../chats/chat_screen.dart';

// ---------------------------------------------------------
// ฟังก์ชันสกัดภาพกึ่งกลางเพื่อใช้เป็นภาพหน้าปก (เวอร์ชันปรับปรุงสมบูรณ์)
// ---------------------------------------------------------
String getMiddleFrameThumbnail(String url) {
  if (url.isEmpty) return url;

  String cleanUrl = url.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');

  const marker = '/upload/';
  final idx = cleanUrl.indexOf(marker);
  if (idx == -1) return cleanUrl;

  final baseUrl = cleanUrl.substring(0, idx + marker.length);
  final remaining = cleanUrl.substring(idx + marker.length);

  final versionRegex = RegExp(r'v\d+/');
  final match = versionRegex.firstMatch(remaining);

  if (match != null) {
    final afterVersion = remaining.substring(match.start);
    return baseUrl + 'so_50p,f_auto,q_auto/' + afterVersion;
  } else {
    List<String> segments = remaining.split('/');
    segments.removeWhere((seg) =>
        seg.contains('so_') ||
        seg.contains('eo_') ||
        seg.contains('vc_') ||
        seg.contains('f_') ||
        seg.contains('q_'));
    return baseUrl + 'so_50p,f_auto,q_auto/' + segments.join('/');
  }
}

// ---------------------------------------------------------
// ฟังก์ชันลบไฟล์ออกจาก Cloudinary
// ---------------------------------------------------------
Future<void> deleteFromCloudinary(String url, bool isVideo) async {
  try {
    final cloudName = CloudinaryConfig.cloudinaryCloudName;
    final apiKey = CloudinaryConfig.cloudinaryApiKey;
    final apiSecret = CloudinaryConfig.cloudinaryApiSecret;

    Uri uri = Uri.parse(url);
    List<String> segments = uri.pathSegments;
    int uploadIndex = segments.indexOf('upload');
    if (uploadIndex == -1) return;

    List<String> publicIdSegments = [];
    for (int i = uploadIndex + 1; i < segments.length; i++) {
      if (RegExp(r'^v\d+$').hasMatch(segments[i])) continue;
      if (segments[i].contains('so_') ||
          segments[i].contains('eo_') ||
          segments[i].contains('f_') ||
          segments[i].contains('q_') ||
          segments[i].contains('vc_')) {
        continue;
      }
      publicIdSegments.add(segments[i]);
    }

    String publicIdWithExtension = publicIdSegments.join('/');
    String publicId = publicIdWithExtension;

    if (publicIdWithExtension.contains('.')) {
      publicId = publicIdWithExtension.substring(
          0, publicIdWithExtension.lastIndexOf('.'));
    }

    if (publicId.isEmpty) return;

    final timestamp =
        (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
    final stringToSign = "public_id=$publicId&timestamp=$timestamp$apiSecret";
    final bytes = utf8.encode(stringToSign);
    final digest = sha1.convert(bytes);
    final signature = digest.toString();

    final resourceType = isVideo ? "video" : "image";
    final deleteUri = Uri.parse(
        "https://api.cloudinary.com/v1_1/$cloudName/$resourceType/destroy");

    final response = await http.post(deleteUri, body: {
      'public_id': publicId,
      'api_key': apiKey,
      'timestamp': timestamp,
      'signature': signature,
    });

    if (response.statusCode == 200) {
      debugPrint("✅ ລົບໄຟລ໌ອອກຈາກ Cloudinary ສຳເລັດ: $publicId");
    } else {
      debugPrint("❌ ລົບ Cloudinary ຜິດພາດ: ${response.body}");
    }
  } catch (e) {
    debugPrint("Cloudinary delete error: $e");
  }
}

// ---------------------------------------------------------
// ສ່ວນສະແດງຜົນຫຼັກ
// ---------------------------------------------------------
class StorySection extends StatefulWidget {
  const StorySection({super.key});

  @override
  State<StorySection> createState() => _StorySectionState();
}

class _StorySectionState extends State<StorySection> {
  bool isUploadingStory = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cleanupExpiredStories();
  }

  Future<void> _cleanupExpiredStories() async {
    try {
      final expiredDocs = await FirebaseFirestore.instance
          .collection('stories')
          .where('expireAt', isLessThan: Timestamp.now())
          .get();

      if (expiredDocs.docs.isEmpty) return;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final doc in expiredDocs.docs) {
        final data = doc.data();
        final String? url = data['storyImage'];
        final bool isVideo = data['mediaType'] == 'video';

        if (url != null && url.isNotEmpty) {
          await deleteFromCloudinary(url, isVideo);
        }

        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint("✅ ສຳເລັດການລົບສະຕໍຣີ່ທີ່ໝົດອາຍຸ");
    } catch (e) {
      debugPrint('cleanupExpiredStories error: $e');
    }
  }

  Future<void> _createNewStory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("ກະລຸນາເຂົ້າສູ່ລະບົບກ່ອນ", isError: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.teal),
              title: const Text("ອັບໂຫຼດຮູບພາບ"),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadMedia(isVideo: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.pink),
              title: const Text("ອັບໂຫຼດວິດີໂອສັ້ນ"),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadMedia(isVideo: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadMedia({required bool isVideo}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    String userAvatar = user.photoURL ?? '';
    if (userDoc.exists && userDoc.data()?['photoUrl'] != null) {
      userAvatar = userDoc.data()!['photoUrl'].toString();
    }

    XFile? file;
    if (isVideo) {
      file = await _picker.pickVideo(source: ImageSource.gallery);
    } else {
      file = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70);
    }

    if (file == null) return;
    if (!mounted) return;

    String displayName = user.displayName ?? "ນັກທ່ອງທ່ຽວ";
    if (userDoc.exists && userDoc.data()?['displayName'] != null) {
      displayName = userDoc.data()!['displayName'];
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryPreviewPage(
          file: file!,
          isVideo: isVideo,
          onShare: (editFile, startSeconds, endSeconds) {
            _uploadStory(
              file: editFile,
              isVideo: isVideo,
              userAvatar: userAvatar,
              displayName: displayName,
              startSeconds: startSeconds,
              endSeconds: endSeconds,
            );
          },
        ),
      ),
    );
  }

  Future<void> _uploadStory({
    required XFile file,
    required bool isVideo,
    required String userAvatar,
    required String displayName,
    double? startSeconds,
    double? endSeconds,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => isUploadingStory = true);

    try {
      String uploadedUrl = await _uploadToCloudinary(
        file,
        isVideo,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
      );

      await FirebaseFirestore.instance.collection('stories').add({
        'userId': user.uid,
        'userName': displayName,
        'userAvatar': userAvatar,
        'storyImage': uploadedUrl,
        'mediaType': isVideo ? 'video' : 'image',
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      });

      _showSnackBar("ສ້າງສະຕໍຣີ່ສຳເລັດ! 🎉", isError: false);
    } catch (e) {
      _showSnackBar("ເກີດຂໍ້ຜິດພາດ: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => isUploadingStory = false);
    }
  }

  Future<String> _uploadToCloudinary(
    XFile file,
    bool isVideo, {
    double? startSeconds,
    double? endSeconds,
  }) async {
    final cloudName = CloudinaryConfig.cloudinaryCloudName;
    final uploadPreset = CloudinaryConfig.cloudinaryUploadPreset;

    File fileToUpload = File(file.path);

    if (isVideo) {
      try {
        final info = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );
        if (info != null && info.file != null) {
          fileToUpload = info.file!;
        }
      } catch (e) {
        debugPrint("Video compress error: $e");
      }
    }

    final resourceType = isVideo ? "video" : "image";
    final uri = Uri.parse(
        "https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload");

    final request = http.MultipartRequest("POST", uri);
    request.fields['upload_preset'] = uploadPreset;
    request.files
        .add(await http.MultipartFile.fromPath('file', fileToUpload.path));

    final response = await request.send();

    if (isVideo) {
      VideoCompress.deleteAllCache();
    }

    if (response.statusCode != 200) {
      final errorResponse = await response.stream.bytesToString();
      debugPrint("❌ Cloudinary Upload Error: $errorResponse");
      throw Exception("ອັບໂຫຼດລົ້ມເຫຼວ (Code: ${response.statusCode})");
    }

    final responseData = await response.stream.toBytes();
    final jsonMap = jsonDecode(String.fromCharCodes(responseData));
    String url = jsonMap['secure_url'];

    if (isVideo && startSeconds != null && endSeconds != null) {
      url = _applyVideoTrimTransformation(url, startSeconds, endSeconds);
    }

    return url;
  }

  String _applyVideoTrimTransformation(
      String url, double startSeconds, double endSeconds) {
    const marker = '/upload/';
    final idx = url.indexOf(marker);
    if (idx == -1) return url;

    final insertPos = idx + marker.length;
    final transformation =
        'so_${startSeconds.toStringAsFixed(2)},eo_${endSeconds.toStringAsFixed(2)},f_mp4,q_auto,vc_h264/';
    return url.substring(0, insertPos) +
        transformation +
        url.substring(insertPos);
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  void _openStoryGroupViewer(List<UserStoryGroup> groups, int initialGroupIdx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FacebookStoryViewer(
            storyGroups: groups, initialGroupIndex: initialGroupIdx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
            padding: EdgeInsets.only(left: 20, top: 20, bottom: 10),
            child: Text("ສະຕໍຣີ່ (Stories)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        Container(
          height: 190,
          padding: const EdgeInsets.only(left: 16),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('stories')
                .where('expireAt', isGreaterThan: Timestamp.now())
                .snapshots(),
            builder: (context, snapshot) {
              List<Widget> storyWidgets = [];

              storyWidgets.add(
                GestureDetector(
                  onTap: isUploadingStory ? null : _createNewStory,
                  child: Container(
                    width: 110,
                    margin: const EdgeInsets.only(right: 8, bottom: 5, top: 5),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ]),
                    child: Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16)),
                                  child: Image.asset('assets/default.jpg',
                                      width: double.infinity,
                                      fit: BoxFit.cover)),
                              Positioned(
                                bottom: -18,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Colors.white,
                                    child: CircleAvatar(
                                      radius: 15,
                                      backgroundColor: Colors.blue[600],
                                      child: isUploadingStory
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2))
                                          : const Icon(Icons.add,
                                              color: Colors.white, size: 20),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                            flex: 1,
                            child: Container(
                                alignment: Alignment.bottomCenter,
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                    isUploadingStory
                                        ? "ກຳລັງອັບ..."
                                        : "ສ້າງສະຕໍຣີ່",
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87)))),
                      ],
                    ),
                  ),
                ),
              );

              if (snapshot.hasData) {
                final docs = snapshot.data!.docs;
                Map<String, List<Map<String, dynamic>>> groupedMap = {};
                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  data['storyDocId'] = doc.id;
                  final uId = data['userId'] ?? 'unknown';
                  groupedMap.putIfAbsent(uId, () => []).add(data);
                }

                List<UserStoryGroup> groups = [];
                groupedMap.forEach((uId, list) {
                  list.sort((a, b) {
                    final aTime = a['createdAt'] as Timestamp?;
                    final bTime = b['createdAt'] as Timestamp?;
                    if (aTime == null) return -1;
                    if (bTime == null) return 1;
                    return aTime.compareTo(bTime);
                  });
                  groups.add(UserStoryGroup(
                    userId: uId,
                    userName: list.last['userName'] ?? 'User',
                    userAvatar: list.last['userAvatar'] ?? '',
                    stories: list,
                  ));
                });

                if (currentUserId != null) {
                  int myIndex =
                      groups.indexWhere((g) => g.userId == currentUserId);
                  if (myIndex != -1) {
                    final myGroup = groups.removeAt(myIndex);
                    groups.insert(0, myGroup);
                  }
                }

                for (int i = 0; i < groups.length; i++) {
                  final group = groups[i];
                  final lastStory = group.stories.last;
                  final isVideo = lastStory['mediaType'] == 'video';
                  final isMyStory = group.userId == currentUserId;

                  storyWidgets.add(
                    GestureDetector(
                      onTap: () => _openStoryGroupViewer(groups, i),
                      child: Container(
                        width: 110,
                        margin:
                            const EdgeInsets.only(right: 8, bottom: 5, top: 5),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: isVideo
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            getMiddleFrameThumbnail(
                                                lastStory['storyImage'] ?? ''),
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) =>
                                                Container(
                                                    color: Colors.black87),
                                          ),
                                          Container(color: Colors.black26),
                                        ],
                                      )
                                    : Image.network(
                                        lastStory['storyImage'] ?? '',
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) =>
                                            const Icon(Icons.broken_image)),
                              ),
                            ),
                            Container(
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: LinearGradient(
                                        colors: [
                                          Colors.black.withOpacity(0.5),
                                          Colors.transparent
                                        ],
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter))),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: isMyStory
                                          ? Colors.greenAccent
                                          : (group.stories.length > 1
                                              ? Colors.pinkAccent
                                              : Colors.blueAccent),
                                      width: 2.5),
                                ),
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.grey[200],
                                  backgroundImage: (group
                                              .userAvatar.isNotEmpty &&
                                          group.userAvatar.startsWith('http'))
                                      ? NetworkImage(group.userAvatar)
                                      : const AssetImage('assets/default.jpg')
                                          as ImageProvider,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Text(
                                  isMyStory ? "ສະຕໍຣີ່ຂອງທ່ານ" : group.userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                            if (group.stories.length > 1)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text("+${group.stories.length}",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              }
              return ListView(
                  scrollDirection: Axis.horizontal, children: storyWidgets);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------
// Classes ສໍາລັບจัดทໍາ Viewer ຂອງ Story
// ---------------------------------------------------------
class UserStoryGroup {
  final String userId;
  final String userName;
  final String userAvatar;
  final List<Map<String, dynamic>> stories;
  UserStoryGroup({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.stories,
  });
}

class FacebookStoryViewer extends StatefulWidget {
  final List<UserStoryGroup> storyGroups;
  final int initialGroupIndex;
  const FacebookStoryViewer({
    super.key,
    required this.storyGroups,
    required this.initialGroupIndex,
  });
  @override
  State<FacebookStoryViewer> createState() => _FacebookStoryViewerState();
}

class _FacebookStoryViewerState extends State<FacebookStoryViewer> {
  late int currentGroupIdx;
  late int currentStoryIdx;
  Timer? _timer;
  double _progress = 0.0;
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  bool _isDisposed = false;

  // ✅ ตัวแปรสำหรับส่งข้อความ
  final TextEditingController _messageController = TextEditingController();
  bool _showChatInput = false;

  @override
  void initState() {
    super.initState();
    currentGroupIdx = widget.initialGroupIndex;
    currentStoryIdx = 0;
    _showStory();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _videoController?.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _showStory() async {
    _timer?.cancel();
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }
    if (_isDisposed) return;

    setState(() {
      _progress = 0.0;
      _isVideoPlaying = false;
      _showChatInput = false; // ✅ ปิดช่องแชทเมื่อเปลี่ยนเรื่อง
    });
    final story = widget.storyGroups[currentGroupIdx].stories[currentStoryIdx];
    final isVideo = story['mediaType'] == 'video';

    if (story['storyDocId'] != null) {
      _recordStoryView(story['storyDocId'], story['userId']);
    }

    if (isVideo) {
      _videoController = VideoPlayerController.networkUrl(
          Uri.parse(story['storyImage'] ?? ''));
      try {
        await _videoController!.initialize();
        if (_isDisposed) return;
        _videoController!.play();
        setState(() {
          _isVideoPlaying = true;
        });
        _startVideoProgress();
      } catch (e) {
        _nextStory();
      }
    } else {
      _startImageTimer();
    }
  }

  void _pauseStory() {
    _timer?.cancel();
    if (_isVideoPlaying && _videoController != null) {
      _videoController!.pause();
    }
  }

  void _resumeStory() {
    if (_isDisposed || !mounted) return;

    final story = widget.storyGroups[currentGroupIdx].stories[currentStoryIdx];
    final isVideo = story['mediaType'] == 'video';

    if (isVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController!.play();
        _startVideoProgress();
      } else {
        _showStory();
      }
    } else {
      _startImageTimer();
    }
  }

  Future<void> _recordStoryView(String storyId, String ownerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid == ownerId) return;

    String name = user.displayName ?? "ນັກທ່ອງທ່ຽວ";
    String avatar = user.photoURL ?? "";

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        name = userDoc.data()?['displayName'] ?? name;
        avatar = userDoc.data()?['photoUrl'] ?? avatar;
      }
    } catch (_) {}

    await FirebaseFirestore.instance
        .collection('stories')
        .doc(storyId)
        .collection('viewers')
        .doc(user.uid)
        .set({
      'userId': user.uid,
      'userName': name,
      'userAvatar': avatar,
      'viewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _sendEmojiReaction(String storyId, String emoji) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String name = user.displayName ?? "ນັກທ່ອງທ່ຽວ";
    String avatar = user.photoURL ?? "";

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        name = userDoc.data()?['displayName'] ?? name;
        avatar = userDoc.data()?['photoUrl'] ?? avatar;
      }
    } catch (_) {}

    await FirebaseFirestore.instance
        .collection('stories')
        .doc(storyId)
        .collection('viewers')
        .doc(user.uid)
        .set({
      'userId': user.uid,
      'userName': name,
      'userAvatar': avatar,
      'emoji': emoji,
      'reactedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("ສົ່ງ $emoji ແລ້ວ! 🎉"),
          duration: const Duration(milliseconds: 700),
          behavior: SnackBarBehavior.floating,
          width: 150,
        ),
      );
    }
  }

  void _showViewersListBottomSheet(String storyId) {
    _pauseStory();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('stories')
              .doc(storyId)
              .collection('viewers')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: Colors.white));
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text("ຍັງບໍ່ມີຄົນເບິ່ງເທື່ອ",
                      style: TextStyle(color: Colors.white60)),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                Text("ຄົນເບິ່ງທັງໝົດ (${docs.length})",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white12),
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final name = data['userName'] ?? 'User';
                      final avt = data['userAvatar'] ?? '';
                      final emoji = data['emoji'] as String?;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey[800],
                          backgroundImage:
                              (avt.isNotEmpty && avt.startsWith('http'))
                                  ? NetworkImage(avt)
                                  : const AssetImage('assets/default.jpg')
                                      as ImageProvider,
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                        trailing: emoji != null
                            ? Text(emoji, style: const TextStyle(fontSize: 22))
                            : const Text("ເບິ່ງແລ້ວ",
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _resumeStory();
    });
  }

  // ✅ ฟังก์ชันเปิดแชท
  void _openChat() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnackBar("ກະລຸນາເຂົ້າສູ່ລະບົບ");
      return;
    }

    final group = widget.storyGroups[currentGroupIdx];
    final targetUserId = group.userId;
    
    // ถ้าเป็นสตอรี่ของตัวเอง ไม่ต้องเปิดแชท
    if (targetUserId == currentUser.uid) {
      _showSnackBar("ນີ້ແມ່ນສະຕໍຣີ່ຂອງທ່ານເອງ");
      return;
    }

    _pauseStory();

    List<String> userIds = [currentUser.uid, targetUserId];
    userIds.sort();
    final chatId = '${userIds[0]}_${userIds[1]}';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();

      if (!doc.exists) {
        await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
          'participants': userIds,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'senderId': currentUser.uid,
          'receiverId': targetUserId,
          'senderName': currentUser.displayName ?? 'User',
          'receiverName': group.userName,
          'senderPhotoUrl': currentUser.photoURL ?? '',
          'receiverPhotoUrl': group.userAvatar,
          'unreadCounts': {
            userIds[0]: 0,
            userIds[1]: 0,
          },
        });
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chatId: chatId,
            otherUserId: targetUserId,
            otherUserName: group.userName,
            otherUserPhoto: group.userAvatar,
          ),
        ),
      ).then((_) {
        if (mounted) {
          _resumeStory();
        }
      });
    } catch (e) {
      debugPrint('Open chat error: $e');
      _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e");
      _resumeStory();
    }
  }

  // ✅ ฟังก์ชันส่งข้อความผ่าน Story
  Future<void> _sendMessageViaStory() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final group = widget.storyGroups[currentGroupIdx];
    final targetUserId = group.userId;
    final story = group.stories[currentStoryIdx];

    // ถ้าเป็นสตอรี่ของตัวเอง
    if (targetUserId == currentUser.uid) {
      _showSnackBar("ທ່ານບໍ່ສາມາດສົ່ງຂໍ້ຄວາມຫາຕົນເອງ");
      return;
    }

    _pauseStory();

    List<String> userIds = [currentUser.uid, targetUserId];
    userIds.sort();
    final chatId = '${userIds[0]}_${userIds[1]}';

    try {
      // สร้างหรืออัปเดตแชท
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();

      if (!doc.exists) {
        await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
          'participants': userIds,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': text,
          'senderId': currentUser.uid,
          'receiverId': targetUserId,
          'senderName': currentUser.displayName ?? 'User',
          'receiverName': group.userName,
          'senderPhotoUrl': currentUser.photoURL ?? '',
          'receiverPhotoUrl': group.userAvatar,
          'unreadCounts': {
            userIds[0]: 0,
            userIds[1]: 1,
          },
        });
      } else {
        // อัปเดต unreadCount
        final docData = doc.data() as Map<String, dynamic>;
        Map<String, dynamic> unreadCounts =
            Map<String, dynamic>.from(docData['unreadCounts'] ?? {});
        unreadCounts[targetUserId] = (unreadCounts[targetUserId] ?? 0) + 1;

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .update({
          'lastMessage': text,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'senderId': currentUser.uid,
          'receiverId': targetUserId,
          'senderName': currentUser.displayName ?? 'User',
          'receiverName': group.userName,
          'senderPhotoUrl': currentUser.photoURL ?? '',
          'receiverPhotoUrl': group.userAvatar,
          'unreadCounts': unreadCounts,
        });
      }

      // ส่งข้อความ
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': currentUser.displayName ?? 'User',
        'senderPhotoUrl': currentUser.photoURL ?? '',
        'receiverId': targetUserId,
        'content': text,
        'isSticker': false,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'isDeleted': false,
        'isEdited': false,
      });

      _messageController.clear();
      setState(() {
        _showChatInput = false;
      });

      _showSnackBar("ສົ່ງຂໍ້ຄວາມສຳເລັດ ✅");
      _resumeStory();
    } catch (e) {
      debugPrint('Send message via story error: $e');
      _showSnackBar("ເກີດຂໍ້ຜິດພາດ: $e");
      _resumeStory();
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startImageTimer() {
    const totalMs = 5000;
    const intervalMs = 50;
    int elapsed = 0;
    _timer = Timer.periodic(const Duration(milliseconds: intervalMs), (t) {
      if (_isDisposed) return;
      elapsed += intervalMs;
      setState(() {
        _progress = elapsed / totalMs;
      });
      if (elapsed >= totalMs) {
        t.cancel();
        _nextStory();
      }
    });
  }

  void _startVideoProgress() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (_isDisposed ||
          _videoController == null ||
          !_videoController!.value.isInitialized) {
        t.cancel();
        return;
      }

      final double pos =
          _videoController!.value.position.inMilliseconds.toDouble();
      final double dur =
          _videoController!.value.duration.inMilliseconds.toDouble();

      if (dur > 0) {
        setState(() {
          _progress = (pos / dur).clamp(0.0, 1.0);
        });
      }

      if (pos >= dur ||
          (!_videoController!.value.isPlaying &&
              pos > 0 &&
              pos >= (dur - 100))) {
        t.cancel();
        _nextStory();
      }
    });
  }

  void _nextStory() {
    final currentGroup = widget.storyGroups[currentGroupIdx];
    if (currentStoryIdx < currentGroup.stories.length - 1) {
      currentStoryIdx++;
      _showStory();
    } else {
      if (currentGroupIdx < widget.storyGroups.length - 1) {
        currentGroupIdx++;
        currentStoryIdx = 0;
        _showStory();
      } else {
        Navigator.pop(context);
      }
    }
  }

  void _prevStory() {
    if (currentStoryIdx > 0) {
      currentStoryIdx--;
      _showStory();
    } else {
      if (currentGroupIdx > 0) {
        currentGroupIdx--;
        currentStoryIdx =
            widget.storyGroups[currentGroupIdx].stories.length - 1;
        _showStory();
      } else {
        _showStory();
      }
    }
  }

  void _deleteCurrentStory(Map<String, dynamic> storyData) async {
    _pauseStory();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("ລົບສະຕໍຣີ່?"),
        content: const Text("ທ່ານຕ້ອງການລົບສະຕໍຣີ່ນີ້ແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(c);
                _resumeStory();
              },
              child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);

              final String storyId = storyData['storyDocId'];
              final String? url = storyData['storyImage'];
              final bool isVideo = storyData['mediaType'] == 'video';

              if (url != null && url.isNotEmpty) {
                await deleteFromCloudinary(url, isVideo);
              }

              await FirebaseFirestore.instance
                  .collection('stories')
                  .doc(storyId)
                  .delete();

              final grp = widget.storyGroups[currentGroupIdx];
              grp.stories.removeAt(currentStoryIdx);
              if (grp.stories.isEmpty) {
                widget.storyGroups.removeAt(currentGroupIdx);
                if (widget.storyGroups.isEmpty) {
                  Navigator.pop(context);
                  return;
                }
                if (currentGroupIdx >= widget.storyGroups.length)
                  currentGroupIdx = widget.storyGroups.length - 1;
                currentStoryIdx = 0;
              } else {
                if (currentStoryIdx >= grp.stories.length)
                  currentStoryIdx = grp.stories.length - 1;
              }
              _showStory();
            },
            child: const Text("ລົບ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storyGroups.isEmpty)
      return const Scaffold(backgroundColor: Colors.black);
    final group = widget.storyGroups[currentGroupIdx];
    final story = group.stories[currentStoryIdx];
    final isVideo = story['mediaType'] == 'video';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMyStory = story['userId'] == currentUserId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (_) => _pauseStory(),
        onTapUp: (details) {
          // ✅ ถ้าแสดงช่องแชทอยู่ ให้ซ่อนก่อน
          if (_showChatInput) {
            setState(() {
              _showChatInput = false;
            });
            return;
          }
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width * 0.3) {
            _prevStory();
          } else {
            _nextStory();
          }
        },
        onTapCancel: () => _resumeStory(),
        onLongPressStart: (_) => _pauseStory(),
        onLongPressEnd: (_) => _resumeStory(),
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 10) {
            Navigator.pop(context);
          }
        },
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 200) {
            _prevStory();
          } else if (details.primaryVelocity != null &&
              details.primaryVelocity! < -200) {
            _nextStory();
          } else {
            _resumeStory();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.transparent),
            Center(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isVideo)
                    Image.network(
                      getMiddleFrameThumbnail(story['storyImage'] ?? ''),
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => Container(color: Colors.black),
                    ),
                  if (isVideo)
                    if (_videoController != null &&
                        _videoController!.value.isInitialized)
                      Center(
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    else
                      const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                  else
                    Image.network(
                      story['storyImage'] ?? '',
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.broken_image, color: Colors.white),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  Row(
                    children: List.generate(group.stories.length, (idx) {
                      double p = 0.0;
                      if (idx < currentStoryIdx)
                        p = 1.0;
                      else if (idx == currentStoryIdx) p = _progress;
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2)),
                          child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: p,
                              child: Container(color: Colors.white)),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _pauseStory();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ProfilePage(targetUserId: group.userId),
                            ),
                          ).then((_) {
                            if (mounted) {
                              _resumeStory();
                            }
                          });
                        },
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey[700],
                              backgroundImage: (group.userAvatar.isNotEmpty &&
                                      group.userAvatar.startsWith('http'))
                                  ? NetworkImage(group.userAvatar)
                                  : const AssetImage('assets/default.jpg')
                                      as ImageProvider,
                            ),
                            const SizedBox(width: 10),
                            Text(isMyStory ? "ສະຕໍຣີ່ຂອງທ່ານ" : group.userName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          // ✅ ปุ่มแชท (แสดงเฉพาะไม่ใช่สตอรี่ของตัวเอง)
                          if (!isMyStory)
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline,
                                  color: Colors.white, size: 24),
                              onPressed: _openChat,
                              tooltip: 'ສົ່ງຂໍ້ຄວາມ',
                            ),
                          if (isMyStory)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.white),
                              color: Colors.grey[900],
                              offset: const Offset(0, 40),
                              onSelected: (value) {
                                if (value == 'delete') {
                                  _deleteCurrentStory(story);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete,
                                          color: Colors.redAccent),
                                      SizedBox(width: 8),
                                      Text('ລົບສະຕໍຣີ່',
                                          style: TextStyle(
                                              color: Colors.redAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          IconButton(
                              icon:
                                  const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  // ✅ แสดงปุ่มต่างๆ ด้านล่าง
                  if (isMyStory)
                    Center(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('stories')
                            .doc(story['storyDocId'])
                            .collection('viewers')
                            .snapshots(),
                        builder: (context, snapshot) {
                          int count =
                              snapshot.hasData ? snapshot.data!.docs.length : 0;
                          return ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: const BorderSide(color: Colors.white30),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                            ),
                            icon: const Icon(Icons.visibility,
                                size: 18, color: Colors.tealAccent),
                            label: Text("ຄົນເບິ່ງ $count ຄົນ",
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              _pauseStory();
                              _showViewersListBottomSheet(story['storyDocId']);
                            },
                          );
                        },
                      ),
                    )
                  else
                    Column(
                      children: [
                        // ✅ ปุ่มเปิดช่องแชท (ข้อความ)
                        if (!_showChatInput)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showChatInput = !_showChatInput;
                                  if (_showChatInput) {
                                    _pauseStory();
                                  } else {
                                    _resumeStory();
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.message, color: Colors.white60),
                                    SizedBox(width: 8),
                                    Text("ຕອບກັບ",
                                        style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // ✅ ช่องพิมพ์ข้อความ
                        if (_showChatInput)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      hintText: "ພິມຂໍ້ຄວາມ...",
                                      hintStyle:
                                          TextStyle(color: Colors.white38),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                    maxLines: 2,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _sendMessageViaStory(),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.send,
                                      color: Colors.tealAccent),
                                  onPressed: _sendMessageViaStory,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white60),
                                  onPressed: () {
                                    setState(() {
                                      _showChatInput = false;
                                      _messageController.clear();
                                    });
                                    _resumeStory();
                                  },
                                ),
                              ],
                            ),
                          ),
                        // ✅ แถวอิโมจิ (ซ่อนเมื่อเปิดช่องแชท)
                        if (!_showChatInput)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(left: 8.0),
                                    child: Text("ສົ່ງຄຳເຫັນ...",
                                        style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 13)),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildEmojiItem("👍", story['storyDocId']),
                                    _buildEmojiItem("❤️", story['storyDocId']),
                                    _buildEmojiItem("😂", story['storyDocId']),
                                    _buildEmojiItem("😮", story['storyDocId']),
                                    _buildEmojiItem("😢", story['storyDocId']),
                                  ],
                                ),
                              ],
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
    );
  }

  Widget _buildEmojiItem(String emoji, String storyId) {
    return GestureDetector(
      onTap: () => _sendEmojiReaction(storyId, emoji),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}