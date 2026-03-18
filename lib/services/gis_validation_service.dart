import '../utils/geo_utils.dart';
import '../models/route_point_model.dart';
import '../config/tracking_constants.dart';

/// Result of a GIS validation pass on a single GPS point.
class GISValidationResult {
  /// Whether the point falls inside the assigned ward polygon.
  final bool isInsideWard;

  /// Whether the point falls within the planned route corridor buffer.
  final bool isInsideRouteBuffer;

  /// Shortest distance (meters) from the point to the planned route polyline.
  final double routeDeviationMeters;

  const GISValidationResult({
    required this.isInsideWard,
    required this.isInsideRouteBuffer,
    required this.routeDeviationMeters,
  });

  /// Default result when no GIS data is available.
  /// Defaults to "inside" everything so tracking is not blocked by missing GIS data.
  static const GISValidationResult defaultResult = GISValidationResult(
    isInsideWard: true,
    isInsideRouteBuffer: true,
    routeDeviationMeters: 0.0,
  );
}

/// Lightweight app-side GIS validation service.
///
/// Performs ward polygon containment, depot geofence, route corridor buffer,
/// and route adherence scoring using pure Dart math (no external GIS backend).
///
/// **Ward and Route Data:**
/// Currently defaults to passing validation when polygons/routes are not
/// provided. To enable real validation, load ward polygons and planned route
/// polylines from Firestore or local storage and pass them to the methods.
class GISValidationService {
  GISValidationService._();
  static final GISValidationService instance = GISValidationService._();
  factory GISValidationService() => instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // CACHED GIS DATA
  // Ward polygons and route polylines can be loaded once and cached here.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ward polygons keyed by wardId.
  /// Load from Firestore `wards/{wardId}` document containing polygon vertices.
  final Map<String, List<({double lat, double lng})>> _wardPolygons = {};

  /// Planned route polylines keyed by routeId.
  /// Load from Firestore `routes/{routeId}` document containing polyline vertices.
  final Map<String, List<({double lat, double lng})>> _routePolylines = {};

  /// Load ward polygon data. Call once when driver starts duty or when GIS
  /// data becomes available.
  void setWardPolygon(String wardId, List<({double lat, double lng})> polygon) {
    _wardPolygons[wardId] = polygon;
  }

  /// Load planned route polyline data.
  void setRoutePloyline(String routeId, List<({double lat, double lng})> polyline) {
    _routePolylines[routeId] = polyline;
  }

  /// Clear cached GIS data (e.g., on logout or ward change).
  void clearCache() {
    _wardPolygons.clear();
    _routePolylines.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POINT VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validates a single GPS point against available GIS data.
  ///
  /// Gracefully defaults to [GISValidationResult.defaultResult] when
  /// ward or route data is not available — tracking is never blocked.
  GISValidationResult validatePoint({
    required double lat,
    required double lng,
    required String wardId,
    String? routeId,
  }) {
    bool insideWard = true;
    bool insideRouteBuffer = true;
    double deviationMeters = 0.0;

    // Ward polygon check
    final wardPoly = _wardPolygons[wardId];
    if (wardPoly != null && wardPoly.length >= 3) {
      insideWard = isPointInsideWard(
        lat: lat,
        lng: lng,
        polygon: wardPoly,
      );
    }

    // Route corridor check
    if (routeId != null) {
      final routePoly = _routePolylines[routeId];
      if (routePoly != null && routePoly.length >= 2) {
        deviationMeters = distanceToNearestRouteSegment(
          lat: lat,
          lng: lng,
          routePolyline: routePoly,
        );
        insideRouteBuffer = isInsideRouteBuffer(
          deviationMeters: deviationMeters,
          bufferThreshold: TrackingConstants.routeBufferThresholdMeters,
        );
      }
    }

    return GISValidationResult(
      isInsideWard: insideWard,
      isInsideRouteBuffer: insideRouteBuffer,
      routeDeviationMeters: deviationMeters,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INDIVIDUAL CHECKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a point is inside a ward polygon.
  bool isPointInsideWard({
    required double lat,
    required double lng,
    required List<({double lat, double lng})> polygon,
  }) {
    return GeoUtils.isPointInsidePolygon(
      point: (lat: lat, lng: lng),
      polygon: polygon,
    );
  }

  /// Check if a point is inside a circular depot geofence.
  bool isInsideDepotGeofence({
    required double pointLat,
    required double pointLng,
    required double depotCenterLat,
    required double depotCenterLng,
    required double radiusMeters,
  }) {
    return GeoUtils.isInsideCircularGeofence(
      pointLat: pointLat,
      pointLng: pointLng,
      centerLat: depotCenterLat,
      centerLng: depotCenterLng,
      radiusMeters: radiusMeters,
    );
  }

  /// Compute shortest distance from a point to the nearest segment of a
  /// planned route polyline.
  double distanceToNearestRouteSegment({
    required double lat,
    required double lng,
    required List<({double lat, double lng})> routePolyline,
  }) {
    return GeoUtils.distanceToNearestPolylineSegment(
      pointLat: lat,
      pointLng: lng,
      polyline: routePolyline,
    );
  }

  /// Whether the deviation from the planned route is within the buffer.
  bool isInsideRouteBuffer({
    required double deviationMeters,
    required double bufferThreshold,
  }) {
    return deviationMeters <= bufferThreshold;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTE ADHERENCE SCORING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate a 0–100 route adherence score from a list of route points.
  ///
  /// Logic:
  /// - Base score: % of points inside route buffer
  /// - Bonus weight: points inside ward polygon count 20% more
  /// - Score is clamped to [0, 100]
  double calculateRouteAdherenceScore({
    required List<RoutePointModel> points,
  }) {
    if (points.isEmpty) return 0.0;

    double totalWeight = 0.0;
    double earnedWeight = 0.0;

    for (final p in points) {
      // Each point has a base weight of 1.0
      double pointWeight = 1.0;

      // Points inside ward get 20% bonus weight
      if (p.isInsideWard) {
        pointWeight += 0.2;
      }

      totalWeight += pointWeight;

      if (p.isInsideRouteBuffer) {
        earnedWeight += pointWeight;
      }
    }

    if (totalWeight <= 0) return 0.0;

    final score = (earnedWeight / totalWeight) * 100.0;
    return score.clamp(0.0, 100.0);
  }
}
