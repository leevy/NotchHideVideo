#!/bin/bash
set -euo pipefail

APP_NAME="NotchHideVideo"
BUILD_DIR="build/${APP_NAME}.app"
CONTENTS="${BUILD_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
ARCH=$(uname -m)

# Generate AppIcon.icns if needed
if [ ! -f "AppIcon.icns" ]; then
  swift make_icon.swift
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  rm -rf AppIcon.iconset
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp Info.plist "${CONTENTS}/Info.plist"
cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"

swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macosx15.0" \
  -framework Cocoa \
  -framework AVFoundation \
  -framework CoreImage \
  -framework CoreMedia \
  -framework VideoToolbox \
  -framework UniformTypeIdentifiers \
  -framework ServiceManagement \
  Sources/*.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

codesign --force --deep --sign - "${BUILD_DIR}"
touch "${BUILD_DIR}"
echo "Built ${BUILD_DIR}"