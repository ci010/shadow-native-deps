import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const output = process.argv[2];
const home = join(process.env.HOME, 'never-created');
assert.deepEqual(readdirSync(process.env.HOME), []);
const { client, close, table, families } = await import('@layerfs/node');
const pkg = JSON.parse(readFileSync('node_modules/@layerfs/node/package.json', 'utf8'));
assert.equal(pkg.name, '@layerfs/node');
assert.equal(pkg.version, '2.0.0-rc.1');
assert.equal(pkg.license, 'MIT');
assert.deepEqual(pkg.os, ['linux']);
assert.deepEqual(pkg.cpu, ['x64']);
assert.deepEqual(pkg.libc, ['glibc']);
assert.equal(pkg.engines.node, '>=22');
assert.equal(process.platform, 'linux');
assert.equal(process.arch, 'x64');
assert.ok(!existsSync(home));
assert.equal(table.length, 84);
assert.equal(families.length, 12);
const api = client({ home });
const names = new Set();
for (const spec of table) {
  assert.equal(typeof spec.family, 'string');
  assert.equal(typeof spec.call, 'string');
  assert.ok(Array.isArray(spec.args));
  assert.ok(Array.isArray(spec.options));
  assert.equal(typeof spec.help, 'string');
  assert.equal(typeof api[spec.family]?.[spec.call], 'function');
  names.add(`${spec.family}.${spec.call}`);
}
assert.equal(names.size, table.length);
let discovered;
try {
  discovered = await api.machine.platforms();
  assert.equal(discovered.host, 'linux');
  const platforms = discovered.platforms.map((row) => row.platform);
  assert.ok(platforms.includes('native') && platforms.includes('docker'));
} finally {
  assert.equal(close(), 0);
}
assert.deepEqual(readdirSync(process.env.HOME), []);
const provenance = JSON.parse(readFileSync(join(output, 'provenance.json'), 'utf8'));
const addon = readFileSync('node_modules/@layerfs/node/layerfs.node');
assert.equal(createHash('sha256').update(addon).digest('hex'), provenance.artifact.addonSha256);
const callTable = JSON.stringify({ families, calls: table }, null, 2) + '\n';
writeFileSync(join(output, 'call-table.json'), callTable);
provenance.callTableSha256 = createHash('sha256').update(callTable).digest('hex');
provenance.smoke = {
  os: 'Ubuntu 24.04',
  glibc: process.report.getReport().header.glibcVersionRuntime,
  packages: execFileSync('dpkg-query', ['-W', '-f=${Package} ${Version}\n', 'libc6', 'libssl3t64'], { encoding: 'utf8' }).trim().split('\n'),
  sharedLibraries: readFileSync('/smoke/loader', 'utf8').trim().split('\n').map((line) => line.trim().replace(/ \(0x[0-9a-f]+\)$/i, '')),
  node: process.version,
  npm: '10.9.4',
  network: 'none',
  isolatedHomeStayedEmpty: true,
  calls: table.length,
  platforms: discovered.platforms.map((row) => row.platform),
};
writeFileSync(join(output, 'provenance.json'), JSON.stringify(provenance, null, 2) + '\n');
console.log(provenance.smoke);
