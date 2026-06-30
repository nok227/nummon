// models/comment_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String placeId;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final String text;
  final DateTime createdAt;
  final List<String> likes;
  final List<Comment> replies;

  Comment({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.text,
    required this.createdAt,
    this.likes = const [],
    this.replies = const [],
  });

  factory Comment.fromMap(String id, Map<String, dynamic> data) {
    return Comment(
      id: id,
      placeId: data['placeId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'ຜູ້ໃຊ້ງານ',
      userPhotoUrl: data['userPhotoUrl'] ?? '',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      likes: List<String>.from(data['likes'] ?? []),
      replies: [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'placeId': placeId,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'likes': likes,
    };
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} ປີກ່ອນ';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} ເດືອນກ່ອນ';
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()} ອາທິດກ່ອນ';
    if (diff.inDays > 0) return '${diff.inDays} ມື້ກ່ອນ';
    if (diff.inHours > 0) return '${diff.inHours} ຊົ່ວໂມງກ່ອນ';
    if (diff.inMinutes > 0) return '${diff.inMinutes} ນາທີກ່ອນ';
    return 'ດຽວນີ້';
  }
}