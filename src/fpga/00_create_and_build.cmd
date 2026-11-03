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
 echo [ERROR] Vivado 2024.1 was not found.
 echo Start Vivado 2024.1, then run this Tcl command:
 echo source {C:/FPGA/V4/scripts/build_all.tcl}
 echo Replace C:/FPGA/V4 with the actual ZIP extraction folder.
 pause
 exit /b 1
)
echo =======================================================
echo  FPGA UDP-only four-function standalone: build from ZERO
 echo SERVO + FFT + FPGA PID + ETHERNET UDP
 echo Original project is NOT used or modified.
echo =======================================================
call "%VIVADO_BAT%" -mode batch -source "%~dp0scripts\build_all.tcl" -log "%~dp0all_in_one_build.log" -journal "%~dp0all_in_one_build.jou"
if errorlevel 1 (
 echo BUILD FAILED: see all_in_one_build.log and project\contest_all.runs
 pause
 exit /b 1
)
echo BUILD COMPLETED. Open project\contest_all.xpr in Vivado GUI.
pause
