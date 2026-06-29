import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';

class InquiryButton extends StatelessWidget {
  final String targetUserId;
  final String targetName;
  final String? targetPhotoUrl;

  const InquiryButton({
    super.key,
    required this.targetUserId,
    required this.targetName,
    this.targetPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => openChat(context),
      icon: const Icon(Icons.chat_bubble_outline, size: 20),
      label: const Text(
        'ແຊ້ດ',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> openChat(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ກະລຸນາເຂົ້າສູ່ລະບົບ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    List<String> userIds = [currentUser.uid, targetUserId];
    userIds.sort();
    final chatId = '${userIds[0]}_${userIds[1]}';

    try {
      final doc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
      
      if (!doc.exists) {
        await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
          'participants': userIds,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'senderId': currentUser.uid,
          'receiverId': targetUserId,
          'senderName': currentUser.displayName ?? 'User',
          'receiverName': targetName,
          'senderPhotoUrl': currentUser.photoURL ?? '',
          'receiverPhotoUrl': targetPhotoUrl ?? '',
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
            otherUserName: targetName,
            otherUserPhoto: targetPhotoUrl,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Open chat error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}