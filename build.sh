#!/bin/bash
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "=== 生成 Xcode 项目 ==="
rm -rf "PinNote.xcodeproj"
xcodegen generate

echo ""
echo "=== 编译 ==="
xcodebuild -project "PinNote.xcodeproj" -scheme "PinNote" -configuration Debug build

if [ $? -eq 0 ]; then
    echo ""
    echo "=== 编译成功 ==="
    BUILD_DIR=$(xcodebuild -project "PinNote.xcodeproj" -scheme "PinNote" -configuration Debug -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $NF}')

    echo "=== 生成 DMG ==="
    rm -rf /tmp/pn_dmg "PinNote.dmg"
    mkdir -p /tmp/pn_dmg
    cp -R "$BUILD_DIR/PinNote.app" /tmp/pn_dmg/
    ln -s /Applications /tmp/pn_dmg/Applications
    hdiutil create -volname "PinNote" -srcfolder /tmp/pn_dmg -ov -format UDZO -imagekey zlib-level=9 "PinNote.dmg"
    rm -rf /tmp/pn_dmg

    echo ""
    echo "=== 完成: PinNote.dmg ==="
else
    echo "=== 编译失败 ==="
fi
