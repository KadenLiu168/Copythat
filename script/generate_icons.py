#!/usr/bin/env python3
from pathlib import Path
import math
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "Copythat" / "Resources"
ASSET_DIR = RESOURCES / "Assets.xcassets" / "AppIcon.appiconset"
ICONSET_DIR = RESOURCES / "AppIcon.iconset"
MARK_FONT = Path("/System/Library/Fonts/Avenir Next.ttc")
APP_MARK = (255, 76, 96, 255)
APP_BG = (255, 250, 244, 255)


def rounded_rectangle_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def light_warm_background(size):
    canvas = Image.new("RGBA", (size, size), APP_BG)
    pixels = canvas.load()
    glow_center = (size * 0.26, size * 0.18)

    for y in range(size):
        for x in range(size):
            glow = max(0, 1 - math.hypot(x - glow_center[0], y - glow_center[1]) / (size * 0.95)) * 8
            blush = max(0, 1 - math.hypot(x - size * 0.72, y - size * 0.78) / (size * 0.85)) * 8
            edge = math.hypot(x - size / 2, y - size / 2) / (size * 0.80) * 6
            pixels[x, y] = (
                int(max(0, min(255, APP_BG[0] + glow - edge))),
                int(max(0, min(255, APP_BG[1] + glow * 0.72 + blush * 0.24 - edge))),
                int(max(0, min(255, APP_BG[2] + glow * 0.48 + blush * 0.16 - edge))),
                255,
            )

    canvas.putalpha(rounded_rectangle_mask(size, round(size * 0.225)))
    return canvas


def c_mark_mask(size):
    if not MARK_FONT.exists():
        raise FileNotFoundError(f"missing icon font: {MARK_FONT}")

    scale = size / 1024
    font = ImageFont.truetype(str(MARK_FONT), max(4, round(735 * scale)))
    stroke = round(18 * scale)
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    box = draw.textbbox((0, 0), "C", font=font, stroke_width=stroke)
    text_width = box[2] - box[0]
    text_height = box[3] - box[1]
    x = (size - text_width) / 2 - box[0] - 4 * scale
    y = (size - text_height) / 2 - box[1] - 4 * scale
    draw.text((x, y), "C", font=font, fill=255, stroke_width=stroke, stroke_fill=255)

    radius = max(1, round(10 * scale))
    return mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda pixel: 255 if pixel > 112 else 0)


def c_mark(size, fill, shadow=False):
    scale = size / 1024
    mask = c_mark_mask(size)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    if shadow:
        shadow_alpha = mask.filter(ImageFilter.GaussianBlur(max(1, round(12 * scale))))
        shadow = Image.new("RGBA", (size, size), (150, 48, 62, 34))
        shadow.putalpha(shadow_alpha)
        canvas.alpha_composite(shadow, (round(10 * scale), round(13 * scale)))

    mark = Image.new("RGBA", (size, size), fill)
    mark.putalpha(mask)
    canvas.alpha_composite(mark)
    return canvas


def make_app_icon(size):
    scale = size / 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(light_warm_background(size))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (86 * scale, 86 * scale, 938 * scale, 938 * scale),
        radius=218 * scale,
        outline=(255, 255, 255, 168),
        width=max(1, round(6 * scale)),
    )
    draw.rounded_rectangle(
        (136 * scale, 136 * scale, 888 * scale, 888 * scale),
        radius=178 * scale,
        outline=(255, 76, 96, 24),
        width=max(1, round(3 * scale)),
    )
    canvas.alpha_composite(c_mark(size, APP_MARK, shadow=True))
    return canvas


def make_transparent_icon(size):
    return c_mark(size, APP_MARK)


def make_menu_bar_icon(size=64):
    return c_mark(size, (0, 0, 0, 255))


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
