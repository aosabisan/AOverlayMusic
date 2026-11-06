# AOverlay for Stream Music - made and distributed by AOSABI. See LICENSE.txt.
# Background helper.
# Every second it checks what VLC and Suno are playing, then serves the overlay
# to OBS at http://localhost:<port>/  (the data itself is at /data).
#
#   -Once   print what is playing right now and exit (for testing)

param([switch]$Once)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common.ps1')
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Write-Log([string]$msg) {
    try {
        if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 512KB) {
            Remove-Item -LiteralPath $LogPath -Force
        }
        Add-Content -LiteralPath $LogPath -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch {}
}

# ---------- only one helper at a time ----------
if (-not $Once) {
    $createdNew = $false
    $script:HelperMutex = [System.Threading.Mutex]::new($true, 'Local\AOverlayForStreamMusicHelper', [ref]$createdNew)
    if (-not $createdNew) { exit }
    [IO.File]::WriteAllText($PidPath, [string]$PID)
    Write-Log "Helper started (version $AppVersion)"
}

# ---------- list of open windows (title + process) ----------
if (-not ('NpoWindows' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class NpoWindows {
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static List<KeyValuePair<int, string>> List() {
        var result = new List<KeyValuePair<int, string>>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            int len = GetWindowTextLength(h);
            if (len <= 0) return true;
            var sb = new StringBuilder(len + 1);
            GetWindowText(h, sb, sb.Capacity);
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            result.Add(new KeyValuePair<int, string>((int)pid, sb.ToString()));
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@
}

$BrowserProcs = @('chrome','msedge','firefox','brave','opera','vivaldi','arc','zen','librewolf',
                  'waterfox','floorp','thorium','chromium','iridium','browser')

function Get-WindowList {
    $names = @{}
    $list = New-Object System.Collections.ArrayList
    foreach ($kv in [NpoWindows]::List()) {
        $id = $kv.Key
        if (-not $names.ContainsKey($id)) {
            try { $names[$id] = [Diagnostics.Process]::GetProcessById($id).ProcessName.ToLowerInvariant() } catch { $names[$id] = '' }
        }
        [void]$list.Add([pscustomobject]@{ Proc = $names[$id]; Title = $kv.Value })
    }
    return ,$list
}

# ---------- name clean-up ----------
$MediaExt = '(?i)\.(mp3|flac|wav|m4a|aac|ogg|oga|opus|wma|alac|aif|aiff|ape|wv|mka|mp4|m4v|mkv|webm|avi|mov|wmv|flv|ts|mpg|mpeg|3gp)$'

function Remove-Extension([string]$name) {
    if (-not $name) { return '' }
    return ($name.Trim() -replace $MediaExt, '').Trim()
}

function Format-Track([string]$title, [string]$artist, [string]$fileName) {
    $t = ''
    if ($title) { $t = $title.Trim() }
    if (-not $t -or ($fileName -and $t -eq $fileName.Trim())) { $t = $fileName }
    $t = Remove-Extension $t
    if (-not $t) { return '' }
    $a = ''
    if ($artist) { $a = $artist.Trim() }
    if ($Settings.showArtist -and $a -and $t.IndexOf($a, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return "$t - $a"
    }
    return $t
}

# ---------- VLC ----------
$script:VlcCfg = $null
$script:VlcCfgTime = [datetime]::MinValue

function Get-VlcConnection {
    if (-not $script:VlcCfg -or ((Get-Date) - $script:VlcCfgTime).TotalSeconds -gt 20) {
        $port = 8080; $pw = ''
        $rc = Join-Path $env:APPDATA 'vlc\vlcrc'
        if (Test-Path -LiteralPath $rc) {
            try {
                foreach ($line in [IO.File]::ReadAllLines($rc)) {
                    if ($line -match '^\s*http-port\s*=\s*(\d+)') { $port = [int]$Matches[1] }
                    elseif ($line -match '^\s*http-password\s*=\s*(.*)$') { $pw = $Matches[1].Trim() }
                }
            } catch {}
        }
        $script:VlcCfg = @{ Port = $port; Password = $pw }
        $script:VlcCfgTime = Get-Date
    }
    $c = @{ Port = $script:VlcCfg.Port; Password = $script:VlcCfg.Password }
    if ([int]$Settings.vlcPort -gt 0) { $c.Port = [int]$Settings.vlcPort }
    if ($Settings.vlcPassword) { $c.Password = [string]$Settings.vlcPassword }
    return $c
}

function Invoke-VlcStatus([int]$port, [string]$password) {
    try {
        $req = [Net.HttpWebRequest]::Create("http://127.0.0.1:$port/requests/status.json")
        $req.Timeout = 700
        $req.ReadWriteTimeout = 700
        $req.Proxy = $null
        $req.Headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":$password"))
        $resp = $req.GetResponse()
        try {
            $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
            $txt = $reader.ReadToEnd()
        } finally { $resp.Close() }
        return ($txt | ConvertFrom-Json)
    } catch { return $null }
}

function Get-VlcTrack($windows) {
    $hasWindow = @($windows | Where-Object { $_.Proc -eq 'vlc' }).Count -gt 0
    if (-not $hasWindow -and -not (Get-Process -Name vlc -ErrorAction SilentlyContinue)) { return '' }

    # 1) VLC's web interface: knows title, artist and whether it is paused.
    $c = Get-VlcConnection
    if ($c.Password) {
        $j = Invoke-VlcStatus $c.Port $c.Password
        if ($j -ne $null) {
            if ([string]$j.state -ne 'playing') { return '' }
            $meta = $null
            try { $meta = $j.information.category.meta } catch {}
            if ($meta -eq $null) { return '' }
            if ($meta.now_playing) { return ([string]$meta.now_playing).Trim() }   # internet radio
            return (Format-Track ([string]$meta.title) ([string]$meta.artist) ([string]$meta.filename))
        }
    }

    # 2) Backup: VLC's title bar, "Song name - VLC media player".
    $tail = ' - VLC media player'
    foreach ($w in $windows) {
        if ($w.Proc -ne 'vlc') { continue }
        if ($w.Title.EndsWith($tail)) {
            $t = Remove-Extension ($w.Title.Substring(0, $w.Title.Length - $tail.Length))
            if ($t) { return $t }
        }
    }
    return ''
}

# ---------- Windows media sessions (browsers, VLC 4) ----------
$script:SmtcManager = $null
$script:AsTaskGeneric = $null

function Wait-WinRt($op, [Type]$type) {
    $task = $script:AsTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    if (-not $task.Wait(2000)) { return $null }
    return $task.Result
}

function Initialize-MediaSessions {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
        $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
        $script:AsTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
        $script:SmtcManager = Wait-WinRt ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
    } catch {
        Write-Log "Windows media sessions unavailable: $($_.Exception.Message)"
    }
}

function Get-MediaSessions([switch]$All) {
    $out = New-Object System.Collections.ArrayList
    if ($script:SmtcManager -eq $null) { return ,$out }
    $sessions = $null
    try { $sessions = $script:SmtcManager.GetSessions() } catch { return ,$out }
    foreach ($s in $sessions) {
        try {
            $status = [string]$s.GetPlaybackInfo().PlaybackStatus
            if (-not $All -and $status -ne 'Playing') { continue }
            $p = Wait-WinRt ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
            $title = ''; $artist = ''
            if ($p -ne $null) { $title = [string]$p.Title; $artist = [string]$p.Artist }
            if (-not $All -and -not $title) { continue }
            [void]$out.Add([pscustomobject]@{ App = [string]$s.SourceAppUserModelId; Status = $status; Title = $title; Artist = $artist })
        } catch {}
    }
    return ,$out
}

# ---------- browser connector (Tampermonkey script on Suno, Spotify web and SoundCloud) ----------
$script:Reports = @{}
$script:ConnectorSeen = @{}      # site -> last time that site's connector reported

function Add-ConnectorReport([string]$body) {
    try {
        $r = $body | ConvertFrom-Json
        $id = [string]$r.id
        if (-not $id) { return }
        $site = [string]$r.site
        if (-not $site) { $site = 'suno' }      # older connector only knew Suno
        $site = $site.ToLowerInvariant()
        $script:Reports[$id] = [pscustomobject]@{
            Site = $site; Playing = [bool]$r.playing; Title = [string]$r.title; Artist = [string]$r.artist; Time = Get-Date }
        $script:ConnectorSeen[$site] = Get-Date
    } catch {}
}

function Test-ConnectorActive([string]$site = '') {
    $now = Get-Date
    foreach ($k in @($script:ConnectorSeen.Keys)) {
        if ($site -and $k -ne $site) { continue }
        if (($now - $script:ConnectorSeen[$k]).TotalSeconds -lt 600) { return $true }
    }
    return $false
}

function Get-ConnectorTracks([string]$site) {
    $result = New-Object System.Collections.ArrayList
    $now = Get-Date
    foreach ($k in @($script:Reports.Keys)) {
        $r = $script:Reports[$k]
        $age = ($now - $r.Time).TotalSeconds
        if ($age -gt 600) { $script:Reports.Remove($k); continue }
        if ($r.Site -ne $site) { continue }
        if ($r.Playing -and $age -lt 6 -and $r.Title) {
            $name = Format-Track $r.Title $r.Artist ''
            if ($name -and -not $result.Contains($name)) { [void]$result.Add($name) }
        }
    }
    return ,$result
}

function Test-BrowserApp([string]$appId) {
    if ($appId -match '^[0-9A-Fa-f]{16}$') { return $true }   # Firefox-family browsers
    return ($appId -match '(?i)chrome|chromium|msedge|brave|opera|vivaldi|thebrowsercompany|firefox|librewolf|waterfox|floorp|thorium|yandex')
}

# Without the connector, browser songs are matched to a site by the open windows:
#  - SoundCloud puts the song in its tab title, so a song shown in a SoundCloud window is SoundCloud.
#  - Suno never puts the song in its tab title, so a browser song that is not the title of any open
#    window counts as Suno when a Suno window is open.
#  - Spotify's web player can only be read through the connector.
function Get-BrowserSiteTracks($windows, $sessions) {
    $out = @{ suno = (New-Object System.Collections.ArrayList); soundcloud = (New-Object System.Collections.ArrayList) }
    $browserWins = @($windows | Where-Object { $BrowserProcs -contains $_.Proc })
    $hasSuno = @($browserWins | Where-Object { $_.Title -match '(?i)\bsuno\b' }).Count -gt 0
    foreach ($m in $sessions) {
        if (-not (Test-BrowserApp $m.App)) { continue }
        if (-not $m.Title) { continue }
        $shownIn = @($browserWins | Where-Object { $_.Title.IndexOf($m.Title, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        $site = $null
        if ($shownIn.Count -gt 0) {
            if (@($shownIn | Where-Object { $_.Title -match '(?i)soundcloud' }).Count -gt 0) { $site = 'soundcloud' }
        } elseif ($hasSuno) { $site = 'suno' }
        if (-not $site) { continue }
        $name = Format-Track $m.Title $m.Artist ''
        if ($name -and -not $out[$site].Contains($name)) { [void]$out[$site].Add($name) }
    }
    return $out
}

# Spotify's desktop app reports its song to Windows itself.
function Get-SpotifyAppTrack($sessions) {
    foreach ($m in $sessions) { if ($m.App -match '(?i)spotify' -and $m.Title) { return (Format-Track $m.Title $m.Artist '') } }
    return ''
}

# ---------- put it together ----------
$script:Tracks = New-Object System.Collections.ArrayList
$script:Windows = @()
$script:LastText = $null

function Get-PlainText {
    $n = $script:Tracks.Count
    if ($n -eq 0) { return '' }
    if ($n -eq 1) { return ('{0} {1}' -f $Settings.headerText, $script:Tracks[0].name) }
    $parts = @(($Settings.multipleTracksText -replace '\{count\}', [string]$n))
    foreach ($t in $script:Tracks) {
        if ($t.source) { $parts += ('{0}: {1}' -f $t.source, $t.name) } else { $parts += $t.name }
    }
    return ('{0} {1}' -f $Settings.headerText, ($parts -join ' | '))
}

function Add-Track($list, [string]$label, [string]$name) {
    if (-not $name) { return }
    foreach ($t in $list) { if ($t.name -eq $name -and $t.source -eq $label) { return } }
    [void]$list.Add([ordered]@{ source = $label; name = $name })
}

function Update-NowPlaying {
    $windows = Get-WindowList
    $sessions = Get-MediaSessions
    $tracks = New-Object System.Collections.ArrayList
    $fallback = Get-BrowserSiteTracks $windows $sessions

    if ($Settings.vlcEnabled) {
        $v = Get-VlcTrack $windows
        if (-not $v) {
            foreach ($m in $sessions) { if ($m.App -match '(?i)vlc' -and $m.Title) { $v = Format-Track $m.Title $m.Artist ''; break } }
        }
        Add-Track $tracks ([string]$Settings.vlcLabel) $v
    }
    if ($Settings.sunoEnabled) {
        # The browser connector is exact, so it wins for a site once it is installed there.
        if (Test-ConnectorActive 'suno') { $list = Get-ConnectorTracks 'suno' } else { $list = $fallback['suno'] }
        foreach ($n in $list) { Add-Track $tracks ([string]$Settings.sunoLabel) $n }
    }
    if ($Settings.spotifyEnabled) {
        Add-Track $tracks ([string]$Settings.spotifyLabel) (Get-SpotifyAppTrack $sessions)
        foreach ($n in (Get-ConnectorTracks 'spotify')) { Add-Track $tracks ([string]$Settings.spotifyLabel) $n }
    }
    if ($Settings.soundcloudEnabled) {
        if (Test-ConnectorActive 'soundcloud') { $list = Get-ConnectorTracks 'soundcloud' } else { $list = $fallback['soundcloud'] }
        foreach ($n in $list) { Add-Track $tracks ([string]$Settings.soundcloudLabel) $n }
    }
    $script:Windows = $windows
    $script:Tracks = $tracks
    $text = Get-PlainText
    if ($text -ne $script:LastText) {
        try { [IO.File]::WriteAllText($TextOutPath, $text, (New-Object Text.UTF8Encoding $false)); $script:LastText = $text } catch {}
    }
}

function Get-PayloadJson {
    $payload = [ordered]@{
        ok       = $true
        version  = $AppVersion
        tracks   = @($script:Tracks.ToArray())
        connector = (Test-ConnectorActive)
        overlay  = (Get-OverlayState)
        settings = $Settings
    }
    return ($payload | ConvertTo-Json -Depth 6 -Compress)
}

# The OBS overlay tells the helper its width and whether it is scrolling, so the settings
# preview can match what is really on stream.
$script:OverlayState = $null
function Set-OverlayState([string]$body) {
    try {
        $r = $body | ConvertFrom-Json
        $script:OverlayState = [pscustomobject]@{ Scrolling = [bool]$r.scrolling; Width = [int]$r.width; Time = Get-Date }
    } catch {}
}
function Get-OverlayState {
    $o = $script:OverlayState
    if ($o -eq $null -or ((Get-Date) - $o.Time).TotalSeconds -gt 15) { return $null }
    return [ordered]@{ scrolling = $o.Scrolling; width = $o.Width }
}

# What the helper can see, for troubleshooting: http://localhost:<port>/debug
function Get-DebugJson {
    $c = Get-VlcConnection
    $wins = @($script:Windows | Where-Object { $BrowserProcs -contains $_.Proc -or $_.Proc -eq 'vlc' } |
              ForEach-Object { [ordered]@{ process = $_.Proc; title = $_.Title } })
    $sess = @()
    foreach ($m in (Get-MediaSessions -All)) {
        $sess += [ordered]@{ app = $m.App; status = $m.Status; title = $m.Title; artist = $m.Artist; isBrowser = (Test-BrowserApp $m.App) } }
    $vlcState = ''
    $vj = Invoke-VlcStatus $c.Port $c.Password
    if ($vj -ne $null) { $vlcState = [string]$vj.state }
    $reports = @($script:Reports.Keys | ForEach-Object {
              $r = $script:Reports[$_]
              [ordered]@{ site = $r.Site; playing = $r.Playing; title = $r.Title; artist = $r.Artist; secondsAgo = [int]((Get-Date) - $r.Time).TotalSeconds } })
    $d = [ordered]@{
        version          = $AppVersion
        tracks           = @($script:Tracks.ToArray())
        mediaSessionsOk  = ($script:SmtcManager -ne $null)
        mediaSessions    = $sess
        windows          = $wins
        vlcWebPort       = $c.Port
        vlcHasPassword   = [bool]$c.Password
        vlcWebAnswers    = ($vj -ne $null)
        vlcState         = $vlcState
        connector        = (Test-ConnectorActive)
        connectorReports = $reports
    }
    return ($d | ConvertTo-Json -Depth 5)
}

$ConnectorFile = Join-Path $PSScriptRoot 'browser-connector.user.js'

# ---------- tiny web server for OBS ----------
function Start-Listener([int]$port) {
    foreach ($prefixes in @(@("http://localhost:$port/", "http://127.0.0.1:$port/"), @("http://localhost:$port/"))) {
        $l = New-Object System.Net.HttpListener
        foreach ($p in $prefixes) { $l.Prefixes.Add($p) }
        try { $l.Start(); Write-Log "Serving the overlay at http://localhost:$port/"; return $l }
        catch { try { $l.Close() } catch {} }
    }
    Write-Log "Could not use port $port. Another program may be using it; pick another port in the settings."
    return $null
}

$OverlayFile = Join-Path $PSScriptRoot 'overlay.html'

function Send-Response($ctx) {
    $res = $ctx.Response
    try {
        $path = $ctx.Request.Url.AbsolutePath.ToLowerInvariant()
        $res.Headers['Cache-Control'] = 'no-store'
        $res.Headers['Access-Control-Allow-Origin'] = '*'
        $method = $ctx.Request.HttpMethod
        if ($method -eq 'OPTIONS') {
            $res.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
            $res.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
            $res.Headers['Access-Control-Allow-Private-Network'] = 'true'
            $res.StatusCode = 204
            $bytes = New-Object byte[] 0
        } elseif (($path -eq '/suno' -or $path -eq '/report') -and $method -eq 'POST') {
            $reader = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
            Add-ConnectorReport ($reader.ReadToEnd())
            $bytes = [Text.Encoding]::UTF8.GetBytes('ok'); $res.ContentType = 'text/plain'
        } elseif ($path -eq '/browser-connector.user.js' -or $path -eq '/suno-connector.user.js') {
            $js = [IO.File]::ReadAllText($ConnectorFile, [Text.Encoding]::UTF8) -replace '__PORT__', [string]$listenerPort
            $bytes = [Text.Encoding]::UTF8.GetBytes($js); $res.ContentType = 'text/javascript; charset=utf-8'
        } elseif ($path -eq '/overlay-state' -and $method -eq 'POST') {
            $reader = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
            Set-OverlayState ($reader.ReadToEnd())
            $bytes = [Text.Encoding]::UTF8.GetBytes('ok'); $res.ContentType = 'text/plain'
        } elseif ($path -eq '/debug') {
            $bytes = [Text.Encoding]::UTF8.GetBytes((Get-DebugJson)); $res.ContentType = 'application/json; charset=utf-8'
        } elseif ($path -eq '/' -or $path -eq '/overlay' -or $path -eq '/overlay.html') {
            $bytes = [IO.File]::ReadAllBytes($OverlayFile); $res.ContentType = 'text/html; charset=utf-8'
        } elseif ($path -eq '/data') {
            $bytes = [Text.Encoding]::UTF8.GetBytes((Get-PayloadJson)); $res.ContentType = 'application/json; charset=utf-8'
        } elseif ($path -eq '/health') {
            $bytes = [Text.Encoding]::UTF8.GetBytes('ok'); $res.ContentType = 'text/plain'
        } else {
            $res.StatusCode = 404
            $bytes = [Text.Encoding]::UTF8.GetBytes('Not found'); $res.ContentType = 'text/plain'
        }
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
    } finally {
        try { $res.Close() } catch {}
    }
}

function Get-SettingsStamp {
    if (Test-Path -LiteralPath $SettingsPath) { return (Get-Item -LiteralPath $SettingsPath).LastWriteTimeUtc.Ticks }
    return 0
}

# ---------- main ----------
$Settings = Read-Settings
$settingsStamp = Get-SettingsStamp
Initialize-MediaSessions

if ($Once) {
    Update-NowPlaying
    Get-PayloadJson
    exit
}

# ---------- tray icon (the AOSABI watermark) while the helper runs ----------
$script:Tray = $null
$script:QuitRequested = $false
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $trayIcon = Get-AppIcon $PSScriptRoot 16
    if ($trayIcon -eq $null) { $trayIcon = [System.Drawing.SystemIcons]::Application }
    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.Icon = $trayIcon
    $script:Tray.Text = 'AOverlay for Stream Music - by AOSABI'
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $miOpen = $menu.Items.Add('Open settings')
    $miOpen.Add_Click({
        Start-Process -FilePath $PowerShellExe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', "`"$(Join-Path $PSScriptRoot 'AOverlaySettings.ps1')`"")
    })
    $miRestart = $menu.Items.Add('Restart helper')
    $miRestart.Add_Click({ $script:QuitRequested = 'restart' })
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $miCredit = $menu.Items.Add($AppCredit)
    $miCredit.Enabled = $false
    $miQuit = $menu.Items.Add('Quit')
    $miQuit.Add_Click({ $script:QuitRequested = 'quit' })
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.Add_DoubleClick({ $miOpen.PerformClick() })
    $script:Tray.Visible = $true
} catch { Write-Log "Tray icon unavailable: $($_.Exception.Message)" }

function Stop-Everything {
    try { if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() } } catch {}
    try { if ($listener) { $listener.Stop(); $listener.Close() } } catch {}
    try { $script:HelperMutex.ReleaseMutex(); $script:HelperMutex.Dispose() } catch {}
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

$listener = Start-Listener ([int]$Settings.port)
$listenerPort = [int]$Settings.port
$pending = $null
if ($listener) { $pending = $listener.GetContextAsync() }
$nextPoll = Get-Date
$nextListenerTry = (Get-Date).AddSeconds(5)

while ($true) {
    # Let the tray icon respond to clicks.
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    if ($script:QuitRequested) {
        $what = $script:QuitRequested
        Write-Log "Helper stopping ($what)"
        Stop-Everything
        if ($what -eq 'restart') { Start-Helper $PSScriptRoot }
        exit
    }

    $now = Get-Date
    if ($now -ge $nextPoll) {
        $stamp = Get-SettingsStamp
        if ($stamp -ne $settingsStamp) {
            $settingsStamp = $stamp
            $Settings = Read-Settings
            if ([int]$Settings.port -ne $listenerPort) {
                if ($listener) { try { $listener.Stop(); $listener.Close() } catch {} }
                $listener = Start-Listener ([int]$Settings.port)
                $listenerPort = [int]$Settings.port
                $pending = $null
                if ($listener) { $pending = $listener.GetContextAsync() }
            }
        }
        try { Update-NowPlaying } catch { Write-Log "Update failed: $($_.Exception.Message)" }
        if ($script:SmtcManager -eq $null -and $now.Second % 30 -eq 0) { Initialize-MediaSessions }
        $nextPoll = $now.AddMilliseconds(1000)
    }

    if ($listener -eq $null) {
        if ($now -ge $nextListenerTry) {
            $listener = Start-Listener ([int]$Settings.port)
            if ($listener) { $pending = $listener.GetContextAsync() }
            $nextListenerTry = $now.AddSeconds(15)
        }
        Start-Sleep -Milliseconds 200
        continue
    }

    try {
        if ($pending.Wait(50)) {
            $ctx = $pending.Result
            $pending = $listener.GetContextAsync()
            Send-Response $ctx
        }
    } catch {
        Write-Log "Web server error: $($_.Exception.Message)"
        try { $pending = $listener.GetContextAsync() } catch { $listener = $null }
    }
}
