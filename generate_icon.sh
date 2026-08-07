#!/bin/bash
# 生成 PinNote.icns 图标（黑色圆角背景 + 三条白色横线，横线左端为圆形）
cd "$(dirname "$0")"

ICON_DIR="PinNote.iconset"
mkdir -p "$ICON_DIR" Resources

python3 << 'PYEOF'
import struct, zlib, math

def create_png(width, height, pixel_func):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            r, g, b, a = pixel_func(x, y, width, height)
            raw += struct.pack('BBBB', r, g, b, a)
    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend

def pixel(x, y, w, h):
    # 圆角方形背景
    r = 0.22 * w
    dx = max(r - x, r - (w - x), 0)
    dy = max(r - y, r - (h - y), 0)
    if dx * dx + dy * dy > r * r:
        return (0, 0, 0, 0)
    # 三条横线（左端圆形）
    line_ys = [0.30, 0.50, 0.70]
    dot_r = 0.045 * w
    half_t = 0.020 * w
    x0 = 0.30 * w
    x1 = 0.74 * w
    for ly in line_ys:
        cy = ly * h
        if (x - x0) ** 2 + (y - cy) ** 2 <= dot_r * dot_r:
            return (255, 255, 255, 255)
        if x0 <= x <= x1 and abs(y - cy) <= half_t:
            return (255, 255, 255, 255)
    return (0, 0, 0, 255)

with open('PinNote.iconset/icon_512x512@2x.png', 'wb') as f:
    f.write(create_png(1024, 1024, pixel))
print("PNG created")
PYEOF

if [ ! -f "PinNote.iconset/icon_512x512@2x.png" ]; then
    echo "PNG generation failed!"
    exit 1
fi

sips -z 512 512 "PinNote.iconset/icon_512x512@2x.png" --out "PinNote.iconset/icon_512x512.png" > /dev/null 2>&1
sips -z 512 512 "PinNote.iconset/icon_512x512@2x.png" --out "PinNote.iconset/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 256 256 "PinNote.iconset/icon_512x512.png" --out "PinNote.iconset/icon_256x256.png" > /dev/null 2>&1
sips -z 256 256 "PinNote.iconset/icon_512x512@2x.png" --out "PinNote.iconset/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 128 128 "PinNote.iconset/icon_512x512.png" --out "PinNote.iconset/icon_128x128.png" > /dev/null 2>&1
sips -z 64 64 "PinNote.iconset/icon_512x512@2x.png" --out "PinNote.iconset/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 32 32 "PinNote.iconset/icon_512x512.png" --out "PinNote.iconset/icon_32x32.png" > /dev/null 2>&1
sips -z 32 32 "PinNote.iconset/icon_512x512@2x.png" --out "PinNote.iconset/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 16 16 "PinNote.iconset/icon_512x512.png" --out "PinNote.iconset/icon_16x16.png" > /dev/null 2>&1
rm -f "PinNote.iconset/icon_64x64.png"

iconutil -c icns "PinNote.iconset" -o "Resources/PinNote.icns"

echo "=== PinNote.icns generated ==="
ls -la Resources/PinNote.icns
