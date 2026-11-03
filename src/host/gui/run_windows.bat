@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "PIP_CACHE_DIR=E:\Codex\FPGA\workspace\pip_cache"
set "PY_CMD="
where py >nul 2>&1
if not errorlevel 1 (
  py -3 -c "import sys; assert sys.version_info >= (3,9)" >nul 2>&1
  if not errorlevel 1 set "PY_CMD=py -3"
)
if not defined PY_CMD (
  where python >nul 2>&1
  if not errorlevel 1 (
    python -c "import sys; assert sys.version_info >= (3,9)" >nul 2>&1
    if not errorlevel 1 set "PY_CMD=python"
  )
)
if not defined PY_CMD goto NO_PYTHON
%PY_CMD% -c "import numpy, matplotlib" >nul 2>&1
if errorlevel 1 (
  echo [1/2] Installing required packages...
  %PY_CMD% -m pip install -r requirements.txt
  if errorlevel 1 goto INSTALL_FAILED
)
echo [2/2] Start H2 UDP live dashboard (local UDP port 5001)...
%PY_CMD% "main.py"
if errorlevel 1 goto APP_FAILED
exit /b 0
:NO_PYTHON
echo ERROR: Python 3.9+ not found. Install from python.org, enable Add to PATH.
goto FAILED
:INSTALL_FAILED
echo ERROR: Dependency installation failed.
goto FAILED
:APP_FAILED
echo ERROR: App stopped unexpectedly. See messages above.
goto FAILED
:FAILED
pause
exit /b 1
