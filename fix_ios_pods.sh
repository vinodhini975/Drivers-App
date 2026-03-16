#!/bin/bash

# Flutter iOS CocoaPods Fix Script
# This script resolves common iOS build issues related to CocoaPods dependencies

echo "🔧 Starting iOS CocoaPods fix..."
echo ""

# Navigate to the iOS directory
cd "$(dirname "$0")/ios" || exit 1

# Step 1: Clean Flutter build
echo "📦 Step 1: Cleaning Flutter build..."
cd ..
flutter clean
echo "✅ Flutter clean complete"
echo ""

# Step 2: Remove old pods and lock file
echo "🗑️  Step 2: Removing old Pods and Podfile.lock..."
cd ios
rm -rf Pods/
rm -rf Podfile.lock
rm -rf .symlinks/
echo "✅ Old files removed"
echo ""

# Step 3: Update CocoaPods repo
echo "🔄 Step 3: Updating CocoaPods specs repository..."
echo "⏳ This may take a few minutes..."
pod repo update
echo "✅ CocoaPods repo updated"
echo ""

# Step 4: Get Flutter dependencies
echo "📥 Step 4: Getting Flutter dependencies..."
cd ..
flutter pub get
echo "✅ Flutter dependencies installed"
echo ""

# Step 5: Install pods
echo "🍎 Step 5: Installing iOS pods..."
cd ios
pod install --repo-update
echo "✅ Pods installed"
echo ""

echo "✨ iOS CocoaPods fix complete!"
echo ""
echo "You can now run your app with: flutter run"
