#!/bin/bash

echo "=========================================="
echo "SHA-1 & SHA-256 Certificate Generator"
echo "for Google Sign-In / Firebase"
echo "=========================================="
echo ""

# Check if keytool is available
if ! command -v keytool &> /dev/null
then
    echo "ERROR: keytool not found!"
    echo "Please ensure Java JDK is installed and added to PATH"
    exit 1
fi

echo "1. Debug Keystore SHA Keys:"
echo "-------------------------------------------"

# Debug keystore location (default)
DEBUG_KEYSTORE="$HOME/.android/debug.keystore"

if [ -f "$DEBUG_KEYSTORE" ]; then
    echo "📍 Location: $DEBUG_KEYSTORE"
    echo ""
    keytool -list -v -keystore "$DEBUG_KEYSTORE" -alias androiddebugkey -storepass android -keypass android | grep -E "SHA1|SHA256"
    echo ""
else
    echo "⚠️  Debug keystore not found at: $DEBUG_KEYSTORE"
    echo ""
fi

echo ""
echo "2. Release Keystore SHA Keys (if exists):"
echo "-------------------------------------------"

# Check for release keystore in common locations
RELEASE_KEYSTORE_LOCATIONS=(
    "android/app/upload-keystore.jks"
    "android/app/release-keystore.jks"
    "android/app/key.jks"
    "android/keystore.jks"
)

FOUND_RELEASE=false

for keystore in "${RELEASE_KEYSTORE_LOCATIONS[@]}"; do
    if [ -f "$keystore" ]; then
        echo "📍 Found release keystore: $keystore"
        echo "Enter the keystore password:"
        read -s KEYSTORE_PASSWORD
        echo "Enter the key alias:"
        read KEY_ALIAS
        echo ""
        
        keytool -list -v -keystore "$keystore" -alias "$KEY_ALIAS" -storepass "$KEYSTORE_PASSWORD" | grep -E "SHA1|SHA256"
        echo ""
        FOUND_RELEASE=true
        break
    fi
done

if [ "$FOUND_RELEASE" = false ]; then
    echo "⚠️  No release keystore found in common locations"
    echo ""
fi

echo "=========================================="
echo "📋 Instructions:"
echo "=========================================="
echo "1. Copy the SHA-1 fingerprint from above"
echo "2. Go to Firebase Console:"
echo "   https://console.firebase.google.com"
echo "3. Select your project: waste-collection-truck-tracker"
echo "4. Go to Project Settings → Your apps"
echo "5. Select your Android app (com.example.driver_app)"
echo "6. Add the SHA-1 certificate fingerprint"
echo "7. Download the updated google-services.json"
echo "8. Replace android/app/google-services.json"
echo ""
echo "✅ Done!"
echo "=========================================="
