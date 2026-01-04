import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/location_service.dart';
import '../services/native_location_service.dart';
import '../services/location_polling_service.dart';
import '../services/permission_helper.dart';

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
  bool _isLoading = true;
  bool _isTrackingStatus = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    try {
      await _loadTrackingState();
      
      // Check if tracking was previously enabled and permissions are granted
      if (trackingStarted) {
        final locationPermission = await Permission.location.status;
        final locationAlwaysPermission = await Permission.locationAlways.status;
        
        if (locationPermission.isGranted && locationAlwaysPermission.isGranted) {
          // Start polling service if tracking was previously enabled
          LocationPollingService.startPolling(widget.username);
          setState(() {
            _isTrackingStatus = true;
          });
        } else {
          // Reset tracking state if permissions are not granted
          await _setTrackingState(false);
          setState(() {
            _isTrackingStatus = false;
          });
        }
      }
    } catch (e) {
      print('Error initializing screen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTrackingState() async {
    final prefs = await SharedPreferences.getInstance();
    trackingStarted = prefs.getBool("tracking_running") ?? false;
  }

  Future<void> _setTrackingState(bool state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("tracking_running", state);
    trackingStarted = state;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _requestPermissions() async {
    final granted = await PermissionHelper.requestLocationPermissionWithDialog(context);
    if (granted) {
      print("All location permissions granted");
    } else {
      print("Location permissions not granted");
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("driver_username");
    await _setTrackingState(false);

    // Stop native tracking service
    await NativeLocationService.stopTracking();
    LocationPollingService.stopPolling();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Driver Dashboard - ${widget.username}"),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initializing...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Driver Dashboard - ${widget.username}", 
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 4,
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.green,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Welcome, ${widget.username}",
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Ready to start tracking",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Ensure location services are enabled to maintain accurate tracking.",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tracking Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isTrackingStatus ? Colors.green[50] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isTrackingStatus ? Colors.green : Colors.grey,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isTrackingStatus ? Colors.green[100] : Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: _isTrackingStatus ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Tracking Status",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isTrackingStatus ? Colors.green[800] : Colors.grey[700],
                            ),
                          ),
                          Text(
                            _isTrackingStatus ? "Active - Location tracking enabled" : "Inactive - Location tracking disabled",
                            style: TextStyle(
                              fontSize: 14,
                              color: _isTrackingStatus ? Colors.green[600] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isTrackingStatus ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isTrackingStatus ? "ON" : "OFF",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              const Text(
                "Quick Actions",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              // Grid of action buttons
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildActionCard(
                    icon: Icons.play_arrow,
                    title: "Start Tracking",
                    subtitle: "Begin location tracking",
                    color: _isTrackingStatus ? Colors.grey : Colors.green,
                    onPressed: () async {
                      if (!_isTrackingStatus) {
                        // Request permissions before starting tracking
                        await _requestPermissions();
                        
                        // Check if permissions are granted before starting service
                        final locationPermission = await Permission.location.status;
                        final locationAlwaysPermission = await Permission.locationAlways.status;
                        
                        if (locationPermission.isGranted && locationAlwaysPermission.isGranted) {
                          // Use native service instead of Flutter background service
                          final result = await NativeLocationService.startTracking(widget.username);
                          
                          if (result != null) {
                            await _setTrackingState(true);
                            
                            // Start polling for location updates from native service
                            LocationPollingService.startPolling(widget.username);
                            
                            setState(() {
                              _isTrackingStatus = true;
                            });

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Tracking started")),
                            );
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Failed to start tracking")),
                            );
                          }
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Location permissions are required for tracking")),
                          );
                        }
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Tracking already running")),
                        );
                      }
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.stop,
                    title: "Stop Tracking",
                    subtitle: "End location tracking",
                    color: Colors.red,
                    onPressed: () async {
                      // Stop native tracking service
                      await NativeLocationService.stopTracking();
                      LocationPollingService.stopPolling();
                      await _setTrackingState(false);
                      
                      setState(() {
                        _isTrackingStatus = false;
                      });

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Tracking stopped")),
                      );
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.my_location,
                    title: "Send Location",
                    subtitle: "Update current location",
                    color: Colors.blue,
                    onPressed: () {
                      LocationService.sendCurrentLocation(widget.username);
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.schedule,
                    title: "Schedule",
                    subtitle: "View today's schedule",
                    color: Colors.orange,
                    onPressed: () {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Today's schedule coming soon")),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Info Cards
              const Text(
                "Information",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.battery_charging_full,
                      title: "Battery",
                      value: "Optimized",
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.location_on,
                      title: "Accuracy",
                      value: "High",
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    // Ensure services are stopped when the screen is disposed
    if (!trackingStarted) {
      LocationPollingService.stopPolling();
    }
  }
}