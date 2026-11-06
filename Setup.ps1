# AOverlay for Stream Music - made and distributed by AOSABI. See LICENSE.txt.
# Installer window. Start it with Install.cmd.
# Installs for the current Windows user only, so no admin rights are needed.

$ErrorActionPreference = 'Continue'
$SourceApp = Join-Path $PSScriptRoot 'app'
. (Join-Path $SourceApp 'Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$existing = $null
try { $existing = (Get-ItemProperty -Path $UninstallKey -ErrorAction Stop).InstallLocation } catch {}
$defaultDir = Join-Path $env:LOCALAPPDATA ('Programs\' + $AppTitle)
if ($existing) { $defaultDir = $existing }

# The earlier version of this program was called 'Now Playing Overlay'.
$legacy = $null
try { $legacy = (Get-ItemProperty -Path $LegacyUninstallKey -ErrorAction Stop).InstallLocation } catch {}

# Removes the earlier 'Now Playing Overlay' install, keeping the user's look settings.
function Remove-LegacyVersion([string]$newDir) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*NowPlayingHelper.ps1*' -or $_.CommandLine -like '*NowPlayingSettings.ps1*' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
    $oldSettings = Join-Path $LegacyDataDir 'settings.json'
    if ((Test-Path -LiteralPath $oldSettings) -and -not (Test-Path -LiteralPath $SettingsPath)) {
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        Copy-Item -LiteralPath $oldSettings -Destination $SettingsPath -Force
    }
    $oldDir = $null
    try { $oldDir = (Get-ItemProperty -Path $LegacyUninstallKey -ErrorAction Stop).InstallLocation } catch {}
    foreach ($l in $LegacyLinks) { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $LegacyStartMenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $LegacyUninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    # Only delete a folder that really is the old program.
    if ($oldDir -and (Test-Path -LiteralPath (Join-Path $oldDir 'NowPlayingHelper.ps1')) -and
        ($oldDir.TrimEnd('\') -ne $newDir.TrimEnd('\'))) {
        Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $LegacyDataDir) { Remove-Item -LiteralPath $LegacyDataDir -Recurse -Force -ErrorAction SilentlyContinue }
}

$ui = New-Object System.Drawing.Font('Segoe UI', 9)
$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppTitle Setup"
$form.ClientSize = New-Object System.Drawing.Size(600, 516)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = $ui
$setupIcon = Get-AppIcon $SourceApp 32
if ($setupIcon) { $form.Icon = $setupIcon }

function Add-Ctl([string]$type, [int]$x, [int]$y, [int]$w, [int]$h) {
    $c = New-Object "System.Windows.Forms.$type"
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, $h)
    $form.Controls.Add($c)
    return $c
}

$title = Add-Ctl 'Label' 20 16 560 38
$title.Text = $AppTitle
$title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)

$about = Add-Ctl 'Label' 22 60 556 104
$about.Text = "Shows what VLC, Suno, Spotify and SoundCloud are playing on your OBS stream, as 'Now Playing -' followed by scrolling song names. When more than one is playing, it says how many songs are open and names each one.`n`nAfter installing, a settings window opens where you pick the font, colors, highlight and transparency."

$lbDir = Add-Ctl 'Label' 22 172 300 22
$lbDir.Text = 'Install to:'
$tbDir = Add-Ctl 'TextBox' 22 196 450 26
$tbDir.Text = $defaultDir
$btBrowse = Add-Ctl 'Button' 480 194 98 30
$btBrowse.Text = 'Browse...'
$btBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose a folder for $AppTitle"
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog($form) -eq 'OK') { $tbDir.Text = Join-Path $dlg.SelectedPath $AppTitle }
})

$ckDesk = Add-Ctl 'CheckBox' 22 238 556 24
$ckDesk.Text = "Put a '$AppTitle Settings' shortcut on my desktop"
$ckDesk.Checked = $true
$ckAuto = Add-Ctl 'CheckBox' 22 266 556 24
$ckAuto.Text = 'Start the overlay helper automatically when Windows starts'
$ckAuto.Checked = $true
$ckOpen = Add-Ctl 'CheckBox' 22 294 556 24
$ckOpen.Text = 'Open the settings window when setup finishes'
$ckOpen.Checked = $true

$status = Add-Ctl 'Label' 22 330 556 50
$status.ForeColor = [System.Drawing.Color]::DimGray
if ($existing) { $status.Text = 'An earlier copy is installed. Clicking Update replaces it and keeps your settings.' }
elseif ($legacy) { $status.Text = 'Now Playing Overlay (this program''s old name) is installed. Clicking Update replaces it and keeps your settings.' }

$lnLicense = Add-Ctl 'LinkLabel' 22 392 340 44
$lnLicense.Text = "Installing means you agree to the license.`nClick here to read it."
$lnLicense.LinkArea = New-Object System.Windows.Forms.LinkArea(0, $lnLicense.Text.Length)
$lnLicense.Add_LinkClicked({
    $lic = Join-Path $PSScriptRoot 'LICENSE.txt'
    if (Test-Path -LiteralPath $lic) { Start-Process notepad.exe -ArgumentList "`"$lic`"" }
})
$lbCredit = Add-Ctl 'Label' 22 480 556 24
$lbCredit.Text = "$AppTitle $AppVersion  -  $AppCredit"
$lbCredit.ForeColor = [System.Drawing.Color]::DimGray

$btInstall = Add-Ctl 'Button' 376 396 100 34
if ($existing -or $legacy) { $btInstall.Text = 'Update' } else { $btInstall.Text = 'Install' }
$btCancel = Add-Ctl 'Button' 484 396 94 34
$btCancel.Text = 'Cancel'
$btCancel.Add_Click({ $form.Close() })
$form.AcceptButton = $btInstall
$form.CancelButton = $btCancel

function Show-Step([string]$text) { $status.Text = $text; $status.Refresh() }

$btInstall.Add_Click({
    $dir = $tbDir.Text.Trim()
    if (-not $dir) { [void][System.Windows.Forms.MessageBox]::Show($form, 'Please choose a folder.', $form.Text); return }
    $btInstall.Enabled = $false; $btCancel.Enabled = $false
    try {
        Show-Step 'Stopping the old helper if it is running...'
        Stop-Helper
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*AOverlaySettings.ps1*' } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
        Start-Sleep -Milliseconds 300
        if ($legacy) {
            Show-Step 'Replacing the old Now Playing Overlay...'
            Remove-LegacyVersion $dir
        }

        Show-Step 'Copying files...'
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
        Copy-Item -Path (Join-Path $SourceApp '*') -Destination $dir -Recurse -Force -ErrorAction Stop
        foreach ($doc in @('LICENSE.txt', 'README.txt')) {
            $docPath = Join-Path $PSScriptRoot $doc
            if (Test-Path -LiteralPath $docPath) { Copy-Item -LiteralPath $docPath -Destination $dir -Force }
        }
        Get-ChildItem -LiteralPath $dir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        $ico = Get-AppIconFile $dir

        Show-Step 'Making shortcuts...'
        New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
        New-Shortcut (Join-Path $StartMenuDir "$AppTitle Settings.lnk") (Join-Path $dir 'AOverlaySettings.ps1') "Change how $AppTitle looks" -Sta -icon $ico
        New-Shortcut (Join-Path $StartMenuDir "Uninstall $AppTitle.lnk") (Join-Path $dir 'Uninstall.ps1') "Remove $AppTitle" -Sta -icon $ico
        if ($ckDesk.Checked) {
            New-Shortcut $DesktopLink (Join-Path $dir 'AOverlaySettings.ps1') "Change how $AppTitle looks" -Sta -icon $ico
        } else {
            Remove-Item -LiteralPath $DesktopLink -Force -ErrorAction SilentlyContinue
        }
        Set-HelperAutostart $ckAuto.Checked $dir

        Show-Step 'Adding it to the Windows apps list...'
        New-Item -Path $UninstallKey -Force | Out-Null
        $size = [int]((Get-ChildItem -LiteralPath $dir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB) + 1
        $props = @{
            DisplayName     = $AppTitle
            DisplayVersion  = $AppVersion
            InstallLocation = $dir
            DisplayIcon     = $(if ($ico) { $ico } else { $PowerShellExe })
            Publisher       = $AppPublisher
            UninstallString = "`"$PowerShellExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$(Join-Path $dir 'Uninstall.ps1')`""
        }
        foreach ($k in $props.Keys) { New-ItemProperty -Path $UninstallKey -Name $k -Value $props[$k] -PropertyType String -Force | Out-Null }
        foreach ($k in @('NoModify', 'NoRepair')) { New-ItemProperty -Path $UninstallKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
        New-ItemProperty -Path $UninstallKey -Name 'EstimatedSize' -Value $size -PropertyType DWord -Force | Out-Null

        Show-Step 'Starting the helper...'
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        if (-not (Test-Path -LiteralPath $SettingsPath)) { Save-Settings (Get-DefaultSettings) }
        Start-Helper $dir

        $port = (Read-Settings).port
        Show-Step 'Done.'
        [void][System.Windows.Forms.MessageBox]::Show($form,
            "$AppTitle is installed.`n`nTo show it on stream: in OBS, click + under Sources, choose Browser, and use this URL:`n`n    http://localhost:$port/`n`nThe settings window has a Copy URL button too.",
            $form.Text, 'OK', 'Information')
        if ($ckOpen.Checked) {
            Start-Process -FilePath $PowerShellExe -WindowStyle Hidden -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', "`"$(Join-Path $dir 'AOverlaySettings.ps1')`"")
        }
        $form.Close()
    } catch {
        Show-Step ('Setup could not finish: ' + $_.Exception.Message)
        $btInstall.Enabled = $true; $btCancel.Enabled = $true
    }
})

[void]$form.ShowDialog()
