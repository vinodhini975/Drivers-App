#Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Services Location
-keep class com.google.android.gms.location.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }

# Keep native service
-keep class com.example.driver_app.LocationTrackingService { *; }

# Keep Flutter method channel
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class io.flutter.plugin.common.MethodChannel$Result { *; }