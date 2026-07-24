import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import install_fonts


class FontDiscoveryTests(unittest.TestCase):
    def test_find_font_files_recurses_and_filters_by_extension(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nested = root / "nested"
            nested.mkdir()
            (root / "Alpha.ttf").write_bytes(b"font")
            (nested / "Beta.OTF").write_bytes(b"font")
            (nested / "Gamma.woff2").write_bytes(b"font")
            (root / "notes.txt").write_text("not a font", encoding="utf-8")

            found = [path.relative_to(root) for path in install_fonts.find_font_files(root)]

        self.assertEqual(
            found,
            [
                Path("Alpha.ttf"),
                Path("nested/Beta.OTF"),
                Path("nested/Gamma.woff2"),
            ],
        )


class GoogleFontsParsingTests(unittest.TestCase):
    def test_parse_google_spec_defaults_to_regular_and_bold(self):
        self.assertEqual(
            install_fonts.parse_google_spec("Roboto"),
            ("Roboto", [(400, False), (700, False)]),
        )

    def test_parse_google_spec_accepts_weights_and_italic_suffix(self):
        self.assertEqual(
            install_fonts.parse_google_spec("Open Sans:300,400i,700"),
            ("Open Sans", [(300, False), (400, True), (700, False)]),
        )

    def test_build_css2_url_for_non_italic_weights(self):
        url = install_fonts.build_css2_url(
            "Open Sans",
            [(700, False), (400, False), (700, False)],
        )

        self.assertEqual(
            url,
            "https://fonts.googleapis.com/css2?family=Open+Sans:wght@400;700&display=swap",
        )

    def test_build_css2_url_for_mixed_italic_weights(self):
        url = install_fonts.build_css2_url(
            "Open Sans",
            [(700, False), (400, True), (400, False)],
        )

        self.assertEqual(
            url,
            "https://fonts.googleapis.com/css2?family=Open+Sans:ital,wght@0,400;0,700;1,400&display=swap",
        )

    def test_parse_css2_extracts_font_faces(self):
        css = """
        @font-face {
          font-family: 'Roboto';
          font-style: normal;
          font-weight: 400;
          src: url(https://fonts.gstatic.com/s/roboto/v30/roboto-400.ttf) format('truetype');
        }
        @font-face {
          font-family: 'Roboto';
          font-style: italic;
          font-weight: 700;
          src: url(https://fonts.gstatic.com/s/roboto/v30/roboto-700i.ttf) format('truetype');
        }
        """

        self.assertEqual(
            install_fonts.parse_css2(css),
            [
                (400, False, "https://fonts.gstatic.com/s/roboto/v30/roboto-400.ttf"),
                (700, True, "https://fonts.gstatic.com/s/roboto/v30/roboto-700i.ttf"),
            ],
        )


class SourceResolutionTests(unittest.TestCase):
    def test_resolve_source_directory_returns_folder_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            resolved, cleanup = install_fonts.resolve_source_directory(folder)

        self.assertEqual(resolved, folder)
        self.assertIsNone(cleanup)

    def test_resolve_source_directory_extracts_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            zip_path = root / "fonts.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("Family/Alpha.ttf", b"font")
                archive.writestr("Family/readme.txt", "notes")

            resolved, cleanup = install_fonts.resolve_source_directory(zip_path)
            try:
                found = [path.relative_to(resolved) for path in install_fonts.find_font_files(resolved)]
                self.assertEqual(found, [Path("Family/Alpha.ttf")])
            finally:
                if cleanup:
                    shutil.rmtree(cleanup, ignore_errors=True)

    def test_resolve_source_directory_rejects_unsafe_zip_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            zip_path = root / "unsafe.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("../outside.ttf", b"font")

            with self.assertRaises(ValueError):
                install_fonts.resolve_source_directory(zip_path)


if __name__ == "__main__":
    unittest.main()
