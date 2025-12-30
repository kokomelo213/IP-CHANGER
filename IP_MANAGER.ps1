param(
  [ValidateSet(
    "random","bestauto","bestpick","benchping",
    "disconnect","pick","status","repair","info","localrenew",
    "rawstatus","checkconfigs","cleanup","cleanupjunk"
  )]
  [string]$Action = "status",
  [string]$Root = ""
)

$ErrorActionPreference = "Stop"

# ---- Root sanitize (fixes "Illegal characters in path") ----
$ToolRoot =
  if ($Root) { $Root.Trim('"').TrimEnd('\','/') }
  else { $PSScriptRoot }

try { $ToolRoot = (Resolve-Path -LiteralPath $ToolRoot).Path } catch { $ToolRoot = $PSScriptRoot }

$ConfigDir = Join-Path $ToolRoot "wg-configs"

$TunnelPrefix = 'WireGuardTunnel$'
$AssumedLifetimeDays = 365
$MaxRotateTries = 6
$WarmupSec      = 2

$BenchIcmpTarget   = "1.1.1.1"
$BenchTcpTargetIP  = "1.1.1.1"
$BenchTcpPort      = 443
$BenchPingCount    = 3
$BenchTimeoutSec   = 1
$TcpTimeoutMs      = 900
$TcpTries          = 3

$TmpRoot = Join-Path $env:TEMP "ipm_wg_tmp"

$WGExeCandidates = @(
  (Join-Path $env:ProgramFiles "WireGuard\wireguard.exe"),
  (Join-Path ${env:ProgramFiles(x86)} "WireGuard\wireguard.exe"),
  "C:\Program Files\WireGuard\wireguard.exe",
  "C:\Program Files (x86)\WireGuard\wireguard.exe"
) | Where-Object { $_ } | Select-Object -Unique

$WGExe = $WGExeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run as Administrator (press A in the menu)." }
}

function Ensure-Ready {
  if (-not $WGExe -or -not (Test-Path $WGExe)) { throw "WireGuard not found. Install WireGuard for Windows." }
  if (-not (Test-Path $ConfigDir)) { throw "Missing folder: $ConfigDir" }
  $confs = Get-ChildItem -LiteralPath $ConfigDir -Filter "*.conf" -File -ErrorAction SilentlyContinue
  if (-not $confs -or $confs.Count -eq 0) { throw "No .conf files found in $ConfigDir." }
  return $confs
}

function Get-PublicIP {
  try { (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 6).ip }
  catch { "Offline" }
}

function Get-TunnelServices {
  Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$TunnelPrefix*" }
}

function Get-ActiveTunnelName {
  $running = Get-TunnelServices | Where-Object Status -eq 'Running' | Select-Object -First 1
  if ($running -and $running.Name.Length -gt $TunnelPrefix.Length) {
    return $running.Name.Substring($TunnelPrefix.Length)
  }
  return $null
}

function Stop-ServiceHard([string]$svcName) {
  try { sc.exe stop $svcName | Out-Null } catch {}
  for ($i=0; $i -lt 30; $i++) {
    $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $s) { break }
    if ($s.Status -eq 'Stopped') { break }
    Start-Sleep -Milliseconds 200
  }
}

function WG-UninstallTunnel([string]$tunnelName) {
  if (-not $tunnelName) { return }
  $svc = "$TunnelPrefix$tunnelName"
  Stop-ServiceHard $svc
  try { & $WGExe "/uninstalltunnelservice" "$tunnelName" | Out-Null } catch {}
}

function WG-DisconnectAll {
  foreach ($s in (Get-TunnelServices)) {
    if ($s.Name.Length -gt $TunnelPrefix.Length) {
      $name = $s.Name.Substring($TunnelPrefix.Length)
      WG-UninstallTunnel $name
    }
  }
}

function Wait-ServiceRunning([int]$TimeoutSec = 15) {
  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
    if (Get-ActiveTunnelName) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

function Wait-ForIPChange([string]$OldIP, [int]$TimeoutSec = 35) {
  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
    $ip = Get-PublicIP
    if ($ip -ne "Offline" -and $ip -ne $OldIP) { return $ip }
    Start-Sleep -Seconds 1
  }
  return $OldIP
}

# Any .conf name allowed: install using a SAFE temp copy name
function New-SafeTempConf([string]$OriginalPath) {
  if (-not (Test-Path $TmpRoot)) { New-Item -ItemType Directory -Path $TmpRoot -Force | Out-Null }
  $guid = [guid]::NewGuid().ToString("N")
  $tmpPath = Join-Path $TmpRoot ("ipm_" + $guid + ".conf")
  Copy-Item -LiteralPath $OriginalPath -Destination $tmpPath -Force
  return $tmpPath
}

function Connect-Conf([string]$confPath) {
  Ensure-Admin
  Ensure-Ready | Out-Null
  WG-DisconnectAll

  $oldIP = Get-PublicIP
  $tmpConf = New-SafeTempConf -OriginalPath $confPath

  Write-Host ("[*] Connecting using: {0}" -f (Split-Path -LiteralPath $confPath -Leaf)) -ForegroundColor Cyan
  & $WGExe "/installtunnelservice" "$tmpConf" | Out-Null
  try { Remove-Item -LiteralPath $tmpConf -Force -ErrorAction SilentlyContinue } catch {}

  if (-not (Wait-ServiceRunning -TimeoutSec 15)) { throw "Tunnel did not start. Use EMERGENCY REPAIR." }

  Start-Sleep -Seconds $WarmupSec
  $newIP = Wait-ForIPChange -OldIP $oldIP -TimeoutSec 35

  Write-Host ""
  Write-Host ("Old IP: {0}" -f $oldIP) -ForegroundColor DarkGray
  if ($newIP -eq $oldIP) {
    Write-Host ("New IP: {0} (UNCHANGED)" -f $newIP) -ForegroundColor Yellow
    Write-Host "[!] Proton exits can be the same IP. Still connected." -ForegroundColor DarkYellow
  } else {
    Write-Host ("New IP: {0}" -f $newIP) -ForegroundColor Green
  }
}

function Measure-IcmpAvg([string]$Target) {
  try {
    $r = Test-Connection -TargetName $Target -Count $BenchPingCount -TimeoutSeconds $BenchTimeoutSec -ErrorAction Stop
    $avg = ($r | Measure-Object -Property ResponseTime -Average).Average
    return [int][math]::Round($avg)
  } catch { return $null }
}

function Measure-TcpOnce([string]$RemoteIp, [int]$Port, [int]$TimeoutMs) {
  try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($RemoteIp,$Port,$null,$null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs,$false)) { try { $client.Close() } catch {}; return $null }
    $client.EndConnect($iar)
    $sw.Stop()
    try { $client.Close() } catch {}
    return [int]$sw.ElapsedMilliseconds
  } catch { return $null }
}

function Measure-TcpMedian([string]$RemoteIp, [int]$Port) {
  $vals = @()
  for ($i=0; $i -lt $TcpTries; $i++) {
    $v = Measure-TcpOnce -RemoteIp $RemoteIp -Port $Port -TimeoutMs $TcpTimeoutMs
    if ($v -ne $null) { $vals += $v }
    Start-Sleep -Milliseconds 120
  }
  if ($vals.Count -eq 0) { return $null }
  $sorted = $vals | Sort-Object
  return [int]$sorted[[int][math]::Floor(($sorted.Count-1)/2)]
}

function Measure-LiveLatency {
  $icmp = Measure-IcmpAvg -Target $BenchIcmpTarget
  if ($icmp -ne $null) { return [pscustomobject]@{ ms=$icmp; method="ICMP" } }
  $tcp = Measure-TcpMedian -RemoteIp $BenchTcpTargetIP -Port $BenchTcpPort
  if ($tcp -ne $null) { return [pscustomobject]@{ ms=$tcp; method="TCP" } }
  return [pscustomobject]@{ ms=$null; method="NONE" }
}

function Live-BenchmarkConfigs {
  Ensure-Admin
  $confs = Ensure-Ready
  $results = @()

  for ($i=0; $i -lt $confs.Count; $i++) {
    $c = $confs[$i]
    Write-Progress -Activity "Live benchmark" -Status ("Testing {0} ({1}/{2})" -f $c.Name, ($i+1), $confs.Count) -PercentComplete ([int](($i+1)*100/$confs.Count))

    WG-DisconnectAll
    $ok = $true
    try { Connect-Conf $c.FullName } catch { $ok = $false }
    $lat = if ($ok) { Measure-LiveLatency } else { [pscustomobject]@{ ms=$null; method="DOWN" } }

    $results += [pscustomobject]@{
      config  = $c.Name
      ping_ms = $lat.ms
      method  = $lat.method
      ok      = [bool]($lat.ms -ne $null)
      path    = $c.FullName
    }

    WG-DisconnectAll
  }

  Write-Progress -Activity "Live benchmark" -Completed
  return $results
}

function Try-ParseExpiryFromConf([string]$confPath) {
  $lines = Get-Content -LiteralPath $confPath -ErrorAction SilentlyContinue
  if (-not $lines) { return $null }
  $rx = '^\s*#\s*(Expires?|Expiry|Valid\s*until)\s*[: ]\s*(.+?)\s*$'
  foreach ($ln in $lines) {
    $m = [regex]::Match($ln, $rx, 'IgnoreCase')
    if ($m.Success) {
      $raw = $m.Groups[2].Value.Trim()
      $formats = @('dd-MMM-yyyy','d-MMM-yyyy','yyyy-MM-dd','dd/MM/yyyy','d/M/yyyy','dd.MM.yyyy','d.M.yyyy')
      foreach ($f in $formats) { try { return [DateTime]::ParseExact($raw, $f, [System.Globalization.CultureInfo]::InvariantCulture) } catch {} }
      try { return [DateTime]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture) } catch {}
      return $null
    }
  }
  return $null
}

function Action-Random {
  Ensure-Admin
  $confs = Ensure-Ready
  $oldIP = Get-PublicIP
  WG-DisconnectAll

  $tries = [Math]::Min($MaxRotateTries, $confs.Count)
  $pool = @($confs)

  for ($i=1; $i -le $tries; $i++) {
    if ($pool.Count -eq 0) { $pool = @($confs) }
    $pick = Get-Random -InputObject $pool
    $pool = $pool | Where-Object { $_.FullName -ne $pick.FullName }

    Write-Host ("[*] Try {0}/{1}: {2}" -f $i, $tries, $pick.Name) -ForegroundColor Yellow
    Connect-Conf $pick.FullName

    $nowIP = Get-PublicIP
    if ($nowIP -ne "Offline" -and $nowIP -ne $oldIP) { return }
    WG-DisconnectAll
  }

  Write-Host "[!] Could not obtain a different public IP after several tries." -ForegroundColor Yellow
}

function Action-Pick {
  Ensure-Admin
  $confs = Ensure-Ready

  Write-Host ""
  Write-Host "Pick a config:" -ForegroundColor Yellow
  for ($i=0; $i -lt $confs.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $confs[$i].Name) }

  while ($true) {
    Write-Host ""
    $sel = Read-Host "Number (0 to cancel)"
    if ($sel -eq "0") { return }
    if ($sel -match '^\d+$') {
      $idx = [int]$sel - 1
      if ($idx -ge 0 -and $idx -lt $confs.Count) { Connect-Conf $confs[$idx].FullName; return }
    }
    Write-Host "[!] Invalid selection." -ForegroundColor Red
  }
}

function Action-Disconnect {
  Ensure-Admin
  $before = Get-PublicIP
  WG-DisconnectAll
  $after = Wait-ForIPChange -OldIP $before -TimeoutSec 25
  Write-Host ""
  Write-Host ("Old IP: {0}" -f $before) -ForegroundColor DarkGray
  Write-Host ("Now IP: {0}" -f $after) -ForegroundColor Green
}

function Action-Status {
  $ip = Get-PublicIP
  $active = Get-ActiveTunnelName
  Write-Host ("Public IP: {0}" -f $ip) -ForegroundColor Magenta
  if ($active) { Write-Host ("Tunnel:    {0}" -f $active) -ForegroundColor Yellow }
  else { Write-Host "Tunnel:    (none)" -ForegroundColor DarkYellow }
}

function Action-RawStatus {
  $ip = Get-PublicIP
  $active = Get-ActiveTunnelName
  Write-Output ("IP:{0}" -f $ip)
  if ($active) { Write-Output ("TUNNEL:{0}" -f $active) }
}

function Action-Info {
  $info = Invoke-RestMethod -Uri "http://ip-api.com/json/?fields=status,message,query,isp,city,country" -TimeoutSec 6
  if ($info.status -ne "success") { throw $info.message }
  Write-Host ("IP:       {0}" -f $info.query)
  Write-Host ("ISP:      {0}" -f $info.isp)
  Write-Host ("Location: {0}, {1}" -f $info.city, $info.country)
}

function Action-LocalRenew {
  Ensure-Admin
  ipconfig /flushdns | Out-Null
  ipconfig /renew    | Out-Null
  Write-Host "[OK] Local network renewed." -ForegroundColor Green
}

function Action-CheckConfigs {
  $confs = Ensure-Ready
  $now = Get-Date
  $rows = foreach ($c in $confs) {
    $exp = Try-ParseExpiryFromConf $c.FullName
    $base = $c.CreationTime
    if ($c.LastWriteTime -lt $base) { $base = $c.LastWriteTime }
    if ($exp) {
      $daysLeft = [int][math]::Floor(($exp - $now).TotalDays)
      $status = if ($daysLeft -lt 0) { "EXPIRED" } elseif ($daysLeft -le 14) { "SOON" } else { "OK" }
      [pscustomobject]@{ config=$c.Name; mode="REAL"; expires=$exp.ToString("yyyy-MM-dd"); days_left=$daysLeft; status=$status }
    } else {
      $estExp = $base.AddDays($AssumedLifetimeDays)
      $estLeft = [int][math]::Floor(($estExp - $now).TotalDays)
      $status = if ($estLeft -lt 0) { "LIKELY EXPIRED" } elseif ($estLeft -le 14) { "LIKELY SOON" } else { "EST OK" }
      [pscustomobject]@{ config=$c.Name; mode="EST"; expires=$estExp.ToString("yyyy-MM-dd"); days_left=$estLeft; status=$status }
    }
  }
  Write-Host ""
  $rows | Sort-Object config | Format-Table -AutoSize
  Write-Host ""
}

function Action-Repair {
  Ensure-Admin
  Write-Host "[*] EMERGENCY REPAIR: removing ALL WireGuard tunnel services..." -ForegroundColor Yellow
  WG-DisconnectAll
  try { Restart-Service -Name "WireGuardManager" -Force -ErrorAction SilentlyContinue } catch {}
  ipconfig /flushdns | Out-Null
  Write-Host "[OK] Repair finished." -ForegroundColor Green
}

function Action-BenchPing {
  $rows = Live-BenchmarkConfigs | Sort-Object @{Expression="ok";Descending=$true}, @{Expression="ping_ms";Ascending=$true}
  Write-Host ""
  Write-Host ("LIVE BENCH PING (ICMP->TCP fallback) | target: {0} / {1}:{2}" -f $BenchIcmpTarget, $BenchTcpTargetIP, $BenchTcpPort) -ForegroundColor Cyan
  $rows | Select-Object config, ping_ms, method, ok | Format-Table -AutoSize
}

function Action-BestAuto {
  $rows = Live-BenchmarkConfigs
  $best = $rows | Where-Object { $_.ok } | Sort-Object ping_ms | Select-Object -First 1
  if (-not $best) { Write-Host "[!] No measurable results." -ForegroundColor Yellow; return }
  Write-Host ("[*] BEST -> {0} ms ({1}) -> {2}" -f $best.ping_ms, $best.method, $best.config) -ForegroundColor Green
  Connect-Conf $best.path
}

function Action-BestPick {
  $rows = Live-BenchmarkConfigs | Sort-Object @{Expression="ok";Descending=$true}, @{Expression="ping_ms";Ascending=$true}
  $okRows = $rows | Where-Object { $_.ok }
  if (-not $okRows -or $okRows.Count -eq 0) { Write-Host "[!] No measurable results." -ForegroundColor Yellow; return }

  Write-Host ""
  Write-Host "BEST VPN LIST (sorted by ping):" -ForegroundColor Cyan
  for ($i=0; $i -lt $okRows.Count; $i++) {
    $r = $okRows[$i]
    Write-Host ("[{0}] {1} | {2} ms ({3})" -f ($i+1), $r.config, $r.ping_ms, $r.method)
  }

  while ($true) {
    Write-Host ""
    $sel = Read-Host "Number (0 to cancel)"
    if ($sel -eq "0") { return }
    if ($sel -match '^\d+$') {
      $idx = [int]$sel - 1
      if ($idx -ge 0 -and $idx -lt $okRows.Count) { Connect-Conf $okRows[$idx].path; return }
    }
    Write-Host "[!] Invalid selection." -ForegroundColor Red
  }
}

function Action-Cleanup { try { Ensure-Admin; WG-DisconnectAll } catch {} }

function Action-CleanupJunk {
  try {
    if (Test-Path $TmpRoot) {
      Get-ChildItem -Path $TmpRoot -Filter "ipm_*.conf" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $TmpRoot -Force -Recurse -ErrorAction SilentlyContinue
    }
  } catch {}
}

try {
  switch ($Action) {
    "random"       { Action-Random }
    "disconnect"   { Action-Disconnect }
    "pick"         { Action-Pick }
    "status"       { Action-Status }
    "repair"       { Action-Repair }
    "info"         { Action-Info }
    "localrenew"   { Action-LocalRenew }
    "rawstatus"    { Action-RawStatus }
    "checkconfigs" { Action-CheckConfigs }
    "benchping"    { Action-BenchPing }
    "bestauto"     { Action-BestAuto }
    "bestpick"     { Action-BestPick }
    "cleanup"      { Action-Cleanup }
    "cleanupjunk"  { Action-CleanupJunk }
    default        { Action-Status }
  }
  exit 0
} catch {
  Write-Host ""
  Write-Host ("[FATAL] " + $_.Exception.Message) -ForegroundColor Red
  Write-Host ("[DETAILS] " + $_.ToString()) -ForegroundColor DarkGray
  exit 1
}
