import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/driver_model.dart';
import '../models/location_model.dart';
import '../services/auth_service.dart';
import '../services/enhanced_location_service.dart';
import '../services/native_location_service.dart';
import '../services/trip_service.dart';
import '../services/route_processing_service.dart';
import '../services/duty_service.dart';
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
  final TripService _tripService = TripService();
  final RouteProcessingService _routeProcessingService = RouteProcessingService();
  final DutyService _dutyService = DutyService();

  StreamSubscription? _sentinelSubscription;
  StreamSubscription? _permissionSubscription;
  StreamSubscription? _locationSubscription;
  Timer? _pollerTimer;
  Timer? _trackingTimer;
  bool _isTrackingActive = false;
  bool _isSyncing = false;
  String? _currentSessionId;
  bool _permissionsVerified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Chain session loading with an initial status check
    _loadOrPersistSession().then((_) {
      _checkRemoteStatusManually();
      _startStatusPoller(); // Senior-grade fallback for laggy connections
    });
    
    _verifyPermissionsOnInit();
    _startReactiveSentinel();
    _startPermissionMonitoring();
    
    debugPrint('[TRIP_INTEL] 💎 Watching Driver Doc: ${widget.driver.id}');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sentinelSubscription?.cancel();
    _permissionSubscription?.cancel();
    _locationSubscription?.cancel();
    _pollerTimer?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }

  void _startStatusPoller() {
    _pollerTimer?.cancel();
    _pollerTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isTrackingActive || !mounted) {
        timer.cancel();
        return;
      }
      _checkRemoteStatusManually();
    });
  }

  Future<void> _loadOrPersistSession() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedSession = prefs.getString('current_session_id');
    
    if (savedSession == null) {
      savedSession = "SESS_${DateTime.now().millisecondsSinceEpoch}";
      await prefs.setString('current_session_id', savedSession);
    }
    
    if (mounted) {
      setState(() => _currentSessionId = savedSession);
      debugPrint('💎 Local Session ID (Restored): $_currentSessionId');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyMandatoryCompliance();
      _checkRemoteStatusManually(); 
      if (!_isTrackingActive) _startStatusPoller();
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

  Future<void> _checkRemoteStatusManually() async {
    if (_isTrackingActive || _currentSessionId == null) return;
    setState(() => _isSyncing = true);
    
    try {
      final doc = await FirebaseFirestore.instance.collection('drivers').doc(widget.driver.id).get();
      if (doc.exists) {
        final data = doc.data()!;
        _processRemoteData(data);
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _processRemoteData(Map<String, dynamic> data) {
    if (_currentSessionId == null) return;

    final bool remoteEnabled = data['isTrackingEnabled'] ?? false;
    final String serverSessionId = (data['activeSessionId'] ?? "").toString().trim();
    final String localSessionId = _currentSessionId!.trim();

    debugPrint('[TRIP_INTEL] 📡 CHECK: Remote=$remoteEnabled | ServerSID=$serverSessionId | LocalSID=$localSessionId');

    if (remoteEnabled && serverSessionId == localSessionId) {
      if (!_isTrackingActive) {
        debugPrint('[TRIP_INTEL] ✅ SUCCESS: Session Matched. Activating tracker.');
        _triggerStartTracking();
      }
    } else {
      if (_isTrackingActive) {
        debugPrint('[TRIP_INTEL] 🛑 STOP: Remote disabled or Session Mismatch.');
        _triggerStopTracking();
      }
    }
  }

  void _startReactiveSentinel() {
    _sentinelSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driver.id)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      _processRemoteData(doc.data()!);
    });
  }

  Future<void> _triggerStartTracking() async {
    if (mounted) setState(() => _isTrackingActive = true);
    
    try {
      final trip = await _tripService.startTrip(
        driverId: widget.driver.id,
        truckId: widget.driver.vehicleId,
        wardId: widget.driver.ward,
        routeId: null,
      );
      _routeProcessingService.resetForNewTrip(trip.tripId);
    } catch (e) {
      debugPrint('⚠️ Trip start error: $e');
    }

    await _dutyService.startDuty(widget.driver.id);
    await _locationService.captureLocation(widget.driver.id);
    await NativeLocationService.startTracking(widget.driver.id);
    
    // Subscribe to high-frequency location stream for detailed history (roaming path)
    _locationSubscription = NativeLocationService.getLocationUpdates().listen((event) async {
       if (event != null && _isTrackingActive) {
         final loc = LocationModel.fromMap({
           ...event,
           'driverId': widget.driver.id,
           'timestamp': Timestamp.now(), // Use fresh timestamp from listener
         });
         // Process into detailed route history sub-collection
         final activeTripId = await _tripService.getActiveTripId();
         if (activeTripId != null) {
            await _routeProcessingService.processLocation(
              location: loc,
              tripId: activeTripId,
              driverId: widget.driver.id,
              wardId: widget.driver.ward,
            );
         }
       }
    });

    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_isTrackingActive) {
        timer.cancel();
        return;
      }
      // Primary: Capture via enhanced service (also writes route point now)
      await _locationService.captureLocation(widget.driver.id);
      
      // Safety net: Direct GPS → Firestore write (guaranteed history)
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        final tripId = await _tripService.getActiveTripId();
        if (tripId != null) {
          final pointId = '${DateTime.now().millisecondsSinceEpoch}_${widget.driver.id}';
          await FirebaseFirestore.instance
              .collection('trips')
              .doc(tripId)
              .collection('routePoints')
              .doc(pointId)
              .set({
            'id': pointId,
            'tripId': tripId,
            'driverId': widget.driver.id,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'timestamp': Timestamp.now(),
            'type': 'checkpoint',
            'speed': pos.speed,
            'accuracy': pos.accuracy,
            'stopDurationSec': 0,
            'isInsideWard': true,
            'isInsideRouteBuffer': true,
            'routeDeviationMeters': 0.0,
          });
          debugPrint('[TRIP_INTEL] 📍 Timer route point SAVED: ${pos.latitude}, ${pos.longitude}');
        }
      } catch (e) {
        debugPrint('[TRIP_INTEL] ⚠️ Timer safety net error: $e');
      }
    });
  }

  Future<void> _triggerStopTracking() async {
    if (mounted) setState(() => _isTrackingActive = false);
    try {
      final currentTripId = await _tripService.getActiveTripId();
      if (currentTripId != null) {
        await _tripService.completeTrip(currentTripId);
      }
    } catch (e) {
      debugPrint('⚠️ Trip completion error: $e');
    }

    // Reset local session after tracking ends so a new one is required tomorrow/next time
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_session_id');
    _currentSessionId = null;
    _loadOrPersistSession(); // Generate next session ID

    await _dutyService.endDuty(widget.driver.id);
    _locationSubscription?.cancel();
    _trackingTimer?.cancel();
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
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout)],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
                Text(
                  'Vehicle: ${widget.driver.vehicleId}',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
                const SizedBox(height: 20),
                
                if (_permissionsVerified && !_isTrackingActive)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]
                    ),
                    child: _currentSessionId == null 
                      ? const SizedBox(width: 180, height: 180, child: Center(child: CircularProgressIndicator()))
                      : QrImageView(
                        data: "${widget.driver.id}|$_currentSessionId",
                        version: QrVersions.auto,
                        size: 180.0,
                      ),
                  ),

                if (_isTrackingActive)
                  Container(
                    height: 180,
                    width: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.check_circle, color: Colors.white, size: 80),
                    ),
                  ),
                
                const SizedBox(height: 16),
                Text(
                  _isTrackingActive ? 'DUTY IN PROGRESS' : 'SHOW QR TO SUPERVISOR', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 12),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    Icon(
                      _isTrackingActive ? Icons.sensors : Icons.qr_code_scanner, 
                      size: 70, 
                      color: statusColor
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isTrackingActive ? 'DUTY APPROVED & LIVE' : 'AWAITING APPROVAL',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: statusColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isTrackingActive 
                        ? 'Your location is being monitored by Government Portal' 
                        : 'Duty start requires supervisor QR validation',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                    
                    if (!_isTrackingActive) ...[
                      const SizedBox(height: 40),
                      SizedBox(
                        width: 220,
                        child: ElevatedButton.icon(
                          onPressed: _isSyncing ? null : _checkRemoteStatusManually,
                          icon: _isSyncing 
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                              : const Icon(Icons.sync),
                          label: Text(_isSyncing ? 'Synchronizing...' : 'Sync Approval Status'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.green[700],
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.green[700]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
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
