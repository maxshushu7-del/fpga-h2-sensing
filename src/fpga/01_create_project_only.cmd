@echo off
setlocal
cd /d "%~dp0"
set "VIVADO_BAT="
if exist "C:\Xilinx\Vivado\2024.1\bin\vivado.bat" set "VIVADO_BAT=C:\Xilinx\Vivado\2024.1\bin\vivado.bat"
if not defined VIVADO_BAT (
  where vivado.bat >nul 2>nul
  if not errorlevel 1 set "VIVADO_BAT=vivado.bat"
)
if not defined VIVADO_BAT (
 echo [ERROR] Vivado 2024.1 not found on PATH or C drive.
 pause
 exit /b 1
)
call "%VIVADO_BAT%" -mode batch -source "%~dp0scripts\create_project.tcl" -log "%~dp0create_project.log" -journal "%~dp0create_project.jou"
pause
