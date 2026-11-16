// Cross-platform smoke tests for termx. Runs with `npm test` on macOS, Linux and Windows.
// Never touches the real HOME: every run uses a throwaway HOME directory.
'use strict';
const { spawnSync } = require('child_process');
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.join(__dirname, '..');
const pkg = require(path.join(root, 'package.json'));
const isWin = process.platform === 'win32';
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'termx-test-'));
const env = { ...process.env, HOME: home, USERPROFILE: home, TERMX_HOME: path.join(home, '.termx'), ZSH: '', ZSH_CUSTOM: '', ZDOTDIR: '' };

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log(`  ok   ${name}`); }
  catch (e) { failed++; console.log(`  FAIL ${name}\n       ${String(e.message).split('\n').join('\n       ')}`); }
}
function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { env, encoding: 'utf8', ...opts });
  if (r.error) throw r.error;
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}
const termx = (...a) => run(process.execPath, [path.join(root, 'bin', 'termx.js'), ...a]);

console.log(`termx ${pkg.version} tests on ${process.platform}, node ${process.version}\n`);

// ---- every OS: npm entry point ------------------------------------------
test('package.json bin points to an existing file', () => {
  assert.ok(fs.existsSync(path.join(root, pkg.bin.termx)));
});
test('script versions match package.json', () => {
  const sh = fs.readFileSync(path.join(root, 'src/unix/termx'), 'utf8');
  const ps = fs.readFileSync(path.join(root, 'src/windows/termx.ps1'), 'utf8');
  assert.ok(sh.includes(`TERMX_VERSION="${pkg.version}"`), 'bash script version differs (run: node scripts/sync-version.js)');
  assert.ok(ps.includes(`$TermxVersion  = '${pkg.version}'`), 'ps1 script version differs (run: node scripts/sync-version.js)');
});
test('termx --version', () => {
  const r = termx('--version');
  assert.strictEqual(r.code, 0, r.out);
  assert.match(r.out, new RegExp(`termx ${pkg.version.replace(/\./g, '\\.')}`));
});
test('termx help lists commands', () => {
  const r = termx('help');
  assert.strictEqual(r.code, 0, r.out);
  for (const c of ['install', 'theme', 'env', 'uninstall']) assert.ok(r.out.includes(c), `missing ${c}`);
});
test('npx install also installs globally (and only then)', () => {
  const { shouldInstallGlobal } = require(path.join(root, 'bin', 'termx.js'));
  const npxDir = path.join('home', '.npm', '_npx', 'abc123', 'node_modules', 'termx-cli', 'bin');
  const globalDir = path.join('usr', 'local', 'lib', 'node_modules', 'termx-cli', 'bin');
  assert.strictEqual(shouldInstallGlobal(npxDir, ['install'], {}), true);
  assert.strictEqual(shouldInstallGlobal(npxDir, ['setup', '--yes'], {}), true);
  assert.strictEqual(shouldInstallGlobal(npxDir, ['install', '--no-global'], {}), false);
  assert.strictEqual(shouldInstallGlobal(npxDir, ['install'], { TERMX_NO_GLOBAL: '1' }), false);
  assert.strictEqual(shouldInstallGlobal(npxDir, ['theme'], {}), false);
  assert.strictEqual(shouldInstallGlobal(globalDir, ['install'], {}), false);
  assert.strictEqual(shouldInstallGlobal('C:\\Users\\a\\AppData\\Local\\npm-cache\\_npx\\x\\node_modules\\termx-cli\\bin', ['install'], {}), true);
});
test('unknown command exits non-zero', () => {
  assert.notStrictEqual(termx('definitely-not-a-command').code, 0);
});

if (isWin) {
  // ---- Windows: PowerShell script --------------------------------------
  test('termx.ps1 parses without syntax errors', () => {
    const ps1 = path.join(root, 'src', 'windows', 'termx.ps1');
    const cmd = `$e=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('${ps1}',[ref]$null,[ref]$e); if($e.Count){$e|%{$_.ToString()}; exit 1}`;
    const r = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', cmd]);
    assert.strictEqual(r.code, 0, r.out);
  });
  test('doctor reports the execution policy', () => {
    const r = termx('doctor');
    assert.match(r.out, /execution policy (Restricted|RemoteSigned|Unrestricted|Bypass|AllSigned)/, r.out);
  });
  test('install checks execution policy before installing anything', () => {
    const src = fs.readFileSync(path.join(root, 'src', 'windows', 'termx.ps1'), 'utf8');
    const body = src.slice(src.indexOf('function Invoke-Install'));
    const a = body.indexOf('Assert-ExecutionPolicy'), b = body.indexOf('Install-OhMyPosh');
    assert.ok(a > 0 && a < b, 'Assert-ExecutionPolicy must run before Install-OhMyPosh');
  });
  test('theme command without install asks to install', () => {
    const r = termx('theme', 'list');
    assert.notStrictEqual(r.code, 0);
    assert.match(r.out, /termx install/);
  });
} else {
  // ---- macOS / Linux: bash script + .zshrc handling --------------------
  const sh = path.join(root, 'src', 'unix', 'termx');
  test('bash syntax (bash -n)', () => {
    const r = run('bash', ['-n', sh]);
    assert.strictEqual(r.code, 0, r.out);
  });
  test('env set / list / unset (with quotes)', () => {
    assert.strictEqual(termx('env', 'set', 'API_URL', "http://it's.local").code, 0);
    const list = termx('env', 'list').out;
    assert.ok(list.includes(`export API_URL='http://it'\\''s.local'`), list);
    assert.strictEqual(termx('env', 'unset', 'API_URL').code, 0);
    assert.ok(!termx('env', 'list').out.includes('API_URL'));
  });
  test('env rejects invalid names', () => {
    assert.notStrictEqual(termx('env', 'set', '1BAD', 'x').code, 0);
  });

  // fake Oh My Zsh install so configure_zshrc can be tested offline
  const omz = path.join(home, '.oh-my-zsh');
  fs.mkdirSync(path.join(omz, 'templates'), { recursive: true });
  fs.mkdirSync(path.join(omz, 'themes'), { recursive: true });
  fs.writeFileSync(path.join(omz, 'oh-my-zsh.sh'), '# fake\n');
  fs.writeFileSync(path.join(omz, 'templates', 'zshrc.zsh-template'),
    'export ZSH="$HOME/.oh-my-zsh"\nZSH_THEME="robbyrussell"\nplugins=(git)\nsource $ZSH/oh-my-zsh.sh\n');
  for (const t of ['robbyrussell', 'agnoster', 'af-magic']) fs.writeFileSync(path.join(omz, 'themes', `${t}.zsh-theme`), 'PROMPT="> "\n');
  const zshrc = path.join(home, '.zshrc');
  const original = 'export PATH="$HOME/go/bin:$PATH"\nalias ll="ls -la"\n';
  fs.writeFileSync(zshrc, original);

  const lib = fs.readFileSync(sh, 'utf8').replace(/\nmain "\$@"\s*$/, '\n');
  const libFile = path.join(home, 'termx-lib.sh');
  fs.writeFileSync(libFile, lib);
  const configure = () => run('bash', ['-c', `set +u; source "${libFile}"; configure_zshrc`]);
  const ok = (r) => assert.strictEqual(r.code, 0, `exit ${r.code}\n${r.out}`);

  test('configure .zshrc keeps user content and is idempotent', () => {
    ok(configure());
    ok(configure());
    const c = fs.readFileSync(zshrc, 'utf8');
    assert.strictEqual(c.split('# >>> termx pre >>>').length - 1, 1, 'pre block duplicated');
    assert.strictEqual(c.split('# >>> termx post >>>').length - 1, 1, 'post block duplicated');
    assert.ok(c.includes('go/bin'), 'user PATH lost');
    assert.ok(c.indexOf('# >>> termx pre >>>') < c.indexOf('source $ZSH/oh-my-zsh.sh'), 'pre block must come before oh-my-zsh.sh');
  });
  test('theme list / set / current', () => {
    const list = termx('theme', 'list').out;
    for (const t of ['robbyrussell', 'agnoster', 'af-magic']) assert.ok(list.includes(t), list);
    assert.strictEqual(termx('theme', 'set', 'agnoster').code, 0);
    assert.strictEqual(termx('theme', 'current').out.trim(), 'agnoster');
    assert.notStrictEqual(termx('theme', 'set', 'nope').code, 0);
  });
  test('uninstall --termx-only removes only termx blocks', () => {
    assert.strictEqual(termx('uninstall', '--termx-only', '--yes').code, 0);
    const c = fs.readFileSync(zshrc, 'utf8');
    assert.ok(!c.includes('termx pre') && !c.includes('termx post'));
    assert.ok(fs.existsSync(omz), 'Oh My Zsh should be kept');
  });
  test('reinstall then uninstall --all restores the true original .zshrc', () => {
    ok(configure());
    ok(termx('uninstall', '--all', '--yes'));
    assert.strictEqual(fs.readFileSync(zshrc, 'utf8'), original);
    assert.ok(!fs.existsSync(omz), 'Oh My Zsh should be removed');
  });
  if (spawnSync('zsh', ['--version']).status === 0) {
    test('generated zsh blocks parse (zsh -n)', () => {
      const blocks = run('bash', ['-c', `source "${libFile}"; pre_block; post_block`]).out;
      const f = path.join(home, 'blocks.zsh'); fs.writeFileSync(f, blocks);
      const r = run('zsh', ['-n', f]);
      assert.strictEqual(r.code, 0, r.out);
    });
  }
}

fs.rmSync(home, { recursive: true, force: true });
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
