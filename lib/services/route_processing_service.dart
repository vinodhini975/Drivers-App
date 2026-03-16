import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import '../models/route_point_model.dart';
import '../enums/route_point_type.dart';
import '../config/tracking_constants.dart';
import '../utils/geo_utils.dart';
import 'database_service.dart';
import 'gis_validation_service.dart';

/// Core route intelligence engine.
///
/// Receives each raw [LocationModel] from the existing tracking pipeline,
/// validates GPS quality, maintains internal state, and decides whether
/// to create a CHECKPOINT, STOP, or IGNORE the point.
///
/// **This service does NOT modify the existing live tracking pipeline.**
/// It runs in parallel: the existing `EnhancedLocationService` continues
/// to update `drivers/{driverId}` with live location AND store raw points.
/// This service only adds classified route points to `trips/{tripId}/routePoints`.
class RouteProcessingService {
  RouteProcessingService._();
  static final RouteProcessingService _instance =
      RouteProcessingService._();
  factory RouteProcessingService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService.instance;
  final Connectivity _connectivity = Connectivity();
  final GISValidationService _gisService = GISValidationService();

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// The last route point we persisted (checkpoint or stop).
  RoutePointModel? _lastSavedPoint;

  /// The last confirmed STOP point. Used for duplicate stop prevention.
  RoutePointModel? _lastConfirmedStop;

  /// When the driver first appeared to start stopping.
  DateTime? _possibleStopStartTime;

  /// The anchor location for potential stop detection.
  LocationModel? _possibleStopAnchor;

  /// Whether we are currently inside a confirmed stop state.
  /// Prevents creating multiple stops while the driver remains parked.
  bool _isCurrentlyInStopState = false;

  /// Counter for generating point IDs within a trip. Combined with tripId
  /// to create unique IDs without the uuid package.
  int _pointCounter = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reset all internal state for a new trip.
  /// Must be called when a new trip starts.
  void resetForNewTrip(String tripId) {
    _lastSavedPoint = null;
    _lastConfirmedStop = null;
    _possibleStopStartTime = null;
    _possibleStopAnchor = null;
    _isCurrentlyInStopState = false;
    _pointCounter = 0;
    debugPrint('🔄 RouteProcessingService reset for trip: $tripId');
  }

  /// Generate a unique point ID using tripId + incrementing counter + timestamp.
  String _generatePointId(String tripId) {
    _pointCounter++;
    return '${tripId}_rp_${_pointCounter}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN ENTRY POINT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Process a single raw location from the existing tracking pipeline.
  ///
  /// This is called for EVERY location point — from both the native foreground
  /// service and the Flutter periodic timer. The method decides whether to
  /// create a CHECKPOINT, STOP, or ignore the point entirely.
  ///
  /// **This method never throws.** All errors are caught internally.
  Future<void> processLocation({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required String wardId,
    String? routeId,
  }) async {
    try {
      // ── STEP 1: Validate GPS accuracy ──────────────────────────────────
      if (location.accuracy > TrackingConstants.maxAcceptedAccuracyMeters) {
        debugPrint(
            '📍 Ignored: accuracy ${location.accuracy.toStringAsFixed(1)}m > ${TrackingConstants.maxAcceptedAccuracyMeters}m');
        return;
      }

      // ── STEP 2: GIS validation ─────────────────────────────────────────
      final gisResult = _gisService.validatePoint(
        lat: location.latitude,
        lng: location.longitude,
        wardId: wardId,
        routeId: routeId,
      );

      // ── STEP 3: Try STOP detection first ───────────────────────────────
      final handledAsStop = await _tryHandleStop(
        location: location,
        tripId: tripId,
        driverId: driverId,
        gis: gisResult,
      );

      // ── STEP 4: If not a stop, try CHECKPOINT ─────────────────────────
      if (!handledAsStop) {
        await _tryCreateCheckpoint(
          location: location,
          tripId: tripId,
          driverId: driverId,
          gis: gisResult,
        );
      }
    } catch (e) {
      debugPrint('❌ RouteProcessingService.processLocation error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOP DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Attempts to detect and create a STOP point.
  ///
  /// Returns `true` if this location was consumed by stop logic (either
  /// accumulating evidence or creating a confirmed stop), meaning the
  /// caller should NOT also create a checkpoint.
  Future<bool> _tryHandleStop({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required GISValidationResult gis,
  }) async {
    // ── Moving too fast → not a stop ─────────────────────────────────────
    if (location.speed > TrackingConstants.stopSpeedThresholdMps) {
      _resetStopAnchor();
      return false;
    }

    // ── First slow point → set anchor ────────────────────────────────────
    if (_possibleStopAnchor == null) {
      _possibleStopAnchor = location;
      _possibleStopStartTime = location.timestamp;
      return true; // Consumed by stop logic, wait for more evidence
    }

    // ── Drifted too far from anchor → reset ──────────────────────────────
    final drift = GeoUtils.distanceBetween(
      _possibleStopAnchor!.latitude,
      _possibleStopAnchor!.longitude,
      location.latitude,
      location.longitude,
    );

    if (drift > TrackingConstants.stopRadiusMeters) {
      _resetStopAnchor();
      return false;
    }

    // ── Check if accumulated enough time ─────────────────────────────────
    final durationSec =
        location.timestamp.difference(_possibleStopStartTime!).inSeconds;

    if (durationSec < TrackingConstants.stopMinDurationSeconds) {
      return true; // Still accumulating — don't create checkpoint either
    }

    // ── Duplicate stop prevention ────────────────────────────────────────
    if (_lastConfirmedStop != null) {
      final distFromLastStop = GeoUtils.distanceBetween(
        _lastConfirmedStop!.lat,
        _lastConfirmedStop!.lng,
        location.latitude,
        location.longitude,
      );
      if (distFromLastStop <
          TrackingConstants.stopDuplicateResetDistanceMeters) {
        // Still near the last confirmed stop — swallow point silently
        return true;
      }
    }

    // ── Create confirmed stop (only once per halt) ───────────────────────
    if (!_isCurrentlyInStopState) {
      final stopPoint = RoutePointModel(
        id: _generatePointId(tripId),
        tripId: tripId,
        driverId: driverId,
        lat: _possibleStopAnchor!.latitude,
        lng: _possibleStopAnchor!.longitude,
        timestamp: _possibleStopStartTime!,
        type: RoutePointType.stop,
        speed: 0.0,
        accuracy: location.accuracy,
        stopDurationSec: durationSec,
        isInsideWard: gis.isInsideWard,
        isInsideRouteBuffer: gis.isInsideRouteBuffer,
        routeDeviationMeters: gis.routeDeviationMeters,
      );

      await _persistRoutePoint(stopPoint);
      _lastConfirmedStop = stopPoint;
      _lastSavedPoint = stopPoint;
      _isCurrentlyInStopState = true;

      // Increment trip stop counter (fire-and-forget)
      _incrementTripCounter(tripId, 'totalStops');

      debugPrint(
          '🛑 STOP created at (${stopPoint.lat.toStringAsFixed(5)}, ${stopPoint.lng.toStringAsFixed(5)}) duration: ${durationSec}s');
    }

    return true;
  }

  /// Reset stop detection state.
  void _resetStopAnchor() {
    _possibleStopAnchor = null;
    _possibleStopStartTime = null;
    _isCurrentlyInStopState = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECKPOINT CREATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a checkpoint if the driver has moved far enough or enough time
  /// has elapsed since the last saved point.
  Future<void> _tryCreateCheckpoint({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required GISValidationResult gis,
  }) async {
    if (_lastSavedPoint != null) {
      final dist = GeoUtils.distanceBetween(
        _lastSavedPoint!.lat,
        _lastSavedPoint!.lng,
        location.latitude,
        location.longitude,
      );
      final timeDiff =
          location.timestamp.difference(_lastSavedPoint!.timestamp).inSeconds;

      // Only create checkpoint if moved enough OR enough time passed
      if (dist < TrackingConstants.checkpointDistanceMeters &&
          timeDiff < TrackingConstants.checkpointTimeSeconds) {
        return; // Not enough movement or time
      }
    }

    final cpPoint = RoutePointModel(
      id: _generatePointId(tripId),
      tripId: tripId,
      driverId: driverId,
      lat: location.latitude,
      lng: location.longitude,
      timestamp: location.timestamp,
      type: RoutePointType.checkpoint,
      speed: location.speed,
      accuracy: location.accuracy,
      stopDurationSec: 0,
      isInsideWard: gis.isInsideWard,
      isInsideRouteBuffer: gis.isInsideRouteBuffer,
      routeDeviationMeters: gis.routeDeviationMeters,
    );

    await _persistRoutePoint(cpPoint);
    _lastSavedPoint = cpPoint;

    // Increment trip checkpoint counter (fire-and-forget)
    _incrementTripCounter(tripId, 'totalCheckpoints');

    debugPrint(
        '📍 CHECKPOINT at (${cpPoint.lat.toStringAsFixed(5)}, ${cpPoint.lng.toStringAsFixed(5)}) speed: ${cpPoint.speed.toStringAsFixed(1)} m/s');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Persist a route point to Firestore (online) or SQLite (offline).
  Future<void> _persistRoutePoint(RoutePointModel point) async {
    final connectivityResult = await _connectivity.checkConnectivity();

    if (connectivityResult != ConnectivityResult.none) {
      try {
        await _saveRoutePointToFirestore(point)
            .timeout(const Duration(seconds: 5));
        return; // Success
      } catch (e) {
        debugPrint('⚠️ Firestore write failed, falling back to SQLite: $e');
      }
    }

    // Offline fallback
    await _saveRoutePointToLocal(point);
  }

  /// Write route point to Firestore: `trips/{tripId}/routePoints/{pointId}`
  Future<void> _saveRoutePointToFirestore(RoutePointModel point) async {
    await _firestore
        .collection('trips')
        .doc(point.tripId)
        .collection('routePoints')
        .doc(point.id)
        .set(point.toMap());
  }

  /// Write route point to local SQLite for later sync.
  Future<void> _saveRoutePointToLocal(RoutePointModel point) async {
    await _dbService.insertOfflineRoutePoint(point);
  }

  /// Increment a counter field on the trip document (fire-and-forget).
  void _incrementTripCounter(String tripId, String field) {
    _firestore.collection('trips').doc(tripId).update({
      field: FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }).catchError((e) {
      debugPrint('⚠️ Trip counter increment failed: $e');
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OFFLINE SYNC (called from EnhancedLocationService on connectivity change)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push all unsynced route points from SQLite to Firestore.
  /// Returns the number of points successfully synced.
  Future<int> syncOfflineRoutePoints() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return 0;

      final unsynced = await _dbService.getUnsyncedRoutePoints();
      if (unsynced.isEmpty) return 0;

      int count = 0;
      for (final point in unsynced) {
        try {
          await _saveRoutePointToFirestore(point)
              .timeout(const Duration(seconds: 3));
          await _dbService.markRoutePointSynced(point.id);
          count++;
        } catch (e) {
          debugPrint('⚠️ Route point sync failed, stopping batch: $e');
          break; // Stop on first failure to avoid spamming
        }
      }

      if (count > 0) {
        debugPrint('✅ Synced $count offline route points');
      }
      return count;
    } catch (e) {
      debugPrint('❌ syncOfflineRoutePoints error: $e');
      return 0;
    }
  }
}
