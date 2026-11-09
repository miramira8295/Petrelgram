// Actual formatter cache, with a counted native-compatible Intl boundary.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE || 'typescript');const ts=imported.default||imported;
const src=fs.readFileSync(new URL('../entry/src/main/ets/util/intlFormat.ets',import.meta.url),'utf8');
const js=ts.transpileModule(src.replace(/^import[\s\S]*?;\n/gm,'').replace(/\bexport /g,''),
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
let constructors=0,failNext=false;
const ctx=vm.createContext({Intl:{...Intl,NumberFormat:class {
 constructor(locale,options){constructors++;if(failNext){failNext=false;throw Error('unavailable');}this.formatter=new Intl.NumberFormat(locale,options);}
 format(value){return this.formatter.format(value);}
},DateTimeFormat:Intl.DateTimeFormat},i18n:{System:{getAppPreferredLanguage:()=> 'en-US'}}});
vm.runInContext(js,ctx);let count=0;
function check(name,fn){try{fn();count++;}catch(e){e.message=`${name}: ${e.message}`;throw e;}}
check('one constructor per locale/precision policy despite changing values',()=>{
 ctx.setLocaleForTest('en-US');const before=constructors;
 for(let i=0;i<1000;i++)assert.equal(ctx.decimal(i/10,1),new Intl.NumberFormat('en-US',{minimumFractionDigits:1,maximumFractionDigits:1}).format(i/10));
 assert.equal(constructors-before,1);
 ctx.decimalUpTo(1.5,1);assert.equal(constructors-before,2);
});
check('locale refresh invalidates prior formatters and preserves locale separators',()=>{
 ctx.setLocaleForTest('de-DE');const before=constructors;assert.equal(ctx.decimal(1234.5,1),'1.234,5');assert.equal(constructors-before,1);
 ctx.setLocaleForTest('en-US');assert.equal(ctx.decimal(1234.5,1),'1,234.5');assert.equal(constructors-before,2);
});
check('failed constructor does not poison retry cache',()=>{
 ctx.setLocaleForTest('en-US');failNext=true;const before=constructors;
 assert.equal(ctx.decimal(1234.5,1),'1234.5');assert.equal(ctx.decimal(1234.5,1),'1,234.5');assert.equal(constructors-before,2);
 assert.equal(ctx.decimal(2.5,1),'2.5');assert.equal(constructors-before,2);
});
check('bounded cache retains correct values after eviction',()=>{
 ctx.setLocaleForTest('en-US');
 for(let digits=0;digits<=20;digits++) {
  assert.equal(ctx.decimal(1.25,digits),new Intl.NumberFormat('en-US',{minimumFractionDigits:digits,maximumFractionDigits:digits}).format(1.25));
  assert.ok(vm.runInContext('numberFormats.size',ctx)<=16);
 }
 assert.equal(ctx.decimal(1.5,2),'1.50');assert.equal(ctx.decimalUpTo(1.5,2),'1.5');
});
console.log(`Number formatter cache: ${count} scenarios passed (1000-value differential, locale, recovery, capacity)`);
