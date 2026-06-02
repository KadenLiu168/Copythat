#!/usr/bin/env python3
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "Copythat" / "Resources"
ASSET_DIR = RESOURCES / "Assets.xcassets" / "AppIcon.appiconset"
ICONSET_DIR = RESOURCES / "AppIcon.iconset"


def rounded_rectangle_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def draw_c_mark(draw, scale, fill):
    box = [246 * scale, 220 * scale, 806 * scale, 780 * scale]
    width = round(104 * scale)
    draw.arc(box, start=44, end=316, fill=fill, width=width)

    cap = width / 2
    for x, y in ((702, 320), (702, 680)):
        draw.ellipse(
            ((x * scale - cap, y * scale - cap), (x * scale + cap, y * scale + cap)),
            fill=fill,
        )

    draw.rounded_rectangle(
        (454 * scale, 456 * scale, 742 * scale, 536 * scale),
        radius=40 * scale,
        fill=fill,
    )


def make_app_icon(size):
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg = Image.new("RGBA", (size, size), (30, 45, 58, 255))
    bg.putalpha(rounded_rectangle_mask(size, round(190 * scale)))

    draw_bg = ImageDraw.Draw(bg)
    draw_bg.rounded_rectangle(
        (104 * scale, 104 * scale, 920 * scale, 920 * scale),
        radius=172 * scale,
        outline=(255, 255, 255, 24),
        width=max(1, round(2 * scale)),
    )

    canvas.alpha_composite(bg)
    draw = ImageDraw.Draw(canvas)
    draw_c_mark(draw, scale, (78, 210, 206, 255))
    return canvas


def make_transparent_icon(size):
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw_c_mark(draw, scale, (34, 191, 188, 255))
    return canvas


def make_menu_bar_icon(size=64):
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw_c_mark(draw, scale, (0, 0, 0, 255))
    return canvas


def save_icons():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    for size in (16, 32, 64, 128, 256, 512, 1024):
        make_app_icon(size).save(ASSET_DIR / f"icon_{size}.png")

    iconset_sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in iconset_sizes.items():
        make_app_icon(size).save(ICONSET_DIR / filename)

    make_app_icon(1024).save(RESOURCES / "AppIcon-1024.png")
    make_transparent_icon(1024).save(RESOURCES / "AppIcon-transparent.png")
    make_menu_bar_icon().save(RESOURCES / "MenuBarIconTemplate.png")

    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(RESOURCES / "AppIcon.icns")],
        check=True,
    )


if __name__ == "__main__":
    save_icons()
