import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/location_model.dart';
import '../models/route_point_model.dart';
import '../enums/route_point_type.dart';
import '../config/tracking_constants.dart';
import '../utils/geo_utils.dart';
import 'gis_validation_service.dart';
import 'database_service.dart';

class RouteProcessingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GISValidationService _gisService = GISValidationService();
  final DatabaseService _dbService = DatabaseService.instance;
  final Uuid _uuid = const Uuid();

  // Internal State
  RoutePointModel? _lastSavedRoutePoint;
  DateTime? _lastCheckpointTimestamp;
  
  // Stop detection state
  DateTime? _possibleStopStartTime;
  RoutePointModel? _possibleStopAnchor;
  bool _isInsideConfirmedStop = false;
  RoutePointModel? _lastConfirmedStop;

  Future<void> resetForNewTrip(String tripId) async {
    _lastSavedRoutePoint = null;
    _lastCheckpointTimestamp = null;
    _possibleStopStartTime = null;
    _possibleStopAnchor = null;
    _isInsideConfirmedStop = false;
    _lastConfirmedStop = null;
    debugPrint('🔄 Route processing state reset for trip: $tripId');
  }

  Future<void> processLocation({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required String wardId,
    String? routeId,
  }) async {
    // 1. Quality Guard
    if (location.accuracy > TrackingConstants.maxAcceptedAccuracyMeters) {
      debugPrint('🚫 Point ignored: Low accuracy (${location.accuracy}m)');
      return;
    }

    // 2. GIS Validation
    final gisResult = await _gisService.validatePoint(
      point: location.toLatLng(),
      wardId: wardId,
      routeId: routeId,
    );

    // 3. Stop detection logic
    final bool handledAsStop = await _tryHandleStop(
      location: location,
      tripId: tripId,
      driverId: driverId,
      gisResult: gisResult,
    );

    if (handledAsStop) return;

    // 4. Checkpoint logic
    await _tryCreateCheckpoint(
      location: location,
      tripId: tripId,
      driverId: driverId,
      gisResult: gisResult,
    );
  }

  Future<void> _tryCreateCheckpoint({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required GISValidationResult gisResult,
  }) async {
    final bool shouldSave = _lastSavedRoutePoint == null ||
        GeoUtils.calculateHaversineDistance(
                location.toLatLng(), 
                _lastSavedRoutePoint!.toLatLng()
            ) > TrackingConstants.checkpointDistanceMeters ||
        (_lastCheckpointTimestamp != null &&
            DateTime.now().difference(_lastCheckpointTimestamp!).inSeconds >
                TrackingConstants.checkpointTimeSeconds);

    if (shouldSave) {
      final point = RoutePointModel(
        id: _uuid.v4(),
        tripId: tripId,
        driverId: driverId,
        lat: location.latitude,
        lng: location.longitude,
        timestamp: DateTime.now(),
        type: RoutePointType.checkpoint,
        speed: location.speed,
        accuracy: location.accuracy,
        isInsideWard: gisResult.isInsideWard,
        isInsideRouteBuffer: gisResult.isInsideRouteBuffer,
        routeDeviationMeters: gisResult.routeDeviationMeters,
      );

      await _persistRoutePoint(point);
      _lastSavedRoutePoint = point;
      _lastCheckpointTimestamp = DateTime.now();
      debugPrint('[TRIP_INTEL] 📍 Checkpoint saved: ${point.lat}, ${point.lng}');
    }
  }

  Future<bool> _tryHandleStop({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required GISValidationResult gisResult,
  }) async {
    final bool isLowSpeed = location.speed < TrackingConstants.stopSpeedThresholdMps;

    if (isLowSpeed) {
      if (_possibleStopAnchor == null) {
        // Potential stop started
        _possibleStopAnchor = RoutePointModel(
           id: _uuid.v4(),
           tripId: tripId,
           driverId: driverId,
           lat: location.latitude,
           lng: location.longitude,
           timestamp: DateTime.now(),
           type: RoutePointType.stop,
        );
        _possibleStopStartTime = DateTime.now();
        return false;
      }

      // Already in potential stop state, check if we stayed in radius
      final distance = GeoUtils.calculateHaversineDistance(
        location.toLatLng(), _possibleStopAnchor!.toLatLng());
      
      if (distance <= TrackingConstants.stopRadiusMeters) {
        final duration = DateTime.now().difference(_possibleStopStartTime!).inSeconds;
        
        if (duration >= TrackingConstants.stopMinDurationSeconds && !_isInsideConfirmedStop) {
          // Validate if it's not a duplicate too close to the previous stop
          if (_lastConfirmedStop != null) {
             final gapD = GeoUtils.calculateHaversineDistance(
               location.toLatLng(), _lastConfirmedStop!.toLatLng());
             if (gapD < TrackingConstants.stopDuplicateResetDistanceMeters) {
                return false; 
             }
          }
          
          // CONFIRMED STOP
          final stopPoint = _possibleStopAnchor!.copyWith(
            timestamp: DateTime.now(),
            stopDurationSec: duration,
            accuracy: location.accuracy,
            isInsideWard: gisResult.isInsideWard,
            isInsideRouteBuffer: gisResult.isInsideRouteBuffer,
            routeDeviationMeters: gisResult.routeDeviationMeters,
          );
          
          await _persistRoutePoint(stopPoint);
          _lastSavedRoutePoint = stopPoint;
          _lastConfirmedStop = stopPoint;
          _isInsideConfirmedStop = true;
          debugPrint('[TRIP_INTEL] 🛑 STOP marker confirmed and saved!');
          return true;
        }
      } else {
        // Moved out of radius while slow - reset stop detection
        _possibleStopAnchor = null;
        _possibleStopStartTime = null;
        _isInsideConfirmedStop = false;
      }
    } else {
      // Speed picked up - end any stop detection state
      _possibleStopAnchor = null;
      _possibleStopStartTime = null;
      _isInsideConfirmedStop = false;
    }
    
    return false;
  }

  Future<void> _persistRoutePoint(RoutePointModel point) async {
    // 1. Try Firestore (Live)
    try {
      await _firestore
          .collection('trips')
          .doc(point.tripId)
          .collection('routePoints')
          .doc(point.id)
          .set(point.toMap());
    } catch (e) {
      debugPrint('⚠️ Firestore route point save failed (offline): $e');
    }

    // 2. Always persist to Local SQLite for sync stability and offline history
    await _dbService.insertOfflineRoutePoint(point);
  }

  Future<void> syncOfflineRoutePoints() async {
    try {
      final unsynced = await _dbService.getUnsyncedRoutePoints();
      if (unsynced.isEmpty) return;

      int syncCount = 0;
      for (var point in unsynced) {
        try {
          // Push to Firestore
          await _firestore
              .collection('trips')
              .doc(point.tripId)
              .collection('routePoints')
              .doc(point.id)
              .set(point.toMap());

          // Mark as synced locally
          await _dbService.markRoutePointSynced(point.id);
          syncCount++;
        } catch (e) {
          debugPrint('⚠️ Individual route point sync failed: $e');
          // continue with others
        }
      }
      if (syncCount > 0) {
        debugPrint('✅ Synced $syncCount offline route points to Firestore');
      }
    } catch (e) {
      debugPrint('❌ Error during route points sync: $e');
    }
  }
}

extension on LocationModel {
  LatLng toLatLng() => LatLng(latitude, longitude);
}

extension on RoutePointModel {
  LatLng toLatLng() => LatLng(lat, lng);
}
