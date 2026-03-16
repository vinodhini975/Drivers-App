import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a single driver trip (one duty session).
///
/// A trip is created when a driver starts duty and completed when duty ends.
/// Route points (checkpoints + stops) are stored as a sub-collection under
/// the trip document in Firestore.
class TripModel {
  final String tripId;
  final String driverId;
  final String? truckId;
  final String? wardId;
  final String? routeId;
  final DateTime startTime;
  final DateTime? endTime;

  /// 'ACTIVE' or 'COMPLETED'
  final String status;

  final int totalStops;
  final int totalCheckpoints;

  /// 0–100 score indicating what percentage of route points fell within
  /// the planned route corridor.
  final double routeAdherenceScore;

  final DateTime createdAt;
  final DateTime updatedAt;

  TripModel({
    required this.tripId,
    required this.driverId,
    this.truckId,
    this.wardId,
    this.routeId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.totalStops = 0,
    this.totalCheckpoints = 0,
    this.routeAdherenceScore = 0.0,
    required this.createdAt,
    required this.updatedAt,
  });

  TripModel copyWith({
    String? tripId,
    String? driverId,
    String? truckId,
    String? wardId,
    String? routeId,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
    int? totalStops,
    int? totalCheckpoints,
    double? routeAdherenceScore,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TripModel(
      tripId: tripId ?? this.tripId,
      driverId: driverId ?? this.driverId,
      truckId: truckId ?? this.truckId,
      wardId: wardId ?? this.wardId,
      routeId: routeId ?? this.routeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      totalStops: totalStops ?? this.totalStops,
      totalCheckpoints: totalCheckpoints ?? this.totalCheckpoints,
      routeAdherenceScore: routeAdherenceScore ?? this.routeAdherenceScore,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'driverId': driverId,
      'truckId': truckId,
      'wardId': wardId,
      'routeId': routeId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'status': status,
      'totalStops': totalStops,
      'totalCheckpoints': totalCheckpoints,
      'routeAdherenceScore': routeAdherenceScore,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory TripModel.fromMap(Map<String, dynamic> map, String docId) {
    return TripModel(
      tripId: docId,
      driverId: map['driverId'] ?? '',
      truckId: map['truckId'],
      wardId: map['wardId'],
      routeId: map['routeId'],
      startTime: map['startTime'] is Timestamp
          ? (map['startTime'] as Timestamp).toDate()
          : DateTime.now(),
      endTime: map['endTime'] != null && map['endTime'] is Timestamp
          ? (map['endTime'] as Timestamp).toDate()
          : null,
      status: map['status'] ?? 'ACTIVE',
      totalStops: map['totalStops'] ?? 0,
      totalCheckpoints: map['totalCheckpoints'] ?? 0,
      routeAdherenceScore: (map['routeAdherenceScore'] ?? 0.0).toDouble(),
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: map['updatedAt'] is Timestamp
          ? (map['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
