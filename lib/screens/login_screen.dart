import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import 'home_screen.dart';
import 'gov_map_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _driverIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _govPasswordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isDriverRole = true; // Role toggle



  @override
  void dispose() {
    _driverIdController.dispose();
    _passwordController.dispose();
    _govPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loginDriver() async {
    final driverId = _driverIdController.text.trim();
    final password = _passwordController.text;

    if (driverId.isEmpty || password.isEmpty) {
      _showMessage('Please enter Driver ID and password', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithDriverId(driverId: driverId, password: password);
      if (!mounted) return;

      if (result['success']) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(driver: result['driver'] as DriverModel)));
      } else {
        _showMessage(result['message'], isError: true);
      }
    } catch (e) {
      _showMessage('Login failed: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loginGovernment() {
    // Navigate directly to map without password validation
    Navigator.push(context, MaterialPageRoute(builder: (context) => const GovMapScreen()));
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.local_shipping, size: 80, color: _isDriverRole ? Colors.green[700] : Colors.blue[900]),
                const SizedBox(height: 15),
                Text('Vehicle Tracking', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _isDriverRole ? Colors.green[700] : Colors.blue[900])),
                const SizedBox(height: 30),

                // Role Selector
                ToggleButtons(
                  isSelected: [_isDriverRole, !_isDriverRole],
                  onPressed: (index) => setState(() => _isDriverRole = index == 0),
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: Colors.white,
                  fillColor: _isDriverRole ? Colors.green[700] : Colors.blue[900],
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 30), child: Text('Driver')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 30), child: Text('Government')),
                  ],
                ),
                const SizedBox(height: 40),

                if (_isDriverRole) ...[
                  // DRIVER LOGIN UI
                  _buildTextField(_driverIdController, 'Driver ID', Icons.badge),
                  const SizedBox(height: 16),
                  _buildTextField(_passwordController, 'Password', Icons.lock, isPassword: true),
                  const SizedBox(height: 30),
                  _buildButton('Driver Login', _loginDriver, Colors.green[700]!),
                ] else ...[
                  // GOVT LOGIN UI
                  _buildTextField(_govPasswordController, 'Government Password', Icons.admin_panel_settings, isPassword: true),
                  const SizedBox(height: 30),
                  _buildButton('Government Login', _loginGovernment, Colors.blue[900]!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword ? IconButton(icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed, Color color) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
