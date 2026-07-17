@echo off
setlocal
cd /d "%~dp0"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: PowerShell 7 was not found.
    echo Install PowerShell 7.4 or later.
    echo.
    pause
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-SharePointReadAccess.ps1"

echo.
pause
