// Standalone recipe. Run with Node 24.15+ in a native MSVC developer shell.
import { spawnSync } from 'node:child_process';
import { mkdirSync, copyFileSync, writeFileSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
const root = resolve(import.meta.dirname, '..');
const arch = process.argv[2];
if (process.platform !== 'win32' || process.arch !== arch || !['x64','arm64'].includes(arch)) throw new Error('Native Windows x64/arm64 runner required');
const target = arch === 'x64' ? 'x86_64-pc-windows-msvc' : 'aarch64-pc-windows-msvc';
const native = join(root, 'integrations/agent-desktop');
function run(cmd,args,cwd=root) { const r=spawnSync(cmd,args,{cwd,stdio:'inherit',shell:false}); if(r.error) throw r.error; if(r.status!==0) throw new Error(`${cmd} failed ${r.status}`); }
run(process.execPath,['scripts/fetch.mjs'],native);
run(process.execPath,['--test','scripts/source-test.mjs'],native);
run('cargo',['test','--locked','--target',target,'--lib'],native);
run(process.execPath,['scripts/build.mjs',target],native);
const artifact=join(native,'artifacts',`win32-${arch}`);
run(process.execPath,['scripts/identity.mjs',join(artifact,'shadow-agent-desktop.node')],native);
run(join(artifact,'shadow-input-guard.exe'),['--identity']);
// dumpbin validates the PE machine and dependency list outside a shell environment.
run('dumpbin',['/headers',join(artifact,'shadow-agent-desktop.node')]);
run('dumpbin',['/dependents',join(artifact,'shadow-agent-desktop.node')]);
const bundle=join(root,'bundle'); mkdirSync(bundle);
for(const name of ['shadow-agent-desktop.node','shadow-input-guard.exe']) copyFileSync(join(artifact,name),join(bundle,name));
for(const name of ['LICENSE','NOTICE']) copyFileSync(join(native,name),join(bundle,name));
// Exact corresponding source: owned recipe + pinned baseline + registry sources.
const source=join(root,'source-bundle'); mkdirSync(source);
run('git',['archive','--format=tar','--output='+join(source,'recipe.tar'),'HEAD']);
run('git',['archive','--format=tar','--output='+join(source,'upstream.tar'),'5a2c9ad43e269164a8adc8978a733c40b1d38a8b'],join(native,'.upstream'));
run('cargo',['vendor','--locked',join(source,'vendor')],native);
run('tar',['-czf',join(bundle,'source.tar.gz'),'-C',source,'.']);
const dependencies=[];
for(const name of readdirSync(join(source,'vendor'))) {
 const dir=join(source,'vendor',name), manifest=readFileSync(join(dir,'Cargo.toml'),'utf8');
 const license=manifest.match(/^license\s*=\s*"([^"]+)"/m)?.[1];
 const licenseFile=manifest.match(/^license-file\s*=\s*"([^"]+)"/m)?.[1];
 if(!license && !licenseFile) throw new Error(`Missing dependency license: ${name}`);
 dependencies.push({name,license,licenseFile, notices:readdirSync(dir).filter(n=>/license|copying|notice/i.test(n))});
}
writeFileSync(join(bundle,'THIRD-PARTY-NOTICES.json'),JSON.stringify(dependencies,null,2)+'\n');
const sha256=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const files=Object.fromEntries(readdirSync(bundle).map(n=>[n,{sha256:sha256(join(bundle,n)),size:statSync(join(bundle,n)).size}]));
writeFileSync(join(bundle,'provenance.json'),JSON.stringify({recipe:'agent-desktop-0.10.1-shadow.1',upstream:'5a2c9ad43e269164a8adc8978a733c40b1d38a8b',commit:process.env.GITHUB_SHA,run:process.env.GITHUB_RUN_ID,target,node:process.version,files},null,2)+'\n');
const name=`agent-desktop-0.10.1-shadow.1-win32-${arch}.tar.gz`;
run('tar',['-czf',join(root,name),'-C',bundle,...readdirSync(bundle)]);
writeFileSync(join(root,name+'.sha256'),`${sha256(join(root,name))}  ${name}\n`);
