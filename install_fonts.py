#!/usr/bin/env python3
"""Install a folder of font files into the current user's font directory.

Works on macOS, Windows, and Linux using only the Python standard library.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

FONT_EXTENSIONS = {".otf", ".ttf", ".woff", ".woff2"}

PLATFORM = sys.platform  # "darwin", "win32", "linux", ...


def get_fonts_dir() -> Path:
    if PLATFORM == "darwin":
        return Path.home() / "Library" / "Fonts"
    if PLATFORM == "win32":
        import os
        local_appdata = os.environ.get("LOCALAPPDATA")
        if not local_appdata:
            print("Error: %LOCALAPPDATA% is not set. Cannot locate the user fonts folder.")
            sys.exit(1)
        return Path(local_appdata) / "Microsoft" / "Windows" / "Fonts"
    # Linux and other Unix-likes
    return Path.home() / ".local" / "share" / "fonts"


FONTS_DIR = get_fonts_dir()


def pick_folder_with_dialog() -> Path:
    if PLATFORM == "darwin":
        return _pick_folder_macos()
    return _pick_folder_tkinter()


def _pick_folder_macos() -> Path:
    script = 'POSIX path of (choose folder with prompt "Select a folder containing fonts to install")'
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print("Error: osascript not found.")
        sys.exit(1)
    except subprocess.CalledProcessError:
        # User likely cancelled the dialog
        print("No folder selected. Exiting.")
        sys.exit(0)

    path_str = result.stdout.strip()
    if not path_str:
        print("No folder selected. Exiting.")
        sys.exit(0)

    return Path(path_str)


def _pick_folder_tkinter() -> Path:
    try:
        import tkinter
        from tkinter import filedialog
    except ImportError:
        print(
            "Error: no folder was given and a folder picker isn't available "
            "(tkinter is not installed). Pass a folder path directly instead, e.g.:\n"
            "  python3 install_fonts.py /path/to/fonts"
        )
        sys.exit(1)

    root = tkinter.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    path_str = filedialog.askdirectory(title="Select a folder containing fonts to install")
    root.destroy()

    if not path_str:
        print("No folder selected. Exiting.")
        sys.exit(0)

    return Path(path_str)


def find_font_files(folder: Path):
    return sorted(
        p for p in folder.rglob("*")
        if p.is_file() and p.suffix.lower() in FONT_EXTENSIONS
    )


def register_font_windows(dest: Path) -> None:
    """Register a font with Windows so apps pick it up without a reboot."""
    import ctypes
    import winreg

    suffix = dest.suffix.lower()
    kind = "OpenType" if suffix == ".otf" else "TrueType"
    value_name = f"{dest.stem} ({kind})"

    try:
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows NT\CurrentVersion\Fonts",
            0,
            winreg.KEY_SET_VALUE,
        ) as key:
            winreg.SetValueEx(key, value_name, 0, winreg.REG_SZ, str(dest))
    except OSError:
        pass  # Font file is still copied even if registry entry fails

    gdi32 = ctypes.windll.gdi32
    gdi32.AddFontResourceW(str(dest))

    HWND_BROADCAST = 0xFFFF
    WM_FONTCHANGE = 0x001D
    ctypes.windll.user32.SendMessageW(HWND_BROADCAST, WM_FONTCHANGE, 0, 0)


def refresh_font_cache_linux() -> Optional[str]:
    """Run fc-cache so newly installed fonts show up immediately. Returns a warning, if any."""
    try:
        subprocess.run(
            ["fc-cache", "-f", str(FONTS_DIR)],
            capture_output=True,
            text=True,
            check=True,
        )
        return None
    except FileNotFoundError:
        return "fc-cache not found; fonts are installed but may not appear until you refresh manually."
    except subprocess.CalledProcessError as e:
        return f"fc-cache reported an error: {e.stderr.strip() or e}"


def main():
    parser = argparse.ArgumentParser(
        description="Install a folder of fonts into your user fonts directory."
    )
    parser.add_argument(
        "folder_path",
        nargs="?",
        default=None,
        help="Folder to scan for fonts. If omitted, a folder picker dialog opens.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite fonts that already exist in the fonts directory.",
    )
    args = parser.parse_args()

    if args.folder_path:
        folder = Path(args.folder_path).expanduser().resolve()
    else:
        folder = pick_folder_with_dialog().expanduser().resolve()

    if not folder.exists():
        print(f"Error: folder does not exist: {folder}")
        sys.exit(1)
    if not folder.is_dir():
        print(f"Error: not a folder: {folder}")
        sys.exit(1)

    try:
        FONTS_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        print(f"Error: could not create fonts directory {FONTS_DIR}: {e}")
        sys.exit(1)

    try:
        font_files = find_font_files(folder)
    except PermissionError as e:
        print(f"Error: permission denied while scanning {folder}: {e}")
        sys.exit(1)
    except OSError as e:
        print(f"Error: could not scan folder {folder}: {e}")
        sys.exit(1)

    if not font_files:
        print(f"No font files (.otf, .ttf, .woff, .woff2) found in {folder}.")
        sys.exit(0)

    installed = []
    skipped = []
    failed = []

    for font_path in font_files:
        dest = FONTS_DIR / font_path.name

        if dest.exists() and not args.force:
            skipped.append(font_path.name)
            continue

        try:
            shutil.copy2(font_path, dest)
            if PLATFORM == "win32" and dest.suffix.lower() in (".otf", ".ttf"):
                register_font_windows(dest)
            installed.append(font_path.name)
        except PermissionError as e:
            failed.append((font_path.name, f"permission denied: {e}"))
        except OSError as e:
            failed.append((font_path.name, str(e)))

    warning = None
    if installed and PLATFORM not in ("darwin", "win32"):
        warning = refresh_font_cache_linux()

    print()
    print("=== Font Installation Summary ===")
    print(f"Fonts found:     {len(font_files)}")
    print(f"Installed:       {len(installed)}")
    print(f"Skipped (exist): {len(skipped)}")
    print(f"Failed:          {len(failed)}")

    if skipped:
        print()
        print("Already installed (use --force to overwrite):")
        for name in skipped:
            print(f"  - {name}")

    if failed:
        print()
        print("Failed to install:")
        for name, reason in failed:
            print(f"  - {name}: {reason}")

    if warning:
        print()
        print(f"Warning: {warning}")

    print()
    if installed:
        if PLATFORM == "win32":
            print("Done. Fonts are registered and ready to use immediately.")
        elif PLATFORM == "darwin":
            print("Done. macOS will pick up the new fonts automatically.")
        else:
            print("Done. Fonts installed to ~/.local/share/fonts.")

    if getattr(sys, "frozen", False) and PLATFORM == "win32":
        # Keep the console window open when double-clicked from Explorer.
        input("\nPress Enter to exit...")


if __name__ == "__main__":
    main()
