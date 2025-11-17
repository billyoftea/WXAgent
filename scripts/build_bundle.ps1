Param(
    [string]$Configuration = "Release",
    [string]$OutputName = "wx_agent_bundle"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $RepoRoot # repo root is .. from scripts
$WxAgentDir = Join-Path $RepoRoot "wx_agent"
$BinDir = Join-Path $WxAgentDir "bin"

function Build-FlutterApp {
    param(
        [string]$ProjectPath,
        [string]$AppName
    )
    Write-Host "Building $AppName ($Configuration) ..."
    Push-Location $ProjectPath
flutter build windows --$($Configuration.ToLower()) | Out-Null
    Pop-Location

    $sourceExe = Join-Path $ProjectPath "build/windows/runner/$Configuration/$AppName.exe"
    if (-not (Test-Path $sourceExe)) {
        throw "Failed to locate $AppName exe at $sourceExe"
    }

    $targetDir = Join-Path $BinDir $AppName
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item $sourceExe (Join-Path $targetDir "$AppName.exe") -Force
}

function Ensure-PyInstaller {
    if (-not (Get-Command pyinstaller -ErrorAction SilentlyContinue)) {
        Write-Host "Installing PyInstaller ..."
        pip install pyinstaller | Out-Null
    }
}

Write-Host "==== Building Flutter components ===="
Build-FlutterApp (Join-Path $RepoRoot "wx_key") "wx_key"
Build-FlutterApp (Join-Path $RepoRoot "echotrace") "echotrace"

Write-Host "==== Preparing Python environment ===="
Push-Location $WxAgentDir
pip install -r requirements.txt | Out-Null
Ensure-PyInstaller
Pop-Location

Write-Host "==== Bundling wx_agent CLI ===="
Push-Location $RepoRoot
pyinstaller `
    --noconfirm `
    --clean `
    --onefile `
    --name $OutputName `
    --add-data "$BinDir;bin" `
    wx_agent\cli.py
Pop-Location

$DistExe = Join-Path $RepoRoot "dist/$OutputName.exe"
if (Test-Path (Join-Path $WxAgentDir "config.json")) {
    Copy-Item (Join-Path $WxAgentDir "config.json") (Join-Path $RepoRoot "dist/config.json") -Force
} else {
    Copy-Item (Join-Path $WxAgentDir "config.example.json") (Join-Path $RepoRoot "dist/config.json") -Force
}

Write-Host "Bundle finished: $DistExe"
