// lib/app_config.dart
class CloudinaryConfig {
  // 1. แก้ไขจาก "nummon_no1" เป็น "aqfrs8hx" ตามที่ปรากฏในหน้าเว็บของคุณ
  static const String cloudName = "aqfrs8hx"; 
  static const String apiKey = "785729656554638"; 
  static const String apiSecret =
      "YOGYjgUFihAo-QTdmTQG4BhcKY4"; 

  // models/api_cloudinary.dart
  // 2. แก้ไขจุดนี้ให้เป็นชื่อเดียวกันด้วยครับ
  static const String cloudinaryCloudName = "aqfrs8hx";
  static const String cloudinaryApiKey =
      "785729656554638"; 
  static const String cloudinaryApiSecret =
      "YOGYjgUFihAo-QTdmTQG4BhcKY4"; 
  static const String cloudinaryUploadPreset = "Nummon";
}