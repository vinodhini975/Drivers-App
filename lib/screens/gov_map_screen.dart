import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'scan_qr_screen.dart';

class GovMapScreen extends StatefulWidget {
  const GovMapScreen({super.key});

  @override
  State<GovMapScreen> createState() => _GovMapScreenState();
}

class _GovMapScreenState extends State<GovMapScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  GoogleMapController? _mapController;
  final Map<String, Marker> _markers = {};
  StreamSubscription? _subscription;
  bool _showList = false;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(12.9716, 77.5946),
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
          if (lat != null && lng != null) {
            _markers[doc.id] = Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(
                title: data['vehicleId'] ?? 'Truck',
                snippet: 'Driver: ${data['phoneNumber']}',
              ),
            );
          }
        }
      });
    });
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
    // 🛡️ Handles Android System Back Button: Close list if open, instead of app exit
    return WillPopScope(
      onWillPop: () async {
        if (_showList) {
          setState(() => _showList = false);
          return false;
        }
        return true; 
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gov Dashboard'),
          backgroundColor: Colors.blue[900],
          foregroundColor: Colors.white,
          leading: _showList 
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _showList = false))
            : null,
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
              onMapCreated: (c) => _mapController = c,
              myLocationEnabled: false,
              zoomControlsEnabled: true,
            ),
            if (_showList) _buildActiveDriversList(),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDriversList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: const Row(
              children: [
                Icon(Icons.list, color: Colors.blue),
                SizedBox(width: 10),
                Text('Active Trucks Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('drivers').where('isTrackingEnabled', isEqualTo: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No active trucks found'));

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.local_shipping, color: Colors.white, size: 20)),
                      title: Text(data['vehicleId'] ?? 'Unknown'),
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
          ),
        ],
      ),
    );
  }
}
