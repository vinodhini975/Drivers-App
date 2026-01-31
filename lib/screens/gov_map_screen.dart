import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'scan_qr_screen.dart';

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
  bool _showList = false;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(12.9716, 77.5946), // Bangalore Center
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// 🛰️ REAL-TIME MARKER LOGIC
  void _startLiveTracking() {
    _subscription = _firestore
        .collection('drivers')
        .where('isTrackingEnabled', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      setState(() {
        _markers.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final lat = data['latitude'] as double?;
          final lng = data['longitude'] as double?;
          final mobile = data['phoneNumber'] ?? 'No Mobile';
          final vehicle = data['vehicleId'] ?? 'No Vehicle';

          if (lat != null && lng != null) {
            _markers[doc.id] = Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(
                title: 'Truck: $vehicle',
                snippet: 'Driver: $mobile',
              ),
            );
          }
        }
      });
    });
  }

  /// 🛑 REMOTE DISABLE LOGIC
  Future<void> _disableTracking(String docId) async {
    await _firestore.collection('drivers').doc(docId).update({
      'isTrackingEnabled': false,
      'activeSessionId': null, // Invalidate current session
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gov Monitoring'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanQrScreen())),
          ),
          IconButton(
            icon: Icon(_showList ? Icons.map : Icons.list),
            onPressed: () => setState(() => _showList = !_showList),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            markers: _markers.values.toSet(),
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: false, // Govt device doesn't track itself
            zoomControlsEnabled: true,
          ),
          if (_showList) _buildActiveDriversList(),
        ],
      ),
    );
  }

  Widget _buildActiveDriversList() {
    return Container(
      color: Colors.white.withOpacity(0.95),
      child: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('drivers').where('isTrackingEnabled', isEqualTo: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          
          if (docs.isEmpty) return const Center(child: Text('No Active Trucks Found'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.local_shipping, color: Colors.blue),
                title: Text(data['vehicleId'] ?? 'Unknown Vehicle'),
                subtitle: Text('Mobile: ${data['phoneNumber']}'),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => _disableTracking(docs[index].id),
                  child: const Text('DISABLE', style: TextStyle(color: Colors.white)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
