"""One-off: build vll-logo*.png + favicon from Cursor-stored Victoria Lush PNGs."""
from __future__ import annotations

from pathlib import Path

from PIL import Image


def knock_out_bg(im: Image.Image, tol: int = 36) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    refs = [
        im.getpixel((0, 0)),
        im.getpixel((w - 1, 0)),
        im.getpixel((0, h - 1)),
        im.getpixel((w - 1, h - 1)),
    ]
    bg = tuple(sum(x[i] for x in refs) // len(refs) for i in range(3))
    px = im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) < tol:
                px[x, y] = (255, 255, 255, 0)
    return im


def to_white_mark(im_rgba: Image.Image) -> Image.Image:
    w, h = im_rgba.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    po, pi = out.load(), im_rgba.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pi[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            al = int(max(0, min(255, a * (0.35 + 0.65 * lum))))
            if al < 8:
                continue
            po[x, y] = (255, 255, 255, al)
    return out


def maskable(sq512: Image.Image, size: int, inner_ratio: float = 0.72) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (24, 24, 24, 255))
    inner = int(size * inner_ratio)
    sm = sq512.resize((inner, inner), Image.Resampling.LANCZOS)
    off = (size - inner) // 2
    canvas.paste(sm, (off, off), sm)
    return canvas


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    assets = root / "assets"
    cursor_assets = Path(
        r"C:\Users\User\.cursor\projects\c-xampp-htdocs-victorialush-project-New-folder\assets"
    )
    src_light = cursor_assets / (
        "c__Users_User_AppData_Roaming_Cursor_User_workspaceStorage_"
        "36c07867ed7564f146bbf2ede1fd7218_images_image-a022a423-b0d1-4946-a4aa-356553a06e7a.png"
    )
    src_dark = cursor_assets / (
        "c__Users_User_AppData_Roaming_Cursor_User_workspaceStorage_"
        "36c07867ed7564f146bbf2ede1fd7218_images_logo-98a4227f-a659-4da0-a2ed-2291499cabed.png"
    )

    light = knock_out_bg(Image.open(src_light))
    mw = 640
    if light.width > mw:
        nh = int(light.height * mw / light.width)
        light = light.resize((mw, nh), Image.Resampling.LANCZOS)
    light.save(assets / "vll-logo-light.png", optimize=True)
    to_white_mark(light.copy()).save(assets / "vll-logo-white.png", optimize=True)
    light.copy().save(assets / "vll-logo.png", optimize=True)

    dark = Image.open(src_dark).convert("RGBA")
    w, h = dark.size
    side = min(int(w * 0.34), h)
    sq = dark.crop((0, 0, side, h)).resize((512, 512), Image.Resampling.LANCZOS)
    sq.save(assets / "vll-app-icon.png", optimize=True)
    dark_r = dark.resize(
        (mw, int(dark.height * mw / dark.width)), Image.Resampling.LANCZOS
    )
    dark_r.save(assets / "vll-logo-dark.png", optimize=True)

    sq.resize((48, 48), Image.Resampling.LANCZOS).save(root / "web" / "favicon.png", optimize=True)
    sq.resize((192, 192), Image.Resampling.LANCZOS).save(
        root / "web" / "icons" / "Icon-192.png", optimize=True
    )
    sq.resize((512, 512), Image.Resampling.LANCZOS).save(
        root / "web" / "icons" / "Icon-512.png", optimize=True
    )
    maskable(sq, 192).save(root / "web" / "icons" / "Icon-maskable-192.png", optimize=True)
    maskable(sq, 512).save(root / "web" / "icons" / "Icon-maskable-512.png", optimize=True)

    sms = Path(r"c:\xampp\htdocs\victorialush-project\New folder\SmSver1\images")
    sms.mkdir(parents=True, exist_ok=True)
    light.copy().save(sms / "logo.png", optimize=True)

    print("brand assets written under", assets)


if __name__ == "__main__":
    main()
