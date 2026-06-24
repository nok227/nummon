import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/api_Cloudinary.dart'; // 🌟 เรียกใช้ Config ส่วนกลางเพื่อความเป็นระบบ

class AddHighlightPage extends StatefulWidget {
  const AddHighlightPage({super.key});

  @override
  State<AddHighlightPage> createState() => _AddHighlightPageState();
}

class _AddHighlightPageState extends State<AddHighlightPage> {
  final _titleController = TextEditingController();
  List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images.map((x) => File(x.path)));
          if (_selectedImages.length > 10) _selectedImages = _selectedImages.sublist(0, 10);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("ເກີດຂໍ້ຜິດພາດ: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<List<String>> _uploadImages() async {
    final cloudName = CloudinaryConfig.cloudinaryCloudName;
    final uploadPreset = CloudinaryConfig.cloudinaryUploadPreset;
    List<String> urls = [];
    
    for (var file in _selectedImages) {
      try {
        final uri = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
        final request = http.MultipartRequest("POST", uri);
        request.fields['upload_preset'] = uploadPreset;
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        final response = await request.send();
        
        if (response.statusCode == 200) {
          final bytes = await response.stream.toBytes();
          final json = jsonDecode(String.fromCharCodes(bytes));
          urls.add(json['secure_url']);
        } else {
          throw Exception("Upload failed: ${response.statusCode}");
        }
      } catch (e) {
        throw Exception("Error uploading: $e");
      }
    }
    return urls;
  }

  Future<void> _saveHighlight() async {
    if (_titleController.text.trim().isEmpty || _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ກະລຸນາປ້ອນຊື່ ແລະ ເເລືອກຮູບ")),
      );
      return;
    }

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final imageUrls = await _uploadImages();
      
      final newHighlight = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': _titleController.text.trim(),
        'coverImage': imageUrls.first,
        'images': imageUrls,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      await userRef.set({
        'highlights': FieldValue.arrayUnion([newHighlight])
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ເພີ່ມໄຮໄລທ໌"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.teal),
                  SizedBox(height: 16),
                  Text("ກຳລັງອັບໂຫຼດ... ກະລຸນາລໍຖ້າ"),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: "ຊື່ໄຮໄລທ໌ (ຕົວຢ່າງ: ທ່ຽວປາກລາຍ)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("ເລືອກຮູບພາບ (ສູงສຸດ 10 ຮູບ)", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length + 1,
                      itemBuilder: (context, i) {
                        if (i == _selectedImages.length) {
                          return GestureDetector(
                            onTap: _pickImages,
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[400]!),
                              ),
                              child: const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(_selectedImages[i], fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedImages.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.red,
                                  child: Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _saveHighlight,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("ບັນທຶກໄຮໄລທ໌", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }
}