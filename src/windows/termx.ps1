<#
=============================================================================
 termx: one-command terminal setup for Windows
 Oh My Posh + PSReadLine predictions (auto-suggestions) + Terminal-Icons
 + Nerd Font + Windows Terminal font + theme picker

 Same commands as the macOS/Linux version:
   termx install            install + configure everything (idempotent)
   termx theme              interactive theme picker (live preview)
   termx theme list         list all themes
   termx theme gallery      render every theme's prompt in the terminal
   termx theme set <name>   apply a theme
   termx theme try <name>   preview a theme in this session only
   termx theme random | current
   termx env list | set K V | unset K | path DIR
   termx update | doctor
   termx uninstall [--all] [--yes]

 Works in Windows PowerShell 5.1 and PowerShell 7+.
=============================================================================
#>
$Argv = [string[]]@($args)

$ErrorActionPreference = 'Continue'   # 'Stop' breaks native-command stderr on PowerShell 5.1
$ProgressPreference    = 'SilentlyContinue'
$TermxVersion  = '1.0.1'
$TermxHome     = if ($env:TERMX_HOME) { $env:TERMX_HOME } else { Join-Path $HOME '.termx' }
$TermxBin      = Join-Path $TermxHome 'bin'
$ThemesDir     = Join-Path $TermxHome 'themes'
$ThemeFile     = Join-Path $TermxHome 'theme'
$EnvFile       = Join-Path $TermxHome 'env.ps1'
$BackupDir     = Join-Path $TermxHome 'backups'
$TermxProfile  = Join-Path $TermxHome 'profile.ps1'
$DefaultTheme  = if ($env:TERMX_DEFAULT_THEME) { $env:TERMX_DEFAULT_THEME } else { 'paradox' }
$FontFace      = 'MesloLGM Nerd Font'
$ThemesZipUrl  = 'https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip'
$ProfileMarker = '# termx: load terminal customizer'
$ProfileLine   = "if (Test-Path `"`$HOME\.termx\profile.ps1`") { . `"`$HOME\.termx\profile.ps1`" }  $ProfileMarker"
$script:AssumeYes = $false

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ------------------------------------------------------------------- ui ------
function Info($m) { Write-Host '==> ' -ForegroundColor Blue -NoNewline; Write-Host $m }
function Ok($m)   { Write-Host ' [ok] ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn($m) { Write-Host ' [!] ' -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Err($m)  { Write-Host ' [x] ' -ForegroundColor Red -NoNewline; Write-Host $m }
function Die($m)  { Err $m; exit 1 }
function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Ask($q, $def) {
    if ($script:AssumeYes) { return $def }
    $a = Read-Host "? $q"
    if ([string]::IsNullOrWhiteSpace($a)) { return $def } else { return $a.Trim() }
}
function Confirm-Step($q) { return -not ((Ask "$q [Y/n]" 'y') -match '^[nN]') }

function Show-Banner {
    Write-Host @'
  _
 | |_ ___ _ __ _ __ ___ __  __
 | __/ _ \ '__| '_ ` _ \\ \/ /
 | ||  __/ |  | | | | | |>  <
  \__\___|_|  |_| |_| |_/_/\_\
'@ -ForegroundColor Cyan
    Write-Host "  terminal customizer v$TermxVersion, Windows, PowerShell $($PSVersionTable.PSVersion)`n" -ForegroundColor DarkGray
}

function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($m, $u) | Where-Object { $_ }) -join ';'
    foreach ($p in @("$env:LOCALAPPDATA\Programs\oh-my-posh\bin", $TermxBin)) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
    }
}

function Get-DocumentsDir { [Environment]::GetFolderPath('MyDocuments') }
function Get-ProfilePaths {
    $docs = Get-DocumentsDir
    @(
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),  # Windows PowerShell 5.1
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')          # PowerShell 7+
    )
}

function Invoke-Winget([string[]]$wingetArgs) {
    if (-not (Has winget)) { return $false }
    & winget @wingetArgs --accept-source-agreements --accept-package-agreements --disable-interactivity *> $null
    # 0 = ok, -1978335189 = already installed / no upgrade available
    return ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189 -or $LASTEXITCODE -eq -1978335135)
}

# ----------------------------------------------------------- install steps ---
function Set-ExecPolicy {
    $p = Get-ExecutionPolicy -Scope CurrentUser
    if ($p -in @('Undefined', 'Restricted', 'AllSigned')) {
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            Ok 'Execution policy (CurrentUser) -> RemoteSigned, so your profile can load'
        } catch { Warn "Could not set execution policy: $($_.Exception.Message)" }
    }
}

function Install-OhMyPosh {
    Refresh-Path
    if (Has oh-my-posh) { Ok "Oh My Posh already installed ($(oh-my-posh version))"; return }
    Info 'Installing Oh My Posh...'
    $done = Invoke-Winget @('install', '--id', 'JanDeDobbeleer.OhMyPosh', '-e', '-s', 'winget', '--scope', 'user')
    Refresh-Path
    if (-not (Has oh-my-posh)) {
        Info 'winget not available or failed, using the official installer...'
        try { Invoke-Expression (Invoke-RestMethod 'https://ohmyposh.dev/install.ps1') } catch { Warn $_.Exception.Message }
        Refresh-Path
    }
    if (-not (Has oh-my-posh)) { Die 'Oh My Posh install failed. Install it from https://ohmyposh.dev and re-run: termx install' }
    New-Item -ItemType File -Force (Join-Path $TermxHome '.installed-omp') | Out-Null
    Ok 'Oh My Posh installed'
}

function Install-Fzf {
    Refresh-Path
    if (Has fzf) { return }
    Info 'Installing fzf (for the interactive theme picker)...'
    if (Invoke-Winget @('install', '--id', 'junegunn.fzf', '-e', '-s', 'winget')) { Refresh-Path }
    if (Has fzf) { Ok 'fzf installed' } else { Warn 'fzf not installed, theme picker will use a numbered list instead' }
}

function Install-NerdFont {
    Info "Installing Nerd Font ($FontFace) for icons..."
    $userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if ((Test-Path "$userFonts\MesloLGM*Nerd*") -or (Test-Path "$env:WINDIR\Fonts\MesloLGM*Nerd*")) { Ok 'Font already installed'; return }
    & oh-my-posh font install meslo --user *> $null
    if ($LASTEXITCODE -ne 0) { & oh-my-posh font install meslo *> $null }
    if ($LASTEXITCODE -eq 0) { Ok 'Font installed' } else { Warn 'Font install failed. Run later: oh-my-posh font install meslo' }
}

function Install-Modules {
    Info 'Installing PowerShell modules (PSReadLine, Terminal-Icons)...'
    try {
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop }
    } catch { Warn "PowerShell Gallery setup: $($_.Exception.Message)" }

    $psrl = Get-Module -ListAvailable PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $psrl -or $psrl.Version -lt [version]'2.2.6') {
        try { Install-Module PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop; Ok 'PSReadLine updated (auto-suggestions)' }
        catch { Warn "PSReadLine update failed: $($_.Exception.Message)" }
    } else { Ok "PSReadLine $($psrl.Version) (auto-suggestions)" }

    foreach ($m in @('Terminal-Icons')) {
        if (Get-Module -ListAvailable $m) { Ok "$m present"; continue }
        try { Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop; Ok "$m installed" } catch { Warn "$m failed: $($_.Exception.Message)" }
    }
    # Extra modules for PowerShell 7 (separate module folder), when pwsh exists
    if (Has pwsh) {
        & pwsh -NoProfile -Command @'
$ErrorActionPreference='SilentlyContinue'
Set-PSRepository PSGallery -InstallationPolicy Trusted
foreach ($m in 'Terminal-Icons','CompletionPredictor') { if (-not (Get-Module -ListAvailable $m)) { Install-Module $m -Scope CurrentUser -Force -AllowClobber } }
'@ *> $null
        Ok 'PowerShell 7 modules (Terminal-Icons, CompletionPredictor) ready'
    }
}

function Install-Themes {
    Info 'Downloading Oh My Posh themes...'
    New-Item -ItemType Directory -Force $ThemesDir | Out-Null
    $zip = Join-Path $env:TEMP "termx-themes-$PID.zip"
    try {
        Invoke-WebRequest -Uri $ThemesZipUrl -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zip -DestinationPath $ThemesDir -Force -ErrorAction Stop
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Ok "$(@(Get-Themes).Count) themes ready"
    } catch {
        if ($env:POSH_THEMES_PATH -and (Test-Path $env:POSH_THEMES_PATH)) {
            Copy-Item "$env:POSH_THEMES_PATH\*" $ThemesDir -Force -Recurse
            Ok 'Themes copied from Oh My Posh install'
        } else { Warn "Theme download failed: $($_.Exception.Message)" }
    }
}

function Write-TermxProfile {
    New-Item -ItemType Directory -Force $TermxHome | Out-Null
    if (-not (Test-Path $ThemeFile)) { Set-Content -Path $ThemeFile -Value $DefaultTheme -Encoding ASCII }
    if (-not (Test-Path $EnvFile)) { Set-Content -Path $EnvFile -Value '# termx env: add with `termx env set KEY VALUE`' -Encoding UTF8 }
    $content = @'
# ============================================================================
#  termx profile: generated, do not edit (re-generated by `termx install`)
#  Your own additions go in your normal $PROFILE or ~/.termx/env.ps1
# ============================================================================
$env:TERMX_HOME = Join-Path $HOME '.termx'
foreach ($__p in @("$env:LOCALAPPDATA\Programs\oh-my-posh\bin", "$env:TERMX_HOME\bin")) {
    if ((Test-Path $__p) -and ($env:Path -notlike "*$__p*")) { $env:Path = "$__p;$env:Path" }
}

function global:__termx_theme_config([string]$name) {
    if (-not $name) {
        $name = if ($env:TERMX_THEME_OVERRIDE) { $env:TERMX_THEME_OVERRIDE }
                elseif (Test-Path "$env:TERMX_HOME\theme") { (Get-Content "$env:TERMX_HOME\theme" -Raw).Trim() }
                else { 'paradox' }
    }
    Get-ChildItem "$env:TERMX_HOME\themes\$name.omp.*" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
function global:__termx_load_prompt([string]$name) {
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) { return }
    $cfg = __termx_theme_config $name
    if ($cfg) { oh-my-posh init pwsh --config $cfg | Invoke-Expression } else { oh-my-posh init pwsh | Invoke-Expression }
}
__termx_load_prompt

# ---- auto-suggestions (PSReadLine predictions) ----
if ($Host.Name -eq 'ConsoleHost') {
    try {
        Import-Module PSReadLine -MinimumVersion 2.2.0 -ErrorAction Stop
        $__src = 'History'
        if ($PSVersionTable.PSVersion.Major -ge 7 -and (Get-Module -ListAvailable CompletionPredictor)) {
            Import-Module CompletionPredictor -ErrorAction SilentlyContinue; $__src = 'HistoryAndPlugin'
        }
        Set-PSReadLineOption -PredictionSource $__src -PredictionViewStyle ListView -HistoryNoDuplicates -BellStyle None
        Set-PSReadLineOption -Colors @{ InlinePrediction = "`e[38;5;244m" } -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Spacebar' -Function AcceptSuggestion
        Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function AcceptNextSuggestionWord
        Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView
    } catch {}
}
Import-Module Terminal-Icons -ErrorAction SilentlyContinue

# ---- your environment (termx env set KEY VALUE) ----
if (Test-Path "$env:TERMX_HOME\env.ps1") { . "$env:TERMX_HOME\env.ps1" }

# ---- termx command: reloads the prompt after theme changes ----
function global:termx {
    $__script = "$env:TERMX_HOME\bin\termx.ps1"
    if ($args.Count -ge 2 -and $args[0] -eq 'theme' -and $args[1] -eq 'try') {
        $cfg = __termx_theme_config $args[2]
        if (-not $cfg) { Write-Host "Theme '$($args[2])' not found. See: termx theme list" -ForegroundColor Red; return }
        __termx_load_prompt $args[2]
        Write-Host "Trying '$($args[2])' in this window only. Run 'termx theme set $($args[2])' to keep it." -ForegroundColor Cyan
        return
    }
    & $__script @args
    if (Test-Path "$env:TERMX_HOME\.reload") {
        Remove-Item "$env:TERMX_HOME\.reload" -Force
        __termx_load_prompt
        if (Test-Path "$env:TERMX_HOME\env.ps1") { . "$env:TERMX_HOME\env.ps1" }
    }
}
'@
    # PowerShell 5.1 has no `e escape, use [char]27 there
    $content = $content.Replace('"`e[38;5;244m"', '"$([char]27)[38;5;244m"')
    Set-Content -Path $TermxProfile -Value $content -Encoding UTF8
    Ok 'termx profile written -> ~\.termx\profile.ps1'
}

function Add-ProfileHooks {
    Info 'Hooking into PowerShell profiles (5.1 and 7)...'
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($p in Get-ProfilePaths) {
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        $leaf = (Split-Path (Split-Path $p) -Leaf)
        if (Test-Path $p) {
            Copy-Item $p (Join-Path $BackupDir "$leaf.profile.$stamp.ps1")
            $lines = @(Get-Content $p)
            if ($lines -match [regex]::Escape($ProfileMarker)) { Ok "$leaf profile already hooked"; continue }
            # Old Oh My Posh init lines would fight with ours, comment them out
            $lines = $lines | ForEach-Object { if ($_ -match '^\s*oh-my-posh\s+init' -and $_ -notmatch 'termx') { "# (disabled by termx) $_" } else { $_ } }
            Set-Content -Path $p -Value (@($lines) + '' + $ProfileLine) -Encoding UTF8
        } else {
            New-Item -ItemType File -Force (Join-Path $BackupDir "$leaf.profile.none") | Out-Null
            Set-Content -Path $p -Value $ProfileLine -Encoding UTF8
        }
        Ok "$leaf profile -> $p"
    }
}

function Install-Self {
    New-Item -ItemType Directory -Force $TermxBin | Out-Null
    $src = $PSCommandPath
    $dst = Join-Path $TermxBin 'termx.ps1'
    if ($src -and (Test-Path $src)) {
        if ((Resolve-Path $src).Path -ne $dst) { Copy-Item $src $dst -Force }
    } elseif ($env:TERMX_SCRIPT_URL) {
        Invoke-WebRequest -Uri $env:TERMX_SCRIPT_URL -OutFile $dst -UseBasicParsing
    }
    # cmd.exe / Run dialog shim
    Set-Content -Path (Join-Path $TermxBin 'termx.cmd') -Encoding ASCII -Value @'
@echo off
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0termx.ps1" %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0termx.ps1" %*)
'@
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (($userPath -split ';') -notcontains $TermxBin) {
        [Environment]::SetEnvironmentVariable('Path', (@($userPath.TrimEnd(';'), $TermxBin) | Where-Object { $_ }) -join ';', 'User')
    }
    Refresh-Path
    Ok 'termx command installed -> ~\.termx\bin (added to your PATH)'
}

function Get-WTSettingsPaths {
    @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    ) | Where-Object { Test-Path $_ }
}

function Read-JsonLoose($path) {
    $raw = Get-Content $path -Raw -ErrorAction Stop
    # strip // comments (outside strings, best effort) and trailing commas for PowerShell 5.1
    $raw = [regex]::Replace($raw, '(?m)^\s*//.*$', '')
    $raw = [regex]::Replace($raw, ',(\s*[}\]])', '$1')
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Set-TerminalFont([string]$face) {
    $paths = @(Get-WTSettingsPaths)
    if ($paths.Count -eq 0) { Warn "Windows Terminal not found. Set your terminal font to '$FontFace' manually"; return }
    foreach ($p in $paths) {
        try {
            Copy-Item $p (Join-Path $BackupDir ("wt-settings.{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force
            $json = Read-JsonLoose $p
            if (-not $json) { throw 'could not parse settings.json' }
            if (-not $json.profiles) { $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) }
            if ($json.profiles -is [array]) { Warn 'Old Windows Terminal settings format, skipping font'; continue }
            if (-not $json.profiles.defaults) { $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force }
            $d = $json.profiles.defaults
            if ($face) {
                if (-not $d.font) { $d | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force }
                $d.font | Add-Member -NotePropertyName face -NotePropertyValue $face -Force
            } elseif ($d.font -and $d.font.face -eq $FontFace) {
                $d.font.PSObject.Properties.Remove('face')
            }
            $json | ConvertTo-Json -Depth 64 | Set-Content -Path $p -Encoding UTF8
            if ($face) { Ok "Windows Terminal font -> $face" } else { Ok 'Windows Terminal font reset' }
        } catch { Warn "Could not update $p : $($_.Exception.Message)" }
    }
}

# ------------------------------------------------------------------ themes ---
function Get-Themes {
    if (-not (Test-Path $ThemesDir)) { return @() }
    Get-ChildItem $ThemesDir -File | Where-Object { $_.Name -match '\.omp\.(json|ya?ml|toml)$' } |
        ForEach-Object { $_.Name -replace '\.omp\.(json|ya?ml|toml)$', '' } | Sort-Object -Unique
}
function Get-ThemePath($name) { Get-ChildItem (Join-Path $ThemesDir "$name.omp.*") -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
function Get-CurrentTheme { if (Test-Path $ThemeFile) { (Get-Content $ThemeFile -Raw).Trim() } else { $DefaultTheme } }

function Show-ThemePreview($name) {
    $cfg = Get-ThemePath $name
    if (-not $cfg) { return }
    $p = & oh-my-posh print primary --config $cfg --shell pwsh 2>$null
    if ($p) { Write-Host (($p -join '') + 'git status') }
}

function Set-Theme($name) {
    if (-not $name) { Die 'Usage: termx theme set <name>   (see: termx theme list)' }
    if (-not (Get-ThemePath $name)) { Die "Theme '$name' not found. See: termx theme list" }
    Set-Content -Path $ThemeFile -Value $name -Encoding ASCII
    New-Item -ItemType File -Force (Join-Path $TermxHome '.reload') | Out-Null
    Ok "Theme set to $name (applied to this window and all new ones)"
}

function Show-Gallery {
    $cur = Get-CurrentTheme; $i = 1
    foreach ($t in Get-Themes) {
        if ($t -eq $cur) { Write-Host ("{0,3}) {1}  (current)" -f $i, $t) -ForegroundColor Green }
        else { Write-Host ("{0,3}) {1}" -f $i, $t) -ForegroundColor White }
        Write-Host '     ' -NoNewline; Show-ThemePreview $t; Write-Host ''
        $i++
    }
}

function Select-Theme {
    $themes = @(Get-Themes)
    if ($themes.Count -eq 0) { Die 'No themes found. Run: termx install' }
    $cur = Get-CurrentTheme
    Refresh-Path
    $choice = $null
    if (Has fzf) {
        $preview = "oh-my-posh print primary --config `"$ThemesDir\{}.omp.json`" --shell pwsh"
        $choice = $themes | & fzf --height=85% --reverse --border=rounded --cycle --ansi `
            --prompt='  theme > ' --header="Up/Down move | type to search | Enter apply | Esc cancel   (current: $cur)" `
            --preview=$preview --preview-window=down,4,wrap
    } else {
        Show-Gallery
        $ans = Ask "Theme number or name (current: $cur):" ''
        if ($ans -match '^\d+$') { $idx = [int]$ans - 1; if ($idx -ge 0 -and $idx -lt $themes.Count) { $choice = $themes[$idx] } }
        else { $choice = $ans }
    }
    if ($choice) { Set-Theme $choice }
}

function Invoke-Theme([string[]]$a) {
    if (-not (Test-Path $ThemesDir)) { Die 'Not installed yet. Run: termx install' }
    $sub = if ($a.Count -gt 0) { $a[0] } else { 'pick' }
    $arg = if ($a.Count -gt 1) { $a[1] } else { $null }
    switch ($sub) {
        { $_ -in 'pick', '' }            { Select-Theme }
        { $_ -in 'list', 'ls' }          { $cur = Get-CurrentTheme
                                           Get-Themes | ForEach-Object { if ($_ -eq $cur) { Write-Host "* $_" -ForegroundColor Green } else { Write-Host "  $_" } }
                                           Write-Host "`n$(@(Get-Themes).Count) themes | preview all: termx theme gallery" }
        { $_ -in 'gallery', 'show' }     { Show-Gallery; Write-Host 'Apply one with: termx theme set <name>   or pick interactively: termx theme' }
        { $_ -in 'set', 'use', 'apply' } { Set-Theme $arg }
        'try'                            { Write-Host "Run this inside your terminal (after install): termx theme try $arg" }
        'random'                         { Set-Theme (Get-Themes | Get-Random) }
        'current'                        { Get-CurrentTheme }
        'render'                         { Show-ThemePreview $(if ($arg) { $arg } else { Get-CurrentTheme }) }
        default                          { Set-Theme $sub }
    }
}

# --------------------------------------------------------------------- env ---
function Invoke-Env([string[]]$a) {
    $sub = if ($a.Count -gt 0) { $a[0] } else { 'list' }
    switch ($sub) {
        'set' {
            if ($a.Count -lt 3) { Die 'Usage: termx env set KEY VALUE' }
            if ($a[1] -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { Die "Invalid variable name: $($a[1])" }
            [Environment]::SetEnvironmentVariable($a[1], $a[2], 'User')
            Set-Item -Path "env:$($a[1])" -Value $a[2]
            Ok "$($a[1]) saved as a User environment variable (all apps, all new terminals)"
        }
        'unset' {
            if ($a.Count -lt 2) { Die 'Usage: termx env unset KEY' }
            [Environment]::SetEnvironmentVariable($a[1], $null, 'User')
            Remove-Item -Path "env:$($a[1])" -ErrorAction SilentlyContinue
            Ok "$($a[1]) removed"
        }
        'path' {
            if ($a.Count -lt 2) { Die 'Usage: termx env path <dir>' }
            $dir = (Resolve-Path $a[1] -ErrorAction SilentlyContinue).Path; if (-not $dir) { $dir = $a[1] }
            $u = [Environment]::GetEnvironmentVariable('Path', 'User'); if (-not $u) { $u = '' }
            if (($u -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', (@($u.TrimEnd(';'), $dir) | Where-Object { $_ }) -join ';', 'User') }
            Refresh-Path; Ok "$dir added to your PATH"
        }
        'list' {
            $vars = [Environment]::GetEnvironmentVariables('User')
            $vars.Keys | Sort-Object | ForEach-Object { '{0}={1}' -f $_, $vars[$_] }
        }
        'edit' { notepad $EnvFile }
        default { Die 'Usage: termx env [list|set KEY VALUE|unset KEY|path DIR|edit]' }
    }
}

# ---------------------------------------------------------------- commands ---
function Invoke-Install([string[]]$a) {
    $theme = $null
    for ($i = 0; $i -lt $a.Count; $i++) {
        switch -Regex ($a[$i]) {
            '^(-y|--yes)$'   { $script:AssumeYes = $true }
            '^--theme$'      { $theme = $a[$i + 1]; $i++ }
            '^--theme=(.+)$' { $theme = $Matches[1] }
        }
    }
    Show-Banner
    New-Item -ItemType Directory -Force $TermxHome, $BackupDir | Out-Null
    Set-ExecPolicy
    Install-OhMyPosh
    Install-Fzf
    Install-NerdFont
    Install-Modules
    Install-Themes
    if ($theme) { Set-Content -Path $ThemeFile -Value $theme -Encoding ASCII }
    Write-TermxProfile
    Add-ProfileHooks
    Install-Self
    Set-TerminalFont $FontFace

    Write-Host "`n All done!`n" -ForegroundColor Green
    Write-Host '  termx theme            pick a theme (live preview)'
    Write-Host '  termx theme gallery    see every theme in your terminal'
    Write-Host '  termx env set K V      add an environment variable'
    Write-Host '  termx uninstall        remove everything'
    Write-Host "`n  Suggestions: type, then pick from the list with Up/Down, or Right Arrow / Ctrl+Space to accept."
    Write-Host '  F2 switches between list view and inline suggestions.'
    Write-Host "`n  Restart your terminal (close and reopen Windows Terminal) to see the new look." -ForegroundColor Cyan
}

function Invoke-Update {
    Info 'Updating Oh My Posh...'
    if (Invoke-Winget @('upgrade', '--id', 'JanDeDobbeleer.OhMyPosh', '-e', '-s', 'winget')) { Ok 'Oh My Posh up to date' }
    else { & oh-my-posh upgrade *> $null }
    try { Update-Module PSReadLine, Terminal-Icons -Force -ErrorAction SilentlyContinue } catch {}
    Install-Themes
    Write-TermxProfile
    New-Item -ItemType File -Force (Join-Path $TermxHome '.reload') | Out-Null
    Ok 'Up to date'
}

function Invoke-Doctor {
    Refresh-Path
    function Row($label, $good) { if ($good) { Ok $label } else { Err $label } }
    Write-Host "termx $TermxVersion on Windows, PowerShell $($PSVersionTable.PSVersion)`n"
    Row "oh-my-posh     $(if (Has oh-my-posh) { oh-my-posh version })" (Has oh-my-posh)
    $psrl = Get-Module -ListAvailable PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
    Row "PSReadLine     $($psrl.Version) (needs 2.2+ for suggestions)" ($psrl -and $psrl.Version -ge [version]'2.2.0')
    Row 'Terminal-Icons' ([bool](Get-Module -ListAvailable Terminal-Icons))
    Row 'fzf            (theme picker preview)' (Has fzf)
    Row "themes         $(@(Get-Themes).Count) in $ThemesDir" (@(Get-Themes).Count -gt 0)
    foreach ($p in Get-ProfilePaths) { Row "profile hook   $p" ((Test-Path $p) -and ((Get-Content $p -Raw) -match [regex]::Escape($ProfileMarker))) }
    Row "termx on PATH  $TermxBin" (([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') -contains $TermxBin)
    Write-Host "`ntheme: $(Get-CurrentTheme)"
}

function Invoke-Uninstall([string[]]$a) {
    $mode = $null
    foreach ($x in $a) {
        switch -Regex ($x) {
            '^--(all|full)$'              { $mode = 'all' }
            '^--(termx-only|keep-omp)$'   { $mode = 'termx' }
            '^(-y|--yes)$'                { $script:AssumeYes = $true }
        }
    }
    if (-not $mode) {
        Write-Host 'What do you want to remove?'
        Write-Host '  1) termx only        (keep Oh My Posh installed, remove termx config)'
        Write-Host '  2) everything        (termx + Oh My Posh + modules, reset terminal font)'
        Write-Host '  3) cancel'
        switch (Ask 'Choose [1-3]:' '3') { '1' { $mode = 'termx' } '2' { $mode = 'all' } default { Write-Host 'Cancelled.'; return } }
    }
    if (-not $script:AssumeYes -and -not (Confirm-Step "Proceed with '$mode' uninstall?")) { Write-Host 'Cancelled.'; return }

    foreach ($p in Get-ProfilePaths) {
        if (-not (Test-Path $p)) { continue }
        $leaf = Split-Path (Split-Path $p) -Leaf
        $lines = @(Get-Content $p) | Where-Object { $_ -notmatch [regex]::Escape($ProfileMarker) } |
                 ForEach-Object { $_ -replace '^# \(disabled by termx\) ', '' }
        if ((Test-Path (Join-Path $BackupDir "$leaf.profile.none")) -and -not (@($lines) -match '\S')) { Remove-Item $p -Force }
        else { Set-Content -Path $p -Value $lines -Encoding UTF8 }
        Ok "termx removed from $leaf profile"
    }
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($u) { [Environment]::SetEnvironmentVariable('Path', (($u -split ';') | Where-Object { $_ -and $_ -ne $TermxBin }) -join ';', 'User') }
    Ok 'termx removed from PATH'

    if ($mode -eq 'all') {
        Set-TerminalFont $null
        if (Invoke-Winget @('uninstall', '--id', 'JanDeDobbeleer.OhMyPosh', '-e')) { Ok 'Oh My Posh uninstalled' }
        else { Warn 'Could not uninstall Oh My Posh with winget (remove it from Settings > Apps)' }
        foreach ($m in @('Terminal-Icons', 'CompletionPredictor')) {
            try { Uninstall-Module $m -AllVersions -Force -ErrorAction Stop; Ok "$m removed" } catch {}
        }
        Write-Host '  PSReadLine and the Nerd Font were kept (they are harmless and used by other tools).' -ForegroundColor DarkGray
    }
    if (Test-Path $BackupDir) {
        $keep = Join-Path $HOME '.termx-backups'
        New-Item -ItemType Directory -Force $keep | Out-Null
        Copy-Item "$BackupDir\*" $keep -Force -Recurse -ErrorAction SilentlyContinue
    }
    Remove-Item $TermxHome -Recurse -Force -ErrorAction SilentlyContinue
    Ok 'termx removed (backups kept in ~\.termx-backups). Restart your terminal to finish.'
}

function Show-Help {
    Write-Host "termx $TermxVersion`: same commands on Windows, macOS and Linux`n" -ForegroundColor Cyan
    @'
  termx install [--theme NAME] [--yes]   install + auto-configure everything
  termx theme                            interactive picker with live preview
  termx theme list | gallery             list names | render every theme
  termx theme set|try NAME               apply | test in this window only
  termx theme random | current
  termx env list|set K V|unset K|path DIR|edit
  termx update | doctor
  termx uninstall [--all|--termx-only] [--yes]
'@ | Write-Host
}

# -------------------------------------------------------------------- main ---
if (-not $Argv) { $Argv = @() }
$cmd  = if ($Argv.Count -gt 0) { $Argv[0] } else { 'help' }
$rest = if ($Argv.Count -gt 1) { [string[]]$Argv[1..($Argv.Count - 1)] } else { [string[]]@() }
switch ($cmd) {
    { $_ -in 'install', 'setup' }        { Invoke-Install $rest }
    { $_ -in 'theme', 'themes' }         { Invoke-Theme $rest }
    'env'                                { Invoke-Env $rest }
    { $_ -in 'update', 'upgrade' }       { Invoke-Update }
    { $_ -in 'doctor', 'status' }        { Invoke-Doctor }
    { $_ -in 'uninstall', 'remove' }     { Invoke-Uninstall $rest }
    { $_ -in 'version', '-v', '--version' } { "termx $TermxVersion" }
    { $_ -in 'help', '-h', '--help' }    { Show-Help }
    default                              { Err "Unknown command: $cmd"; Show-Help; exit 1 }
}
