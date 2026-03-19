import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import '../../models/trip_model.dart';
import '../../models/route_point_model.dart';
import '../../enums/route_point_type.dart';

class RouteHistoryScreen extends StatefulWidget {
  final String tripId;

  const RouteHistoryScreen({super.key, required this.tripId});

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  GoogleMapController? _mapController;
  TripModel? _trip;
  final List<RoutePointModel> _points = [];
  bool _isLoading = true;
  String _startAddress = "Loading start location...";
  String _endAddress = "Loading end location...";
  StreamSubscription? _liveSubscription;
  LatLng? _livePosition;

  @override
  void initState() {
    super.initState();
    _fetchTripData();
    _startLiveListener();
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startLiveListener() {
    FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .snapshots()
        .listen((tripDoc) {
      if (tripDoc.exists && mounted) {
        final driverId = tripDoc.data()?['driverId'];
        if (driverId != null) {
          _liveSubscription?.cancel();
          _liveSubscription = FirebaseFirestore.instance
              .collection('drivers')
              .doc(driverId)
              .snapshots()
              .listen((driverDoc) {
            if (driverDoc.exists && mounted) {
              final data = driverDoc.data()!;
              if (data['latitude'] != null && data['longitude'] != null) {
                setState(() {
                  _livePosition = LatLng(
                    (data['latitude'] as num).toDouble(),
                    (data['longitude'] as num).toDouble(),
                  );
                });
              }
            }
          });
        }
      }
    });
  }

  Future<void> _fetchTripData() async {
    try {
      final tripDoc = await FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .get();
      
      if (!tripDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final pointsSnap = await FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .collection('routePoints')
          .orderBy('timestamp', descending: false)
          .get();

      if (mounted) {
        setState(() {
          _trip = TripModel.fromMap(tripDoc.data()!, tripDoc.id);
          _points.clear();
          for (var doc in pointsSnap.docs) {
            _points.add(RoutePointModel.fromMap(doc.data(), doc.id));
          }
          _isLoading = false;
        });
      }

      if (_points.isNotEmpty) {
        _fitBounds();
        _geocodeStartPoint();
        _geocodeEndPoint();
      }
    } catch (e) {
      debugPrint('Error fetching history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _geocodeStartPoint() async {
    try {
      List<Placemark> p = await placemarkFromCoordinates(_points.first.lat, _points.first.lng);
      if (p.isNotEmpty && mounted) setState(() => _startAddress = "${p.first.street}, ${p.first.subLocality}");
    } catch (_) { if (mounted) setState(() => _startAddress = "Area not found"); }
  }

  Future<void> _geocodeEndPoint() async {
    try {
      List<Placemark> p = await placemarkFromCoordinates(_points.last.lat, _points.last.lng);
      if (p.isNotEmpty && mounted) setState(() => _endAddress = "${p.first.street}, ${p.first.subLocality}");
    } catch (_) { if (mounted) setState(() => _endAddress = "Area not found"); }
  }

  void _fitBounds() {
    if (_points.isEmpty || _mapController == null) return;
    
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in _points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      70,
    ));
  }

  Set<Polyline> _getPolylines() {
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _points.map((e) => LatLng(e.lat, e.lng)).toList(),
        color: Colors.blue.withOpacity(0.7),
        width: 6,
        jointType: JointType.round,
      )
    };
  }

  Set<Marker> _getMarkers() {
    final markers = <Marker>{};
    
    // Live Position Marker (Blue Truck) - Priority 1
    if (_livePosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('live_pos'),
        position: _livePosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Live Vehicle Position'),
        zIndex: 10,
      ));
    }

    if (_points.isEmpty) return markers;

    // Start Marker (Green)
    markers.add(Marker(
      markerId: const MarkerId('start'),
      position: LatLng(_points.first.lat, _points.first.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: 'Started At', snippet: _startAddress),
    ));

    // End Marker (Destination)
    markers.add(Marker(
      markerId: const MarkerId('end'),
      position: LatLng(_points.last.lat, _points.last.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: 'Last At', snippet: _endAddress),
    ));

    // Stop Markers
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      if (p.type == RoutePointType.stop) {
        markers.add(Marker(
          markerId: MarkerId('stop_$i'),
          position: LatLng(p.lat, p.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'Halt Point',
            snippet: 'Duration: ${p.stopDurationSec} sec',
          ),
        ));
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Intelligence'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trip == null
              ? const Center(child: Text('No trip details found.'))
              : Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _livePosition ?? (_points.isNotEmpty ? LatLng(_points.first.lat, _points.first.lng) : const LatLng(12.9716, 77.5946)),
                        zoom: 14,
                      ),
                      onMapCreated: (c) {
                        _mapController = c;
                        if (_points.isNotEmpty) _fitBounds();
                      },
                      polylines: _getPolylines(),
                      markers: _getMarkers(),
                    ),
                    _buildTripSummaryCard(),
                  ],
                ),
    );
  }

  Widget _buildTripSummaryCard() {
    if (_trip == null) return const SizedBox.shrink();
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vehicle: ${_trip!.truckId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text('Driver ID: ${_trip!.driverId}', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Score: ${_trip!.routeAdherenceScore.toInt()}%',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                   _statEntry(Icons.stop_circle, '${_trip!.totalStops}', 'Stops'),
                   _statEntry(Icons.gps_fixed, '${_points.length}', 'Points'),
                   _statEntry(Icons.timer_outlined, _formatDuration(_trip!.startTime, _trip!.endTime), 'Duration'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statEntry(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF1A237E), size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  String _formatDuration(DateTime start, DateTime? end) {
    final finish = end ?? DateTime.now();
    final diff = finish.difference(start);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}
