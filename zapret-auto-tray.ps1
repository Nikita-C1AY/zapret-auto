# zapret-auto-tray.ps1 - tray launcher for Zapret Auto (v9.5.2)
# Starts zapret-auto.ps1 and shows a toggle icon near the clock.
# Knob RIGHT = on: green = working, yellow = testing / switching / not responding
# Knob LEFT = off: red = no strategy works, grey = no internet or stopped
# Right click: show/hide window, open log, stop. Double click: show/hide window.
# Settings: data\settings.txt (ShowConsole, NotifySwitch, Language, MemLimitMB, Interval).

$ShowConsole = $false; $NotifySwitch = $false; $Language = "auto"; $MemLimitMB = 200; $Interval = 60

$Me        = $PSCommandPath
$Dir       = $PSScriptRoot
$DataDir   = Join-Path $Dir "data"
$Core      = Join-Path $Dir "zapret-auto.ps1"
$Log       = Join-Path $DataDir "zapret-auto.log"
$Stats     = Join-Path $DataDir "zapret-auto-stats.json"
$OldStats  = Join-Path $Dir "zapret-auto-stats.json"
$StateFile = Join-Path $DataDir "zapret-auto.state"
$BeatFile  = Join-Path $DataDir "zapret-auto.beat"
$WinFile   = Join-Path $DataDir "zapret-auto.window"
$HwndFile  = Join-Path $DataDir "zapret-auto.hwnd"
$SetFile   = Join-Path $DataDir "settings.txt"
$Sys32     = Join-Path $env:SystemRoot "System32"
$PsExe     = Join-Path $Sys32 "WindowsPowerShell\v1.0\powershell.exe"
$Conhost   = Join-Path $Sys32 "conhost.exe"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Start-Process $PsExe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Me`""
  exit
}

$TrayMutex = New-Object System.Threading.Mutex($false, "Global\ZapretAutoTray")
try { $got = $TrayMutex.WaitOne(0) } catch { $got = $true }
if (-not $got) { exit }

# --- the few settings the tray needs (same file as the main script) ---
if (Test-Path $SetFile) {
  foreach ($raw in (Get-Content $SetFile -Encoding UTF8 -TotalCount 500)) {
    if ($raw.Trim() -notmatch '^\$?(\w+)\s*=\s*(.*)$') { continue }
    $k = $matches[1]; $v = ($matches[2] -replace '(^|\s)#.*$', '').Trim().Trim('"').Trim("'")
    if ($k -eq "ShowConsole" -or $k -eq "NotifySwitch") {
      $b = $null
      if ($v -match '^(\$?true|1|yes|да)$') { $b = $true } elseif ($v -match '^(\$?false|0|no|нет)$') { $b = $false }
      if ($null -ne $b) { Set-Variable -Name $k -Value $b }
    }
    elseif ($k -eq "MemLimitMB" -or $k -eq "Interval") { $n = 0; if ([int]::TryParse($v, [ref]$n) -and $n -ge 10) { Set-Variable -Name $k -Value $n } }
    elseif ($k -eq "Language" -and $v -match '^(auto|[a-z]{2})$') { $Language = $v }
  }
}
$StaleSec = [math]::Max(300, $Interval * 3)

# --- language ---
$LangTexts = @{}
$LangCode = $Language
if ($LangCode -eq "auto") { try { $LangCode = (Get-UICulture).TwoLetterISOLanguageName } catch { $LangCode = "en" } }
if ($LangCode -notmatch '^[a-z]{2}$') { $LangCode = "en" }
$LangFile = Join-Path $Dir "zapret-auto-lang-$LangCode.txt"
if ($LangCode -ne "en" -and (Test-Path $LangFile)) {
  foreach ($ln in [IO.File]::ReadAllLines($LangFile, [Text.Encoding]::UTF8)) {
    if ($ln -match '^\s*([\w.]+)\s*=\s*(.+)$') { $LangTexts[$matches[1]] = $matches[2].TrimEnd() }
  }
}
function T($k, $en) {
  $s = $en
  if ($script:LangTexts.ContainsKey($k)) { $s = $script:LangTexts[$k] }
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
[DllImport("user32.dll")] public static extern bool IsWindow(System.IntPtr h);
'@
function Hide-Win($h) { if ($h -and $h -ne [IntPtr]::Zero) { [void][ZA.Win]::ShowWindow($h, 0) } }
function Show-Win($h) { if ($h -and $h -ne [IntPtr]::Zero) { [void][ZA.Win]::ShowWindow($h, 5) } }

# ---------- toggle icon: knob right = on, lightning in the knob ----------
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

# first run (no rating yet): the window stays until the main script says "hide" (after a countdown).
$firstRun = -not (Test-Path $Stats) -and -not (Test-Path $OldStats)
foreach ($f in @($StateFile, $WinFile, $HwndFile, $BeatFile)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }

$Proc = Start-Process $Conhost -ArgumentList "`"$PsExe`" -NoProfile -ExecutionPolicy Bypass -File `"$Core`"" -PassThru
$script:h = [IntPtr]::Zero
$script:hidden = $false
$script:manual = $false
$script:pendingHide = $false
$script:current = ""
$script:since = $null
$script:state = ""
$script:last = ""
$script:lastWin = ""
$script:stale = $false
$script:ticks = 0

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
  if ($script:h -eq [IntPtr]::Zero) { return }
  if ($script:hidden) { Show-Win $script:h; $script:hidden = $false; $script:manual = $true }
  else { Hide-Win $script:h; $script:hidden = $true }
}
function Hide-Auto {
  if ($ShowConsole -or $script:hidden -or $script:manual) { return }
  if ($script:h -eq [IntPtr]::Zero) { $script:pendingHide = $true; return }
  Hide-Win $script:h; $script:hidden = $true; $script:pendingHide = $false
}
function Quit-Tray {
  $timer.Stop(); $icon.Visible = $false; $icon.Dispose()
  [System.Windows.Forms.Application]::Exit()
}
function Get-CoreProcs {
  return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*zapret-auto.ps1*" })
}
function Stop-All {
  foreach ($p in (Get-CoreProcs)) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force
  Quit-Tray
}
# memory guard: restart the main script and the tray (winws keeps running, internet does not drop)
function Restart-All($mb) {
  $line = "$(Get-Date -f 'dd.MM HH:mm:ss') " + (T "tray.memrestart" "memory {0} MB is over the limit {1} MB - restarting Zapret Auto" $mb $MemLimitMB)
  Add-Content -Path $Log -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
  $timer.Stop()
  foreach ($p in (Get-CoreProcs)) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep 2
  $icon.Visible = $false; $icon.Dispose()
  try { $TrayMutex.ReleaseMutex() } catch {}
  Start-Process $PsExe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Me`""
  [Environment]::Exit(0)
}
function Check-Memory {
  $limit = [int64]$MemLimitMB * 1MB
  $mine = [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64
  if ($mine -gt $limit) { Restart-All ([math]::Round($mine / 1MB)) }
  foreach ($p in (Get-CoreProcs)) { if ([int64]$p.WorkingSetSize -gt $limit) { Restart-All ([math]::Round([int64]$p.WorkingSetSize / 1MB)) } }
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
    if (-not $firstRun) { Hide-Auto }
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
  $script:ticks++
  # the main script writes its own console window handle - no guessing
  if ($script:h -eq [IntPtr]::Zero -and (Test-Path $HwndFile)) {
    $n = [int64]0
    if ([int64]::TryParse(([IO.File]::ReadAllText($HwndFile)).Trim(), [ref]$n) -and $n -ne 0 -and [ZA.Win]::IsWindow([IntPtr]$n)) {
      $script:h = [IntPtr]$n
      if ($ShowConsole) { Show-Win $script:h } elseif ($script:pendingHide) { Hide-Auto }
    }
  }
  foreach ($w in @(Get-Process winws -ErrorAction SilentlyContinue)) { Hide-Win $w.MainWindowHandle }

  if (Test-Path $StateFile) {
    try { $s = ([IO.File]::ReadAllText($StateFile)).Trim() } catch { $s = $script:last }
    if ($s -and $s -ne $script:last) { $script:last = $s; if (-not $script:stale) { Handle-State $s } }
  }
  if (Test-Path $WinFile) {
    try { $wv = ([IO.File]::ReadAllText($WinFile)).Trim() } catch { $wv = $script:lastWin }
    if ($wv -ne $script:lastWin) {
      $script:lastWin = $wv
      if ($wv -eq "hide") { Hide-Auto } elseif ($wv -eq "keep") { $script:manual = $true }
    }
  }

  # heartbeat: the main script must say "alive" regularly, otherwise the icon turns yellow
  if (Test-Path $BeatFile) {
    $age = ((Get-Date) - (Get-Item $BeatFile).LastWriteTime).TotalSeconds
    if ($age -gt $StaleSec) {
      if (-not $script:stale) { $script:stale = $true; Set-Icon "yellow" (T "tray.stale" "not responding - press Esc in its window") }
    } elseif ($script:stale) { $script:stale = $false; $script:state = ""; Handle-State $script:last }
  }

  if ($script:state -eq "green" -and $script:since -and -not $script:stale) {
    $m = [math]::Floor(((Get-Date) - $script:since).TotalMinutes)
    Set-Icon "green" (T "tray.work" "{0}, {1} min" $script:current $m)
  }

  if ($script:ticks % 150 -eq 0) { Check-Memory }

  if ($Proc.HasExited) {
    Set-Icon "grey" (T "tray.stopped" "stopped")
    $icon.ShowBalloonTip(6000, "Zapret Auto", (T "tray.bal.stopped" "Zapret Auto has stopped. Run the START bat again."), [System.Windows.Forms.ToolTipIcon]::Warning)
    Start-Sleep 6
    Quit-Tray
  }
})
$timer.Start()

[System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
