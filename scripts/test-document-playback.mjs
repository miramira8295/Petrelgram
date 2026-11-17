import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/src/main/ets/';
const context=vm.createContext({});
function load(path,names,ctx=context){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load(root+'util/animationSlotPool.ets',[]);load(root+'util/documentPlaybackLease.ets',['DocumentPlaybackLease']);
let active=0,peak=0;const changes=[];
const leases=Array.from({length:1000},(_,i)=>new context.DocumentPlaybackLease(on=>{active+=on?1:-1;peak=Math.max(peak,active);changes.push([i,on]);}));
for(const lease of leases)lease.update(true,false);assert.equal(active,1);assert.equal(peak,1);
const before=changes.length;leases[0].update(true,true);assert.equal(changes.length,before,'scroll must preserve a live surface');
for(let i=1;i<999;i++)leases[i].update(false,false);
leases[0].dispose();assert.equal(active,1);assert.deepEqual(changes.at(-1),[999,true]);
leases[999].dispose();assert.equal(active,0);
for(const lease of leases)lease.dispose();assert.equal(active,0);
let gate,park,fileCallback,requests=0,offFiles=0;
Object.assign(context,{ViewV2:class{},ViewPU:class{},chatEnv:{},chatAnimationSuspended:()=>false,senderAnimationsParked:()=>false,
 subscribeChatAnimationGate:fn=>{gate=fn;fn(false);return ()=>{};},subscribeSenderAnimationPark:fn=>{park=fn;fn(false);return ()=>{};},
 documentFileState:()=>({path:''}),watchDocumentFile:(_f,fn)=>{fileCallback=fn;return ()=>offFiles++;},requestDocumentFile:()=>requests++,MEDIA_PREFETCH_PRIORITY:8});
load('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root+'pages/chat/DrawnDocumentPlayback.ts',['DrawnDocumentPlayback']);

const playback=Object.create(context.DrawnDocumentPlayback.prototype);
Object.assign(playback,{media:{kind:'animation',file:{id:1}},env:{powerSaving:false,reduceAnim:false,autoplayGif:true,autoplayVideo:true},pageActive:true,
 attached:false,visible:true,suspended:true,parked:false,failed:false,generation:0,active:false,animationPath:'',offGate:null,offPark:null,offFile:null});
playback.lease=new context.DocumentPlaybackLease(on=>{playback.active=on;if(on)playback.loadAnimation();else{playback.offFile?.();playback.offFile=null;}});
playback.aboutToAppear();assert.equal(playback.active,true);assert.equal(requests,1);
const old=fileCallback;gate(true);assert.equal(playback.active,true);assert.equal(offFiles,0);
park(true);assert.equal(playback.active,false);old({path:'/late'});assert.equal(playback.animationPath,'');
park(false);gate(false);assert.equal(playback.active,true);
const staleCompletion=playback.completionFor(playback.media,playback.generation);
playback.media={kind:'video',file:{id:2}};playback.onSourceChanged();
staleCompletion();assert.equal(playback.failed,false);assert.equal(playback.active,true,'old playback callbacks must not stop new owner');assert.equal(playback.animationPath,'');assert.equal(requests,2,'video must stream, not request its whole file');
old({path:'/wrong'});assert.equal(playback.animationPath,'');
playback.env.powerSaving=true;playback.onPolicyChanged();assert.equal(playback.active,false);
playback.env.powerSaving=false;playback.pageActive=false;playback.onPolicyChanged();assert.equal(playback.active,false);
playback.aboutToDisappear();assert.equal(playback.active,false);
console.log('PASS: 1000 bounded playback leases, O(1) cancellation, retained surface on scroll, parked/offscreen/settings gates, GIF ownership and no full-video download.');
let touching=false;context.setTableScrollTouch=on=>touching=on;
load('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root+'pages/chat/DrawnDocumentGallery.ts',['DocumentGallerySource','DrawnDocumentGallery']);
const source=new context.DocumentGallerySource();let reloads=0;const listener={onDataReloaded(){reloads++;}};
source.registerDataChangeListener(listener);
const slides=Array.from({length:256},(_,index)=>({key:'s'+index,index}));source.update(slides);assert.equal(reloads,1);
for(let i=0;i<1000;i++)source.update(slides);assert.equal(reloads,1,'same immutable gallery is O(1), no reload');
assert.equal(source.totalCount(),256);assert.equal(source.getData(222),slides[222]);
const gallery=Object.create(context.DrawnDocumentGallery.prototype);
Object.assign(gallery,{selected:42,touching:true,slides:slides.slice(0,2),source});gallery.onSourceChanged();
assert.equal(gallery.selected,0);assert.equal(source.totalCount(),2);assert.equal(touching,false);
assert.equal(reloads,2);source.unregisterDataChangeListener(listener);source.update([]);assert.equal(reloads,2);
console.log('PASS: lazy gallery source, constant-time same-source updates, ownership reset and touch release.');
