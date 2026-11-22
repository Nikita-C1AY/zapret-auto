@echo off
rem Zapret Auto v9.5.2 - starts the tray launcher (it asks for Administrator rights once)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0zapret-auto-tray.ps1"
