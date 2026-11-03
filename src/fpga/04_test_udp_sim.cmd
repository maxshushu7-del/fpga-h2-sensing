@echo off
setlocal
cd /d "%~dp0"
set "VIVADO_BAT="
if exist "C:\Xilinx\Vivado\2024.1\bin\vivado.bat" set "VIVADO_BAT=C:\Xilinx\Vivado\2024.1\bin\vivado.bat"
if not defined VIVADO_BAT (
  where vivado.bat >nul 2>nul
  if not errorlevel 1 set "VIVADO_BAT=vivado.bat"
)
if not defined VIVADO_BAT (echo Vivado not found.& pause& exit /b 1)
call "%VIVADO_BAT%" -mode batch -source "%~dp0scripts\udp_sim.tcl" -log "%~dp0udp_sim.log" -journal "%~dp0udp_sim.jou"
pause
