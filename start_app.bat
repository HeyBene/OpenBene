@echo off
echo ========================================
echo OpenBene App - Quick Start
echo ========================================
echo.

cd openbene_app

echo [1/2] Installing dependencies...
echo.
call flutter pub get

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Failed to install dependencies!
    echo Please check your Flutter installation.
    pause
    exit /b 1
)

echo.
echo ========================================
echo [2/2] Dependencies installed successfully!
echo ========================================
echo.
echo Next steps:
echo.
echo 1. Connect your Android device or start emulator
echo 2. Run: flutter run
echo.
echo Or use this script to run directly:
echo.

choice /C YN /M "Do you want to run the app now"

if errorlevel 2 goto end
if errorlevel 1 goto run

:run
echo.
echo Starting app...
call flutter run

:end
echo.
echo Done!
pause
