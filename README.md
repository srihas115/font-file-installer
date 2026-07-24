# font-file-installer

Install a whole folder or `.zip` file of fonts (`.otf`, `.ttf`, `.woff`, `.woff2`) in one go — on macOS, Windows, or Linux.

## Get started

Go to the [**Releases page**](https://github.com/srihas115/font-file-installer/releases/latest) and download the file for your operating system:

| Your computer | Download | How to run it |
|---|---|---|
| **Windows** | `install-fonts.exe` | Double-click it. A window opens, let you pick your fonts folder, and installs them — no install step needed. |
| **Mac** | `Install-Fonts-macOS.zip` | Unzip it and open **Install Fonts.app**. If macOS blocks it, see [macOS Installation](#macos-installation) below — it's a one-time, one-command fix. Then drag your fonts folder onto the window and click Install. |
| **Linux** | `install-fonts` | Right-click → Properties → **Allow executing file as program** (or run `chmod +x install-fonts` in a terminal), then double-click or run it. It'll open a folder picker. |

## macOS Installation

When you unzip `Install-Fonts-macOS.zip` and try to open **Install Fonts.app**, macOS may show:

> **"Install Fonts.app" is damaged and can't be opened. You should move it to the Trash.**

**Your download is not actually broken.** This message shows up because the app isn't signed with a paid Apple Developer certificate ($99/year — this project doesn't have one). macOS quarantines any unsigned app downloaded from a browser and, instead of a clear "unidentified developer" warning, newer versions of macOS show this scarier "damaged" message for unsigned apps. It's misleading, but the fix is quick:

1. Open **Terminal** (Spotlight → search "Terminal").
2. Type `xattr -cr "` (with the trailing space and quote), then drag **Install Fonts.app** from Finder into the Terminal window — this fills in the correct path automatically. Add a closing `"` and press Enter:
   ```bash
   xattr -cr "/Users/you/Downloads/Install Fonts.app"
   ```
3. Try opening the app again.

If you still see a prompt at this point, it'll be the milder **"Install Fonts.app" is from an unidentified developer** warning rather than "damaged." To get past that one:

1. **Right-click** (or Control-click) **Install Fonts.app** and choose **Open** — don't double-click.
2. In the dialog that appears, click **Open** to confirm.

You only need to do this once per download; after that, the app opens normally like any other.

## For developers: command-line option

Requires only Python 3 (standard library — no installs needed).

```bash
python3 install_fonts.py [folder_or_zip_path]
python3 install_fonts.py --check-updates
python3 install_fonts.py --fontsource Roboto
```

- Omit `folder_or_zip_path` to get a native folder picker dialog (macOS uses AppleScript; Windows/Linux use Tk).
- Pass a `.zip` file to extract and install any fonts inside it.
- Recursively finds font files and copies them into your user fonts directory:
  - macOS: `~/Library/Fonts`
  - Windows: `%LOCALAPPDATA%\Microsoft\Windows\Fonts` (also registers the font so it's usable immediately)
  - Linux: `~/.local/share/fonts` (runs `fc-cache -f` afterward)
- Skips files that already exist there (use `--force` to overwrite).
- Checks GitHub Releases for a newer version with `--check-updates`.
- Prints a summary of found/installed/skipped/failed fonts.

### Installing straight from Fontsource

```bash
python3 install_fonts.py --fontsource Roboto "Open Sans:400,400i,700"
```

- Pass one or more Fontsource family names or ids instead of a folder.
- Add `:WEIGHTS` after a family to pick specific weights (default is `400,700`); append `i` to a weight for the italic cut.
- This uses Fontsource's documented API at `https://api.fontsource.org/v1/fonts`.

### Installing straight from Google Fonts

```bash
python3 install_fonts.py --google Roboto "Open Sans:700,400i"
```

- Pass one or more family names instead of a folder. No API key, account, or extra install needed.
- Add `:WEIGHTS` after a family to pick specific weights (default is `400,700`); append `i` to a weight for the italic cut, e.g. `"Merriweather:400,400i,700"`.
- The catalog of available family names is cached locally for a week; pass `--refresh-catalog` to force a fresh copy.
- This talks to the same public endpoints fonts.google.com's own website uses (no official, versioned API) — if a family name doesn't match, it'll suggest close matches.

## For developers: Mac app source (drag-and-drop)

A native SwiftUI app lives in [`mac-app/`](mac-app/). Build it yourself with:

```bash
cd mac-app
./Scripts/build_app.sh
open "Install Fonts.app"
```

Use the **Check for updates** button in the app to check GitHub Releases for a newer download. Use the **Fontsource** tab to search and install fonts from Fontsource.

This is the same app published in Releases — the [`.github/workflows/release.yml`](.github/workflows/release.yml) workflow builds it (plus the Windows `.exe` and Linux binary via PyInstaller) automatically whenever a `v*` tag is pushed.

## License

MIT

## How this works

This repo has two independent ways to install fonts: scan a folder or `.zip` file for `.otf`/`.ttf`/`.woff`/`.woff2` files and copy each one into the current user's font directory, skipping anything already installed unless told to overwrite.

- **[`install_fonts.py`](install_fonts.py)** — the core implementation, a single Python script using only the standard library. It detects the OS (`sys.platform`) and adjusts three things per platform: how it opens a folder picker (AppleScript on macOS, Tk on Windows/Linux), where the fonts directory lives (`~/Library/Fonts`, `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, or `~/.local/share/fonts`), and what extra step is needed after copying (Windows registry entry + `AddFontResource` call so the font works without a reboot; `fc-cache -f` on Linux to refresh the font cache). This same script is also what gets frozen into the Windows `.exe` and Linux binary — see below.
- **[`mac-app/`](mac-app/)** — a native SwiftUI app that wraps the same install logic (`FontInstaller.swift` mirrors the scan/copy behavior of `install_fonts.py`) behind a window with a drag-and-drop target and a "Choose Folder" button, built with Swift Package Manager rather than a full Xcode project.

Nothing here needs installing to build, test, or run from source — the Python script only needs a Python 3 interpreter, and the Swift app only needs Xcode's Command Line Tools (`swift build`).

Run the Python unit tests with:

```bash
python3 -m unittest discover -s tests
```

**Getting pre-built downloads to the Releases page** is handled by [`.github/workflows/release.yml`](.github/workflows/release.yml), a GitHub Actions workflow that runs whenever a tag matching `v*` is pushed (e.g. `git tag v1.0.0 && git push origin v1.0.0`). It runs three jobs in parallel — freezing `install_fonts.py` into a standalone `.exe` on a Windows runner and a standalone binary on a Linux runner (both via PyInstaller, so end users don't need Python installed), and building/zipping the SwiftUI `.app` on a macOS runner — then a fourth job collects all three artifacts and publishes them as a GitHub Release. That's why the Releases page stays empty until a version tag is pushed: nothing runs on a plain commit to `main`.
