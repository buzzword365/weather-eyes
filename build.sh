#!/bin/bash
# Builds "Weather Eyes.app" next to this script. Needs Xcode Command Line Tools:
#   xcode-select --install
set -e
cd "$(dirname "$0")"
APP="Weather Eyes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/WeatherEyes" \
  -framework Cocoa -framework WebKit -framework ServiceManagement
cp eyes.html "$APP/Contents/Resources/"
[ -f config.js ] && cp config.js "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "Built $APP — drag it into Applications and open it."
