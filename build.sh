#!/bin/bash
# Сборка TickNotch.app без Xcode — хватает Command Line Tools (swiftc).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TickNotch.app"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
    -target "$TARGET" \
    TickNotch/*.swift \
    -o "$APP/Contents/MacOS/TickNotch"

cp TickNotch/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc подпись; при пересборке Keychain может переспросить доступ к cookie — это нормально.
codesign --force -s - "$APP"

echo "Готово: $APP"
echo "Запуск: open $APP"
