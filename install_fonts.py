#!/usr/bin/env python3
"""Install a folder of font files into ~/Library/Fonts."""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

FONT_EXTENSIONS = {".otf", ".ttf", ".woff", ".woff2"}
FONTS_DIR = Path.home() / "Library" / "Fonts"


def pick_folder_with_dialog() -> Path:
    script = 'POSIX path of (choose folder with prompt "Select a folder containing fonts to install")'
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print("Error: osascript not found. This tool requires macOS.")
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


def find_font_files(folder: Path):
    return sorted(
        p for p in folder.rglob("*")
        if p.is_file() and p.suffix.lower() in FONT_EXTENSIONS
    )


def main():
    parser = argparse.ArgumentParser(
        description="Install a folder of fonts into ~/Library/Fonts."
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
        help="Overwrite fonts that already exist in ~/Library/Fonts.",
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
            installed.append(font_path.name)
        except PermissionError as e:
            failed.append((font_path.name, f"permission denied: {e}"))
        except OSError as e:
            failed.append((font_path.name, str(e)))

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

    print()
    if installed:
        print("Done. macOS will pick up the new fonts automatically.")


if __name__ == "__main__":
    main()
