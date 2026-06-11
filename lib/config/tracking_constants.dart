class TrackingConstants {
  // Checkpoint Rules: Ultra-Granular for Roaming Path
  static const double checkpointDistanceMeters = 10.0;
  static const int checkpointTimeSeconds = 10;

  // Stop Detection Rules
  static const double stopSpeedThresholdMps = 0.5;
  static const double stopRadiusMeters = 5.0;
  static const int stopMinDurationSeconds = 10;
  static const double stopDuplicateResetDistanceMeters = 10.0;

  // GIS & Quality Rules
  static const double routeBufferThresholdMeters = 30.0;
  static const double maxAcceptedAccuracyMeters = 80.0;
  static const double depotGeofenceRadiusMeters = 50.0;
}
