# font-file-installer

Install a whole folder or `.zip` file of fonts (`.otf`, `.ttf`, `.woff`, `.woff2`) in one go — on macOS, Windows, or Linux.

## Get started

Go to the [**Releases page**](https://github.com/srihas115/font-file-installer/releases/latest) and download the file for your operating system:

| Your computer | Download | How to run it |
|---|---|---|
| **Windows** | `Font-Installer-Windows.exe` | Double-click it. Like the Mac app, use the segmented tabs to install from a folder/zip, browse Google Fonts or Fontsource, or manage installed fonts — no install step needed. |
| **Mac** | `Font Installer.zip` | Unzip it and open **Font Installer.app**. If macOS blocks it, see [macOS Installation](#macos-installation) below — it's a one-time, one-command fix. Then drag your fonts folder onto the window and click Install. |
| **Linux** | `install-fonts` | Right-click → Properties → **Allow executing file as program** (or run `chmod +x install-fonts` in a terminal), then double-click or run it. It'll open a folder picker. |

## macOS Installation

When you unzip `Font Installer.zip` and try to open **Font Installer.app**, macOS may show:

> **"Font Installer.app" is damaged and can't be opened. You should move it to the Trash.**

**Your download is not actually broken.** This message shows up because the app isn't signed with a paid Apple Developer certificate ($99/year — this project doesn't have one). macOS quarantines any unsigned app downloaded from a browser and, instead of a clear "unidentified developer" warning, newer versions of macOS show this scarier "damaged" message for unsigned apps. It's misleading, but the fix is quick:

1. Open **Terminal** (Spotlight → search "Terminal").
2. Type `xattr -cr "` (with the trailing space and quote), then drag **Font Installer.app** from Finder into the Terminal window — this fills in the correct path automatically. Add a closing `"` and press Enter:
   ```bash
   xattr -cr "/Users/you/Downloads/Font Installer.app"
   ```
3. Try opening the app again.

If you still see a prompt at this point, it'll be the milder **"Font Installer.app" is from an unidentified developer** warning rather than "damaged." To get past that one:

1. **Right-click** (or Control-click) **Font Installer.app** and choose **Open** — don't double-click.
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

## For developers: native desktop apps

The Mac and Windows apps provide the same core workflow: install from a folder or ZIP, browse Google Fonts and Fontsource, check for updates, and view/remove fonts installed for the current user.

### macOS app

The native SwiftUI app lives in [`mac-app/`](mac-app/). Build it with:

```bash
cd mac-app
./Scripts/build_app.sh
open "Font Installer.app"
```

Use the segmented mode picker to switch between folder/ZIP installs, Google Fonts, Fontsource, and installed fonts.

### Refreshing the bundled Google Fonts popularity list

The Mac app ships with `mac-app/Resources/google-fonts-popularity.json` so **Most Popular** works for everyone without requiring a Google API key. To refresh that bundled ranking from Google's official Web Fonts Developer API, run:

```bash
cd mac-app
GOOGLE_FONTS_API_KEY="your_key_here" ./Scripts/update_google_fonts_popularity.py
```

Commit the updated `Resources/google-fonts-popularity.json` file. Do not commit your API key.

### Windows app

The native Windows app lives in [`windows-app-csharp/`](windows-app-csharp/) and is implemented with C#/.NET 8 WPF. It uses the same compact, segmented layout as the Mac app. Build a self-contained release executable on Windows with:

```powershell
dotnet publish .\windows-app-csharp\FontInstaller.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -o .\dist\windows
Start-Process .\dist\windows\Font-Installer-Windows.exe
```

This is the same app published in Releases — the [`.github/workflows/release.yml`](.github/workflows/release.yml) workflow builds the C# Windows `.exe`, Linux binary, and macOS app automatically whenever a `v*` tag is pushed.

## License

MIT

## How this works

This repo has three implementations of the same font-install flow: scan a folder or `.zip` file for `.otf`/`.ttf`/`.woff`/`.woff2` files, copy each into the current user's font directory, and skip existing files unless asked to overwrite.

- **[`install_fonts.py`](install_fonts.py)** — a dependency-free command-line tool for all platforms and the source of the Linux binary. It detects the OS, installs into the correct user font directory, registers fonts on Windows, and refreshes the Linux cache.
- **[`mac-app/`](mac-app/)** — a native SwiftUI app for macOS 13+.
- **[`windows-app-csharp/`](windows-app-csharp/)** — a native C#/.NET 8 WPF app for Windows. It registers `.ttf` and `.otf` files with Windows so they are ready to use immediately.

The Python CLI needs Python 3, the Mac app needs Xcode Command Line Tools, and the Windows app needs the .NET 8 SDK to build from source. Release downloads are self-contained and need none of these tools.

Run the Python unit tests with:

```bash
python3 -m unittest discover -s tests
```

**Getting pre-built downloads to the Releases page** is handled by [`.github/workflows/release.yml`](.github/workflows/release.yml), a GitHub Actions workflow that runs whenever a tag matching `v*` is pushed (e.g. `git tag v1.0.0 && git push origin v1.0.0`). It builds the self-contained C# Windows executable, the PyInstaller Linux binary, and the zipped SwiftUI macOS app, then publishes all three to the GitHub Release.
