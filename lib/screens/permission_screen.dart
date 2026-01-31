import 'package:flutter/material.dart';
import '../services/permission_helper.dart';
import '../models/driver_model.dart';
import 'home_screen.dart';

class PermissionScreen extends StatefulWidget {
  final DriverModel driver;
  const PermissionScreen({super.key, required this.driver});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with WidgetsBindingObserver {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndProceed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndProceed();
    }
  }

  Future<void> _checkAndProceed() async {
    setState(() => _isChecking = true);
    final hasAccess = await PermissionHelper.hasAllPermissions();
    
    if (hasAccess && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(driver: widget.driver)),
      );
    } else {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, size: 100, color: Colors.red),
              const SizedBox(height: 30),
              const Text(
                'Location Mandatory',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              const Text(
                'BBMP tracking requires "Allow all the time" location access to work correctly. You cannot proceed without this.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              if (_isChecking)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () => PermissionHelper.requestAllPermissions(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text('GRANT PERMISSION', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
