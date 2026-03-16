import 'dart:math' as math;

/// Pure-Dart geospatial utility functions.
///
/// Lightweight implementations of Haversine, point-in-polygon,
/// and point-to-segment distance — no external GIS backend needed.
class GeoUtils {
  GeoUtils._(); // Prevent instantiation

  static const double _earthRadiusMeters = 6371000.0;
  static const double _degToRad = math.pi / 180.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // HAVERSINE DISTANCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the great-circle distance in **meters** between two points
  /// using the Haversine formula.
  static double distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = (lat2 - lat1) * _degToRad;
    final dLon = (lon2 - lon1) * _degToRad;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * _degToRad) *
            math.cos(lat2 * _degToRad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POINT-IN-POLYGON (Ray Casting)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns `true` if [point] lies inside the [polygon].
  ///
  /// Uses the ray-casting algorithm. [polygon] must be a closed ring
  /// (first and last vertex should be the same, but works either way).
  static bool isPointInsidePolygon({
    required ({double lat, double lng}) point,
    required List<({double lat, double lng})> polygon,
  }) {
    if (polygon.length < 3) return false;

    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final yi = polygon[i].lat;
      final xi = polygon[i].lng;
      final yj = polygon[j].lat;
      final xj = polygon[j].lng;

      if (((yi > point.lat) != (yj > point.lat)) &&
          (point.lng < (xj - xi) * (point.lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POINT-TO-SEGMENT DISTANCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the shortest distance in **meters** from [point] to a line
  /// segment defined by [segStart] → [segEnd].
  ///
  /// Projects the point onto the segment and clamps to endpoints.
  static double pointToSegmentDistance({
    required double pointLat,
    required double pointLng,
    required double segStartLat,
    required double segStartLng,
    required double segEndLat,
    required double segEndLng,
  }) {
    // Convert to planar approximation (meters) from segStart
    final dx = _longitudeToMeters(segEndLng - segStartLng, segStartLat);
    final dy = _latitudeToMeters(segEndLat - segStartLat);
    final px = _longitudeToMeters(pointLng - segStartLng, segStartLat);
    final py = _latitudeToMeters(pointLat - segStartLat);

    final segLenSq = dx * dx + dy * dy;

    if (segLenSq < 0.001) {
      // Segment is essentially a point
      return distanceBetween(pointLat, pointLng, segStartLat, segStartLng);
    }

    // Project point onto segment, clamped to [0, 1]
    double t = (px * dx + py * dy) / segLenSq;
    t = t.clamp(0.0, 1.0);

    final projLat = segStartLat + t * (segEndLat - segStartLat);
    final projLng = segStartLng + t * (segEndLng - segStartLng);

    return distanceBetween(pointLat, pointLng, projLat, projLng);
  }

  /// Returns the shortest distance in **meters** from [point] to a polyline.
  static double distanceToNearestPolylineSegment({
    required double pointLat,
    required double pointLng,
    required List<({double lat, double lng})> polyline,
  }) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) {
      return distanceBetween(
          pointLat, pointLng, polyline[0].lat, polyline[0].lng);
    }

    double minDist = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = pointToSegmentDistance(
        pointLat: pointLat,
        pointLng: pointLng,
        segStartLat: polyline[i].lat,
        segStartLng: polyline[i].lng,
        segEndLat: polyline[i + 1].lat,
        segEndLng: polyline[i + 1].lng,
      );
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CIRCULAR GEOFENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns `true` if [point] is inside a circular geofence centered at
  /// [centerLat], [centerLng] with the given [radiusMeters].
  static bool isInsideCircularGeofence({
    required double pointLat,
    required double pointLng,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) {
    return distanceBetween(pointLat, pointLng, centerLat, centerLng) <=
        radiusMeters;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DUPLICATE DISTANCE CHECK
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns `true` if the distance between two points is less than
  /// [thresholdMeters]. Useful for duplicate stop prevention.
  static bool isWithinDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
    required double thresholdMeters,
  }) {
    return distanceBetween(lat1, lng1, lat2, lng2) < thresholdMeters;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Approximate conversion of latitude difference to meters.
  static double _latitudeToMeters(double dLat) {
    return dLat * 111320.0; // ~111.32 km per degree latitude
  }

  /// Approximate conversion of longitude difference to meters at a given
  /// [latitude] (accounts for convergence of meridians).
  static double _longitudeToMeters(double dLng, double latitude) {
    return dLng * 111320.0 * math.cos(latitude * _degToRad);
  }
}
