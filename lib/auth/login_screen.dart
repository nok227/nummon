import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      // Admin logic
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
      // ไม่ต้องนำทางเพราะ StreamBuilder จะจัดการ
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
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) return;
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await _auth.signInWithCredential(credential);
      _showSnackBar("ເຂົ້າລະບົບດ້ວຍ Google ສຳເລັດ!");
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
        title: const Text("ຍຶນດີຕ້ອນຮັບ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.teal,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.teal,
          tabs: const [Tab(text: "ເຂົົ້າສູ່ລະບົບ"), Tab(text: "ສະໝັກສະມາຊິກ")],
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
                        Column(children: [
                          TextField(controller: _emailLoginController, decoration: const InputDecoration(labelText: "ເມລ ຫຼື admin_app", prefixIcon: Icon(Icons.email))),
                          const SizedBox(height: 16),
                          TextField(controller: _passwordLoginController, obscureText: true, decoration: const InputDecoration(labelText: "ລະຫັດຜ່ານ", prefixIcon: Icon(Icons.lock))),
                          const SizedBox(height: 24),
                          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _loginWithEmail, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), child: const Text("เข้าสู่ระบบ", style: TextStyle(color: Colors.white)))),
                        ]),
                        Column(children: [
                          TextField(controller: _emailRegisterController, decoration: const InputDecoration(labelText: "ເມລ", prefixIcon: Icon(Icons.mail_outline))),
                          const SizedBox(height: 16),
                          TextField(controller: _passwordRegisterController, obscureText: true, decoration: const InputDecoration(labelText: "ລະຫັດຜ່ານ (6+ ຕົວ)", prefixIcon: Icon(Icons.lock_outline))),
                          const SizedBox(height: 24),
                          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _registerWithEmail, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), child: const Text("ສະໝັກສະມາຊິກ", style: TextStyle(color: Colors.white)))),
                        ]),
                      ],
                    ),
                  ),
                  const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("ຫຼື ດຳເນີນກາຮຕໍ່ດ້ວຍ", style: TextStyle(color: Colors.grey))), Expanded(child: Divider())]),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(onPressed: _signInWithGoogle, icon: const Icon(Icons.g_mobiledata), label: const Text("ກຳເນີນການຕໍ່ດ້ວຍ Google", style: TextStyle(color: Colors.black)), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[100]))),
                ],
              ),
            ),
    );
  }
}