#!/usr/bin/env bash
###############################################################################
# Setup script for CI Dart (tarball) – persistent version
###############################################################################
set -euxo pipefail

# 1. Download Dart SDK only once
DART_VERSION="3.8.1"
DART_SDK_INSTALL_DIR="$HOME/dart"
DART_TARBALL_URL="https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-x64-release.zip"

if [[ ! -d "$DART_SDK_INSTALL_DIR" ]]; then
  echo "📦  Download Dart $DART_VERSION …"
  curl -sL "$DART_TARBALL_URL" -o /tmp/dartsdk.zip
  unzip -q /tmp/dartsdk.zip -d "$HOME"
  mv "$HOME/dart-sdk" "$DART_SDK_INSTALL_DIR"
else
  echo "⚠️   Dart cache already present → $DART_SDK_INSTALL_DIR"
fi

# avoid “dubious ownership” warnings
git config --global --add safe.directory "$DART_SDK_INSTALL_DIR"

# 2. Make dart visible in all steps
export PATH="$DART_SDK_INSTALL_DIR/bin:$PATH"

sudo ln -sf "$DART_SDK_INSTALL_DIR/bin/dart" /usr/local/bin/dart

dart --version

# 3. Project dependencies
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"
dart pub get

# 4. build_runner if generated files are required
if grep -R --include='*.dart' -e 'part .*\.g\.dart' lib >/dev/null 2>&1; then
  dart run build_runner build --delete-conflicting-outputs --build-filter="lib/**"
fi

echo "✅  Dart setup completed for $(basename "$PROJECT_DIR")"
