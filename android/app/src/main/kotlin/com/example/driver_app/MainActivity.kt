package com.example.driver_app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "location_permission"
    private val GPS_REQUEST_CODE = 1001
    private val PERMISSION_REQUEST_CODE = 1002
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "requestLocationAndEnableGPS") {
                pendingResult = result
                checkPermissionsAndEnableGPS()
            } else {
                result.notImplemented()
            }
        }
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
}
