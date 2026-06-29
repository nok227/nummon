import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../routes/map_picker.dart';
import '../models/place_model.dart';
import '../models/api_Cloudinary.dart';

// ──────────────────────────────────────────────────────────────
// โมเดลจุดย่อย (draft ที่ยังไม่ได้อัปโหลด)
// ──────────────────────────────────────────────────────────────
class _ExtraPlaceDraft {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descController = TextEditingController();

  /// รูปใหม่ที่เลือกจากเครื่อง (XFile)
  List<XFile> images = [];

  /// URL รูปเก่าจาก Cloudinary (กรณี Edit)
  List<String> existingImageUrls = [];

  ll.LatLng? location;

  void dispose() {
    nameController.dispose();
    descController.dispose();
  }

  /// รูปทั้งหมดที่จะแสดงใน UI (เก่า + ใหม่)
  int get totalImageCount => existingImageUrls.length + images.length;
}

// ──────────────────────────────────────────────────────────────
// Widget หลัก
// ──────────────────────────────────────────────────────────────
class AdminAddPlacePage extends StatefulWidget {
  final ScrollController scrollController;

  /// ถ้าส่ง editPlace มา = โหมดแก้ไข, ถ้าไม่ส่ง = โหมดเพิ่มใหม่
  final Place? editPlace;

  const AdminAddPlacePage({
    super.key,
    required this.scrollController,
    this.editPlace,
  });

  @override
  State<AdminAddPlacePage> createState() => _AdminAddPlacePageState();
}

class _AdminAddPlacePageState extends State<AdminAddPlacePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  /// รูปใหม่ที่เลือกจากเครื่อง
  List<XFile> _selectedImages = [];

  /// URL รูปเก่า (กรณี Edit)
  List<String> _existingImageUrls = [];

  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  int _uploadProgress = 0;
  int _totalToUpload = 0;

  String? _selectedDistrict;
  final List<String> _districts = [
    'ເມືອງໄຊຍະບູລີ',
    'ເມືອງຂອບ',
    'ເມືອງຫົງສາ',
    'ເມືອງເງິນ',
    'ເມືອງຊຽງຮ່ອນ',
    'ເມືອງພຽງ',
    'ເມືອງປາກລາຍ',
    'ເມືອງແກ່ນທ້າວ',
    'ເມືອງບໍ່ແຕນ',
    'ເມືອງທົ່ງມີໄຊ',
    'ເມືອງໄຊສະຖານ',
  ];

  ll.LatLng? _pickedLocation;
  final List<_ExtraPlaceDraft> _extraDrafts = [];

  /// โหมดปัจจุบัน
  bool get _isEditMode => widget.editPlace != null;

  @override
  void initState() {
    super.initState();
    _prefillIfEditMode();
  }

  /// Pre-fill ฟอร์มทุกฟิลด์เมื่ออยู่โหมดแก้ไข
  void _prefillIfEditMode() {
    final place = widget.editPlace;
    if (place == null) return;

    _nameController.text = place.name;
    _descriptionController.text = place.description;
    _selectedDistrict = place.district;
    _latitudeController.text = place.latitude.toStringAsFixed(6);
    _longitudeController.text = place.longitude.toStringAsFixed(6);
    _pickedLocation = ll.LatLng(place.latitude, place.longitude);

    // รูปเก่า
    if (place.imageUrls != null && place.imageUrls!.isNotEmpty) {
      _existingImageUrls = List<String>.from(place.imageUrls!);
    } else if (place.imageUrl.isNotEmpty) {
      _existingImageUrls = [place.imageUrl];
    }

    // จุดย่อยเก่า
    if (place.extraPlaces != null) {
      for (final extra in place.extraPlaces!) {
        final draft = _ExtraPlaceDraft();
        draft.nameController.text = extra.name;
        draft.descController.text = extra.description;
        draft.location = ll.LatLng(extra.latitude, extra.longitude);
        draft.existingImageUrls = List<String>.from(extra.allImages);
        _extraDrafts.add(draft);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    for (final draft in _extraDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // ปักหมุดพิกัด
  // ──────────────────────────────────────────────────────────────
  Future<void> _openMapToPickLocation() async {
    final ll.LatLng? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MapPickerPage()),
    );

    if (result != null && mounted) {
      setState(() {
        _pickedLocation = result;
        _latitudeController.text = result.latitude.toStringAsFixed(6);
        _longitudeController.text = result.longitude.toStringAsFixed(6);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ດຶງພິກັດຈາກແຜນທີ່ສຳເລັດ!'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────
  // เลือกรูปภาพหลัก
  // ──────────────────────────────────────────────────────────────
  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1920,
      );
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
          final total = _existingImageUrls.length + _selectedImages.length;
          if (total > 15) {
            final canAdd = 15 - _existingImageUrls.length;
            _selectedImages = _selectedImages.sublist(
                0, canAdd.clamp(0, _selectedImages.length));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ສູງສຸດ 15 ຮູບ')),
            );
          }
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Dialog จุดย่อย
  // ──────────────────────────────────────────────────────────────
  Future<void> _openExtraPlaceDialog({int? editIndex}) async {
    final draft =
        editIndex != null ? _extraDrafts[editIndex] : _ExtraPlaceDraft();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickSubImages() async {
              final List<XFile> imgs = await _picker.pickMultiImage(
                imageQuality: 70,
                maxWidth: 1920,
              );
              if (imgs.isNotEmpty) {
                setSheetState(() {
                  draft.images.addAll(imgs);
                  if (draft.totalImageCount > 10) {
                    final canAdd = 10 - draft.existingImageUrls.length;
                    draft.images = draft.images
                        .sublist(0, canAdd.clamp(0, draft.images.length));
                  }
                });
              }
            }

            Future<void> pickSubLocation() async {
              final ll.LatLng? result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MapPickerPage()),
              );
              if (result != null) {
                setSheetState(() => draft.location = result);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      editIndex != null
                          ? 'ແກ້ໄຂຈຸດທ່ອງທ່ຽວຍ່ອຍ'
                          : 'ເພີ່ມຈຸດທ່ອງທ່ຽວຍ່ອຍ',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // ── รูปจุดย่อย ──
                    SizedBox(
                      height: 90,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // รูปเก่า (URL)
                          ...draft.existingImageUrls
                              .asMap()
                              .entries
                              .map((entry) {
                            final i = entry.key;
                            final url = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(url,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => setSheetState(() =>
                                          draft.existingImageUrls.removeAt(i)),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          // รูปใหม่ (XFile)
                          ...draft.images.asMap().entries.map((entry) {
                            final i = entry.key;
                            final img = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(File(img.path),
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => setSheetState(
                                          () => draft.images.removeAt(i)),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          // ปุ่มเพิ่มรูป
                          GestureDetector(
                            onTap: pickSubImages,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.teal[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add_a_photo,
                                  color: Colors.teal),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: draft.nameController,
                      decoration: const InputDecoration(
                        labelText: 'ຊື່ຈຸດຍ່ອຍ *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: draft.descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ລາຍລະອຽດ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: pickSubLocation,
                        icon: const Icon(Icons.location_on, color: Colors.red),
                        label: Text(
                          draft.location == null
                              ? 'ປັກໝຸດພິກັດຈຸດຍ່ອຍ'
                              : 'ພິກັດ: ${draft.location!.latitude.toStringAsFixed(5)}, ${draft.location!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: Colors.teal, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: Colors.teal, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          if (draft.nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('ກະລຸນາປ້ອນຊື່ຈຸດຍ່ອຍ')),
                            );
                            return;
                          }
                          if (draft.location == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('ກະລຸນາປັກໝຸດພິກັດ')),
                            );
                            return;
                          }
                          Navigator.pop(context, true);
                        },
                        child: const Text('ບັນທຶກຈຸດຍ່ອຍ',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      setState(() {
        if (editIndex == null) _extraDrafts.add(draft);
      });
    }
  }

  void _removeExtraPlace(int index) {
    setState(() {
      _extraDrafts[index].dispose();
      _extraDrafts.removeAt(index);
    });
  }

  // ──────────────────────────────────────────────────────────────
  // อัปโหลดรูปเดียว
  // ──────────────────────────────────────────────────────────────
// ──────────────────────────────────────────────────────────────
  // ອັບໂຫລດຮູບດຽວ (ແກ້ໄຂເພື່ອເບິ່ງ Error)
  // ──────────────────────────────────────────────────────────────
  Future<String> _uploadOneImage(XFile file) async {
    const cloudName = CloudinaryConfig.cloudName;
    const uploadPreset = CloudinaryConfig.cloudinaryUploadPreset;
    var uri =
        Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
    var request = http.MultipartRequest("POST", uri);
    request.fields['upload_preset'] = uploadPreset;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    
    var response = await request.send();
    
    // ອ່ານຄ່າຄຳຕອບກັບຈາກ Cloudinary ທັງໝົດ
    var responseData = await response.stream.toBytes();
    var responseString = String.fromCharCodes(responseData);

    if (response.statusCode == 200) {
      var result = json.decode(responseString);
      return result['secure_url'] as String;
    } else {
      // ປິຼ້ນ Error ທີ່ Cloudinary ສົ່ງກັບມາອອກເບິ່ງໃນ Console ທາງລຸ່ມ
      debugPrint("❌ Cloudinary Error: $responseString (Status: ${response.statusCode})");
      throw Exception("ອັບໂຫລດຮູບບໍ່ສຳເລັດ: $responseString");
    }
  }

  // ──────────────────────────────────────────────────────────────
  // บันทึก (เพิ่มใหม่ หรือ อัปเดต)
  // ──────────────────────────────────────────────────────────────
  Future<void> _savePlace() async {
    if (!_formKey.currentState!.validate()) return;

    final totalMainImages = _existingImageUrls.length + _selectedImages.length;
    if (totalMainImages == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ກະລຸນາເລືອກຮູບພາບຢ່າງໜ້ອຍ 1 ຮູບ')),
      );
      return;
    }
    if (_selectedDistrict == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ກະລຸນາເລືອກ ເມືອງ / ອຳເພີ')),
      );
      return;
    }

    // คำนวณจำนวนรูปที่ต้องอัปโหลดทั้งหมด
    int totalNew = _selectedImages.length;
    for (final d in _extraDrafts) {
      totalNew += d.images.length;
    }

    setState(() {
      _isSaving = true;
      _uploadProgress = 0;
      _totalToUpload = totalNew;
    });

    try {
      // ── อัปโหลดรูปหลักใหม่ ──
      final List<String> newMainUrls = [];
      for (final img in _selectedImages) {
        final url = await _uploadOneImage(img);
        newMainUrls.add(url);
        setState(() => _uploadProgress++);
      }

      // รวมรูปเก่า + รูปใหม่
      final List<String> allMainUrls = [
        ..._existingImageUrls,
        ...newMainUrls,
      ];

      // ── อัปโหลดรูปจุดย่อยใหม่ + รวมกับเก่า ──
      final List<Map<String, dynamic>> extraPlacesData = [];
      for (final draft in _extraDrafts) {
        final List<String> newSubUrls = [];
        for (final img in draft.images) {
          final url = await _uploadOneImage(img);
          newSubUrls.add(url);
          setState(() => _uploadProgress++);
        }

        final allSubUrls = [...draft.existingImageUrls, ...newSubUrls];

        extraPlacesData.add(ExtraPlace(
          name: draft.nameController.text.trim(),
          description: draft.descController.text.trim(),
          latitude: draft.location!.latitude,
          longitude: draft.location!.longitude,
          imageUrl: allSubUrls.isNotEmpty ? allSubUrls.first : '',
          imageUrls: allSubUrls,
        ).toMap());
      }

      // ── ID: ใช้ของเดิม (edit) หรือสร้างใหม่ ──
      final placeId = _isEditMode
          ? widget.editPlace!.id
          : FirebaseFirestore.instance.collection('places').doc().id;

      final Map<String, dynamic> data = {
        'id': placeId,
        'name': _nameController.text.trim(),
        'district': _selectedDistrict,
        'description': _descriptionController.text.trim(),
        'latitude': double.tryParse(_latitudeController.text.trim()) ?? 0.0,
        'longitude': double.tryParse(_longitudeController.text.trim()) ?? 0.0,
        'imageUrl': allMainUrls.isNotEmpty ? allMainUrls.first : '',
        'imageUrls': allMainUrls,
        'extraPlaces': extraPlacesData,
        // คงค่า imageAlignmentY เดิมไว้ (ถ้าเป็น edit mode)
        'imageAlignmentY':
            _isEditMode ? (widget.editPlace!.imageAlignmentY) : 0.0,
        if (!_isEditMode) 'createdAt': FieldValue.serverTimestamp(),
        if (_isEditMode) 'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .set(data, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'ອັບເດດຂໍ້ມູນສຳເລັດ!'
                : 'ບັນທຶກ ແລະ ອັບໂຫລດຮູບພາບສຳເລັດ!'),
            backgroundColor: Colors.teal,
          ),
        );

        if (_isEditMode) {
          // Reload ข้อมูลจาก Firestore เพื่อให้ได้ข้อมูลล่าสุดที่ถูกต้อง
          final doc = await FirebaseFirestore.instance
              .collection('places')
              .doc(placeId)
              .get();
          final updatedPlace = Place.fromMap(placeId, doc.data()!);
          if (mounted) Navigator.pop(context, updatedPlace);
        } else {
          // โหมดเพิ่มใหม่: รีเซ็ตฟอร์ม
          _nameController.clear();
          _descriptionController.clear();
          _latitudeController.clear();
          _longitudeController.clear();
          for (final draft in _extraDrafts) {
            draft.dispose();
          }
          setState(() {
            _selectedImages.clear();
            _existingImageUrls.clear();
            _selectedDistrict = null;
            _pickedLocation = null;
            _uploadProgress = 0;
            _extraDrafts.clear();
          });
        }
      }
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ເກີດຂໍ້ຜິດພາດ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
    ;
  }

  // ──────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final totalImages = _existingImageUrls.length + _selectedImages.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'ແກ້ໄຂສະຖານທີ່' : 'ເພີ່ມສະຖານທີ່ໃໝ່ (Admin)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    'ກຳລັງອັບໂຫລດ $_uploadProgress / $_totalToUpload ຮູບ...',
                    style: TextStyle(
                        color: Colors.teal[700], fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: LinearProgressIndicator(
                      value: _totalToUpload == 0
                          ? 0
                          : _uploadProgress / _totalToUpload,
                      color: Colors.teal,
                      backgroundColor: Colors.teal.shade100,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── ส่วนรูปภาพหลัก ──
                    const Text(
                      'ຮູບພາບສະຖານທີ່ (ສູງສຸດ 15 ຮູບ) *',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: totalImages == 0
                          ? Center(
                              child: TextButton.icon(
                                onPressed: _pickImages,
                                icon: const Icon(Icons.add_a_photo,
                                    size: 30, color: Colors.teal),
                                label: const Text('ກົດເລືອກຮູບພາບ',
                                    style: TextStyle(color: Colors.teal)),
                              ),
                            )
                          : ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.all(8),
                              children: [
                                // รูปเก่า (URL)
                                ..._existingImageUrls
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final i = entry.key;
                                  final url = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(
                                            url,
                                            width: 140,
                                            height: 140,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                                _existingImageUrls.removeAt(i)),
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle),
                                              child: const Icon(Icons.close,
                                                  color: Colors.white,
                                                  size: 18),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 4,
                                          left: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.black.withOpacity(0.5),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text('ຮູບເກົ່າ',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                // รูปใหม่ (XFile)
                                ..._selectedImages.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final img = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.file(
                                            File(img.path),
                                            width: 140,
                                            height: 140,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                                _selectedImages.removeAt(i)),
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle),
                                              child: const Icon(Icons.close,
                                                  color: Colors.white,
                                                  size: 18),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                // ปุ่มเพิ่มรูป
                                if (totalImages < 15)
                                  GestureDetector(
                                    onTap: _pickImages,
                                    child: Container(
                                      width: 140,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        color: Colors.teal[50],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.add,
                                          color: Colors.teal, size: 40),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ເລືອກໄປແລ້ວ $totalImages/15 ຮູບ',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const Divider(height: 28),

                    // ── ชื่อสถานที่ ──
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'ຊື່ສະຖານທີ່ *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'ກະລຸນາປ້ອນຊື່ສະຖານທີ່' : null,
                    ),
                    const SizedBox(height: 16),

                    // ── เมือง / อำเภอ ──
                    DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      decoration: const InputDecoration(
                        labelText: 'ເມືອງ / ອຳເພີ *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      hint: const Text('ກະລຸນາເລືອກ ເມືອງ'),
                      items: _districts
                          .map(
                              (d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedDistrict = v),
                      validator: (v) => v == null ? 'ກະລຸນາເລືອກ ເມືອງ' : null,
                    ),
                    const SizedBox(height: 16),

                    // ── คำอธิบาย ──
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ລາຍລະອຽດ *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? 'ກະລຸນາປ້ອນລາຍລະອຽດ' : null,
                    ),
                    const SizedBox(height: 20),

                    // ── ปักหมุดพิกัด ──
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _openMapToPickLocation,
                        icon: const Icon(Icons.location_on, color: Colors.red),
                        label: const Text(
                          'ປັກໝຸດພິກັດຈາກແຜນທີ່',
                          style: TextStyle(
                              color: Colors.teal, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: Colors.teal, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Latitude / Longitude ──
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latitudeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Latitude *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.map),
                            ),
                            validator: (v) =>
                                v!.isEmpty ? 'ກະລຸນາເລືອກພິກັດ' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _longitudeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Longitude *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.map),
                            ),
                            validator: (v) =>
                                v!.isEmpty ? 'ກະລຸນາເລືອກພິກັດ' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Preview แผนที่ ──
                    if (_pickedLocation != null) ...[
                      const Text(
                        'ຕຳແໜ່ງທີ່ເລືອກໃນແຜນທີ່:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 200,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: _pickedLocation!,
                              initialZoom: 14,
                              interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.abc_new',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _pickedLocation!,
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.location_pin,
                                        color: Colors.red, size: 40),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── จุดย่อย ──
                    // ── ຈຸດຍ່ອຍ ──
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ໃຫ້ແກ້ໄຂໂດຍການເພີ່ມ Expanded ຫໍ່ Text ໄວ້ບ່ອນນີ້
                        Expanded(
                          child: const Text(
                            'ຈຸດທ່ອງທ່ຽວຍ່ອຍ (ປັກໝຸດ + ແນບຮູບໄດ້)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _openExtraPlaceDialog(),
                          icon: const Icon(Icons.add_location_alt,
                              color: Colors.teal),
                          label: const Text('ເພີ່ມຈຸດຍ່ອຍ',
                              style: TextStyle(color: Colors.teal)),
                        ),
                      ],
                    ),
                    if (_extraDrafts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('ຍັງບໍ່ມີຈຸດທ່ອງທ່ຽວຍ່ອຍ',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _extraDrafts.length,
                        itemBuilder: (context, index) {
                          final draft = _extraDrafts[index];
                          // ภาพแรกที่จะแสดง (เก่าก่อน ถ้าไม่มีใช้ใหม่)
                          final firstExistUrl =
                              draft.existingImageUrls.isNotEmpty
                                  ? draft.existingImageUrls.first
                                  : null;
                          final firstNewImg = draft.images.isNotEmpty
                              ? draft.images.first
                              : null;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: firstExistUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(firstExistUrl,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover),
                                    )
                                  : firstNewImg != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Image.file(
                                              File(firstNewImg.path),
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover),
                                        )
                                      : const Icon(Icons.image_not_supported,
                                          color: Colors.grey),
                              title: Text(draft.nameController.text.isEmpty
                                  ? '(ບໍ່ມີຊື່)'
                                  : draft.nameController.text),
                              subtitle: Text(
                                draft.location != null
                                    ? 'Lat: ${draft.location!.latitude.toStringAsFixed(5)}, Lng: ${draft.location!.longitude.toStringAsFixed(5)}'
                                    : 'ຍັງບໍ່ໄດ້ປັກໝຸດ',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.teal, size: 20),
                                    onPressed: () =>
                                        _openExtraPlaceDialog(editIndex: index)
                                            .then((_) => setState(() {})),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red, size: 20),
                                    onPressed: () => _removeExtraPlace(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                    // ── ปุ่มบันทึก ──
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _savePlace,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon:
                            const Icon(Icons.cloud_upload, color: Colors.white),
                        label: Text(
                          _isEditMode
                              ? 'ອັບເດດ ແລະ ບັນທຶກການແກ້ໄຂ'
                              : 'ບັນທຶກ ແລະ ອັບໂຫລດຮູບພາບ',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}
