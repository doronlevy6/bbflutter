#!/bin/bash
set -e

echo "Downloading Flutter SDK..."
curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz -o flutter.tar.xz
tar xf flutter.tar.xz

export PATH="$PATH:$(pwd)/flutter/bin"

flutter config --enable-web
flutter pub get

echo "Building Flutter Web..."
flutter build web --release --dart-define=PROD_API_URL=https://renderbbserver.onrender.com
