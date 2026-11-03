@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0scripts\inspect_timing.py" "%~dp0results\final_timing_summary.txt"
) else (
  where python >nul 2>nul
  if not errorlevel 1 (
    python "%~dp0scripts\inspect_timing.py" "%~dp0results\final_timing_summary.txt"
  ) else (
    echo Python unavailable. Open results\final_timing_summary.txt and check WNS/TNS/WHS/THS.
  )
)
pause
