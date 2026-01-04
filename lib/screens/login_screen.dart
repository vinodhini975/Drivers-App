import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/permission_helper.dart';
import 'home_screen.dart';
import 'driver_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  
  // Toggle between username/password and email/password
  bool _useEmailAuth = true;
  
  bool _isLoading = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _authenticateUser() async {
    if (_useEmailAuth) {
      if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter email and password")),
        );
        return;
      }
    } else {
      if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter username and password")),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      String email = _useEmailAuth 
          ? _emailController.text.trim()
          : "${_usernameController.text.trim()}@driverapp.com";
          
      UserCredential userCredential;
      
      if (_isSignUp) {
        // Sign up with Firebase
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );
      } else {
        // Sign in with Firebase
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );
      }

      await _handleAuthSuccess(userCredential.user);

    } on FirebaseAuthException catch (e) {
      print("Firebase Auth Error: ${e.code} - ${e.message}");
      if (e.message != null && e.message!.contains("API key not valid")) {
        _showErrorDialog(
          "Configuration Error", 
          "The API key in google-services.json is invalid or restricted.\n\n"
          "Possible solutions:\n"
          "1. Download the latest google-services.json from Firebase Console.\n"
          "2. Check API Key restrictions in Google Cloud Console.\n"
          "3. Ensure the package name 'com.example.driver_app' matches exactly."
        );
      } else {
        _handleAuthError(e);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Authentication error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      
      if (googleUser == null) {
        // The user canceled the sign-in
        setState(() => _isLoading = false);
        return;
      }
      
      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      // Once signed in, return the UserCredential
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      await _handleAuthSuccess(userCredential.user);
      
    } on PlatformException catch (e) {
      print("Google Sign In Platform Exception: ${e.code} - ${e.message} - ${e.details}");
      
      // Check for common configuration errors
      if (e.code == 'sign_in_failed' || e.toString().contains("ApiException: 10")) {
        _showErrorDialog(
          "Google Sign In Setup Error",
          "This error (Code 10) usually means the app is not properly configured in Firebase.\n\n"
          "Please check:\n"
          "1. SHA-1 Fingerprint: Ensure your debug keystore SHA-1 is added to Firebase Console.\n"
          "2. google-services.json: Ensure it is in android/app/ and matches package 'com.example.driver_app'.\n"
          "3. Support Email: Ensure a support email is set in Firebase Project Settings."
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Google Sign In failed: ${e.message}")),
          );
        }
      }
    } catch (e) {
      print("Google Sign In Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Google Sign In failed: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAuthSuccess(User? user) async {
    if (user == null) return;
    
    // Determine username
    String username;
    if (_useEmailAuth) {
      // Try to extract username from email or name
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        username = user.displayName!;
      } else {
        username = user.email!.split('@')[0];
      }
    } else {
      username = _usernameController.text.trim();
    }
    
    // Save username locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("driver_username", username);

    // Check if driver profile exists
    final doc = await FirebaseFirestore.instance
        .collection("drivers")
        .doc(username) 
        .get();

    if (!mounted) return;
    
    if (doc.exists && (doc.data()?["profileCompleted"] == true)) {
      // Profile exists -> go to home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              HomeScreen(username: username),
        ),
      );
    } else {
      // No profile -> go to profile screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ProfileScreen(username: username),
        ),
      );
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    String message = "Authentication failed";
    if (e.code == 'weak-password') {
      message = "Password is too weak";
    } else if (e.code == 'email-already-in-use') {
      message = "Account already exists";
    } else if (e.code == 'user-not-found') {
      message = "No account found";
    } else if (e.code == 'wrong-password') {
      message = "Incorrect password";
    } else if (e.code == 'invalid-email') {
      message = "Invalid email address";
    } else {
      message = e.message ?? "Authentication failed";
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? "Create Account" : "Driver Login"),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Icon(
                Icons.drive_eta,
                size: 80,
                color: Colors.green,
              ),
              const SizedBox(height: 20),
              Text(
                _isSignUp ? "Create Your Account" : "Driver Tracking App",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isSignUp 
                  ? "Enter your details to create an account" 
                  : "Sign in to start tracking",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 30),
              
              // Auth Type Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Email'),
                    selected: _useEmailAuth,
                    onSelected: (bool selected) {
                      setState(() {
                        _useEmailAuth = true;
                      });
                    },
                    selectedColor: Colors.green[100],
                    checkmarkColor: Colors.green,
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('Username'),
                    selected: !_useEmailAuth,
                    onSelected: (bool selected) {
                      setState(() {
                        _useEmailAuth = false;
                      });
                    },
                    selectedColor: Colors.green[100],
                    checkmarkColor: Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_useEmailAuth)
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: "Email",
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                )
              else
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: "Username",
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  enabled: !_isLoading,
                ),
              
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 30),
              
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _authenticateUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isSignUp ? "Create Account" : "Login",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    
                    // Google Sign In Button
                    OutlinedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login, color: Colors.red),
                      label: const Text("Sign in with Google"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSignUp = !_isSignUp;
                    _usernameController.clear();
                    _passwordController.clear();
                    _emailController.clear();
                  });
                },
                child: Text(
                  _isSignUp 
                    ? "Already have an account? Sign In" 
                    : "Don't have an account? Sign Up",
                  style: const TextStyle(
                    color: Colors.green,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  await PermissionHelper.requestLocationPermissionWithDialog(context);
                },
                child: const Text(
                  "Grant Location Permissions",
                  style: TextStyle(
                    color: Colors.green,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}