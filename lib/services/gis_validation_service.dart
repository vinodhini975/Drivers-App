import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/route_point_model.dart';
import '../utils/geo_utils.dart';

class GISValidationResult {
  final bool isInsideWard;
  final bool isInsideRouteBuffer;
  final double routeDeviationMeters;

  GISValidationResult({
    required this.isInsideWard,
    required this.isInsideRouteBuffer,
    required this.routeDeviationMeters,
  });
}

class GISValidationService {
  Future<GISValidationResult> validatePoint({
    required LatLng point,
    String? wardId,
    String? routeId,
  }) async {
    // In a production app, we would fetch polygons from Firestore or a local cache
    // For now, we use a basic Point-in-Polygon stub or treat it as always inside 
    // to maintain non-blocking app flow.
    
    // logic to fetch ward polygon or route corridor
    
    return GISValidationResult(
      isInsideWard: true, // Placeholder logic
      isInsideRouteBuffer: true, // Placeholder logic
      routeDeviationMeters: 0.0,
    );
  }

  bool isPointInsideWard({required LatLng point, required List<LatLng> polygon}) {
    return GeoUtils.isPointInPolygon(point, polygon);
  }

  bool isInsideDepotGeofence({
    required LatLng point, 
    required LatLng depotCenter, 
    double radiusMeters = 50.0
  }) {
    final distance = GeoUtils.calculateHaversineDistance(point, depotCenter);
    return distance <= radiusMeters;
  }

  double calculateRouteAdherenceScore(List<RoutePointModel> points) {
    if (points.isEmpty) return 100.0;
    
    // Percentage of points inside the route corridor buffer
    int compliantCount = points.where((p) => p.isInsideRouteBuffer).length;
    double score = (compliantCount / points.length) * 100.0;
    
    // 💡 Add penalty for points outside assigned ward
    int outsideWardCount = points.where((p) => !p.isInsideWard).length;
    if (outsideWardCount > 0) {
      score -= (outsideWardCount / points.length) * 10.0; // max 10% penalty
    }
    
    return score.clamp(0.0, 100.0);
  }
}
