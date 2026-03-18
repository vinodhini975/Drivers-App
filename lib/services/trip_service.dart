import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/trip_model.dart';
import '../models/route_point_model.dart';
import 'gis_validation_service.dart';

/// Service managing the lifecycle of trips (one per duty session).
///
/// A trip starts when the driver taps "START MY DUTY" and completes when
/// they tap "END MY DUTY". The active trip ID is persisted in
/// SharedPreferences so it survives app restarts during an active duty.
class TripService {
  TripService._();
  static final TripService instance = TripService._();
  factory TripService() => instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _activeTripKey = 'active_trip_id';

  // ═══════════════════════════════════════════════════════════════════════════
  // TRIP LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new trip document in Firestore and persist the trip ID locally.
  ///
  /// Called immediately after [DutyService.startDuty] succeeds.
  Future<TripModel> startTrip({
    required String driverId,
    String? truckId,
    String? wardId,
    String? routeId,
  }) async {
    final now = DateTime.now();

    // Generate a unique trip ID using Firestore's auto-ID (no uuid dependency)
    final docRef = _firestore.collection('trips').doc();
    final tripId = docRef.id;

    final trip = TripModel(
      tripId: tripId,
      driverId: driverId,
      truckId: truckId,
      wardId: wardId,
      routeId: routeId,
      startTime: now,
      status: 'ACTIVE',
      totalStops: 0,
      totalCheckpoints: 0,
      routeAdherenceScore: 0.0,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await docRef.set(trip.toMap());
    } catch (e) {
      // If Firestore write fails (offline), we still proceed.
      // The trip will be created when connectivity returns.
      debugPrint('⚠️ Trip creation failed (offline?): $e');
    }

    // Always persist locally so route processing can work offline
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTripKey, tripId);

    debugPrint('🚀 Trip started: $tripId for driver: $driverId');
    return trip;
  }

  /// Complete the active trip: set endTime, status, and final counters.
  ///
  /// Called immediately before [DutyService.endDuty].
  Future<void> completeTrip(String tripId) async {
    final now = DateTime.now();

    try {
      // Fetch route points to calculate final adherence score
      double adherenceScore = 0.0;
      int totalStops = 0;
      int totalCheckpoints = 0;

      try {
        final pointsSnap = await _firestore
            .collection('trips')
            .doc(tripId)
            .collection('routePoints')
            .get();

        if (pointsSnap.docs.isNotEmpty) {
          final points = pointsSnap.docs
              .map((doc) => RoutePointModel.fromMap(doc.data(), doc.id))
              .toList();

          totalStops = points.where((p) => p.type.name == 'stop').length;
          totalCheckpoints =
              points.where((p) => p.type.name == 'checkpoint').length;
          adherenceScore = GISValidationService()
              .calculateRouteAdherenceScore(points: points);
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch route points for scoring: $e');
      }

      await _firestore.collection('trips').doc(tripId).update({
        'endTime': Timestamp.fromDate(now),
        'status': 'COMPLETED',
        'totalStops': totalStops,
        'totalCheckpoints': totalCheckpoints,
        'routeAdherenceScore': adherenceScore,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
          '✅ Trip completed: $tripId | Stops: $totalStops | CPs: $totalCheckpoints | Score: ${adherenceScore.toStringAsFixed(1)}');
    } catch (e) {
      debugPrint('⚠️ Trip completion Firestore update failed: $e');
    }

    // Always clear local trip ID
    await clearActiveTripId();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCAL PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the active trip ID from local storage.
  /// Returns `null` if no trip is active (i.e., driver is off-duty).
  Future<String?> getActiveTripId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_activeTripKey);
    } catch (e) {
      debugPrint('Error getting active trip ID: $e');
      return null;
    }
  }

  /// Clear the active trip ID from local storage.
  Future<void> clearActiveTripId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeTripKey);
    } catch (e) {
      debugPrint('Error clearing active trip ID: $e');
    }
  }
}
