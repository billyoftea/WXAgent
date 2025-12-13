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

# Clean output directory
if (Test-Path $DistDir) {
    Write-Host "Cleaning old output directory..." -ForegroundColor Yellow
    Remove-Item $DistDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# ============================================
# 1. Build Backend (Go)
# ============================================
Write-Host ""
Write-Host "==== [1/4] Building Backend (Go) ====" -ForegroundColor Green

Push-Location $BackendDir
try {
    Write-Host "Compiling backend..."
    go build -ldflags="-s -w" -o wxagent_backend.exe ./cmd/wxagent_backend
    if ($LASTEXITCODE -ne 0) { throw "Go build failed" }
    
    Copy-Item "wxagent_backend.exe" $DistDir -Force
    Write-Host "[OK] Backend compiled" -ForegroundColor Green
    
    # Copy config file
    if (Test-Path "config.json") {
        Copy-Item "config.json" (Join-Path $DistDir "config.json") -Force
        Write-Host "[OK] Config file copied" -ForegroundColor Green
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
    
    Copy-Item "$FlutterBuildDir\*" $DistDir -Recurse -Force
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
        go build -ldflags="-s -w -H=windowsgui" -o WXAgent.exe .
        if ($LASTEXITCODE -ne 0) { throw "Launcher build failed" }
        
        Copy-Item "WXAgent.exe" $DistDir -Force
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

if (Test-Path $ModulesDir) {
    New-Item -ItemType Directory -Force -Path $DistModulesDir | Out-Null
    
    $EchotraceDir = Join-Path $ModulesDir "echotrace"
    if (Test-Path $EchotraceDir) {
        $EchotraceDist = Join-Path $DistModulesDir "echotrace"
        New-Item -ItemType Directory -Force -Path $EchotraceDist | Out-Null
        
        $EchoBuildDir = Join-Path $EchotraceDir "build\windows\x64\runner\$Configuration"
        if (Test-Path $EchoBuildDir) {
            Copy-Item "$EchoBuildDir\*" $EchotraceDist -Recurse -Force
            Write-Host "[OK] Echotrace copied" -ForegroundColor Green
        }
    }
    
    $WxKeyDir = Join-Path $ModulesDir "wx_key"
    if (Test-Path $WxKeyDir) {
        $WxKeyDist = Join-Path $DistModulesDir "wx_key"
        New-Item -ItemType Directory -Force -Path $WxKeyDist | Out-Null
        
        $WxKeyBuildDir = Join-Path $WxKeyDir "build\windows\x64\runner\$Configuration"
        if (Test-Path $WxKeyBuildDir) {
            Copy-Item "$WxKeyBuildDir\*" $WxKeyDist -Recurse -Force
            Write-Host "[OK] WxKey copied" -ForegroundColor Green
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
Write-Host "     - wxagent_backend.exe serve --port=8080"
Write-Host "     - wx_agent_app.exe"
Write-Host ""
