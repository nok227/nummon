// ci/comment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment_model.dart';
import 'dart:developer';
import 'package:flutter/foundation.dart';

class CommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ✅ แก้ไขให้โหลดเร็วขึ้น - ไม่ต้องรอ replies ก่อน
  Stream<List<Comment>> getComments(String placeId) {
    return _firestore
        .collection('places')
        .doc(placeId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final List<Comment> comments = [];
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            comments.add(Comment(
              id: doc.id,
              placeId: data['placeId'] ?? '',
              userId: data['userId'] ?? '',
              userName: data['userName'] ?? 'ຜູ້ໃຊ້ງານ',
              userPhotoUrl: data['userPhotoUrl'] ?? '',
              text: data['text'] ?? '',
              createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              likes: List<String>.from(data['likes'] ?? []),
              replies: [], // ✅ เริ่มต้นเป็น [] แล้วค่อยโหลดทีหลัง
            ));
          }
          return comments;
        });
  }

  // ✅ โหลด replies แบบ Real-time (Stream)
  Stream<List<Comment>> getRepliesStream(String placeId, String commentId) {
    return _firestore
        .collection('places')
        .doc(placeId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Comment(
              id: doc.id,
              placeId: data['placeId'] ?? '',
              userId: data['userId'] ?? '',
              userName: data['userName'] ?? 'ຜູ້ໃຊ້ງານ',
              userPhotoUrl: data['userPhotoUrl'] ?? '',
              text: data['text'] ?? '',
              createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              likes: List<String>.from(data['likes'] ?? []),
              replies: [],
            );
          }).toList();
        });
  }

  // ✅ โหลด replies แยกต่างหาก (เรียกเมื่อกดแสดงคอมเมนต์) - แบบ Future
  Future<List<Comment>> getReplies(String placeId, String commentId) async {
    try {
      final snapshot = await _firestore
          .collection('places')
          .doc(placeId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .orderBy('createdAt', descending: false)
          .get();

      return snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Comment(
              id: doc.id,
              placeId: data['placeId'] ?? '',
              userId: data['userId'] ?? '',
              userName: data['userName'] ?? 'ຜູ້ໃຊ້ງານ',
              userPhotoUrl: data['userPhotoUrl'] ?? '',
              text: data['text'] ?? '',
              createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              likes: List<String>.from(data['likes'] ?? []),
              replies: [],
            );
          })
          .toList();
    } catch (e) {
      debugPrint('Error loading replies: $e');
      return [];
    }
  }

  // ✅ เพิ่มคอมเมนต์
  Future<void> addComment(String placeId, String text) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('ກະລຸນາເຂົ້າສູ່ລະບົບ');

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data() ?? {};
    final userName = userData['displayName'] ?? user.displayName ?? 'ຜູ້ໃຊ້ງານ';
    final userPhotoUrl = userData['photoURL'] ?? user.photoURL ?? '';

    final comment = {
      'placeId': placeId,
      'userId': user.uid,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': [],
    };

    await _firestore
        .collection('places')
        .doc(placeId)
        .collection('comments')
        .add(comment);
  }

  // ✅ เพิ่มการตอบกลับ
  Future<void> addReply(String placeId, String commentId, String text) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('ກະລຸນາເຂົ້າສູ່ລະບົບ');

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDoc.data() ?? {};
    final userName = userData['displayName'] ?? user.displayName ?? 'ຜູ້ໃຊ້ງານ';
    final userPhotoUrl = userData['photoURL'] ?? user.photoURL ?? '';

    final reply = {
      'placeId': placeId,
      'userId': user.uid,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': [],
    };

    await _firestore
        .collection('places')
        .doc(placeId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .add(reply);
  }

  // ✅ กดถูกใจ / เลิกถูกใจ
  Future<void> toggleLike(
    String placeId,
    String commentId,
    bool isReply, {
    String? replyId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    String collectionPath =
        'places/$placeId/comments/$commentId${isReply ? '/replies/$replyId' : ''}';

    final docRef = _firestore.doc(collectionPath);
    final doc = await docRef.get();

    if (!doc.exists) return;

    final List<String> likes = List<String>.from(doc.data()?['likes'] ?? []);
    if (likes.contains(user.uid)) {
      likes.remove(user.uid);
    } else {
      likes.add(user.uid);
    }

    await docRef.update({'likes': likes});
  }

  // ✅ ลบคอมเมนต์ / ตอบกลับ
  Future<void> deleteComment(
    String placeId,
    String commentId, {
    String? replyId,
  }) async {
    if (replyId != null) {
      await _firestore
          .collection('places')
          .doc(placeId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .doc(replyId)
          .delete();
    } else {
      final replies = await _firestore
          .collection('places')
          .doc(placeId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .get();

      for (var reply in replies.docs) {
        await reply.reference.delete();
      }

      await _firestore
          .collection('places')
          .doc(placeId)
          .collection('comments')
          .doc(commentId)
          .delete();
    }
  }
}