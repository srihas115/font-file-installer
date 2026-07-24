#!/usr/bin/env python3
"""Install a folder of font files into the current user's font directory.

Works on macOS, Windows, and Linux using only the Python standard library.
"""

import argparse
import difflib
import importlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Optional

FONT_EXTENSIONS = {".otf", ".ttf", ".woff", ".woff2"}

PLATFORM = sys.platform  # "darwin", "win32", "linux", ...

USER_AGENT = "font-file-installer/1.0"
GOOGLE_METADATA_URL = "https://fonts.google.com/metadata/fonts"
GOOGLE_CSS_URL = "https://fonts.googleapis.com/css2"
CATALOG_CACHE_TTL_SECONDS = 7 * 24 * 3600
APP_VERSION = "1.1.0"
GITHUB_LATEST_RELEASE_API = "https://api.github.com/repos/srihas115/font-file-installer/releases/latest"
GITHUB_RELEASES_URL = "https://github.com/srihas115/font-file-installer/releases/latest"


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


def get_cache_dir() -> Path:
    import os

    if PLATFORM == "darwin":
        base = Path.home() / "Library" / "Caches"
    elif PLATFORM == "win32":
        base = Path(os.environ.get("LOCALAPPDATA", str(Path.home())))
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    return base / "font-file-installer"


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


def resolve_source_directory(source: Path):
    """Return a directory to scan, extracting a .zip file to a temp directory when needed."""
    if source.suffix.lower() != ".zip":
        return source, None

    temp_dir = Path(tempfile.mkdtemp(prefix="install_fonts_zip_"))
    try:
        with zipfile.ZipFile(source) as archive:
            _extract_zip_safely(archive, temp_dir)
    except (OSError, ValueError, zipfile.BadZipFile):
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise

    return temp_dir, temp_dir


def _extract_zip_safely(archive: zipfile.ZipFile, dest_dir: Path) -> None:
    dest_root = dest_dir.resolve()
    for member in archive.infolist():
        member_path = dest_root / member.filename
        try:
            member_path.resolve().relative_to(dest_root)
        except ValueError as e:
            raise ValueError(f"zip file contains an unsafe path: {member.filename}") from e
    archive.extractall(dest_root)


def register_font_windows(dest: Path) -> None:
    """Register a font with Windows so apps pick it up without a reboot."""
    import ctypes

    winreg = importlib.import_module("winreg")
    open_key = getattr(winreg, "OpenKey")
    set_value = getattr(winreg, "SetValueEx")
    hkey_current_user = getattr(winreg, "HKEY_CURRENT_USER")
    key_set_value = getattr(winreg, "KEY_SET_VALUE")
    reg_sz = getattr(winreg, "REG_SZ")

    suffix = dest.suffix.lower()
    kind = "OpenType" if suffix == ".otf" else "TrueType"
    value_name = f"{dest.stem} ({kind})"

    try:
        with open_key(
            hkey_current_user,
            r"Software\Microsoft\Windows NT\CurrentVersion\Fonts",
            0,
            key_set_value,
        ) as key:
            set_value(key, value_name, 0, reg_sz, str(dest))
    except OSError:
        pass  # Font file is still copied even if registry entry fails

    windll = getattr(ctypes, "windll")
    gdi32 = windll.gdi32
    gdi32.AddFontResourceW(str(dest))

    HWND_BROADCAST = 0xFFFF
    WM_FONTCHANGE = 0x001D
    windll.user32.SendMessageW(HWND_BROADCAST, WM_FONTCHANGE, 0, 0)


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


def _fetch_url(url: str, timeout: float = 15, retries: int = 1, backoff: float = 1.0) -> bytes:
    """GET a URL with a small retry/backoff, identifying ourselves with a real User-Agent."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    last_error: Optional[Exception] = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, OSError) as e:
            last_error = e
            if attempt < retries:
                time.sleep(backoff)
    assert last_error is not None
    raise last_error


def normalize_version(version: str) -> str:
    return version.strip().lstrip("vV")


def version_parts(version: str):
    parts = []
    for token in re.split(r"[.-]", normalize_version(version)):
        if not token:
            continue
        if token.isdigit():
            parts.append(int(token))
        else:
            break
    return tuple(parts or [0])


def is_newer_version(latest: str, current: str) -> bool:
    latest_parts = version_parts(latest)
    current_parts = version_parts(current)
    length = max(len(latest_parts), len(current_parts))
    latest_parts += (0,) * (length - len(latest_parts))
    current_parts += (0,) * (length - len(current_parts))
    return latest_parts > current_parts


def fetch_latest_release_info(fetch_url=_fetch_url) -> dict:
    raw = fetch_url(GITHUB_LATEST_RELEASE_API, timeout=10, retries=0).decode("utf-8")
    release = json.loads(raw)
    tag_name = release.get("tag_name")
    if not tag_name:
        raise RuntimeError("GitHub returned a release without a tag name.")
    return {
        "tag_name": tag_name,
        "html_url": release.get("html_url") or GITHUB_RELEASES_URL,
        "name": release.get("name") or tag_name,
    }


def print_update_status(current_version: str = APP_VERSION, fetch_url=_fetch_url) -> int:
    try:
        release = fetch_latest_release_info(fetch_url=fetch_url)
    except (RuntimeError, json.JSONDecodeError, UnicodeDecodeError, urllib.error.URLError, OSError) as e:
        print(f"Could not check for updates: {e}")
        return 1

    latest = release["tag_name"]
    print(f"Current version: {current_version}")
    print(f"Latest release:  {latest}")

    if is_newer_version(latest, current_version):
        print(f"Update available: {release['html_url']}")
    else:
        print("You're up to date.")

    return 0


def fetch_google_catalog(force_refresh: bool = False) -> dict:
    """Fetch (and cache) the Google Fonts family catalog.

    Uses the public JSON endpoint fonts.google.com itself relies on (no API key
    required); this is an unofficial endpoint, so failures fall back to a stale
    cache when one exists rather than breaking the whole tool.
    """
    cache_path = get_cache_dir() / "google-fonts-metadata.json"

    if not force_refresh and cache_path.exists():
        age = time.time() - cache_path.stat().st_mtime
        if age < CATALOG_CACHE_TTL_SECONDS:
            try:
                return json.loads(cache_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass

    try:
        raw = _fetch_url(GOOGLE_METADATA_URL).decode("utf-8")
    except (urllib.error.URLError, OSError) as e:
        if cache_path.exists():
            try:
                return json.loads(cache_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass
        raise RuntimeError(f"could not reach the Google Fonts catalog: {e}") from e

    # The response is prefixed with a `)]}'` XSSI-protection line; strip it before parsing.
    if raw.startswith(")]}'"):
        raw = raw.split("\n", 1)[1] if "\n" in raw else "{}"

    catalog = json.loads(raw)

    try:
        cache_dir = get_cache_dir()
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(catalog), encoding="utf-8")
    except OSError:
        pass  # Caching is a nice-to-have; a failure here shouldn't break the fetch.

    return catalog


def parse_google_spec(spec: str):
    """Parse a `--google` argument like "Roboto" or "Open Sans:700,400i" into
    (family_name, [(weight, italic), ...]). Weights default to 400/700 non-italic."""
    if ":" in spec:
        family, weights_part = spec.split(":", 1)
    else:
        family, weights_part = spec, ""
    family = family.strip()

    weights = []
    for token in weights_part.split(","):
        token = token.strip()
        if not token:
            continue
        italic = token.lower().endswith("i")
        if italic:
            token = token[:-1]
        try:
            weights.append((int(token), italic))
        except ValueError:
            print(f"Warning: ignoring invalid weight '{token}' for '{family}'.")

    if not weights:
        weights = [(400, False), (700, False)]

    return family, weights


def build_css2_url(family: str, weights) -> str:
    # Percent-encode the family name only (keeping a literal "+" for spaces), then build
    # the query string by hand: urlencode() would re-escape the ":;,@" characters that
    # the css2 API expects to see literally.
    family_param = urllib.parse.quote(family.replace(" ", "+"), safe="+")
    has_italic = any(italic for _, italic in weights)

    if has_italic:
        pairs = sorted(set(weights), key=lambda w: (w[1], w[0]))
        axis = ";".join(f"{1 if italic else 0},{weight}" for weight, italic in pairs)
        family_axis = f"{family_param}:ital,wght@{axis}"
    else:
        distinct_weights = sorted({weight for weight, _ in weights})
        family_axis = f"{family_param}:wght@{';'.join(str(w) for w in distinct_weights)}"

    return f"{GOOGLE_CSS_URL}?family={family_axis}&display=swap"


FONT_FACE_RE = re.compile(r"@font-face\s*\{([^}]*)\}", re.DOTALL)


def parse_css2(css_text: str):
    """Parse css2 API output into a list of (weight, italic, file_url) tuples."""
    entries = []
    for block in FONT_FACE_RE.findall(css_text):
        weight_match = re.search(r"font-weight:\s*(\d+)", block)
        style_match = re.search(r"font-style:\s*(\w+)", block)
        url_match = re.search(r"url\((https://fonts\.gstatic\.com/[^)]+)\)", block)
        if not (weight_match and url_match):
            continue
        weight = int(weight_match.group(1))
        italic = bool(style_match and style_match.group(1) == "italic")
        entries.append((weight, italic, url_match.group(1)))
    return entries


def resolve_google_font_files(family: str, weights):
    """Fetch the css2 stylesheet for `family`/`weights` and return the font files it references."""
    css_text = _fetch_url(build_css2_url(family, weights)).decode("utf-8")
    return parse_css2(css_text)


def download_google_fonts(family: str, entries, dest_dir: Path):
    """Download resolved (weight, italic, url) entries into dest_dir. Returns the files written."""
    downloaded = []
    safe_family = re.sub(r"[^A-Za-z0-9]+", "", family) or "Font"
    for weight, italic, url in entries:
        suffix = Path(urllib.parse.urlparse(url).path).suffix or ".ttf"
        filename = f"{safe_family}-{weight}{'Italic' if italic else ''}{suffix}"
        dest = dest_dir / filename
        try:
            dest.write_bytes(_fetch_url(url, timeout=30))
            downloaded.append(dest)
        except (urllib.error.URLError, OSError) as e:
            print(f"Warning: failed to download {filename}: {e}")
    return downloaded


def prepare_google_fonts_folder(specs, force_refresh: bool = False) -> Path:
    """Resolve one or more --google family specs into a temp folder of downloaded font files."""
    try:
        catalog = fetch_google_catalog(force_refresh=force_refresh)
    except RuntimeError as e:
        print(f"Error: {e}")
        sys.exit(1)

    known_families = {
        entry["family"].lower(): entry["family"]
        for entry in catalog.get("familyMetadataList", [])
        if "family" in entry
    }

    temp_dir = Path(tempfile.mkdtemp(prefix="install_fonts_google_"))
    any_downloaded = False

    for spec in specs:
        family_input, weights = parse_google_spec(spec)
        matched_family = known_families.get(family_input.lower())

        if not matched_family:
            print(f"Error: '{family_input}' was not found in the Google Fonts catalog.")
            suggestions = difflib.get_close_matches(family_input, known_families.values(), n=3)
            if suggestions:
                print(f"  Did you mean: {', '.join(suggestions)}?")
            continue

        try:
            entries = resolve_google_font_files(matched_family, weights)
        except (urllib.error.URLError, OSError) as e:
            print(f"Error: could not fetch '{matched_family}' from Google Fonts: {e}")
            continue

        if not entries:
            print(f"Warning: no font files found for '{matched_family}' with the requested weights.")
            continue

        downloaded = download_google_fonts(matched_family, entries, temp_dir)
        if downloaded:
            any_downloaded = True
            print(f"Downloaded {len(downloaded)} file(s) for {matched_family}.")

    if not any_downloaded:
        shutil.rmtree(temp_dir, ignore_errors=True)
        print("No fonts were downloaded from Google Fonts.")
        sys.exit(1)

    return temp_dir


def main():
    parser = argparse.ArgumentParser(
        description="Install a folder or .zip file of fonts into your user fonts directory."
    )
    parser.add_argument(
        "folder_path",
        metavar="folder_or_zip_path",
        nargs="?",
        default=None,
        help="Folder or .zip file to scan for fonts. If omitted, a folder picker dialog opens.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite fonts that already exist in the fonts directory.",
    )
    parser.add_argument(
        "--google",
        nargs="+",
        metavar="FAMILY[:WEIGHTS]",
        help=(
            'Install one or more Google Fonts by family name instead of a local folder, e.g. '
            '--google Roboto "Open Sans:700,400i". Weights default to 400,700 '
            '(comma-separated, append "i" for italic).'
        ),
    )
    parser.add_argument(
        "--refresh-catalog",
        action="store_true",
        help="Force re-downloading the cached Google Fonts catalog before resolving --google families.",
    )
    parser.add_argument(
        "--check-updates",
        action="store_true",
        help="Check GitHub Releases for a newer version and exit.",
    )
    args = parser.parse_args()

    if args.check_updates:
        sys.exit(print_update_status())

    google_temp_folder = None
    zip_temp_folder = None
    if args.google:
        google_temp_folder = prepare_google_fonts_folder(args.google, force_refresh=args.refresh_catalog)
        folder = google_temp_folder
    elif args.folder_path:
        folder = Path(args.folder_path).expanduser().resolve()
    else:
        folder = pick_folder_with_dialog().expanduser().resolve()

    try:
        if not folder.exists():
            print(f"Error: path does not exist: {folder}")
            sys.exit(1)
        if not folder.is_dir() and folder.suffix.lower() != ".zip":
            print(f"Error: not a folder or .zip file: {folder}")
            sys.exit(1)

        try:
            folder, zip_temp_folder = resolve_source_directory(folder)
        except zipfile.BadZipFile:
            print(f"Error: not a valid .zip file: {folder}")
            sys.exit(1)
        except ValueError as e:
            print(f"Error: {e}")
            sys.exit(1)
        except OSError as e:
            print(f"Error: could not extract .zip file {folder}: {e}")
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
    finally:
        if google_temp_folder:
            shutil.rmtree(google_temp_folder, ignore_errors=True)
        if zip_temp_folder:
            shutil.rmtree(zip_temp_folder, ignore_errors=True)


if __name__ == "__main__":
    main()
