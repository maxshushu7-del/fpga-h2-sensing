@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (py -3 scripts\check_local.py) else (python scripts\check_local.py)
pause
