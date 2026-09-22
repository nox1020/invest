"""Generate invest app icons from assets/invest.png for desktop and Android."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
MASTER_NAME = "invest.png"
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


def load_master() -> Image.Image:
    path = ASSETS / MASTER_NAME
    if not path.exists():
        raise FileNotFoundError(f"Missing master icon: {path}")
    img = Image.open(path).convert("RGBA")
    if img.size != (1024, 1024):
        img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    return img


def main() -> int:
    ASSETS.mkdir(parents=True, exist_ok=True)
    master = load_master()

    ico_images = [master.resize((s, s), Image.Resampling.LANCZOS) for s in ICO_SIZES]
    ico_images[-1].save(
        ASSETS / "app.ico",
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=ico_images[:-1],
    )
    master.resize((512, 512), Image.Resampling.LANCZOS).save(
        ASSETS / "app.png", format="PNG"
    )

    for folder, size in MIPMAP_SIZES.items():
        out_dir = ANDROID_RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            out_dir / "ic_launcher.png", format="PNG"
        )

    for folder, size in FOREGROUND_SIZES.items():
        out_dir = ANDROID_RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            out_dir / "ic_launcher_foreground.png", format="PNG"
        )

    print(f"Wrote {ASSETS / 'app.ico'}, {ASSETS / 'app.png'} from {MASTER_NAME}")
    print(f"Wrote Android launcher icons under {ANDROID_RES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
