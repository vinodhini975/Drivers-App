import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'scan_qr_screen.dart';
import 'admin/route_history_screen.dart';

class GovMapScreen extends StatefulWidget {
  const GovMapScreen({super.key});

  @override
  State<GovMapScreen> createState() => _GovMapScreenState();
}

class _GovMapScreenState extends State<GovMapScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  GoogleMapController? _mapController;
  final Map<String, Marker> _markers = {};
  StreamSubscription? _subscription;
  bool _showList = false;

  final Map<String, Map<String, dynamic>> _driverDataCache = {};
  final Map<String, String?> _activeTripIds = {};
  final Map<String, String> _addressCache = {};

  late AnimationController _pulseController;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(12.9716, 77.5946),
    zoom: 12,
  );

  static const Color _primaryDark = Color(0xFF0D1B2A);
  static const Color _primaryBlue = Color(0xFF1B4965);
  static const Color _accentGreen = Color(0xFF2EC4B6);
  static const Color _accentBlue = Color(0xFF5FA8D3);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _startLiveTracking();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _mapController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startLiveTracking() {
    _subscription?.cancel();
    _subscription = _firestore
        .collection('drivers')
        .where('isTrackingEnabled', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        final bool isFirstLoad = _markers.isEmpty && snapshot.docs.isNotEmpty;
        _markers.clear();
        _driverDataCache.clear();
        _activeTripIds.clear();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final lat = (data['latitude'] as num?)?.toDouble();
          final lng = (data['longitude'] as num?)?.toDouble();

          if (lat != null && lng != null) {
            _driverDataCache[doc.id] = {
              'name': data['name'] ?? 'Driver',
              'vehicleId': data['vehicleId'] ?? 'N/A',
              'phone': data['phoneNumber'] ?? '',
              'lat': lat,
              'lng': lng,
              'lastUpdate': data['lastUpdate'],
            };

            _addressCache.putIfAbsent(doc.id, () => "Calculating area...");
            _reverseGeocode(doc.id, lat, lng);

            _markers[doc.id] = Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                title: data['vehicleId'],
                snippet: 'Area: ${_addressCache[doc.id]}',
                onTap: () => _onDriverMarkerTapped(doc.id),
              ),
            );

            _fetchActiveTripId(doc.id);
          }
        }
        
        // Auto-focus if this was the first time vehicles appeared
        if (isFirstLoad) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllMarkers());
        }
      });
    }, onError: (error) {
      debugPrint('Government map error: $error');
    });
  }

  Future<void> _reverseGeocode(String docId, double lat, double lng) async {
    // Basic throttle/skip if already known for similar point
    if (_addressCache[docId] != null && _addressCache[docId] != "Calculating area...") {
      return; 
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark p = placemarks[0];
        String addr = "${p.street}, ${p.subLocality}";
        if (mounted) setState(() => _addressCache[docId] = addr);
      }
    } catch (e) {
      debugPrint('Geocoding error for $docId: $e');
    }
  }

  Future<void> _fetchActiveTripId(String driverDocId) async {
    try {
      // Find the most recent active trip for this driver
      final tripSnap = await _firestore
          .collection('trips')
          .where('driverId', isEqualTo: driverDocId)
          .where('status', isEqualTo: 'ACTIVE')
          .limit(1)
          .get();

      if (mounted && tripSnap.docs.isNotEmpty) {
        setState(() {
          _activeTripIds[driverDocId] = tripSnap.docs.first.id;
        });
        debugPrint('[GOV_PORTAL] 🔗 Linked Trip ${tripSnap.docs.first.id} to Driver $driverDocId');
      }
    } catch (e) {
      if (e.toString().contains('index')) {
        debugPrint('[GOV_PORTAL] 🚨 CRITICAL: Firestore Composite Index missing! Click the link in your console to create it.');
      } else {
        debugPrint('[GOV_PORTAL] Error fetching trip: $e');
      }
    }
  }

  void _onDriverMarkerTapped(String docId) {
    final driverData = _driverDataCache[docId];
    if (driverData == null) return;

    final tripId = _activeTripIds[docId];
    final address = _addressCache[docId] ?? "N/A";
    
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(driverData['lat'], driverData['lng']), 15),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildModernBottomSheet(
        docId: docId,
        name: driverData['name'],
        vehicleId: driverData['vehicleId'],
        lat: driverData['lat'],
        lng: driverData['lng'],
        address: address,
        tripId: tripId,
        lastUpdate: driverData['lastUpdate'],
      ),
    );
  }

  Future<void> _disableTracking(String docId) async {
    await _firestore.collection('drivers').doc(docId).update({
      'isTrackingEnabled': false,
      'activeSessionId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context, 
      MaterialPageRoute(builder: (_) => const LoginScreen()), 
      (route) => false
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Live Monitoring', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _primaryDark.withOpacity(0.9),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Driver QR',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanQrScreen())),
          ),
          IconButton(
            icon: Icon(_showList ? Icons.map : Icons.list),
            tooltip: _showList ? 'View Map' : 'Active Drivers List',
            onPressed: () => setState(() => _showList = !_showList),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            markers: _markers.values.toSet(),
            onMapCreated: (c) {
              _mapController = c;
              _setMapStyle(c);
            },
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(top: 100),
          ),
          if (_showList) _buildActiveDriversList(),
          if (!_showList) _buildDriverCountFAB(),
        ],
      ),
    );
  }

  Widget _buildActiveDriversList() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: kToolbarHeight + 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: const Row(
              children: [
                Icon(Icons.list, color: _primaryBlue),
                SizedBox(width: 10),
                Text('Active Trucks Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _driverDataCache.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final id = _driverDataCache.keys.elementAt(index);
                final data = _driverDataCache[id]!;
                final addr = _addressCache[id] ?? "N/A";

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _primaryBlue,
                    child: Icon(Icons.local_shipping, color: Colors.white, size: 20),
                  ),
                  title: Text(data['vehicleId']),
                  subtitle: Text('Location: $addr'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => _disableTracking(id),
                    child: const Text('DISABLE', style: TextStyle(color: Colors.white)),
                  ),
                  onTap: () {
                    setState(() => _showList = false);
                    _onDriverMarkerTapped(id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCountFAB() {
    return Positioned(
      bottom: 32,
      left: 20,
      right: 20,
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: _primaryDark,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryDark.withOpacity(0.2 + 0.15 * _pulseController.value),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _accentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_markers.length} Active Vehicles',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          FloatingActionButton(
            backgroundColor: Colors.white,
            onPressed: _fitAllMarkers,
            child: const Icon(Icons.fit_screen, color: _primaryDark),
          ),
        ],
      ),
    );
  }

  Widget _buildModernBottomSheet({
    required String docId,
    required String name,
    required String vehicleId,
    required double lat,
    required double lng,
    required String address,
    required String? tripId,
    required dynamic lastUpdate,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _accentGreen.withOpacity(0.1),
                child: const Icon(Icons.person, color: _accentGreen, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('Vehicle: $vehicleId', style: TextStyle(color: Colors.grey[600])),
                    Text('Location: $address', style: TextStyle(color: Colors.blue[900], fontSize: 13, fontWeight: FontWeight.w500)),
                    if (lastUpdate != null)
                      Text(
                        'Last seen: ${_formatTimestamp(lastUpdate)}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 8),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: tripId != null 
                ? () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RouteHistoryScreen(tripId: tripId)));
                  }
                : null,
              icon: const Icon(Icons.route),
              label: Text(tripId != null ? 'View Route History' : 'No Trip Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: Colors.grey[200],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () {
                _disableTracking(docId);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              label: const Text('Stop Remote Tracking', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  void _fitAllMarkers() {
    if (_markers.isEmpty || _mapController == null) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final marker in _markers.values) {
      final pos = marker.position;
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 
      70
    ));
  }

  void _setMapStyle(GoogleMapController controller) {
    const style = '''[{"featureType":"poi","stylers":[{"visibility":"off"}]}]''';
    controller.setMapStyle(style);
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Never';
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return 'Unknown';
    }
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}
