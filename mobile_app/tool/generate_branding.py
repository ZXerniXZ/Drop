#!/usr/bin/env python3
"""Regenerate Drop branding from the white hand-drawn droplet on black."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/branding/source/logo_white_on_black.jpg"

WEB_ICONS = ROOT / "web/icons"
WEB_ROOT = ROOT / "web"
OUT = ROOT / "assets/branding"
ANDROID_RES = ROOT / "android/app/src/main/res"
IOS_ICON_DIR = ROOT / "ios/Runner/AppIconAlt"
APPICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
MACICON = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"

# Sampled from the approved artwork. Adaptive-icon background must match.
PAPER = (20, 20, 20, 255)


def ink_bounds(im: Image.Image) -> tuple[int, int, int, int]:
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            if max(px[x, y]) > 40:
                minx, miny = min(minx, x), min(miny, y)
                maxx, maxy = max(maxx, x), max(maxy, y)
    return minx, miny, maxx, maxy


def load_icon() -> Image.Image:
    """Approved square: white droplet, black field, original framing."""
    im = Image.open(SRC).convert("RGB")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    return im


def header_mark(icon: Image.Image) -> Image.Image:
    """Same mark, cropped tighter so it stays readable beside the wordmark."""
    minx, miny, maxx, maxy = ink_bounds(icon)
    ink_h = maxy - miny
    pad = int(ink_h * 0.14)
    side = max(maxx - minx, ink_h) + pad * 2
    cx = (minx + maxx) // 2
    cy = (miny + maxy) // 2
    left = max(0, cx - side // 2)
    top = max(0, cy - side // 2)
    right = min(icon.width, left + side)
    bottom = min(icon.height, top + side)
    cropped = icon.crop((left, top, right, bottom))
    canvas = Image.new("RGB", (side, side), PAPER[:3])
    canvas.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    return canvas


def save_resized(icon: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    icon.resize((size, size), Image.Resampling.LANCZOS).save(path)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    IOS_ICON_DIR.mkdir(parents=True, exist_ok=True)
    WEB_ICONS.mkdir(parents=True, exist_ok=True)

    icon = load_icon()
    icon.save(OUT / "app_icon_1024.png")
    # Keep the previous filenames so nothing still pointing at them shows the old mark.
    icon.save(OUT / "app_icon_dark_1024.png")
    icon.save(OUT / "app_icon_light_1024.png")

    header = header_mark(icon).resize((256, 256), Image.Resampling.LANCZOS)
    header.save(OUT / "logo_header.png")

    for folder, sz in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        d = ANDROID_RES / folder
        save_resized(icon, d / "ic_launcher.png", sz)
        save_resized(icon, d / "ic_launcher_light.png", sz)
        save_resized(icon, d / "ic_launcher_foreground.png", sz)

    for name in ("default", "light", "dark"):
        save_resized(icon, IOS_ICON_DIR / f"{name}@2x.png", 120)
        save_resized(icon, IOS_ICON_DIR / f"{name}@3x.png", 180)

    ios_sizes = {
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
    for name, sz in ios_sizes.items():
        save_resized(icon, APPICON / name, sz)

    for sz, name in (
        (16, "app_icon_16.png"),
        (32, "app_icon_32.png"),
        (64, "app_icon_64.png"),
        (128, "app_icon_128.png"),
        (256, "app_icon_256.png"),
        (512, "app_icon_512.png"),
        (1024, "app_icon_1024.png"),
    ):
        save_resized(icon, MACICON / name, sz)

    for sz in (192, 512):
        save_resized(icon, WEB_ICONS / f"Icon-{sz}.png", sz)
        save_resized(icon, WEB_ICONS / f"Icon-maskable-{sz}.png", sz)
    save_resized(icon, WEB_ICONS / "apple-touch-icon.png", 180)
    save_resized(icon, WEB_ROOT / "favicon.png", 32)

    print("Branding assets regenerated from the white droplet on black.")


if __name__ == "__main__":
    main()
