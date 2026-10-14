@echo off
setlocal
echo === dsh-tray-launcher: uninstall autostart ===
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0autostart.ps1" uninstall
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo [FAILED] exit code %RC% -- see autostart.log in this folder
echo Press any key to close this window...
pause >nul
endlocal
