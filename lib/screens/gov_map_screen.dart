import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class GovMapScreen extends StatefulWidget {
  const GovMapScreen({super.key});

  @override
  State<GovMapScreen> createState() => _GovMapScreenState();
}

class _GovMapScreenState extends State<GovMapScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  GoogleMapController? _mapController;
  final Map<String, Marker> _markers = {};
  StreamSubscription? _subscription;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(12.9716, 77.5946),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _startListeningToDrivers();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startListeningToDrivers() {
    // Read-only query - compatible with current rules
    _subscription = _firestore
        .collection('drivers')
        .where('status', isEqualTo: 'active')  // Filter for active drivers
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      setState(() {
        _markers.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final lat = data['latitude'] as double?;
          final lng = data['longitude'] as double?;
          final driverId = data['driverId'] as String? ?? 'Unknown';
          final name = data['name'] as String? ?? 'Driver';
          final status = data['status'] as String?;

          if (lat != null && lng != null && status == 'active') {
            final marker = Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: name,
                snippet: 'ID: $driverId | Vehicle: ${data['vehicleId']}',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            );
            _markers[doc.id] = marker;
          }
        }
      });
    }, onError: (error) {
      // Handle errors gracefully without spam
      debugPrint('Government map error: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government Live Monitoring'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _startListeningToDrivers(),
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: _initialCamera,
        markers: _markers.values.toSet(),
        onMapCreated: (controller) => _mapController = controller,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
        mapType: MapType.normal,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_markers.isNotEmpty) {
            final firstMarker = _markers.values.first.position;
            _mapController?.animateCamera(CameraUpdate.newLatLngZoom(firstMarker, 14));
          }
        },
        label: Text('Found ${_markers.length} Drivers'),
        icon: const Icon(Icons.local_shipping),
        backgroundColor: Colors.blue[900],
      ),
    );
  }
}
