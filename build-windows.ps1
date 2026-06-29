param(
    [string]$OutputDir = "dist\artifacts",
    [string]$Version,
    [string]$BackendTargetOS = "windows",
    [string]$BackendTargetArch = "amd64",
    [string]$GoProxy,
    [string]$FrontendServerUrl,
    [switch]$Clean,
    [switch]$SkipInstall,
    [switch]$SkipDefaultFrontend,
    [switch]$SkipClassicFrontend,
    [switch]$SkipBackend,
    [switch]$ExportFrontendForPages
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Command '$Name' was not found. Please install it and add it to PATH."
    }
}

function Test-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $PSScriptRoot,
        [hashtable]$EnvironmentOverrides = @{}
    )

    Write-Host "[$WorkingDirectory] $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray

    Push-Location $WorkingDirectory
    $previousValues = @{}
    try {
        foreach ($key in $EnvironmentOverrides.Keys) {
            $previousValues[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
            [Environment]::SetEnvironmentVariable($key, [string]$EnvironmentOverrides[$key], "Process")
        }

        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed: $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        foreach ($key in $EnvironmentOverrides.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousValues[$key], "Process")
        }
        Pop-Location
    }
}

function Invoke-ExternalCommandAllowFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $PSScriptRoot,
        [hashtable]$EnvironmentOverrides = @{}
    )

    try {
        Invoke-ExternalCommand -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory -EnvironmentOverrides $EnvironmentOverrides
        return $true
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        return $false
    }
}

function Resolve-BuildVersion {
    param([string]$ExplicitVersion)

    if ($ExplicitVersion) {
        return $ExplicitVersion.Trim()
    }

    $fallbackVersion = "v0.0.0-dev"
    $versionFile = Join-Path $PSScriptRoot "VERSION"
    if (Test-Path $versionFile) {
        $rawVersion = Get-Content -Path $versionFile -Raw
        if ($null -ne $rawVersion) {
            $resolved = $rawVersion.Trim()
            if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                return $resolved
            }
        }
    }

    return $fallbackVersion
}

function Resolve-BackendTargetOS {
    param([string]$RawValue)

    $normalized = $RawValue.Trim().ToLowerInvariant()
    switch ($normalized) {
        "ubuntu" { return "linux" }
        "linux" { return "linux" }
        "windows" { return "windows" }
        default {
            throw "Unsupported backend target OS '$RawValue'. Supported values: windows, linux, ubuntu."
        }
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir
    )

    if (-not (Test-Path $SourceDir)) {
        throw "Directory does not exist: $SourceDir"
    }

    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $DestinationDir -Recurse -Force
}

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $parentDir = Split-Path -Parent $Path
    if ($parentDir) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$repoRoot = $PSScriptRoot
$defaultFrontendDir = Join-Path $repoRoot "web\default"
$classicFrontendDir = Join-Path $repoRoot "web\classic"
$resolvedBackendTargetOS = Resolve-BackendTargetOS -RawValue $BackendTargetOS
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
} else {
    Join-Path $repoRoot $OutputDir
}

$buildVersion = Resolve-BuildVersion -ExplicitVersion $Version
$backendBinaryName = if ($resolvedBackendTargetOS -eq "windows") {
    "new-api-{0}.exe" -f $buildVersion
} else {
    "new-api-{0}" -f $buildVersion
}
$backendOutputDir = Join-Path $resolvedOutputDir ("backend\{0}-{1}" -f $resolvedBackendTargetOS, $BackendTargetArch)
$backendBinaryPath = Join-Path $backendOutputDir $backendBinaryName
$pagesOutputDir = Join-Path $resolvedOutputDir "pages"
$buildDefaultFrontend = -not $SkipDefaultFrontend.IsPresent
$buildClassicFrontend = -not $SkipClassicFrontend.IsPresent
$buildBackend = -not $SkipBackend.IsPresent
$exportPages = $ExportFrontendForPages.IsPresent
$backendGoProxy = if ($GoProxy) {
    $GoProxy
} elseif ($resolvedBackendTargetOS -eq "linux") {
    "direct"
} else {
    ""
}

Write-Step "Checking build dependencies"
Assert-Command -Name "go"
$bunAvailable = Test-Command -Name "bun"
if (($buildDefaultFrontend -or $buildClassicFrontend) -and (-not $bunAvailable)) {
    Write-Host "bun was not found. Frontend build steps will be skipped, and backend build will continue." -ForegroundColor Yellow
    $buildDefaultFrontend = $false
    $buildClassicFrontend = $false
    if ($exportPages) {
        Write-Host "Pages export requires bun. Pages export will be skipped." -ForegroundColor Yellow
        $exportPages = $false
    }
}

Write-Step "Build parameters"
Write-Host ("Version: {0}" -f $buildVersion)
Write-Host ("Output directory: {0}" -f $resolvedOutputDir)
Write-Host ("Backend target OS: {0}" -f $resolvedBackendTargetOS)
Write-Host ("Backend target arch: {0}" -f $BackendTargetArch)
Write-Host ("Go proxy override: {0}" -f $(if ($backendGoProxy) { $backendGoProxy } else { "<not set>" }))
Write-Host ("Frontend server URL: {0}" -f $(if ($FrontendServerUrl) { $FrontendServerUrl } else { "<not set>" }))
Write-Host ("Skip install: {0}" -f $SkipInstall.IsPresent)
Write-Host ("Build default frontend: {0}" -f $buildDefaultFrontend)
Write-Host ("Build classic frontend: {0}" -f $buildClassicFrontend)
Write-Host ("Build backend: {0}" -f $buildBackend)
Write-Host ("Export frontend for Pages: {0}" -f $exportPages)
Write-Host ("bun available: {0}" -f $bunAvailable)

if ($Clean -and (Test-Path $resolvedOutputDir)) {
    Write-Step "Cleaning old artifacts"
    Remove-Item -Path $resolvedOutputDir -Recurse -Force
}

New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
New-Item -ItemType Directory -Path $backendOutputDir -Force | Out-Null

if ($buildDefaultFrontend) {
    Write-Step "Building default frontend"
    if (-not $SkipInstall) {
        Invoke-ExternalCommand -FilePath "bun" -Arguments @("install") -WorkingDirectory $defaultFrontendDir
    }
    Invoke-ExternalCommand `
        -FilePath "bun" `
        -Arguments @("run", "build") `
        -WorkingDirectory $defaultFrontendDir `
        -EnvironmentOverrides @{
            DISABLE_ESLINT_PLUGIN = "true"
            VITE_REACT_APP_VERSION = $buildVersion
            VITE_REACT_APP_SERVER_URL = $FrontendServerUrl
        }

    if ($exportPages) {
        Write-Step "Exporting default frontend for Pages"
        Copy-DirectoryContents `
            -SourceDir (Join-Path $defaultFrontendDir "dist") `
            -DestinationDir (Join-Path $pagesOutputDir "default")
    }
}

if ($buildClassicFrontend) {
    Write-Step "Building classic frontend"
    if (-not $SkipInstall) {
        Invoke-ExternalCommand -FilePath "bun" -Arguments @("install") -WorkingDirectory $classicFrontendDir
    }
    Invoke-ExternalCommand `
        -FilePath "bun" `
        -Arguments @("run", "build") `
        -WorkingDirectory $classicFrontendDir `
        -EnvironmentOverrides @{
            VITE_REACT_APP_VERSION = $buildVersion
            VITE_REACT_APP_SERVER_URL = $FrontendServerUrl
        }

    if ($exportPages) {
        Write-Step "Exporting classic frontend for Pages"
        Copy-DirectoryContents `
            -SourceDir (Join-Path $classicFrontendDir "dist") `
            -DestinationDir (Join-Path $pagesOutputDir "classic")
    }
}

if ($buildBackend) {
    $backendGoEnvironment = @{
        GOOS = $resolvedBackendTargetOS
        GOARCH = $BackendTargetArch
        CGO_ENABLED = if ($resolvedBackendTargetOS -eq "linux") { "0" } else { "1" }
    }
    if ($backendGoProxy) {
        $backendGoEnvironment["GOPROXY"] = $backendGoProxy
    }
    $backendLabel = if ($resolvedBackendTargetOS -eq "linux") {
        "Building Ubuntu/Linux backend binary"
    } else {
        "Building Windows backend binary"
    }
    Write-Step $backendLabel
    $moduleDownloadSucceeded = Invoke-ExternalCommandAllowFailure -FilePath "go" -Arguments @("mod", "download") -WorkingDirectory $repoRoot -EnvironmentOverrides $backendGoEnvironment
    if (-not $moduleDownloadSucceeded) {
        Write-Host "go mod download failed. The script will continue and try to build with the local module cache." -ForegroundColor Yellow
    }
    Invoke-ExternalCommand `
        -FilePath "go" `
        -Arguments @(
            "build",
            "-ldflags",
            "-s -w -X ""github.com/QuantumNous/new-api/common.Version=$buildVersion""",
            "-o",
            $backendBinaryPath,
            "."
        ) `
        -WorkingDirectory $repoRoot `
        -EnvironmentOverrides $backendGoEnvironment

    if ($resolvedBackendTargetOS -eq "linux") {
        $ubuntuRunScript = @'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

chmod +x "./__BACKEND_BINARY__"
exec "./__BACKEND_BINARY__"
'@.Replace("__BACKEND_BINARY__", $backendBinaryName)
        Write-TextFile -Path (Join-Path $backendOutputDir "run-ubuntu.sh") -Content $ubuntuRunScript

        $ubuntuReadme = @'
# Ubuntu backend deployment notes

## Files
- __BACKEND_BINARY__: backend executable
- run-ubuntu.sh: launch wrapper script

## Recommended environment
- Ubuntu 20.04 / 22.04 / 24.04
- systemd
- Network access to database, Redis, and upstream services

## Start steps
1. Upload the whole directory to Ubuntu, for example `/opt/new-api`
2. Run `chmod +x __BACKEND_BINARY__ run-ubuntu.sh`
3. Prepare a `.env` file in the same directory
4. Run `./run-ubuntu.sh`

## Notes
- This build uses `GOOS=linux GOARCH=__BACKEND_ARCH__`
- Linux builds use `CGO_ENABLED=0` by default for easier non-Docker deployment
'@
        $ubuntuReadme = $ubuntuReadme.Replace("__BACKEND_BINARY__", $backendBinaryName).Replace("__BACKEND_ARCH__", $BackendTargetArch)
        Write-TextFile -Path (Join-Path $backendOutputDir "README-ubuntu.md") -Content $ubuntuReadme
    }
}

if ($exportPages) {
    $pagesReadme = @"
# Aliyun ESA PAGES frontend artifact notes

## Files
- default/: static build output from `web/default`
- classic/: static build output from `web/classic`

## Deployment suggestions
- Deploy to Aliyun ESA PAGES or another static hosting platform
- If frontend and backend use different domains, verify the frontend API base URL strategy
- To set a backend URL for the classic frontend, pass `-FrontendServerUrl https://api.example.com`

## Current project limits
- The default frontend mainly calls the backend through same-origin `/api`, so it works best with:
  - reverse proxy on the same domain
  - a gateway in front of ESA PAGES that forwards `/api`, `/mj`, and `/pg` to the backend
- The classic frontend supports a custom backend URL through `VITE_REACT_APP_SERVER_URL`
"@
    Write-TextFile -Path (Join-Path $pagesOutputDir "README-pages.md") -Content $pagesReadme
}

Write-Step "Build completed"
if ($buildDefaultFrontend) {
    Write-Host ("Default frontend artifact: {0}" -f (Join-Path $defaultFrontendDir "dist"))
}
if ($buildClassicFrontend) {
    Write-Host ("Classic frontend artifact: {0}" -f (Join-Path $classicFrontendDir "dist"))
}
if ($buildBackend) {
    Write-Host ("Backend artifact: {0}" -f $backendBinaryPath)
}
if ($exportPages) {
    Write-Host ("Pages frontend artifact: {0}" -f $pagesOutputDir)
}

Write-Host ""
Write-Host "Examples:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -Clean"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -BackendTargetOS ubuntu -SkipDefaultFrontend -SkipClassicFrontend"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -ExportFrontendForPages -SkipBackend"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -ExportFrontendForPages -SkipDefaultFrontend -FrontendServerUrl https://api.example.com"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -SkipInstall -Version v1.2.3 -BackendTargetOS linux -BackendTargetArch amd64"
