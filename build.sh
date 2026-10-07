#!/bin/bash

# Simple build script for Jeeves
# Usage: ./build.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🏗️  Building Jeeves for iOS 9.3.5..."

cd "$PROJECT_DIR"

xcodebuild \
    -project Jeeves.xcodeproj \
    -scheme Jeeves \
    -configuration Debug \
    -sdk iphoneos \
    -arch armv7 \
    -arch arm64 \
    IPHONEOS_DEPLOYMENT_TARGET=9.3 \
    CODE_SIGN_IDENTITY="iPhone Developer" \
    DEVELOPMENT_TEAM="7UB7J68BJQ" \
    build

echo "✅ Build complete!"
