// Standard verification entry: never replay stale CompileArkTS output.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const candidates=[process.env.TYPESCRIPT_MODULE,
  process.env.DEVECO_NODE_HOME && path.resolve(process.env.DEVECO_NODE_HOME,'../ohpm/node_modules/typescript/lib/typescript.js'),
  '/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript/lib/typescript.js'].filter(Boolean);
let typescript;
for(const candidate of candidates){
  const resolved=candidate.startsWith('file:')?fileURLToPath(candidate):candidate;
  if(fs.existsSync(resolved)){typescript=pathToFileURL(path.resolve(resolved)).href;break;}
}
if(!typescript)throw new Error('Set TYPESCRIPT_MODULE to the DevEco TypeScript lib/typescript.js path.');
const env={...process.env,TYPESCRIPT_MODULE:typescript};
function run(command,args){
  const result=spawnSync(command,args,{cwd:root,env,stdio:'inherit',shell:process.platform==='win32'});
  if(result.error)throw result.error;
  if(result.status!==0)process.exit(result.status||1);
}
console.log('DRAWN HOST: building current main/ets before compiler-output replay.');
run('devecocli',['build']);
const suites=JSON.parse(fs.readFileSync(path.join(root,'scripts/drawn-regressions.json'),'utf8'));
if(!Array.isArray(suites)||suites.length===0||new Set(suites).size!==suites.length)throw new Error('Invalid drawn regression manifest');
for(const suite of suites){
  if(!/^test-[a-z0-9-]+\.mjs$/.test(suite))throw new Error(`Invalid suite: ${suite}`);
  console.log(`DRAWN HOST: ${suite}`);
  run(process.execPath,[path.join(root,'scripts',suite)]);
}
console.log(`DRAWN HOST: PASS (${suites.length} suites; Hypium count is reported separately)`);
