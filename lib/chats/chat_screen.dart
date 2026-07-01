import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../private/profile_page.dart';
import '../services/onesignal_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhoto;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _showStickerPicker = false;

  final List<String> _stickers = [
    '😊', '😂', '❤️', '👍', '👋', '😍', '🎉', '🔥',
    '💪', '🙏', '🤗', '😎', '🥰', '😘', '🤩', '✨',
    '💯', '🙌', '👏', '🤝', '💖', '🌟', '🌈', '☀️',
    '🤣', '🥳', '😺', '🐱', '⭐', '🎊', '💕', '🌺',
  ];

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
  }

  void _markMessagesAsRead() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final messagesRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false);

      final snapshot = await messagesRef.get();
      for (var doc in snapshot.docs) {
        await doc.reference.update({'isRead': true});
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'unreadCounts.${currentUser.uid}': 0,
      });
    } catch (e) {
      debugPrint('Mark messages as read error: $e');
    }
  }

  Future<void> _sendMessage({String? text, String? sticker}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    String content = '';
    bool isSticker = false;

    if (sticker != null && sticker.isNotEmpty) {
      content = sticker;
      isSticker = true;
    } else if (text != null && text.trim().isNotEmpty) {
      content = text.trim();
      isSticker = false;
    } else {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': currentUser.displayName ?? 'User',
        'senderPhotoUrl': currentUser.photoURL ?? '',
        'receiverId': widget.otherUserId,
        'content': content,
        'isSticker': isSticker,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'isDeleted': false,
        'isEdited': false,
        'isStoryReply': false, // ✅ เพิ่มค่าเริ่มต้น
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'senderId': currentUser.uid,
        'receiverId': widget.otherUserId,
        'senderName': currentUser.displayName ?? 'User',
        'receiverName': widget.otherUserName,
        'senderPhotoUrl': currentUser.photoURL ?? '',
        'receiverPhotoUrl': widget.otherUserPhoto ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      if (chatDoc.exists) {
        final data = chatDoc.data() as Map<String, dynamic>;
        Map<String, dynamic> unreadCounts =
            Map<String, dynamic>.from(data['unreadCounts'] ?? {});
        unreadCounts[widget.otherUserId] =
            (unreadCounts[widget.otherUserId] ?? 0) + 1;

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({'unreadCounts': unreadCounts});
      }

      // ✅ ແຈ້ງເຕືອນເຂົ້າມືຖືຜູ້ຮັບ ຖ້າລາວປິດແອັບ/ບໍ່ໄດ້ຢູ່ໜ້າແຊດ
      OneSignalService().sendChatNotification(
        receiverExternalId: widget.otherUserId,
        title: currentUser.displayName ?? 'ຂໍ້ຄວາມໃໝ່',
        body: isSticker ? 'ສົ່ງສະຕິກເກີ' : content,
        data: {
          'type': 'chat_message',
          'chatId': widget.chatId,
        },
      );

      _messageController.clear();
      setState(() => _showStickerPicker = false);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Send message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('ເກີດຂໍ້ຜິດພາດ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── ລົບຂໍ້ຄວາມ ───
  Future<void> _deleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ລົບຂໍ້ຄວາມ'),
        content: const Text('ທ່ານຕ້ອງການລົບຂໍ້ຄວາມນີ້ແທ້ຫຼືບໍ່?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ຍົກເລີກ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ລົບ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      if (chatDoc.exists) {
        final data = chatDoc.data() as Map<String, dynamic>;
        final messageDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(messageId)
            .get();

        final messageData = messageDoc.data() as Map<String, dynamic>;

        if (data['lastMessage'] == messageData['content']) {
          // ✅ ไม่ใช้ .where('isDeleted', ...) ร่วมกับ .orderBy('timestamp', ...)
          // เพราะ Firestore ต้องการ composite index สำหรับคู่นี้โดยเฉพาะ
          // (ถ้ายังไม่ได้สร้าง index จะเจอ error FAILED_PRECONDITION ทันที)
          // แก้โดยดึงมาตามลำดับเวลาอย่างเดียว แล้วมากรอง isDeleted ในแอปแทน
          final recentSnapshot = await FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(20)
              .get();

          final activeDocs = recentSnapshot.docs
              .where((doc) =>
                  doc.id != messageId && (doc.data()['isDeleted'] != true))
              .toList();

          if (activeDocs.isNotEmpty) {
            final lastMsgData = activeDocs.first.data();
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(widget.chatId)
                .update({
              'lastMessage': lastMsgData['content'] ?? '',
              'lastMessageTime': lastMsgData['timestamp'] ?? FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(widget.chatId)
                .update({
              'lastMessage': '',
              'lastMessageTime': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'isDeleted': true,
        'content': 'ຂໍ້ຄວາມຖືກລົບແລ້ວ',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ລົບຂໍ້ຄວາມສຳເລັດ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Delete message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── ແກ້ໄຂຂໍ້ຄວາມ ───
  void _showEditDialog(String messageId, String currentContent) {
    _editController.text = currentContent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ແກ້ໄຂຂໍ້ຄວາມ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _editController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'ແກ້ໄຂຂໍ້ຄວາມ...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[400]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('ຍົກເລີກ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final newContent = _editController.text.trim();
                        if (newContent.isNotEmpty) {
                          _saveEditedMessage(messageId, newContent);
                          Navigator.pop(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ກະລຸນາໃສ່ຂໍ້ຄວາມ'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('ບັນທຶກ'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveEditedMessage(String messageId, String newContent) async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'content': newContent,
        'isEdited': true,
      });

      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      if (chatDoc.exists) {
        final data = chatDoc.data() as Map<String, dynamic>;

        if (data['lastMessage'] == _editController.text) {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .update({
            'lastMessage': newContent,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ແກ້ໄຂຂໍ້ຄວາມສຳເລັດ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Edit message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── ແສດງເມນູເມື່ອກົດຄ້າງຂໍ້ຄວາມ ───
  void _showMessageMenu(BuildContext context, String messageId, String content,
      bool isMe, bool isSticker, bool isStoryReply) {
    // ✅ ถ้าเป็นข้อความตอบสตอรี่ ไม่ให้แก้ไข/ลบได้
    if (isStoryReply) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ນີ້ແມ່ນຂໍ້ຄວາມຕອບສະຕໍຣີ່ ບໍ່ສາມາດແກ້ໄຂ ຫຼື ລົບໄດ້'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ສາມາດແກ້ໄຂ ຫຼື ລົບໄດ້ສະເພາະຂໍ້ຄວາມຂອງທ່ານເທົ່ານັ້ນ'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              // ✅ ສະຕິກເກີ/ອີໂມຈິ ບໍ່ມີຂໍ້ຄວາມໃຫ້ແກ້ໄຂ ຈຶ່ງເອົາ "ແກ້ໄຂ" ອອກ
              // ແຕ່ "ລົບ" ຍັງໃຫ້ໃຊ້ໄດ້ຄືເດີມ
              if (!isSticker)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('ແກ້ໄຂ'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(messageId, content);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('ລົບ', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(messageId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _goToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(
          targetUserId: widget.otherUserId,
        ),
      ),
    );
  }

  // ✅ Widget แสดงข้อความตอบสตอรี่
  Widget _buildStoryReplyMessage({
    required String content,
    required bool isMe,
    required String storyImage,
    required String storyMediaType,
    required DateTime? timestamp,
    required bool isEdited,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ รูปย่อสตอรี่
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          storyImage,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey[300],
                            child: Icon(
                              storyMediaType == 'video'
                                  ? Icons.videocam
                                  : Icons.image,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📸 ຕອບສະຕໍຣີ່',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              content,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isEdited) ...[
                    const SizedBox(height: 2),
                    Text(
                      'ແກ້ໄຂແລ້ວ',
                      style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                    ),
                  ],
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(timestamp),
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
          ] else ...[
            const SizedBox(width: 4),
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              '📸 ຕອບສະຕໍຣີ່',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              content,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          storyImage,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            width: 40,
                            height: 40,
                            color: Colors.teal[400],
                            child: Icon(
                              storyMediaType == 'video'
                                  ? Icons.videocam
                                  : Icons.image,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isEdited) ...[
                    const SizedBox(height: 2),
                    Text(
                      'ແກ້ໄຂແລ້ວ',
                      style: TextStyle(
                          fontSize: 9, color: Colors.white.withOpacity(0.6)),
                    ),
                  ],
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(timestamp),
                      style: TextStyle(
                          fontSize: 10, color: Colors.white.withOpacity(0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _goToProfile,
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: widget.otherUserPhoto != null &&
                        widget.otherUserPhoto!.isNotEmpty
                    ? NetworkImage(widget.otherUserPhoto!)
                    : null,
                child: widget.otherUserPhoto == null ||
                        widget.otherUserPhoto!.isEmpty
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                widget.otherUserName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: _goToProfile,
            tooltip: 'ເບິ່ງໂພຣໄຟລ໌',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.teal));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 60, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'ຍັງບໍ່ມີຂໍ້ຄວາມ',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'ເລີ່ມສົນທະນາກັນເລີຍ!',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                final allMessages = snapshot.data!.docs;
                final currentUser = FirebaseAuth.instance.currentUser;

                final activeMessages = allMessages.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['isDeleted'] != true;
                }).toList();

                if (activeMessages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 60, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'ຍັງບໍ່ມີຂໍ້ຄວາມ',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: activeMessages.length,
                  itemBuilder: (context, index) {
                    final doc = activeMessages[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final messageId = doc.id;
                    final isMe = data['senderId'] == currentUser?.uid;
                    final isSticker = data['isSticker'] ?? false;
                    final isEdited = data['isEdited'] ?? false;
                    final isStoryReply = data['isStoryReply'] ?? false;
                    final content = data['content'] ?? '';
                    final timestamp =
                        (data['timestamp'] as Timestamp?)?.toDate();

                    // ✅ ถ้าเป็นข้อความตอบสตอรี่
                    if (isStoryReply) {
                      final storyImage = data['storyImage'] ?? '';
                      final storyMediaType = data['storyMediaType'] ?? 'image';
                      return _buildStoryReplyMessage(
                        content: content,
                        isMe: isMe,
                        storyImage: storyImage,
                        storyMediaType: storyMediaType,
                        timestamp: timestamp,
                        isEdited: isEdited,
                      );
                    }

                    return GestureDetector(
                      onLongPress: () {
                        _showMessageMenu(
                            context, messageId, content, isMe, isSticker, isStoryReply);
                      },
                      child: _buildMessageBubble(
                        messageId: messageId,
                        content: content,
                        isMe: isMe,
                        isSticker: isSticker,
                        isEdited: isEdited,
                        timestamp: timestamp,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ─── ຊ່ອງພິມຂໍ້ຄວາມ + ປຸ່ມສະຕິກເກີ ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  if (_showStickerPicker)
                    Container(
                      height: 120,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: GridView.builder(
                        scrollDirection: Axis.horizontal,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: _stickers.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              _sendMessage(sticker: _stickers[index]);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Center(
                                child: Text(
                                  _stickers[index],
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(
                          _showStickerPicker
                              ? Icons.keyboard
                              : Icons.emoji_emotions,
                          color: Colors.teal,
                          size: 28,
                        ),
                        onPressed: () {
                          setState(() {
                            _showStickerPicker = !_showStickerPicker;
                          });
                        },
                        tooltip:
                            _showStickerPicker ? 'ປິດສະຕິກເກີ' : 'ເປີດສະຕິກເກີ',
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: TextField(
                            controller: _messageController,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText: 'ພິມຂໍ້ຄວາມ...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            onSubmitted: (_) {
                              final text = _messageController.text.trim();
                              if (text.isNotEmpty) {
                                _sendMessage(text: text);
                              }
                            },
                          ),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _messageController,
                        builder: (context, value, child) {
                          return IconButton(
                            icon: Icon(
                              Icons.send,
                              color: value.text.trim().isEmpty
                                  ? Colors.grey
                                  : Colors.green,
                              size: 28,
                            ),
                            onPressed: () {
                              final text = _messageController.text.trim();
                              if (text.isNotEmpty) {
                                _sendMessage(text: text);
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String messageId,
    required String content,
    required bool isMe,
    required bool isSticker,
    required bool isEdited,
    required DateTime? timestamp,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            if (isSticker)
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Center(
                  child: Text(content, style: const TextStyle(fontSize: 40)),
                ),
              )
            else
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content,
                      style:
                          const TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                    if (isEdited) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ແກ້ໄຂແລ້ວ',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      ),
                    ],
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(timestamp),
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(width: 4),
          ] else ...[
            const SizedBox(width: 4),
            if (isSticker)
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.teal[200]!),
                ),
                child: Center(
                  child: Text(content, style: const TextStyle(fontSize: 40)),
                ),
              )
            else
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      content,
                      style: const TextStyle(fontSize: 15, color: Colors.white),
                    ),
                    if (isEdited) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ແກ້ໄຂແລ້ວ',
                        style: TextStyle(
                            fontSize: 9, color: Colors.white.withOpacity(0.6)),
                      ),
                    ],
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('HH:mm').format(timestamp),
                        style: TextStyle(
                            fontSize: 10, color: Colors.white.withOpacity(0.8)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}