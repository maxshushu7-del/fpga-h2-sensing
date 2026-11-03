@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0host\udp_monitor.py"
) else (
  python "%~dp0host\udp_monitor.py"
)
if errorlevel 1 echo Python 3 required: install Python and ensure it is on PATH.
pause
