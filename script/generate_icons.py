#!/usr/bin/env python3
from collections import deque
from functools import lru_cache
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "Copythat" / "Resources"
ASSET_DIR = RESOURCES / "Assets.xcassets" / "AppIcon.appiconset"
LOGO_SOURCE = ROOT / "script" / "assets" / "Copythat.png"
DARK_EDGE_THRESHOLD = 56
MENU_BAR_SIZE = 64


try:
    RESAMPLE = Image.Resampling.LANCZOS
except AttributeError:
    RESAMPLE = Image.LANCZOS


def is_edge_background(pixel):
    red, green, blue, alpha = pixel
    return alpha > 0 and max(red, green, blue) <= DARK_EDGE_THRESHOLD


def remove_edge_background(image):
    image = image.copy()
    width, height = image.size
    pixels = image.load()
    visited = bytearray(width * height)
    queue = deque()

    def enqueue(x, y):
        index = y * width + x
        if visited[index] or not is_edge_background(pixels[x, y]):
            return
        visited[index] = 1
        queue.append((x, y))

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)

    while queue:
        x, y = queue.popleft()
        red, green, blue, _ = pixels[x, y]
        pixels[x, y] = (red, green, blue, 0)

        if x > 0:
            enqueue(x - 1, y)
        if x + 1 < width:
            enqueue(x + 1, y)
        if y > 0:
            enqueue(x, y - 1)
        if y + 1 < height:
            enqueue(x, y + 1)

    return image


@lru_cache(maxsize=1)
def source_logo():
    if not LOGO_SOURCE.exists():
        raise FileNotFoundError(f"missing logo source: {LOGO_SOURCE}")

    image = Image.open(LOGO_SOURCE).convert("RGBA")
    if image.width != image.height:
        raise ValueError(f"logo source must be square: {image.size}")

    return remove_edge_background(image)


def make_app_icon(size):
    return source_logo().resize((size, size), RESAMPLE)


def make_menu_bar_mask():
    logo = source_logo()
    mask = Image.new("L", logo.size, 0)
    source_pixels = logo.load()
    mask_pixels = mask.load()
    width, height = logo.size

    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha == 0:
                continue

            saturation = max(red, green, blue) - min(red, green, blue)
            luminance = (red * 0.299) + (green * 0.587) + (blue * 0.114)
            if saturation >= 28 and luminance <= 248:
                mask_pixels[x, y] = alpha

    bbox = mask.getbbox()
    if bbox is None:
        return logo.getchannel("A")

    return mask.crop(bbox)


def make_menu_bar_icon(size=MENU_BAR_SIZE):
    mark = make_menu_bar_mask()
    padded_side = max(mark.width, mark.height)
    padded = Image.new("L", (padded_side, padded_side), 0)
    padded.paste(mark, ((padded_side - mark.width) // 2, (padded_side - mark.height) // 2))

    target = max(1, round(size * 0.78))
    resized = padded.resize((target, target), RESAMPLE)
    alpha = Image.new("L", (size, size), 0)
    alpha.paste(resized, ((size - target) // 2, (size - target) // 2))

    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    image.putalpha(alpha)
    return image


def save_icons():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

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
    with TemporaryDirectory(prefix="copythat-iconset-") as temporary_directory:
        iconset_dir = Path(temporary_directory) / "AppIcon.iconset"
        iconset_dir.mkdir()
        for filename, size in iconset_sizes.items():
            make_app_icon(size).save(iconset_dir / filename)

        make_app_icon(1024).save(RESOURCES / "AppIcon-transparent.png")
        make_menu_bar_icon().save(RESOURCES / "MenuBarIconTemplate.png")

        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(RESOURCES / "AppIcon.icns")],
            check=True,
        )


if __name__ == "__main__":
    save_icons()
