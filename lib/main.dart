import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/location_permission_screen.dart';
import 'services/location_permission_service.dart';
import 'services/permission_edge_case_handler.dart';
import 'services/auth_service.dart';
import 'models/driver_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // STEP 1: GLOBAL INITIALIZATION
  await Firebase.initializeApp();

  final authService = AuthService();
  final bool isLoggedIn = await authService.isLoggedIn();
  
  DriverModel? loggedInDriver;
  if (isLoggedIn) {
    final mobile = await authService.getSavedMobile();
    if (mobile != null) {
      try {
        loggedInDriver = await authService.getDriverByMobile(mobile);
      } catch (e) {
        debugPrint("Session restore error: $e");
      }
    }
  }

  runApp(DriverApp(initialDriver: loggedInDriver));
}

class DriverApp extends StatelessWidget {
  final DriverModel? initialDriver;
  static final navigatorKey = GlobalKey<NavigatorState>();
  const DriverApp({super.key, this.initialDriver});

  /// Check permissions before showing home screen
  Widget _buildHomeWithPermissionCheck(DriverModel driver) {
    // Check if all permissions are granted
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final edgeCaseResult = await PermissionEdgeCaseHandler.handleAppResume();
      
      switch (edgeCaseResult.action) {
        case PermissionAction.PROCEED:
          // All good, continue to home screen
          break;
          
        case PermissionAction.REDIRECT_TO_PERMISSION_SCREEN:
        case PermissionAction.REDIRECT_TO_GPS_SETTINGS:
        case PermissionAction.REDIRECT_TO_APP_SETTINGS:
          // Navigate to permission screen
          if (navigatorKey.currentContext != null) {
            Navigator.pushReplacement(
              navigatorKey.currentContext!,
              MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: driver)),
            );
          }
          break;
          
        case PermissionAction.SHOW_WARNING:
        case PermissionAction.SHOW_ERROR:
          // Show warning but allow proceeding for now
          if (navigatorKey.currentContext != null) {
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              SnackBar(
                content: Text(edgeCaseResult.reason),
                backgroundColor: Colors.orange,
              ),
            );
          }
          break;
      }
    });
    
    return HomeScreen(driver: driver);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'BBMP Driver App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.green,
      ),
      home: initialDriver != null 
          ? _buildHomeWithPermissionCheck(initialDriver!) 
          : const LoginScreen(),
    );
  }
}
