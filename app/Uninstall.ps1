# AOverlay for Stream Music - made and distributed by AOSABI. See LICENSE.txt.
# Uninstaller.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$ans = [System.Windows.Forms.MessageBox]::Show("Remove $AppTitle from this computer?", "Uninstall $AppTitle", 'YesNo', 'Question')
if ($ans -ne 'Yes') { exit }

Stop-Helper
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*AOverlaySettings.ps1*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }

Remove-Item -LiteralPath $StartupLink -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $DesktopLink -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $StartMenuDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue

$keep = [System.Windows.Forms.MessageBox]::Show("Also delete your saved overlay settings (font, colors and so on)?`n`nChoose No to keep them in case you install it again.", "Uninstall $AppTitle", 'YesNo', 'Question')
if ($keep -eq 'Yes') { Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue }

# The program folder is removed a moment after this window closes.
$appDir = $PSScriptRoot
Set-Location $env:TEMP
Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -WindowStyle Hidden -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$appDir`""

[void][System.Windows.Forms.MessageBox]::Show("$AppTitle has been removed. Remember to delete its Browser source in OBS too.", "Uninstall $AppTitle", 'OK', 'Information')
