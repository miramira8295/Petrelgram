// Verify reactive-read boundaries using actual compiled consumers. No claim
// about ArkUI frame timings; device trace must confirm the tick fanout stops.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
const ctx=vm.createContext({});
const run=s=>vm.runInContext(ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
run(fs.readFileSync(root+'util/messageRowClock.ets','utf8').replace(/^import.*;\n/gm,'').replace(/@(ObservedV2|Trace)\s*/g,'').replace(/\bexport /g,'')+'\nglobalThis.Clock=MessageRowClock;globalThis.needs=messageRowNeedsClock;');
function member(file,name){
 const s=fs.readFileSync(compiled+'pages/chat/'+file+'.ts','utf8');
 const a=ts.createSourceFile(file,s,ts.ScriptTarget.Latest,true);
 const c=a.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===file);
 return c.members.find(n=>n.name?.getText(a)===name).getText(a);
}
run(`class Row {${member('MessageRowHost','rowNowSec')}};globalThis.Row=Row;`);
let reads=0,seconds=1000;
const clock=new ctx.Clock();Object.defineProperty(clock,'nowSec',{get(){reads++;return seconds;}});
const row=new ctx.Row();row.clock=clock;
for(const type of ['text','richMessage','photo','video','sticker','emoji','customEmoji','audio','document','contact']){
 row.group={head:{isOutgoing:false,contentType:type}};const before=reads;
 for(let i=0;i<1000;i++){seconds++;assert.equal(row.rowNowSec(),0);}
 assert.equal(reads,before,type+' must not subscribe ordinary incoming rows to ticks');
}
for(const [type,outgoing] of [['text',true],['photo',true],['video',true],['location',false],['venue',false],['poll',false]]){
 row.group={head:{isOutgoing:outgoing,contentType:type}};
 const before=reads;assert.equal(row.rowNowSec(),seconds);seconds+=30;assert.equal(row.rowNowSec(),seconds);assert.equal(reads,before+2);
}
// Same physical host may switch between rows: branch selection must follow
// current params rather than retain the old row's dependency choice.
for(let i=0;i<1000;i++){
 row.group={head:{contentType:'poll',isOutgoing:false}};assert.equal(row.rowNowSec(),seconds);
 row.group={head:{contentType:'photo',isOutgoing:false}};const before=reads;assert.equal(row.rowNowSec(),0);assert.equal(reads,before);
}
const timeline=member('ChatPage','surfaceTimeline');
assert.match(timeline,/clock: this\.rowClock/);assert.doesNotMatch(timeline,/nowSec:|\.nowSec\b/);
const rowBuilder=member('ChatTimelineHost','preparedMessageBubble');
assert.match(rowBuilder,/clock: this\.clock/);assert.doesNotMatch(rowBuilder,/\.nowSec\b/);
assert.match(member('MessageRowHost','initialRender'),/nowSec: this\.rowNowSec\(\)/);
assert.match(member('ChatPage','mediaViewer'),/nowSec: this\.nowSec/,'open viewer retains its live relative time');
assert.match(member('ChatPage','armNowSecTimer'),/NOW_SEC_TICK_MS/,'existing single timer cadence is unchanged');
assert.notEqual(new ctx.Clock(),clock,'each page owns its own clock');
console.log('PASS: 10000 ordinary incoming renders read zero clock ticks; outgoing menus/location/poll stay live; 1000 mixed reuse switches; compiled page/list pass stable clock and open viewer keeps time.');
