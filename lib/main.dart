import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // main isolate only

  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  Future<Widget> _loadInitialScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUsername = prefs.getString("driver_username");

    if (savedUsername != null && savedUsername.isNotEmpty) {
      // 🔥 ENSURE background service is running
      await initializeService(savedUsername);

      return HomeScreen(username: savedUsername);
    }

    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Driver Tracking',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: FutureBuilder<Widget>(
        future: _loadInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return const Scaffold(
              body: Center(child: Text("Something went wrong")),
            );
          }

          return snapshot.data ?? const LoginScreen();
        },
      ),
    );
  }
}
