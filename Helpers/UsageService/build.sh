#!/bin/sh
set -eu
service="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/XPCServices/UsageService.xpc"
mkdir -p "$service/Contents/MacOS" "$service/Contents/Resources"
cp "$SRCROOT/Helpers/UsageService/Info.plist" "$service/Contents/Info.plist"
cp "$SRCROOT/Tools/usage_bridge/usage_bridge.py" "$service/Contents/Resources/usage_bridge.py"
arch_flags=""
for architecture in $ARCHS; do arch_flags="$arch_flags -arch $architecture"; done
xcrun clang -fobjc-arc -framework Foundation -mmacosx-version-min=12.0 $arch_flags "$SRCROOT/Helpers/UsageService/main.m" -o "$service/Contents/MacOS/UsageService"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$service"
fi
