// widgets/reply_dialog.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReplyDialog extends StatefulWidget {
  final String placeId;
  final String commentId;
  final String userName;
  final Function(String) onReplySent;

  const ReplyDialog({
    super.key,
    required this.placeId,
    required this.commentId,
    required this.userName,
    required this.onReplySent,
  });

  @override
  State<ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<ReplyDialog> {
  final TextEditingController _replyController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ກະລຸນາພິມຄຳຕອບກັບ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ກະລຸນາເຂົ້າສູ່ລະບົບ'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final userData = userDoc.data() ?? {};
      final userName = userData['displayName'] ?? user.displayName ?? 'ຜູ້ໃຊ້ງານ';
      final userPhotoUrl = userData['photoURL'] ?? user.photoURL ?? '';

      final reply = {
        'placeId': widget.placeId,
        'userId': user.uid,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': [],
      };

      await FirebaseFirestore.instance
          .collection('places')
          .doc(widget.placeId)
          .collection('comments')
          .doc(widget.commentId)
          .collection('replies')
          .add(reply);

      widget.onReplySent(text);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ຕອບກັບສຳເລັດແລ້ວ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ເກີດຂໍ້ຜິດພາດ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.reply, color: Colors.teal),
          const SizedBox(width: 8),
          Text('ຕອບກັບ @${widget.userName}'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _replyController,
            decoration: const InputDecoration(
              hintText: 'ພິມຄຳຕອບກັບ...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            maxLines: 3,
            autofocus: true,
            enabled: !_isLoading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('ຍົກເລີກ'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          onPressed: _isLoading ? null : _sendReply,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('ສົ່ງ'),
        ),
      ],
    );
  }
}