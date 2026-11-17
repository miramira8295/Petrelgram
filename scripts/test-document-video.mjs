import assert from 'node:assert/strict';import fs from 'node:fs';import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
let next=0,stops=0;const timers=new Map();
const ctx=vm.createContext({ViewV2:class{},ViewPU:class{},setTimeout:cb=>{timers.set(++next,cb);return next;},clearTimeout:id=>timers.delete(id),VideoController:class{stop(){stops++;}}});
function load(path,names){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load(root+'util/documentEmbedNavigation.ets',['documentEmbedDirectVideo']);load(root+'util/documentVideoFocus.ets',['claimDocumentVideo']);load(compiled+'pages/chat/DrawnDocumentVideo.ts',['DrawnDocumentVideo']);
for(const url of ['https://cdn.test/a.mp4','https://cdn.test/a.MP4?token=x#t=3'])assert.equal(ctx.documentEmbedDirectVideo(url,''),true);
for(const url of ['https://site.test/a.mp4.exe','file:///a.mp4','https://site.test/page?file=a.mp4'])assert.equal(ctx.documentEmbedDirectVideo(url,''),false);
assert.equal(ctx.documentEmbedDirectVideo('https://cdn.test/a.mp4','<p>HTML wins</p>'),false);
function row(){const r=Object.create(ctx.DrawnDocumentVideo.prototype);Object.assign(r,{widget:{url:'https://cdn.test/a.mp4'},playing:false,fallback:false,visible:true,timeout:-1,generation:0,release:null,controller:new ctx.VideoController(),onClaim:()=>true});return r;}
function flush(){const pending=[...timers.values()];timers.clear();for(const fn of pending)fn();}
const a=row(),b=row();assert.equal(a.playing,false);a.start();const oldController=a.controller,oldWidget=a.widget,oldGeneration=a.generation;assert.ok(a.current(oldController,oldWidget,oldGeneration));a.prepared();assert.equal(timers.size,0);
b.start();assert.equal(a.playing,false);assert.equal(b.playing,true);assert.equal(a.current(oldController,oldWidget,oldGeneration),false);assert.equal(stops,1);
b.widget={url:'https://cdn.test/b.mp4'};b.sourceChanged();assert.equal(b.playing,false);assert.equal(timers.size,0);b.start();flush();assert.equal(b.fallback,true);assert.equal(b.playing,false);
a.visible=false;a.start();assert.equal(a.playing,false);a.visible=true;a.onClaim=()=>false;a.start();assert.equal(a.playing,false);
for(let i=0;i<1000;i++){const r=row();r.start();r.aboutToDisappear();}assert.equal(timers.size,0);const last=row();last.start();last.aboutToDisappear();assert.equal(timers.size,0);
console.log('PASS: direct MP4/signed URL routing, HTML precedence, explicit play, one active player, stale owner, local fallback, timeout and 1000 recycle cleanup.');
