plugins {
    // Android & Kotlin
    id("com.android.application")
    id("org.jetbrains.kotlin.android")

    // Flutter plugin must come after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase services
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.driver_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.driver_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        // Needed for background services + geolocator + multidex
        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildTypes {
        release {
            // Use release signing config from debug for testing
            signingConfig = signingConfigs.getByName("debug")

            // Enable code shrinking and obfuscation
            isMinifyEnabled = false 
            isShrinkResources = false 

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            // Disable shrinking for debug build
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BoM — Match pubspec firebase versions
    implementation(platform("com.google.firebase:firebase-bom:32.7.3"))

    // Firebase Analytics (correct artifact name)
    implementation("com.google.firebase:firebase-analytics-ktx")

    // Required for multidex support
    implementation("androidx.multidex:multidex:2.0.1")
    
    // Add core library desugaring for newer Java APIs on older Android versions
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    // Google Play Services for location - use only the required parts
    implementation("com.google.android.gms:play-services-location:21.3.0")
}