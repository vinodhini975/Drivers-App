enum RoutePointType {
  checkpoint,
  stop,
}

extension RoutePointTypeExtension on RoutePointType {
  String toFirestoreString() {
    return name;
  }

  static RoutePointType fromFirestoreString(String value) {
    return RoutePointType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RoutePointType.checkpoint,
    );
  }
}
