import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_messenger/ui/theme.dart';
import 'package:secure_messenger/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase.initializeApp() will go here

  runApp(const ProviderScope(child: JAVSMessengerApp()));
}

class JAVSMessengerApp extends StatelessWidget {
  const JAVSMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JAVS Secure Messenger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginScreen(),
    );
  }
}
