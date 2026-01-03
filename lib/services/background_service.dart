import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_service.dart';


@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  String username = "";
  bool serviceActive = true;

  // Restore username if service restarts
  final prefs = await SharedPreferences.getInstance();
  username = prefs.getString("driver_username") ?? "";

  // Receive username dynamically
  service.on("setUser").listen((event) {
    username = event?["username"] ?? username;
    debugPrint("📌 Background tracking for: $username");
  });

  // Stop service safely
  service.on("stopService").listen((event) {
    serviceActive = false;
    service.stopSelf();
  });

  // Foreground service (MANDATORY)
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Driver Tracking Active",
      content: "Updating location…",
    );
  }

  // Periodic task (SAFE)
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (!serviceActive) {
      timer.cancel();
      return;
    }

    if (username.isEmpty) return;

    final success = await LocationService.sendCurrentLocation(username);

    // Update notification
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Driver Tracking Active",
        content: success
            ? "Location updated successfully"
            : "Waiting for location permission",
      );
    }
  });
}

/// 🔹 Start background service safely
Future<void> initializeService(String username) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString("driver_username", username);

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'driver_tracking_channel',
      initialNotificationTitle: 'Driver Tracking Active',
      initialNotificationContent: 'Initializing location tracking…',
    ),
    iosConfiguration: IosConfiguration(),
  );

  await service.startService();

  service.invoke("setUser", {"username": username});
}
