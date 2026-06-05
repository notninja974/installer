## Configuración de SteamVault
$Host.UI.RawUI.WindowTitle = "SteamVault Installer | Plugin Manager"
$name = "steamvault"
$link = "https://github.com/notninja974/installer/releases/download/v4.7.1/steamvault.zip"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath
$upperName = "SteamVault"

#### Función de Log ####
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

# Cerrar Steam para comenzar
Log "INFO" "Cerrando Steam para preparar el entorno..."
Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force

#### Instalación de Dependencias ####
Log "LOG" "Configurando dependencias..."

# Verificación de Archivos
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

# Verificación de Millennium
$millFiles = @("millennium.dll", "python311.dll")
$needsMillennium = $false
foreach ($file in $millFiles) {
    if (!(Test-Path (Join-Path $steamPath $file))) { $needsMillennium = $true; break }
}

if ($needsMillennium) {
    Invoke-Expression "& { $(Invoke-RestMethod 'https://clemdotla.github.io/millennium-installer-ps1/millennium.ps1') } -NoLog -DontStart -SteamPath '$steamPath'"
}

Log "OK" "Dependencias listas."

#### Instalación del Plugin SteamVault ####
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

#### Optimización ####
Log "INFO" "Limpiando cache y optimizando archivos..."
$betaPath = Join-Path $steamPath "package\beta"
if (Test-Path $betaPath) { Remove-Item $betaPath -Recurse -Force }
$cfgPath = Join-Path $steamPath "steam.cfg"
if (Test-Path $cfgPath) { Remove-Item $cfgPath -Recurse -Force }

# Habilitar en config.json
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
