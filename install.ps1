## Configuración de SteamNexus
$Host.UI.RawUI.WindowTitle = "SteamNexus Installer | Plugin Manager"
$name = "steamnexus"
$link = "https://github.com/CallMeNaiky/FSTools/releases/download/steam/steamnexus.zip"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# Definiciones ocultas
$steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath
$upperName = "SteamNexus"

#### Función de Log ####
function Log {
    param ([string]$Type, [string]$Message, [boolean]$NoNewline = $false)
    $foreground = switch ($Type.ToUpper()) {
        "OK" { "Green" }
        "INFO" { "Cyan" }
        "ERR" { "Red" }
        "LOG" { "Magenta" }
        default { "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor "Cyan" -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $foreground
}

$ProgressPreference = 'SilentlyContinue'

Write-Host "`n==========================================================" -ForegroundColor Yellow
Write-Host "                STEAM NEXUS INSTALLER                     " -ForegroundColor Yellow
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

#### Instalación del Plugin SteamNexus ####
$PluginsPath = Join-Path $steamPath "plugins"
if (!(Test-Path $PluginsPath)) {
    New-Item -Path $PluginsPath -ItemType Directory *> $null
}

$subPath = Join-Path $env:TEMP "$name.zip"
Log "LOG" "Descargando plugin de SteamNexus..."
Invoke-WebRequest -Uri $link -OutFile $subPath *> $null

if (!(Test-Path $subPath)) {
    Log "ERR" "Error critico: No se pudo descargar el archivo."
    exit
}

Log "LOG" "Extrayendo componentes en el directorio..."
Expand-Archive -Path $subPath -DestinationPath $PluginsPath -Force *>$null
Remove-Item $subPath -ErrorAction SilentlyContinue

Log "OK" "SteamNexus instalado correctamente."

#### Optimización ####
Log "INFO" "Limpiando cache y optimizando archivos..."
$betaPath = Join-Path $steamPath "package\beta"
if (Test-Path $betaPath) { Remove-Item $betaPath -Recurse -Force }
$cfgPath = Join-Path $steamPath "steam.cfg"
if (Test-Path $cfgPath) { Remove-Item $cfgPath -Recurse -Force }

# Habilitar en config.json
$configPath = Join-Path $steamPath "ext/config.json"
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
