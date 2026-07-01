import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OneSignalService {
  static final OneSignalService _instance = OneSignalService._internal();
  factory OneSignalService() => _instance;
  OneSignalService._internal();

  bool _isInitialized = false;
  bool _observerRegistered = false;

  // ✅ ใช้ dotenv
  String get appId => dotenv.env['ONESIGNAL_APP_ID'] ?? '';
  String get restApiKey => dotenv.env['ONESIGNAL_REST_API_KEY'] ?? '';

  void initialize() {
    if (_isInitialized) return;

    if (appId.isEmpty) {
      debugPrint('⚠️ OneSignal App ID ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ');
      return;
    }

    OneSignal.Debug.setLogLevel(OSLogLevel.none);
    OneSignal.initialize(appId);
    OneSignal.Notifications.requestPermission(true);

    _isInitialized = true;
    debugPrint('✅ OneSignal initialized');
  }

  void login(String externalId) {
    if (!_isInitialized) {
      debugPrint('⚠️ OneSignal ຍັງບໍ່ໄດ້ initialize');
      return;
    }
    OneSignal.login(externalId);
    debugPrint("✅ OneSignal Login: $externalId");
  }

  void logout() {
    if (!_isInitialized) return;
    OneSignal.logout();
    debugPrint("✅ OneSignal Logout");
  }

  void setTag(String key, String value) {
    if (!_isInitialized) return;
    OneSignal.User.addTagWithKey(key, value);
  }

  void setupPushSubscriptionObserver(BuildContext context) {
    if (_observerRegistered) return;
    if (!_isInitialized) {
      debugPrint('⚠️ OneSignal ຍັງບໍ່ໄດ້ initialize');
      return;
    }
    _observerRegistered = true;

    OneSignal.User.pushSubscription.addObserver((state) {
      final previousId = state.previous.id;
      final currentId = state.current.id;

      if ((previousId == null || previousId.isEmpty) &&
          currentId != null &&
          currentId.isNotEmpty) {
        _showWelcomeDialog(context);
      }
    });
  }

  void _showWelcomeDialog(BuildContext context) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Your OneSignal integration is complete!'),
        content: const Text(
            'Click the button below to trigger your first journey via an in-app message.'),
        actions: [
          TextButton(
            onPressed: () {
              OneSignal.InAppMessages.addTrigger(
                  "ai_implementation_campaign_email_journey", "true");
              Navigator.pop(context);
            },
            child: const Text('Trigger your first journey'),
          ),
        ],
      ),
    );
  }

  Future<void> sendChatNotification({
    required String receiverExternalId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (restApiKey.isEmpty) {
      debugPrint('⚠️ OneSignal REST API Key ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ');
      return;
    }

    if (appId.isEmpty) {
      debugPrint('⚠️ OneSignal App ID ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.onesignal.com/notifications?c=push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Key $restApiKey',
        },
        body: jsonEncode({
          'app_id': appId,
          'include_aliases': {
            'external_id': [receiverExternalId]
          },
          'target_channel': 'push',
          'headings': {'en': title},
          'contents': {'en': body},
          'ios_badgeType': 'Increase',
          'ios_badgeCount': 1,
          if (data != null) 'data': data,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ ສົ່ງ push notification ສຳເລັດ: ${response.body}');
      } else {
        debugPrint(
            '❌ ສົ່ງ push notification ຜິດພາດ (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('OneSignal sendChatNotification error: $e');
    }
  }
}