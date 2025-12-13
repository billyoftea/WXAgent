@echo off
REM WXAgent Frontend Builder
echo ========================================
echo WXAgent Frontend Builder
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

REM Clean previous build
echo [INFO] Cleaning previous build...
flutter clean
echo.

REM Get dependencies
echo [INFO] Getting dependencies...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to get dependencies!
    pause
    exit /b 1
)
echo.

REM Build release version
echo [INFO] Building release version for Windows...
echo [INFO] This may take several minutes...
flutter build windows --release

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build failed!
    pause
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo ========================================
echo.
echo Output location: build\windows\x64\runner\Release\
echo.
echo Files to distribute:
echo   - wx_agent_app.exe
echo   - flutter_windows.dll
echo   - data\ folder
echo   - Make sure to include backend executable
echo.

pause
