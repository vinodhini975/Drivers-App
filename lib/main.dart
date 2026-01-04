import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase initialization error: $e");
  }

  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Driver Tracking',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        // Custom text theme for professional look
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          displaySmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          headlineSmall: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          titleLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          titleMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.green, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
      home: const _InitialScreen(), // Changed to a StatefulWidget to handle loading properly
    );
  }
}

// New StatefulWidget to handle initial screen loading
class _InitialScreen extends StatefulWidget {
  const _InitialScreen();

  @override
  State<_InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<_InitialScreen> {
  Widget? _initialScreen;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialScreen();
    
    // Listen for auth state changes
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        _loadInitialScreen();
      }
    });
  }

  Future<void> _loadInitialScreen() async {
    try {
      // Check if user is signed in with Firebase
      final User? user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        // User is signed in, check if we have the username in shared prefs
        final prefs = await SharedPreferences.getInstance();
        String? savedUsername = prefs.getString("driver_username");
        
        // If we don't have a username saved, try to extract it from the email
        if (savedUsername == null || savedUsername.isEmpty) {
          // Extract username from email (remove @driverapp.com part)
          String email = user.email ?? '';
          if (email.endsWith('@driverapp.com')) {
            savedUsername = email.replaceAll('@driverapp.com', '');
            await prefs.setString("driver_username", savedUsername);
          }
        }
        
        // Use the '??' operator to provide a fallback
        setState(() {
          _initialScreen = HomeScreen(username: savedUsername ?? "Guest");
          _isLoading = false;
        });
      } else {
        // No user signed in, go to login
        setState(() {
          _initialScreen = const LoginScreen();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading initial screen: $e");
      setState(() {
        _initialScreen = const LoginScreen();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _initialScreen == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              SizedBox(height: 20),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _initialScreen!;
  }
}