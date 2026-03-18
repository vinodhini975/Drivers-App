#!/bin/bash

# Quick fix script - Run this if you encounter build errors
# This will clean and rebuild everything properly

echo "🔧 Quick Fix - Cleaning and rebuilding project..."
echo ""

cd /Users/deepakkambam/StudioProjects/Drivers-App

# Clean everything
echo "1️⃣  Cleaning Flutter..."
flutter clean

# Remove iOS pods
echo "2️⃣  Removing iOS pods..."
cd ios
rm -rf Pods Podfile.lock .symlinks
cd ..

# Get dependencies
echo "3️⃣  Getting Flutter dependencies..."
flutter pub get

# Update and install pods
echo "4️⃣  Installing iOS pods (this may take a few minutes)..."
cd ios
pod deintegrate 2>/dev/null || true
pod repo update
pod install
cd ..

echo ""
echo "✅ Done! Try running your app now:"
echo "   flutter run"
echo ""
