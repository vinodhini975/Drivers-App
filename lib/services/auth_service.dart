import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/driver_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _driverIdKey = 'driver_id';
  static const String _deviceIdKey = 'device_id';
  static const String _isLoggedInKey = 'is_logged_in';

  // ==============================
  // Password hash (Firestore only)
  // ==============================
  String _computeHash(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  // ==============================
  // Device ID (Stable & Correct)
  // ==============================
  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id; // stable identifier
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'ios_fallback';
      }
    } catch (e) {
      debugPrint('Device ID error: $e');
    }
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ==============================
  // Driver Login / Auto-Register
  // ==============================
  Future<Map<String, dynamic>> signInWithDriverId({
    required String driverId,
    required String password,
  }) async {
    try {
      final deviceId = await getDeviceId();
      final cleanId = driverId.trim();
      final email = '${cleanId.toLowerCase()}@driverapp.com';
      final passwordHash = _computeHash(password);

      // STEP 1: Search for existing driver document by driverId field
      final querySnapshot = await _firestore
          .collection('drivers')
          .where('driverId', isEqualTo: cleanId)
          .limit(1)
          .get();
      
      final existingDoc = querySnapshot.docs.isNotEmpty ? querySnapshot.docs.first : null;

      // ==========================
      // FIRST-TIME DRIVER
      // ==========================
      if (existingDoc == null) {
        debugPrint('New driver detected. Registering: $cleanId');

        UserCredential credential;
        try {
          credential = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            credential = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
          } else {
            rethrow;
          }
        }

        // 🔒 Ensure auth state is propagated
        await _auth.idTokenChanges().first;
        final user = _auth.currentUser;
        if (user == null) {
          return {
            'success': false,
            'message': 'Authentication session not ready. Try again.'
          };
        }

        // Use UID as document ID
        await _firestore.collection('drivers').doc(user.uid).set({
          'driverId': cleanId,
          'email': email,
          'name': 'Driver $cleanId',
          'status': 'active',
          'deviceId': deviceId,
          'passwordHash': passwordHash,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'isOnDuty': false,
          'vehicleId': 'V-${cleanId.toUpperCase()}',
          'zone': 'Default',
          'ward': 'Default',
        });
      } 
      // ==========================
      // RETURNING DRIVER
      // ==========================
      else {
        final data = existingDoc.data();
        final storedDeviceId = data['deviceId'] as String?;
        final storedHash = data['passwordHash'] as String?;

        if (storedDeviceId != deviceId) {
          return {
            'success': false,
            'message': 'This ID is registered on another device.'
          };
        }

        if (storedHash != passwordHash) {
          return {'success': false, 'message': 'Incorrect password.'};
        }

        await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        await _auth.idTokenChanges().first;
        final user = _auth.currentUser;
        if (user == null) {
          return {
            'success': false,
            'message': 'Authentication session lost.'
          };
        }

        // Use UID as document ID
        await _firestore.collection('drivers').doc(user.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
          'status': 'active',
        });
      }

      // Finalize session locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_driverIdKey, cleanId);
      await prefs.setString(_deviceIdKey, deviceId);
      await prefs.setBool(_isLoggedInKey, true);

      // Re-fetch the updated doc using UID
      final updatedDoc = await _firestore.collection('drivers').doc(_auth.currentUser!.uid).get();

      return {
        'success': true,
        'message': 'Login Successful',
        'driver': DriverModel.fromFirestore(updatedDoc),
      };
    } 
    on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: ${e.code}');
      if (e.code == 'network-request-failed') {
        return {
          'success': false,
          'message': 'Network error. Please check your internet.'
        };
      }
      return {
        'success': false,
        'message': e.message ?? 'Authentication failed'
      };
    } catch (e) {
      debugPrint('Login Error: $e');
      return {
        'success': false,
        'message': 'An error occurred during login.'
      };
    }
  }

  // ==============================
  // Sign out
  // ==============================
  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('drivers').doc(user.uid).update({
          'status': 'inactive',
        });
      }

      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Signout Error: $e');
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<DriverModel?> getCurrentDriver() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('drivers').doc(user.uid).get();
      return doc.exists ? DriverModel.fromFirestore(doc) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> validateSession() async {
    try {
      final user = _auth.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(_deviceIdKey);
      if (user == null || deviceId == null) return false;

      final doc = await _firestore.collection('drivers').doc(user.uid).get();
      return doc.exists && doc.data()?['deviceId'] == deviceId;
    } catch (_) {
      return false;
    }
  }
}
