package com.example.driver_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private val CHANNEL = "location_tracking_service"
    private var locationUpdateHandler: Handler? = null
    private var locationUpdateRunnable: Runnable? = null
    private lateinit var sharedPreferences: SharedPreferences
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sharedPreferences = applicationContext.getSharedPreferences("LocationTrackingPrefs", Context.MODE_PRIVATE)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    val username = call.argument<String>("username")
                    startLocationTrackingService(username)
                    result.success("Service started")
                }
                "stopTracking" -> {
                    stopLocationTrackingService()
                    result.success("Service stopped")
                }
                "isTracking" -> {
                    // We would need to implement a way to check if the service is running
                    result.success(false) // Placeholder
                }
                "getLastLocation" -> {
                    // This method will be called by Flutter to get the latest location
                    val lat = sharedPreferences.getString("last_location_lat", null)
                    val lng = sharedPreferences.getString("last_location_lng", null)
                    val lastUsername = sharedPreferences.getString("last_username", null)
                    val updated = sharedPreferences.getBoolean("location_updated", false)
                    
                    if (lat != null && lng != null && lastUsername != null) {
                        val locationMap = mapOf(
                            "lat" to lat.toDouble(),
                            "lng" to lng.toDouble(),
                            "username" to lastUsername,
                            "updated" to updated
                        )
                        result.success(locationMap)
                        // Reset the updated flag
                        sharedPreferences.edit().putBoolean("location_updated", false).apply()
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Start periodic checking for location updates from the native service
        startLocationUpdateListener()
    }
    
    private fun startLocationUpdateListener() {
        locationUpdateHandler = Handler(Looper.getMainLooper())
        locationUpdateRunnable = object : Runnable {
            override fun run() {
                // Check if location was updated
                if (sharedPreferences.getBoolean("location_updated", false)) {
                    // Location was updated, send to Flutter
                    val lat = sharedPreferences.getString("last_location_lat", null)
                    val lng = sharedPreferences.getString("last_location_lng", null)
                    val username = sharedPreferences.getString("last_username", null)
                    
                    if (lat != null && lng != null && username != null) {
                        // Send location update to Flutter - this would require an event channel
                        // For now, we'll just log it
                    }
                }
                
                // Schedule next check
                locationUpdateHandler?.postDelayed(this, 5000) // Check every 5 seconds
            }
        }
        locationUpdateHandler?.post(locationUpdateRunnable!!)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        locationUpdateRunnable?.let {
            locationUpdateHandler?.removeCallbacks(it)
        }
    }
    
    private fun startLocationTrackingService(username: String?) {
        if (username != null) {
            val intent = Intent(this, LocationTrackingService::class.java)
            intent.putExtra("username", username)
            startService(intent)
        }
    }
    
    private fun stopLocationTrackingService() {
        val intent = Intent(this, LocationTrackingService::class.java)
        stopService(intent)
    }
}