import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  /// Sends driver's current location to Firestore.
  /// Safe for foreground & background execution.
  static Future<bool> sendCurrentLocation(String username) async {
    try {
      // -------------------------------
      // 1️⃣ Check if location service is ON
      // -------------------------------
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("❌ Location services are disabled");
        return false;
      }

      // -------------------------------
      // 2️⃣ Check permission status
      // -------------------------------
      LocationPermission permission = await Geolocator.checkPermission();

      // Request foreground permission ONLY if denied
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Hard stop conditions
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint("❌ Location permission denied");
        return false;
      }

      // NOTE:
      // LocationPermission.whileInUse  → OK (foreground)
      // LocationPermission.always     → OK (background)

      // -------------------------------
      // 3️⃣ Get current location (safe)
      // -------------------------------
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Changed from high to medium to save battery
        timeLimit: const Duration(seconds: 15),
      );

      debugPrint("📍 LocationService: Got position for $username: ${position.latitude}, ${position.longitude}");

      // -------------------------------
      // 4️⃣ Firestore reference
      // -------------------------------
      final docRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(username);

      final docSnap = await docRef.get();

      final bool hasCreatedAt =
          docSnap.exists && docSnap.data()!.containsKey('createdAt');

      // -------------------------------
      // 5️⃣ Save / update location
      // -------------------------------
      await docRef.set({
        'name': username,
        'lat': position.latitude,
        'lng': position.longitude,
        'isActive': true,
        'createdAt': hasCreatedAt
            ? docSnap['createdAt']
            : FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
        "📍 Location updated for $username: "
        "${position.latitude}, ${position.longitude}",
      );

      return true;
    } catch (e, stack) {
      debugPrint("❌ Location update failed: $e");
      debugPrintStack(stackTrace: stack);

      // -------------------------------
      // 6️⃣ Mark driver inactive safely
      // -------------------------------
      try {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(username)
            .set({
              'isActive': false,
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (_) {}
      return false;
    }
  }
}