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

// ── ตัวร่างข้อมูลของ "จุดย่อย" (Extra Place) ก่อนบันทึกลง Firestore ──
// เก็บไฟล์รูปที่เลือกไว้ในเครื่อง (XFile) รอตอนบันทึกค่อยอัปโหลดขึ้น Cloudinary
class _ExtraPlaceDraft {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descController = TextEditingController();
  List<XFile> images = [];
  ll.LatLng? location;

  void dispose() {
    nameController.dispose();
    descController.dispose();
  }
}

class AdminAddPlacePage extends StatefulWidget {
  final ScrollController scrollController;
  const AdminAddPlacePage({super.key, required this.scrollController});

  @override
  State<AdminAddPlacePage> createState() => _AdminAddPlacePageState();
}

class _AdminAddPlacePageState extends State<AdminAddPlacePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  int _uploadProgress = 0;

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
    'ເມືອງໄຊສະຖານ'
  ];

  ll.LatLng? _pickedLocation;

  // ── รายการ "จุดท่องเที่ยวย่อย" ที่ผู้ดูแลเพิ่มเข้ามา (ยังไม่ได้อัปโหลด) ──
  final List<_ExtraPlaceDraft> _extraDrafts = [];

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

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
          if (_selectedImages.length > 15) {
            _selectedImages = _selectedImages.sublist(0, 15);
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

  // ── เปิดหน้าต่างสำหรับเพิ่ม / แก้ไข "จุดท่องเที่ยวย่อย" หนึ่งจุด ──
  Future<void> _openExtraPlaceDialog({int? editIndex}) async {
    final draft = editIndex != null ? _extraDrafts[editIndex] : _ExtraPlaceDraft();

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
              final List<XFile> imgs = await _picker.pickMultiImage();
              if (imgs.isNotEmpty) {
                setSheetState(() {
                  draft.images.addAll(imgs);
                  if (draft.images.length > 10) {
                    draft.images = draft.images.sublist(0, 10);
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
                      editIndex != null ? 'ແກ້ໄຂຈຸດທ່ອງທ່ຽວຍ່ອຍ' : 'ເພີ່ມຈຸດທ່ອງທ່ຽວຍ່ອຍ',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // ── รูปภาพของจุดย่อย ──
                    SizedBox(
                      height: 90,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
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
                                        width: 80, height: 80, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setSheetState(() => draft.images.removeAt(i)),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                            color: Colors.red, shape: BoxShape.circle),
                                        child: const Icon(Icons.close,
                                            color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          GestureDetector(
                            onTap: pickSubImages,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.teal[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add_a_photo, color: Colors.teal),
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
                          side: const BorderSide(color: Colors.teal, width: 1.5),
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
                              const SnackBar(content: Text('ກະລຸນາປ້ອນຊື່ຈຸດຍ່ອຍ')),
                            );
                            return;
                          }
                          if (draft.location == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ກະລຸນາປັກໝຸດພິກັດ')),
                            );
                            return;
                          }
                          Navigator.pop(context, true);
                        },
                        child: const Text('ບັນທຶກຈຸດຍ່ອຍ',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // ── อัปโหลดรูปภาพหนึ่งไฟล์ขึ้น Cloudinary แล้วคืน secure_url ──
  Future<String> _uploadOneImage(XFile file) async {
    const String cloudName = "duo2b46ro";
    const String uploadPreset = "travel_app_preset";
    var uri = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
    var request = http.MultipartRequest("POST", uri);
    request.fields['upload_preset'] = uploadPreset;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    if (response.statusCode == 200) {
      var responseData = await response.stream.toBytes();
      var result = json.decode(String.fromCharCodes(responseData));
      return result['secure_url'] as String;
    } else {
      throw Exception("ອັບໂຫລດຮູບບໍ່ສຳເລັດ");
    }
  }

  Future<void> _savePlace() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty) {
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

    setState(() {
      _isSaving = true;
      _uploadProgress = 0;
    });

    List<String> uploadedImageUrls = [];
    String placeId = FirebaseFirestore.instance.collection('places').doc().id;

    const String cloudName = "duo2b46ro";
    const String uploadPreset = "travel_app_preset";

    try {
      for (int i = 0; i < _selectedImages.length; i++) {
        File file = File(_selectedImages[i].path);
        var uri = Uri.parse(
            "https://api.cloudinary.com/v1_1/$cloudName/image/upload");
        var request = http.MultipartRequest("POST", uri);
        request.fields['upload_preset'] = uploadPreset;
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var response = await request.send();
        if (response.statusCode == 200) {
          var responseData = await response.stream.toBytes();
          var result = json.decode(String.fromCharCodes(responseData));
          uploadedImageUrls.add(result['secure_url'] as String);
          setState(() => _uploadProgress = i + 1);
        } else {
          throw Exception("ອັບໂຫລດຮູບທີ ${i + 1} ບໍ່ສຳເລັດ");
        }
      }

      // ── อัปโหลดรูปของ "จุดท่องเที่ยวย่อย" แต่ละจุด แล้วประกอบเป็น ExtraPlace ──
      List<Map<String, dynamic>> extraPlacesData = [];
      for (final draft in _extraDrafts) {
        List<String> subUrls = [];
        for (final img in draft.images) {
          final url = await _uploadOneImage(img);
          subUrls.add(url);
        }
        extraPlacesData.add(ExtraPlace(
          name: draft.nameController.text.trim(),
          description: draft.descController.text.trim(),
          latitude: draft.location!.latitude,
          longitude: draft.location!.longitude,
          imageUrl: subUrls.isNotEmpty ? subUrls.first : '',
          imageUrls: subUrls,
        ).toMap());
      }

      await FirebaseFirestore.instance.collection('places').doc(placeId).set({
        'id': placeId,
        'name': _nameController.text.trim(),
        'district': _selectedDistrict,
        'description': _descriptionController.text.trim(),
        'latitude': double.tryParse(_latitudeController.text.trim()) ?? 0.0,
        'longitude': double.tryParse(_longitudeController.text.trim()) ?? 0.0,
        'imageUrl': uploadedImageUrls.isNotEmpty ? uploadedImageUrls.first : '',
        'imageUrls': uploadedImageUrls,
        'extraPlaces': extraPlacesData,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ບັນທຶກ ແລະ ອັບໂຫລດຮູບພາບສຳເລັດ!'),
            backgroundColor: Colors.teal,
          ),
        );
        _nameController.clear();
        _descriptionController.clear();
        _latitudeController.clear();
        _longitudeController.clear();
        for (final draft in _extraDrafts) {
          draft.dispose();
        }
        setState(() {
          _selectedImages.clear();
          _selectedDistrict = null;
          _pickedLocation = null;
          _uploadProgress = 0;
          _extraDrafts.clear();
        });
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ເພີ່ມສະຖານທີ່ໃໝ່ (Admin)',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
                    'ກຳລັງອັບໂຫລດ $_uploadProgress / ${_selectedImages.length} ຮູບ...',
                    style: TextStyle(
                        color: Colors.teal[700], fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: LinearProgressIndicator(
                      value: _selectedImages.isEmpty
                          ? 0
                          : _uploadProgress / _selectedImages.length,
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
                    // ── ส่วนเลือกรูปภาพ ──
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
                      child: _selectedImages.isEmpty
                          ? Center(
                              child: TextButton.icon(
                                onPressed: _pickImages,
                                icon: const Icon(Icons.add_a_photo,
                                    size: 30, color: Colors.teal),
                                label: const Text('ກົດເລືອກຮູບພາບ',
                                    style: TextStyle(color: Colors.teal)),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(8),
                              scrollDirection: Axis.horizontal,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 1, mainAxisSpacing: 8),
                              itemCount: _selectedImages.length +
                                  (_selectedImages.length < 15 ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _selectedImages.length) {
                                  return GestureDetector(
                                    onTap: _pickImages,
                                    child: Container(
                                      decoration: BoxDecoration(
                                          color: Colors.teal[50],
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: const Icon(Icons.add,
                                          color: Colors.teal, size: 40),
                                    ),
                                  );
                                }
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(_selectedImages[index].path),
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: GestureDetector(
                                        onTap: () => setState(() =>
                                            _selectedImages.removeAt(index)),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ເລືອກໄປແລ້ວ ${_selectedImages.length}/15 ຮູບ',
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

                    // ── เลือกเมือง ──
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

                    // ── รายละเอียด ──
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

                    // ── ปุ่มเปิด Map Picker ──
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

                    // ── แสดงพิกัดที่เลือก ──
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

                    // ── Preview Map ──
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
                                flags: InteractiveFlag.none,
                              ),
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

                    // ── ส่วน "จุดท่องเที่ยวย่อย" (สามารถปักหมุด+แนบรูปได้เหมือนสถานที่หลัก) ──
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ຈຸດທ່ອງທ່ຽວຍ່ອຍ (ປັກໝຸດ + ແນບຮູບໄດ້)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        TextButton.icon(
                          onPressed: () => _openExtraPlaceDialog(),
                          icon: const Icon(Icons.add_location_alt, color: Colors.teal),
                          label: const Text('ເພີ່ມຈຸດຍ່ອຍ', style: TextStyle(color: Colors.teal)),
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
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: draft.images.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(
                                        File(draft.images.first.path),
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(Icons.image_not_supported, color: Colors.grey),
                              title: Text(draft.nameController.text.isEmpty
                                  ? '(ไม่มีชื่อ)'
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
                                    icon: const Icon(Icons.edit, color: Colors.teal, size: 20),
                                    onPressed: () => _openExtraPlaceDialog(editIndex: index)
                                        .then((_) => setState(() {})),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
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
                        label: const Text(
                          'ບັນທຶກ ແລະ ອັບໂຫລດຮູບພາບ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}