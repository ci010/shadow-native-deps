import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const [platform, arch] = process.argv.slice(2);
assert.equal(process.platform, platform); assert.equal(process.arch, arch);
const bin = `bundle/aria2c${platform === 'win32' ? '.exe' : ''}`;
const data = readFileSync(bin);
if (platform === 'win32') { const pe = data.readUInt32LE(60); assert.equal(data.readUInt16LE(pe + 4), 0x8664); }
else if (platform === 'linux') { assert.equal(data.readUInt32BE(0), 0x7f454c46); assert.equal(data.readUInt16LE(18), 62); }
else { assert.equal(data.readUInt32LE(0), 0xfeedfacf); assert.equal(data.readUInt32LE(4), arch === 'arm64' ? 0x100000c : 0x1000007); }
// Execute outside MSYS2: catches missing Windows runtime DLLs as well as native loader failures.
assert.match(execFileSync(bin, ['--version'], { encoding: 'utf8' }), /^aria2 version 1\.37\.0\r?$/m);
if (platform === 'linux') { const deps = execFileSync('ldd', [bin], {encoding:'utf8'}); console.log(deps); assert(!deps.includes('not found')); }
if (platform === 'darwin') {
  const deps = execFileSync('otool', ['-L', bin], {encoding:'utf8'}); console.log(deps);
  for (const line of deps.trim().split('\n').slice(1)) assert(/^\s+\/(usr\/lib|System\/Library)\//.test(line), `Non-system macOS dependency: ${line}`);
}
for (const name of ['COPYING', 'LICENSE.OpenSSL', 'THIRD-PARTY-NOTICES.txt', 'build-aria2-native.sh', 'aria2-1.37.0-source.tar.gz']) assert(readFileSync(`bundle/${name}`).length > 0);
