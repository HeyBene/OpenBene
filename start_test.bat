@echo off
REM Quick start script for testing OpenBene

echo ============================================================
echo OpenBene Test Suite Launcher
echo ============================================================
echo.
echo This script will open 3 terminal windows:
echo   1. UDP Broadcaster (mock_app.py)
echo   2. TCP Server (mock_tcp_server.py)
echo   3. Control Client (quick_test.py)
echo.
echo Press any key to start...
pause >nul

cd /d "%~dp0openbene_sdk"

REM Start UDP broadcaster
start "OpenBene - UDP Broadcaster" cmd /k "python examples\mock_app.py TestBot"

REM Wait 2 seconds
timeout /t 2 /nobreak >nul

REM Start TCP server
start "OpenBene - TCP Server" cmd /k "python examples\mock_tcp_server.py"

REM Wait 2 seconds
timeout /t 2 /nobreak >nul

REM Start control client
start "OpenBene - Control Client" cmd /k "python examples\quick_test.py && pause"

echo.
echo All components started!
echo Check the opened windows for output.
echo.
pause
