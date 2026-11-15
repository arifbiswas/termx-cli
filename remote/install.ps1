# One-liner (Windows PowerShell or PowerShell 7):
#   irm https://raw.githubusercontent.com/arifbiswas/termx-cli/main/remote/install.ps1 | iex
$repo   = if ($env:TERMX_REPO)   { $env:TERMX_REPO }   else { 'arifbiswas/termx-cli' }
$branch = if ($env:TERMX_BRANCH) { $env:TERMX_BRANCH } else { 'main' }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$tmp = Join-Path $env:TEMP "termx-$PID.ps1"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$repo/$branch/src/windows/termx.ps1" -OutFile $tmp
Set-ExecutionPolicy -Scope Process Bypass -Force
& $tmp install
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
