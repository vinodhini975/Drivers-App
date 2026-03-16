import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/driver_model.dart';
import '../services/auth_service.dart';
import '../services/enhanced_location_service.dart';
import '../services/native_location_service.dart';
import 'login_screen.dart';
import 'location_permission_screen.dart';
import '../services/location_permission_service.dart';

class HomeScreen extends StatefulWidget {
  final DriverModel driver;
  const HomeScreen({super.key, required this.driver});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final EnhancedLocationService _locationService = EnhancedLocationService();

  StreamSubscription? _sentinelSubscription;
  StreamSubscription? _permissionSubscription;
  bool _isTrackingActive = false;
  late String _currentSessionId;
  bool _permissionsVerified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentSessionId = "SESS_${DateTime.now().millisecondsSinceEpoch}";
    
    _verifyPermissionsOnInit();
    _startReactiveSentinel();
    _startPermissionMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sentinelSubscription?.cancel();
    _permissionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyMandatoryCompliance();
    }
  }

  Future<void> _verifyPermissionsOnInit() async {
    final permissionsGranted = await LocationPermissionService.areAllPermissionsGranted();
    if (!permissionsGranted && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: widget.driver)),
      );
    } else {
      setState(() => _permissionsVerified = true);
    }
  }

  void _startPermissionMonitoring() {
    _permissionSubscription = Permission.location.status.asStream().listen((status) async {
      final allPermissions = await LocationPermissionService.areAllPermissionsGranted();
      if (!allPermissions && mounted) {
        await _handlePermissionRevocation();
      }
    });
  }

  Future<void> _handlePermissionRevocation() async {
    if (_isTrackingActive) {
      await _triggerStopTracking();
    }
    
    if (mounted) {
      setState(() {
        _permissionsVerified = false;
        _isTrackingActive = false;
      });
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: widget.driver)),
      );
    }
  }

  Future<void> _verifyMandatoryCompliance() async {
    final stillHasAccess = await LocationPermissionService.areAllPermissionsGranted();
    if (!stillHasAccess && mounted) {
      _triggerStopTracking();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: widget.driver)),
      );
    }
  }

  void _startReactiveSentinel() {
    _sentinelSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driver.id)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data()!;
      final bool remoteEnabled = data['isTrackingEnabled'] ?? false;
      final String? serverSessionId = data['activeSessionId'];

      if (remoteEnabled && serverSessionId == _currentSessionId) {
        if (!_isTrackingActive) _triggerStartTracking();
      } else {
        if (_isTrackingActive) _triggerStopTracking();
      }
    });
  }

  Future<void> _triggerStartTracking() async {
    if (mounted) setState(() => _isTrackingActive = true);
    await NativeLocationService.startTracking(widget.driver.id);
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isTrackingActive) {
        timer.cancel();
        return;
      }
      await _locationService.captureLocation(widget.driver.id);
    });
  }

  Future<void> _triggerStopTracking() async {
    if (mounted) setState(() => _isTrackingActive = false);
    await NativeLocationService.stopTracking();
  }

  Future<void> _handleLogout() async {
    if (_isTrackingActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking active - Controlled by Government'), backgroundColor: Colors.red),
      );
      return;
    }
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isTrackingActive ? Colors.green : Colors.orange;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Track Connect'),
        backgroundColor: Colors.green[700],
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout)],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
            decoration: BoxDecoration(
              color: Colors.green[700],
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
            ),
            child: Column(
              children: [
                Text(
                  widget.driver.name, 
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 25),
                
                if (_permissionsVerified)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]
                    ),
                    child: QrImageView(
                      data: "${widget.driver.id}|$_currentSessionId",
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                
                const SizedBox(height: 20),
                const Text(
                  'SHOW QR TO SUPERVISOR', 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                ),
              ],
            ),
          ),

          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isTrackingActive ? Icons.verified_user : Icons.qr_code_scanner, 
                      size: 80, 
                      color: statusColor
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isTrackingActive ? 'TRACKING ACTIVE' : 'AWAITING APPROVAL',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: statusColor),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isTrackingActive 
                        ? 'Vehicle tracking is live' 
                        : 'Approval required to start',
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
