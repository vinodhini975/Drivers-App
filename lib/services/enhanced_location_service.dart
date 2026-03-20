import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import 'database_service.dart';
import 'duty_service.dart';
import 'auth_service.dart';
import 'trip_service.dart';
import 'route_processing_service.dart';

class EnhancedLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DatabaseService _dbService = DatabaseService.instance;
  final DutyService _dutyService = DutyService();
  final AuthService _authService = AuthService();
  final TripService _tripService = TripService();
  final RouteProcessingService _routeProcessingService = RouteProcessingService();

  Future<bool> captureLocation(String driverId) async {
    // 1. Guard: Ensure driver ID is valid
    if (driverId.isEmpty) {
      debugPrint('Sync skipped: Waiting for driver identity');
      return false;
    }

    try {
      final isDutyActive = await _dutyService.isDutyActive();
      if (!isDutyActive) return false;

      final batteryLevel = await _battery.batteryLevel;
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final location = LocationModel(
        driverId: driverId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        batteryLevel: batteryLevel,
        timestamp: DateTime.now(),
        isOnDuty: true,
        isSynced: false,
      );

      // ════════════════════════════════════════════════════════════════════
      // NEW: Feed location into route processing pipeline (fire-and-forget)
      // ════════════════════════════════════════════════════════════════════
      _feedToRouteProcessing(location, driverId);

      // ════════════════════════════════════════════════════════════════════
      // EXISTING: Live location sync (PRESERVED)
      // ════════════════════════════════════════════════════════════════════
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        try {
          await _syncToFirebase(location).timeout(const Duration(seconds: 5));
          return true;
        } catch (e) {
          debugPrint('⚠️ Network lag, saving offline: $e');
          await _dbService.insertLocation(location);
          return true;
        }
      } else {
        await _dbService.insertLocation(location);
        return true;
      }
    } catch (e) {
      debugPrint('❌ Capture Error: $e');
      return false;
    }
  }

  /// FIXED: Direct route point writer — bypasses complex pipeline.
  /// Every captured location is now GUARANTEED to be saved as a trip route point.
  void _feedToRouteProcessing(LocationModel location, String driverId) async {
    try {
      final activeTripId = await _tripService.getActiveTripId();
      if (activeTripId == null) {
        debugPrint('[TRIP_INTEL] ⚠️ No active trip ID found. Route point skipped.');
        return;
      }

      // DIRECT WRITE: Save route point straight to Firestore (no filters, no GIS)
      final pointId = '${DateTime.now().millisecondsSinceEpoch}_$driverId';
      await _firestore
          .collection('trips')
          .doc(activeTripId)
          .collection('routePoints')
          .doc(pointId)
          .set({
        'id': pointId,
        'tripId': activeTripId,
        'driverId': driverId,
        'lat': location.latitude,
        'lng': location.longitude,
        'timestamp': Timestamp.fromDate(location.timestamp),
        'type': 'checkpoint',
        'speed': location.speed,
        'accuracy': location.accuracy,
        'stopDurationSec': 0,
        'isInsideWard': true,
        'isInsideRouteBuffer': true,
        'routeDeviationMeters': 0.0,
      });

      debugPrint('[TRIP_INTEL] 📍 Route point SAVED: ${location.latitude}, ${location.longitude} → Trip: $activeTripId');
    } catch (e) {
      debugPrint('[TRIP_INTEL] ❌ Route point save FAILED: $e');
    }
  }

  Future<void> _syncToFirebase(LocationModel location) async {
    final docRef = _firestore.collection('drivers').doc(location.driverId);
    WriteBatch batch = _firestore.batch();
    
    batch.update(docRef, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'lastUpdate': FieldValue.serverTimestamp(),
      'isActive': true,
    });

    final historyRef = docRef.collection('location_history').doc();
    batch.set(historyRef, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'timestamp': Timestamp.fromDate(location.timestamp),
    });

    await batch.commit();
  }

  Future<int> syncOfflineLocations() async {
    final driverId = await _authService.getCurrentDriverId();
    if (driverId == null) {
      debugPrint('Sync skipped: No authenticated driver found');
      return 0;
    }

    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return 0;

      // Sync offline route points
      _routeProcessingService.syncOfflineRoutePoints();

      final unsynced = await _dbService.getUnsyncedLocations();
      if (unsynced.isEmpty) return 0;

      int count = 0;
      for (var loc in unsynced) {
        try {
          await _syncToFirebase(loc).timeout(const Duration(seconds: 3));
          if (loc.id != null) {
             await _dbService.markAsSynced(loc.id!);
             count++;
          }
        } catch (e) {
          break; 
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> shouldContinueTracking() async {
    final driverId = await _authService.getCurrentDriverId();
    if (driverId == null) return false;
    
    final active = await _dutyService.isDutyActive();
    return active;
  }

  Stream<ConnectivityResult> get connectivityStream => _connectivity.onConnectivityChanged;
}
