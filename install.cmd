@echo off
rem termx installer for Windows (cmd or PowerShell):  .\install
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\windows\termx.ps1" install %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\windows\termx.ps1" install %*)
