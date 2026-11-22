# zapret-auto.ps1 - self-learning auto switching of zapret strategies
# Version 9.5.2. Windows 10 (1803+) / 11. License: MIT, "AS IS", use at your own risk.
# Files: zapret-auto.ps1 (setup), zapret-auto-engine.ps1 (checks + main loop),
#   zapret-auto-tray.ps1 (tray icon), zapret-auto-lang-ru.txt (Russian texts), START bat.
# YOUR SETTINGS: data\settings.txt (created on the first run, kept on updates).
#   The values below are only defaults - do not edit them here.
# WORKING FILES: data\ (log, rating, state, your sites and domains).
# SECURITY: zapret folder is locked (only Administrators can change files), autostart only
#   from the root of a drive. Undo the lock: icacls "C:\path\to\zapret" /reset /T /C /Q
# NOTE for editors: PowerShell variable names ignore case ($Lang and $lang are the same).

$Version = "9.5.2"

# ===================== DEFAULTS (change them in data\settings.txt) =====================
$Language        = "auto"
$Prefer          = ""
$Interval        = 60
$HeavyEvery      = 5
$VideoEvery      = 3
$Fails           = 2
$Timeout         = 6
$DiscordTimeout  = 12
$FirstCheck      = 5
$CheckStep       = 5
$MaxWarmUp       = 20
$YouTubeMin      = 131072
$CutMin          = 8192
$ScoreCap        = 1440
$LogMaxKB        = 1024
$ProtectFolder   = $true
$RelearnOnChange = $true
$QuarantineMin   = 30
$FailPenalty     = 0.5
$HideCountdown   = 15
$ShowConsole     = $false
$NotifySwitch    = $false
$MemLimitMB      = 200
# =======================================================================================
$SettingNames = @("Language","Prefer","Interval","HeavyEvery","VideoEvery","Fails","Timeout","DiscordTimeout",
  "FirstCheck","CheckStep","MaxWarmUp","YouTubeMin","CutMin","ScoreCap","LogMaxKB","ProtectFolder",
  "RelearnOnChange","QuarantineMin","FailPenalty","HideCountdown","ShowConsole","NotifySwitch","MemLimitMB")
$SettingMin = @{ Interval = 10; HeavyEvery = 1; VideoEvery = 1; Fails = 1; Timeout = 2; DiscordTimeout = 2;
  FirstCheck = 1; CheckStep = 1; MaxWarmUp = 5; ScoreCap = 60; LogMaxKB = 64; MemLimitMB = 50 }

$ScriptDir = $PSScriptRoot
$DataDir   = Join-Path $ScriptDir "data"
$SettingsFile = Join-Path $DataDir "settings.txt"
$TaskName  = "ZapretAuto"
$Sys32     = Join-Path $env:SystemRoot "System32"
$Curl      = Join-Path $Sys32 "curl.exe"
$Icacls    = Join-Path $Sys32 "icacls.exe"
$PsExe     = Join-Path $Sys32 "WindowsPowerShell\v1.0\powershell.exe"
$Engine    = Join-Path $ScriptDir "zapret-auto-engine.ps1"
$TrayFile  = Join-Path $ScriptDir "zapret-auto-tray.ps1"

# --- settings: only known names, every value checked; anything else is ignored ---
function Read-Settings {
  $bad = @()
  if (-not (Test-Path $SettingsFile)) { return $bad }
  foreach ($raw in (Get-Content $SettingsFile -Encoding UTF8 -TotalCount 500)) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    if ($line -notmatch '^\$?(\w+)\s*=\s*(.*)$') { $bad += $line; continue }
    $k = $matches[1]; $v = ($matches[2] -replace '(^|\s)#.*$', '').Trim().Trim('"').Trim("'")
    $name = $SettingNames | Where-Object { $_ -eq $k } | Select-Object -First 1
    if (-not $name) { $bad += $line; continue }
    $cur = Get-Variable -Name $name -Scope Script -ValueOnly
    if ($cur -is [bool]) {
      if ($v -match '^(\$?true|1|yes|да)$') { Set-Variable -Name $name -Scope Script -Value $true }
      elseif ($v -match '^(\$?false|0|no|нет)$') { Set-Variable -Name $name -Scope Script -Value $false }
      else { $bad += $line }
    } elseif ($cur -is [int]) {
      $n = 0; $min = 0; if ($SettingMin.ContainsKey($name)) { $min = $SettingMin[$name] }
      if ([int]::TryParse($v, [ref]$n) -and $n -ge $min -and $n -le 100000000) { Set-Variable -Name $name -Scope Script -Value $n } else { $bad += $line }
    } elseif ($cur -is [double]) {
      $d = 0.0
      if ([double]::TryParse(($v -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -and $d -ge 0 -and $d -le 1) { Set-Variable -Name $name -Scope Script -Value $d } else { $bad += $line }
    } else {
      if ($v.Length -le 100 -and $v -notmatch '[\\/:*?<>|"%`$;]') { Set-Variable -Name $name -Scope Script -Value $v } else { $bad += $line }
    }
  }
  return $bad
}
function New-SettingsFile {
  $txt = @"
# Zapret Auto - YOUR SETTINGS / ВАШИ НАСТРОЙКИ
# Format: Name = value. Lines with # are comments. Delete a line = default value.
# This file is kept when you update Zapret Auto. Edit it as Administrator.
# Формат: Имя = значение. Строки с # - комментарии. Удалили строку - будет значение по умолчанию.
# Файл сохраняется при обновлении. Редактируйте от имени администратора.

Language        = auto     # auto / ru / en
Prefer          =          # favourite strategy / любимая стратегия, e.g. general (EXP).bat
Interval        = 60       # seconds between checks / секунд между проверками
Fails           = 2        # failed checks in a row before switching / провалов подряд до переключения
QuarantineMin   = 30       # minutes a failed strategy is skipped / минут карантина упавшей стратегии
FailPenalty     = 0.5      # score multiplier on failure / множитель балла при сбое (0.5 = пополам)
ShowConsole     = false    # true = window always visible / окно всегда видно
NotifySwitch    = false    # true = notification on every switch / уведомление при каждом переключении
HideCountdown   = 15       # seconds before the window hides after the first test / секунд до скрытия окна
MemLimitMB      = 200      # restart if a process uses more RAM / перезапуск, если процесс занял больше
ProtectFolder   = true     # lock the zapret folder (recommended) / защита папки (рекомендуется)
RelearnOnChange = true     # zapret files changed -> new full test / изменились файлы запрета - новый подбор

# Advanced / для продвинутых
HeavyEvery      = 5
VideoEvery      = 3
Timeout         = 6
DiscordTimeout  = 12
FirstCheck      = 5
CheckStep       = 5
MaxWarmUp       = 20
YouTubeMin      = 131072
CutMin          = 8192
ScoreCap        = 1440
LogMaxKB        = 1024
"@
  [IO.File]::WriteAllText($SettingsFile, $txt, (New-Object Text.UTF8Encoding($true)))
}
$BadSettings = @(Read-Settings)

# --- language: texts from zapret-auto-lang-XX.txt, English if missing ---
$LangTexts = @{}
$LangCode = $Language
if ($LangCode -eq "auto") { try { $LangCode = (Get-UICulture).TwoLetterISOLanguageName } catch { $LangCode = "en" } }
if ($LangCode -notmatch '^[a-z]{2}$') { $LangCode = "en" }
$LangFile = Join-Path $ScriptDir "zapret-auto-lang-$LangCode.txt"
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

$Host.UI.RawUI.WindowTitle = "Zapret Auto v$Version"
$Host.UI.RawUI.BackgroundColor = "Black"
Clear-Host

function Stop-WithError($msg) {
  Write-Host ""; Write-Host "$(T 'error' 'ERROR'): $msg" -ForegroundColor Red; Write-Host ""
  Read-Host (T "enter" "Press Enter to close"); exit 1
}

if ($PSVersionTable.PSVersion.Major -lt 5) { Stop-WithError (T "err.ps" "Windows is too old. Windows 10 (1803+) or 11 is required.") }
if (-not (Test-Path $Curl)) { Stop-WithError (T "err.curl" "curl.exe not found in {0}. Update Windows." $Sys32) }
if (-not (Test-Path $Engine)) { Stop-WithError (T "err.engine" "zapret-auto-engine.ps1 not found next to this script.") }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Stop-WithError (T "err.admin" "Run as Administrator (double-click the START bat).") }

$Mutex = New-Object System.Threading.Mutex($false, "Global\ZapretAutoSingleInstance")
try { $got = $Mutex.WaitOne(0) } catch { $got = $true }
if (-not $got) {
  Write-Host (T "already" "Zapret Auto is already running. Nothing to do.") -ForegroundColor Yellow
  Start-Sleep 5; exit 0
}

# --- data folder and working files ---
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
$LogFile    = Join-Path $DataDir "zapret-auto.log"
$OldLog     = Join-Path $DataDir "zapret-auto.old.log"
$StatsFile  = Join-Path $DataDir "zapret-auto-stats.json"
$MyTargets  = Join-Path $DataDir "zapret-auto-targets.txt"
$MyDomains  = Join-Path $DataDir "zapret-auto-domains.txt"
$PackIpFile = Join-Path $DataDir "packs-ipset.txt"
$StateFile  = Join-Path $DataDir "zapret-auto.state"
$BeatFile   = Join-Path $DataDir "zapret-auto.beat"
$WinFile    = Join-Path $DataDir "zapret-auto.window"
$HwndFile   = Join-Path $DataDir "zapret-auto.hwnd"
$PacksDir   = Join-Path $ScriptDir "packs"

function State($s) { try { [IO.File]::WriteAllText($StateFile, $s) } catch {} }
function Beat { try { [IO.File]::WriteAllText($BeatFile, (Get-Date).ToString("o")) } catch {} }
function Win($s) { try { [IO.File]::WriteAllText($WinFile, $s) } catch {} }
function Rotate-Log { if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxKB * 1024)) { Move-Item $LogFile $OldLog -Force } }
function Log($msg, $color = "Gray") {
  $line = "$(Get-Date -f 'dd.MM HH:mm:ss') $msg"
  Write-Host $line -ForegroundColor $color
  Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}
function Status($msg, $color) { Write-Host "$(Get-Date -f 'dd.MM HH:mm:ss') $msg" -ForegroundColor $color }

# move working files of 9.5.1 into data\ (once)
$moved = $false
foreach ($f in @("zapret-auto.log", "zapret-auto.old.log", "zapret-auto-stats.json", "zapret-auto-targets.txt", "zapret-auto-domains.txt", "packs-ipset.txt")) {
  $src = Join-Path $ScriptDir $f; $dst = Join-Path $DataDir $f
  if (Test-Path $src) { if (Test-Path $dst) { Remove-Item $src -Force } else { Move-Item $src $dst }; $moved = $true }
}
foreach ($f in @("zapret-auto.state", "packs\instagram-moved.flag")) { Remove-Item (Join-Path $ScriptDir $f) -Force -ErrorAction SilentlyContinue }
$newSettings = -not (Test-Path $SettingsFile)
if ($newSettings) { New-SettingsFile }

# console: tell the tray which window is ours, and switch off QuickEdit
# (a mouse click in the window used to PAUSE the whole script until Esc)
try {
  Add-Type -Namespace ZA -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);
'@
  [IO.File]::WriteAllText($HwndFile, "$([int64][ZA.Con]::GetConsoleWindow())")
  $hIn = [ZA.Con]::GetStdHandle(-10); $mode = [uint32]0
  if ([ZA.Con]::GetConsoleMode($hIn, [ref]$mode)) {
    $newMode = ([int64]$mode -band [int64]4294967231) -bor 0x80
    [void][ZA.Con]::SetConsoleMode($hIn, [uint32]$newMode)
  }
} catch {}

Rotate-Log
Log "Zapret Auto v$Version ($LangCode)" "White"
if ($moved) { Log (T "moved.data" "Working files moved to the data folder") "DarkGray" }
if ($newSettings) { Log (T "set.created" "Settings file created: {0}" $SettingsFile) "DarkGray" }
foreach ($b in $BadSettings) { Log (T "set.bad" "Invalid line in settings.txt skipped: {0}" $b) "Yellow" }

if (Get-ChildItem -Path $ScriptDir -Filter "general*.bat" -ErrorAction SilentlyContinue) { $ZapretDir = $ScriptDir }
else {
  $ZapretDir = Split-Path $ScriptDir -Parent
  if (-not (Get-ChildItem -Path $ZapretDir -Filter "general*.bat" -ErrorAction SilentlyContinue)) {
    Stop-WithError (T "err.nozapret" "zapret not found. Put the folder zapret-auto INTO the zapret folder (next to service.bat).")
  }
}
$ZapTargets = Join-Path $ZapretDir "utils\targets.txt"
$UserList   = Join-Path $ZapretDir "lists\list-general-user.txt"

# --- versions, ipset, VPN for feedback ---
$ZapretVer = "unknown"
$svc = Join-Path $ZapretDir "service.bat"
if (Test-Path $svc) {
  foreach ($svcLine in (Get-Content $svc -TotalCount 60 -ErrorAction SilentlyContinue)) { if ($svcLine -match '(\d+\.\d+\.\d+)') { $ZapretVer = $matches[1]; break } }
}
$WinVer = "unknown"
try { $os = Get-CimInstance Win32_OperatingSystem; $WinVer = "$($os.Caption) build $($os.BuildNumber)" } catch {}
$IpsetMode = "unknown"
$ipsetAll = Join-Path $ZapretDir "lists\ipset-all.txt"
if (Test-Path $ipsetAll) { if ((Get-Item $ipsetAll).Length -lt 100) { $IpsetMode = "off" } else { $IpsetMode = "loaded" } }

$vpn = @()
if (Get-Process warp-svc -ErrorAction SilentlyContinue) { $vpn += "Cloudflare WARP" }
try {
  $ad = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -match 'WireGuard|Wintun|TAP-Windows|Cloudflare WARP|OpenVPN|TUN' })
  foreach ($a in $ad) { $vpn += $a.InterfaceDescription }
} catch {}
$vpn = @($vpn | Select-Object -Unique)
$VpnText = T "none" "none"; if ($vpn.Count -gt 0) { $VpnText = $vpn -join ", " }
Log (T "versions" "zapret: {0} | ipset: {1} | VPN: {2} | Windows: {3}" $ZapretVer $IpsetMode $VpnText $WinVer) "DarkGray"
if ($vpn.Count -gt 0) { Log (T "vpn.warn" "WARNING: a VPN is active ({0}). It conflicts with zapret checks - results may be wrong. Turn it off for the test." $VpnText) "Yellow" }

$hash = (Get-FileHash -Path $PSCommandPath -Algorithm SHA256).Hash
Write-Host (T "sha" "SHA-256 of this script: {0} (verify it yourself BEFORE the first run)" $hash) -ForegroundColor DarkGray

if (Get-Service -Name "zapret" -ErrorAction SilentlyContinue) {
  Stop-WithError (T "err.service" "zapret service is installed. Open service.bat -> Remove Services, then run this again.")
}

# --- location check ---
$parent      = Split-Path $ZapretDir -Parent
$driveRoot   = [IO.Path]::GetPathRoot($ZapretDir)
$userProfile = [Environment]::GetFolderPath("UserProfile")
$SafePlace   = (($parent.TrimEnd('\') + '\') -eq $driveRoot) -and -not $ZapretDir.StartsWith($userProfile, [StringComparison]::OrdinalIgnoreCase)
$suggest     = Join-Path $driveRoot (Split-Path $ZapretDir -Leaf)
if ($driveRoot -match '^\\\\') { $SafePlace = $false; $suggest = "C:\zapret" }
if (-not $SafePlace) {
  Write-Host ""
  Write-Host ("  " + (T "loc1" "WARNING: zapret is in an unsafe place: {0}" $ZapretDir)) -ForegroundColor Yellow
  Write-Host ("  " + (T "loc2" "Move the whole zapret folder to the ROOT of a drive, e.g. {0}" $suggest)) -ForegroundColor Yellow
  Write-Host ("  " + (T "loc3" "Zapret Auto works now, but AUTOSTART IS OFF until you move it.")) -ForegroundColor Yellow
  Write-Host ""
  Log (T "loc.log" "Unsafe location: {0} - autostart disabled" $ZapretDir) "Yellow"
}

Get-ChildItem -Path $ZapretDir -Recurse | Unblock-File -ErrorAction SilentlyContinue

if ($ProtectFolder) {
  & $Icacls "$ZapretDir" /setowner "*S-1-5-32-544" /T /C /Q | Out-Null; $c0 = $LASTEXITCODE
  & $Icacls "$ZapretDir" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" /C /Q | Out-Null; $c1 = $LASTEXITCODE
  & $Icacls "$ZapretDir\*" /reset /T /C /Q | Out-Null; $c2 = $LASTEXITCODE
  if ($c0 -eq 0 -and $c1 -eq 0 -and $c2 -eq 0) { Log (T "lock.ok" "Folder locked: only Administrators can change files") "DarkGray" }
  else { Log (T "lock.fail" "Folder lock failed ({0}) - restoring normal rights" "$c0/$c1/$c2") "Yellow"; & $Icacls "$ZapretDir" /reset /T /C /Q | Out-Null }
}

$all = @(Get-ChildItem -Path $ZapretDir -Filter "general*.bat" | Sort-Object Name | Select-Object -ExpandProperty Name)
if ($Prefer) {
  if ($all -contains $Prefer) { Log (T "fav" "Favourite strategy: {0}" $Prefer) "DarkCyan" }
  else { Log (T "fav.missing" "Favourite strategy '{0}' not found - ignored" $Prefer) "Yellow"; $Prefer = "" }
}

# --- your own files ---
if (-not (Test-Path $MyTargets)) {
@'
# YOUR sites to CHECK:  KeyName = "https://host..."   (# = comment)
SpotifyWeb    = "https://open.spotify.com"
SpotifyApi    = "https://api.spotify.com"
DiscordMedia  = "https://media.discordapp.net"
'@ | Set-Content -Path $MyTargets
}
if (-not (Test-Path $MyDomains)) {
@'
# YOUR domains to UNBLOCK, one per line (subdomains included). Added to zapret's
# list-general-user.txt on every start, nothing is ever removed. # = comment
spotify.com
scdn.co
spotifycdn.com
discordapp.com
discordapp.net
'@ | Set-Content -Path $MyDomains
}

# --- packs: folders set the priority ---
$newPacks = -not (Test-Path $PacksDir)
if ($newPacks) { New-Item -ItemType Directory -Path $PacksDir | Out-Null }
foreach ($d in @("critical", "normal", "off", "disabled")) { $p = Join-Path $PacksDir $d; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

$tpl = Join-Path $PacksDir "_template.txt"
if (-not (Test-Path $tpl)) {
@'
# PACK TEMPLATE - copy it into one of the folders and rename it (mysite.txt).
# The FOLDER decides what happens:
#   critical - checked all the time like YouTube and Discord, failure = switch (max 3)
#   normal   - checked in the full test, affects the rating
#   off      - only adds domains, no checks
#   disabled - not used
# Domains are never removed from zapret's list automatically.
# The folder is locked: copy / edit files as Administrator.

name = My site

[domains]
example.com

[check]
ExampleWeb = "https://www.example.com"

[ips]
# optional: public IPv4 or subnet, not wider than /16. Local networks are refused.
'@ | Set-Content -Path $tpl
}

if ($newPacks) {
  "name = Instagram`r`n`r`n[domains]`r`ninstagram.com`r`ncdninstagram.com`r`nfbcdn.net`r`n`r`n[check]`r`nInstagramWeb    = `"https://www.instagram.com`"`r`nInstagramStatic = `"https://static.cdninstagram.com`"`r`n`r`n[ips]" | Set-Content -Path (Join-Path $PacksDir "disabled\instagram.txt")
  "name = GitHub`r`n`r`n[domains]`r`ngithub.com`r`ngithubusercontent.com`r`ngithubassets.com`r`ngithub.io`r`n`r`n[check]`r`nGitHubWeb = `"https://github.com`"`r`n`r`n[ips]" | Set-Content -Path (Join-Path $PacksDir "disabled\github.txt")
  "name = Steam`r`n`r`n[domains]`r`nsteampowered.com`r`nsteamcommunity.com`r`nsteamstatic.com`r`n`r`n[check]`r`nSteamStore = `"https://store.steampowered.com`"`r`n`r`n[ips]" | Set-Content -Path (Join-Path $PacksDir "disabled\steam.txt")
}

$domainRx = '^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'
$urlRx    = '^(\w+)\s*=\s*"(https?://[A-Za-z0-9.\-]+(:\d+)?(/[^"\s]*)?)"$'

function Test-SafeIp($s) {
  if ($s -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:/(\d{1,2}))?$') { return $false }
  $o = @([int]$matches[1], [int]$matches[2], [int]$matches[3], [int]$matches[4])
  $pfx = 32; if ($matches[5]) { $pfx = [int]$matches[5] }
  foreach ($x in $o) { if ($x -gt 255) { return $false } }
  if ($pfx -lt 16 -or $pfx -gt 32) { return $false }
  $a = $o[0]; $b = $o[1]
  if ($a -eq 0 -or $a -eq 10 -or $a -eq 127 -or $a -ge 224) { return $false }
  if ($a -eq 169 -and $b -eq 254) { return $false }
  if ($a -eq 172 -and $b -ge 16 -and $b -le 31) { return $false }
  if ($a -eq 192 -and $b -eq 168) { return $false }
  if ($a -eq 100 -and $b -ge 64 -and $b -le 127) { return $false }
  if ($a -eq 198 -and ($b -eq 18 -or $b -eq 19)) { return $false }
  return $true
}

$Packs = @(); $seen = @{}
foreach ($prio in @("critical", "normal", "off")) {
  foreach ($f in @(Get-ChildItem -Path (Join-Path $PacksDir $prio) -Filter "*.txt" -File | Where-Object { -not $_.Name.StartsWith("_") } | Sort-Object Name | Select-Object -First 50)) {
    $key = $f.BaseName.ToLower()
    if ($seen.ContainsKey($key)) { Log (T "pack.twice" "Pack {0} is in two folders ({1} and {2}) - using {1}" $f.Name $seen[$key] $prio) "Yellow"; continue }
    $seen[$key] = $prio
    $p = @{ Name = $f.BaseName; Priority = $prio; Domains = @(); Checks = @(); Ips = @(); Skipped = 0 }
    $sec = ""
    foreach ($raw in (Get-Content $f.FullName -TotalCount 2000)) {
      $pl = $raw.Trim()
      if (-not $pl -or $pl.StartsWith("#")) { continue }
      if ($pl -match '^\[(\w+)\]$') { $sec = $matches[1].ToLower(); continue }
      if ($sec -eq "") {
        if ($pl -match '^name\s*=\s*([\w .\-]{1,40})$') { $p.Name = $matches[1].Trim() }
        elseif ($pl -notmatch '^(enabled|priority)\s*=') { $p.Skipped++ }
        continue
      }
      if ($sec -eq "domains") { $d = $pl.ToLower(); if ($d -match $domainRx -and $p.Domains.Count -lt 300) { $p.Domains += $d } else { $p.Skipped++ } }
      elseif ($sec -eq "check") { if ($pl -match $urlRx -and $p.Checks.Count -lt 10) { $p.Checks += @{ Name = $matches[1]; Url = $matches[2] } } else { $p.Skipped++ } }
      elseif ($sec -eq "ips") { if ((Test-SafeIp $pl) -and $p.Ips.Count -lt 300) { $p.Ips += $pl } else { $p.Skipped++ } }
      else { $p.Skipped++ }
    }
    Log (T "pack.on" "Pack ON: {0} [{1}] - {2} domains, {3} checks, {4} IPs" $p.Name $prio $p.Domains.Count $p.Checks.Count $p.Ips.Count) "DarkCyan"
    if ($p.Skipped -gt 0) { Log ("   " + (T "pack.skipped" "invalid or refused lines skipped: {0} in {1}" $p.Skipped $f.Name)) "Yellow" }
    $Packs += $p
  }
}
$Critical = @(); foreach ($p in $Packs) { if ($p.Priority -eq "critical") { $Critical += $p.Checks } }
$critPacks = @($Packs | Where-Object { $_.Priority -eq "critical" }).Count
if ($critPacks -gt 3) { Log (T "crit.many" "Warning: {0} critical packs. More than 3 = slower checks and extra switching." $critPacks) "Yellow" }

# --- sync domains ---
$wanted = @(Get-Content $MyDomains | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -and -not $_.StartsWith("#") })
$badLines = @($wanted | Where-Object { $_ -notmatch $domainRx })
if ($badLines.Count -gt 0) { Log (T "dom.bad" "Skipped invalid lines in domains file: {0}" ($badLines -join ', ')) "Yellow" }
$wanted = @($wanted | Where-Object { $_ -match $domainRx })
foreach ($p in $Packs) { $wanted += $p.Domains }
$wanted = @($wanted | Select-Object -Unique)
$have = @(); if (Test-Path $UserList) { $have = @(Get-Content $UserList | ForEach-Object { $_.Trim().ToLower() }) }
$added = @($wanted | Where-Object { $have -notcontains $_ })
if ($added.Count -gt 0) {
  if (Test-Path $UserList) { $raw = [IO.File]::ReadAllText($UserList); if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { Add-Content -Path $UserList -Value "" } }
  Add-Content -Path $UserList -Value $added
  Log (T "dom.added" "Added to list-general-user.txt: {0}" ($added -join ', ')) "DarkGray"
}

$allIps = @(); foreach ($p in $Packs) { $allIps += $p.Ips }
$allIps = @($allIps | Select-Object -Unique)
if ($allIps.Count -gt 0) { $allIps | Set-Content -Path $PackIpFile; Log (T "ips.saved" "Pack IPs: {0} saved to packs-ipset.txt (not connected to zapret yet)" $allIps.Count) "DarkGray" }

function Read-TargetFile($path) {
  $list = @()
  if (Test-Path $path) { foreach ($line in Get-Content $path) { if ($line.Trim() -match $urlRx) { $list += @{ Name = $matches[1]; Url = $matches[2] } } } }
  return $list
}
$Targets = @(Read-TargetFile $ZapTargets) + @(Read-TargetFile $MyTargets)
foreach ($p in $Packs) { if ($p.Priority -ne "off") { $Targets += $p.Checks } }
if ($Targets.Count -eq 0) { $Targets = @(@{ Name = "YouTubeWeb"; Url = "https://www.youtube.com" }, @{ Name = "DiscordMain"; Url = "https://discord.com" }) }

Log (T "folder" "zapret folder: {0}" $ZapretDir) "DarkGray"
Log (T "counts" "Strategies: {0}, targets: {1}, critical checks: {2}" $all.Count $Targets.Count $Critical.Count) "DarkGray"

# fingerprint of zapret settings. The targets file keeps its 9.5.1 key, so moving it
# into data\ does not trigger a new full test.
function Get-ConfigPrint {
  $items = @()
  $files = @()
  $files += @(Get-ChildItem (Join-Path $ZapretDir "lists") -File -ErrorAction SilentlyContinue)
  $files += @(Get-ChildItem $ZapretDir -Filter "general*.bat" -File -ErrorAction SilentlyContinue)
  $files += @(Get-ChildItem (Join-Path $ZapretDir "utils") -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne ".log" })
  $files += @(Get-ChildItem $PacksDir -Filter "*.txt" -File -Recurse -ErrorAction SilentlyContinue)
  foreach ($f in $files) { $items += @{ K = $f.FullName.Substring($ZapretDir.Length); P = $f.FullName } }
  if (Test-Path $MyTargets) { $items += @{ K = (Join-Path $ScriptDir "zapret-auto-targets.txt").Substring($ZapretDir.Length); P = $MyTargets } }
  $sb = New-Object System.Text.StringBuilder
  foreach ($it in ($items | Sort-Object { $_.K })) {
    $h = (Get-FileHash $it.P -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
    [void]$sb.Append("$($it.K)=$h;")
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))) -replace '-', '')
}
$ConfigPrint = Get-ConfigPrint
$FirstRun = -not (Test-Path $StatsFile)

# --- autostart: the tray if it is there, otherwise this script with a window ---
if ($SafePlace) {
  if (Test-Path $TrayFile) { $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayFile`"" }
  else { $argLine = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`"" }
  $act = New-ScheduledTaskAction -Execute $PsExe -Argument $argLine
  $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
  Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
  Log (T "auto.ok" "Autostart task updated") "DarkGray"
} elseif (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Log (T "auto.removed" "Old autostart task removed (unsafe location)") "Yellow"
}

# --- checks, rating and the main loop ---
. $Engine
