import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_svg/flutter_svg.dart';  // ✅ เพิ่ม import
import '../pages/main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;

  final TextEditingController _emailLoginController = TextEditingController();
  final TextEditingController _passwordLoginController = TextEditingController();
  final TextEditingController _emailRegisterController = TextEditingController();
  final TextEditingController _passwordRegisterController = TextEditingController();

  bool _isLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailLoginController.dispose();
    _passwordLoginController.dispose();
    _emailRegisterController.dispose();
    _passwordRegisterController.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _navigateToMainScreen() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  Future<void> _loginWithEmail() async {
    String email = _emailLoginController.text.trim();
    String password = _passwordLoginController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("ກະລຸນາປ້ອນຂໍ້ມູນໄຫ້ຄົບຖ້ວນ");
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (email == "admin_app" && password == "0001") {
        email = "admin_app@travel.com";
        password = "admin_app_0001";
        try {
          await _auth.signInWithEmailAndPassword(email: email, password: password);
        } catch (e) {
          await _auth.createUserWithEmailAndPassword(email: email, password: password);
        }
      } else {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      }
      _showSnackBar("ເຂົ້າສູ່ລະບົບສຳເລັດ!");
      _navigateToMainScreen();
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? "ເກີດຂໍ້ຜິດພາດ");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerWithEmail() async {
    String email = _emailRegisterController.text.trim();
    String password = _passwordRegisterController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("ກະລຸນາປ້ອນຂ້ມູນ");
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      _showSnackBar("ສະໝັກສະມາຊິສຳເລັດ");
      _emailRegisterController.clear();
      _passwordRegisterController.clear();
      _tabController.animateTo(0);
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await _auth.signInWithCredential(credential);
      _showSnackBar("ເຂົ້າລະບົບດ້ວຍ Google ສຳເລັດ!");
      _navigateToMainScreen();
    } catch (e) {
      _showSnackBar("Google Sign-In ລົ້ມເຫຼວ: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("ຍິນດີຕ້ອນຮັບ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.teal,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.teal,
          tabs: const [
            Tab(text: "ເຂົົ້າສູ່ລະບົບ"),
            Tab(text: "ສະໝັກສະມາຊິກ"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 280,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab Login
                        Column(children: [
                          TextField(
                            controller: _emailLoginController,
                            decoration: const InputDecoration(
                              labelText: "ເມລ ຫຼື admin_app",
                              prefixIcon: Icon(Icons.email),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordLoginController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "ລະຫັດຜ່ານ",
                              prefixIcon: Icon(Icons.lock),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _loginWithEmail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("ເຂົ້າສູ່ລະບົບ"),
                            ),
                          ),
                        ]),
                        // Tab Register
                        Column(children: [
                          TextField(
                            controller: _emailRegisterController,
                            decoration: const InputDecoration(
                              labelText: "ເມລ",
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordRegisterController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "ລະຫັດຜ່ານ (6+ ຕົວ)",
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _registerWithEmail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("ສະໝັກສະມາຊິກ"),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("ຫຼື ດຳເນີນກາຮຕໍ່ດ້ວຍ", style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // ✅ ปุ่ม Google Sign-In พร้อม SVG สีสัน
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ✅ ใช้ SvgPicture.network โหลด SVG จาก URL
                          SvgPicture.network(
                            'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                            height: 24,
                            width: 24,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "ສືບຕໍ່ດ້ວຍ Google",
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}