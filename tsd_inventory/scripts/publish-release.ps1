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

    [ValidateSet("Auto", "yc", "aws")]
    [string]$UploadTool = "Auto",

    [string]$Bucket = "tsd-inventory-updates-b1g3poudt",
    [string]$DeviceId = "2502410",
    [string]$PackageName = "ru.tsd.tsd_inventory",
    [string]$AdbPath = "C:\Android\Sdk\platform-tools\adb.exe",
    [string]$S3Endpoint = "https://storage.yandexcloud.net"
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
$apkFileName = "tsd-inventory-$versionName-$versionCode.apk"
$apkKey = "releases/$apkFileName"

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

$manifest = [ordered]@{
    versionName = $versionName
    versionCode = $versionCode
    apkKey = $apkKey
    sha256 = $sha256
    releaseNotes = $ReleaseNotes.Trim()
    required = [bool]$Required
}

$manifestJson = $manifest | ConvertTo-Json -Depth 3
Write-Utf8WithoutBom -Path $manifestPath -Value $manifestJson

Write-Host "[3/5] Manifest generated: $manifestPath" -ForegroundColor Cyan
Write-Host "       APK:       $sourceApkPath"
Write-Host "       Object:    $apkKey"
Write-Host "       SHA-256:   $sha256"
Write-Host "       Required:  $([bool]$Required)"

if (-not $BuildOnly) {
    $selectedUploadTool = $UploadTool
    $ycPath = Resolve-CommandPath -Name "yc"
    $awsPath = Resolve-CommandPath -Name "aws"

    if ($selectedUploadTool -eq "Auto") {
        if (-not [string]::IsNullOrWhiteSpace($ycPath)) {
            $selectedUploadTool = "yc"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($awsPath)) {
            $selectedUploadTool = "aws"
        }
        else {
            throw "Neither Yandex Cloud CLI ('yc') nor AWS CLI ('aws') was found. Install and authenticate one of them, or use -BuildOnly."
        }
    }

    $apkUri = "s3://$Bucket/$apkKey"
    $manifestUri = "s3://$Bucket/manifest.json"

    Write-Host "[4/5] Uploading APK with $selectedUploadTool..." -ForegroundColor Cyan

    if ($selectedUploadTool -eq "yc") {
        if ([string]::IsNullOrWhiteSpace($ycPath)) {
            throw "Yandex Cloud CLI ('yc') was not found in PATH."
        }

        # The APK is uploaded first. The manifest remains unchanged if this fails.
        Invoke-NativeCommand -FilePath $ycPath -Arguments @(
            "storage", "s3", "cp", $sourceApkPath, $apkUri
        )
        Invoke-NativeCommand -FilePath $ycPath -Arguments @(
            "storage", "s3api", "head-object",
            "--bucket", $Bucket,
            "--key", $apkKey
        )

        Write-Host "[5/5] Uploading manifest last..." -ForegroundColor Cyan
        Invoke-NativeCommand -FilePath $ycPath -Arguments @(
            "storage", "s3", "cp", $manifestPath, $manifestUri
        )
        Invoke-NativeCommand -FilePath $ycPath -Arguments @(
            "storage", "s3api", "head-object",
            "--bucket", $Bucket,
            "--key", "manifest.json"
        )
    }
    else {
        if ([string]::IsNullOrWhiteSpace($awsPath)) {
            throw "AWS CLI ('aws') was not found in PATH."
        }

        # AWS CLI reads credentials from its profile or AWS_* environment variables.
        Invoke-NativeCommand -FilePath $awsPath -Arguments @(
            "--endpoint-url=$S3Endpoint",
            "s3", "cp", $sourceApkPath, $apkUri,
            "--content-type", "application/vnd.android.package-archive",
            "--only-show-errors"
        )
        Invoke-NativeCommand -FilePath $awsPath -Arguments @(
            "--endpoint-url=$S3Endpoint",
            "s3api", "head-object",
            "--bucket", $Bucket,
            "--key", $apkKey
        )

        Write-Host "[5/5] Uploading manifest last..." -ForegroundColor Cyan
        Invoke-NativeCommand -FilePath $awsPath -Arguments @(
            "--endpoint-url=$S3Endpoint",
            "s3", "cp", $manifestPath, $manifestUri,
            "--content-type", "application/json",
            "--cache-control", "no-store",
            "--only-show-errors"
        )
        Invoke-NativeCommand -FilePath $awsPath -Arguments @(
            "--endpoint-url=$S3Endpoint",
            "s3api", "head-object",
            "--bucket", $Bucket,
            "--key", "manifest.json"
        )
    }
}
else {
    Write-Host "[4/5] Upload skipped (-BuildOnly)." -ForegroundColor Yellow
    Write-Host "[5/5] Upload skipped (-BuildOnly)." -ForegroundColor Yellow
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
