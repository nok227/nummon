import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages/main_screen.dart';
import 'auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBhmpBpL6rsu2CFxp_-AnpA_KyUa3pLvbs",
      appId: "1:447844170700:android:351a8b0df679a0aef63b69",
      messagingSenderId: "447844170700",
      projectId: "my-app-7eb60",
      storageBucket: "my-app-7eb60.firebasestorage.app",
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