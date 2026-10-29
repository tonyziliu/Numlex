#!/usr/bin/env python3
"""Draws the Journal app icon (a white J on a teal squircle) and writes
Assets/Journal.iconset plus Sources/NumlexApp/Resources/AppIcon.icns."""
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 4096
TOP, BOTTOM = (45, 212, 191), (13, 148, 136)

def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        row = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = row
    return img

def j_path(cx, cy, h, r):
    stem_x = cx + r * 0.55
    top = cy - h / 2
    arc_cy = cy + h / 2 - r * 1.2
    pts = [(stem_x, top + i * (arc_cy - top) / 60) for i in range(61)]
    ccx = stem_x - r
    for i in range(1, 91):
        a = math.radians(i * 2)
        pts.append((ccx + r * math.cos(a), arc_cy + r * math.sin(a)))
    return pts

def render():
    body = 824 / 1024 * S
    inset = (S - body) / 2
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, S - inset, S - inset], radius=body * 0.225, fill=255)
    base = gradient(S)
    draw = ImageDraw.Draw(base)
    w = body * 0.15
    pts = j_path(S / 2, S / 2, body * 0.52, body * 0.19)
    stem_x, bar_y = pts[0]
    pts = pts[1:]
    for x, y in pts:
        draw.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill="white")
    draw.rectangle([stem_x - w / 2, bar_y, stem_x + w / 2, pts[0][1]], fill="white")
    draw.rounded_rectangle([stem_x - body * 0.2, bar_y - w / 2, stem_x + w / 2, bar_y + w / 2],
                           radius=w / 2, fill="white")
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 70), (0, int(S * 0.012)), mask)
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(S * 0.01)))
    out.paste(base, (0, 0), mask)
    return out

master = render().resize((1024, 1024), Image.LANCZOS)
iconset = os.path.join(ROOT, "Assets", "Journal.iconset")
os.makedirs(iconset, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    master.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
    master.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
master.save(os.path.join(ROOT, "Assets", "JournalIconPreview.png"))
subprocess.run(["iconutil", "-c", "icns", iconset, "-o",
                os.path.join(ROOT, "Sources", "NumlexApp", "Resources", "AppIcon.icns")], check=True)
print("ok")
