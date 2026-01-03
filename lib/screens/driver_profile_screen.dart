import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String username;
  const ProfileScreen({super.key, required this.username});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _truckController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSaving = false;

  Future<void> _saveProfile() async {
    if (_nameController.text.isEmpty ||
        _truckController.text.isEmpty ||
        _phoneController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Fill all fields")));
      return;
    }

    setState(() => _isSaving = true);

    // ---- save to Firestore ----
    await FirebaseFirestore.instance
        .collection("drivers")
        .doc(widget.username)
        .set({
          "name": _nameController.text.trim(),
          "truckNumber": _truckController.text.trim(),
          "phoneNumber": _phoneController.text.trim(),
          "profileCompleted": true,
        }, SetOptions(merge: true));

    setState(() => _isSaving = false);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(username: widget.username),
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("driver_username");

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
        title: const Text("Driver Profile"),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Driver Name"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _truckController,
              decoration: const InputDecoration(labelText: "Truck Number"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: "Phone Number"),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),

            _isSaving
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _saveProfile,
                    child: const Text("Save Profile"),
                  ),
          ],
        ),
      ),
    );
  }
}
