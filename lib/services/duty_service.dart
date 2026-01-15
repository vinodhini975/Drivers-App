import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

/// Service to handle duty management for drivers
class DutyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Battery _battery = Battery();
  
  static const String _isDutyActiveKey = 'is_duty_active';
  static const String _dutyStartTimeKey = 'duty_start_time';

  /// Start duty for driver
  Future<Map<String, dynamic>> startDuty(String driverId) async {
    try {
      // Add authentication check before any Firestore operations
      final authService = AuthService();
      final currentDriver = await authService.getCurrentDriver();
      if (currentDriver?.driverId != driverId) {
        return {
          'success': false,
          'message': 'Unauthorized: Cannot start duty for another driver',
        };
      }
      
      final now = DateTime.now();
      final batteryLevel = await _battery.batteryLevel;
      
      // Update driver status
      await _firestore.collection('drivers').doc(driverId).update({
        'isOnDuty': true,
        'dutyStartTime': Timestamp.fromDate(now),
        'dutySession': {
          'startTime': Timestamp.fromDate(now),
          'isActive': true,
          'batteryAtStart': batteryLevel,
          'createdAt': FieldValue.serverTimestamp(),
        },
        'lastDutyUpdate': FieldValue.serverTimestamp(),
      });
      
      // Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isDutyActiveKey, true);
      await prefs.setInt(_dutyStartTimeKey, now.millisecondsSinceEpoch);
      
      // Log in debug mode
      if (kDebugMode) {
        debugPrint('Duty started for driver: $driverId at $now');
      }
      
      return {
        'success': true,
        'message': 'Duty started successfully',
        'startTime': now,
      };
      
    } catch (e) {
      // Log in debug mode
      if (kDebugMode) {
        debugPrint('Error starting duty: $e');
      }
      return {
        'success': false,
        'message': 'Failed to start duty',
      };
    }
  }

  /// End duty for driver
  Future<Map<String, dynamic>> endDuty(String driverId) async {
    try {
      // Add authentication check before any Firestore operations
      final authService = AuthService();
      final currentDriver = await authService.getCurrentDriver();
      if (currentDriver?.driverId != driverId) {
        return {
          'success': false,
          'message': 'Unauthorized: Cannot end duty for another driver',
        };
      }
      
      final now = DateTime.now();
      final batteryLevel = await _battery.batteryLevel;
      
      // Get current driver document to get duty session info
      final driverDoc = await _firestore.collection('drivers').doc(driverId).get();
      if (driverDoc.exists) {
        final dutySession = driverDoc.data()?['dutySession'];
        if (dutySession != null && dutySession['isActive'] == true) {
          final startTime = (dutySession['startTime'] as Timestamp).toDate();
          final durationMinutes = now.difference(startTime).inMinutes;
          
          // Update duty session
          await _firestore.collection('drivers').doc(driverId).update({
            'dutySession.endTime': Timestamp.fromDate(now),
            'dutySession.isActive': false,
            'dutySession.batteryAtEnd': batteryLevel,
            'dutySession.durationMinutes': durationMinutes,
            'dutySession.updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      
      // Update driver status
      await _firestore.collection('drivers').doc(driverId).update({
        'isOnDuty': false,
        'dutyStartTime': null,
        'status': 'inactive',
        'lastDutyUpdate': FieldValue.serverTimestamp(),
      });
      
      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isDutyActiveKey, false);
      await prefs.remove(_dutyStartTimeKey);
      
      // Log in debug mode
      if (kDebugMode) {
        debugPrint('Duty ended for driver: $driverId at $now');
      }
      
      return {
        'success': true,
        'message': 'Duty ended successfully',
        'endTime': now,
      };
      
    } catch (e) {
      // Log in debug mode
      if (kDebugMode) {
        debugPrint('Error ending duty: $e');
      }
      return {
        'success': false,
        'message': 'Failed to end duty',
      };
    }
  }

  /// Check if duty is active
  Future<bool> isDutyActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_isDutyActiveKey) ?? false;
    } catch (e) {
      // Log in debug mode
      if (kDebugMode) {
        print('Error checking duty status: $e');
      }
      return false;
    }
  }

  /// Get duty start time
  Future<DateTime?> getDutyStartTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_dutyStartTimeKey);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      // Log in debug mode
      if (kDebugMode) {
        print('Error getting duty start time: $e');
      }
      return null;
    }
  }

  /// Get current duty duration in minutes
  Future<int> getCurrentDutyDuration() async {
    final startTime = await getDutyStartTime();
    if (startTime == null) return 0;
    return DateTime.now().difference(startTime).inMinutes;
  }

  /// Check battery level and return status
  Future<Map<String, dynamic>> checkBatteryStatus() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      
      bool isLow = batteryLevel < 20;
      bool isCritical = batteryLevel < 10;
      bool isCharging = batteryState == BatteryState.charging;
      
      return {
        'level': batteryLevel,
        'state': batteryState.toString(),
        'isLow': isLow,
        'isCritical': isCritical,
        'isCharging': isCharging,
        'message': isCritical 
            ? '🔴 Critical battery! Please charge immediately.'
            : isLow 
                ? '⚠️ Low battery. Consider charging soon.'
                : '✅ Battery level is good.',
      };
    } catch (e) {
      // Log in debug mode
      if (kDebugMode) {
        print('Error checking battery: $e');
      }
      return {
        'level': 100,
        'state': 'unknown',
        'isLow': false,
        'isCritical': false,
        'isCharging': false,
        'message': 'Unable to check battery status',
      };
    }
  }

  /// Stream battery level changes
  Stream<int> get batteryLevelStream {
    return _battery.onBatteryStateChanged.asyncMap((_) async {
      return await _battery.batteryLevel;
    });
  }
}