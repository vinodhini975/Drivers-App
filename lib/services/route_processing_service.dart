import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
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
  }

  Future<void> processLocation({
    required LocationModel location,
    required String tripId,
    required String driverId,
    required String wardId,
    String? routeId,
  }) async {
    if (location.accuracy > TrackingConstants.maxAcceptedAccuracyMeters) return;

    final gisResult = await _gisService.validatePoint(
      point: LatLng(location.latitude, location.longitude),
      wardId: wardId,
      routeId: routeId,
    );

    final bool handledAsStop = await _tryHandleStop(
      location: location,
      tripId: tripId,
      driverId: driverId,
      gisResult: gisResult,
    );

    if (handledAsStop) return;

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
                LatLng(location.latitude, location.longitude), 
                LatLng(_lastSavedRoutePoint!.lat, _lastSavedRoutePoint!.lng)
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

      final distance = GeoUtils.calculateHaversineDistance(
        LatLng(location.latitude, location.longitude), LatLng(_possibleStopAnchor!.lat, _possibleStopAnchor!.lng));
      
      if (distance <= TrackingConstants.stopRadiusMeters) {
        final duration = DateTime.now().difference(_possibleStopStartTime!).inSeconds;
        
        if (duration >= TrackingConstants.stopMinDurationSeconds && !_isInsideConfirmedStop) {
          if (_lastConfirmedStop != null) {
             final gapD = GeoUtils.calculateHaversineDistance(
               LatLng(location.latitude, location.longitude), LatLng(_lastConfirmedStop!.lat, _lastConfirmedStop!.lng));
             if (gapD < TrackingConstants.stopDuplicateResetDistanceMeters) return false; 
          }
          
          final stopPoint = RoutePointModel(
            id: _possibleStopAnchor!.id,
            tripId: tripId,
            driverId: driverId,
            lat: location.latitude,
            lng: location.longitude,
            timestamp: DateTime.now(),
            type: RoutePointType.stop,
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
          return true;
        }
      } else {
        _possibleStopAnchor = null;
        _possibleStopStartTime = null;
        _isInsideConfirmedStop = false;
      }
    } else {
      _possibleStopAnchor = null;
      _possibleStopStartTime = null;
      _isInsideConfirmedStop = false;
    }
    return false;
  }

  Future<void> _persistRoutePoint(RoutePointModel point) async {
    try {
      await _firestore
          .collection('trips')
          .doc(point.tripId)
          .collection('routePoints')
          .doc(point.id)
          .set(point.toMap());
    } catch (e) {
      debugPrint("❌ RouteProcessing PERSIST ERROR: $e");
    }
    await _dbService.insertOfflineRoutePoint(point);
  }

  Future<void> syncOfflineRoutePoints() async {
    try {
      final unsynced = await _dbService.getUnsyncedRoutePoints();
      if (unsynced.isEmpty) return;

      for (var point in unsynced) {
        try {
          await _firestore
              .collection('trips')
              .doc(point.tripId)
              .collection('routePoints')
              .doc(point.id)
              .set(point.toMap());
          await _dbService.markRoutePointSynced(point.id);
        } catch (e) {
          debugPrint("❌ RouteSync ERROR for point ${point.id}: $e");
        }
      }
    } catch (e) {
      debugPrint("❌ Global RouteSync ERROR: $e");
    }
  }
}
