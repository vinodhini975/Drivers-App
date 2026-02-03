import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/gov_map_screen.dart';
import 'screens/location_permission_screen.dart';
import 'services/auth_service.dart';
import 'services/location_permission_service.dart';
import 'models/driver_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final authService = AuthService();
  
  // 1. Check Gov Session First
  if (await authService.isGovLoggedIn()) {
    runApp(const DriverApp(startScreen: GovMapScreen()));
    return;
  }

  // 2. Check Driver Session
  if (await authService.isDriverLoggedIn()) {
    final driver = await authService.getCurrentDriver();
    if (driver != null) {
      // Check permissions before showing home
      final bool hasPerms = await LocationPermissionService.areAllPermissionsGranted();
      if (hasPerms) {
        runApp(DriverApp(startScreen: HomeScreen(driver: driver)));
      } else {
        runApp(DriverApp(startScreen: LocationPermissionScreen(driver: driver)));
      }
      return;
    }
  }

  // 3. Default: Login Screen
  runApp(const DriverApp(startScreen: LoginScreen()));
}

class DriverApp extends StatelessWidget {
  final Widget startScreen;
  const DriverApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BBMP TrackConnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.green),
      home: startScreen,
    );
  }
}
