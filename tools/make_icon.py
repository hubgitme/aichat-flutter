#!/usr/bin/env python3
"""Generate Android launcher icons for aichat-flutter from the web icon.

Source: ~/workspace/review/aichat-sync/jsonedits/icons/icon-512.png
(512x512 RGBA: blue #4F46E5 rounded square + white chat bubble,
transparent corners).

Outputs under <repo>/android-icon/:
  mipmap-mdpi/ic_launcher.png      48x48
  mipmap-hdpi/ic_launcher.png      72x72
  mipmap-xhdpi/ic_launcher.png     96x96
  mipmap-xxhdpi/ic_launcher.png    144x144
  mipmap-xxxhdpi/ic_launcher.png   192x192
  mipmap-xxxhdpi/ic_launcher_foreground.png  432x432 (adaptive icon:
    bubble artwork scaled to the 72dp safe zone, centred on a transparent
    108dp canvas)
  res/values/ic_launcher_background.xml  (solid #4F46E5)
  README.md
"""
import os
import sys

from PIL import Image

SRC = os.path.expanduser(
    "~/workspace/review/aichat-sync/jsonedits/icons/icon-512.png")
OUT = os.path.expanduser("~/workspace/review/aichat-flutter/android-icon")
BLUE = (79, 70, 229)  # #4F46E5 — sampled from the icon itself

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    assert src.size == (512, 512), f"unexpected source size {src.size}"
    # Sanity: the dominant opaque colour must be the sampled blue.
    corner = src.getpixel((256, 20))
    assert corner[:3] == BLUE, f"unexpected blue {corner}"

    for d, size in SIZES.items():
        dpath = os.path.join(OUT, d)
        os.makedirs(dpath, exist_ok=True)
        icon = src.resize((size, size), Image.LANCZOS)
        icon.save(os.path.join(dpath, "ic_launcher.png"))

    # Adaptive-icon foreground: 108dp canvas (432px at xxxhdpi), artwork
    # inside the 72dp safe zone => 288px, centred.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    art = src.resize((288, 288), Image.LANCZOS)
    fg.alpha_composite(art, (72, 72))
    fg.save(os.path.join(OUT, "mipmap-xxxhdpi", "ic_launcher_foreground.png"))

    values = os.path.join(OUT, "res", "values")
    os.makedirs(values, exist_ok=True)
    with open(
        os.path.join(values, "ic_launcher_background.xml"),
        "w",
        encoding="utf-8",
    ) as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            '    <!-- Background of the adaptive launcher icon: the web '
            "icon's blue -->\n"
            '    <color name="ic_launcher_background">#4F46E5</color>\n'
            "</resources>\n"
        )

    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8") as f:
        f.write(
            "# Launcher icon (from the web version)\n\n"
            "Generated from the AICHAT web PWA icon "
            "(`icons/icon-512.png` in the jsonedits web project): blue "
            "`#4F46E5` rounded square with a white\n"
            "chat bubble, by `tools/make_icon.py`.\n\n"
            "The CI workflow re-scaffolds `android/` fresh on every build, so\n"
            "these files live here and the workflow copies them over the\n"
            "scaffolded tree (see the `Scaffold Android platform` step):\n\n"
            "- `mipmap-*/ic_launcher.png` → "
            "`android/app/src/main/res/mipmap-*/ic_launcher.png`\n"
            "- `mipmap-xxxhdpi/ic_launcher_foreground.png` → "
            "`android/app/src/main/res/mipmap-xxxhdpi/`\n"
            "- `res/values/ic_launcher_background.xml` → "
            "`android/app/src/main/res/values/`\n\n"
            "Regenerate with: `python3 tools/make_icon.py`\n"
        )
    print("icons written to", OUT)
    for root, _dirs, files in sorted(os.walk(OUT)):
        for name in sorted(files):
            p = os.path.join(root, name)
            print(" ", os.path.relpath(p, OUT))


if __name__ == "__main__":
    sys.exit(main())
