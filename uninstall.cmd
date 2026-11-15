@echo off
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\windows\termx.ps1" uninstall %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\windows\termx.ps1" uninstall %*)
