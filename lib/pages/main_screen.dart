import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/place_model.dart';

import 'home.dart';
import 'explore.dart';
import 'tourist_attractions.dart';
import 'map.dart';
import 'admin_add_place.dart';
import 'profile_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  
  // ── ฟีเจอร์ซ่อน/แสดง Footer แบบ Facebook ──
  bool _isFooterVisible = true;
  bool isAdmin = false;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    if (currentUser != null &&
        (currentUser!.email == 'admin_app@travel.com' ||
            currentUser!.email == 'admin_app')) {
      isAdmin = true;
    }

    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isFooterVisible) {
          setState(() {
            _isFooterVisible = false;
          });
        }
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isFooterVisible) {
          setState(() {
            _isFooterVisible = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── เปิดแผนที่ Google Maps ──
  Future<void> _openGoogleMap(double lat, double lng) async {
    final String urlString = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("Could not open the map.");
    }
  }

  void _openSharePostForm(Map<String, dynamic> planData) {
    Navigator.pop(context); 
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ShareTripPostSheet(planData: planData),
    );
  }

  // ── ฟังก์ชันแก้ไขแผนการเดินทาง (เวลาไป-กลับ และ งบประมาณ) ──
  Future<void> _showEditPlanDialog(BuildContext context, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final TextEditingController startCtrl = TextEditingController(
        text: data['startDateTime'] == 'ຍັງບໍ່ໄດ້ກຳນົດ' ? '' : data['startDateTime']);
    final TextEditingController endCtrl = TextEditingController(
        text: data['endDateTime'] == 'ຍັງບໍ່ໄດ້ກຳนົດ' ? '' : data['endDateTime']);
    final TextEditingController budgetCtrl = TextEditingController(
        text: data['budget']?.toString() ?? '');

    // ฟังก์ชันช่วยสำหรับเปิดหน้าต่างเลือก วันที่ และ เวลา
    Future<void> pickDateTime(TextEditingController controller) async {
      final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

      if (pickedDate != null) {
        if (!context.mounted) return;
        final TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );

        if (pickedTime != null) {
          // จัดรูปแบบ String ให้เป็น วัน/เดือน/ปี ชั่วโมง:นาที (เช่น 10/10/2024 08:00)
          final String day = pickedDate.day.toString().padLeft(2, '0');
          final String month = pickedDate.month.toString().padLeft(2, '0');
          final String year = pickedDate.year.toString();
          final String hour = pickedTime.hour.toString().padLeft(2, '0');
          final String minute = pickedTime.minute.toString().padLeft(2, '0');

          // อัปเดตข้อความในกล่องข้อความโดยตรง
          controller.text = "$day/$month/$year $hour:$minute";
        }
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('ຈັດແຈງແຜນການ\n(${data['placeName']})', style: const TextStyle(fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: startCtrl,
                  readOnly: true, // บังคับไม่ให้พิมพ์เองเพื่อป้องกันข้อผิดพลาด
                  onTap: () => pickDateTime(startCtrl), // เมื่อแตะจะเปิดตัวเลือกเวลา
                  decoration: const InputDecoration(
                    labelText: 'ເວລາໄປ (Start Time)',
                    hintText: 'ແຕະເພື່ອເລືອກເວລາ...',
                    prefixIcon: Icon(Icons.access_time),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: endCtrl,
                  readOnly: true, // บังคับไม่ให้พิมพ์เองเพื่อป้องกันข้อผิดพลาด
                  onTap: () => pickDateTime(endCtrl), // เมื่อแตะจะเปิดตัวเลือกเวลา
                  decoration: const InputDecoration(
                    labelText: 'ເວລາກັບ (End Time)',
                    hintText: 'ແຕະເພື່ອເລືອກເວລາ...',
                    prefixIcon: Icon(Icons.access_time_filled),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: budgetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ງົບປະມານ (Budget - ກີບ)',
                    hintText: 'ເຊັ່ນ: 500000',
                    prefixIcon: Icon(Icons.account_balance_wallet, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ຍົກເລີກ', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () async {
                await doc.reference.update({
                  'startDateTime': startCtrl.text.isEmpty ? 'ຍັງບໍ່ໄດ້ກຳນົດ' : startCtrl.text,
                  'endDateTime': endCtrl.text.isEmpty ? 'ຍັງບໍ່ໄດ້ກຳນົດ' : endCtrl.text,
                  'budget': budgetCtrl.text,
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('ບັນທຶກ'),
            ),
          ],
        );
      },
    );
  }

  // ── ยืนยันการลบสถานที่ ──
  Future<void> _confirmDelete(BuildContext context, DocumentSnapshot doc) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ຢືນຢັນການລົບ"),
        content: const Text("ທ່ານຕ້ອງການລົບສະຖານທີ່ນີ້ອອກຈາກແຜນການແທ້ບໍ່?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ຍົກເລີກ")),
          TextButton(
            onPressed: () {
              doc.reference.delete();
              Navigator.pop(context);
            },
            child: const Text("ລົບເລີຍ", style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );
  }

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
          'budget': 'ບໍ່ໄດ້ກຳນົດ', // ເພີ່ມຊ່ອງງົບປະມານ
          'addedAt': FieldValue.serverTimestamp(),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ເພີ່ມ "${place.name}" ເຂົ້າໃນແຜນການແລ້ວ!'), backgroundColor: Colors.teal),
          );
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
        onProfilePressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage())),
      ),
      if (isAdmin) AdminAddPlacePage(scrollController: _scrollController),
      ExplorePage(scrollController: _scrollController, onAddToPlan: addToPlan),
      TouristAttractionsPage(
        scrollController: _scrollController,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onAddToPlan: addToPlan,
      ),
      const MapPage(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                color: Colors.teal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ແຜນການເດີນທາງ', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(currentUser?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: currentUser == null
                    ? const Center(child: Text("ກະລຸນາເຂົ້າສູ່ລະບົບ"))
                    : StreamBuilder<QuerySnapshot>(
                        // ดึงข้อมูลจริงจาก Firebase แบบ Realtime
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(currentUser!.uid)
                            .collection('plans')
                            .orderBy('addedAt', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          final docs = snapshot.data!.docs;
                          final planningItems = docs.where((d) => (d.data() as Map)['status'] == 'planning').toList();
                          final completedItems = docs.where((d) => (d.data() as Map)['status'] == 'completed').toList();

                          return ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            children: [
                              const Text("📌 ແຜນການທີ່ຈະໄປທ່ຽວ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
                              const Divider(),
                              if (planningItems.isEmpty) const Padding(padding: EdgeInsets.all(8.0), child: Text("ບໍ່ມີແຜນການ", style: TextStyle(color: Colors.grey, fontSize: 12))),
                              ...planningItems.map((doc) => _buildPlanCard(doc, isCompletedType: false)),
                              const SizedBox(height: 20),
                              const Text("✅ ສະຖານທີ່ໆທ່ຽວແລ້ວ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                              const Divider(),
                              if (completedItems.isEmpty) const Padding(padding: EdgeInsets.all(8.0), child: Text("ບໍ່ມີປະຫວັດການທ່ຽວ", style: TextStyle(color: Colors.grey, fontSize: 12))),
                              ...completedItems.map((doc) => _buildPlanCard(doc, isCompletedType: true)),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      body: pages[_currentIndex >= pages.length ? 0 : _currentIndex],
      
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isFooterVisible ? kBottomNavigationBarHeight + 25 : 0.0,
        child: Wrap(
          children: [
            NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              destinations: [
                const NavigationDestination(icon: Icon(Icons.home), label: "Home"),
                if (isAdmin) const NavigationDestination(icon: Icon(Icons.add_box, color: Colors.teal), label: "Add Place"),
                const NavigationDestination(icon: Icon(Icons.explore), label: "Explore"),
                const NavigationDestination(icon: Icon(Icons.place), label: "Tourist"),
                const NavigationDestination(icon: Icon(Icons.map), label: "Map"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── UI Card สำหรับแสดงข้อมูลแผนการเดินทางแต่ละรายการ ──
  Widget _buildPlanCard(DocumentSnapshot doc, {required bool isCompletedType}) {
    final data = doc.data() as Map<String, dynamic>;
    String start = data['startDateTime'] ?? 'ຍັງບໍ່ໄດ້ກຳນົດ';
    String end = data['endDateTime'] ?? 'ຍັງບໍ່ໄດ້ກຳນົດ';
    String budget = data['budget'] ?? 'ບໍ່ໄດ້ກຳນົດ';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['placeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            // ສະແດງເວລາໄປ
            Row(
              children: [
                const Icon(Icons.flight_takeoff, size: 16, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(child: Text("เวลาไป: $start", style: const TextStyle(fontSize: 13, color: Colors.black87))),
              ],
            ),
            const SizedBox(height: 4),
            // ສະແດງເວລາກັບ
            Row(
              children: [
                const Icon(Icons.flight_land, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text("ເວລາກັບ: $end", style: const TextStyle(fontSize: 13, color: Colors.black87))),
              ],
            ),
            const SizedBox(height: 4),
            // ສະແດງງົບປະມານ
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text("ງົບປະມານ: $budget ₭", style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            
            // ── แถวปุ่มจัดการ (Map, Edit, Delete, Complete) ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isCompletedType) ...[
                  ElevatedButton.icon(
                    onPressed: () => _openSharePostForm(data),
                    icon: const Icon(Icons.share, size: 14),
                    label: const Text("ແຊຣ໌", style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
                  const Spacer(),
                ],
                
                // ປຸ່ມແກ້ໄຂເວລາແລະງົບ
                if (!isCompletedType)
                  IconButton(
                    tooltip: "ຈັດແຈງແຜນ",
                    icon: const Icon(Icons.edit_calendar, size: 20, color: Colors.blue), 
                    onPressed: () => _showEditPlanDialog(context, doc)
                  ),
                
                // ປຸ່ມເเบິ່ງແผนที่
                IconButton(
                  tooltip: "ເບິ່ງແຜນທີ່",
                  icon: const Icon(Icons.map, size: 20, color: Colors.green), 
                  onPressed: () => _openGoogleMap(data['latitude'], data['longitude'])
                ),
                
                // ປຸ່ມລົບ
                IconButton(
                  tooltip: "ລົບແຜນການ",
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red), 
                  onPressed: () => _confirmDelete(context, doc)
                ),
                
                // ປຸ່ມໝາຍວ່າສຳເລັດແລ້ວ (ສຳລັບລາຍການທີ່ຍັງບໍ່ສຳເລັດ)
                if (!isCompletedType)
                  IconButton(
                    tooltip: "ທ່ຽວສຳເລັດແລ້ວ",
                    icon: const Icon(Icons.check_circle, size: 22, color: Colors.orange), 
                    onPressed: () => doc.reference.update({'status': 'completed'})
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ── หน้าต่างแผ่นฟอร์มเขียนรายละเอียดและแนบรูปภาพสูงสุด 10 รูป ──
class ShareTripPostSheet extends StatefulWidget {
  final Map<String, dynamic> planData;
  const ShareTripPostSheet({super.key, required this.planData});

  @override
  State<ShareTripPostSheet> createState() => _ShareTripPostSheetState();
}

class _ShareTripPostSheetState extends State<ShareTripPostSheet> {
  final TextEditingController _contentController = TextEditingController();
  final List<String> _mockUploadedImages = []; 
  bool _isPosting = false;

  void _addMockImage() {
    if (_mockUploadedImages.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ສາມາດເພີ່ມຮູບໄດ້ສູງສຸດ 10 ຮູບ")));
      return;
    }
    setState(() {
      _mockUploadedImages.add("https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400");
    });
  }

  void _submitPost() async {
    if (_contentController.text.trim().isEmpty) return;
    setState(() => _isPosting = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isPosting = false);
      return;
    }

    String userName = user.displayName ?? user.email ?? 'ນັກທ່ອງທ່ຽວ';
    String userAvatar = user.photoURL ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100';
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      userName = doc.data()?['displayName'] ?? userName;
      userAvatar = doc.data()?['photoURL'] ?? userAvatar;
    }

    await FirebaseFirestore.instance.collection('user_posts').add({
      'userId': user.uid,
      'userName': userName,
      'userAvatar': userAvatar,
      'placeName': widget.planData['placeName'] ?? '',
      'content': _contentController.text.trim(),
      'images': _mockUploadedImages.isNotEmpty ? _mockUploadedImages : [widget.planData['imageUrl'] ?? ''],
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'user_share',
      'likes': 0,
      'likedBy': [],
    });

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ແຊຣ໌ຄວາມປະທັບໃຈສຳເລັດແລ້ວ!"), backgroundColor: Colors.teal),
      );
    }
    setState(() => _isPosting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: Wrap(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("ແຊຣ໌ປະສົบການ: ${widget.planData['placeName']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              _isPosting 
                ? const CircularProgressIndicator()
                : TextButton(onPressed: _submitPost, child: const Text("ໂພສຕ໌", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          TextField(
            controller: _contentController,
            maxLines: 4,
            decoration: const InputDecoration(hintText: "ຂຽນລາຍລະອຽດຄວາມປະທັບໃຈຂອງທ່ານຢູ່ບ່ອນນີ້...", border: InputBorder.none),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _addMockImage,
            icon: const Icon(Icons.add_photo_alternate),
            label: Text("ເພີ່ມຮູບພາບທ່ຽວຂອງທ່ານ (${_mockUploadedImages.length}/10)"),
          ),
          const SizedBox(height: 15),
          if (_mockUploadedImages.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _mockUploadedImages.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(_mockUploadedImages[i], width: 80, height: 80, fit: BoxFit.cover)),
                ),
              ),
            ),
          const SizedBox(height: 25),
        ],
      ),
    );
  }
}