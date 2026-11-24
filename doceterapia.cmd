@echo off
setlocal
rem No arguments means a double click: open the window without a console.
if "%~1"=="" (
    start "" wscript.exe "%~dp0doceterapia.vbs"
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\doceterapia.ps1" %*
exit /b %ERRORLEVEL%
