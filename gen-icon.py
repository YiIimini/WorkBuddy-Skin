#!/usr/bin/env python3
"""WorkBuddy-Skin 现代扁平图标生成器"""
from PIL import Image, ImageDraw
import os, sys, math

SIZES = [16, 32, 64, 128, 256, 512, 1024]

def draw_rounded_rect(draw, x, y, w, h, r, color):
    """绘制圆角矩形"""
    draw.ellipse([x, y, x+r*2, y+r*2], fill=color)
    draw.ellipse([x+w-r*2, y, x+w, y+r*2], fill=color)
    draw.ellipse([x, y+h-r*2, x+r*2, y+h], fill=color)
    draw.ellipse([x+w-r*2, y+h-r*2, x+w, y+h], fill=color)
    draw.rectangle([x+r, y, x+w-r, y+h], fill=color)
    draw.rectangle([x, y+r, x+w, y+h-r], fill=color)

def draw_icon(size):
    """现代图标：圆角方形渐变色底 + 菱形✦图案"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 背景圆角方形渐变色（深紫→粉紫）
    margin = size * 0.06
    r = size * 0.20
    bg_size = size - margin * 2

    for y in range(size):
        for x in range(size):
            # 圆角裁剪
            rx = x - margin
            ry = y - margin
            inside = True
            if rx < r and ry < r and (rx-r)**2 + (ry-r)**2 > r*r: inside = False
            if rx > bg_size-r and ry < r and (rx-(bg_size-r))**2 + (ry-r)**2 > r*r: inside = False
            if rx < r and ry > bg_size-r and (rx-r)**2 + (ry-(bg_size-r))**2 > r*r: inside = False
            if rx > bg_size-r and ry > bg_size-r and (rx-(bg_size-r))**2 + (ry-(bg_size-r))**2 > r*r: inside = False
            if rx < 0 or rx > bg_size or ry < 0 or ry > bg_size: inside = False
            if not inside: continue

            ratio = y / size
            rv = int(80 + ratio * 30)
            gv = int(30 + ratio * 25)
            bv = int(130 + ratio * 40)
            img.putpixel((x, y), (rv, gv, bv, 255))

    # 中心✦菱形符号
    cx, cy = size/2, size/2
    diamond_r = size * 0.25

    for y in range(size):
        for x in range(size):
            dx, dy = abs(x - cx), abs(y - cy)
            # 菱形: |dx| + |dy| < r
            if dx + dy < diamond_r:
                # 空心效果 - 边缘更亮
                dist = dx + dy
                border = diamond_r * 0.3
                if dist > diamond_r - border:
                    alpha = int(255 * (1 - (dist - (diamond_r - border)) / border))
                    color = (255, 220, 240, alpha)
                else:
                    color = (255, 255, 255, 200)
                img.putpixel((x, y), color)

    return img

outdir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/AppIcon.iconset"
os.makedirs(outdir, exist_ok=True)

for s in SIZES:
    icon = draw_icon(s)
    path = f"{outdir}/icon_{s}x{s}.png"
    icon.save(path)
    if s <= 512:
        s2 = s * 2
        resized = icon.resize((s2, s2), Image.LANCZOS)
        resized.save(f"{outdir}/icon_{s}x{s}@2x.png")
    print(f"  {s}x{s} ✓")

print("✅ 图标生成完成")
