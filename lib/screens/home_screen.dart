import 'package:flutter/material.dart';
import 'dart:async';
import '../models/driver_model.dart';
import '../services/auth_service.dart';
import '../services/duty_service.dart';
import '../services/enhanced_location_service.dart';
import '../services/permission_helper.dart';
import '../services/native_location_service.dart';
import 'login_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HomeScreen extends StatefulWidget {
  final DriverModel driver;
  const HomeScreen({super.key, required this.driver});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final DutyService _dutyService = DutyService();
  final EnhancedLocationService _locationService = EnhancedLocationService();
  
  Timer? _locationTimer;
  Timer? _dutyTimer;
  StreamSubscription? _batterySubscription;
  StreamSubscription? _connectivitySubscription;
  
  bool _isDutyActive = false;
  bool _isLoading = false;
  int _dutyDurationMinutes = 0;
  int _batteryLevel = 100;
  bool _isBatteryLow = false;
  
  bool _backgroundServiceStarted = false; // Track service state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
    _dutyTimer?.cancel();
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _checkDutyStatus();
    await _checkBatteryStatus();
    _startBatteryMonitoring();
    _startConnectivityMonitoring();
    
    if (_isDutyActive && !_backgroundServiceStarted) {
      await _startBackgroundService();
      await _startTracking();
    }
  }

  Future<void> _startTracking() async {
    _locationTimer?.cancel();
    // Reduce frequency since Android service handles primary tracking
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      // Check if duty is active
      final isDutyActive = await _dutyService.isDutyActive();
      if (isDutyActive) {
        await _locationService.captureLocation(widget.driver.driverId);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _checkDutyStatus() async {
    final active = await _dutyService.isDutyActive();
    setState(() => _isDutyActive = active);
    if (active) _startDutyTimer();
  }

  Future<void> _checkBatteryStatus() async {
    final status = await _dutyService.checkBatteryStatus();
    setState(() { _batteryLevel = status['level']; _isBatteryLow = status['isLow']; });
  }

  void _startBatteryMonitoring() {
    _batterySubscription = _dutyService.batteryLevelStream.listen((level) {
      setState(() { _batteryLevel = level; _isBatteryLow = level < 20; });
    });
  }

  void _startConnectivityMonitoring() {
    _connectivitySubscription = _locationService.connectivityStream.listen((result) {
      if (result != ConnectivityResult.none) {
        _locationService.syncOfflineLocations();
      }
    });
  }

  void _startDutyTimer() {
    _dutyTimer?.cancel();
    _dutyTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final duration = await _dutyService.getCurrentDutyDuration();
      if (mounted) setState(() => _dutyDurationMinutes = duration);
    });
  }
  
  Future<void> _startBackgroundService() async {
    if (_backgroundServiceStarted) {
      return; // Service already started
    }
    
    try {
      await NativeLocationService.startTracking(widget.driver.driverId);
      _backgroundServiceStarted = true;
      debugPrint('Background location service started for driver: ${widget.driver.driverId}');
    } catch (e) {
      debugPrint('Failed to start background service: $e');
    }
  }

  Future<void> _startDuty() async {
    final ready = await PermissionHelper.ensureLocationRequirement(context);
    if (!ready) return;

    setState(() => _isLoading = true);
    final result = await _dutyService.startDuty(widget.driver.driverId);
    if (result['success']) {
      setState(() => _isDutyActive = true);
      _startDutyTimer();
      
      // Start background service if not already started
      if (!_backgroundServiceStarted) {
        await _startBackgroundService();
      }
      await _startTracking();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _endDuty() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Duty'),
        content: const Text('Are you sure you want to end your duty and stop location tracking?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Duty', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    _locationTimer?.cancel();
    await _dutyService.endDuty(widget.driver.driverId);
    
    // Stop background service
    if (_backgroundServiceStarted) {
      await NativeLocationService.stopTracking();
      _backgroundServiceStarted = false;
      debugPrint('Background location service stopped');
    }
    
    setState(() { _isDutyActive = false; _dutyDurationMinutes = 0; });
    _dutyTimer?.cancel();
    setState(() => _isLoading = false);
  }

  Future<void> _logout() async {
    if (_isDutyActive) {
      _showMessage('Please end duty before logging out', isError: true);
      return;
    }
    
    // Stop Android native service if running
    if (_backgroundServiceStarted) {
      await NativeLocationService.stopTracking();
      _backgroundServiceStarted = false;
      debugPrint('Background location service stopped on logout');
    }
    
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Driver Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
                boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 60, color: Colors.green),
                  ),
                  const SizedBox(height: 15),
                  Text(widget.driver.name, 
                       style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(20)),
                    child: Text('ID: ${widget.driver.driverId}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildHeaderStat(Icons.battery_3_bar, '$_batteryLevel%', 'Battery', _isBatteryLow ? Colors.red[200]! : Colors.white),
                      _buildHeaderStat(Icons.access_time_filled, '${_dutyDurationMinutes}m', 'Duty Time', Colors.white),
                      _buildHeaderStat(Icons.local_shipping, widget.driver.vehicleId, 'Vehicle', Colors.white),
                    ],
                  )
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Duty Status Control
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    elevation: 5,
                    shadowColor: Colors.black26,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _isDutyActive 
                            ? [Colors.white, Colors.green[50]!] 
                            : [Colors.white, Colors.red[50]!],
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isDutyActive ? Icons.online_prediction : Icons.offline_bolt,
                                color: _isDutyActive ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _isDutyActive ? 'LOCATION TRACKING ON' : 'LOCATION TRACKING OFF',
                                style: TextStyle(
                                  fontSize: 16, 
                                  fontWeight: FontWeight.w800, 
                                  color: _isDutyActive ? Colors.green[800] : Colors.red[800],
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _isLoading ? null : (_isDutyActive ? _endDuty : _startDuty),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 70),
                              backgroundColor: _isDutyActive ? Colors.red : Colors.green,
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                            child: _isLoading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_isDutyActive ? Icons.stop_circle : Icons.play_circle, color: Colors.white, size: 28),
                                    const SizedBox(width: 12),
                                    Text(
                                      _isDutyActive ? 'END MY DUTY' : 'START MY DUTY',
                                      style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  
                  // Assignment Information
                  _buildSectionTitle('Route Information'),
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 25),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        _buildAssignmentInfo('ZONE', widget.driver.zone, Icons.location_city),
                        Container(height: 40, width: 1, color: Colors.grey[200]),
                        _buildAssignmentInfo('WARD', widget.driver.ward, Icons.map),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
    );
  }

  Widget _buildHeaderStat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildAssignmentInfo(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.green[600], size: 24),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
