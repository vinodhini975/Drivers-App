#!/bin/bash

# Script to setup CocoaPods for the iOS project
set -e

echo "🔧 Starting iOS pod setup..."

# Navigate to iOS directory
cd "$(dirname "$0")"

# Update CocoaPods specs repository
echo "📦 Updating CocoaPods repository..."
pod repo update

# Remove old pods and derived data
echo "🧹 Cleaning old pods..."
rm -rf Pods
rm -rf Podfile.lock
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Install pods
echo "📥 Installing pods..."
pod install --repo-update

echo "✅ Pod setup complete!"
echo "You can now run: flutter run"
