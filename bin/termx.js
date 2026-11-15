#!/usr/bin/env node
// termx: npm entry point. Same command on every OS; picks the right engine:
//   Windows       -> src/windows/termx.ps1  (Oh My Posh)
//   macOS / Linux -> src/unix/termx         (Oh My Zsh)
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..');
const args = process.argv.slice(2);

function run(cmd, cmdArgs) {
  const r = spawnSync(cmd, cmdArgs, { stdio: 'inherit' });
  if (r.error) return null;
  return r.status === null ? 1 : r.status;
}

let code;
if (process.platform === 'win32') {
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
