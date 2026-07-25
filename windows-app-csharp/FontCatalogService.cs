using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace FontInstaller.Windows;

public static class FontCatalogService
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(30) };
    static FontCatalogService() => Client.DefaultRequestHeaders.UserAgent.ParseAdd("font-file-installer/1.1");

    public static async Task<List<FontFamilyItem>> LoadCatalogAsync(string kind)
    {
        if (kind == "google")
        {
            var raw = (await Client.GetStringAsync("https://fonts.google.com/metadata/fonts")).TrimStart();
            if (raw.StartsWith(")]}'")) raw = raw[(raw.IndexOf('\n') + 1)..];
            using var doc = JsonDocument.Parse(raw);
            return doc.RootElement.GetProperty("familyMetadataList").EnumerateArray().Select(item => new FontFamilyItem(item.GetProperty("family").GetString()!, item.GetProperty("family").GetString()!)).OrderBy(item => item.Family).ToList();
        }
        using var response = JsonDocument.Parse(await Client.GetStringAsync("https://api.fontsource.org/v1/fonts"));
        return response.RootElement.EnumerateArray().Select(item => new FontFamilyItem(item.GetProperty("family").GetString()!, item.GetProperty("id").GetString()!)).OrderBy(item => item.Family).ToList();
    }

    public static async Task<InstallResult> InstallAsync(string kind, List<FontFamilyItem> families, string weights, bool italic, bool overwrite)
    {
        var temp = Path.Combine(Path.GetTempPath(), "FontInstaller-" + Guid.NewGuid());
        Directory.CreateDirectory(temp);
        try
        {
            var requests = ParseWeights(weights, italic);
            foreach (var family in families)
            {
                if (kind == "google") await DownloadGoogleAsync(family.Family, requests, temp);
                else await DownloadFontsourceAsync(family, requests, temp);
            }
            return await FontInstallerService.InstallAsync(temp, overwrite);
        }
        finally { Directory.Delete(temp, true); }
    }

    public static async Task<string> LatestVersionAsync()
    {
        using var doc = JsonDocument.Parse(await Client.GetStringAsync("https://api.github.com/repos/srihas115/font-file-installer/releases/latest"));
        return doc.RootElement.GetProperty("tag_name").GetString()!;
    }

    private static List<(string Weight, bool Italic)> ParseWeights(string value, bool italic)
    {
        var weights = value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(item => item.TrimEnd('i')).Where(item => int.TryParse(item, out _)).Distinct().ToList();
        if (weights.Count == 0) weights = ["400", "700"];
        return weights.SelectMany(weight => italic ? new[] { (weight, false), (weight, true) } : new[] { (weight, false) }).ToList();
    }

    private static async Task DownloadGoogleAsync(string family, List<(string Weight, bool Italic)> requests, string destination)
    {
        var axis = string.Join(';', requests.Select(item => item.Italic ? $"1,{item.Weight}" : $"0,{item.Weight}"));
        var url = $"https://fonts.googleapis.com/css2?family={Uri.EscapeDataString(family.Replace(" ", "+"))}:ital,wght@{axis}&display=swap";
        var css = await Client.GetStringAsync(url);
        var urls = Regex.Matches(css, @"url\((?<url>[^)]+)\)").Select(match => match.Groups["url"].Value).Distinct().ToList();
        var index = 0;
        foreach (var fileUrl in urls)
        {
            var bytes = await Client.GetByteArrayAsync(fileUrl);
            await File.WriteAllBytesAsync(Path.Combine(destination, $"{SafeName(family)}-{index++}.ttf"), bytes);
        }
    }

    private static async Task DownloadFontsourceAsync(FontFamilyItem family, List<(string Weight, bool Italic)> requests, string destination)
    {
        using var doc = JsonDocument.Parse(await Client.GetStringAsync($"https://api.fontsource.org/v1/fonts/{Uri.EscapeDataString(family.Id)}"));
        var variants = doc.RootElement.GetProperty("variants");
        var defaultSubset = doc.RootElement.TryGetProperty("defSubset", out var subsetNode) ? subsetNode.GetString() : null;
        foreach (var request in requests)
        {
            if (!variants.TryGetProperty(request.Weight, out var weight) || !weight.TryGetProperty(request.Italic ? "italic" : "normal", out var style)) continue;
            var subset = defaultSubset is not null && style.TryGetProperty(defaultSubset, out var chosen) ? chosen : style.EnumerateObject().FirstOrDefault().Value;
            if (subset.ValueKind == JsonValueKind.Undefined || !subset.TryGetProperty("url", out var files)) continue;
            var url = files.TryGetProperty("ttf", out var ttf) ? ttf.GetString() : files.TryGetProperty("woff2", out var woff) ? woff.GetString() : null;
            if (url is null) continue;
            var extension = url.EndsWith(".woff2", StringComparison.OrdinalIgnoreCase) ? ".woff2" : ".ttf";
            await File.WriteAllBytesAsync(Path.Combine(destination, $"{SafeName(family.Family)}-{request.Weight}{(request.Italic ? "Italic" : "")}{extension}"), await Client.GetByteArrayAsync(url));
        }
    }

    private static string SafeName(string input) => Regex.Replace(input, "[^A-Za-z0-9]+", "");
}
