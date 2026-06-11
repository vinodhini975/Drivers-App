import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeoUtils {
  static double calculateHaversineDistance(LatLng p1, LatLng p2) {
    const double radius = 6371000; // Earth's radius in meters
    double dLat = (p2.latitude - p1.latitude) * pi / 180;
    double dLng = (p2.longitude - p1.longitude) * pi / 180;
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(p1.latitude * pi / 180) * cos(p2.latitude * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return radius * c;
  }

  static bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        inside = !inside;
      }
    }
    return inside;
  }

  static double distanceToNearestRouteSegment(LatLng point, List<LatLng> polyline) {
    if (polyline.length < 2) return 0.0;
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      double dist = _distanceToSegment(point, polyline[i], polyline[i+1]);
      if (dist < minDistance) minDistance = dist;
    }
    return minDistance;
  }

  static double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    double l2 = pow(a.latitude - b.latitude, 2).toDouble() + pow(a.longitude - b.longitude, 2).toDouble();
    if (l2 == 0) return calculateHaversineDistance(p, a);
    double t = ((p.latitude - a.latitude) * (b.latitude - a.latitude) + (p.longitude - a.longitude) * (b.longitude - a.longitude)) / l2;
    t = max(0, min(1, t));
    LatLng projection = LatLng(a.latitude + t * (b.latitude - a.latitude), a.longitude + t * (b.longitude - a.longitude));
    return calculateHaversineDistance(p, projection);
  }
}
