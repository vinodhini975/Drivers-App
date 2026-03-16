import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/trip_model.dart';
import '../../models/route_point_model.dart';
import '../../enums/route_point_type.dart';

/// Admin screen to view a driver's trip route history.
///
/// Displays:
/// - Google Map with full polyline from all ordered route points
/// - Red markers for validated STOP points
/// - Green marker for trip start
/// - Blue marker for trip end
/// - Bottom card with trip summary (driver, truck, times, stops, adherence)
///
/// Usage:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => RouteHistoryScreen(tripId: 'some-trip-id'),
/// ));
/// ```
class RouteHistoryScreen extends StatefulWidget {
  final String tripId;

  const RouteHistoryScreen({super.key, required this.tripId});

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  TripModel? _trip;
  List<RoutePointModel> _points = [];
  bool _isLoading = true;
  String? _errorMessage;

  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      // Fetch trip metadata
      final tripDoc =
          await _firestore.collection('trips').doc(widget.tripId).get();

      if (!tripDoc.exists) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Trip not found: ${widget.tripId}';
        });
        return;
      }

      _trip = TripModel.fromMap(tripDoc.data()!, tripDoc.id);

      // Fetch route points ordered by timestamp
      final pointsSnapshot = await _firestore
          .collection('trips')
          .doc(widget.tripId)
          .collection('routePoints')
          .orderBy('timestamp', descending: false)
          .get();

      _points = pointsSnapshot.docs
          .map((doc) => RoutePointModel.fromMap(doc.data(), doc.id))
          .toList();

      _buildMapData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading trip: $e';
      });
    }
  }

  void _buildMapData() {
    _polylines.clear();
    _markers.clear();

    if (_points.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // ── Build polyline from ALL route points (both checkpoints & stops) ──
    final polylineCoords =
        _points.map((p) => LatLng(p.lat, p.lng)).toList();

    _polylines.add(Polyline(
      polylineId: const PolylineId('route_polyline'),
      color: Colors.blue.shade700,
      width: 4,
      points: polylineCoords,
      patterns: const [], // solid line
    ));

    // ── Start marker (green) ─────────────────────────────────────────────
    _markers.add(Marker(
      markerId: const MarkerId('start'),
      position: polylineCoords.first,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title: 'Start',
        snippet: _formatTime(_points.first.timestamp),
      ),
    ));

    // ── End marker (blue) ────────────────────────────────────────────────
    _markers.add(Marker(
      markerId: const MarkerId('end'),
      position: polylineCoords.last,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: InfoWindow(
        title: 'End',
        snippet: _formatTime(_points.last.timestamp),
      ),
    ));

    // ── Stop markers (red) ───────────────────────────────────────────────
    final stops =
        _points.where((p) => p.type == RoutePointType.stop).toList();
    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      _markers.add(Marker(
        markerId: MarkerId('stop_$i'),
        position: LatLng(stop.lat, stop.lng),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Stop #${i + 1}',
          snippet: 'Duration: ${stop.stopDurationSec}s | ${_formatTime(stop.timestamp)}',
        ),
      ));
    }

    setState(() => _isLoading = false);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDuration(DateTime start, DateTime? end) {
    if (end == null) return 'Ongoing';
    final diff = end.difference(start);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading route data...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700])),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _fetchData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_points.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No route points recorded for this trip',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // ── Google Map ─────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_points.first.lat, _points.first.lng),
            zoom: 14,
          ),
          polylines: _polylines,
          markers: _markers,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          mapType: MapType.normal,
          onMapCreated: (controller) {
            _mapController = controller;
            // Fit map to show entire route
            _fitMapToRoute();
          },
        ),

        // ── Bottom Trip Summary Card ───────────────────────────────────
        if (_trip != null) _buildTripSummaryCard(),
      ],
    );
  }

  void _fitMapToRoute() {
    if (_points.isEmpty || _mapController == null) return;

    double minLat = _points.first.lat;
    double maxLat = _points.first.lat;
    double minLng = _points.first.lng;
    double maxLng = _points.first.lng;

    for (final p in _points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!
        .animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  Widget _buildTripSummaryCard() {
    final trip = _trip!;
    final stops =
        _points.where((p) => p.type == RoutePointType.stop).length;
    final checkpoints =
        _points.where((p) => p.type == RoutePointType.checkpoint).length;

    // Determine adherence score color
    Color scoreColor;
    if (trip.routeAdherenceScore >= 80) {
      scoreColor = Colors.green;
    } else if (trip.routeAdherenceScore >= 50) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 15,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: trip.status == 'ACTIVE'
                          ? Colors.green.shade100
                          : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: trip.status == 'ACTIVE'
                            ? Colors.green.shade800
                            : Colors.blue.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Driver: ${trip.driverId}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Stats Row ──────────────────────────────────────────
              Row(
                children: [
                  _buildStatChip(Icons.local_shipping, trip.truckId ?? 'N/A',
                      'Truck'),
                  const SizedBox(width: 12),
                  _buildStatChip(Icons.access_time,
                      _formatDuration(trip.startTime, trip.endTime), 'Duration'),
                ],
              ),
              const SizedBox(height: 10),

              // ── Counts Row ─────────────────────────────────────────
              Row(
                children: [
                  _buildStatChip(
                      Icons.stop_circle, '$stops', 'Stops',
                      color: Colors.red),
                  const SizedBox(width: 12),
                  _buildStatChip(
                      Icons.route, '$checkpoints', 'Checkpoints',
                      color: Colors.blue),
                  const SizedBox(width: 12),
                  _buildStatChip(
                    Icons.score,
                    '${trip.routeAdherenceScore.toStringAsFixed(0)}%',
                    'Adherence',
                    color: scoreColor,
                  ),
                ],
              ),

              // ── Time Details ───────────────────────────────────────
              const SizedBox(height: 10),
              Text(
                'Start: ${_formatTime(trip.startTime)} | End: ${trip.endTime != null ? _formatTime(trip.endTime!) : "Ongoing"}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label,
      {Color? color}) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey[700]),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color ?? Colors.black87,
                  )),
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}
