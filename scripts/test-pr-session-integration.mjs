// PR integration boundaries: real services, deterministic platform/TDLib edges.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const compile=source=>ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
function load(ctx,file,names=[]){
 const source=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(ObservedV2|Trace)\s*/g,'');
 vm.runInContext(compile(source+names.map(n=>`\nglobalThis.${n}=${n};`).join('')),ctx,{filename:file});
}
const storage=new Map(),timers=new Map(),requests=[],publications=[];let serial=0;
const ctx=vm.createContext({AppStorage:{get:k=>storage.get(k),setOrCreate:(k,v)=>storage.set(k,v)},
 text:{FontWeight:Object.fromEntries(Array.from({length:9},(_,i)=>['W'+(i+1)*100,i]))},
 setTimeout:fn=>{timers.set(++serial,fn);return serial;},clearTimeout:id=>timers.delete(id),
 publishTranslating:id=>publications.push(id),clearTranslationStatus:id=>publications.push(id),publishTranslationFailed:id=>publications.push(id),logE:()=>{}});
load(ctx,'util/systemFontWeight.ets');
ctx.seedSystemFontWeightScale({fontWeightScale:1.4});assert.equal(ctx.drawnWeightNormal(),5);assert.equal(ctx.drawnWeightBold(),8);
ctx.seedSystemFontWeightScale({fontWeightScale:Infinity});assert.equal(ctx.drawnWeightNormal(),3);
load(ctx,'util/edgeBlurSetting.ets',['edgeBlurSwitch']);
for(const key of ['chatTop','chatBottom','listTop','listBottom'])assert.equal(ctx.edgeBlurPageTopOn(true,true,ctx.edgeBlurSwitch[key]),false,'timeline stays filter-free by default');
assert.equal(ctx.edgeBlurPageTopOn(false,true,'on'),false);assert.equal(ctx.edgeBlurPageTopOn(true,false,'on'),true);
load(ctx,'services/TranslationService.ets',['TranslationService','getTranslationService']);
const client={send:()=>new Promise((resolve,reject)=>requests.push({resolve,reject}))};
const flush=async()=>{for(let n=0;n<8;n++)await Promise.resolve();};
const service=ctx.getTranslationService(client),answers=[];
for(let i=0;i<10;i++)service.request(1,i,0,'en',value=>answers.push(value));
assert.ok(service.activeJobs.size>0);assert.ok(service.queue.length>0);
ctx.getTranslationService({send:client.send});assert.equal(answers.length,10);assert.ok(answers.every(v=>v===null));
const published=publications.length;
for(const req of requests.splice(0))req.resolve({text:'old account',entities:[]});await flush();
assert.equal(publications.length,published);assert.equal(service.cache.size,0);assert.equal(service.activeJobs.size,0);
service.request(1,1,0,'en',value=>assert.equal(value,null));assert.equal(requests.length,0);
const fresh=new ctx.TranslationService(client);
for(let i=0;i<510;i++){
 fresh.request(2,i,0,'en',()=>{});requests.shift().resolve({text:String(i),entities:[]});await flush();
}
assert.equal(fresh.cache.size,500);assert.equal(fresh.cached(2,0,0,'en'),null);assert.equal(fresh.cached(2,509,0,'en').text,'509');
fresh.request(2,999,0,'en',()=>{});requests.shift().reject({message:'retry after 10'});await flush();
for(let i=0;i<20;i++)fresh.request(2,1000+i,0,'en',()=>{});
assert.equal(timers.size,1,'one cooldown timer despite repeated requests');fresh.abandon();assert.equal(timers.size,0);

load(ctx,'services/MediaPlaybackKeepAlive.ets',['MediaPlaybackKeepAlive']);
vm.runInContext('globalThis.keep=mediaPlaybackKeepAlive;',ctx);
const keep=ctx.keep;keep.started=true;let stops=0;keep.stopCurrent=async()=>{stops++;keep.started=false;};
ctx.mediaPlaybackKeepAlive=keep;ctx.getUiAbilityContext=()=>({});ctx.KEY_BG_PLAY_VIDEO='videoBackground';storage.set('videoBackground',true);
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root+'pages/chat/StreamingVideoPlayer.ts';
const source=fs.readFileSync(compiled,'utf8'),ast=ts.createSourceFile(compiled,source,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='StreamingVideoPlayer');
const methods=cls.members.filter(n=>['onPlayingChanged','releaseKeepAlive'].includes(n.name?.getText(ast)))
 .map(n=>n.getText(ast).replace(/@\w+\([^)]*\)\s*/g,'')).join('\n');
vm.runInContext(compile(`class Player {${methods}} globalThis.Player=Player;`),ctx);
function player(){const p=new ctx.Player();Object.assign(p,{keepAliveToken:null,isPlaying:true,appOnly:false,embedded:false});
 for(const method of ['syncProgressPolling','refreshProgress','onPlayStateChanged','syncScreenAwake','syncAudioFocus','syncAutoHideControls'])p[method]=()=>{};return p;}
const a=player(),b=player();for(let i=0;i<1000;i++)a.onPlayingChanged();b.onPlayingChanged();await flush();assert.equal(keep.holds.size,2);
a.embedded=true;a.onPlayingChanged();await flush();assert.equal(keep.holds.size,1);assert.equal(stops,0);
b.isPlaying=false;b.onPlayingChanged();await flush();assert.equal(keep.holds.size,0);assert.equal(stops,1);
console.log('PASS: default filter-free timelines, real system weight normalization, translation account cancellation/500 cache/single timer, and 1000 idempotent video keepalive updates with independent owners.');
