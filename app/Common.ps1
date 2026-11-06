# AOverlay for Stream Music - made and distributed by AOSABI. See LICENSE.txt.
# Shared paths, settings and helper-process controls, used by the helper, the settings
# window, the installer and the uninstaller.

$AppName       = 'AOverlayForStreamMusic'
$AppTitle      = 'AOverlay for Stream Music'
$AppVersion    = '1.4.0'
$AppPublisher  = 'AOSABI'
$AppCredit     = 'Made and distributed by AOSABI'
$DataDir       = Join-Path $env:APPDATA $AppName
$SettingsPath  = Join-Path $DataDir 'settings.json'
$PidPath       = Join-Path $DataDir 'helper.pid'
$LogPath       = Join-Path $DataDir 'helper.log'
$TextOutPath   = Join-Path $DataDir 'nowplaying.txt'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$StartupLink   = Join-Path ([Environment]::GetFolderPath('Startup')) "$AppTitle Helper.lnk"
$StartMenuDir  = Join-Path ([Environment]::GetFolderPath('Programs')) $AppTitle
$DesktopLink   = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppTitle Settings.lnk"
$UninstallKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AOverlayForStreamMusic'
# Where the earlier version (named 'Now Playing Overlay') kept things, so Setup can replace it.
$LegacyDataDir      = Join-Path $env:APPDATA 'NowPlayingOverlay'
$LegacyUninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NowPlayingOverlay'
$LegacyStartMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Now Playing Overlay'
$LegacyLinks        = @((Join-Path ([Environment]::GetFolderPath('Startup')) 'Now Playing Overlay Helper.lnk'),
                        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Now Playing Overlay Settings.lnk'))

function Get-DefaultSettings {
    $o = [ordered]@{}
    # Look
    $o.headerText             = 'Now Playing -'
    $o.fontFamily             = 'Segoe UI'
    $o.fontSize               = 32
    $o.fontBold               = $true
    $o.fontItalic             = $false
    $o.textColor              = '#FFFFFF'
    $o.highlightColor         = '#FFC83D'
    $o.showBackground         = $true
    $o.backgroundColor        = '#101018'
    $o.backgroundTransparency = 35     # 0 = solid background, 100 = no background
    $o.overallTransparency    = 0      # 0 = fully visible, 90 = almost invisible
    $o.textTransparency       = 0      # the letters only
    $o.outlineTransparency    = 0      # the outline only
    $o.shadowTransparency     = 0      # the drop shadow only
    $o.textShadow             = $true
    $o.cornerRadius           = 12
    # Outline around the letters
    $o.outlineEnabled         = $false
    $o.outlineColor           = '#000000'
    $o.outlineThickness       = 3      # pixels
    $o.outlineFade            = 2      # pixels of soft fade at the outline's edge
    # Behaviour
    $o.scrollSpeed            = 90     # pixels per second
    $o.alwaysScroll           = $false
    $o.hideWhenIdle           = $true
    $o.idleText               = 'Nothing playing'
    $o.showArtist             = $true
    $o.showSourceSingle       = $false
    $o.multipleTracksText     = '{count} tracks open'
    $o.separator              = '   ' + [char]0x2022 + '   '
    # Music sources
    $o.vlcEnabled             = $true
    $o.sunoEnabled            = $true
    $o.spotifyEnabled         = $true
    $o.soundcloudEnabled      = $true
    # What each source is called on screen (blank = no label)
    $o.vlcLabel               = 'VLC'
    $o.sunoLabel              = 'Suno'
    $o.spotifyLabel           = 'Spotify'
    $o.soundcloudLabel        = 'SoundCloud'
    $o.vlcPort                = 0      # 0 = read it from VLC's own settings
    $o.vlcPassword            = ''     # blank = read it from VLC's own settings
    # OBS
    $o.port                   = 8095
    return $o
}

function Read-Settings {
    $d = Get-DefaultSettings
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $j = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($k in @($d.Keys)) {
                $p = $j.PSObject.Properties[$k]
                if ($p -ne $null -and $p.Value -ne $null) {
                    try { $d[$k] = [System.Management.Automation.LanguagePrimitives]::ConvertTo($p.Value, $d[$k].GetType()) } catch {}
                }
            }
        } catch {}
    }
    return $d
}

function Save-Settings($s) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $json = $s | ConvertTo-Json
    [IO.File]::WriteAllText($SettingsPath, $json, (New-Object Text.UTF8Encoding $false))
}

function Get-HelperProcess {
    if (-not (Test-Path -LiteralPath $PidPath)) { return $null }
    try {
        $id = [int]([IO.File]::ReadAllText($PidPath).Trim())
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop
        if ($cim -and $cim.CommandLine -like '*AOverlayHelper.ps1*') { return (Get-Process -Id $id -ErrorAction Stop) }
    } catch {}
    return $null
}

function Stop-Helper {
    $p = Get-HelperProcess
    if ($p) { try { $p.Kill(); [void]$p.WaitForExit(3000) } catch {} }
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

function Start-Helper([string]$appDir) {
    $helper = Join-Path $appDir 'AOverlayHelper.ps1'
    Start-Process -FilePath $PowerShellExe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', "`"$helper`"")
}

function New-Shortcut([string]$path, [string]$scriptPath, [string]$description, [switch]$Sta, [string]$icon = '') {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($path)
    $sc.TargetPath = $PowerShellExe
    $extra = ''
    if ($Sta) { $extra = ' -STA' }
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden$extra -File `"$scriptPath`""
    $sc.WorkingDirectory = Split-Path -Parent $scriptPath
    $sc.Description = $description
    $sc.WindowStyle = 7
    if ($icon -and (Test-Path -LiteralPath $icon)) { $sc.IconLocation = "$icon,0" }
    $sc.Save()
}

function Set-HelperAutostart([bool]$on, [string]$appDir) {
    if ($on) { New-Shortcut $StartupLink (Join-Path $appDir 'AOverlayHelper.ps1') "Starts the $AppTitle helper" -Sta -icon (Join-Path $appDir 'icon.ico') }
    else { Remove-Item -LiteralPath $StartupLink -Force -ErrorAction SilentlyContinue }
}

# ---------- app icon (the AOSABI watermark) ----------
# The icon ships as icon.png. These turn it into a Windows .ico file on this computer.
function New-IcoFromPng([string]$pngPath, [string]$icoPath) {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($pngPath)
    try {
        # A picture with a plain white background gets that white made see-through,
        # so the icon is just the mark.
        $keyAttr = $null
        try {
            $probe = New-Object System.Drawing.Bitmap($src)
            $c = $probe.GetPixel(0, 0); $probe.Dispose()
            if ($c.A -eq 255 -and $c.R -ge 235 -and $c.G -ge 235 -and $c.B -ge 235) {
                $keyAttr = New-Object System.Drawing.Imaging.ImageAttributes
                $keyAttr.SetColorKey([System.Drawing.Color]::FromArgb(235, 235, 235), [System.Drawing.Color]::FromArgb(255, 255, 255))
            }
        } catch {}
        $sizes = @(16, 24, 32, 48, 64, 128, 256)
        $images = New-Object System.Collections.ArrayList
        foreach ($sz in $sizes) {
            $bmp = New-Object System.Drawing.Bitmap($sz, $sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.SmoothingMode = 'HighQuality'
            $g.PixelOffsetMode = 'HighQuality'
            $g.Clear([System.Drawing.Color]::Transparent)
            # Keep the picture's shape: fit it inside the square and center it.
            $k = [Math]::Min($sz / $src.Width, $sz / $src.Height)
            $w = [int][Math]::Round($src.Width * $k); $h = [int][Math]::Round($src.Height * $k)
            $dest = New-Object System.Drawing.Rectangle([int](($sz - $w) / 2), [int](($sz - $h) / 2), $w, $h)
            if ($keyAttr) { $g.DrawImage($src, $dest, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $keyAttr) }
            else { $g.DrawImage($src, $dest) }
            $g.Dispose()
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            [void]$images.Add(@($sz, $ms.ToArray()))
            $ms.Dispose()
        }
        $out = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter($out)
        $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$images.Count)
        $offset = 6 + 16 * $images.Count
        foreach ($im in $images) {
            $sz = $im[0]; $data = $im[1]
            $d = $(if ($sz -ge 256) { 0 } else { $sz })
            $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
            $bw.Write([UInt16]1); $bw.Write([UInt16]32)
            $bw.Write([UInt32]$data.Length); $bw.Write([UInt32]$offset)
            $offset += $data.Length
        }
        foreach ($im in $images) { $bw.Write([byte[]]$im[1]) }
        $bw.Flush()
        [IO.File]::WriteAllBytes($icoPath, $out.ToArray())
        $bw.Dispose(); $out.Dispose()
    } finally { $src.Dispose() }
}

# Returns the path of icon.ico in a folder, making it from icon.png first if needed.
function Get-AppIconFile([string]$dir) {
    $ico = Join-Path $dir 'icon.ico'
    $png = Join-Path $dir 'icon.png'
    if (-not (Test-Path -LiteralPath $ico) -and (Test-Path -LiteralPath $png)) {
        try { New-IcoFromPng $png $ico } catch {}
    }
    if (Test-Path -LiteralPath $ico) { return $ico }
    return ''
}

# Returns the icon as an object a window or the tray can show, or $null.
function Get-AppIcon([string]$dir, [int]$size = 32) {
    Add-Type -AssemblyName System.Drawing
    $ico = Get-AppIconFile $dir
    if ($ico) { try { return (New-Object System.Drawing.Icon($ico, $size, $size)) } catch {} }
    return $null
}
