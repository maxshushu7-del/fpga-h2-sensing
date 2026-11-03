@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0project\contest_all.xpr" (
  echo Run 00_create_and_build.cmd or 01_create_project_only.cmd first.
  pause
  exit /b 1
)
if exist "C:\Xilinx\Vivado\2024.1\bin\vivado.bat" (
  call "C:\Xilinx\Vivado\2024.1\bin\vivado.bat" -mode gui "%~dp0project\contest_all.xpr"
) else (
  start "" "%~dp0project\contest_all.xpr"
)
