#!/bin/bash
# Double-click to build and install Weather Eyes as your live wallpaper.
cd "$(dirname "$0")"
echo "Building Weather Eyes…"
if ! command -v swiftc >/dev/null; then
  echo "Apple's developer tools are needed. A window will pop up: click Install, then double-click this file again."
  xcode-select --install; read -n1 -p "Press any key to close."; exit 1
fi
./build.sh || { read -n1 -p "Build failed. Press any key to close."; exit 1; }
pkill -x WeatherEyes 2>/dev/null
rm -rf "$HOME/Applications/Weather Eyes.app"
mv "Weather Eyes.app" "$HOME/Applications/"
open "$HOME/Applications/Weather Eyes.app"
echo "Done! Weather Eyes is now your wallpaper. Look for 👀 in the menu bar."
sleep 3
