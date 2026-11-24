# Launcher icon (from the web version)

Generated from the AICHAT web PWA icon (`icons/icon-512.png` in the jsonedits web project): blue `#4F46E5` rounded square with a white
chat bubble, by `tools/make_icon.py`.

The CI workflow re-scaffolds `android/` fresh on every build, so
these files live here and the workflow copies them over the
scaffolded tree (see the `Scaffold Android platform` step):

- `mipmap-*/ic_launcher.png` → `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `mipmap-xxxhdpi/ic_launcher_foreground.png` → `android/app/src/main/res/mipmap-xxxhdpi/`
- `res/values/ic_launcher_background.xml` → `android/app/src/main/res/values/`

Regenerate with: `python3 tools/make_icon.py`
