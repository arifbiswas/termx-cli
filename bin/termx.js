#!/usr/bin/env node
// termx: npm entry point. Same command on every OS; picks the right engine:
//   Windows       -> src/windows/termx.ps1  (Oh My Posh)
//   macOS / Linux -> src/unix/termx         (Oh My Zsh)
//
// Recommended:  npm i -g termx-cli && termx install
// `npx termx-cli install` also installs the latest termx-cli globally and
// hands off to it, so even an old cached npx copy runs the newest code.
// Skip that with --no-global (or TERMX_NO_GLOBAL=1).
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..');
const pkg = require(path.join(root, 'package.json'));
const isWin = process.platform === 'win32';

// Running from npx's temporary cache (npx / npm exec), not a real install?
function isNpx(dir) {
  return dir.split(/[\\/]/).includes('_npx');
}

function shouldInstallGlobal(dir, args, env) {
  if (args[0] !== 'install' && args[0] !== 'setup') return false;
  if (env.TERMX_HANDOFF === '1') return false;
  if (args.includes('--no-global') || env.TERMX_NO_GLOBAL === '1') return false;
  return isNpx(dir);
}

function npm(args, opts = {}) {
  // npm is npm.cmd on Windows, which needs a shell to run
  return spawnSync('npm', args, { shell: isWin, encoding: 'utf8', ...opts });
}

// npx (especially an old cached npx copy) -> install the LATEST termx-cli
// globally, then hand off to it so the newest code does the setup.
function installGlobal() {
  const spec = `${pkg.name}@latest`;
  console.log(`\x1b[34m\x1b[1m==>\x1b[0m Installing ${spec} globally (npm i -g) so the \`termx\` command is always available…`);
  const r = npm(['install', '-g', spec, '--no-fund', '--no-audit', '--loglevel=error'], { stdio: 'inherit' });
  if (r.status === 0) {
    console.log(` \x1b[32m✓\x1b[0m termx installed globally`);
    return true;
  }
  // e.g. EACCES with a system Node on mac/Linux: setup still works,
  // because termx also installs itself to ~/.termx/bin and adds it to PATH.
  console.log(` \x1b[33m!\x1b[0m Global npm install failed, continuing with this copy (termx also installs itself to ~/.termx/bin)`);
  return false;
}

// Run the globally installed `termx`, skipping npx's own .bin folders on PATH
// (otherwise `termx` would resolve back to this npx copy). null = not found.
function runGlobal(args) {
  const key = Object.keys(process.env).find((k) => k.toUpperCase() === 'PATH') || 'PATH';
  const clean = (process.env[key] || '').split(path.delimiter)
    .filter((p) => !p.split(/[\\/]/).includes('_npx')).join(path.delimiter);
  const env = { ...process.env, [key]: clean, TERMX_HANDOFF: '1' };
  const r = spawnSync('termx', args, { stdio: 'inherit', env, shell: isWin });
  if (r.error || r.status === 127 || (isWin && r.status === 9009)) return null;
  return r.status === null ? 1 : r.status;
}

function run(cmd, cmdArgs) {
  const r = spawnSync(cmd, cmdArgs, { stdio: 'inherit' });
  if (r.error) return null;
  return r.status === null ? 1 : r.status;
}

function main() {
  const argv = process.argv.slice(2);
  const args = argv.filter((a) => a !== '--no-global');
  if (shouldInstallGlobal(__dirname, argv, process.env) && installGlobal()) {
    const code = runGlobal(args);
    if (code !== null) process.exit(code);
  }

  let code;
  if (isWin) {
    const script = path.join(root, 'src', 'windows', 'termx.ps1');
    const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args];
    code = run('pwsh', psArgs);
    if (code === null) code = run('powershell.exe', psArgs);
    if (code === null) { console.error('termx: PowerShell not found.'); code = 1; }
  } else {
    code = run('bash', [path.join(root, 'src', 'unix', 'termx'), ...args]);
    if (code === null) { console.error('termx: bash not found.'); code = 1; }
  }
  process.exit(code);
}

if (require.main === module) main();
module.exports = { isNpx, shouldInstallGlobal, installGlobal, runGlobal };
