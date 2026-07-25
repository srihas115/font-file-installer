using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.IO.Compression;

namespace FontInstaller.Windows;

public static class FontInstallerService
{
    private static readonly string FontDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Fonts");
    private static readonly string[] Extensions = [".ttf", ".otf", ".woff", ".woff2"];
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] private static extern int AddFontResource(string path);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] private static extern bool RemoveFontResource(string path);
    [DllImport("user32.dll")] private static extern nint SendMessage(nint hWnd, uint msg, nint wParam, nint lParam);

    public static async Task<InstallResult> InstallAsync(string source, bool overwrite)
    {
        string? temporary = null;
        try
        {
            var folder = source;
            if (Path.GetExtension(source).Equals(".zip", StringComparison.OrdinalIgnoreCase))
            {
                temporary = Path.Combine(Path.GetTempPath(), "FontInstaller-" + Guid.NewGuid());
                ZipFile.ExtractToDirectory(source, temporary);
                folder = temporary;
            }
            Directory.CreateDirectory(FontDirectory);
            var fonts = Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories).Where(path => Extensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase)).ToList();
            var installed = 0; var skipped = 0; var failed = 0;
            foreach (var font in fonts)
            {
                var destination = Path.Combine(FontDirectory, Path.GetFileName(font));
                if (File.Exists(destination) && !overwrite) { skipped++; continue; }
                try { File.Copy(font, destination, overwrite); if (Extensions[..2].Contains(Path.GetExtension(destination), StringComparer.OrdinalIgnoreCase)) Register(destination); installed++; }
                catch { failed++; }
            }
            return await Task.FromResult(new InstallResult(fonts.Count, installed, skipped, failed));
        }
        finally { if (temporary is not null) Directory.Delete(temporary, true); }
    }

    public static List<InstalledFontItem> ListInstalled()
    {
        Directory.CreateDirectory(FontDirectory);
        return Directory.EnumerateFiles(FontDirectory).Where(path => Extensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase)).OrderBy(Path.GetFileName).Select(path => new InstalledFontItem(Path.GetFileName(path), FormatSize(new FileInfo(path).Length), path)).ToList();
    }

    public static int Uninstall(IEnumerable<string> paths)
    {
        var removed = 0;
        foreach (var path in paths) { try { RemoveFontResource(path); File.Delete(path); removed++; } catch { } }
        SendMessage((nint)0xffff, 0x001d, 0, 0); return removed;
    }

    private static void Register(string path)
    {
        try { using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows NT\CurrentVersion\Fonts", true); key?.SetValue($"{Path.GetFileNameWithoutExtension(path)} ({(Path.GetExtension(path).Equals(".otf", StringComparison.OrdinalIgnoreCase) ? "OpenType" : "TrueType")})", path); } catch { }
        AddFontResource(path); SendMessage((nint)0xffff, 0x001d, 0, 0);
    }
    private static string FormatSize(long bytes) => bytes < 1024 ? $"{bytes} B" : bytes < 1024 * 1024 ? $"{bytes / 1024d:F1} KB" : $"{bytes / 1024d / 1024d:F1} MB";
}
