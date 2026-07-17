<#
    Steam Cache Fixer  —  run with:  irm <raw-url> | iex

    Fixes owned games showing "PURCHASE" instead of "PLAY", an empty/half-loaded
    library, or a stuck "Cloud: Out of sync". These come from a corrupted local
    ownership/metadata cache (steam\appcache) — usually a connection drop while
    Steam was writing it.

    This script backs that cache up (RENAME, not delete — fully reversible) and
    restarts Steam so it rebuilds fresh. Your installed games in steamapps\ are
    never touched.
#>

# ── SET THIS to your raw GitHub URL so elevation can re-run the script ──────
#    (e.g. https://raw.githubusercontent.com/you/repo/main/Clear-SteamCache.ps1)
$ScriptUrl = ''
# ───────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn2{ param($m) Write-Host "    $m" -ForegroundColor Yellow }
function Write-Err2 { param($m) Write-Host "!!  $m" -ForegroundColor Red }

function Get-SteamPath {
    $candidates = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam',
                     'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                     'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($props.SteamPath)   { $candidates += $props.SteamPath }
            if ($props.InstallPath) { $candidates += $props.InstallPath }
        } catch { }
    }
    $candidates += @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam",
                     'C:\Steam', 'D:\Steam', 'E:\Steam')
    foreach ($c in $candidates) {
        if ($c) {
            $c = $c -replace '/', '\'
            if (Test-Path (Join-Path $c 'steam.exe')) { return (Resolve-Path $c).Path }
        }
    }
    throw "Couldn't find Steam. Is it installed in a normal location?"
}

function Test-Writable {
    param([string] $Path)
    try {
        $probe = Join-Path $Path (".w_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
        [IO.File]::WriteAllText($probe, 'x'); Remove-Item $probe -Force; return $true
    } catch { return $false }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Stop-Steam {
    param([string] $Exe)
    if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { Write-Ok 'Steam is not running.'; return }
    Write-Step 'Shutting Steam down gracefully...'
    Start-Process $Exe -ArgumentList '-shutdown' | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { Write-Ok 'Steam has exited.'; return }
    }
    Write-Warn2 'Graceful shutdown timed out; forcing it closed.'
    Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (Get-Process steam -ErrorAction SilentlyContinue) { throw 'Steam would not close. Close it by hand and rerun.' }
    Write-Ok 'Steam stopped.'
}

# ── main ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ' Steam Cache Fixer ' -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ''

$steam = Get-SteamPath
$exe   = Join-Path $steam 'steam.exe'
Write-Step "Steam found: $steam"

# Elevate if the cache folder isn't writable. Under irm|iex there is no local
# file to relaunch, so we re-run the hosted URL in an elevated window instead.
if (-not (Test-Writable $steam) -and -not (Test-IsAdmin)) {
    if ($ScriptUrl -notmatch '^https?://') {
        Write-Err2 "Steam's folder needs Administrator rights on this PC."
        Write-Warn2 'Close this window, reopen PowerShell as Administrator, and run the command again.'
        return
    }
    Write-Warn2 'Needs Administrator — relaunching elevated...'
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-Command',
        "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; irm '$ScriptUrl' | iex"
    )
    return
}

Write-Host ''
Write-Warn2 'This closes Steam and resets its cache. Your installed games are NOT touched.'
if ((Read-Host '    Continue? (y/N)') -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; return }

Stop-Steam -Exe $exe

$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$appcache = Join-Path $steam 'appcache'
Write-Step 'Backing up cache (reversible)...'
if (Test-Path $appcache) {
    Rename-Item -LiteralPath $appcache -NewName "appcache_backup_$stamp"
    Write-Ok "appcache -> appcache_backup_$stamp"
} else {
    Write-Warn2 'appcache already gone — nothing to back up.'
}

Write-Step 'Relaunching Steam — it rebuilds the cache and re-pulls your licenses...'
Start-Process $exe
Write-Host ''
Write-Ok 'Done. Wait ~30s, then open your Library. Games should show PLAY again.'
Write-Ok "If anything looks off, your old cache is safe at: appcache_backup_$stamp"
Write-Host ''
