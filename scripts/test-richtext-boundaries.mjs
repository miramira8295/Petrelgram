// Exact differential against a supplied pre-change parser, including whitespace
// patterns that are rare in short messages. Host checks do not measure ArkUI.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript');const ts=imported.default||imported;
assert.ok(process.argv[2],'Pass the pre-change richText.ets');
function load(path){const c=vm.createContext({});const s=fs.readFileSync(path,'utf8').replace(/^import[^\n]*\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s+'\nglobalThis.api={trimBlockText,trimBoundaryBreaks,messageUrls};',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,c);return c.api;}
const old=load(process.argv[2]),now=load('entry/src/main/ets/util/richText.ets');
const plain=x=>JSON.parse(JSON.stringify(x));
const run=text=>({text,offset:0,bold:false,italic:false,underline:false,strike:false,code:false,spoiler:false,customEmojiId:'',link:false,url:''});
let cases=0;
function verify(text){assert.equal(now.trimBlockText(text),old.trimBlockText(text));
 const runs=[run(text),run('middle'),run(text)];assert.deepEqual(plain(now.trimBoundaryBreaks(runs)),plain(old.trimBoundaryBreaks(runs)));cases++;}
let layer=[''];verify('');
for(let n=1;n<=7;n++){const next=[];for(const p of layer)for(const c of [' ','\t','\r','\n','x']){const s=p+c;verify(s);next.push(s);}layer=next;}
const long='x'+' '.repeat(100000);assert.equal(now.trimBlockText(long),long);
const blank=Array.from({length:10000},()=>run('\n'));assert.equal(now.trimBoundaryBreaks(blank).length,0);
const entities=Array.from({length:2000},(_,i)=>({offset:0,length:1,type:{'@type':i%3===0?'textEntityTypeUrl':'textEntityTypeTextUrl',url:`https://example.org/${i%900}`}}));
assert.deepEqual(plain(now.messageUrls('x',entities)),plain(old.messageUrls('x',entities)));
console.log(`PASS: ${cases} exhaustive whitespace differentials, 100000-char suffix, 10000 blank runs, URL order/dedup differential.`);
