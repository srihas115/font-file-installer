# font-file-installer

Install a whole folder of fonts (`.otf`, `.ttf`, `.woff`, `.woff2`) into `~/Library/Fonts` in one go. Two ways to use it:

## Mac app (drag-and-drop)

A native SwiftUI app in [`mac-app/`](mac-app/) with a drag-and-drop window and a "Choose Folder" button.

Build and run it from the terminal (no full Xcode install required, just the Command Line Tools):

```bash
cd mac-app
./Scripts/build_app.sh
open "Install Fonts.app"
```

This produces `mac-app/Install Fonts.app`, a real double-clickable app. Drag a folder onto the window, or click "Choose Folder…", then click Install.

Since the app isn't signed/notarized (that requires a paid Apple Developer account), macOS Gatekeeper will block it on first launch for anyone downloading a pre-built copy. Right-click the app → **Open** → **Open** to bypass this once; after that it opens normally.

## Command-line script

```bash
python3 install_fonts.py [folder_path]
```

- Omit `folder_path` to get a native macOS folder picker dialog.
- Recursively finds font files and copies them into `~/Library/Fonts`.
- Skips files that already exist there (use `--force` to overwrite).
- Prints a summary of found/installed/skipped/failed fonts.

Requires only the Python 3 standard library.

## License

MIT
