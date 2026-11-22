# zapret-auto-engine.ps1 - checks, rating and the main loop of Zapret Auto (v9.5.2)
# Do not run this file directly: zapret-auto.ps1 loads it at the end.
if (-not $ZapretDir) { Write-Host "Start zapret-auto.ps1 (or the START bat), not this file."; exit 1 }

# ===================== STATS =====================
$Stats = @{}
$script:Quar = @{}
function Load-Stats {
  if (-not (Test-Path $StatsFile)) { return $false }
  try {
    $obj = Get-Content $StatsFile -Raw | ConvertFrom-Json
    $saved = $null
    foreach ($p in $obj.PSObject.Properties) {
      if ($p.Name -eq "_config") { $saved = "$($p.Value)"; continue }
      if ($all -contains $p.Name) { $script:Stats[$p.Name] = [double]$p.Value }
    }
    if ($RelearnOnChange -and $saved -and $saved -ne $ConfigPrint) {
      Log (T "relearn" "zapret settings changed (lists, ipset, strategies or packs) - relearning") "Magenta"
      $script:Stats = @{}; return $false
    }
    return $true
  } catch { Log (T "stats.broken" "Stats file is broken, relearning") "Yellow"; $script:Stats = @{}; return $false }
}
function Save-Stats {
  $o = @{}; foreach ($k in $script:Stats.Keys) { $o[$k] = $script:Stats[$k] }
  $o["_config"] = $ConfigPrint
  $o | ConvertTo-Json | Set-Content -Path $StatsFile
}
function Get-Score($name) { if ($script:Stats.ContainsKey($name)) { return [double]$script:Stats[$name] }; return 0 }
function Set-Score($name, $value) { $v = [double]$value; if ($v -lt 0) { $v = 0 }; $script:Stats[$name] = [math]::Round([math]::Min($v, $ScoreCap), 2) }
function Get-Order {
  $o = @($all | Sort-Object @{ Expression = { Get-Score $_ }; Descending = $true }, @{ Expression = { $_ } })
  if ($Prefer) { $o = @($Prefer) + @($o | Where-Object { $_ -ne $Prefer }) }
  return $o
}
function Show-Top {
  $order = Get-Order; $n = [math]::Min(5, $order.Count)
  Write-Host (" ---- " + (T "top" "TOP {0}" $n) + " ----") -ForegroundColor DarkCyan
  for ($i = 0; $i -lt $n; $i++) {
    $mark = ""; if ($order[$i] -eq $Prefer) { $mark = " " + (T "fav.mark" "[favourite]") }
    Write-Host ("  {0}. {1}  ({2}){3}" -f ($i + 1), $order[$i], [math]::Round((Get-Score $order[$i]), 1), $mark) -ForegroundColor DarkCyan
  }
}

# ===================== CHECKS =====================
function Get-Size($url, $range = 0, $timeout = $Timeout) {
  $curlArgs = @("-s", "-o", "NUL", "-m", $timeout, "--connect-timeout", "5", "--proto", "=http,https", "-w", "%{size_download}")
  if ($range -gt 0) { $curlArgs += @("-r", "0-$($range - 1)") }
  $size = & $Curl @curlArgs $url
  $code = $LASTEXITCODE; $n = 0
  [void][int64]::TryParse("$size", [ref]$n)
  if ($code -ne 0) { if ($n -gt 0) { return $n }; return -1 }
  return $n
}
function Test-Url($url, $minBytes, $range = 0, $timeout = $Timeout) { $n = Get-Size $url $range $timeout; return ($n -ge 0 -and $n -ge $minBytes) }
function Test-Internet {
  if (Test-Url "https://ya.ru" 0) { return $true }
  if (Test-Url "http://www.msftconnecttest.com/connecttest.txt" 0) { return $true }
  return $false
}
function Wait-Internet {
  if (Test-Internet) { return }
  State "nointernet"; $offSince = Get-Date
  Log (T "noinet" "No internet connection - waiting, ratings are not touched") "Magenta"
  while (-not (Test-Internet)) { Beat; Start-Sleep 15 }
  Log (T "inet.back" "Internet is back") "Magenta"; $script:aliveSince = $script:aliveSince + ((Get-Date) - $offSince)
  if ($script:current) { State "working $($script:current)" } else { State "back" }
}
function Test-Discord {
  if (Test-Url "https://discord.com" 0 16384 $DiscordTimeout) { return $true }
  if (Test-Url "https://gateway.discord.gg" 0 0 $DiscordTimeout) { Status (T "discord.slow" "Discord: discord.com slow, gateway OK") "DarkGray"; return $true }
  return $false
}

$script:VideoHost = $null
$script:VideoFallback = $false
$videoRx = '^rr\d{1,2}---sn-[a-z0-9]{4,12}(-[a-z0-9]{2,12})?\.googlevideo\.com$'
$Redirector = "https://redirector.googlevideo.com/report_mapping?di=no"
function Find-VideoHost {
  $txt = & $Curl -s -m 8 --connect-timeout 5 --proto "=https" $Redirector
  if ($LASTEXITCODE -ne 0 -or -not $txt) { return $null }
  if ("$txt" -match '(sn-[a-z0-9]{4,12}(-[a-z0-9]{2,12})?)') { $h = "rr1---$($matches[1]).googlevideo.com"; if ($h -match $videoRx) { return $h } }
  return $null
}
function Update-VideoHost {
  $h = Find-VideoHost
  if ($h) {
    if ($h -ne $script:VideoHost) { Log (T "video.found" "YouTube video server: {0}" $h) "DarkGray" }
    $script:VideoHost = $h; $script:VideoFallback = $false
  } elseif (-not $script:VideoHost -and -not $script:VideoFallback) {
    $script:VideoFallback = $true
    Log (T "video.fallback" "YouTube video server not found - checking redirector.googlevideo.com instead") "Yellow"
  }
}
function Test-Video {
  if ($script:VideoHost) {
    $codeTxt = & $Curl -s -o NUL -m $Timeout --connect-timeout 5 --proto "=https" -w "%{http_code}" "https://$($script:VideoHost)/generate_204"
    return ("$codeTxt" -eq "204")
  }
  if ($script:VideoFallback) { return (Test-Url $Redirector 0) }
  return $true
}
function Test-Critical($quiet = $false) {
  foreach ($c in $Critical) { if (-not (Test-Url $c.Url 0)) { if (-not $quiet) { Log (T "chk.crit" "Check: {0} no response" $c.Name) "Yellow" }; return $false } }
  return $true
}
function Get-QuickResult {
  $yt = Get-Size "https://www.youtube.com" 262144
  if ($yt -ge $YouTubeMin) {
    if (-not (Test-Discord)) { return "none" }
    if (-not (Test-Video)) { return "none" }
    if (-not (Test-Critical $true)) { return "none" }
    return "ok"
  }
  if ($yt -ge $CutMin) { return "cut" }
  return "none"
}
function Test-Ok($heavy = $true, $video = $true) {
  if ($heavy) { if (-not (Test-Url "https://www.youtube.com" $YouTubeMin 262144)) { Log (T "chk.ytcut" "Check: YouTube cut off or no response") "Yellow"; return $false } }
  else { if (-not (Test-Url "https://www.youtube.com" 0 16384)) { Log (T "chk.yt" "Check: YouTube no response") "Yellow"; return $false } }
  if (-not (Test-Discord)) { Log (T "chk.discord" "Check: Discord no response") "Yellow"; return $false }
  if ($video -and -not (Test-Video)) { Log (T "chk.video" "Check: YouTube video server no response") "Yellow"; return $false }
  if (-not (Test-Critical)) { return $false }
  return $true
}
function Test-WarmUp {
  $start = Get-Date; Start-Sleep $FirstCheck
  while ($true) {
    Beat
    $r = Get-QuickResult
    $sec = [math]::Round(((Get-Date) - $start).TotalSeconds)
    if ($r -eq "ok") { Log ("   " + (T "warm.ready" "ready after {0} s" $sec)) "DarkGray"; return $true }
    if ($r -eq "cut") { Log ("   " + (T "warm.cut" "YouTube cut by DPI after {0} s - dropped" $sec)) "DarkGray"; return $false }
    if ($sec -ge $MaxWarmUp) { Log ("   " + (T "warm.none" "no answer after {0} s" $sec)) "DarkGray"; return $false }
    Start-Sleep $CheckStep
  }
}
function Test-Full {
  $passed = 0; $failedNames = @()
  foreach ($t in $Targets) {
    Beat
    if ($t.Url -match 'www\.youtube\.com') { $ok = Test-Url $t.Url $YouTubeMin 262144 }
    elseif ($t.Url -match 'discord') { $ok = Test-Url $t.Url 0 0 $DiscordTimeout }
    else { $ok = Test-Url $t.Url 0 }
    if ($ok) { $passed++ } else { $failedNames += $t.Name }
  }
  return @{ Passed = $passed; Failed = $failedNames }
}

# ===================== WINDOW =====================
# first run: the window stays during the full test, then a countdown, then it hides to the tray
function Ask-Hide {
  if ($ShowConsole) { return }
  try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { Win "hide"; return }
  Write-Host ""
  for ($i = $HideCountdown; $i -gt 0; $i--) {
    Write-Host ("`r" + (T "hide.count" "The window will hide to the tray in {0} s. Press any key to keep it open." $i) + "   ") -NoNewline -ForegroundColor Cyan
    Beat
    for ($j = 0; $j -lt 10; $j++) {
      if ([Console]::KeyAvailable) {
        [void][Console]::ReadKey($true); Write-Host ""
        Log (T "hide.keep" "OK, the window stays open. You can hide it from the tray menu.") "Cyan"
        Win "keep"; return
      }
      Start-Sleep -Milliseconds 100
    }
  }
  Write-Host ""
  Win "hide"
}

# ===================== CORE =====================
function Start-Strategy($name) {
  $old = Get-Process winws -ErrorAction SilentlyContinue
  if ($old) { $old | Stop-Process -Force }
  Start-Sleep 2
  Log (T "starting" "Starting {0} (score {1})" $name ([math]::Round((Get-Score $name), 1))) "Cyan"
  Start-Process -FilePath (Join-Path $ZapretDir $name) -WorkingDirectory $ZapretDir -WindowStyle Hidden
  Start-Sleep 2
  if (-not (Get-Process winws -ErrorAction SilentlyContinue)) {
    Start-Sleep 3
    if (-not (Get-Process winws -ErrorAction SilentlyContinue)) { Log (T "winws.fail" "ERROR: winws did not start") "Red" }
  }
}
function Set-Working($name) {
  $script:current = $name; $script:aliveSince = Get-Date
  Log (T "working" "Working: {0}" $name) "Green"
  State "working $name"
  if (-not $script:VideoHost) { Update-VideoHost }
  Show-Top
  if ($script:AskHide) { $script:AskHide = $false; Ask-Hide }
}
function Sweep-One($s) {
  Start-Strategy $s
  if (-not (Test-WarmUp)) { return $null }
  if (-not $script:VideoHost) { Update-VideoHost }
  return (Test-Full)
}
function Full-Sweep {
  $sweepStart = Get-Date
  State "testing"
  Log (T "full.start" "Full test: {0} strategies (about 5-12 min, internet will blink)" $all.Count) "Magenta"
  $total = $Targets.Count; $i = 0
  foreach ($s in $all) {
    $i++
    Beat
    State "test $i/$($all.Count)"
    Log "[$i/$($all.Count)]" "DarkGray"
    Wait-Internet
    $r = Sweep-One $s
    if ($null -eq $r -and -not (Test-Internet)) { Log (T "full.drop" "Internet dropped during the test of {0} - testing again" $s) "Magenta"; Wait-Internet; $r = Sweep-One $s }
    if ($null -eq $r) { Set-Score $s 0; Log (T "full.fail" "FAIL {0} - YouTube, Discord or a critical pack not working" $s) "DarkYellow" }
    else {
      Set-Score $s (30 * $r.Passed / $total)
      Log (T "full.pass" "PASS {0} - {1}/{2}" $s $r.Passed $total) "Green"
      if ($r.Failed.Count -gt 0) { Log ("   " + (T "full.notwork" "not working: {0}" ($r.Failed -join ', '))) "DarkGray" }
    }
  }
  Save-Stats
  Log (T "full.done" "Full test done in {0} min. Best: {1}" ([math]::Round(((Get-Date) - $sweepStart).TotalMinutes, 1)) ((Get-Order)[0])) "Magenta"
}
function Find-Working($dead) {
  Rotate-Log
  # order: fresh strategies by rating, then quarantined ones, the one that just died - last
  $now = Get-Date; $fresh = @(); $quar = @()
  foreach ($s in (Get-Order)) {
    if ($s -eq $dead) { continue }
    if ($script:Quar.ContainsKey($s) -and $script:Quar[$s] -gt $now) { $quar += $s } else { $fresh += $s }
  }
  $order = @($fresh) + @($quar); if ($dead) { $order += $dead }
  foreach ($s in $order) {
    Beat
    Wait-Internet
    Start-Strategy $s
    if (Test-WarmUp) { Set-Working $s; Save-Stats; return }
    if (-not (Test-Internet)) { Wait-Internet; Start-Strategy $s; if (Test-WarmUp) { Set-Working $s; Save-Stats; return } }
    Set-Score $s ((Get-Score $s) * 0.8); Save-Stats
  }
  Log (T "nostrategy" "No strategy passed the check, staying on the best one and retrying later") "Red"
  State "nostrategy"
  $best = (Get-Order)[0]; Start-Strategy $best
  $script:current = $best; $script:aliveSince = Get-Date
}

# ===================== START =====================
$script:current = $null; $script:aliveSince = Get-Date
$script:AskHide = $FirstRun -and -not $ShowConsole
$bad = 0; $checkNo = 0
State "start"; Beat
Log (T "start" "Start, waiting for network...")
Start-Sleep 20
Beat
Wait-Internet
if (-not (Load-Stats)) { Full-Sweep }
foreach ($s in $all) { if (-not $Stats.ContainsKey($s)) { $Stats[$s] = 0 } }
foreach ($k in @($Stats.Keys)) { Set-Score $k $Stats[$k] }
Save-Stats
$first = (Get-Order)[0]
Start-Strategy $first
if (Test-WarmUp) { Set-Working $first } else { Find-Working $first }

while ($true) {
  Beat
  Start-Sleep $Interval
  Beat
  $checkNo++
  if ($checkNo % 60 -eq 0) { Rotate-Log }
  $heavy = ($checkNo % $HeavyEvery -eq 0)
  $video = ($checkNo % $VideoEvery -eq 0)
  if ($video -and -not $script:VideoHost) { Update-VideoHost }
  $alive = [math]::Round(((Get-Date) - $script:aliveSince).TotalMinutes, 1)
  if (Test-Ok $heavy $video) {
    $bad = 0
    if ($alive -gt (Get-Score $script:current) -and (Get-Score $script:current) -lt $ScoreCap) { Set-Score $script:current $alive; Save-Stats }
    Status (T "ok" "OK - {0} (up {1} min)" $script:current $alive) "Green"
  }
  elseif (-not (Test-Internet)) { $bad = 0; Wait-Internet }
  else {
    $bad++
    Status (T "fail" "FAIL ({0}/{1}) - {2}" $bad $Fails $script:current) "Red"
    if ($bad -ge $Fails) {
      # v9.5.2: a real penalty - the score is cut (by default in half), plus a quarantine
      $old = Get-Score $script:current
      Set-Score $script:current ([math]::Max($old, $alive) * $FailPenalty); Save-Stats
      State "switching"
      Log (T "died" "{0} died after {1} min, new score {2}" $script:current $alive ([math]::Round((Get-Score $script:current), 1))) "Yellow"
      if ($QuarantineMin -gt 0) {
        $script:Quar[$script:current] = (Get-Date).AddMinutes($QuarantineMin)
        Log (T "quar" "{0} is in quarantine for {1} min - trying others first" $script:current $QuarantineMin) "DarkYellow"
      }
      Find-Working $script:current
      $bad = 0
    }
  }
}
