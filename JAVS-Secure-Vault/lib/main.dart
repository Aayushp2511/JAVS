import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'package:secure_messenger/ui/dashboard/dashboard_screen.dart';
import 'package:secure_messenger/ui/auth/auth_screen.dart';
import 'package:secure_messenger/ui/theme/cyber_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Firebase Secure Perimeter
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 3. Launch the Root Controller
  runApp(
    const ProviderScope(
      child: JAVSMessengerApp(),
    ),
  );
}

class JAVSMessengerApp extends StatelessWidget {
  const JAVSMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JAVS.CORE',
      debugShowCheckedModeBanner: false,
      theme: CyberTheme.darkTheme,
      // Adaptive routing based on authentication state
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: CyberTheme.background,
              body: Center(child: CircularProgressIndicator(color: CyberTheme.primaryNeon)),
            );
          }
          
          if (snapshot.hasData) {
            return const DashboardScreen();
          }
          
          return const AuthScreen();
        },
      ),
    );
  }
}