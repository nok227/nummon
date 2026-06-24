class ExtraPlace {
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final String imageUrl;
  final List<String>? imageUrls;

  ExtraPlace({
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.imageUrl = '',
    this.imageUrls,
  });

  // ดึงรายการรูปภาพทั้งหมดของจุดย่อยนี้ (ใช้ imageUrls ถ้ามี ไม่งั้นใช้ imageUrl เดี่ยว)
  List<String> get allImages {
    if (imageUrls != null && imageUrls!.isNotEmpty) return imageUrls!;
    if (imageUrl.isNotEmpty) return [imageUrl];
    return [];
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
    };
  }

  factory ExtraPlace.fromMap(Map<String, dynamic> map) {
    return ExtraPlace(
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      imageUrl: map['imageUrl'] ?? '',
      imageUrls: (map['imageUrls'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

class Place {
  final String id;
  final String name;
  final String district;
  final String description;
  final String imageUrl;
  final List<String>? imageUrls;
  final double latitude;
  final double longitude;
  final List<ExtraPlace>? extraPlaces;
  final double imageAlignmentY; // <-- เพิ่มคุณสมบัตินี้รองรับแนวตั้ง

  Place({
    required this.id,
    required this.name,
    required this.district,
    required this.description,
    required this.imageUrl,
    this.imageUrls,
    required this.latitude,
    required this.longitude,
    this.extraPlaces,
    this.imageAlignmentY = 0.0, // <-- ค่าเริ่มต้นเป็น 0.0 (กึ่งกลาง)
  });

  factory Place.fromMap(String id, Map<String, dynamic> map) {
    List<ExtraPlace>? extraList;
    if (map['extraPlaces'] != null) {
      extraList = (map['extraPlaces'] as List<dynamic>)
          .map((e) => ExtraPlace.fromMap(e as Map<String, dynamic>))
          .toList();
    }
    return Place(
      id: id,
      name: map['name'] ?? '',
      district: map['district'] ?? '',
      description: map['description'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      imageUrls: (map['imageUrls'] as List<dynamic>?)?.cast<String>(),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      extraPlaces: extraList,
      imageAlignmentY: (map['imageAlignmentY'] ?? 0.0).toDouble(), // <-- ดึงข้อมูลจากฐานข้อมูล
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'district': district,
      'description': description,
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
      'latitude': latitude,
      'longitude': longitude,
      'extraPlaces': extraPlaces?.map((e) => e.toMap()).toList(),
      'imageAlignmentY': imageAlignmentY, // <-- ส่งบันทึกขึ้น Firestore
    };
  }
}