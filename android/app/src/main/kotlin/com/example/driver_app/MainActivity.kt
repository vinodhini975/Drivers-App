package com.example.driver_app

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val PERMISSION_CHANNEL = "location_permission"
    private val TRACKING_CHANNEL = "location_tracking_service"
    private val EVENT_CHANNEL = "location_tracking_service/events"

    private val GPS_REQUEST_CODE = 1001
    private val PERMISSION_REQUEST_CODE = 1002
    private var pendingResult: MethodChannel.Result? = null
    
    private var eventSink: EventChannel.EventSink? = null

    private val locationUpdateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.driver_app.LOCATION_UPDATE") {
                val lat = intent.getDoubleExtra("lat", 0.0)
                val lng = intent.getDoubleExtra("lng", 0.0)
                val acc = intent.getFloatExtra("acc", 0f)
                val speed = intent.getFloatExtra("speed", 0f)
                
                val locationData = mapOf(
                    "latitude" to lat,
                    "longitude" to lng,
                    "accuracy" to acc.toDouble(),
                    "speed" to speed.toDouble()
                )
                
                runOnUiThread {
                    eventSink?.success(locationData)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Permission Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "requestLocationAndEnableGPS") {
                pendingResult = result
                checkPermissionsAndEnableGPS()
            } else {
                result.notImplemented()
            }
        }

        // Tracking Channel (Restored)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRACKING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    val username = call.argument<String>("username")
                    if (username != null) {
                        val intent = Intent(this, LocationTrackingService::class.java)
                        intent.putExtra("username", username)
                        ContextCompat.startForegroundService(this, intent)
                        result.success("Service started")
                    } else {
                        result.error("INVALID_ARG", "Username required", null)
                    }
                }
                "stopTracking" -> {
                    val intent = Intent(this, LocationTrackingService::class.java)
                    stopService(intent)
                    result.success("Service stopped")
                }
                "isTracking" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Event Channel for background dart updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    val filter = IntentFilter("com.example.driver_app.LOCATION_UPDATE")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(locationUpdateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(locationUpdateReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun checkPermissionsAndEnableGPS() {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissions.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }

        val missingPermissions = permissions.filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missingPermissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        } else {
            enableGPS()
        }
    }

    private fun enableGPS() {
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10000L).build()
        val builder = LocationSettingsRequest.Builder().addLocationRequest(locationRequest)
        val client: SettingsClient = LocationServices.getSettingsClient(this)
        val task = client.checkLocationSettings(builder.build())

        task.addOnSuccessListener {
            pendingResult?.success("SUCCESS")
            pendingResult = null
        }

        task.addOnFailureListener { exception ->
            if (exception is ResolvableApiException) {
                try {
                    exception.startResolutionForResult(this, GPS_REQUEST_CODE)
                } catch (sendEx: IntentSender.SendIntentException) {
                    pendingResult?.error("GPS_ERROR", "Could not show GPS dialog", null)
                    pendingResult = null
                }
            } else {
                pendingResult?.error("GPS_UNAVAILABLE", "Device does not support GPS settings", null)
                pendingResult = null
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                enableGPS()
            } else {
                pendingResult?.success("FAILURE")
                pendingResult = null
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == GPS_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                pendingResult?.success("SUCCESS")
            } else {
                pendingResult?.success("FAILURE")
            }
            pendingResult = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(locationUpdateReceiver)
        } catch (e: Exception) {}
    }
}
