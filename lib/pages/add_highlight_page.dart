import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

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
  bool _isLoading = false;

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
    const cloudName = "duo2b46ro";
    const uploadPreset = "travel_app_preset";
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
          throw Exception("Upload failed with status ${response.statusCode}");
        }
      } catch (e) {
        throw Exception("Error uploading image: $e");
      }
    }
    return urls;
  }

  Future<void> _saveHighlight() async {
    if (_titleController.text.trim().isEmpty || _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ກະລຸນາປ້ອນຊື່ ແລະ ເລືອກຮູບຢ່າງໜ້ອຍ 1 ຮູບ")),
      );
      return;
    }

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ກະລຸນາເຂົ້າສູ່ລະບົບ"), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final imageUrls = await _uploadImages();
      final highlight = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': _titleController.text.trim(),
        'coverImage': imageUrls.first,
        'images': imageUrls,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userRef.update({
        'highlights': FieldValue.arrayUnion([highlight])
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ເພີ່ມໄຮໄລທ໌ສຳເລັດ!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ການອັບໂຫຼດລົ້ມເຫຼວ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: "ຊື່ໄຮໄລທ໌ (ຕົວຢ່າງ: ທ່ຽວປາກລາຍ)"),
                  ),
                  const SizedBox(height: 16),
                  const Text("ເລືອກຮູບພາບ (ສູງສຸດ 10 ຮູບ)"),
                  const SizedBox(height: 8),
                  Container(
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
                              color: Colors.grey[200],
                              child: const Icon(Icons.add_photo_alternate, size: 40),
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              child: Image.file(_selectedImages[i], fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 0,
                              right: 8,
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
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveHighlight,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text("ບັນທຶກໄຮໄລທ໌"),
                  ),
                ],
              ),
            ),
    );
  }
}