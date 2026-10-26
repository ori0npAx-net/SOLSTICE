@echo off
echo Starting Solar Tracker. First launch may download Java and MariaDB.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch.ps1"
if errorlevel 1 (
  echo.
  echo Startup failed. Read the error above. Keep this folder inside the complete repository.
  pause
)
