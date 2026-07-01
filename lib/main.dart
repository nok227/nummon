import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages/main_screen.dart';
import 'auth/login_screen.dart';
import 'services/onesignal_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDZp6bkYDu1cqyMeOMNEwQ8PJyjks2ydik", 
      appId: "1:479832480739:android:0eda3881e1dcb91f82ded6", 
      messagingSenderId: "479832480739",                   
      projectId: "nummon-8b175",                           
      storageBucket: "nummon-8b175.firebasestorage.app",   
    ),
  );

  OneSignalService().initialize();

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
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            // ✅ ส่ง user ไปให้ MainScreen
            return MainScreen(user: snapshot.data);
          }
          return const LoginScreen();
        },
      ),
    );
  }
}