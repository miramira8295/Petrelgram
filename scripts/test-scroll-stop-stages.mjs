// Real instrumentation and compiled stop handler; native tracing is a double.
// Checks behavior/order and work bounds, not device performance.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
const trace=[],work=[],queue=[];let fail='',nativeAllowed=false;
const action=name=>()=>{work.push(name);if(fail===name)throw Error(name);};
const ctx=vm.createContext({hiTraceMeter:{HiTraceOutputLevel:{COMMERCIAL:1},
 startSyncTrace(_level,name){assert.ok(nativeAllowed,'disabled mode must not enter NAPI');trace.push(['begin',name]);},
 finishSyncTrace(){assert.ok(nativeAllowed);trace.push(['end']);}},setScrollActive:action('effects'),setStickerDecodePaused:action('decode')});
const run=s=>vm.runInContext(ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
run(fs.readFileSync(root+'util/drawnStageMetrics.ets','utf8').replace(/^import.*;\n/gm,'').replace(/\bexport /g,'')+'\nglobalThis.metrics=drawnStageMetrics;');
const source=fs.readFileSync(compiled+'pages/chat/ChatTimelineSession.ts','utf8');
const ast=ts.createSourceFile('session',source,ts.ScriptTarget.Latest,true),cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatTimelineSession');
const handler=cls.members.find(n=>n.name?.getText(ast)==='handleTimelineScrollStop').getText(ast);
run(`class Session {${handler}} globalThis.Session=Session;`);
const session=new ctx.Session();
Object.defineProperty(session,'timelineScrollActive',{set:action('active')});
Object.defineProperty(session,'nextDidScrollIsUserDriven',{set:action('user')});
Object.assign(session,{bindings:{store:()=>({flushScrollDeferredUpdate:action('flush')}),playSlot:{setScrolling:moving=>{assert.equal(moving,false);action('play-gate')();},armSettle:action('play')},capMessageReuseBuckets:action('cache')},
 maybeTrimWindow:action('trim'),resumeChatTgsAfterScroll:action('animations'),driveVisibleWork:settle=>{assert.equal(settle,false,'stop owns the only playback settle');action('visible')();},
 scheduleScrollWork:callback=>{action('schedule')();queue.push(callback);},flushQueuedOlderLoad:action('history')});
const expected=['active','user','effects','decode','flush','trim','animations','visible','play-gate','play','cache','schedule'];
for(let i=0;i<1000;i++){
 work.length=0;session.handleTimelineScrollStop();assert.deepEqual(work,expected);assert.equal(queue.length,1);
 queue.shift()();assert.equal(work.at(-1),'history');
}
assert.equal(trace.length,0,'1000 disabled stops produce zero native trace calls');
function balanced(){let depth=0;for(const [kind] of trace){depth+=kind==='begin'?1:-1;assert.ok(depth>=0);}assert.equal(depth,0);}
nativeAllowed=true;ctx.metrics.setEnabled(true);work.length=0;session.handleTimelineScrollStop();
assert.deepEqual(work,expected);assert.equal(queue.length,1);queue.shift()();balanced();
const names=trace.filter(e=>e[0]==='begin').map(e=>e[1]);
assert.deepEqual(names,['PG/scroll-stop',...['state','effects','decode','flush','trim','animations','visible','play','cache','schedule','history'].map(x=>'PG/scroll-stop/'+x)]);
for(const name of expected){
 fail=name;work.length=0;trace.length=0;queue.length=0;
 assert.throws(()=>session.handleTimelineScrollStop(),new RegExp(name));
 assert.deepEqual(work,expected.slice(0,expected.indexOf(name)+1),'errors must not continue later phases');balanced();
}
fail='';trace.length=0;session.handleTimelineScrollStop();fail='history';assert.throws(()=>queue.shift()(),/history/);balanced();
fail='';trace.length=0;ctx.metrics.setTraceOutput(false);session.handleTimelineScrollStop();queue.shift()();assert.equal(trace.length,0,'sampling mode suppresses native spans');
console.log('PASS: 1000 disabled stops preserve exact order and one deferred history callback, no native calls; enabled spans fixed/balanced; every phase exception propagates and stops later work; sampling suppression preserved.');

run(fs.readFileSync(root+'util/readMarking.ets','utf8').replace(/\bexport /g,'')+'\nglobalThis.VisibleReadIds=VisibleReadIds;');
const ids=new ctx.VisibleReadIds();let memberReads=0;
const at=i=>{memberReads++;return [i+1,i+1];};
const first=ids.prepare(1,100,at,10,15);assert.deepEqual(Array.from(first),[11,12,13,14,15,16]);
const initialReads=memberReads;
for(let i=0;i<10000;i++)assert.equal(ids.prepare(1,100,at,10,15),first);
assert.equal(memberReads,initialReads,'same snapshot/range performs no traversal or allocation');
assert.notEqual(ids.prepare(2,100,at,10,15),first,'same-size edits invalidate');
assert.deepEqual(Array.from(ids.prepare(2,100,at,-1,15)),[]);
assert.deepEqual(Array.from(ids.prepare(2,100,at,99,99)),[100]);
console.log('PASS: visible read-ID cache bounds retained data to visible IDs, 10000 O(1) hits, edit/range/invalid range refresh.');
// Exercise the actual groups accessor: same-size replacement changes revision,
// identical immutable snapshots do not; cache retains no groups/history object.
const accessors=cls.members.filter(n=>n.name?.getText(ast)==='groups').map(n=>n.getText(ast)).join('\n');
run(`class Groups { groupSnapshot=[]; groupsRevision=0; ${accessors} } globalThis.Groups=Groups;`);
const groups=new ctx.Groups(),snapshot=[{memberIds:[1]}];groups.groups=snapshot;
const revision=groups.groupsRevision;groups.groups=snapshot;assert.equal(groups.groupsRevision,revision);
groups.groups=[{memberIds:[2]}];assert.equal(groups.groupsRevision,revision+1);
// Re-evaluate unread state even when visible ID cache hits, and permit retries.
const storeSource=fs.readFileSync(compiled+'store/MessageStore.ts','utf8');
const storeAst=ts.createSourceFile('store',storeSource,ts.ScriptTarget.Latest,true);
const storeClass=storeAst.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='MessageStore');
const mentionMethod=storeClass.members.find(n=>n.name?.getText(storeAst)==='markVisibleMentions').getText(storeAst);
run(`class Mentions {${mentionMethod}} globalThis.Mentions=Mentions;`);
const mentions=new ctx.Mentions(),requests=[],failures=[];
Object.assign(mentions,{chatId:5,messages:[{containsUnreadMention:false}],viewedMentions:new Set(),indexOf:id=>id===1?0:-1,
 viewSource:()=>({}),client:{send:r=>{requests.push(r);return {catch:fn=>failures.push(fn)};}}});
for(let i=0;i<1000;i++)mentions.markVisibleMentions([1]);assert.equal(requests.length,0);
mentions.messages[0].containsUnreadMention=true;mentions.markVisibleMentions([1]);assert.equal(requests.length,1);
mentions.markVisibleMentions([1]);assert.equal(requests.length,1);failures.shift()();
mentions.markVisibleMentions([1]);assert.equal(requests.length,2,'failed request remains retryable on unchanged viewport');
assert.deepEqual(Array.from(requests[1].message_ids),[1]);
console.log('PASS: real timeline revisions and store mention handling preserve late unread events, deduplication and failed request retry.');
