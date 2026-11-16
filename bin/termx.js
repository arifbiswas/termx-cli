#!/usr/bin/env node
// termx: npm entry point. Same command on every OS; picks the right engine:
//   Windows       -> src/windows/termx.ps1  (Oh My Posh)
//   macOS / Linux -> src/unix/termx         (Oh My Zsh)
//
// `npx termx-cli install` also installs termx-cli globally first, so the
// `termx` command keeps working after npx's temporary copy is gone.
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
  if (args.includes('--no-global') || env.TERMX_NO_GLOBAL === '1') return false;
  return isNpx(dir);
}

function npm(args, opts = {}) {
  // npm is npm.cmd on Windows, which needs a shell to run
  return spawnSync('npm', args, { shell: isWin, encoding: 'utf8', ...opts });
}

// Version of termx-cli installed globally, or null. Uses `npm ls --json`
// (not `npm root -g`: npm masks UUID-like path segments as "***").
function globalVersion() {
  const r = npm(['ls', '-g', pkg.name, '--depth=0', '--json']);
  try {
    const dep = JSON.parse(r.stdout || '{}').dependencies || {};
    return (dep[pkg.name] && dep[pkg.name].version) || null;
  } catch { return null; }
}

function installGlobal() {
  const spec = `${pkg.name}@${pkg.version}`;
  if (globalVersion() === pkg.version) {
    console.log(` \x1b[32m✓\x1b[0m ${spec} already installed globally`);
    return;
  }
  console.log(`\x1b[34m\x1b[1m==>\x1b[0m Installing ${spec} globally (npm install -g) so \`termx\` stays available…`);
  const r = npm(['install', '-g', spec, '--no-fund', '--no-audit', '--loglevel=error'], { stdio: 'inherit' });
  if (r.status === 0) {
    console.log(` \x1b[32m✓\x1b[0m termx installed globally`);
  } else {
    // e.g. EACCES with a system Node on mac/Linux: setup still works,
    // because termx also installs itself to ~/.termx/bin and adds it to PATH.
    console.log(` \x1b[33m!\x1b[0m Global npm install failed, continuing (termx is also installed to ~/.termx/bin)`);
  }
}

function run(cmd, cmdArgs) {
  const r = spawnSync(cmd, cmdArgs, { stdio: 'inherit' });
  if (r.error) return null;
  return r.status === null ? 1 : r.status;
}

function main() {
  const argv = process.argv.slice(2);
  if (shouldInstallGlobal(__dirname, argv, process.env)) installGlobal();
  const args = argv.filter((a) => a !== '--no-global');

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
module.exports = { isNpx, shouldInstallGlobal, installGlobal };
