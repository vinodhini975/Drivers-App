import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'dart:ui';
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
  final Set<Polyline> _polylines = {};
  StreamSubscription? _subscription;
  StreamSubscription? _routeSubscription;
  String? _selectedDriverId;
  bool _showList = false;

  // DIAGNOSTIC STATE
  static const bool _debugEnabled = false; 
  String? _diagnosticError;
  int _diagnosticPoints = 0;
  String? _activeTripId;

  final Map<String, Map<String, dynamic>> _driverDataCache = {};
  final Map<String, String?> _activeTripIds = {};
  final Map<String, String> _addressCache = {};
  final Map<String, LatLng> _lastGeocodedPosition = {};

  late AnimationController _pulseController;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(12.9716, 77.5946),
    zoom: 12,
  );

  static const Color _primaryDark = Color(0xFF0D1B2A);
  static const Color _accentGreen = Color(0xFF2EC4B6);

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
    _routeSubscription?.cancel();
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

      // Determine which driver IDs are currently present
      final Set<String> currentIds = snapshot.docs.map((doc) => doc.id).toSet();

      // Remove any drivers that are no longer in the snapshot from caches and markers
      final List<String> removedIds = _driverDataCache.keys.where((id) => !currentIds.contains(id)).toList();
      for (final id in removedIds) {
        _driverDataCache.remove(id);
        _addressCache.remove(id);
        _lastGeocodedPosition.remove(id);
        _markers.remove(id);
        if (_selectedDriverId == id) {
          _selectedDriverId = null;
          _activeTripId = null;
          _diagnosticPoints = 0;
          _polylines.clear();
          _markers.remove('trip_start');
          _routeSubscription?.cancel();
        }
      }

      setState(() {
        final bool isFirstLoad = _markers.isEmpty && snapshot.docs.isNotEmpty;
        _markers.removeWhere((key, value) => key != 'trip_start');
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final lat = (data['latitude'] as num?)?.toDouble();
          final lng = (data['longitude'] as num?)?.toDouble();

          _driverDataCache[doc.id] = {
            'name': data['name'] ?? 'Driver',
            'vehicleId': data['vehicleId'] ?? 'N/A',
            'lat': lat,
            'lng': lng,
            'lastUpdate': data['lastUpdate'],
          };

          if (lat != null && lng != null) {
            debugPrint('[GOV_PORTAL] 🛰️ Driver ${doc.id} (${data['name']}) raw coords: lat=$lat, lng=$lng, vehicle=${data['vehicleId']}');
            _addressCache.putIfAbsent(doc.id, () => "Calculating area...");
            _reverseGeocode(doc.id, lat, lng);

            _markers[doc.id] = Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              onTap: () => _onDriverMarkerTapped(doc.id),
            );
            _fetchImplicitTrip(doc.id);
          }
        }
        
        if (isFirstLoad) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllMarkers());
        }
      });
    }, onError: (e) {
      setState(() => _diagnosticError = "Live Track Error: $e");
    });
  }

  /// Returns true if the driver has moved significantly since last geocode (~100m)
  bool _hasMovedSignificantly(String docId, double lat, double lng) {
    final lastPos = _lastGeocodedPosition[docId];
    if (lastPos == null) return true;
    // ~0.001 degrees ≈ 111 meters
    final dLat = (lat - lastPos.latitude).abs();
    final dLng = (lng - lastPos.longitude).abs();
    return dLat > 0.001 || dLng > 0.001;
  }

  /// Uses the geocoding package for accurate, local/device-based human-readable place names.
  Future<void> _reverseGeocode(String docId, double lat, double lng) async {
    if (_addressCache[docId] != null &&
        _addressCache[docId] != "Calculating area..." &&
        !_hasMovedSignificantly(docId, lat, lng)) {
      return;
    }

    debugPrint('[GOV_PORTAL] 🔄 Geocoding $docId at lat=$lat, lng=$lng');

    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 8));
      if (!mounted) return;

      String area = 'Unknown location';

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty && p.subLocality != p.street) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        ];
        if (parts.isNotEmpty) {
          area = parts.take(2).join(', ');
        } else {
          area = 'Unknown location';
        }
      }

      debugPrint('[GOV_PORTAL] 📌 Address for $docId: $area');

      setState(() {
        _addressCache[docId] = area;
        _lastGeocodedPosition[docId] = LatLng(lat, lng);
        final data = _driverDataCache[docId];
        if (data != null) {
          _markers[docId] = Marker(
            markerId: MarkerId(docId),
            position: LatLng(data['lat'], data['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            onTap: () => _onDriverMarkerTapped(docId),
          );
        }
      });
    } catch (e) {
      debugPrint('[GOV_PORTAL] ⚠️ Geocoding failed for $docId: $e');
      if (mounted) {
        setState(() {
          _addressCache[docId] = 'Location unavailable';
        });
      }
    }
  }

  Future<void> _fetchImplicitTrip(String driverId) async {
    try {
      var tripSnap = await _firestore
          .collection('trips')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'ACTIVE')
          .orderBy('startTime', descending: true)
          .limit(1)
          .get();

      if (tripSnap.docs.isEmpty) {
        final cutOff = DateTime.now().subtract(const Duration(hours: 24));
        tripSnap = await _firestore
            .collection('trips')
            .where('driverId', isEqualTo: driverId)
            .where('status', isEqualTo: 'COMPLETED')
            .where('startTime', isGreaterThan: Timestamp.fromDate(cutOff))
            .orderBy('startTime', descending: true)
            .limit(1)
            .get();
      }

      if (mounted && tripSnap.docs.isNotEmpty) {
        final tripId = tripSnap.docs.first.id;
        setState(() {
          _activeTripIds[driverId] = tripId;
          if (_selectedDriverId == driverId) {
            _activeTripId = tripId;
            _listenToSelectedRoute(tripId);
          }
        });
      } else {
        if (mounted && _selectedDriverId == driverId) {
          setState(() {
            _activeTripId = null;
            _diagnosticPoints = 0;
            _polylines.clear();
          });
        }
      }
    } catch (e) {
      setState(() => _diagnosticError = "Trip Fetch Error: $e");
      debugPrint("❌ Trip Fetch Error: $e");
    }
  }

  void _listenToSelectedRoute(String tripId) {
    _routeSubscription?.cancel();
    _routeSubscription = _firestore
        .collection('trips')
        .doc(tripId)
        .collection('routePoints')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final points = snapshot.docs.map((doc) => LatLng(
        (doc.data()['lat'] as num).toDouble(),
        (doc.data()['lng'] as num).toDouble(),
      )).toList();

      setState(() {
        _diagnosticPoints = points.length;
        _polylines.clear();
        _markers.remove('trip_start');

        if (points.isNotEmpty) {
          _polylines.add(Polyline(
            polylineId: PolylineId(tripId),
            points: points,
            color: Colors.blueAccent.shade700,
            width: 7,
          ));

          _markers['trip_start'] = Marker(
            markerId: const MarkerId('trip_start'),
            position: points.first,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          );
        }
      });
    }, onError: (e) {
      setState(() => _diagnosticError = "Route Listener Error: $e");
    });
  }

  void _onDriverMarkerTapped(String docId) {
    final driverData = _driverDataCache[docId];
    if (driverData == null) return;

    setState(() {
      _selectedDriverId = docId;
      _diagnosticError = null;
    });

    final lat = driverData['lat'];
    final lng = driverData['lng'];
    
    if (lat != null && lng != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
    }

    final address = _addressCache[docId] ?? "N/A";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DriverDetailBottomSheet(
        docId: docId,
        initialName: driverData['name'],
        initialVehicleId: driverData['vehicleId'],
        initialLat: lat ?? 0.0,
        initialLng: lng ?? 0.0,
        initialAddress: address,
        initialLastUpdate: driverData['lastUpdate'],
        onDisableTracking: _disableTracking,
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

  Widget _buildDiagnosticOverlay() {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Text(
                  "DIAGNOSTICS - ${(_selectedDriverId ?? 'NO DRIVER SELECTED').toUpperCase()}",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            Text("Active Trip ID: ${_activeTripId ?? 'None'}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
            Text("Route Points: $_diagnosticPoints", style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
            if (_diagnosticError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text("ERROR: $_diagnosticError", style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
          ],
        ),
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

  Widget _buildFloatingAppBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Live Monitoring',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _primaryDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.shade400,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.shade400.withOpacity(0.5),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_driverDataCache.length} Active Vehicles',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _appBarActionButton(
                      icon: Icons.qr_code_scanner_rounded,
                      tooltip: 'Scan Driver QR',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ScanQrScreen()),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    _appBarActionButton(
                      icon: Icons.format_list_bulleted_rounded,
                      tooltip: 'Active Drivers List',
                      onPressed: () => setState(() => _showList = true),
                    ),
                    const SizedBox(width: 12),
                    _appBarActionButton(
                      icon: Icons.logout_rounded,
                      tooltip: 'Logout',
                      color: Colors.red.shade600,
                      onPressed: _logout,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appBarActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          splashColor: (color ?? _primaryDark).withOpacity(0.2),
          highlightColor: (color ?? _primaryDark).withOpacity(0.1),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(icon, color: color ?? _primaryDark, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            markers: _markers.values.toSet(),
            polylines: _polylines,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              _setMapStyle(c);
            },
            onTap: (_) => setState(() {
              _selectedDriverId = null;
              _polylines.clear();
              _routeSubscription?.cancel();
              _activeTripId = null;
              _diagnosticPoints = 0;
            }),
          ),
          if (_debugEnabled && _selectedDriverId != null) _buildDiagnosticOverlay(),
          if (!_showList) _buildFloatingAppBar(),
          if (_showList) _buildActiveDriversList(),
        ],
      ),
    );
  }

  Widget _buildActiveDriversList() {
    return SafeArea(
      child: Container(
        color: Colors.grey.shade50,
        child: Column(
          children: [
            Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _primaryDark.withOpacity(0.1),
                  child: const Icon(Icons.local_shipping, color: _primaryDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Active Drivers Attendance',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: _primaryDark),
                      ),
                      Text(
                        '${_driverDataCache.length} vehicles currently tracking',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _primaryDark),
                  onPressed: () => setState(() => _showList = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _driverDataCache.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.no_accounts_rounded, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No Active Drivers',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                        ),
                        Text(
                          'Active drivers will appear here',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _driverDataCache.length,
                    itemBuilder: (context, index) {
                      final id = _driverDataCache.keys.elementAt(index);
                      final data = _driverDataCache[id]!;
                      final addr = _addressCache[id] ?? "N/A";
                      final lastSeen = data['lastUpdate'];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() => _showList = false);
                              _onDriverMarkerTapped(id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: _accentGreen.withOpacity(0.1),
                                        child: const Icon(Icons.person, color: _accentGreen, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              data['name'] ?? 'Driver',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _primaryDark),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Vehicle ID: ${data['vehicleId']}',
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.circle, color: Colors.green, size: 6),
                                            SizedBox(width: 4),
                                            Text(
                                              'LIVE',
                                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, color: Colors.grey.shade400, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          addr,
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (lastSeen != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.access_time, color: Colors.grey.shade400, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Last updated: ${_formatTimestamp(lastSeen)}',
                                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],

                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
     ),
    );
  }

}

class DriverDetailBottomSheet extends StatefulWidget {
  final String docId;
  final String initialName;
  final String initialVehicleId;
  final double initialLat;
  final double initialLng;
  final String initialAddress;
  final dynamic initialLastUpdate;
  final Function(String) onDisableTracking;

  const DriverDetailBottomSheet({
    super.key,
    required this.docId,
    required this.initialName,
    required this.initialVehicleId,
    required this.initialLat,
    required this.initialLng,
    required this.initialAddress,
    required this.initialLastUpdate,
    required this.onDisableTracking,
  });

  @override
  State<DriverDetailBottomSheet> createState() => _DriverDetailBottomSheetState();
}

class _DriverDetailBottomSheetState extends State<DriverDetailBottomSheet> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _currentAddress = "";
  LatLng? _lastGeocodedPos;

  @override
  void initState() {
    super.initState();
    _currentAddress = widget.initialAddress;
    _lastGeocodedPos = LatLng(widget.initialLat, widget.initialLng);
  }

  Future<void> _reverseGeocodeSheet(double lat, double lng) async {
    if (_lastGeocodedPos != null) {
      final dLat = (lat - _lastGeocodedPos!.latitude).abs();
      final dLng = (lng - _lastGeocodedPos!.longitude).abs();
      if (dLat < 0.001 && dLng < 0.001) return;
    }

    _lastGeocodedPos = LatLng(lat, lng);

    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty && p.subLocality != p.street) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        ];
        setState(() {
          _currentAddress = parts.isNotEmpty ? parts.take(2).join(', ') : 'Unknown location';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('drivers').doc(widget.docId).snapshots(),
      builder: (context, driverSnapshot) {
        var name = widget.initialName;
        var vehicleId = widget.initialVehicleId;
        var lat = widget.initialLat;
        var lng = widget.initialLng;

        if (driverSnapshot.hasData && driverSnapshot.data!.exists) {
          final data = driverSnapshot.data!.data()!;
          name = data['name'] ?? widget.initialName;
          vehicleId = data['vehicleId'] ?? widget.initialVehicleId;
          lat = (data['latitude'] as num?)?.toDouble() ?? widget.initialLat;
          lng = (data['longitude'] as num?)?.toDouble() ?? widget.initialLng;
          _reverseGeocodeSheet(lat, lng);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('trips')
              .where('driverId', isEqualTo: widget.docId)
              .snapshots(),
          builder: (context, tripSnapshot) {
            String? tripId;
            if (tripSnapshot.hasData && tripSnapshot.data!.docs.isNotEmpty) {
              final docs = tripSnapshot.data!.docs;
              final activeTrips = docs.where((doc) => doc.data()['status'] == 'ACTIVE').toList();
              if (activeTrips.isNotEmpty) {
                activeTrips.sort((a, b) {
                  final aTime = (a.data()['startTime'] as Timestamp).toDate();
                  final bTime = (b.data()['startTime'] as Timestamp).toDate();
                  return bTime.compareTo(aTime);
                });
                tripId = activeTrips.first.id;
              } else {
                final cutOff = DateTime.now().subtract(const Duration(hours: 24));
                final recentCompleted = docs.where((doc) {
                  final data = doc.data();
                  if (data['status'] != 'COMPLETED') return false;
                  final startTime = (data['startTime'] as Timestamp?)?.toDate();
                  return startTime != null && startTime.isAfter(cutOff);
                }).toList();
                
                if (recentCompleted.isNotEmpty) {
                  recentCompleted.sort((a, b) {
                    final aTime = (a.data()['startTime'] as Timestamp).toDate();
                    final bTime = (b.data()['startTime'] as Timestamp).toDate();
                    return bTime.compareTo(aTime);
                  });
                  tripId = recentCompleted.first.id;
                }
              }
            }

            return Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2EC4B6).withOpacity(0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const CircleAvatar(
                          radius: 30,
                          backgroundColor: Color(0xFFE8F8F7),
                          child: Icon(Icons.person_rounded, color: Color(0xFF2EC4B6), size: 32),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0D1B2A),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.green.shade100, width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'LIVE',
                                        style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.local_shipping_outlined, color: Colors.grey.shade500, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Vehicle: $vehicleId',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, color: Colors.grey.shade500, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _currentAddress,
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: tripId != null
                                ? () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => RouteHistoryScreen(tripId: tripId!)),
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.route_rounded, size: 20),
                            label: const Text(
                              'Route History',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D1B2A),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              disabledBackgroundColor: Colors.grey.shade200,
                              disabledForegroundColor: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Stop Tracking?'),
                                  content: Text('Are you sure you want to stop tracking $name ($vehicleId)? This will end their active tracking session.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        Navigator.pop(context);
                                        widget.onDisableTracking(widget.docId);
                                      },
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Stop Tracking'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              side: BorderSide(color: Colors.red.shade200, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Stop Tracking',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
