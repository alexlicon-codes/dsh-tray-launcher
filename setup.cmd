@echo off
rem One-click setup wizard for the dsh-tray-launcher.
rem Asks for the Harness path first, then writes settings.json.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup.ps1"
