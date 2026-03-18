import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../models/driver_model.dart';

class AuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _isGovLoggedInKey = 'is_gov_logged_in';
  static const String _userMobileKey = 'user_mobile';
  static const String _emailKey = 'email'; // For backward compatibility/consistency with stashed work
  static const String _driverIdKey = 'driverId'; // For backward compatibility/consistency with stashed work

  /* ================= OTP MECHANISM ================= */
  Future<void> requestOtp(String mobile) async {
    // In a real app, this would call Firebase Auth verifyPhoneNumber
    // For now, we simulate sending an OTP
    debugPrint('OTP requested for $mobile');
  }

  Future<bool> verifyOtp(String otp) async {
    // Simulating OTP verification - any 6 digit number works for now
    return RegExp(r'^[0-9]{6}$').hasMatch(otp);
  }

  Future<bool> checkDriverExists(String mobile) async {
    final driver = await getDriverByMobile(mobile);
    return driver != null;
  }

  /* ================= DRIVER SESSION ================= */
  Future<void> saveDriverSession(String mobile, {String? email, String? driverId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_userMobileKey, mobile);
    await prefs.setBool(_isGovLoggedInKey, false);
    
    if (email != null) await prefs.setString(_emailKey, email);
    if (driverId != null) await prefs.setString(_driverIdKey, driverId);
  }

  Future<bool> isDriverLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  /* ================= GOVERNMENT SESSION ================= */
  Future<void> saveGovSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isGovLoggedInKey, true);
    await prefs.setBool(_isLoggedInKey, false);
  }

  Future<bool> isGovLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isGovLoggedInKey) ?? false;
  }

  /* ================= COMMON LOGIC ================= */
  Future<String?> getCurrentDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userMobileKey) ?? prefs.getString(_driverIdKey);
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
    } catch (e) {
      print('Auth sign out error: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /* ================= DATA FETCHING ================= */
  Future<DriverModel?> getDriverByMobile(String mobile) async {
    final query = await _firestore
        .collection('drivers')
        .where('phoneNumber', isEqualTo: mobile)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return DriverModel.fromFirestore(query.docs.first);
  }

  Future<DriverModel?> getCurrentDriver() async {
    final mobileOrDriverId = await getCurrentDriverId();
    if (mobileOrDriverId == null) return null;
    
    // Try by mobile first (main's logic)
    var driver = await getDriverByMobile(mobileOrDriverId);
    if (driver != null) return driver;
    
    // Try by document ID (stashed logic used driverId as docId)
    final driverDoc = await _firestore.collection('drivers').doc(mobileOrDriverId).get();
    if (driverDoc.exists) {
      return DriverModel.fromFirestore(driverDoc);
    }
    
    return null;
  }

  /* ================= STASHED FEATURES: GOOGLE SIGN IN & REGISTRATION ================= */

  /// Sign in with driver ID (Email/Password)
  Future<Map<String, dynamic>> signInWithDriverId({
    required String driverId,
    required String password,
  }) async {
    try {
      // First, check if driver exists in Firestore
      final driverDoc = await _firestore.collection('drivers').doc(driverId).get();
      
      if (!driverDoc.exists) {
        return {
          'success': false,
          'message': 'Driver ID not found in database',
        };
      }
      
      final driverData = driverDoc.data();
      final email = driverData?['email'] as String?;
      final phoneNumber = driverData?['phoneNumber'] as String?;
      
      if (email == null || email.isEmpty) {
        return {
          'success': false,
          'message': 'Driver email not configured. Contact admin.',
        };
      }
      if (phoneNumber == null || phoneNumber.isEmpty) {
        return {
          'success': false,
          'message': 'Driver phone number not configured. Contact admin.',
        };
      }
      
      // Sign in with Firebase Auth
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        return {
          'success': false,
          'message': 'Authentication failed',
        };
      }

      // Update last login time (only if user is authenticated)
      try {
        await _firestore.collection('drivers').doc(driverId).update({
          'lastLogin': FieldValue.serverTimestamp(),
          'status': 'active',
        });
      } catch (e) {
        // Log but don't fail if update fails due to permissions
        print('Warning: Could not update last login: $e');
      }

      // Save to local storage using the main branch's session logic
      final driver = DriverModel.fromFirestore(driverDoc);
      await saveDriverSession(phoneNumber, email: email, driverId: driverId);
      
      return {
        'success': true,
        'message': 'Login successful',
        'driver': driver,
      };
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed';
      
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found with this email. Contact admin to create your account.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          message = 'Invalid email format in driver profile. Contact admin.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled. Contact admin.';
          break;
        case 'too-many-requests':
          message = 'Too many login attempts. Please wait and try again later.';
          break;
        case 'invalid-credential':
          message = 'Invalid credentials. Please check your password.';
          break;
        default:
          message = 'Login failed: ${e.message}';
      }
      
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      print('Login error: $e');
      return {
        'success': false,
        'message': 'Connection error. Please check your internet and try again.',
      };
    }
  }

  /// Register new driver
  Future<Map<String, dynamic>> registerDriver({
    required String driverId,
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required String vehicleId,
    required String licenseNumber,
    required String zone,
    required String ward,
  }) async {
    try {
      // Check if driver ID already exists
      final existingDriver = await _firestore.collection('drivers').doc(driverId).get();
      if (existingDriver.exists) {
        return {
          'success': false,
          'message': 'Driver ID already exists. Please choose a different ID.',
        };
      }

      // Create Firebase Auth user first
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        return {
          'success': false,
          'message': 'Failed to create authentication account',
        };
      }

      // Create driver document in Firestore
      await _firestore.collection('drivers').doc(driverId).set({
        'driverId': driverId,
        'name': name,
        'email': email,
        'phoneNumber': phoneNumber,
        'vehicleId': vehicleId,
        'licenseNumber': licenseNumber,
        'zone': zone,
        'ward': ward,
        'isActive': true,
        'status': 'active',
        'isOnDuty': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // Save to local storage using the main branch's session logic
      final driverDoc = await _firestore.collection('drivers').doc(driverId).get();
      final driver = DriverModel.fromFirestore(driverDoc);
      await saveDriverSession(phoneNumber, email: email, driverId: driverId);
      
      return {
        'success': true,
        'message': 'Registration successful! Welcome aboard!',
        'driver': driver,
      };
    } on FirebaseAuthException catch (e) {
      String message = 'Registration failed';
      
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered. Please login instead.';
          break;
        case 'invalid-email':
          message = 'Invalid email address format.';
          break;
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        case 'operation-not-allowed':
          message = 'Registration is currently disabled. Contact support.';
          break;
        default:
          message = 'Registration failed: ${e.message}';
      }
      
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      print('Registration error: $e');
      // Clean up auth user if Firestore creation failed
      try {
        await _auth.currentUser?.delete();
      } catch (deleteError) {
        print('Failed to cleanup auth user: $deleteError');
      }
      
      return {
        'success': false,
        'message': 'Registration error: $e',
      };
    }
  }

  /// Sign in with Google
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User canceled the sign-in
        return {
          'success': false,
          'message': 'Google sign-in was cancelled',
        };
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user == null) {
        return {
          'success': false,
          'message': 'Failed to sign in with Google',
        };
      }

      final email = userCredential.user!.email!;
      final name = userCredential.user!.displayName ?? 'Driver';
      
      // Check if driver already exists in Firestore
      final driversQuery = await _firestore
          .collection('drivers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (driversQuery.docs.isEmpty) {
        // New user - need to create driver profile
        // Generate a driver ID based on email
        final driverId = _generateDriverId(email);
        
        return {
          'success': false,
          'isNewUser': true,
          'message': 'Please complete your driver profile',
          'email': email,
          'name': name,
          'suggestedDriverId': driverId,
        };
      }
      
      // Existing user - log them in
      final driverDoc = driversQuery.docs.first;
      final driver = DriverModel.fromFirestore(driverDoc);
      
      // Update last login
      try {
        await _firestore.collection('drivers').doc(driver.id).update({
          'lastLogin': FieldValue.serverTimestamp(),
          'status': 'active',
        });
      } catch (e) {
        debugPrint('Warning: Could not update last login: $e');
      }
      
      // Save to local storage using the main branch's session logic
      await saveDriverSession(driver.phoneNumber, email: email, driverId: driver.id);
      
      return {
        'success': true,
        'message': 'Signed in successfully',
        'driver': driver,
      };
    } catch (e) {
      print('Google sign-in error: $e');
      return {
        'success': false,
        'message': 'Google sign-in failed: $e',
      };
    }
  }

  /// Complete Google Sign-In registration
  Future<Map<String, dynamic>> completeGoogleSignUp({
    required String driverId,
    required String phoneNumber,
    required String vehicleId,
    required String licenseNumber,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        return {
          'success': false,
          'message': 'No authenticated user found. Please sign in with Google again.',
        };
      }
      
      final email = user.email!;
      final name = user.displayName ?? 'Driver';
      
      // Check if driver ID already exists
      final existingDriver = await _firestore.collection('drivers').doc(driverId).get();
      if (existingDriver.exists) {
        return {
          'success': false,
          'message': 'Driver ID already exists. Please choose a different ID.',
        };
      }
      
      // Create driver document
      await _firestore.collection('drivers').doc(driverId).set({
        'driverId': driverId,
        'name': name,
        'email': email,
        'phoneNumber': phoneNumber,
        'vehicleId': vehicleId,
        'licenseNumber': licenseNumber,
        'zone': 'Default Zone', // Default values for now
        'ward': 'Default Ward', // Default values for now
        'isActive': true,
        'status': 'active',
        'isOnDuty': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });
      
      // Save to local storage using the main branch's session logic
      final driverDoc = await _firestore.collection('drivers').doc(driverId).get();
      final driver = DriverModel.fromFirestore(driverDoc);
      await saveDriverSession(phoneNumber, email: email, driverId: driverId);
      
      return {
        'success': true,
        'message': 'Registration completed successfully!',
        'driver': driver,
      };
    } catch (e) {
      print('Complete registration error: $e');
      return {
        'success': false,
        'message': 'Failed to complete registration: $e',
      };
    }
  }

  /// Generate a driver ID from email
  String _generateDriverId(String email) {
    // Extract first part of email and generate ID
    final username = email.split('@')[0].toUpperCase();
    final prefix = username.length >= 3 ? username.substring(0, 3) : 'DRV';
    final randomNum = DateTime.now().millisecondsSinceEpoch % 1000;
    return '$prefix${randomNum.toString().padLeft(3, '0')}';
  }
}
