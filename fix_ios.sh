#!/bin/bash

# Comprehensive Flutter iOS Fix Script
# This script fixes CocoaPods issues and ensures stable dependencies

set -e

echo "🚀 Starting comprehensive Flutter iOS setup..."
echo ""

# Change to project root
PROJECT_DIR="/Users/deepakkambam/StudioProjects/Drivers-App"
cd "$PROJECT_DIR"

# Step 1: Flutter Clean
echo "🧹 Step 1: Cleaning Flutter build cache..."
flutter clean
echo "✅ Flutter clean complete"
echo ""

# Step 2: Remove iOS build artifacts
echo "🗑️  Step 2: Removing iOS build artifacts..."
cd ios
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
echo "✅ iOS artifacts removed"
echo ""

# Step 3: Update CocoaPods repository
echo "📦 Step 3: Updating CocoaPods specs repository..."
echo "   This may take a few minutes..."
pod repo update
echo "✅ CocoaPods repo updated"
echo ""

# Step 4: Get Flutter dependencies
echo "📥 Step 4: Getting Flutter dependencies..."
cd "$PROJECT_DIR"
flutter pub get
echo "✅ Flutter dependencies retrieved"
echo ""

# Step 5: Install CocoaPods
echo "🔧 Step 5: Installing CocoaPods for iOS..."
cd ios
pod deintegrate 2>/dev/null || true
pod install --repo-update
echo "✅ CocoaPods installed successfully"
echo ""

# Step 6: Verify setup
echo "🔍 Step 6: Verifying setup..."
if [ -d "Pods" ] && [ -f "Podfile.lock" ]; then
    echo "✅ All iOS dependencies installed correctly"
else
    echo "⚠️  Warning: Some iOS dependencies may not be installed"
fi
echo ""

echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Ensure you have a valid google-services.json in android/app/"
echo "2. Ensure you have a valid GoogleService-Info.plist in ios/Runner/"
echo "3. Run: flutter run"
echo ""
