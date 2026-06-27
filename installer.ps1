$Host.UI.RawUI.WindowTitle = "SteamVault Installer | Plugin Manager"
$name = "steamvault"
$link = "https://github.com/notninja974/installer/releases/download/v4.8/steamvault.zip"
$MillVersion = "v2.36.4"
$MillUrl     = "https://github.com/SteamClientHomebrew/Millennium/releases/download/$MillVersion/millennium-$MillVersion-windows-x86_64.zip"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

function Find-SteamPath {
    $PossiblePaths = @()
    try {
        $regPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
        if ($regPath.InstallPath) { $PossiblePaths += $regPath.InstallPath }
    } catch {}
    try {
        $regPath = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($regPath.SteamPath) { $PossiblePaths += $regPath.SteamPath }
    } catch {}

    $SteamDefault = "C:\Program Files (x86)\Steam"
    if (Test-Path $SteamDefault) { $PossiblePaths += $SteamDefault }
    $PossiblePaths = $PossiblePaths | Select-Object -Unique | Where-Object { Test-Path $_ }

    if ($PossiblePaths.Count -eq 0) { return $null }
    return $PossiblePaths[0]
}

$steamPath = Find-SteamPath
if (-not $steamPath) {
    Write-Host "[ERR] No se pudo encontrar la ruta de instalacion de Steam." -ForegroundColor Red
    Read-Host "`nPresiona Enter para cerrar..."
    exit
}
$upperName = "SteamVault"

function Log {
    param ([string]$Type, [string]$Message, [boolean]$NoNewline = $false)
    $foreground = switch ($Type.ToUpper()) {
        "OK"   { "Green" }
        "INFO" { "Cyan" }
        "ERR"  { "Red" }
        "LOG"  { "Magenta" }
        default { "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor "Cyan" -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $foreground
}

$ProgressPreference = 'SilentlyContinue'

Write-Host "`n==========================================================" -ForegroundColor Yellow
Write-Host "                STEAM VAULT INSTALLER                      " -ForegroundColor Yellow
Write-Host "==========================================================`n" -ForegroundColor Yellow

Log "INFO" "Cerrando Steam para preparar el entorno..."
Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force

Log "LOG" "Configurando dependencias..."

$stPath = Join-Path $steamPath "xinput1_4.dll"
if (!(Test-Path $stPath)) {
    $script = Invoke-RestMethod "https://steam.run"
    $keptLines = @()
    foreach ($line in $script -split "`n") {
        $conditions = @(
            ($line -imatch "Start-Process" -and $line -imatch "steam"),
            ($line -imatch "steam\.exe"),
            ($line -imatch "Start-Sleep" -or $line -imatch "Write-Host"),
            ($line -imatch "cls" -or $line -imatch "exit"),
            ($line -imatch "Stop-Process" -and -not ($line -imatch "Get-Process"))
        )
        if (-not($conditions -contains $true)) { $keptLines += $line }
    }
    Invoke-Expression ($keptLines -join "`n") *> $null
}

$Mill3xDir = Join-Path $steamPath "millennium"
if (Test-Path $Mill3xDir) {
    Log "INFO" "Detectado Millennium 3.x incompatible. Eliminandolo..."
    Remove-Item $Mill3xDir -Recurse -Force -ErrorAction SilentlyContinue
}

Log "LOG" "Descargando Millennium $MillVersion (compatible con backend Python)..."
$MillZip = Join-Path $env:TEMP "millennium-$MillVersion.zip"
try {
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($MillUrl, $MillZip)
}
catch {
    Log "ERR" "No se pudo descargar Millennium: $($_.Exception.Message)"
    Read-Host "`nPresiona Enter para cerrar..."
    exit
}

Log "LOG" "Instalando Millennium $MillVersion..."
try {
    $MillTmp = Join-Path $env:TEMP "millennium_extract"
    if (Test-Path $MillTmp) { Remove-Item $MillTmp -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($MillZip, $MillTmp)
    Copy-Item (Join-Path $MillTmp '*') $steamPath -Recurse -Force
    Remove-Item $MillTmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $MillZip -Force -ErrorAction SilentlyContinue
}
catch {
    Log "ERR" "No se pudo instalar Millennium: $($_.Exception.Message)"
    Read-Host "`nPresiona Enter para cerrar..."
    exit
}

Log "OK" "Dependencias listas."

$PluginsPath = Join-Path $steamPath "plugins"
if (!(Test-Path $PluginsPath)) {
    New-Item -Path $PluginsPath -ItemType Directory *> $null
}

$subPath = Join-Path $env:TEMP "$name.zip"
Log "LOG" "Descargando plugin de SteamVault..."
try {
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($link, $subPath)
    Log "OK" "Descarga finalizada correctamente."
}
catch {
    Log "ERR" "Error critico al descargar: $($_.Exception.Message)"
    Read-Host "`nPresiona Enter para cerrar..."
    exit
}

if (!(Test-Path $subPath)) {
    Log "ERR" "Error critico: No se pudo descargar el archivo."
    Read-Host "`nPresiona Enter para cerrar..."
    exit
}

Log "INFO" "Eliminando version anterior del plugin..."
$ExistingPlugin = Join-Path $PluginsPath $name
if (Test-Path $ExistingPlugin) {
    Remove-Item $ExistingPlugin -Recurse -Force -ErrorAction SilentlyContinue
}

Log "LOG" "Extrayendo componentes en el directorio..."
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($subPath, $PluginsPath)
    Log "OK" "SteamVault instalado correctamente."
}
catch {
    try {
        Expand-Archive -Path $subPath -DestinationPath $PluginsPath -Force
        Log "OK" "SteamVault instalado correctamente (metodo alternativo)."
    }
    catch {
        Log "ERR" "Error critico al extraer: $($_.Exception.Message)"
        Read-Host "`nPresiona Enter para cerrar..."
        exit
    }
}

Remove-Item $subPath -ErrorAction SilentlyContinue

Log "INFO" "Limpiando cache y optimizando archivos..."
$betaPath = Join-Path $steamPath "package\beta"
if (Test-Path $betaPath) { Remove-Item $betaPath -Recurse -Force }
$cfgPath = Join-Path $steamPath "steam.cfg"
if (Test-Path $cfgPath) { Remove-Item $cfgPath -Recurse -Force }

$configPath = Join-Path $steamPath "ext\config.json"
if (!(Test-Path $configPath)) {
    $config = @{ plugins = @{ enabledPlugins = @($name) }; general = @{ checkForMillenniumUpdates = $false } }
    if (!(Test-Path (Split-Path $configPath))) { New-Item -Path (Split-Path $configPath) -ItemType Directory -Force | Out-Null }
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
} else {
    $config = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json
    if (!$config.plugins) { $config | Add-Member -Name "plugins" -Value @{ enabledPlugins = @() } -MemberType NoteProperty }

    $enabledList = [System.Collections.Generic.List[string]]($config.plugins.enabledPlugins)
    if ($enabledList -notcontains $name) {
        $enabledList.Add($name)
        $config.plugins.enabledPlugins = $enabledList.ToArray()
    }

    if (!$config.general) { $config | Add-Member -Name "general" -Value @{} -MemberType NoteProperty }
    if ($config.general.PSObject.Properties.Name -contains "checkForMillenniumUpdates") {
        $config.general.checkForMillenniumUpdates = $false
    } else {
        $config.general | Add-Member -Name "checkForMillenniumUpdates" -Value $false -MemberType NoteProperty
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

Log "OK" "Configuracion aplicada."
Write-Host ""
Log "INFO" "Iniciando Steam..."
$exe = Join-Path $steamPath "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "           INSTALACION COMPLETADA CON EXITO               " -ForegroundColor Green
Write-Host "==========================================================`n" -ForegroundColor Green

Start-Sleep -Seconds 2
Read-Host "`nPresiona Enter para cerrar..."
