import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';
import 'package:flutter/foundation.dart';

class TripService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _activeTripIdKey = 'current_active_trip_id';

  Future<TripModel> startTrip({
    required String driverId,
    required String truckId,
    String? wardId,
    String? routeId,
  }) async {
    final String tripId = "TRIP_${DateTime.now().millisecondsSinceEpoch}_$driverId";
    
    final trip = TripModel(
      tripId: tripId,
      driverId: driverId,
      truckId: truckId,
      wardId: wardId,
      routeId: routeId,
      startTime: DateTime.now(),
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await _firestore.collection('trips').doc(tripId).set(trip.toMap());
      await _saveActiveTripId(tripId);
      debugPrint('✅ Trip started on Firestore: $tripId');
    } catch (e) {
      debugPrint('❌ Failed to start trip on Firestore: $e');
      // Even if firestore fails (offline), we should save locally
      await _saveActiveTripId(tripId);
    }

    return trip;
  }

  Future<void> completeTrip(String tripId, {
    int totalStops = 0,
    int totalCheckpoints = 0,
    double routeAdherenceScore = 100.0,
  }) async {
    try {
      await _firestore.collection('trips').doc(tripId).update({
        'status': 'COMPLETED',
        'endTime': FieldValue.serverTimestamp(),
        'totalStops': totalStops,
        'totalCheckpoints': totalCheckpoints,
        'routeAdherenceScore': routeAdherenceScore,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await clearActiveTripId();
      debugPrint('🏁 Trip completed: $tripId');
    } catch (e) {
      debugPrint('❌ Failed to complete trip: $e');
      // Mark as completed locally at least
      await clearActiveTripId();
    }
  }

  Future<String?> getActiveTripId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeTripIdKey);
  }

  Future<void> _saveActiveTripId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTripIdKey, id);
  }

  Future<void> clearActiveTripId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeTripIdKey);
  }
}
