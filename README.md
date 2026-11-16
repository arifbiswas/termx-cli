# termx: one-command terminal customizer

[![npm version](https://img.shields.io/npm/v/termx-cli?logo=npm&color=cb3837)](https://www.npmjs.com/package/termx-cli)
[![npm downloads](https://img.shields.io/npm/dm/termx-cli?logo=npm)](https://www.npmjs.com/package/termx-cli)
[![CI](https://github.com/arifbiswas/termx-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/arifbiswas/termx-cli/actions/workflows/ci.yml)
[![license](https://img.shields.io/npm/l/termx-cli)](LICENSE)

📦 **npm:** [npmjs.com/package/termx-cli](https://www.npmjs.com/package/termx-cli)

**Same command on every device.** termx detects the OS and installs the right setup:

| | macOS / Linux | Windows |
|---|---|---|
| Prompt engine | **Oh My Zsh** (+ Powerlevel10k, Spaceship, 140+ themes) | **Oh My Posh** (100+ themes) |
| Auto-suggestions | `zsh-autosuggestions` + `zsh-syntax-highlighting` + `zsh-completions` | PSReadLine predictions (ListView) + CompletionPredictor (PS 7) |
| Icons / font | MesloLGS Nerd Font, set in Terminal.app & iTerm2 | MesloLGM Nerd Font, set in Windows Terminal |
| Extras | fzf, `z` jump, Homebrew env, history tuning | Terminal-Icons, fzf, Tab menu-complete |

## Install

**With npm: the same two commands on macOS, Linux and Windows:**

```bash
npm i -g termx-cli
termx install
```

`npm i -g` installs the `termx` command **globally**, so it's always available. `termx install` then sets up everything.
As one line: `npm i -g termx-cli && termx install` (bash, zsh, cmd, PowerShell 7). In Windows PowerShell 5.1 use `;` instead of `&&`.

Update later with `npm i -g termx-cli@latest`.

<details><summary>Using npx instead</summary>

`npx termx-cli@latest install` also works: it installs the latest `termx-cli` globally first, then runs setup with it.
Always add `@latest`, because without it npx can reuse an old cached copy.
</details>

Without Node, from a clone of this repo: `./install` (mac/Linux) or `.\install` (Windows).

Or the no-Node one-liners:

```bash
curl -fsSL https://raw.githubusercontent.com/arifbiswas/termx-cli/main/remote/install.sh | bash
```
```powershell
irm https://raw.githubusercontent.com/arifbiswas/termx-cli/main/remote/install.ps1 | iex
```

Options: `--theme NAME` (start with a theme), `--yes` (no questions).

### What gets configured automatically (no manual steps)
- Package manager (Homebrew on mac / winget on Windows), git, zsh, fzf
- Oh My Zsh / Oh My Posh + plugins + themes + Nerd Font
- Terminal font (Terminal.app, iTerm2, Windows Terminal)
- Shell profile (`~/.zshrc` / PowerShell 5.1 **and** 7 profiles). Your existing PATH, aliases and env are kept and backed up first
- Default shell → zsh on mac
- **Windows execution policy is checked first.** If PowerShell can't run scripts, termx sets `RemoteSigned` for your user (both PowerShell 5.1 and 7) *before* installing anything. If that fails, for example because Group Policy locks it, setup stops with the exact fix, so nothing is half-installed. Downloaded script files are unblocked too.
- `termx` added to PATH. Powerlevel10k comes preconfigured, so no setup wizard pops up

Re-running install is safe (idempotent).

## Usage: identical on all platforms

```text
termx theme                 interactive picker: arrows + search + live preview, Enter applies
termx theme gallery         render EVERY theme's prompt in your terminal
termx theme list            list theme names (* = current)
termx theme set agnoster    apply a theme (shell reloads instantly)
termx theme try agnoster    test a theme without saving it
termx theme random          surprise me
termx env set KEY VALUE     add an env variable for all new shells
termx env path ~/bin        add a folder to PATH
termx env list | unset KEY
termx update                update engine, plugins, themes
termx doctor                check what's installed and configured
termx uninstall             menu: termx only / everything
termx uninstall --all --yes
```

**Suggestions:** type and the grey suggestion appears. Press **→** or **Ctrl+Space** to accept, **Ctrl+→** to accept one word.
On Windows the list view shows several suggestions; move with ↑/↓ and press **F2** to switch to inline.

## Uninstall
`termx uninstall` (or `./uninstall` / `.\uninstall`):
1. **termx only**: removes termx's config blocks and PATH entry, keeps Oh My Zsh / Oh My Posh
2. **everything**: also removes Oh My Zsh / Oh My Posh + modules, restores your original `~/.zshrc`, resets the terminal font

Backups are kept in `~/.termx-backups`. Fonts, fzf and Homebrew are left installed.

## Layout
```
install, install.cmd        same-name entry points (mac/linux · windows)
uninstall, uninstall.cmd
src/unix/termx              macOS/Linux CLI (bash 3.2 compatible)
src/windows/termx.ps1       Windows CLI (PowerShell 5.1 + 7)
remote/install.sh|.ps1      curl / irm one-liners
```
Files termx owns: `~/.termx/` (theme, env, backups, bin). In `~/.zshrc` only the blocks between `# >>> termx … >>>` markers.
