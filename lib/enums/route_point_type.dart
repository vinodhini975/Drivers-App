/// Classification types for processed route points.
///
/// Raw GPS points from the tracking pipeline are classified into one of these
/// types by [RouteProcessingService] before being stored as route history.
enum RoutePointType {
  /// Sparse movement point saved for polyline continuity.
  /// Created when the driver has moved > [TrackingConstants.checkpointDistanceMeters]
  /// or time > [TrackingConstants.checkpointTimeSeconds] since the last saved point.
  checkpoint,

  /// Validated halt point for actual stop markers.
  /// Created when the driver has been stationary within [TrackingConstants.stopRadiusMeters]
  /// for at least [TrackingConstants.stopMinDurationSeconds].
  stop,
}

/// Extension methods for [RoutePointType] serialization.
extension RoutePointTypeExtension on RoutePointType {
  /// Converts enum to a Firestore-safe string.
  String toFirestoreString() => name;

  /// Parses a Firestore string back into the enum.
  /// Falls back to [RoutePointType.checkpoint] for unknown values.
  static RoutePointType fromFirestoreString(String value) {
    return RoutePointType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RoutePointType.checkpoint,
    );
  }
}
