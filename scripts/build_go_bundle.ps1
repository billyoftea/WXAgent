Param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $RepoRoot # repo root is .. from scripts
$DistDir = Join-Path $RepoRoot "dist"

# Clean dist
if (Test-Path $DistDir) {
    Remove-Item $DistDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# 1. Build Echotrace (Flutter)
Write-Host "==== Building Echotrace (Flutter) ===="
$EchotraceDir = Join-Path $RepoRoot "echotrace"
Push-Location $EchotraceDir
flutter build windows --$($Configuration.ToLower())
if ($LASTEXITCODE -ne 0) { throw "Flutter build failed" }
Pop-Location

# 2. Build Backend (Go)
Write-Host "==== Building Backend (Go) ===="
$GoDir = Join-Path $RepoRoot "go_backend"
Push-Location $GoDir
go build -o wx_agent.exe ./cmd/wxagent_backend
if ($LASTEXITCODE -ne 0) { throw "Go build failed" }
Pop-Location

# 3. Assemble Bundle
Write-Host "==== Assembling Bundle ===="

# Copy Backend
Copy-Item (Join-Path $GoDir "wx_agent.exe") $DistDir -Force

# Copy Echotrace
$EchotraceBinDir = Join-Path $DistDir "bin/echotrace"
New-Item -ItemType Directory -Force -Path $EchotraceBinDir | Out-Null
$EchotraceBuildDir = Join-Path $EchotraceDir "build/windows/x64/runner/$Configuration"
Copy-Item "$EchotraceBuildDir\*" $EchotraceBinDir -Recurse -Force

# Copy Config
if (Test-Path (Join-Path $RepoRoot "wx_agent/config.json")) {
    Copy-Item (Join-Path $RepoRoot "wx_agent/config.json") (Join-Path $DistDir "config.json") -Force
} else {
    Copy-Item (Join-Path $RepoRoot "wx_agent/config.example.json") (Join-Path $DistDir "config.json") -Force
}

Write-Host "✅ Build success! Output: $DistDir"
Write-Host "   Run: cd dist; .\wx_agent.exe start"
