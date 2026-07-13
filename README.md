# font-file-installer

Install a whole folder of fonts (`.otf`, `.ttf`, `.woff`, `.woff2`) in one go — on macOS, Windows, or Linux.

## Get started (no technical background needed)

Go to the [**Releases page**](https://github.com/srihas115/font-file-installer/releases/latest) and download the file for your operating system:

| Your computer | Download | How to run it |
|---|---|---|
| **Windows** | `install-fonts.exe` | Double-click it. A window opens, let you pick your fonts folder, and installs them — no install step needed. |
| **Mac** | `Install-Fonts-macOS.zip` | Unzip it, then right-click **Install Fonts.app** → **Open** → **Open** (only needed the first time, since the app isn't from a paid Apple developer account). Drag your fonts folder onto the window, then click Install. |
| **Linux** | `install-fonts` | Right-click → Properties → **Allow executing file as program** (or run `chmod +x install-fonts` in a terminal), then double-click or run it. It'll open a folder picker. |

That's it — no Python, no Xcode, no command line required.

## For developers: command-line option

Requires only Python 3 (standard library — no installs needed).

```bash
python3 install_fonts.py [folder_path]
```

- Omit `folder_path` to get a native folder picker dialog (macOS uses AppleScript; Windows/Linux use Tk).
- Recursively finds font files and copies them into your user fonts directory:
  - macOS: `~/Library/Fonts`
  - Windows: `%LOCALAPPDATA%\Microsoft\Windows\Fonts` (also registers the font so it's usable immediately)
  - Linux: `~/.local/share/fonts` (runs `fc-cache -f` afterward)
- Skips files that already exist there (use `--force` to overwrite).
- Prints a summary of found/installed/skipped/failed fonts.

## For developers: Mac app source (drag-and-drop)

A native SwiftUI app lives in [`mac-app/`](mac-app/). Build it yourself with:

```bash
cd mac-app
./Scripts/build_app.sh
open "Install Fonts.app"
```

This is the same app published in Releases — the [`.github/workflows/release.yml`](.github/workflows/release.yml) workflow builds it (plus the Windows `.exe` and Linux binary via PyInstaller) automatically whenever a `v*` tag is pushed.

## License

MIT
