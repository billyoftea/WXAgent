# WXAgent Build Release Script
# Build backend, frontend and launcher into a release package

Param(
    [string]$Configuration = "Release",
    [string]$OutputDir = ".\release"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $RepoRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    WXAgent Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Project Root: $RepoRoot"
Write-Host "Configuration: $Configuration"
Write-Host "Output Dir: $OutputDir"
Write-Host ""

# Define paths
$BackendDir = Join-Path $RepoRoot "backend"
$FrontendDir = Join-Path $RepoRoot "frontend"
$LauncherDir = Join-Path $RepoRoot "launcher"
$DistDir = Join-Path $RepoRoot $OutputDir

function Stop-ProcessesFromDirectory([string]$Dir) {
    # Stop processes that still hold files under the old release directory.
    if (-not (Test-Path $Dir)) { return }
    $resolved = (Resolve-Path $Dir -ErrorAction Stop).Path

    $targets = @()
    try {
        $targets = Get-CimInstance Win32_Process | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolved, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
    catch {
        return
    }

    foreach ($proc in $targets) {
        try {
            Write-Host "Stopping process: $($proc.Name) (PID $($proc.ProcessId))" -ForegroundColor Yellow
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
        catch {
            # ignore
        }
    }
}

function Remove-DirectoryRobust([string]$Dir) {
    # Retry directory removal and clear locking processes after the first failure.
    if (-not (Test-Path $Dir)) { return }

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Remove-Item $Dir -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -eq 1) {
                Stop-ProcessesFromDirectory $Dir
            }
            Start-Sleep -Milliseconds (400 * $attempt)
        }
    }

    # Last try, surface the original error to the user.
    Remove-Item $Dir -Recurse -Force -ErrorAction Stop
}

# Clean output directory
if (Test-Path $DistDir) {
    Write-Host "Cleaning old output directory..." -ForegroundColor Yellow
    Remove-DirectoryRobust $DistDir
}
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# ============================================
# 1. Build Backend (Go)
# ============================================
Write-Host ""
Write-Host "==== [1/4] Building Backend (Go) ====" -ForegroundColor Green

$DistBackendDir = Join-Path $DistDir "backend"
New-Item -ItemType Directory -Force -Path $DistBackendDir | Out-Null

Push-Location $BackendDir
try {
    Write-Host "Compiling backend..."
    $DistBackendExe = Join-Path $DistBackendDir "wxagent_backend.exe"
    go build -ldflags="-s -w" -o $DistBackendExe ./cmd/wxagent_backend
    if ($LASTEXITCODE -ne 0) { throw "Go build failed" }

    Write-Host "[OK] Backend compiled" -ForegroundColor Green
    
    # Copy config file (prefer release-safe template)
    $ConfigCandidates = @(
        (Join-Path $BackendDir "config.release.json"),
        (Join-Path $BackendDir "config.json")
    )

    $Copied = $false
    foreach ($Candidate in $ConfigCandidates) {
        if (Test-Path $Candidate) {
            Copy-Item $Candidate (Join-Path $DistDir "config.json") -Force
            Write-Host "[OK] Config file copied: $Candidate" -ForegroundColor Green
            $Copied = $true
            break
        }
    }

    if (-not $Copied) {
        Write-Host "[WARN] No config.json found to copy" -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}

# ============================================
# 2. Build Frontend (Flutter)
# ============================================
Write-Host ""
Write-Host "==== [2/4] Building Frontend (Flutter) ====" -ForegroundColor Green

$DistFrontendDir = Join-Path $DistDir "frontend"
New-Item -ItemType Directory -Force -Path $DistFrontendDir | Out-Null

Push-Location $FrontendDir
try {
    Write-Host "Getting Flutter dependencies..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter pub get failed" }
    
    Write-Host "Building Flutter Windows app..."
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter build failed" }
    
    # Copy Flutter build output
    $FlutterBuildDir = Join-Path $FrontendDir "build\windows\x64\runner\$Configuration"
    if (-not (Test-Path $FlutterBuildDir)) {
        $FlutterBuildDir = Join-Path $FrontendDir "build\windows\runner\$Configuration"
    }
    
    Copy-Item "$FlutterBuildDir\*" $DistFrontendDir -Recurse -Force
    Write-Host "[OK] Frontend built" -ForegroundColor Green
}
finally {
    Pop-Location
}

# ============================================
# 3. Build Launcher (Go)
# ============================================
Write-Host ""
Write-Host "==== [3/4] Building Launcher ====" -ForegroundColor Green

if (Test-Path $LauncherDir) {
    Push-Location $LauncherDir
    try {
        Write-Host "Compiling launcher..."
        $LauncherExe = Join-Path $DistDir "WXAgent.exe"
        go build -ldflags="-s -w -H=windowsgui" -o $LauncherExe .
        if ($LASTEXITCODE -ne 0) { throw "Launcher build failed" }

        Write-Host "[OK] Launcher compiled" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "[SKIP] Launcher directory not found" -ForegroundColor Yellow
}

# ============================================
# 4. Copy Module Dependencies
# ============================================
Write-Host ""
Write-Host "==== [4/4] Copying Modules ====" -ForegroundColor Green

$ModulesDir = Join-Path $RepoRoot "modules"
$DistModulesDir = Join-Path $DistDir "modules"

function Get-FlutterBuildMode([string]$Config) {
    # Convert script configuration into a flutter build mode flag.
    if ([string]::IsNullOrWhiteSpace($Config)) { return "--release" }
    switch ($Config.Trim().ToLowerInvariant()) {
        "debug" { return "--debug" }
        "profile" { return "--profile" }
        default { return "--release" }
    }
}

function Build-FlutterModule([string]$ModuleDir, [string]$Name, [string]$FlutterMode) {
    # Build a Flutter module and copy only generated runtime output into release.
    if (-not (Test-Path $ModuleDir)) {
        Write-Host "[WARN] $Name module directory not found: $ModuleDir" -ForegroundColor Yellow
        return $false
    }

    Write-Host "Building $Name module ($FlutterMode)..." -ForegroundColor Cyan
    Push-Location $ModuleDir
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "${Name}: flutter pub get failed" }

        flutter build windows $FlutterMode
        if ($LASTEXITCODE -ne 0) { throw "${Name}: flutter build windows failed" }
    }
    finally {
        Pop-Location
    }

    return $true
}

function Build-GoDecryptDll([string]$ModuleDir, [string]$Name) {
    # Build EchoTrace's Go FFI decrypt DLL before Flutter packaging copies it.
    $GoDecryptDir = Join-Path $ModuleDir "go_decrypt"
    if (-not (Test-Path $GoDecryptDir)) {
        return
    }

    $OutputDll = Join-Path $ModuleDir "windows\runner\go_decrypt.dll"
    Write-Host "Building $Name Go decrypt DLL..." -ForegroundColor Cyan

    $OldCGO = $env:CGO_ENABLED
    $OldGOOS = $env:GOOS
    $OldGOARCH = $env:GOARCH
    $OldCGOLDFLAGS = $env:CGO_LDFLAGS

    Push-Location $GoDecryptDir
    try {
        $env:CGO_ENABLED = "1"
        $env:GOOS = "windows"
        $env:GOARCH = "amd64"
        $env:CGO_LDFLAGS = "-static -static-libgcc -static-libstdc++"

        go build -buildmode=c-shared -ldflags="-s -w" -o $OutputDll main.go
        if ($LASTEXITCODE -ne 0) { throw "${Name}: go_decrypt DLL build failed" }
    }
    finally {
        $env:CGO_ENABLED = $OldCGO
        $env:GOOS = $OldGOOS
        $env:GOARCH = $OldGOARCH
        $env:CGO_LDFLAGS = $OldCGOLDFLAGS
        Pop-Location
    }
}

function Copy-FlutterBuildOutput([string]$BuildRoot, [string]$DestDir, [string]$Config) {
    # Copy Flutter Windows runtime output across known Flutter output layouts.
    $Candidates = @(
        (Join-Path $BuildRoot "build\\windows\\x64\\runner\\$Config"),
        (Join-Path $BuildRoot "build\\windows\\runner\\$Config"),
        (Join-Path $BuildRoot "build\\windows\\x64\\runner\\Release"),
        (Join-Path $BuildRoot "build\\windows\\x64\\runner\\Debug"),
        (Join-Path $BuildRoot "build\\windows\\runner\\Release"),
        (Join-Path $BuildRoot "build\\windows\\runner\\Debug")
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($Dir in $Candidates) {
        Copy-Item "$Dir\\*" $DestDir -Recurse -Force
        Write-Host "[OK] Module copied from: $Dir" -ForegroundColor Green
        return $true
    }

    return $false
}

if (Test-Path $ModulesDir) {
    New-Item -ItemType Directory -Force -Path $DistModulesDir | Out-Null
    $FlutterMode = Get-FlutterBuildMode $Configuration
    
    $EchotraceDir = Join-Path $ModulesDir "echotrace"
    if (Test-Path $EchotraceDir) {
        $EchotraceDist = Join-Path $DistModulesDir "echotrace"
        New-Item -ItemType Directory -Force -Path $EchotraceDist | Out-Null

        # Ensure module is built before copying.
        Build-GoDecryptDll -ModuleDir $EchotraceDir -Name "Echotrace"
        Build-FlutterModule -ModuleDir $EchotraceDir -Name "Echotrace" -FlutterMode $FlutterMode | Out-Null
        if (-not (Copy-FlutterBuildOutput -BuildRoot $EchotraceDir -DestDir $EchotraceDist -Config $Configuration)) {
            throw "Echotrace build output not found (expected build/windows/.../$Configuration)"
        }
    }
    
    $WxKeyDir = Join-Path $ModulesDir "wx_key"
    if (Test-Path $WxKeyDir) {
        $WxKeyDist = Join-Path $DistModulesDir "wx_key"
        New-Item -ItemType Directory -Force -Path $WxKeyDist | Out-Null

        # Ensure module is built before copying.
        Build-FlutterModule -ModuleDir $WxKeyDir -Name "WxKey" -FlutterMode $FlutterMode | Out-Null
        if (-not (Copy-FlutterBuildOutput -BuildRoot $WxKeyDir -DestDir $WxKeyDist -Config $Configuration)) {
            throw "WxKey build output not found (expected build/windows/.../$Configuration)"
        }
    }
}

$OutputDestDir = Join-Path $DistDir "output"
New-Item -ItemType Directory -Force -Path $OutputDestDir | Out-Null
Write-Host "[OK] Output directory created" -ForegroundColor Green

# ============================================
# Done
# ============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output: $DistDir" -ForegroundColor Yellow
Write-Host ""
Write-Host "Contents:" -ForegroundColor Yellow
Get-ChildItem $DistDir | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host ""
Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  1. Double-click WXAgent.exe (launches backend + frontend)"
Write-Host "  2. Or run separately:"
Write-Host "     - backend\\wxagent_backend.exe server --port=8000"
Write-Host "     - frontend\\wx_agent_app.exe"
Write-Host ""
