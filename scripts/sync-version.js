// Copies package.json's version into the bash and PowerShell scripts.
// Runs automatically during `npm version` (see "version" script in package.json).
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const { version } = require(path.join(root, 'package.json'));
const targets = [
  ['src/unix/termx', /^TERMX_VERSION="[^"]*"/m, `TERMX_VERSION="${version}"`],
  ['src/windows/termx.ps1', /^\$TermxVersion\s*=\s*'[^']*'/m, `$TermxVersion  = '${version}'`],
];
for (const [file, re, repl] of targets) {
  const p = path.join(root, file);
  const src = fs.readFileSync(p, 'utf8');
  if (!re.test(src)) { console.error(`sync-version: version line not found in ${file}`); process.exit(1); }
  fs.writeFileSync(p, src.replace(re, repl));
  console.log(`sync-version: ${file} -> ${version}`);
}
