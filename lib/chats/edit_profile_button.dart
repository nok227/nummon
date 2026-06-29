import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../private/edit_profile_page.dart';

class EditProfileButton extends StatelessWidget {
  final bool isOwner;

  const EditProfileButton({
    super.key,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    if (isOwner) {
      // ─── ปุ่มแก้ไขสำหรับเจ้าของโปรไฟล์ ───
      return ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditProfilePage()),
          );
        },
        icon: const Icon(Icons.edit, size: 20),
        label: const Text(
          'ແກ້ໄຂໂພຣໄຟລ໌',
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
    } else {
      // ─── ปุ่มแก้ไขสำหรับผู้ที่ดูโปรไฟล์ผู้อื่น (Popup) ───
      return OutlinedButton.icon(
        onPressed: () => _showEditPopup(context),
        icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.teal),
        label: const Text(
          'แก้ไข',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.teal),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.teal),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _showEditPopup(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final TextEditingController reasonController = TextEditingController();

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── ตัวบ่งชี้ (Handle) ───
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

              // ─── หัวข้อ ───
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_note, color: Colors.teal, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ขอแก้ไขโปรไฟล์',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'ส่งคำขอแก้ไขข้อมูลโปรไฟล์',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // ─── ช่องพิมพ์เหตุผล ───
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: reasonController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'ระบุเหตุผลที่ต้องการแก้ไขโปรไฟล์...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ─── ปุ่มยกเลิก + ส่งคำขอ ───
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
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final reason = reasonController.text.trim();
                        if (reason.isNotEmpty) {
                          _submitEditRequest(
                            context,
                            senderId: currentUser?.uid,
                            senderName: currentUser?.displayName ?? 'ผู้ใช้',
                            reason: reason,
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ส่งคำขอแก้ไขเรียบร้อยแล้ว 📝'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('กรุณาระบุเหตุผล'),
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
                      child: const Text('ส่งคำขอ'),
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

  Future<void> _submitEditRequest(
    BuildContext context, {
    required String? senderId,
    required String senderName,
    required String reason,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('edit_requests').add({
        'senderId': senderId,
        'senderName': senderName,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // pending, approved, rejected
      });
      debugPrint('ส่งคำขอแก้ไขสำเร็จ');
    } catch (e) {
      debugPrint('ส่งคำขอแก้ไขล้มเหลว: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}