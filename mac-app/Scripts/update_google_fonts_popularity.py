#!/usr/bin/env python3
"""Refresh the bundled Google Fonts popularity ranking.

Usage:
  GOOGLE_FONTS_API_KEY=your_key ./Scripts/update_google_fonts_popularity.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Resources" / "google-fonts-popularity.json"
API_URL = "https://www.googleapis.com/webfonts/v1/webfonts"


def main() -> int:
    api_key = os.environ.get("GOOGLE_FONTS_API_KEY", "").strip()
    if not api_key:
        print("Set GOOGLE_FONTS_API_KEY before running this script.", file=sys.stderr)
        return 1

    query = urllib.parse.urlencode({"sort": "popularity", "key": api_key})
    request = urllib.request.Request(
        f"{API_URL}?{query}",
        headers={"User-Agent": "font-file-installer-popularity-refresh/1.0"},
    )

    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))

    families = [
        item["family"]
        for item in payload.get("items", [])
        if isinstance(item, dict) and item.get("family")
    ]

    if not families:
        print("Google Fonts API returned no families.", file=sys.stderr)
        return 1

    OUTPUT.write_text(
        json.dumps(
            {
                "source": "Google Web Fonts Developer API sort=popularity",
                "families": families,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Wrote {len(families)} families to {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
