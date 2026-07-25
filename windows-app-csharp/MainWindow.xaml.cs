using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using MessageBox = System.Windows.MessageBox;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;

namespace FontInstaller.Windows;

public partial class MainWindow : Window
{
    private static readonly string FontsDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Fonts");
    private static readonly string[] Extensions = [".ttf", ".otf", ".woff", ".woff2"];
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(30) };
    private string? sourcePath;
    private string catalogKind = "google";
    private List<FontFamilyItem> catalog = [];

    public MainWindow()
    {
        InitializeComponent();
        Client.DefaultRequestHeaders.UserAgent.ParseAdd("font-file-installer/1.1");
        ShowPage(InstallPage, SegmentInstall);
    }

    private void ShowInstall(object sender, RoutedEventArgs e) => ShowPage(InstallPage, SegmentInstall);
    private void ShowGoogle(object sender, RoutedEventArgs e) { catalogKind = "google"; CatalogLink.Text = "Fonts by Google Fonts"; ShowPage(CatalogPage, SegmentGoogle); }
    private void ShowFontsource(object sender, RoutedEventArgs e) { catalogKind = "fontsource"; CatalogLink.Text = "Fonts by Fontsource"; ShowPage(CatalogPage, SegmentFontsource); }
    private void ShowLibrary(object sender, RoutedEventArgs e) { ShowPage(LibraryPage, SegmentLibrary); RefreshLibrary(sender, e); }

    private void ShowPage(Grid page, System.Windows.Controls.Button activeSegment)
    {
        InstallPage.Visibility = page == InstallPage ? Visibility.Visible : Visibility.Collapsed;
        CatalogPage.Visibility = page == CatalogPage ? Visibility.Visible : Visibility.Collapsed;
        LibraryPage.Visibility = page == LibraryPage ? Visibility.Visible : Visibility.Collapsed;
        foreach (var button in new[] { SegmentInstall, SegmentGoogle, SegmentFontsource, SegmentLibrary })
        {
            button.Background = button == activeSegment ? System.Windows.Media.Brushes.Black : System.Windows.Media.Brushes.Transparent;
            button.Foreground = button == activeSegment ? System.Windows.Media.Brushes.White : System.Windows.Media.Brushes.LightGray;
        }
    }

    private void ChooseSource(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "ZIP files (*.zip)|*.zip", Title = "Choose a font ZIP file" };
        if (dialog.ShowDialog() == true) sourcePath = dialog.FileName;
        else
        {
            using var folder = new System.Windows.Forms.FolderBrowserDialog { Description = "Choose a folder containing fonts", UseDescriptionForTitle = true };
            if (folder.ShowDialog() == System.Windows.Forms.DialogResult.OK) sourcePath = folder.SelectedPath;
        }
        if (sourcePath is null) return;
        SourceButton.Content = $"✓\n\n{ShortPath(sourcePath)}\n\nReady to install";
        InstallButton.IsEnabled = true;
    }

    private async void InstallLocal(object sender, RoutedEventArgs e)
    {
        if (sourcePath is null) return;
        InstallButton.IsEnabled = false;
        await InstallAndReport(() => FontInstallerService.InstallAsync(sourcePath, OverwriteCheck.IsChecked == true));
        InstallButton.IsEnabled = true;
    }

    private async void LoadCatalog(object sender, RoutedEventArgs e)
    {
        StatusText.Text = $"Loading {catalogKind} catalog…";
        try
        {
            catalog = await FontCatalogService.LoadCatalogAsync(catalogKind);
            FilterCatalog(sender, null!);
            CatalogInstallButton.IsEnabled = catalog.Count > 0;
            StatusText.Text = $"Loaded {catalog.Count:N0} families.";
        }
        catch (Exception error) { ReportError(error); }
    }

    private void FilterCatalog(object sender, TextChangedEventArgs e)
    {
        var query = SearchBox.Text?.Trim() ?? "";
        FamiliesList.ItemsSource = catalog.Where(item => item.Family.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        FamiliesList.DisplayMemberPath = nameof(FontFamilyItem.Family);
    }

    private async void InstallCatalog(object sender, RoutedEventArgs e)
    {
        var selected = FamiliesList.SelectedItems.Cast<FontFamilyItem>().ToList();
        if (selected.Count == 0) { MessageBox.Show("Select one or more font families first.", "Font Installer", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        CatalogInstallButton.IsEnabled = false;
        await InstallAndReport(() => FontCatalogService.InstallAsync(catalogKind, selected, WeightsBox.Text, ItalicCheck.IsChecked == true, CatalogOverwriteCheck.IsChecked == true));
        CatalogInstallButton.IsEnabled = catalog.Count > 0;
    }

    private async Task InstallAndReport(Func<Task<InstallResult>> work)
    {
        StatusText.Text = "Installing fonts…";
        try
        {
            var result = await work();
            var summary = $"Found {result.Found} · Installed {result.Installed} · Skipped {result.Skipped} · Failed {result.Failed}";
            StatusText.Text = summary;
            MessageBox.Show(result.Installed > 0 ? summary + "\n\nYour fonts are ready to use." : result.Found == 0 ? "No supported font files were found." : summary, "Font Installer", MessageBoxButton.OK, result.Installed > 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
        }
        catch (Exception error) { ReportError(error); }
    }

    private void RefreshLibrary(object sender, RoutedEventArgs e)
    {
        try
        {
            var fonts = FontInstallerService.ListInstalled();
            FontsGrid.ItemsSource = fonts;
            LibraryCount.Text = $"{fonts.Count} font{(fonts.Count == 1 ? "" : "s")} installed";
        }
        catch (Exception error) { ReportError(error); }
    }

    private void OpenFonts(object sender, RoutedEventArgs e) { Directory.CreateDirectory(FontsDirectory); Process.Start(new ProcessStartInfo { FileName = FontsDirectory, UseShellExecute = true }); }
    private void UninstallSelected(object sender, RoutedEventArgs e)
    {
        var selected = FontsGrid.SelectedItems.Cast<InstalledFontItem>().ToList();
        if (selected.Count == 0) { MessageBox.Show("Select one or more font files first.", "Font Installer", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        if (MessageBox.Show($"Remove {selected.Count} selected font file(s)?", "Uninstall fonts", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        var removed = FontInstallerService.Uninstall(selected.Select(item => item.Path));
        RefreshLibrary(sender, e); StatusText.Text = $"Uninstalled {removed} font(s).";
    }

    private async void CheckUpdates(object sender, RoutedEventArgs e)
    {
        try
        {
            StatusText.Text = "Checking for updates…";
            var version = await FontCatalogService.LatestVersionAsync();
            if (IsNewer(version, "1.1.0") && MessageBox.Show($"Version {version} is available. Open Releases?", "Update available", MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
                Process.Start(new ProcessStartInfo { FileName = "https://github.com/srihas115/font-file-installer/releases/latest", UseShellExecute = true });
            else if (!IsNewer(version, "1.1.0")) MessageBox.Show("You have the latest version.", "Font Installer", MessageBoxButton.OK, MessageBoxImage.Information);
            StatusText.Text = "Ready.";
        }
        catch (Exception error) { ReportError(error); }
    }

    private void Settings(object sender, RoutedEventArgs e)
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "font-file-installer", "google-fonts-metadata.json");
        if (MessageBox.Show("Clear the cached Google Fonts catalog? It will be downloaded again next time.", "Settings", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
        { if (File.Exists(path)) File.Delete(path); MessageBox.Show("Catalog cache cleared.", "Settings", MessageBoxButton.OK, MessageBoxImage.Information); }
    }

    private void ReportError(Exception error) { StatusText.Text = "Something needs attention."; MessageBox.Show(error.Message, "Font Installer", MessageBoxButton.OK, MessageBoxImage.Error); }
    private static string ShortPath(string path) => path.Length <= 70 ? path : path[..33] + "…" + path[^33..];
    private static bool IsNewer(string latest, string current) => Version.TryParse(latest.TrimStart('v', 'V'), out var left) && Version.TryParse(current, out var right) && left > right;
}

public record FontFamilyItem(string Family, string Id);
public record InstalledFontItem(string Name, string Size, string Path);
public record InstallResult(int Found, int Installed, int Skipped, int Failed);
