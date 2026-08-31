"""Generate V+ app icon (black on white) for desktop, Flutter assets, and Android."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
TEXT = "V+"
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)

MIPMAP_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

FOREGROUND_SIZES = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ("arialbd.ttf", "segoeuib.ttf", "arial.ttf", "calibrib.ttf"):
        path = Path(r"C:\Windows\Fonts") / name
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def _draw_mark(
    draw: ImageDraw.ImageDraw,
    size: int,
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
    fill: tuple[int, int, int, int],
) -> None:
    bbox = draw.textbbox((0, 0), TEXT, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (size - tw) // 2 - bbox[0]
    y = (size - th) // 2 - bbox[1] - max(0, int(size * 0.03))
    draw.text((x, y), TEXT, fill=fill, font=font)


def render_square(size: int, *, transparent: bool = False) -> Image.Image:
    bg = (255, 255, 255, 0 if transparent else 255)
    img = Image.new("RGBA", (size, size), bg)
    draw = ImageDraw.Draw(img)
    font_size = max(7, int(size * 0.44))
    font = _load_font(font_size)
    _draw_mark(draw, size, font, (0, 0, 0, 255))
    return img


def main() -> int:
    ASSETS.mkdir(parents=True, exist_ok=True)

    master = render_square(256)
    master.save(
        ASSETS / "app.ico",
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
    )
    render_square(512).save(ASSETS / "app.png", format="PNG")
    render_square(512).save(ASSETS / "app_icon.png", format="PNG")

    for folder, size in MIPMAP_SIZES.items():
        out_dir = ANDROID_RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        render_square(size).save(out_dir / "ic_launcher.png", format="PNG")

    for folder, size in FOREGROUND_SIZES.items():
        out_dir = ANDROID_RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        render_square(size, transparent=True).save(
            out_dir / "ic_launcher_foreground.png",
            format="PNG",
        )

    print(f"Wrote {ASSETS / 'app.ico'}, {ASSETS / 'app.png'}")
    print(f"Wrote Android launcher icons under {ANDROID_RES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
