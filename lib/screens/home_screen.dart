import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../services/location_service.dart';
import '../services/background_service.dart';

import 'driver_profile_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  const HomeScreen({super.key, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool trackingStarted = false;

  @override
  void initState() {
    super.initState();
    _loadTrackingState();
  }

  Future<void> _loadTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    trackingStarted = prefs.getBool("tracking_running") ?? false;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setTrackingState(bool state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("tracking_running", state);
    trackingStarted = state;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("driver_username");
    await _setTrackingState(false);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Driver Dashboard - ${widget.username}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: "Edit Profile",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ProfileScreen(username: widget.username),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: _logout,
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🚚 START TRACKING
            ElevatedButton(
              onPressed: () async {
                if (!trackingStarted) {
                  await initializeService(widget.username);
                  await _setTrackingState(true);

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Tracking started")),
                  );
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Tracking already running")),
                  );
                }
              },
              child: const Text("Start Tracking"),
            ),
            const SizedBox(height: 20),

            // 🛑 STOP TRACKING
            ElevatedButton(
              onPressed: () async {
                FlutterBackgroundService().invoke("stopService");
                await _setTrackingState(false);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Tracking stopped")),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Stop Tracking"),
            ),
            const SizedBox(height: 20),

            // 📍 ONE-TIME LOCATION
            ElevatedButton(
              onPressed: () {
                LocationService.sendCurrentLocation(widget.username);
              },
              child: const Text("Send Current Location Once"),
            ),
            const SizedBox(height: 20),

            // 📅 SCHEDULES
            ElevatedButton(
              onPressed: () {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Today's schedule coming soon")),
                );
              },
              child: const Text("Today's Schedule"),
            ),
          ],
        ),
      ),
    );
  }
}
