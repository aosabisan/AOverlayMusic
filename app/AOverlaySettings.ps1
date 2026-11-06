# AOverlay for Stream Music - made and distributed by AOSABI. See LICENSE.txt.
# Settings window.
# Every change is saved right away and shows up in OBS within a second.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Only one settings window at a time.
$created = $false
$script:SettingsMutex = [System.Threading.Mutex]::new($true, 'Local\AOverlayForStreamMusicSettings', [ref]$created)
if (-not $created) { exit }

$script:S = Read-Settings
$script:Loading = $true
$script:Bound = New-Object System.Collections.ArrayList
$script:SliderLabels = @{}
$script:SliderSuffix = @{}
$script:ColorButtons = New-Object System.Collections.ArrayList
$script:FontCache = @{}
$script:Live = $null
$script:PvOffset = 0.0
$script:PvLoop = 0.0
$script:PvScroll = $false
$script:PvLastTick = [DateTime]::UtcNow

$UiFont = New-Object System.Drawing.Font('Segoe UI', 9)

# ---------------- small helpers ----------------
function Get-Font([string]$family, [single]$px, [bool]$bold, [bool]$italic) {
    $key = "$family|$px|$bold|$italic"
    if ($script:FontCache.ContainsKey($key)) { return $script:FontCache[$key] }
    $f = $null
    try {
        $fam = New-Object System.Drawing.FontFamily($family)
        $style = [System.Drawing.FontStyle]::Regular
        if ($bold) { $style = [System.Drawing.FontStyle]($style -bor [System.Drawing.FontStyle]::Bold) }
        if ($italic) { $style = [System.Drawing.FontStyle]($style -bor [System.Drawing.FontStyle]::Italic) }
        foreach ($st in @($style, [System.Drawing.FontStyle]::Regular, [System.Drawing.FontStyle]::Bold, [System.Drawing.FontStyle]::Italic)) {
            if ($fam.IsStyleAvailable($st)) { $f = New-Object System.Drawing.Font($fam, $px, $st, [System.Drawing.GraphicsUnit]::Pixel); break }
        }
    } catch {}
    if ($f -eq $null) { $f = New-Object System.Drawing.Font('Segoe UI', $px, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel) }
    $script:FontCache[$key] = $f
    return $f
}

function ConvertTo-Color([string]$hex, [double]$alpha = 1.0) {
    $c = [System.Drawing.Color]::White
    try { $c = [System.Drawing.ColorTranslator]::FromHtml($hex) } catch {}
    $a = [int][Math]::Max(0, [Math]::Min(255, [Math]::Round(255 * $alpha)))
    return [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B)
}

function Set-Changed {
    if ($script:Loading) { return }
    $script:SaveTimer.Stop()
    $script:SaveTimer.Start()
    $script:Preview.Invalidate()
}

function New-Ctl([string]$type, $parent, [int]$x, [int]$y, [int]$w, [int]$h) {
    $c = New-Object "System.Windows.Forms.$type"
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, $h)
    $c.Font = $UiFont
    $parent.Controls.Add($c)
    return $c
}

function Add-Label($parent, [string]$text, [int]$x, [int]$y, [int]$w = 120) {
    $l = New-Ctl 'Label' $parent $x ($y + 3) $w 20
    $l.Text = $text
    return $l
}

function Add-Check($parent, [string]$text, [int]$x, [int]$y, [string]$key, [int]$w = 360) {
    $c = New-Ctl 'CheckBox' $parent $x $y $w 22
    $c.Text = $text
    $c.Tag = $key
    $c.Add_CheckedChanged({ param($s, $e) if ($script:Loading) { return }; $script:S[$s.Tag] = $s.Checked; Set-Changed })
    [void]$script:Bound.Add($c)
    return $c
}

function Add-Number($parent, [int]$x, [int]$y, [int]$min, [int]$max, [string]$key, [int]$w = 70) {
    $n = New-Ctl 'NumericUpDown' $parent $x $y $w 24
    $n.Minimum = $min
    $n.Maximum = $max
    $n.Tag = $key
    $n.Add_ValueChanged({ param($s, $e) if ($script:Loading) { return }; $script:S[$s.Tag] = [int]$s.Value; Set-Changed })
    [void]$script:Bound.Add($n)
    return $n
}

function Add-Text($parent, [int]$x, [int]$y, [int]$w, [string]$key) {
    $t = New-Ctl 'TextBox' $parent $x $y $w 24
    $t.Tag = $key
    $t.Add_TextChanged({ param($s, $e) if ($script:Loading) { return }; $script:S[$s.Tag] = $s.Text; Set-Changed })
    [void]$script:Bound.Add($t)
    return $t
}

function Add-Slider($parent, [int]$x, [int]$y, [int]$min, [int]$max, [string]$key, [string]$suffix) {
    $tb = New-Ctl 'TrackBar' $parent $x ($y - 4) 190 30
    $tb.AutoSize = $false
    $tb.TickStyle = 'None'
    $tb.Minimum = $min
    $tb.Maximum = $max
    $tb.Tag = $key
    $lbl = New-Ctl 'Label' $parent ($x + 194) ($y + 3) 60 20
    $script:SliderLabels[$key] = $lbl
    $script:SliderSuffix[$key] = $suffix
    $tb.Add_ValueChanged({
        param($s, $e)
        $script:SliderLabels[$s.Tag].Text = '{0}{1}' -f $s.Value, $script:SliderSuffix[$s.Tag]
        if ($script:Loading) { return }
        $script:S[$s.Tag] = [int]$s.Value
        Set-Changed
    })
    [void]$script:Bound.Add($tb)
    return $tb
}

function Update-ColorButton($b) {
    $c = ConvertTo-Color ([string]$script:S[$b.Tag])
    $b.BackColor = [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B)
    $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
    if ($lum -gt 140) { $b.ForeColor = [System.Drawing.Color]::Black } else { $b.ForeColor = [System.Drawing.Color]::White }
    $b.Text = ([string]$script:S[$b.Tag]).ToUpper()
}

function Add-ColorButton($parent, [int]$x, [int]$y, [string]$key) {
    $b = New-Ctl 'Button' $parent $x ($y - 1) 120 27
    $b.FlatStyle = 'Flat'
    $b.Tag = $key
    $b.Add_Click({
        param($s, $e)
        $dlg = New-Object System.Windows.Forms.ColorDialog
        $dlg.FullOpen = $true
        $dlg.AnyColor = $true
        $dlg.Color = ConvertTo-Color ([string]$script:S[$s.Tag])
        if ($dlg.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:S[$s.Tag] = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
            Update-ColorButton $s
            Set-Changed
        }
    })
    [void]$script:ColorButtons.Add($b)
    return $b
}

# ---------------- window ----------------
$script:Form = New-Object System.Windows.Forms.Form
$Form.Text = "$AppTitle - Settings"
$Form.ClientSize = New-Object System.Drawing.Size(830, 854)
$Form.FormBorderStyle = 'FixedSingle'
$Form.MaximizeBox = $false
$Form.StartPosition = 'CenterScreen'
$Form.Font = $UiFont
$winIcon = Get-AppIcon $PSScriptRoot 32
if ($winIcon) { $Form.Icon = $winIcon }
$lbCredit = New-Ctl 'Label' $Form 12 820 400 20
$lbCredit.Text = "$AppTitle $AppVersion  -  $AppCredit"
$lbCredit.ForeColor = [System.Drawing.Color]::DimGray

# --- Look ---
$gLook = New-Ctl 'GroupBox' $Form 12 8 400 356
$gLook.Text = 'Look'
Add-Label $gLook 'Header text' 14 26 | Out-Null
$tbHeader = Add-Text $gLook 140 26 240 'headerText'

Add-Label $gLook 'Font' 14 60 | Out-Null
$cbFont = New-Ctl 'ComboBox' $gLook 140 60 240 24
$cbFont.DropDownStyle = 'DropDownList'
$cbFont.DrawMode = 'OwnerDrawFixed'
$cbFont.ItemHeight = 24
$cbFont.DropDownWidth = 430
$cbFont.MaxDropDownItems = 18
$families = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name } | Sort-Object -Unique
foreach ($f in $families) { [void]$cbFont.Items.Add($f) }
$cbFont.Add_DrawItem({
    param($s, $e)
    $e.DrawBackground()
    if ($e.Index -ge 0) {
        $name = [string]$s.Items[$e.Index]
        $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        if ($selected) { $brush = [System.Drawing.SystemBrushes]::HighlightText } else { $brush = [System.Drawing.SystemBrushes]::ControlText }
        $e.Graphics.DrawString($name, $UiFont, $brush, [single]($e.Bounds.X + 3), [single]($e.Bounds.Y + 4))
        if ($e.Bounds.Width -gt 300) {
            $sample = Get-Font $name 17 $false $false
            $e.Graphics.DrawString('Now Playing', $sample, $brush, [single]($e.Bounds.X + 215), [single]($e.Bounds.Y + 2))
        }
    }
    $e.DrawFocusRectangle()
})
$cbFont.Add_SelectedIndexChanged({
    param($s, $e)
    if ($script:Loading -or $s.SelectedItem -eq $null) { return }
    $script:S['fontFamily'] = [string]$s.SelectedItem
    Set-Changed
})

Add-Label $gLook 'Text size' 14 94 | Out-Null
$nuSize = Add-Number $gLook 140 94 10 160 'fontSize'
$ckBold = Add-Check $gLook 'Bold' 222 95 'fontBold' 60
$ckItalic = Add-Check $gLook 'Italic' 290 95 'fontItalic' 70

Add-Label $gLook 'Text color' 14 130 | Out-Null
$btText = Add-ColorButton $gLook 140 130 'textColor'
Add-Label $gLook 'Highlight color' 14 164 | Out-Null
$btHl = Add-ColorButton $gLook 140 164 'highlightColor'
Add-Label $gLook '(header and labels)' 266 164 130 | Out-Null
$ckBox = Add-Check $gLook 'Show a background box behind the text' 14 198 'showBackground'
Add-Label $gLook 'Background color' 14 228 | Out-Null
$btBg = Add-ColorButton $gLook 140 228 'backgroundColor'

Add-Label $gLook 'Background' 14 264 | Out-Null
Add-Label $gLook 'transparency' 14 280 | Out-Null
$slBgT = Add-Slider $gLook 136 270 0 100 'backgroundTransparency' '%'
Add-Label $gLook 'Whole overlay' 14 310 | Out-Null
Add-Label $gLook 'transparency' 14 326 | Out-Null
$slAllT = Add-Slider $gLook 136 316 0 90 'overallTransparency' '%'

# --- Extras ---
$gMore = New-Ctl 'GroupBox' $Form 12 370 400 196
$gMore.Text = 'Scrolling and extras'
Add-Label $gMore 'Scroll speed' 14 26 | Out-Null
$slSpeed = Add-Slider $gMore 136 30 20 300 'scrollSpeed' ''
Add-Label $gMore 'Rounded corners' 14 60 | Out-Null
$nuRadius = Add-Number $gMore 140 60 0 60 'cornerRadius'
$ckShadow = Add-Check $gMore 'Text shadow' 222 61 'textShadow' 150
$ckAlways = Add-Check $gMore 'Always scroll, even when the names fit' 14 92 'alwaysScroll'
$ckHide = Add-Check $gMore 'Hide the overlay when nothing is playing' 14 116 'hideWhenIdle'
$ckArtist = Add-Check $gMore 'Show artist names' 14 140 'showArtist'
$ckSrc1 = Add-Check $gMore 'Show "VLC:" or "Suno:" even when only one song plays' 14 164 'showSourceSingle'

# --- Sources ---
$gSrc = New-Ctl 'GroupBox' $Form 12 572 400 240
$gSrc.Text = 'Music sources (untick to hide one)'
$ckVlc = Add-Check $gSrc 'VLC media player' 14 22 'vlcEnabled' 180
Add-Label $gSrc 'shown as' 196 22 56 | Out-Null
$tbVlcL = Add-Text $gSrc 254 22 130 'vlcLabel'
$ckSuno = Add-Check $gSrc 'Suno (web)' 14 50 'sunoEnabled' 180
Add-Label $gSrc 'shown as' 196 50 56 | Out-Null
$tbSunoL = Add-Text $gSrc 254 50 130 'sunoLabel'
$ckSpot = Add-Check $gSrc 'Spotify (app or web)' 14 78 'spotifyEnabled' 180
Add-Label $gSrc 'shown as' 196 78 56 | Out-Null
$tbSpotL = Add-Text $gSrc 254 78 130 'spotifyLabel'
$ckSc = Add-Check $gSrc 'SoundCloud (web)' 14 106 'soundcloudEnabled' 180
Add-Label $gSrc 'shown as' 196 106 56 | Out-Null
$tbScL = Add-Text $gSrc 254 106 130 'soundcloudLabel'
Add-Label $gSrc 'Several playing' 14 140 112 | Out-Null
$tbMulti = Add-Text $gSrc 130 140 254 'multipleTracksText'
$lbMultiTip = New-Ctl 'Label' $gSrc 130 166 260 18
$lbMultiTip.Text = '{count} becomes the number of songs playing'
$lbMultiTip.ForeColor = [System.Drawing.Color]::DimGray
$lbConn = New-Ctl 'Label' $gSrc 14 188 376 20
$lbConn.Text = 'Browser connector: checking...'
$btConn = New-Ctl 'Button' $gSrc 14 208 250 26
$btConn.Text = 'Set up the browser connector...'
$btConn.Add_Click({ Show-ConnectorSetup })

# --- Preview ---
$gPv = New-Ctl 'GroupBox' $Form 424 8 394 216
$gPv.Text = 'Preview'
$script:Preview = New-Ctl 'Panel' $gPv 12 24 370 150
$Preview.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($Preview, $true, $null)
$ckAnim = New-Ctl 'CheckBox' $gPv 12 182 120 22
$ckAnim.Text = 'Animate'
$ckAnim.Checked = $true
$script:PvAnimate = $true
$ckAnim.Add_CheckedChanged({ $script:PvAnimate = $ckAnim.Checked; $script:Preview.Invalidate() })
$ckTwo = New-Ctl 'CheckBox' $gPv 140 182 246 22
$ckTwo.Text = 'Two-song example'
$ckTwo.Add_CheckedChanged({ $script:Preview.Invalidate() })

$checkTile = New-Object System.Drawing.Bitmap(24, 24)
$gt = [System.Drawing.Graphics]::FromImage($checkTile)
$gt.Clear([System.Drawing.Color]::FromArgb(88, 88, 96))
$dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(64, 64, 72))
$gt.FillRectangle($dark, 0, 0, 12, 12)
$gt.FillRectangle($dark, 12, 12, 12, 12)
$gt.Dispose()
$CheckBrush = New-Object System.Drawing.TextureBrush($checkTile)

function Get-PreviewTracks {
    if ($ckTwo.Checked) {
        $ex = New-Object System.Collections.ArrayList
        if ($script:S.vlcEnabled) { [void]$ex.Add([pscustomobject]@{ source = [string]$script:S.vlcLabel; name = 'Midnight Drive - Example Artist' }) }
        if ($script:S.sunoEnabled) { [void]$ex.Add([pscustomobject]@{ source = [string]$script:S.sunoLabel; name = 'Neon Skyline - Example Creator' }) }
        if ($script:S.spotifyEnabled) { [void]$ex.Add([pscustomobject]@{ source = [string]$script:S.spotifyLabel; name = 'Golden Hour - Example Band' }) }
        if ($script:S.soundcloudEnabled) { [void]$ex.Add([pscustomobject]@{ source = [string]$script:S.soundcloudLabel; name = 'Late Night Mix - Example DJ' }) }
        if ($ex.Count -gt 0) { return $ex.ToArray() }
    }
    if ($script:Live -ne $null -and @($script:Live.tracks).Count -gt 0) { return @($script:Live.tracks) }
    return @([pscustomobject]@{ source = [string]$script:S.vlcLabel; name = 'Your Song Title - Artist' })
}

function Get-Segments($tracks) {
    $segs = New-Object System.Collections.ArrayList
    $S = $script:S
    if ($tracks.Count -eq 1) {
        if ($S.showSourceSingle -and $tracks[0].source) { [void]$segs.Add(@($tracks[0].source + ': ', $true)) }
        [void]$segs.Add(@([string]$tracks[0].name, $false))
    } else {
        [void]$segs.Add(@(($S.multipleTracksText -replace '\{count\}', [string]$tracks.Count), $true))
        foreach ($t in $tracks) {
            [void]$segs.Add(@([string]$S.separator, $true))
            if ($t.source) { [void]$segs.Add(@($t.source + ': ', $true)) }
            [void]$segs.Add(@([string]$t.name, $false))
        }
    }
    return ,$segs
}

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = [Math]::Min($r, [Math]::Min($w, $h) / 2)
    if ($r -lt 1) { $p.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h))); return $p }
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$script:Fmt = [System.Drawing.StringFormat]::GenericTypographic.Clone()
$script:Fmt.FormatFlags = $script:Fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces -bor [System.Drawing.StringFormatFlags]::NoWrap

# Draws one piece of text: drop shadow, then outline, then the letters, each with its own
# transparency. The outline/shadow never shift where the letters sit.
function Draw-Text($g, [string]$text, $font, [single]$x, [single]$y, $isHl, [single]$scale) {
    $isHl = ($isHl -eq $true)
    $S = $script:S
    $whole = (100 - $S.overallTransparency) / 100.0
    $textA = $whole * (100 - $S.textTransparency) / 100.0
    $olA   = $whole * (100 - $S.outlineTransparency) / 100.0
    $shA   = $whole * (100 - $S.shadowTransparency) / 100.0
    $fc = ConvertTo-Color $(if ($isHl) { $S.highlightColor } else { $S.textColor }) 1
    $ol = $S.outlineEnabled -and $S.outlineThickness -gt 0
    $t = [Math]::Max(0.6, $S.outlineThickness * $scale)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString($text, $font.FontFamily, [int]$font.Style, $font.Size, (New-Object System.Drawing.PointF($x, $y)), $script:Fmt)

    if ($S.textShadow -and $shA -gt 0) {
        $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Translate(1.2, 2)
        $sp = $path.Clone(); $sp.Transform($m)
        $sc = [System.Drawing.Color]::FromArgb([int](200 * $shA), 0, 0, 0)
        if ($ol) { $pen = New-Object System.Drawing.Pen $sc, ([single](2 * $t + 2)); $pen.LineJoin = 'Round'; $g.DrawPath($pen, $sp); $pen.Dispose() }
        $sb = New-Object System.Drawing.SolidBrush $sc; $g.FillPath($sb, $sp); $sb.Dispose(); $sp.Dispose(); $m.Dispose()
    }
    if ($ol -and $olA -gt 0) {
        $f = $S.outlineFade * $scale
        $oc = ConvertTo-Color $S.outlineColor 1
        $steps = [int][Math]::Min(8, [Math]::Ceiling($f))
        for ($i = $steps; $i -ge 1; $i--) {
            $a = $olA * 0.5 * (1 - $i / ($steps + 1))
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int](255 * $a), $oc.R, $oc.G, $oc.B)), ([single](2 * ($t + $f * $i / $steps)))
            $pen.LineJoin = 'Round'; $g.DrawPath($pen, $path); $pen.Dispose()
        }
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int](255 * $olA), $oc.R, $oc.G, $oc.B)), ([single](2 * $t))
        $pen.LineJoin = 'Round'; $g.DrawPath($pen, $path); $pen.Dispose()
    }
    $fb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int](255 * $textA), $fc.R, $fc.G, $fc.B))
    $g.FillPath($fb, $path); $fb.Dispose(); $path.Dispose()
}

# Draws a bitmap with its left and right edges faded softly to transparent, over any background.
function Draw-Faded($g, $bmp, [int]$dx, [int]$dy, [single]$fade) {
    $w = $bmp.Width; $h = $bmp.Height
    $fi = [int][Math]::Max(1, [Math]::Round($fade))
    if ($fi * 2 -ge $w) { $fi = [int][Math]::Max(1, [Math]::Floor($w / 2) - 1) }
    $mid = $w - 2 * $fi
    if ($mid -gt 0) {
        $g.DrawImage($bmp, (New-Object System.Drawing.Rectangle(($dx + $fi), $dy, $mid, $h)), $fi, 0, $mid, $h, [System.Drawing.GraphicsUnit]::Pixel)
    }
    for ($i = 0; $i -lt $fi; $i++) {
        $al = [single](($i + 0.5) / $fi)
        $cm = New-Object System.Drawing.Imaging.ColorMatrix; $cm.Matrix33 = $al
        $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
        $g.DrawImage($bmp, (New-Object System.Drawing.Rectangle(($dx + $i), $dy, 1, $h)), [single]$i, [single]0, [single]1, [single]$h, [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $g.DrawImage($bmp, (New-Object System.Drawing.Rectangle(($dx + $w - 1 - $i), $dy, 1, $h)), [single]($w - 1 - $i), [single]0, [single]1, [single]$h, [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $ia.Dispose()
    }
}

function Draw-PvBox($g, $x0, $y0, $barW, $barH, $scale) {
    $S = $script:S
    if (-not $S.showBackground) { return }
    $oa = (100 - $S.overallTransparency) / 100.0
    $bgA = (100 - $S.backgroundTransparency) / 100.0 * $oa
    if ($bgA -le 0) { return }
    $path = New-RoundRect $x0 $y0 $barW $barH ($S.cornerRadius * $scale)
    $b = New-Object System.Drawing.SolidBrush (ConvertTo-Color $S.backgroundColor $bgA)
    $g.FillPath($b, $path); $b.Dispose(); $path.Dispose()
}

# Measures everything at one text size. (Names here avoid $w/$h: PowerShell treats
# $w and $W as the same variable, which used to squash the preview.)
function Measure-Pv($g, [single]$px) {
    $S = $script:S
    $m = @{}
    $m.Px = $px
    $m.Font = Get-Font $S.fontFamily $px $S.fontBold $S.fontItalic
    $m.Segs = Get-Segments (Get-PreviewTracks)
    $m.Widths = @()
    $m.TextW = 0.0
    foreach ($sg in $m.Segs) { $segW = $g.MeasureString($sg[0], $m.Font, 100000, $script:Fmt).Width; $m.Widths += $segW; $m.TextW += $segW }
    $m.HeadW = 0.0
    if ($S.headerText) { $m.HeadW = $g.MeasureString($S.headerText, $m.Font, 100000, $script:Fmt).Width }
    $m.HeadGap = $(if ($S.headerText) { $px * 0.5 } else { 0 })
    # Room for the font's lean plus outline and shadow, like the overlay.
    $reach = $(if ($S.outlineEnabled) { $S.outlineThickness + $S.outlineFade * 2 } else { 0 }) + $(if ($S.textShadow) { 6 } else { 0 })
    $m.Ext = $px * 0.35 + $reach * ($px / [Math]::Max(1, $S.fontSize))
    $m.PadX = [Math]::Max($px * 0.7, $m.Ext)
    $m.PadY = $px * 0.28
    $m.LineH = $px * 1.3
    $m.BarH = $m.LineH + 2 * $m.PadY
    $m.FixedW = 2 * $m.PadX + $m.HeadW + $m.HeadGap + $m.TextW
    return $m
}

# Should the preview scroll? Only when the text on stream scrolls (or Always scroll is on).
function Test-PvScroll($m) {
    $S = $script:S
    if ($S.alwaysScroll) { return $true }
    $ov = $null
    if ($script:Live -ne $null) { $ov = $script:Live.overlay }
    if ($ov -eq $null) { return $false }
    $showingLive = (-not $ckTwo.Checked) -and $script:Live -ne $null -and @($script:Live.tracks).Count -gt 0
    if ($showingLive) { return [bool]$ov.scrolling }
    # Example text: estimate it at full size against the OBS source's width.
    $full = $m.FixedW * ($S.fontSize / $m.Px)
    return ($full -gt ([int]$ov.width - 6))
}

function Draw-Preview($g, [int]$PanelW, [int]$PanelH) {
    $S = $script:S
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAlias'
    $g.FillRectangle($CheckBrush, 0, 0, $PanelW, $PanelH)

    $scale = 0.6
    $px = [single][Math]::Max(9, [Math]::Min(40, $S.fontSize * $scale))
    $m = Measure-Pv $g $px
    $scroll = Test-PvScroll $m
    $script:PvScroll = $scroll

    if (-not $scroll) {
        # Still text: shrink the preview to fit if needed, so all of it always shows.
        if ($m.FixedW -gt ($PanelW - 12)) {
            $px = [single][Math]::Max(6, $px * ($PanelW - 12) / $m.FixedW)
            $m = Measure-Pv $g $px
        }
        $k = $px / [Math]::Max(1, $S.fontSize)
        $ty0 = ($m.LineH - $m.Font.GetHeight($g)) / 2
        $barW = $m.FixedW
        $x0 = ($PanelW - $barW) / 2
        $y0 = $PanelH / 2.0 - $m.BarH / 2
        $ty = $y0 + $m.PadY + $ty0
        Draw-PvBox $g $x0 $y0 $barW $m.BarH $k
        $x = $x0 + $m.PadX
        if ($S.headerText) { Draw-Text $g $S.headerText $m.Font ([single]$x) ([single]$ty) $true $k; $x += $m.HeadW + $m.HeadGap }
        for ($i = 0; $i -lt $m.Segs.Count; $i++) { $seg = $m.Segs[$i]; $segText = [string]$seg[0]; $segHl = ($seg[1] -eq $true); Draw-Text $g $segText $m.Font ([single]$x) ([single]$ty) $segHl $k; $x += $m.Widths[$i] }
        return
    }

    # Scrolling: fixed header on the left; the title scrolls in its own area to the right,
    # fading softly at both ends so no letter, outline or shadow is ever cut.
    $k = $px / [Math]::Max(1, $S.fontSize)
    $ty0 = ($m.LineH - $m.Font.GetHeight($g)) / 2
    $barW = $PanelW - 8; $x0 = 4.0
    $y0 = $PanelH / 2.0 - $m.BarH / 2
    $ty = $y0 + $m.PadY + $ty0
    Draw-PvBox $g $x0 $y0 $barW $m.BarH $k
    $hx = $x0 + $m.PadX
    $rl = [int][Math]::Round($hx + $m.HeadW + $m.HeadGap)
    $rr = [int][Math]::Round($x0 + $barW - $m.PadX)
    $rw = [Math]::Max(10, $rr - $rl)
    $fade = [single][Math]::Max($px * 1.5, $m.Ext * 2 + 4)
    if ($fade -gt $rw / 3) { $fade = [single]($rw / 3) }
    $gapW = [Math]::Max($px * 5, $fade * 2 + $px * 2)
    $script:PvLoop = $m.TextW + $gapW

    $rbmp = New-Object System.Drawing.Bitmap([int]$rw, [int]$PanelH)
    $rg = [System.Drawing.Graphics]::FromImage($rbmp)
    $rg.SmoothingMode = 'AntiAlias'; $rg.TextRenderingHint = 'AntiAlias'
    $base = $fade - ($script:PvOffset % $script:PvLoop)
    for ($sx = $base - $script:PvLoop; $sx -lt $rw; $sx += $script:PvLoop) {
        $x = $sx
        for ($i = 0; $i -lt $m.Segs.Count; $i++) { $seg = $m.Segs[$i]; $segText = [string]$seg[0]; $segHl = ($seg[1] -eq $true); Draw-Text $rg $segText $m.Font ([single]$x) ([single]$ty) $segHl $k; $x += $m.Widths[$i] }
    }
    $rg.Dispose()
    Draw-Faded $g $rbmp $rl 0 $fade
    $rbmp.Dispose()
    if ($S.headerText) { Draw-Text $g $S.headerText $m.Font ([single]$hx) ([single]$ty) $true $k }
}

$Preview.Add_Paint({
    param($s, $e)
    try { Draw-Preview $e.Graphics $s.ClientSize.Width $s.ClientSize.Height }
    catch {
        try {
            $e.Graphics.ResetClip()
            $e.Graphics.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $s.ClientSize.Width, $s.ClientSize.Height)
            $msg = 'Preview error: ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')'
            $e.Graphics.DrawString($msg, $UiFont, [System.Drawing.Brushes]::OrangeRed,
                (New-Object System.Drawing.RectangleF(4, 4, ($s.ClientSize.Width - 8), ($s.ClientSize.Height - 8))))
        } catch {}
    }
})

$anim = New-Object System.Windows.Forms.Timer
$anim.Interval = 33
$anim.Add_Tick({
    $now = [DateTime]::UtcNow
    $dt = [Math]::Min(0.1, ($now - $script:PvLastTick).TotalSeconds)
    $script:PvLastTick = $now
    if ($script:PvAnimate -and $script:PvScroll -and $script:PvLoop -gt 0) {
        $script:PvOffset = ($script:PvOffset + $script:S.scrollSpeed * 0.6 * $dt) % $script:PvLoop
        $script:Preview.Invalidate()
    }
})

# --- Transparency ---
$gTr = New-Ctl 'GroupBox' $Form 424 230 394 120
$gTr.Text = 'Transparency (separate for each)'
Add-Label $gTr 'Text' 14 24 | Out-Null
$slTxT = Add-Slider $gTr 120 28 0 100 'textTransparency' '%'
Add-Label $gTr 'Outline' 14 56 | Out-Null
$slOlTr = Add-Slider $gTr 120 60 0 100 'outlineTransparency' '%'
Add-Label $gTr 'Shadow' 14 88 | Out-Null
$slShTr = Add-Slider $gTr 120 92 0 100 'shadowTransparency' '%'

# --- Outline ---
$gOl = New-Ctl 'GroupBox' $Form 424 356 394 150
$gOl.Text = 'Outline around the letters'
$ckOl = Add-Check $gOl 'Outline the text' 14 24 'outlineEnabled' 200
Add-Label $gOl 'Outline color' 14 56 | Out-Null
$btOl = Add-ColorButton $gOl 140 56 'outlineColor'
Add-Label $gOl 'Thickness' 14 92 | Out-Null
$slOlT = Add-Slider $gOl 136 96 1 20 'outlineThickness' ' px'
Add-Label $gOl 'Fade distance' 14 124 | Out-Null
$slOlF = Add-Slider $gOl 136 128 0 20 'outlineFade' ' px'

# --- OBS ---
$gObs = New-Ctl 'GroupBox' $Form 424 512 394 250
$gObs.Text = 'Add it to OBS'
$lbHow = New-Ctl 'Label' $gObs 12 22 370 52
$lbHow.Text = "In OBS, click + under Sources, choose Browser, and paste this URL. Set the width to the space you want it to fill (1000 x 100 is a good start)."
$tbUrl = New-Ctl 'TextBox' $gObs 12 80 270 24
$tbUrl.ReadOnly = $true
$btCopy = New-Ctl 'Button' $gObs 290 78 92 27
$btCopy.Text = 'Copy URL'
$btCopy.Add_Click({ try { [System.Windows.Forms.Clipboard]::SetText($tbUrl.Text); $btCopy.Text = 'Copied!' } catch {} })
Add-Label $gObs 'Port' 12 116 40 | Out-Null
$nuPort = Add-Number $gObs 56 116 1024 65535 'port' 80
$lbPortTip = Add-Label $gObs '(change only if another program uses it)' 144 116 240

$lbStatus = New-Ctl 'Label' $gObs 12 150 370 40
$lbStatus.Text = 'Checking the helper...'
$btRestart = New-Ctl 'Button' $gObs 12 192 150 28
$btRestart.Text = 'Restart helper'
$btRestart.Add_Click({
    $lbStatus.Text = 'Restarting the helper...'
    Stop-Helper
    Start-Helper $PSScriptRoot
})
$ckAuto = New-Ctl 'CheckBox' $gObs 172 194 215 24
$ckAuto.Text = 'Start helper with Windows'
$ckAuto.Add_CheckedChanged({ if ($script:Loading) { return }; Set-HelperAutostart $ckAuto.Checked $PSScriptRoot })

function Update-UrlBox {
    $u = "http://localhost:$($script:S.port)/"
    if ($tbUrl.Text -ne $u) { $tbUrl.Text = $u; $btCopy.Text = 'Copy URL' }
}

# --- bottom buttons ---
$lbAuto = New-Ctl 'Label' $Form 424 770 394 34
$lbAuto.Text = 'Changes are saved by themselves and show up in OBS within a second.'
$btReset = New-Ctl 'Button' $Form 424 812 150 30
$btReset.Text = 'Reset to defaults'
$btReset.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show($script:Form, 'Put every setting back to how it started?', $AppTitle, 'YesNo', 'Question')
    if ($ans -eq 'Yes') {
        $keepPort = $script:S.port
        $script:S = Get-DefaultSettings
        $script:S.port = $keepPort
        Load-Controls
        Save-Settings $script:S
        $script:Preview.Invalidate()
    }
})
$btClose = New-Ctl 'Button' $Form 718 812 100 30
$btClose.Text = 'Close'
$btClose.Add_Click({ $script:Form.Close() })

# ---------------- browser connector setup ----------------
function Show-ConnectorSetup {
    $port = $script:S.port
    $url = "http://localhost:$port/browser-connector.user.js"
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Set up the browser connector'
    $d.ClientSize = New-Object System.Drawing.Size(540, 400)
    $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterParent'
    $d.Font = $UiFont
    $intro = New-Ctl 'Label' $d 16 12 508 62
    $intro.Text = "Suno, Spotify's web player and SoundCloud play in your browser, and Windows only tells the overlay about some of them, so songs can be missed (Spotify's web player always is). This small connector lets those sites tell the overlay directly. You only do this once in each browser you play music in."
    $s1 = New-Ctl 'Label' $d 16 82 508 40
    $s1.Text = "Step 1. Install Tampermonkey, a free browser add-on that runs small scripts like this one."
    $b1 = New-Ctl 'Button' $d 32 120 230 28
    $b1.Text = 'Open the Tampermonkey website'
    $b1.Add_Click({ Start-Process 'https://www.tampermonkey.net/' })
    $s1b = New-Ctl 'Label' $d 32 152 492 36
    $s1b.Text = "Using Firefox? Nothing more to do here, go to step 2. (Chrome, Edge and Brave need one extra switch: Tampermonkey's Details page > 'Allow user scripts'.)"
    $s2 = New-Ctl 'Label' $d 16 196 508 36
    $s2.Text = "Step 2. Open this link in the browser you play music in, then click Install (or Update) on the page Tampermonkey shows:"
    $tu = New-Ctl 'TextBox' $d 32 234 330 24
    $tu.ReadOnly = $true
    $tu.Text = $url
    $bc = New-Ctl 'Button' $d 370 232 70 27
    $bc.Text = 'Copy'
    $bc.Add_Click({ try { [System.Windows.Forms.Clipboard]::SetText($url) } catch {} }.GetNewClosure())
    $bo = New-Ctl 'Button' $d 446 232 78 27
    $bo.Text = 'Open'
    $bo.Add_Click({ Start-Process $url }.GetNewClosure())
    $s3 = New-Ctl 'Label' $d 16 274 508 54
    $s3.Text = "Step 3. Reload your Suno, Spotify or SoundCloud tabs and play a song. In the settings window, 'Browser connector' changes to 'working'.`n`nIf you had the older Suno-only connector, delete it in Tampermonkey's dashboard. If you ever change the port, do step 2 again."
    $bx = New-Ctl 'Button' $d 434 356 90 30
    $bx.Text = 'Done'
    $bx.Add_Click({ $d.Close() }.GetNewClosure())
    [void]$d.ShowDialog($script:Form)
}

# ---------------- load / save ----------------
function Load-Controls {
    $script:Loading = $true
    foreach ($c in $script:Bound) {
        $v = $script:S[$c.Tag]
        if ($c -is [System.Windows.Forms.CheckBox]) { $c.Checked = [bool]$v }
        elseif ($c -is [System.Windows.Forms.NumericUpDown]) { $c.Value = [Math]::Max($c.Minimum, [Math]::Min($c.Maximum, [decimal]$v)) }
        elseif ($c -is [System.Windows.Forms.TrackBar]) {
            $c.Value = [Math]::Max($c.Minimum, [Math]::Min($c.Maximum, [int]$v))
            $script:SliderLabels[$c.Tag].Text = '{0}{1}' -f $c.Value, $script:SliderSuffix[$c.Tag]
        }
        elseif ($c -is [System.Windows.Forms.TextBox]) { $c.Text = [string]$v }
    }
    foreach ($b in $script:ColorButtons) { Update-ColorButton $b }
    $idx = $cbFont.Items.IndexOf([string]$script:S.fontFamily)
    if ($idx -lt 0) { $idx = $cbFont.Items.IndexOf('Segoe UI') }
    $cbFont.SelectedIndex = $idx
    $ckAuto.Checked = Test-Path -LiteralPath $StartupLink
    Update-UrlBox
    $script:Loading = $false
}

$script:SaveTimer = New-Object System.Windows.Forms.Timer
$SaveTimer.Interval = 350
$SaveTimer.Add_Tick({
    $script:SaveTimer.Stop()
    try { Save-Settings $script:S } catch {}
    Update-UrlBox
})

function Get-LiveData {
    try {
        $req = [Net.HttpWebRequest]::Create("http://localhost:$($script:S.port)/data")
        $req.Timeout = 600
        $req.Proxy = $null
        $resp = $req.GetResponse()
        try { $txt = (New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd() } finally { $resp.Close() }
        return ($txt | ConvertFrom-Json)
    } catch { return $null }
}

$script:StartedHelper = $false
$liveTimer = New-Object System.Windows.Forms.Timer
$liveTimer.Interval = 1500
$liveTimer.Add_Tick({
    $script:Live = Get-LiveData
    if ($script:Live -ne $null -and $script:Live.connector) { $lbConn.Text = 'Browser connector: working' }
    elseif ($script:Live -ne $null) { $lbConn.Text = 'Browser connector: not set up yet (needed for Spotify web)' }
    if ($script:Live -ne $null) {
        $t = @($script:Live.tracks)
        if ($t.Count -eq 0) { $lbStatus.Text = 'Helper is running. Nothing is playing right now.' }
        else { $lbStatus.Text = 'Helper is running. Playing: ' + (($t | ForEach-Object { '{0}: {1}' -f $_.source, $_.name }) -join '  |  ') }
    } else {
        if (-not $script:StartedHelper -and -not (Get-HelperProcess)) {
            $script:StartedHelper = $true
            Start-Helper $PSScriptRoot
            $lbStatus.Text = 'Starting the helper...'
        } else {
            $lbStatus.Text = 'Helper is not answering. Click Restart helper. If it keeps failing, try another port.'
        }
    }
    $script:Preview.Invalidate()
})

$Form.Add_Shown({ $anim.Start(); $liveTimer.Start() })
$Form.Add_FormClosing({
    if ($script:SaveTimer.Enabled) { $script:SaveTimer.Stop(); try { Save-Settings $script:S } catch {} }
    $anim.Stop(); $liveTimer.Stop()
})

Load-Controls
if (-not (Test-Path -LiteralPath $SettingsPath)) { Save-Settings $script:S }
[void]$Form.ShowDialog()
