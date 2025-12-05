@echo off
REM Windows build script for Go DLL compilation

echo Building Go decrypt library for Windows...

REM Change to script directory
cd /d "%~dp0"

REM Set output directory
set OUTPUT_DIR=..\windows\runner

REM Create output directory
if not exist %OUTPUT_DIR% mkdir %OUTPUT_DIR%

REM Compile 64-bit DLL
echo Compiling 64-bit DLL...
set CGO_ENABLED=1
set GOOS=windows
set GOARCH=amd64
set CGO_LDFLAGS=-static -static-libgcc -static-libstdc++
go build -buildmode=c-shared -ldflags="-s -w" -o %OUTPUT_DIR%\go_decrypt.dll main.go

if %ERRORLEVEL% EQU 0 (
    echo Build successful! DLL created at %OUTPUT_DIR%\go_decrypt.dll
) else (
    echo Build failed with error code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

echo Done!

