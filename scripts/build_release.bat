@echo off
chcp 65001 >nul
REM WXAgent One-Click Build Script

echo ========================================
echo    WXAgent Build Tool
echo ========================================
echo.

REM Check for Go
where go >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Go not found! Please install Go and add to PATH
    echo Download: https://go.dev/dl/
    pause
    exit /b 1
)

REM Check for Flutter
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter not found! Please install Flutter and add to PATH
    echo Download: https://flutter.dev/docs/get-started/install/windows
    pause
    exit /b 1
)

echo [INFO] Go and Flutter found, starting build...
echo.

REM Run PowerShell build script
powershell -ExecutionPolicy Bypass -File "%~dp0build_release.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build failed!
    pause
    exit /b 1
)

echo.
echo [SUCCESS] Build complete!
echo Output: %~dp0..\release
echo.
pause
