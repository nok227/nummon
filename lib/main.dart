import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages/main_screen.dart';
import 'auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      // ⚠️ ให้เอา Web API Key ของโปรเจกต์ Nummon มาใส่ตรงนี้ครับ
      apiKey: "AIzaSyDZp6bkYDu1cqyMeOMNEwQ8PJyjks2ydik", 
      
      // ⚠️ ให้เอา App ID ของแอป com.phakin.aii มาใส่ตรงนี้ครับ (จะขึ้นต้นด้วย 1:479832480739:android:...)
      appId: "1:479832480739:android:0eda3881e1dcb91f82ded6", 
      
      messagingSenderId: "479832480739",                   // อัปเดตแล้ว (ใช้ Project number)
      projectId: "nummon-8b175",                           // อัปเดตแล้ว (ใช้ Project ID)
      storageBucket: "nummon-8b175.firebasestorage.app",   // อัปเดตแล้ว (ใช้ตามโครงสร้าง Project ID ใหม่)
    ),
  );
  // await Firebase.initializeApp();
  runApp(const TravelApp());
}

class TravelApp extends StatelessWidget {
  const TravelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Travel App',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) return const MainScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}