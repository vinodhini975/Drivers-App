import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/route_point_type.dart';

class RoutePointModel {
  final String id;
  final String tripId;
  final String driverId;
  final double lat;
  final double lng;
  final DateTime timestamp;
  final RoutePointType type;
  final double speed;
  final double accuracy;
  final int stopDurationSec;
  final bool isInsideWard;
  final bool isInsideRouteBuffer;
  final double routeDeviationMeters;
  final bool isSynced;

  RoutePointModel({
    required this.id,
    required this.tripId,
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.type,
    this.speed = 0.0,
    this.accuracy = 0.0,
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

  factory RoutePointModel.fromMap(Map<String, dynamic> map, String docId) {
    return RoutePointModel(
      id: map['id'] ?? docId,
      tripId: map['tripId'] ?? '',
      driverId: map['driverId'] ?? '',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      type: RoutePointTypeExtension.fromFirestoreString(map['type'] ?? 'checkpoint'),
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      stopDurationSec: map['stopDurationSec'] ?? 0,
      isInsideWard: map['isInsideWard'] ?? true,
      isInsideRouteBuffer: map['isInsideRouteBuffer'] ?? true,
      routeDeviationMeters: (map['routeDeviationMeters'] as num?)?.toDouble() ?? 0.0,
      isSynced: true,
    );
  }

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

  factory RoutePointModel.fromLocalStorage(Map<String, dynamic> map) {
    return RoutePointModel(
      id: map['id'],
      tripId: map['tripId'],
      driverId: map['driverId'],
      lat: map['lat'],
      lng: map['lng'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      type: RoutePointTypeExtension.fromFirestoreString(map['type']),
      speed: map['speed'],
      accuracy: map['accuracy'],
      stopDurationSec: map['stopDurationSec'],
      isInsideWard: map['isInsideWard'] == 1,
      isInsideRouteBuffer: map['isInsideRouteBuffer'] == 1,
      routeDeviationMeters: map['routeDeviationMeters'],
      isSynced: map['isSynced'] == 1,
    );
  }
}
