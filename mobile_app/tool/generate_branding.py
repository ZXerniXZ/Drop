#!/usr/bin/env python3
"""Regenerate Drop branding assets from source PNGs in repo assets/."""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
# logo_light.png = white droplet on black (dark UI / app icon)
# logo_dark.png = black droplet on white (light UI)
SRC_DARK_UI = ROOT / "assets/branding/source/logo_light.png"
SRC_LIGHT_UI = ROOT / "assets/branding/source/logo_dark.png"

OUT = ROOT / "assets/branding"
ANDROID_RES = ROOT / "android/app/src/main/res"
IOS_ICON_DIR = ROOT / "ios/Runner/AppIconAlt"
APPICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"


def stroke_bounds(im: Image.Image, is_dark: bool) -> tuple[int, int, int, int]:
    w, h = im.size
    px = im.load()
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if is_dark:
                if max(r, g, b) > 45:
                    minx, miny = min(minx, x), min(miny, y)
                    maxx, maxy = max(maxx, x), max(maxy, y)
            else:
                if min(r, g, b) < 190:
                    minx, miny = min(minx, x), min(miny, y)
                    maxx, maxy = max(maxx, x), max(maxy, y)
    return minx, miny, maxx, maxy


def crop_droplet_square(path: Path, is_dark: bool, pad: int = 24) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    minx, miny, maxx, maxy = stroke_bounds(im.convert("RGB"), is_dark)
    size = max(maxx - minx, maxy - miny) + pad * 2
    cx = (minx + maxx) // 2
    cy = (miny + maxy) // 2
    left = max(0, cx - size // 2)
    top = max(0, cy - size // 2)
    right = min(im.width, left + size)
    bottom = min(im.height, top + size)
    cropped = im.crop((left, top, right, bottom))
    side = max(cropped.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ox = (side - cropped.width) // 2
    oy = (side - cropped.height) // 2
    square.paste(cropped, (ox, oy))
    return square


def make_transparent(square: Image.Image, is_dark: bool) -> Image.Image:
    im = square.copy()
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if is_dark:
                if r < 35 and g < 35 and b < 35:
                    px[x, y] = (0, 0, 0, 0)
            else:
                if r > 170 and g > 170 and b > 170:
                    px[x, y] = (0, 0, 0, 0)
    return im


def make_app_icon(square: Image.Image, is_dark: bool, size: int = 1024) -> Image.Image:
    bg = (0, 0, 0, 255) if is_dark else (250, 250, 250, 255)
    canvas = Image.new("RGBA", (size, size), bg)
    target = int(size * 0.72)
    scaled = square.resize((target, target), Image.Resampling.LANCZOS)
    ox = (size - target) // 2
    oy = (size - target) // 2
    canvas.paste(scaled, (ox, oy), scaled)
    return canvas.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    IOS_ICON_DIR.mkdir(parents=True, exist_ok=True)

    dark_ui_sq = crop_droplet_square(SRC_DARK_UI, True)
    light_ui_sq = crop_droplet_square(SRC_LIGHT_UI, False)

    make_transparent(dark_ui_sq, True).resize((112, 112), Image.Resampling.LANCZOS).save(
        OUT / "logo_header_dark.png"
    )
    make_transparent(light_ui_sq, False).resize((112, 112), Image.Resampling.LANCZOS).save(
        OUT / "logo_header_light.png"
    )

    app_icon = make_app_icon(dark_ui_sq, True)
    light_icon = make_app_icon(light_ui_sq, False)
    app_icon_fg = make_transparent(dark_ui_sq, True)
    app_icon.save(OUT / "app_icon_dark_1024.png")
    light_icon.save(OUT / "app_icon_light_1024.png")

    for folder, sz in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        d = ANDROID_RES / folder
        d.mkdir(parents=True, exist_ok=True)
        app_icon.resize((sz, sz), Image.Resampling.LANCZOS).save(d / "ic_launcher.png")
        light_icon.resize((sz, sz), Image.Resampling.LANCZOS).save(d / "ic_launcher_light.png")
        fg_sz = int(sz * 0.72)
        fg = app_icon_fg.resize((fg_sz, fg_sz), Image.Resampling.LANCZOS)
        fg_canvas = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
        offset = (sz - fg_sz) // 2
        fg_canvas.paste(fg, (offset, offset), fg)
        fg_canvas.save(d / "ic_launcher_foreground.png")

    for name, icon, sizes in [
        ("light", light_icon, ((120, 180),)),
    ]:
        icon120 = icon.resize((120, 120), Image.Resampling.LANCZOS)
        icon180 = icon.resize((180, 180), Image.Resampling.LANCZOS)
        icon120.save(IOS_ICON_DIR / f"{name}@2x.png")
        icon180.save(IOS_ICON_DIR / f"{name}@3x.png")

    mapping = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, sz in mapping.items():
        app_icon.resize((sz, sz), Image.Resampling.LANCZOS).save(APPICON / name)

    print("Branding assets regenerated.")


if __name__ == "__main__":
    main()
