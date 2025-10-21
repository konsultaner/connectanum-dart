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
if [[ -f "$PROJECT_DIR/pubspec.yaml" ]]; then
  cd "$PROJECT_DIR"
  dart pub get

  # 4. build_runner if generated files are required
  if grep -R --include='*.dart' -e 'part .*\\.g\\.dart' lib >/dev/null 2>&1; then
    dart run build_runner build --delete-conflicting-outputs --build-filter="lib/**"
  fi
elif [[ -f "$PROJECT_DIR/packages/connectanum_client/pubspec.yaml" ]]; then
  for pkg in connectanum_core connectanum_client connectanum_router; do
    if [[ -f "$PROJECT_DIR/packages/$pkg/pubspec.yaml" ]]; then
      cd "$PROJECT_DIR/packages/$pkg"
      dart pub get

      if grep -R --include='*.dart' -e 'part .*\\.g\\.dart' lib >/dev/null 2>&1; then
        dart run build_runner build --delete-conflicting-outputs --build-filter="lib/**"
      fi
    fi
  done
else
  echo "No pubspec.yaml found in $PROJECT_DIR or its connectanum_* packages" >&2
  exit 1
fi

echo "✅  Dart setup completed for $(basename "$PROJECT_DIR")"

# 5. build temporary chromium script
cat <<'EOF' >/tmp/chrome-wrapper.sh
#!/bin/sh
exec google-chrome --no-sandbox "$@"
EOF

# 6. set the script as executable for chromium
chmod +x /tmp/chrome-wrapper.sh
export CHROME_EXECUTABLE=/tmp/chrome-wrapper.sh
