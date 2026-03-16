import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import 'location_permission_screen.dart';
import 'gov_map_screen.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'google_signup_complete_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _driverIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _govPasswordController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _isDriverRole = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _driverIdController.dispose();
    _passwordController.dispose();
    _govPasswordController.dispose();
    super.dispose();
  }

  /* ================= DRIVER LOGIN ================= */

  Future<void> _loginDriver() async {
    final driverId = _driverIdController.text.trim().toUpperCase();
    final password = _passwordController.text;

    if (driverId.isEmpty || password.isEmpty) {
      _showMessage('Please enter both Driver ID and password', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signInWithDriverId(
        driverId: driverId,
        password: password,
      );

      if (result['success']) {
        _showMessage('Welcome ${result['driver'].name}!');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: result['driver'] as DriverModel)),
        );
      } else {
        _showMessage(result['message'] ?? 'Login failed', isError: true);
      }
    } catch (e) {
      _showMessage('Login error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (!mounted) return;

      if (result['success']) {
        _showMessage(result['message']);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: result['driver'] as DriverModel)),
        );
      } else if (result['isNewUser'] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoogleSignupCompleteScreen(
              email: result['email'],
              name: result['name'],
              suggestedDriverId: result['suggestedDriverId'],
            ),
          ),
        );
      } else {
        _showMessage(result['message'], isError: true);
      }
    } catch (e) {
      _showMessage('Google sign-in failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ================= GOVT LOGIN ================= */

  void _loginGovernment() async {
    if (_govPasswordController.text == 'admin') {
      await _authService.saveGovSession();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GovMapScreen()));
    } else {
      _showMessage('Invalid password', isError: true);
    }
  }

  /* ================= UI COMPONENTS ================= */

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 15))),
          ],
        ),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = _isDriverRole ? Colors.green[700]! : Colors.blue[900]!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.local_shipping, size: 80, color: mainColor),
                const SizedBox(height: 15),
                Text(
                  _isDriverRole ? 'BBMP VEHICLE TRACKING' : 'GOVERNMENT ACCESS',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: mainColor),
                ),
                const SizedBox(height: 40),

                // Role Selector
                ToggleButtons(
                  isSelected: [_isDriverRole, !_isDriverRole],
                  onPressed: (index) => setState(() => _isDriverRole = index == 0),
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: Colors.white,
                  fillColor: mainColor,
                  constraints: BoxConstraints(minWidth: (MediaQuery.of(context).size.width - 60) / 2, minHeight: 60),
                  children: const [
                    Text('DRIVER', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('GOVERNMENT', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 40),

                if (_isDriverRole) _driverUI(mainColor) else _govUI(mainColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _driverUI(Color color) {
    return Column(
      children: [
        _buildTextField(_driverIdController, 'DRIVER ID', Icons.badge, hintText: 'e.g. DRV001'),
        const SizedBox(height: 16),
        _buildTextField(_passwordController, 'PASSWORD', Icons.lock, isPassword: true),
        const SizedBox(height: 30),
        _bigButton('DRIVER LOGIN', _loginDriver, color),
        const SizedBox(height: 16),
        
        OutlinedButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            side: BorderSide(color: color, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('New User? Register Here', style: TextStyle(fontSize: 16, color: color, fontWeight: FontWeight.bold)),
        ),
        
        const SizedBox(height: 25),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey[400])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('OR', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold))),
            Expanded(child: Divider(color: Colors.grey[400])),
          ],
        ),
        const SizedBox(height: 25),

        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loginWithGoogle,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            side: BorderSide(color: Colors.grey[300]!, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
          ),
          icon: Image.network(
            'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
            height: 24,
            width: 24,
            errorBuilder: (context, error, stackTrace) => Icon(Icons.g_mobiledata, color: Colors.red[700], size: 28),
          ),
          label: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue with Google', style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _govUI(Color color) {
    return Column(
      children: [
        _buildTextField(_govPasswordController, 'GOVERNMENT PASSWORD', Icons.admin_panel_settings, isPassword: true),
        const SizedBox(height: 30),
        _bigButton('GOVERNMENT LOGIN', _loginGovernment, color),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, String? hintText}) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword 
          ? IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off), 
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ) 
          : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _bigButton(String text, VoidCallback onTap, Color color) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color, 
        minimumSize: const Size(double.infinity, 64), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
}
}
