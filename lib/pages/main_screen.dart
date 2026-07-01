import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/place_model.dart';
import '../models/api_Cloudinary.dart';
import 'home.dart';
import 'explore.dart';
import 'tourist_attractions.dart';
import '../routes/map.dart';
import '../admin/admin_add_place.dart';
import '../private/profile_page.dart';
import '../services/onesignal_service.dart';

// ─── import หน้าแชท ───
import '../chats/chat_list_screen.dart';

class MainScreen extends StatefulWidget {
  final User? user; // ✅ เพิ่มบรรทัดนี้
  const MainScreen({super.key, this.user});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  bool _isFooterVisible = true;
  bool isAdmin = false;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  int _totalUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      OneSignalService().login(widget.user!.uid);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OneSignalService().setupPushSubscriptionObserver(context);
    });
    if (currentUser != null &&
        (currentUser!.email == 'admin_app@travel.com' ||
            currentUser!.email == 'admin_app')) {
      isAdmin = true;
    }
    _scrollController.addListener(() {
      final direction = _scrollController.position.userScrollDirection;
      if (direction == ScrollDirection.reverse && _isFooterVisible)
        setState(() => _isFooterVisible = false);
      if (direction == ScrollDirection.forward && !_isFooterVisible)
        setState(() => _isFooterVisible = true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _parseBudget(dynamic b) =>
      int.tryParse(b?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '') ?? 0;

  void _openMap(double lat, double lng, String placeName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapPage(
          latitude: lat,
          longitude: lng,
          placeName: placeName,
        ),
      ),
    );
  }

  void _openSharePostForm(Map<String, dynamic> planData) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ShareTripPostSheet(planData: planData),
    );
  }

  Future<void> _showEditPlanDialog(
      BuildContext context, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final startCtrl = TextEditingController(
        text: data['startDateTime'] == 'ຍັງບໍ່ໄດ້ກຳນົດ'
            ? ''
            : data['startDateTime']);
    final endCtrl = TextEditingController(
        text:
            data['endDateTime'] == 'ຍັງບໍ່ໄດ້ກຳນົດ' ? '' : data['endDateTime']);
    final budgetCtrl =
        TextEditingController(text: data['budget']?.toString() ?? '');

    Future<void> pickDateTime(TextEditingController controller) async {
      final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100));
      if (date != null && context.mounted) {
        final time = await showTimePicker(
            context: context, initialTime: TimeOfDay.now());
        if (time != null) {
          controller.text =
              "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
        }
      }
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ຈັດແຈງແຜນການ\n(${data['placeName']})',
            style: const TextStyle(fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: startCtrl,
                readOnly: true,
                onTap: () => pickDateTime(startCtrl),
                decoration: const InputDecoration(
                    labelText: 'ເວລາໄປ (Start Time)',
                    prefixIcon: Icon(Icons.access_time))),
            const SizedBox(height: 10),
            TextField(
                controller: endCtrl,
                readOnly: true,
                onTap: () => pickDateTime(endCtrl),
                decoration: const InputDecoration(
                    labelText: 'ເວລາກັບ (End Time)',
                    prefixIcon: Icon(Icons.access_time_filled))),
            const SizedBox(height: 10),
            TextField(
                controller: budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ງົບປະມານ (Budget - ກີບ)',
                    prefixIcon: Icon(Icons.account_balance_wallet,
                        color: Colors.green))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('ຍົກເລີກ', style: TextStyle(color: Colors.black87))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () async {
              await doc.reference.update({
                'startDateTime':
                    startCtrl.text.isEmpty ? 'ຍັງບໍ່ໄດ້ກຳນົດ' : startCtrl.text,
                'endDateTime':
                    endCtrl.text.isEmpty ? 'ຍັງບໍ່ໄດ້ກຳນົດ' : endCtrl.text,
                'budget': budgetCtrl.text
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('ບັນທຶກ'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, DocumentSnapshot doc) async {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("ຢືນຢັນການລົບ"),
              content:
                  const Text("ທ່ານຕ້ອງການລົບສະຖານທີ່ນີ້ອອກຈາກແຜນການແທ້ບໍ່?"),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("ຍົກເລີກ")),
                TextButton(
                    onPressed: () async {
                      await doc.reference.delete();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text("ລົບເລີຍ",
                        style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  Widget _buildRowInfo(IconData icon, Color color, String text,
          {bool isBold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight:
                          isBold ? FontWeight.bold : FontWeight.normal)))
        ]),
      );

  @override
  Widget build(BuildContext context) {
    void addToPlan(Place place) async {
      if (currentUser == null) return;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .collection('plans')
            .add({
          'placeName': place.name,
          'latitude': place.latitude,
          'longitude': place.longitude,
          'imageUrl': place.imageUrl,
          'status': 'planning',
          'startDateTime': 'ຍັງບໍ່ໄດ້ກຳນົດ',
          'endDateTime': 'ຍັງບໍ່ໄດ້ກຳນົດ',
          'budget': 'ບໍ່ໄດ້ກຳນົດ',
          'addedAt': FieldValue.serverTimestamp(),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('ເພີ່ມ "${place.name}" ເຂົ້າໃນແຜນການແລ້ວ!'),
              backgroundColor: Colors.teal));
          _scaffoldKey.currentState?.openDrawer();
        }
      } catch (e) {
        debugPrint('addToPlan error: $e');
      }
    }

    final List<Widget> pages = [
      HomePage(
          scrollController: _scrollController,
          onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
          onAddToPlan: addToPlan,
          onProfilePressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (context) => const ProfilePage()))),
      if (isAdmin) AdminAddPlacePage(scrollController: _scrollController),
      ExplorePage(scrollController: _scrollController, onAddToPlan: addToPlan),
      TouristAttractionsPage(
          scrollController: _scrollController,
          onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
          onAddToPlan: addToPlan),
      const ChatListScreen(),
      const MapPage(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              color: Colors.teal,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ແຜນການເດີນທາງ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(currentUser?.email ?? '',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ]),
            ),
            Expanded(
              child: currentUser == null
                  ? const Center(child: Text("ກະລຸນາເຂົ້າສູ່ລະບົບ"))
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser!.uid)
                          .collection('plans')
                          .orderBy('addedAt', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const Center(
                              child: CircularProgressIndicator());
                        final docs = snapshot.data!.docs;
                        final planning = docs
                            .where((d) =>
                                (d.data() as Map<String, dynamic>)['status'] ==
                                'planning')
                            .toList();
                        final completed = docs
                            .where((d) =>
                                (d.data() as Map<String, dynamic>)['status'] ==
                                'completed')
                            .toList();

                        int budgetPlan = planning.fold(
                            0,
                            (sum, item) =>
                                sum +
                                _parseBudget((item.data() as Map)['budget']));
                        int budgetDone = completed.fold(
                            0,
                            (sum, item) =>
                                sum +
                                _parseBudget((item.data() as Map)['budget']));

                        return ListView(
                          padding: const EdgeInsets.all(10),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                  color: Colors.teal.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.teal.withOpacity(0.3))),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("📊 ສັງລວມຄ່າໃຊ້ຈ່າຍທັງໝົດ",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.teal)),
                                    const Divider(height: 12),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("💰 ງົບກຳລັງວາງແຜນ:",
                                              style: TextStyle(fontSize: 12)),
                                          Text("$budgetPlan ₭",
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold))
                                        ]),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("✅ ງົບທີ່ຈ່າຍໄປແລ້ວ:",
                                              style: TextStyle(fontSize: 12)),
                                          Text("$budgetDone ₭",
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange))
                                        ]),
                                    const Divider(height: 12),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("💵 ງົບປະມານລວມທັງໝົດ:",
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold)),
                                          Text("${budgetPlan + budgetDone} ₭",
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green))
                                        ]),
                                  ]),
                            ),
                            const Text("📌 ແຜນການທີ່ຈະໄປທ່ຽວ",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.teal)),
                            const Divider(),
                            if (planning.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text("ບໍ່ມີແຜນການ",
                                      style: TextStyle(
                                          color: Colors.black87, fontSize: 12))),
                            ...planning.map((doc) =>
                                _buildPlanCard(doc, isCompletedType: false)),
                            const SizedBox(height: 20),
                            const Text("✅ ສະຖານທີ່ໆທ່ຽວແລ້ວ",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.orange)),
                            const Divider(),
                            if (completed.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text("ບໍ່ມີປະຫວັດການທ່ຽວ",
                                      style: TextStyle(
                                          color: Colors.black87, fontSize: 12))),
                            ...completed.map((doc) =>
                                _buildPlanCard(doc, isCompletedType: true)),
                          ],
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
      body: pages[_currentIndex >= pages.length ? 0 : _currentIndex],
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isFooterVisible ? kBottomNavigationBarHeight + 25 : 0.0,
        child: Wrap(children: [
          StreamBuilder<QuerySnapshot>(
            stream: currentUser != null
                ? FirebaseFirestore.instance
                    .collection('chats')
                    .where('participants', arrayContains: currentUser!.uid)
                    .snapshots()
                : const Stream.empty(),
            builder: (context, snapshot) {
              int totalUnread = 0;
              if (snapshot.hasData && currentUser != null) {
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final unreadCounts =
                      Map<String, dynamic>.from(data['unreadCounts'] ?? {});
                  int unread = (unreadCounts[currentUser!.uid] ?? 0).toInt();
                  totalUnread += unread;
                }
              }

              if (_totalUnreadCount != totalUnread) {
                _totalUnreadCount = totalUnread;
              }

              return NavigationBarTheme(
                data: NavigationBarThemeData(
                  labelTextStyle: MaterialStateProperty.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold);
                    }
                    return const TextStyle(color: Colors.black87);
                  }),
                  iconTheme: MaterialStateProperty.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return const IconThemeData(color: Colors.green);
                    }
                    return const IconThemeData(color: Colors.black87);
                  }),
                ),
                child: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _currentIndex = index),
                  indicatorColor: Colors.transparent, // ✅ เพิ่มบรรทัดนี้
                  overlayColor: MaterialStateProperty.all(
                      Colors.transparent), // ✅ เพิ่มบรรทัดนี้
                  destinations: [
                    const NavigationDestination(
                        icon: Icon(Icons.home), label: "ໜ້າຫຼັກ"),
                    if (isAdmin)
                      const NavigationDestination(
                          icon: Icon(Icons.add_box), label: "ເພີ່ມ"),
                    const NavigationDestination(
                        icon: Icon(Icons.travel_explore), label: "ຜູ້ຄົນ"),
                    const NavigationDestination(
                        icon: Icon(Icons.place), label: "ເມືອງທ່ຽວ"),
                    NavigationDestination(
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.chat_bubble_outline),
                          if (totalUnread > 0)
                            Positioned(
                              right: -8,
                              top: -8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$totalUnread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      label: "ແຊັດ",
                    ),
                    const NavigationDestination(
                        icon: Icon(Icons.map), label: "ແຜນທີ່"),
                  ],
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildPlanCard(DocumentSnapshot doc, {required bool isCompletedType}) {
    final data = doc.data() as Map<String, dynamic>;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data['placeName'] ?? '',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _buildRowInfo(Icons.flight_takeoff, Colors.teal,
              "เวลาไป: ${data['startDateTime'] ?? 'ຍັງບໍ່ໄດ້ກຳນົດ'}"),
          _buildRowInfo(Icons.flight_land, Colors.orange,
              "ເວລາກັບ: ${data['endDateTime'] ?? 'ຍັງບໍ່ໄດ້ກຳນົດ'}"),
          _buildRowInfo(Icons.account_balance_wallet, Colors.green,
              "ງົບປະມານ: ${data['budget'] ?? 'ບໍ່ໄດ້ກຳນົດ'} ₭",
              isBold: true),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (isCompletedType) ...[
              ElevatedButton.icon(
                onPressed: () => _openSharePostForm(data),
                icon: const Icon(Icons.share, size: 14),
                label: const Text("ແຊຣ໌", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              const Spacer(),
            ],
            if (!isCompletedType)
              IconButton(
                  tooltip: "ຈັດແຈງແຜນ",
                  icon: const Icon(Icons.edit_calendar,
                      size: 20, color: Colors.blue),
                  onPressed: () => _showEditPlanDialog(context, doc)),
            IconButton(
              tooltip: "ເບິ່ງແຜນທີ່",
              icon: const Icon(Icons.map, size: 20, color: Colors.green),
              onPressed: () => _openMap(
                (data['latitude'] as num?)?.toDouble() ?? 0.0,
                (data['longitude'] as num?)?.toDouble() ?? 0.0,
                data['placeName'] ?? '',
              ),
            ),
            IconButton(
                tooltip: "ລົບແຜນການ",
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () => _confirmDelete(context, doc)),
            if (!isCompletedType)
              IconButton(
                  tooltip: "ທ່ຽວສຳເລັດແລ້ວ",
                  icon: const Icon(Icons.check_circle,
                      size: 22, color: Colors.orange),
                  onPressed: () async =>
                      await doc.reference.update({'status': 'completed'})),
          ])
        ]),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// ShareTripPostSheet (ไม่มีการเปลี่ยนแปลง)
// ────────────────────────────────────────────────────────────────
class ShareTripPostSheet extends StatefulWidget {
  final Map<String, dynamic> planData;
  const ShareTripPostSheet({super.key, required this.planData});
  @override
  State<ShareTripPostSheet> createState() => _ShareTripPostSheetState();
}

class _ShareTripPostSheetState extends State<ShareTripPostSheet> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _picker = ImagePicker();
  final List<File> _selectedImages = [];
  final List<String> _existingImages = [];
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.planData['placeName'] ?? '';
    if (widget.planData['imageUrl'] != null &&
        widget.planData['imageUrl'].toString().isNotEmpty) {
      _existingImages.add(widget.planData['imageUrl']);
    }
  }

  Future<void> _pickImages() async {
    if ((_selectedImages.length + _existingImages.length) >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ສາມາດເພີ່ມຮູບໄດ້ສູງสุด 10 ຮູບ")));
      return;
    }
    try {
      final List<XFile> images =
          await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1920);
      if (images.isNotEmpty) {
        setState(() {
          for (var img in images) {
            if ((_selectedImages.length + _existingImages.length) < 10)
              _selectedImages.add(File(img.path));
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<List<String>> _uploadImagesToCloudinary() async {
    List<String> uploadedUrls = [];
    for (File file in _selectedImages) {
      final request = http.MultipartRequest(
          'POST',
          Uri.parse(
              "https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudinaryCloudName}/image/upload"))
        ..fields['upload_preset'] = CloudinaryConfig.cloudinaryUploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final result =
            json.decode(String.fromCharCodes(await response.stream.toBytes()));
        uploadedUrls.add(result['secure_url']);
      }
    }
    return uploadedUrls;
  }

  void _submitPost() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ກະລຸນາໃສ່ຫົວຂໍ້ (Title)")));
      return;
    }
    if (_contentController.text.trim().isEmpty &&
        _selectedImages.isEmpty &&
        _existingImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ກະລຸນາຂຽນລາຍລະອຽດ ຫຼື ເພີ່ມຮູບພາບ")));
      return;
    }
    setState(() => _isPosting = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isPosting = false);
      return;
    }

    try {
      List<String> finalImageUrls = await _uploadImagesToCloudinary();
      finalImageUrls.insertAll(0, _existingImages);
      String userName = user.displayName ?? user.email ?? 'ນັກທ່ອງທ່ຽວ';
      String userAvatar = user.photoURL ??
          'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100';
      String userBackground = '';

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        userName = doc.data()?['displayName'] ?? userName;
        userAvatar = doc.data()?['photoURL'] ?? userAvatar;
        userBackground = doc.data()?['backgroundURL'] ?? userBackground;
      }

      await FirebaseFirestore.instance.collection('user_posts').add({
        'userId': user.uid,
        'userName': userName,
        'userAvatar': userAvatar,
        'userBackground': userBackground,
        'placeName': widget.planData['placeName'] ?? '',
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'latitude': widget.planData['latitude'] ?? 0.0,
        'longitude': widget.planData['longitude'] ?? 0.0,
        'images': finalImageUrls,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'user_share',
        'likes': 0,
        'likedBy': [],
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("ແຊຣ໌ຄວາມປະທັບໃຈສຳເລັດແລ້ວ!"),
            backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("ເກີດຂໍ້ຜິດພາດໃນການແຊຣ໌")));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Widget _buildImageItem(
          {required Widget child, required VoidCallback onTap}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
          Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 16)))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    int totalImages = _selectedImages.length + _existingImages.length;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Wrap(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("ແຊຣ໌ປະສົບການ",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          _isPosting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: _submitPost,
                  child: const Text("ໂພສຕ໌",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: _titleController,
            decoration: const InputDecoration(
                hintText: "ຫົວຂໍ້ (Topic)...",
                labelText: "ຫົວຂໍ້ການແຊຣ໌",
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
        const SizedBox(height: 10),
        TextField(
            controller: _contentController,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: "ຂຽນລາຍລະອຽດຄວາມປະທັບໃຈຂອງທ່ານຢູ່ບ່ອນນີ້...",
                border: OutlineInputBorder())),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: Text("ເພີ່ມຮູບພາບທ່ຽວຂອງທ່ານ ($totalImages/10)")),
        const SizedBox(height: 15),
        if (totalImages > 0)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._existingImages.asMap().entries.map((e) => _buildImageItem(
                    child: Image.network(e.value,
                        width: 80, height: 80, fit: BoxFit.cover),
                    onTap: () =>
                        setState(() => _existingImages.removeAt(e.key)))),
                ..._selectedImages.asMap().entries.map((e) => _buildImageItem(
                    child: Image.file(e.value,
                        width: 80, height: 80, fit: BoxFit.cover),
                    onTap: () =>
                        setState(() => _selectedImages.removeAt(e.key)))),
              ],
            ),
          ),
        const SizedBox(height: 25),
      ]),
    );
  }
}
