# zapret-auto-tray.ps1 - tray launcher for Zapret Auto (v9.5)
# Starts zapret-auto.ps1 without windows and shows a toggle icon near the clock.
# Knob RIGHT = on:  green = working, yellow = testing / switching
# Knob LEFT  = off: red = no strategy works, grey = no internet or stopped
# Right click: show/hide window, open log, stop. Double click: show/hide window.
# Texts: zapret-auto-lang-XX.txt (same file as the main script), English if missing.

# ===================== SETTINGS =====================
$ShowConsole  = $false   # $true = the Zapret Auto window stays visible
$NotifySwitch = $false   # $true = notification on every strategy switch
                         # (a notification when NO strategy works is always shown)
$Language     = "auto"   # auto = by Windows language, or "ru" / "en"
# ====================================================

$Me    = $PSCommandPath
$Dir   = $PSScriptRoot
$Core  = Join-Path $Dir "zapret-auto.ps1"
$Log   = Join-Path $Dir "zapret-auto.log"
$Stats = Join-Path $Dir "zapret-auto-stats.json"
$StateFile = Join-Path $Dir "zapret-auto.state"
$Sys32 = Join-Path $env:SystemRoot "System32"
$PsExe = Join-Path $Sys32 "WindowsPowerShell\v1.0\powershell.exe"
$Conhost = Join-Path $Sys32 "conhost.exe"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Start-Process $PsExe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Me`""
  exit
}

$TrayMutex = New-Object System.Threading.Mutex($false, "Global\ZapretAutoTray")
if (-not $TrayMutex.WaitOne(0)) { exit }

# --- language ---
$L = @{}
$LangCode = $Language
if ($LangCode -eq "auto") { try { $LangCode = (Get-UICulture).TwoLetterISOLanguageName } catch { $LangCode = "en" } }
if ($LangCode -notmatch '^[a-z]{2}$') { $LangCode = "en" }
$LangFile = Join-Path $Dir "zapret-auto-lang-$LangCode.txt"
if ($LangCode -ne "en" -and (Test-Path $LangFile)) {
  foreach ($ln in [IO.File]::ReadAllLines($LangFile, [Text.Encoding]::UTF8)) {
    if ($ln -match '^\s*([\w.]+)\s*=\s*(.+)$') { $L[$matches[1]] = $matches[2].TrimEnd() }
  }
}
function T($k, $en) {
  $s = $en
  if ($L.ContainsKey($k)) { $s = $L[$k] }
  if ($args.Count -gt 0) { $s = $s -f $args }
  return $s
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not (Test-Path $Core)) {
  [System.Windows.Forms.MessageBox]::Show((T "tray.notfound" "zapret-auto.ps1 not found next to the tray file."), "Zapret Auto") | Out-Null
  exit 1
}
Add-Type -Namespace ZA -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);
'@
function Hide-Win($h) { if ($h -and $h -ne [IntPtr]::Zero) { [void][ZA.Win]::ShowWindow($h, 0) } }
function Show-Win($h) { if ($h -and $h -ne [IntPtr]::Zero) { [void][ZA.Win]::ShowWindow($h, 5) } }

# ---------- toggle icon: same shape always, knob right = on, lightning in the knob ----------
function New-ToggleIcon($r, $g, $b, $on) {
  $bmp = New-Object System.Drawing.Bitmap 32, 32
  $gr = [System.Drawing.Graphics]::FromImage($bmp)
  $gr.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $gr.Clear([System.Drawing.Color]::Transparent)
  $col  = [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
  $dark = [System.Drawing.Color]::FromArgb(255, [int]($r * 0.6), [int]($g * 0.6), [int]($b * 0.6))
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc(0, 6, 20, 20, 90, 180)
  $path.AddArc(12, 6, 20, 20, 270, 180)
  $path.CloseFigure()
  $gr.FillPath((New-Object System.Drawing.SolidBrush $col), $path)
  $gr.DrawPath((New-Object System.Drawing.Pen $dark, 1.5), $path)
  if ($on) { $kx = 14 } else { $kx = 2 }
  $gr.FillEllipse([System.Drawing.Brushes]::White, $kx, 8, 16, 16)
  $cx = $kx + 8
  $pts = @(
    (New-Object System.Drawing.PointF ($cx + 1.5), 9.5),
    (New-Object System.Drawing.PointF ($cx - 3.5), 16.5),
    (New-Object System.Drawing.PointF ($cx - 0.5), 16.5),
    (New-Object System.Drawing.PointF ($cx - 1.5), 22.5),
    (New-Object System.Drawing.PointF ($cx + 3.5), 15.0),
    (New-Object System.Drawing.PointF ($cx + 0.5), 15.0)
  )
  $gr.FillPolygon((New-Object System.Drawing.SolidBrush $col), [System.Drawing.PointF[]]$pts)
  $gr.Dispose()
  $hIcon = $bmp.GetHicon()
  $icon = [System.Drawing.Icon]::FromHandle($hIcon).Clone()
  [void][ZA.Win]::DestroyIcon($hIcon)
  $bmp.Dispose()
  return $icon
}
$Icons = @{
  green  = New-ToggleIcon 25 170 110 $true
  yellow = New-ToggleIcon 235 165 20 $true
  red    = New-ToggleIcon 220 60 60 $false
  grey   = New-ToggleIcon 130 130 140 $false
}

# first run (no rating yet): keep the window until a strategy works.
# later runs: hide as soon as the start checks are passed (errors stay visible).
$firstRun = -not (Test-Path $Stats)
Remove-Item $StateFile -Force -ErrorAction SilentlyContinue

$Proc = Start-Process $Conhost -ArgumentList "`"$PsExe`" -NoProfile -ExecutionPolicy Bypass -File `"$Core`"" -PassThru
$script:h = [IntPtr]::Zero
$script:hidden = $false
$script:manual = $false
$script:current = ""
$script:since = $null
$script:state = ""
$script:last = ""

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Visible = $true

function Set-Icon($st, $tip) {
  if ($st -ne $script:state) { $icon.Icon = $Icons[$st]; $script:state = $st }
  $tip = "Zapret Auto: $tip"
  if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
  $icon.Text = $tip
}
Set-Icon "yellow" (T "tray.starting" "starting...")

function Toggle-Window {
  if ($script:hidden) { Show-Win $script:h; $script:hidden = $false; $script:manual = $true }
  else { Hide-Win $script:h; $script:hidden = $true }
}
function Hide-Auto { if (-not $ShowConsole -and -not $script:hidden -and -not $script:manual) { Hide-Win $script:h; $script:hidden = $true } }
function Quit-Tray {
  $timer.Stop(); $icon.Visible = $false; $icon.Dispose()
  [System.Windows.Forms.Application]::Exit()
}
function Stop-All {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*zapret-auto.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force
  Quit-Tray
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $menu.Items.Add((T "tray.show" "Show / hide window"))
$miLog  = $menu.Items.Add((T "tray.log" "Open log"))
$miStop = $menu.Items.Add((T "tray.stop" "Stop Zapret Auto"))
$miShow.add_Click({ Toggle-Window })
$miLog.add_Click({ if (Test-Path $Log) { Start-Process notepad.exe "`"$Log`"" } })
$miStop.add_Click({ Stop-All })
$icon.ContextMenuStrip = $menu
$icon.add_DoubleClick({ Toggle-Window })

function Short($n) { return ($n -replace '^general\s*', '' -replace '\.bat$', '' -replace '[()]', '').Trim() }

# state codes written by the main script (never translated)
function Handle-State($s) {
  if ($s -match '^start') { if (-not $firstRun) { Hide-Auto } }
  elseif ($s -match '^testing') { Set-Icon "yellow" (T "tray.testing" "full test, about 10 min") }
  elseif ($s -match '^test (\d+/\d+)') { Set-Icon "yellow" (T "tray.test" "full test {0}" $matches[1]) }
  elseif ($s -match '^switching') { Set-Icon "yellow" (T "tray.switch" "switching strategy...") }
  elseif ($s -match '^working (.+)$') {
    $script:current = Short $matches[1]; $script:since = Get-Date
    Set-Icon "green" (T "tray.work" "{0}, {1} min" $script:current 0)
    Hide-Auto
    if ($NotifySwitch) { $icon.ShowBalloonTip(4000, "Zapret Auto", (T "tray.bal.switch" "Now using {0}" $script:current), [System.Windows.Forms.ToolTipIcon]::Info) }
  }
  elseif ($s -match '^nostrategy') {
    Set-Icon "red" (T "tray.nostrat" "no strategy works, retrying")
    $icon.ShowBalloonTip(8000, "Zapret Auto", (T "tray.bal.nostrat" "No strategy works right now. Zapret Auto keeps trying."), [System.Windows.Forms.ToolTipIcon]::Warning)
  }
  elseif ($s -match '^nointernet') { Set-Icon "grey" (T "tray.noinet" "no internet, waiting") }
  elseif ($s -match '^back') { Set-Icon "yellow" (T "tray.back" "internet is back, checking") }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.add_Tick({
  if ($script:h -eq [IntPtr]::Zero) { $Proc.Refresh(); $script:h = $Proc.MainWindowHandle }
  foreach ($w in @(Get-Process winws -ErrorAction SilentlyContinue)) { Hide-Win $w.MainWindowHandle }

  if (Test-Path $StateFile) {
    try { $s = ([IO.File]::ReadAllText($StateFile)).Trim() } catch { $s = $script:last }
    if ($s -and $s -ne $script:last) { $script:last = $s; Handle-State $s }
  }

  if ($script:state -eq "green" -and $script:since) {
    $m = [math]::Floor(((Get-Date) - $script:since).TotalMinutes)
    Set-Icon "green" (T "tray.work" "{0}, {1} min" $script:current $m)
  }

  if ($Proc.HasExited) {
    Set-Icon "grey" (T "tray.stopped" "stopped")
    $icon.ShowBalloonTip(6000, "Zapret Auto", (T "tray.bal.stopped" "Zapret Auto has stopped. Run START zapret-auto.bat again."), [System.Windows.Forms.ToolTipIcon]::Warning)
    Start-Sleep 6
    Quit-Tray
  }
})
$timer.Start()

[System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
