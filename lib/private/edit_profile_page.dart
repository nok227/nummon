import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:http/http.dart' as http;

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();

  String _photoUrl = '';
  String _coverUrl = '';
  bool _isSaving = false;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  String? _tempPhotoPath;
  String? _tempCoverPath;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _displayNameController.text =
            data['displayName'] ?? user.displayName ?? '';
        _bioController.text = data['bio'] ?? '';
        _photoUrl = data['photoURL'] ?? user.photoURL ?? '';
        _coverUrl = data['coverURL'] ?? '';
      } else {
        _displayNameController.text = user.displayName ?? '';
        _photoUrl = user.photoURL ?? '';
      }
    } catch (e) {
      debugPrint('Load user data error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("ໂຫຼດຂໍ້ມູນຜິດພາດ: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    try {
      const cloudName = "duo2b46ro";
      const uploadPreset = "travel_app_preset"; 
      final uri =
          Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
      final request = http.MultipartRequest("POST", uri);
      request.fields['upload_preset'] = uploadPreset;
      request.files
          .add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response =
          await request.send().timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        final json = jsonDecode(String.fromCharCodes(bytes));
        return json['secure_url'];
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _removeExistingPhoto(bool isProfile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isProfile ? "ລຶບຮູບໂປຣໄຟລ໌?" : "ລຶບຮູບພື້ນຫຼັງ?"),
        content: const Text("ການລຶບນີ້ຈະມີຜົນທັນທີ ແລະ ບໍ່ສາມາດກູ້ຄືນໄດ້"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ລຶບ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        isProfile ? 'photoURL' : 'coverURL': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));

      if (isProfile) {
        await user.updatePhotoURL(null).timeout(const Duration(seconds: 10));
      }

      if (mounted) {
        setState(() {
          if (isProfile) {
            _photoUrl = '';
            _tempPhotoPath = null;
          } else {
            _coverUrl = '';
            _tempCoverPath = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("ລຶບຮູບສຳເລັດ"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('🔴 _removeExistingPhoto error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("ລຶບຮູບບໍ່ສຳເລັດ: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // 💡 ปรับปรุงฟังก์ชันการทำงานตรงส่วนนี้ให้ส่งค่าเด้งกลับเข้าหน้าจอบันทึกทันที
  Future<void> _pickAndCropImage(bool isProfile) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return; // ถ้าผู้ใช้กดยกเลิกการเลือกรูปภาพให้หยุดทำงาน

      // เรียกใช้งาน ImageCropper และตั้งค่าให้เด้งกลับเมื่อกดถูกต้อง
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: isProfile
            ? const CropAspectRatio(ratioX: 1, ratioY: 1)
            : const CropAspectRatio(ratioX: 16, ratioY: 9),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: isProfile ? 'ຕັດຮູບໂປຣໄຟລ໌' : 'ຕັດຮູບພື້ນຫຼັງ',
            toolbarColor: Colors.teal,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false, // 💡 ปรับเป็น false ชั่วคราวเพื่อให้ UI บน Android ยอมปล่อยผลลัพธ์กลับหน้าเดิมได้สะดวกขึ้น
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: isProfile ? 'ຕັດຮູບໂປຣໄຟລ໌' : 'ຕັດຮູບພື້ນຫຼັງ',
            doneButtonTitle: 'ຕົກລົງ',
            cancelButtonTitle: 'ຍົກເລີກ',
          ),
        ],
      );

      // เมื่อได้ไฟล์ที่ผ่านการตัด (กดปุ่ม ✓) และ Widget ยังแสดงผลอยู่บนหน้าจอ
      if (croppedFile != null && mounted) {
        setState(() {
          if (isProfile) {
            _tempPhotoPath = croppedFile.path; // บันทึกพาธรูปลงตัวแปรชั่วคราว
          } else {
            _tempCoverPath = croppedFile.path;
          }
        });
        debugPrint('🟢 จัดตำแหน่งรูปภาพเสร็จสิ้น เด้งกลับมาที่หน้าบันทึกเรียบร้อย');
      }
    } catch (e) {
      debugPrint('🔴 Crop Image Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("ເກີດຂໍ້ຜິດພາດໃນການຕັດຮູບ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    final formState = _formKey.currentState;
    if (formState == null) return;
    
    if (!formState.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("ກະລຸນາປ້ອນຊື່ສະແດງ"),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("ກະລຸນາເຂົ້າສູ່ລະບົບ"),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      String finalPhotoUrl = _photoUrl;
      String finalCoverUrl = _coverUrl;

      if (_tempPhotoPath != null) {
        final uploaded = await _uploadImage(File(_tempPhotoPath!));
        if (uploaded != null) {
          finalPhotoUrl = uploaded;
          await user.updatePhotoURL(uploaded).timeout(const Duration(seconds: 10));
        } else {
          throw Exception("ອັບໂຫລດຮູບໂປຣໄຟລ໌ບໍ່ສຳເລັດ");
        }
      }

      if (_tempCoverPath != null) {
        final uploaded = await _uploadImage(File(_tempCoverPath!));
        if (uploaded != null) {
          finalCoverUrl = uploaded;
        } else {
          throw Exception("ອັບໂຫລດຮູບປົກບໍ່ສຳເລັດ");
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        'photoURL': finalPhotoUrl,
        'coverURL': finalCoverUrl,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));

      await user.updateDisplayName(_displayNameController.text.trim()).timeout(const Duration(seconds: 10));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("ອັບເດດໂປຣໄຟລ໌ສຳເລັດ!"),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // ปิดหน้าบันทึกเมื่อบันทึกข้อมูลสำเร็จ
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ເກີດຂໍ້ຜິດພາດ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.7,
                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image,
                      color: Colors.white, size: 50),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("ແກ້ໄຂໂປຣໄຟລ໌"),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isSaving ? null : _saveProfile,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // ─── Cover ───
                      GestureDetector(
                        onTap: () => _pickAndCropImage(false),
                        onLongPress: () {
                          if (_coverUrl.isNotEmpty) _showImagePreview(_coverUrl);
                        },
                        child: Stack(
                          children: [
                            Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                image: _tempCoverPath != null
                                    ? DecorationImage(
                                        image: FileImage(File(_tempCoverPath!)),
                                        fit: BoxFit.cover)
                                    : (_coverUrl.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(_coverUrl),
                                            fit: BoxFit.cover)
                                        : null),
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: (_coverUrl.isEmpty && _tempCoverPath == null)
                                      ? const Icon(Icons.add_photo_alternate, size: 40)
                                      : null,
                            ),
                            if (_tempCoverPath != null)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: GestureDetector(
                                  onTap: () => setState(() => _tempCoverPath = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                        color: Colors.red, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                    color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  children: const [
                                    Icon(Icons.crop, color: Colors.white, size: 16),
                                    SizedBox(width: 4),
                                    Text("ຕັດ", style: TextStyle(color: Colors.white, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                            if (_coverUrl.isNotEmpty && _tempCoverPath == null)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                          color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.visibility, color: Colors.white, size: 14),
                                          SizedBox(width: 4),
                                          Text("ເບິ່ງ", style: TextStyle(color: Colors.white, fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _removeExistingPhoto(false),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                            color: Colors.red, shape: BoxShape.circle),
                                        child: const Icon(Icons.delete, color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── Profile Photo ───
                      GestureDetector(
                        onTap: () => _pickAndCropImage(true),
                        onLongPress: () {
                          if (_photoUrl.isNotEmpty) _showImagePreview(_photoUrl);
                        },
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.grey[300],
                              backgroundImage: _tempPhotoPath != null
                                  ? FileImage(File(_tempPhotoPath!))
                                  : (_photoUrl.isNotEmpty
                                      ? NetworkImage(_photoUrl)
                                      : null),
                              child: (_photoUrl.isEmpty && _tempPhotoPath == null)
                                      ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                      : null,
                            ),
                            if (_tempPhotoPath != null)
                              Positioned(
                                top: 0,
                                left: 0,
                                child: GestureDetector(
                                  onTap: () => setState(() => _tempPhotoPath = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                        color: Colors.red, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.teal,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.crop, color: Colors.white, size: 16),
                              ),
                            ),
                            if (_photoUrl.isNotEmpty && _tempPhotoPath == null)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _removeExistingPhoto(true),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                        color: Colors.red, shape: BoxShape.circle),
                                    child: const Icon(Icons.delete, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _displayNameController,
                        decoration: const InputDecoration(labelText: "ຊື່ສະແດງ *"),
                        validator: (v) => v!.isEmpty ? "ກະລุนາປ້ອນຊື່" : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bioController,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: "ກ່ຽວກັບຂ້ອຍ"),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text("ບັນທຶກ", style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}