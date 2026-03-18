import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/route_point_type.dart';

/// Model representing a single classified route point within a trip.
///
/// Each raw GPS point that passes through [RouteProcessingService] is
/// classified as either a [RoutePointType.checkpoint] or [RoutePointType.stop]
/// before being persisted as a [RoutePointModel].
class RoutePointModel {
  /// Unique identifier for this route point.
  final String id;

  /// The trip this point belongs to.
  final String tripId;

  /// The driver who generated this point.
  final String driverId;

  /// Latitude in decimal degrees.
  final double lat;

  /// Longitude in decimal degrees.
  final double lng;

  /// When this point was captured.
  final DateTime timestamp;

  /// Classification: checkpoint or stop.
  final RoutePointType type;

  /// Speed at capture time, in m/s.
  final double speed;

  /// GPS accuracy at capture time, in meters.
  final double accuracy;

  /// Duration the driver was stopped (only meaningful for STOP points).
  final int stopDurationSec;

  /// Whether this point falls inside the assigned ward polygon.
  final bool isInsideWard;

  /// Whether this point falls within the route corridor buffer.
  final bool isInsideRouteBuffer;

  /// Shortest distance (meters) from this point to the planned route polyline.
  final double routeDeviationMeters;

  /// Whether this point has been synced to Firestore (for offline support).
  final bool isSynced;

  RoutePointModel({
    required this.id,
    required this.tripId,
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.type,
    required this.speed,
    required this.accuracy,
    this.stopDurationSec = 0,
    this.isInsideWard = true,
    this.isInsideRouteBuffer = true,
    this.routeDeviationMeters = 0.0,
    this.isSynced = false,
  });

  RoutePointModel copyWith({
    String? id,
    String? tripId,
    String? driverId,
    double? lat,
    double? lng,
    DateTime? timestamp,
    RoutePointType? type,
    double? speed,
    double? accuracy,
    int? stopDurationSec,
    bool? isInsideWard,
    bool? isInsideRouteBuffer,
    double? routeDeviationMeters,
    bool? isSynced,
  }) {
    return RoutePointModel(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      driverId: driverId ?? this.driverId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      stopDurationSec: stopDurationSec ?? this.stopDurationSec,
      isInsideWard: isInsideWard ?? this.isInsideWard,
      isInsideRouteBuffer: isInsideRouteBuffer ?? this.isInsideRouteBuffer,
      routeDeviationMeters: routeDeviationMeters ?? this.routeDeviationMeters,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  /// Serialize to Firestore document map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'driverId': driverId,
      'lat': lat,
      'lng': lng,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type.toFirestoreString(),
      'speed': speed,
      'accuracy': accuracy,
      'stopDurationSec': stopDurationSec,
      'isInsideWard': isInsideWard,
      'isInsideRouteBuffer': isInsideRouteBuffer,
      'routeDeviationMeters': routeDeviationMeters,
    };
  }

  /// Deserialize from Firestore document map.
  factory RoutePointModel.fromMap(Map<String, dynamic> map, [String? docId]) {
    return RoutePointModel(
      id: docId ?? map['id'] ?? '',
      tripId: map['tripId'] ?? '',
      driverId: map['driverId'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      timestamp: map['timestamp'] is Timestamp
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      type: RoutePointTypeExtension.fromFirestoreString(map['type'] ?? 'checkpoint'),
      speed: (map['speed'] ?? 0.0).toDouble(),
      accuracy: (map['accuracy'] ?? 0.0).toDouble(),
      stopDurationSec: map['stopDurationSec'] ?? 0,
      isInsideWard: map['isInsideWard'] is bool
          ? map['isInsideWard']
          : (map['isInsideWard'] ?? 1) == 1,
      isInsideRouteBuffer: map['isInsideRouteBuffer'] is bool
          ? map['isInsideRouteBuffer']
          : (map['isInsideRouteBuffer'] ?? 1) == 1,
      routeDeviationMeters: (map['routeDeviationMeters'] ?? 0.0).toDouble(),
      isSynced: map['isSynced'] is bool
          ? map['isSynced']
          : (map['isSynced'] ?? 0) == 1,
    );
  }

  /// Serialize to SQLite row map.
  Map<String, dynamic> toLocalStorage() {
    return {
      'id': id,
      'tripId': tripId,
      'driverId': driverId,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type.toFirestoreString(),
      'speed': speed,
      'accuracy': accuracy,
      'stopDurationSec': stopDurationSec,
      'isInsideWard': isInsideWard ? 1 : 0,
      'isInsideRouteBuffer': isInsideRouteBuffer ? 1 : 0,
      'routeDeviationMeters': routeDeviationMeters,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  /// Deserialize from SQLite row map.
  factory RoutePointModel.fromLocalStorage(Map<String, dynamic> map) {
    return RoutePointModel(
      id: map['id'] ?? '',
      tripId: map['tripId'] ?? '',
      driverId: map['driverId'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      type: RoutePointTypeExtension.fromFirestoreString(map['type'] ?? 'checkpoint'),
      speed: (map['speed'] ?? 0.0).toDouble(),
      accuracy: (map['accuracy'] ?? 0.0).toDouble(),
      stopDurationSec: map['stopDurationSec'] ?? 0,
      isInsideWard: (map['isInsideWard'] ?? 1) == 1,
      isInsideRouteBuffer: (map['isInsideRouteBuffer'] ?? 1) == 1,
      routeDeviationMeters: (map['routeDeviationMeters'] ?? 0.0).toDouble(),
      isSynced: (map['isSynced'] ?? 0) == 1,
    );
  }
}
