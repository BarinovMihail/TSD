[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,

    [Parameter(Position = 1)]
    [string]$ReleaseNotes,

    [switch]$Required,
    [switch]$InstallToTsd,
    [switch]$BuildOnly,
    [switch]$Force,

    # Формат публикации APK на Диске. Приложение умеет читать оба.
    #   apk — залить готовый .apk (по умолчанию, проще).
    #   zip — упаковать .apk в .zip (исторический формат).
    [ValidateSet("apk", "zip")]
    [string]$Format = "apk",

    # Путь к папке с обновлениями на Яндекс Диске (где лежат manifest.json и
    # каталог releases/). Например: "APK NO DELETE/ТСД".
    [string]$DiskFolder = "APK NO DELETE/ТСД",

    # OAuth-токен Яндекс Диска для выгрузки. Если не передан явно, читается из
    # переменной окружения $env:YANDEX_DISK_OAUTH_TOKEN. Нужен только скрипту;
    # в само приложение токен НЕ попадает (приложение читает публичную папку).
    [string]$OAuthToken,

    [string]$DeviceId = "2502410",
    [string]$PackageName = "ru.tsd.tsd_inventory",
    [string]$AdbPath = "C:\Android\Sdk\platform-tools\adb.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
    }
}

function Resolve-CommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    return $command.Path
}

function Write-Utf8WithoutBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $Path,
        $Value + [Environment]::NewLine,
        $utf8WithoutBom
    )
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Read-Host "Release version (example: 0.2.8+10)"
}

$versionMatch = [regex]::Match(
    $Version.Trim(),
    '^(?<name>\d+\.\d+\.\d+)\+(?<code>[1-9]\d*)$'
)

if (-not $versionMatch.Success) {
    throw "Invalid version '$Version'. Expected format: 0.2.8+10"
}

$versionName = $versionMatch.Groups["name"].Value
$versionCode64 = [long]$versionMatch.Groups["code"].Value
if ($versionCode64 -gt [int]::MaxValue) {
    throw "Version code must not exceed $([int]::MaxValue)."
}
$versionCode = [int]$versionCode64

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    $ReleaseNotes = Read-Host "Release notes"
}

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    throw "Release notes must not be empty."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$distDirectory = Join-Path $projectRoot "dist"
$manifestPath = Join-Path $distDirectory "manifest.json"
$sourceApkPath = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"
$apkFileName = "tsd-inventory-$versionName-$versionCode"
# Формат публикации: apk (готовый .apk) или zip (apk внутри .zip). Приложение
# умеет читать оба (см. update_repository.dart — автоопределение по расширению).
$publishExtension = if ($Format -eq "zip") { "zip" } else { "apk" }
# Локальный публикуемый файл (apk напрямую или zip с apk внутри).
$localPublishPath = Join-Path $distDirectory "$apkFileName.$publishExtension"
$publishName = "$apkFileName.$publishExtension"
# Путь к файлу относительно публичной папки Диска (тот же, что в apkPath манифеста).
$apkPath = "releases/$publishName"
# Полный путь на Диске (от корня Диска): <папка>/releases/<файл>.
$diskReleasesPrefix = ($DiskFolder.TrimEnd('/').TrimEnd('\') + "/releases") -replace '\\', '/'

if (-not (Test-Path -LiteralPath $distDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null
}

if ((Test-Path -LiteralPath $manifestPath -PathType Leaf) -and -not $Force) {
    $currentManifest = $null
    try {
        $currentManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "The existing manifest could not be checked: $($_.Exception.Message)"
    }

    if (($null -ne $currentManifest) -and
        ($null -ne $currentManifest.versionCode) -and
        ($versionCode -le [int]$currentManifest.versionCode)) {
        throw "Version code $versionCode must be greater than the current manifest code $($currentManifest.versionCode). Use a newer code or -Force for an intentional republish."
    }
}

$flutterPath = Resolve-CommandPath -Name "flutter"
if ([string]::IsNullOrWhiteSpace($flutterPath)) {
    throw "Flutter was not found in PATH. Open a terminal where the 'flutter' command works."
}

Push-Location $projectRoot
try {
    Write-Host "[1/5] Building APK $versionName ($versionCode)..." -ForegroundColor Cyan
    Invoke-NativeCommand -FilePath $flutterPath -Arguments @(
        "build",
        "apk",
        "--release",
        "--build-name=$versionName",
        "--build-number=$versionCode"
    )
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $sourceApkPath -PathType Leaf)) {
    throw "Flutter completed, but the APK was not found: $sourceApkPath"
}

Write-Host "[2/5] Calculating SHA-256..." -ForegroundColor Cyan
$sha256 = (Get-FileHash -LiteralPath $sourceApkPath -Algorithm SHA256).Hash.ToLowerInvariant()

# Подготовка публикуемого файла: apk напрямую или zip с apk внутри.
if ($Format -eq "zip") {
    Write-Host "[2.5/5] Packaging APK into zip..." -ForegroundColor Cyan
    if (Test-Path -LiteralPath $localPublishPath) {
        Remove-Item -LiteralPath $localPublishPath -Force
    }
    Compress-Archive -LiteralPath $sourceApkPath -DestinationPath $localPublishPath -CompressionLevel Optimal
} else {
    Write-Host "[2.5/5] Copying APK as-is ($Format)..." -ForegroundColor Cyan
    Copy-Item -LiteralPath $sourceApkPath -Destination $localPublishPath -Force
}

$manifest = [ordered]@{
    versionName = $versionName
    versionCode = $versionCode
    apkPath = $apkPath
    sha256 = $sha256
    releaseNotes = $ReleaseNotes.Trim()
    required = [bool]$Required
}

$manifestJson = $manifest | ConvertTo-Json -Depth 3
Write-Utf8WithoutBom -Path $manifestPath -Value $manifestJson

Write-Host "[3/5] Manifest generated: $manifestPath" -ForegroundColor Cyan
Write-Host "       APK:       $sourceApkPath"
Write-Host "       Publish:   $localPublishPath ($Format)"
Write-Host "       apkPath:   $apkPath"
Write-Host "       SHA-256:   $sha256"
Write-Host "       Required:  $([bool]$Required)"

if (-not $BuildOnly) {
    if ([string]::IsNullOrWhiteSpace($OAuthToken)) {
        $OAuthToken = $env:YANDEX_DISK_OAUTH_TOKEN
    }
    if ([string]::IsNullOrWhiteSpace($OAuthToken)) {
        throw "No Yandex Disk OAuth token. Pass -OAuthToken or set $env:YANDEX_DISK_OAUTH_TOKEN, or use -BuildOnly."
    }

    $apiBase = "https://cloud-api.yandex.net/v1/disk"

    # Запрос временной прямой ссылки для загрузки файла (PUT) на Диск.
    # Возвращает JSON { href, method }. Перезаписываем существующий файл.
    function Get-UploadHref {
        param([string]$DiskPath)
        $encodedPath = [uri]::EscapeDataString($DiskPath)
        $url = "$apiBase/resources/upload?path=$encodedPath&overwrite=true"
        $resp = Invoke-RestMethod -Uri $url -Method Get -Headers @{ Authorization = "OAuth $OAuthToken" }
        return $resp.href
    }

    # Загрузка байтов локального файла на Диск по выданной ссылке (HTTP PUT).
    function Send-ToDisk {
        param([string]$LocalPath, [string]$DiskPath)
        Write-Host "       -> $DiskPath" -ForegroundColor DarkGray
        $href = Get-UploadHref -DiskPath $DiskPath
        Invoke-RestMethod -Uri $href -Method Put -InFile $LocalPath -ContentType "application/octet-stream" | Out-Null
    }

    # Сначала APK-файл (apk или zip), последним — manifest.json: чтобы клиенты
    # не увидели манифест, ссылающийся на ещё не залитый файл.
    Write-Host "[4/5] Uploading APK ($Format) to Yandex Disk..." -ForegroundColor Cyan
    $apkDiskPath = "$diskReleasesPrefix/$publishName"
    Send-ToDisk -LocalPath $localPublishPath -DiskPath $apkDiskPath

    Write-Host "[5/5] Uploading manifest last..." -ForegroundColor Cyan
    $manifestDiskPath = ($DiskFolder.TrimEnd('/').TrimEnd('\') + "/manifest.json") -replace '\\', '/'
    Send-ToDisk -LocalPath $manifestPath -DiskPath $manifestDiskPath

    Write-Host "Upload to Yandex Disk complete: $DiskFolder" -ForegroundColor Green
}
else {
    Write-Host "[4/5] Upload skipped (-BuildOnly)." -ForegroundColor Yellow
    Write-Host "[5/5] Upload skipped (-BuildOnly)." -ForegroundColor Yellow
    Write-Host "Manual upload to Yandex Disk folder '$DiskFolder':" -ForegroundColor Yellow
    Write-Host "  - $localPublishPath  ->  $DiskFolder/releases/$publishName" -ForegroundColor Yellow
    Write-Host "  - $manifestPath      ->  $DiskFolder/manifest.json   (APK FIRST, manifest LAST)" -ForegroundColor Yellow
}

if ($InstallToTsd) {
    $resolvedAdbPath = $null
    if (Test-Path -LiteralPath $AdbPath -PathType Leaf) {
        $resolvedAdbPath = (Resolve-Path -LiteralPath $AdbPath).Path
    }
    else {
        $resolvedAdbPath = Resolve-CommandPath -Name "adb"
    }

    if ([string]::IsNullOrWhiteSpace($resolvedAdbPath)) {
        throw "ADB was not found. Checked '$AdbPath' and PATH."
    }

    $deviceLines = & $resolvedAdbPath devices
    if ($LASTEXITCODE -ne 0) {
        throw "Could not get the ADB device list."
    }

    $devicePattern = '^' + [regex]::Escape($DeviceId) + '\s+device\b'
    if (-not ($deviceLines | Select-String -Pattern $devicePattern -Quiet)) {
        throw "ADB device '$DeviceId' is not connected or not authorized."
    }

    Write-Host "Installing the new APK on TSD $DeviceId..." -ForegroundColor Cyan
    Write-Warning "This bypasses the auto-update test because the TSD will already have version code $versionCode."
    Invoke-NativeCommand -FilePath $resolvedAdbPath -Arguments @(
        "-s", $DeviceId,
        "install", "-r",
        $sourceApkPath
    )

    $packageInfo = & $resolvedAdbPath -s $DeviceId shell dumpsys package $PackageName
    if ($LASTEXITCODE -ne 0) {
        throw "The APK was installed, but package information could not be read."
    }

    $versionInfo = $packageInfo | Select-String -Pattern "versionCode=|versionName="
    Write-Host ($versionInfo -join [Environment]::NewLine)
}

Write-Host "Release $versionName+$versionCode is ready." -ForegroundColor Green
if (-not $InstallToTsd) {
    Write-Host "The TSD was not changed. Open the app to test auto-update from the previously installed version."
}
