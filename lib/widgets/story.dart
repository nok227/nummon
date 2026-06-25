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
import 'package:video_compress/video_compress.dart'; // 🌟 ເພີ່ມຕົວບີບອັດວິດີໂອ
import '../models/api_Cloudinary.dart'; // 🌟 Import Config
import 'story_preview_page.dart';

// ---------------------------------------------------------
// ฟังก์ชันลบไฟล์ออกจาก Cloudinary แบบละเอียด (Pro Delete)
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
      if (RegExp(r'^v\d+$').hasMatch(segments[i])) continue; // ຂ້າມເວີຊັນ
      // ຂ້າມ Transformations ຕ່າງໆທີ່ Cloudinary ສ້າງຂຶ້ນ
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

    // ຕັດນາມສະກຸນໄຟລ໌ອອກ
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

    // กำหนดประเภททรัพยากร
    final resourceType = isVideo ? "video" : "image";
    final uri = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload");
    
    final request = http.MultipartRequest("POST", uri);
    request.fields['upload_preset'] = uploadPreset;

    // 🚨 นำโค้ดส่วน eager และ eager_async ออกเพื่อป้องกัน Timeout จาก Cloudinary
    // การครอบตัดวิดีโอ (Trim) จะถูกจัดการผ่านการแปลง URL ด้านล่างแทน 

    request.files.add(await http.MultipartFile.fromPath('file', fileToUpload.path));
    
    final response = await request.send();

    if (isVideo) {
      VideoCompress.deleteAllCache();
    }

    if (response.statusCode != 200) {
      // 🌟 เพิ่มบรรทัดนี้เพื่อปริ้นท์ดูข้อผิดพลาดที่แท้จริงจาก Cloudinary
      final errorResponse = await response.stream.bytesToString();
      debugPrint("❌ Cloudinary Upload Error: $errorResponse");
      throw Exception("ອັບໂຫຼດລົ້ມເຫຼວ (Code: ${response.statusCode})");
    }

    final responseData = await response.stream.toBytes();
    final jsonMap = jsonDecode(String.fromCharCodes(responseData));
    String url = jsonMap['secure_url'];

    // 🌟 จัดการตัดวิดีโอ (Trim) ด้วยการแก้ไข URL โดยตรง
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
        'so_${startSeconds.toStringAsFixed(2)},eo_${endSeconds.toStringAsFixed(2)},f_auto,q_auto,vc_auto/';
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

                for (int i = 0; i < groups.length; i++) {
                  final group = groups[i];
                  final lastStory = group.stories.last;
                  final isVideo = lastStory['mediaType'] == 'video';

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
                                    ? Container(
                                        color: Colors.black87,
                                        child: const Icon(
                                            Icons.play_circle_fill,
                                            color: Colors.white,
                                            size: 32))
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
                                      color: group.stories.length > 1
                                          ? Colors.pinkAccent
                                          : Colors.blueAccent,
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
                              child: Text(group.userName,
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
// Classes ສໍາລັບจัดการ Viewer ของ Story
// ---------------------------------------------------------

class UserStoryGroup {
  final String userId;
  final String userName;
  final String userAvatar;
  final List<Map<String, dynamic>> stories;
  UserStoryGroup(
      {required this.userId,
      required this.userName,
      required this.userAvatar,
      required this.stories});
}

class FacebookStoryViewer extends StatefulWidget {
  final List<UserStoryGroup> storyGroups;
  final int initialGroupIndex;
  const FacebookStoryViewer(
      {super.key, required this.storyGroups, required this.initialGroupIndex});
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
    });
    final story = widget.storyGroups[currentGroupIdx].stories[currentStoryIdx];
    final isVideo = story['mediaType'] == 'video';

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
    _timer?.cancel();
    _videoController?.pause();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("ລົບສະຕໍຣີ່?"),
        content: const Text("ທ່ານຕ້ອງການລົບສະຕໍຣີ່ນີ້ແທ້ຫຼືບໍ່?"),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(c);
                _showStory();
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
      body: Stack(
        children: [
          GestureDetector(
            onTapUp: (details) {
              final width = MediaQuery.of(context).size.width;
              if (details.globalPosition.dx < width * 0.3) {
                _prevStory();
              } else {
                _nextStory();
              }
            },
            child: Center(
              child: isVideo
                  ? (_videoController != null &&
                          _videoController!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!))
                      : const CircularProgressIndicator(color: Colors.white))
                  : Image.network(story['storyImage'] ?? '',
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.broken_image, color: Colors.white)),
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
                    Row(
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
                        Text(group.userName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ],
                    ),
                    Row(
                      children: [
                        if (isMyStory)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                color: Colors.white), // จุด 3 จุดแนวตั้ง
                            color: Colors.grey[900], // สีพื้นหลังเมนู
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
                                    Icon(Icons.delete, color: Colors.redAccent),
                                    SizedBox(width: 8),
                                    Text('ລົບສະຕໍຣີ່',
                                        style:
                                            TextStyle(color: Colors.redAccent)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context)),
                      ],
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
}
