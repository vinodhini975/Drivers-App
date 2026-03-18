/// Configurable constants for the route intelligence engine.
///
/// Tune these values to match Indian municipal field conditions:
/// - Urban dense areas: reduce checkpoint distance, increase stop duration
/// - Highway routes: increase checkpoint distance, increase speed threshold
/// - Low-end devices: increase accuracy tolerance
class TrackingConstants {
  TrackingConstants._(); // Prevent instantiation

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECKPOINT RULES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Minimum distance (meters) the driver must move from the last saved
  /// route point before a new checkpoint is created.
  static const double checkpointDistanceMeters = 120.0;

  /// Maximum time (seconds) allowed between saved route points.
  /// If exceeded, a checkpoint is forced even if the driver hasn't moved
  /// [checkpointDistanceMeters]. Ensures polyline continuity.
  static const int checkpointTimeSeconds = 75;

  // ═══════════════════════════════════════════════════════════════════════════
  // STOP DETECTION RULES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Speed threshold (m/s) below which a point is considered potentially
  /// stationary. 1.5 m/s ≈ 5.4 km/h — walking speed.
  static const double stopSpeedThresholdMps = 1.5;

  /// Allowed GPS drift radius (meters) while the driver is parked.
  /// Points within this radius of the stop anchor are still considered
  /// the same stop location.
  static const double stopRadiusMeters = 15.0;

  /// Minimum duration (seconds) the driver must remain within
  /// [stopRadiusMeters] to confirm a stop.
  /// Tune higher (45–60) if traffic jams trigger false stops.
  static const int stopMinDurationSeconds = 25;

  /// Distance (meters) the driver must move away from the last confirmed
  /// stop before a new stop can be created. Prevents duplicate stop markers
  /// when the driver briefly moves and parks again at the same spot.
  static const double stopDuplicateResetDistanceMeters = 40.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GPS QUALITY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum acceptable GPS accuracy (meters). Points with worse accuracy
  /// are silently dropped to prevent jitter-based false checkpoints/stops.
  static const double maxAcceptedAccuracyMeters = 50.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GIS VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Buffer distance (meters) around the planned route polyline.
  /// Points within this buffer are considered "on-route."
  static const double routeBufferThresholdMeters = 30.0;

  /// Geofence radius (meters) around the depot/yard center point.
  static const double depotGeofenceRadiusMeters = 50.0;
}
