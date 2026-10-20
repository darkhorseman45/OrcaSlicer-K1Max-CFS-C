@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Setup.ps1"
if errorlevel 1 (
    echo.
    echo Setup ended with an error. Read the displayed message and INSTALLATION.md.
    pause
)
endlocal