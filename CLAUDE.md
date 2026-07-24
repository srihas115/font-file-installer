# CLAUDE.md

Guidance for Claude Code (or any agent) working in this repository.

## What this repo is

A small cross-platform tool that installs font files into the current user's OS font
directory. One idea, three shipped artifacts:

- **`install_fonts.py`** — a dependency-free Python 3 script (stdlib only). This same file
  is frozen via PyInstaller into the Windows `.exe` and Linux binary released on GitHub.
- **`mac-app/`** — a native SwiftUI app (macOS 13+, Swift Package Manager, no Xcode
  project) that wraps the same idea behind a drag-and-drop window.
- **`.github/workflows/release.yml`** — builds all three artifacts in parallel and
  publishes them to a GitHub Release whenever a `v*` tag is pushed. Nothing is built on
  plain commits to `main`.

Target audience is explicitly non-technical (see README) — prefer solutions that need no
setup, no accounts, and no extra installs over ones that do.

## Core flow (shared across platforms)

1. Get a source: a local folder, a `.zip`, or (since the Google Fonts feature) a family
   name resolved and downloaded from Google Fonts into a temp folder.
2. Recursively find `.otf`/`.ttf`/`.woff`/`.woff2` files in that folder.
3. Copy each into the user's font directory, skipping existing files unless `--force`/
   "Overwrite" is set.
4. Do whatever OS-specific step makes the font usable without a reboot.

Key functions to know, by platform:

- **Python** (`install_fonts.py`): `get_fonts_dir()`, `find_font_files()`,
  `register_font_windows()` (registry entry + `AddFontResourceW` + `WM_FONTCHANGE`),
  `refresh_font_cache_linux()` (`fc-cache -f`), `main()`.
- **Swift** (`mac-app/Sources/InstallFonts/FontInstaller.swift`):
  `FontInstaller.install(from:force:)` is the core entry point — it accepts any folder
  URL (or a `.zip`, auto-extracted via `resolveSourceDirectory`) and returns an
  `InstallResult` (found/installed/skipped/failed). Reuse this function unchanged for any
  new source of fonts rather than duplicating the copy/skip/force logic.

## Google Fonts one-click install

Both platforms can install directly from Google's font catalog with **no API key**:

- Catalog listing: `GET https://fonts.google.com/metadata/fonts` (strip the leading
  `)]}'` XSSI-protection line before parsing JSON) — the same JSON the fonts.google.com
  website itself loads. Cached locally (~7 day TTL) since it's a few MB.
- Font files: `GET https://fonts.googleapis.com/css2?family=<Name>:wght@400;700&display=swap`
  — with the default/non-browser User-Agent both `urllib.request` and `URLSession` send,
  this returns raw **TTF** files (not WOFF2), which is what an OS font directory needs.
  No User-Agent spoofing required.
- Both endpoints are **unofficial** (not versioned/documented by Google) — code that uses
  them should degrade gracefully (fall back to a stale cache, clear error message) rather
  than assume perfect uptime or response-shape stability.
- Licensing is a non-issue: nearly all Google Fonts are OFL-1.1/Apache-2.0, which
  explicitly permit local install/redistribution.

Implementation split:

- Python: `fetch_google_catalog()`, `parse_google_spec()`, `build_css2_url()`,
  `parse_css2()`, `resolve_google_font_files()`, `download_google_fonts()`,
  `prepare_google_fonts_folder()` in `install_fonts.py`, wired up via the `--google` CLI
  flag. Everything downloaded lands in a temp dir that's fed into the existing
  `find_font_files()`/copy loop unchanged, then cleaned up in `main()`'s `finally` block.
- Swift: `GoogleFontsCatalog.swift` (networking/parsing/caching, no UI) and
  `GoogleFontsView.swift` (search/browse/install UI), wired into `ContentView.swift` via
  a segmented `Picker` ("From Folder/Zip" vs. "Google Fonts"). Downloaded fonts land in a
  temp dir passed straight into `FontInstaller.install(from:force:)` unchanged.
  `InstallResultsView.swift` holds the installed/skipped/failed summary view shared by
  both the folder/zip flow and the Google Fonts flow.

## Building and running locally

```bash
# Python / CLI (all platforms)
python3 install_fonts.py [folder_path]
python3 install_fonts.py [font_zip_path]
python3 install_fonts.py --google Roboto "Open Sans:700,400i"
python3 -m unittest discover -s tests

# macOS app
cd mac-app
./Scripts/build_app.sh
open "Install Fonts.app"
```

The Python test suite covers pure logic and safe source resolution. For changes that
actually install fonts, also verify manually by running the script/app and checking
installed fonts show up (Font Book on macOS, Windows font settings, or `fc-list` on Linux).

## Conventions

- Keep `install_fonts.py` dependency-free (stdlib only) — no `pip install` step exists
  anywhere in the release pipeline for it.
- No App Sandbox/entitlements exist in the macOS app (`mac-app/Resources/Info.plist` has
  no `com.apple.security.*` keys) — networking works out of the box; don't add
  entitlements unless a specific new capability genuinely requires it.
- No new SPM dependencies unless truly necessary — `Package.swift` currently declares
  none.
