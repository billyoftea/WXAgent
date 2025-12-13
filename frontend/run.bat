@echo off
REM WXAgent Frontend Launcher
echo ========================================
echo WXAgent Frontend Launcher
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter is not installed or not in PATH!
    echo Please install Flutter from: https://flutter.dev/docs/get-started/install/windows
    pause
    exit /b 1
)

echo [INFO] Flutter found!
flutter --version
echo.

REM Navigate to frontend directory
cd /d "%~dp0"
echo [INFO] Current directory: %CD%
echo.

REM Check if dependencies are installed
if not exist "pubspec.lock" (
    echo [INFO] Installing dependencies...
    flutter pub get
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to install dependencies!
        pause
        exit /b 1
    )
    echo.
)

REM Run the application
echo [INFO] Starting WXAgent Frontend...
echo [INFO] Press 'r' for hot reload, 'R' for hot restart, 'q' to quit
echo.
flutter run -d windows

pause
