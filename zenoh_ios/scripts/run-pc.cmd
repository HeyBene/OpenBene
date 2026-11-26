@echo off
rem OpenBene Zenoh PC side, Windows one-liner. The iOS app stays unchanged.
setlocal
where python >nul 2>nul && (python "%~dp0run_pc.py" %*) || (py -3 "%~dp0run_pc.py" %*)
if errorlevel 1 pause
