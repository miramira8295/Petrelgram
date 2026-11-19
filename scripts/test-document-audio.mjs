import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
const ctx=vm.createContext({ViewV2:class{},ViewPU:class{},MEDIA_USER_PRIORITY:24});
function load(path,names=[]){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load(root+'util/drawnDocumentMedia.ets');load(root+'util/drawnDocumentWidget.ets',['drawnDocumentWidget']);
load(root+'util/documentAudioTrack.ets',['documentAudioTrack']);
const audio=id=>({'@type':'pageBlockAudio',audio:{audio:{id,size:5000},title:'Track '+id,performer:'Artist',duration:40}});
const first=ctx.drawnDocumentWidget(audio(20),'a'),second=ctx.drawnDocumentWidget(audio(21),'b');
assert.equal(first.kind,'audio');assert.equal(first.title,'Track 20');
const a=ctx.documentAudioTrack(first,3,123,'/music'),b=ctx.documentAudioTrack(second,3,123,'');
assert.equal(a.messageId,-20);assert.equal(b.messageId,-21);assert.equal(a.sourceMessageId,123);assert.equal(b.sourceMessageId,123);
assert.equal(ctx.drawnDocumentWidget(audio(NaN),'bad'),null);
load(root+'services/VoicePlayback.ets',['VoicePlayback']);
const engine=Object.create(ctx.VoicePlayback.prototype),started=[];engine.toggleCurrent=()=>false;engine.play=(...args)=>started.push(args);
engine.toggleDocumentMusic(20,ctx.localAudioSource('/music'),40);
assert.equal(started[0][0],-20);assert.equal(started[0][3],'music');
engine.startDocumentMusic(21,ctx.streamAudioSource(21,5000,'audio/mpeg'),40);assert.equal(started[1][0],-21);
engine.toggleMusic(-20,'/invalid',40);engine.startMusic(-20,'/invalid',40);engine.toggleDocumentMusic(0,ctx.localAudioSource('/invalid'),40);
assert.equal(started.length,2);
let fileCallback,voiceCallback,requests=0,published=[],plays=[],seeks=[];
ctx.cachedMusicCover=()=>'';
Object.assign(ctx,{documentFileState:()=>({path:'',failed:false}),watchDocumentFile:(_file,fn)=>{fileCallback=fn;return()=>{};},
 requestDocumentFile(){requests++},cancelDocumentFile(){},publishNowPlaying:state=>published.push(state),
 getVoicePlayback:()=>({current:()=>({mode:'idle'}),setDocumentPlaylist(){},subscribe:fn=>{voiceCallback=fn;return()=>{};},toggleDocumentMusic:(...args)=>plays.push(args),seek:(...args)=>seeks.push(args)})});
load(compiled+'pages/chat/DrawnDocumentAudio.ts',['DrawnDocumentAudio']);
const card=Object.create(ctx.DrawnDocumentAudio.prototype);
Object.assign(card,{widget:first,audioItems:[first,second],chatId:3,messageId:123,visible:true,generation:0,pending:false,offFile:null,offVoice:null,onClaim:()=>true});
card.bind();card.tap();assert.equal(plays.length,1);assert.equal(plays[0][1].fileId,20);assert.equal(requests,0);
assert.equal(published[0].sourceMessageId,123);assert.equal(published[0].documentTrack.fileId,20);
const stale=fileCallback;card.widget={...second,size:0};card.onSourceChanged();card.tap();assert.equal(requests,1);assert.equal(card.pending,true);
stale({path:'/wrong',failed:false});assert.equal(card.path,'');assert.equal(plays.length,1);
fileCallback({path:'/right',failed:false});assert.equal(plays.length,2);assert.equal(plays[1][0],21);assert.equal(plays[1][1].path,'/right');
const publications=published.length;
for(let i=0;i<1000;i++)voiceCallback({playingId:-21,mode:'music',status:'playing',positionMs:i,durationMs:40000});
assert.equal(published.length,publications);assert.equal(requests,1);
card.aboutToDisappear();assert.equal(card.pending,false);
// Current track adoption is O(1), cancels old pending work and never restarts playback.
load(root+'util/musicTrackModel.ets');load(root+'store/MusicPlayerController.ets',['MusicPlayerController']);
const controller=Object.create(ctx.MusicPlayerController.prototype);
Object.assign(controller,{queue:[a],index:0,playSeq:2,loadingKey:'old',documentIndices:new Map(),notify(){}});
controller.adopt(b);assert.equal(controller.current(),b);assert.equal(controller.playSeq,3);assert.equal(controller.loadingKey,'');
controller.adopt(b);assert.equal(controller.playSeq,3);
controller.toggle();assert.equal(plays.at(-1)[0],21);
console.log('PASS: embedded music stream/local IDs, real-message metadata, invalid-ID rejection, reuse-safe download intent, 1000 playback ticks without metadata publication, current-track adoption.');
// One shared playlist per source, O(1) subsequent reads, stable document order.
const items=[first,second,first],list=ctx.documentAudioPlaylist(items,3,123);
assert.deepEqual(Array.from(list,t=>t.fileId),[20,21]);
for(let i=0;i<1000;i++)assert.equal(ctx.documentAudioPlaylist(items,3,123),list);
let account={send:()=>Promise.resolve({})};ctx.getTdClient=()=>account;
const queued=Object.create(ctx.VoicePlayback.prototype),advanced=[];
Object.assign(queued,{documentPlaylist:[],documentIndices:new Map(),documentClient:null,documentDownloadSerial:0,documentDownloading:false,generation:1,state:{playingId:-20,status:'completed'}});
queued.playDocumentTrack=(track,source)=>advanced.push([track,source]);
queued.setDocumentPlaylist(list);queued.advanceDocumentPlaylist(-20);assert.equal(advanced[0][0].fileId,21);
queued.advanceDocumentPlaylist(-21);assert.equal(advanced.length,1,'stop at end rather than replay the last song');
account={send:()=>Promise.resolve({})};queued.advanceDocumentPlaylist(-20);assert.equal(advanced.length,1);assert.equal(queued.documentPlaylist.length,0);
let finish,downloadCalls=0;account={send:()=>{downloadCalls++;return new Promise(resolve=>finish=resolve)}};
const unknown={...b,fileSize:0,localPath:''};queued.setDocumentPlaylist([a,unknown]);queued.advanceDocumentPlaylist(-20);queued.advanceDocumentPlaylist(-20);
assert.equal(downloadCalls,1);
queued.generation++;finish({local:{is_downloading_completed:true,path:'/late'}});await Promise.resolve();assert.equal(advanced.length,1);
queued.setDocumentPlaylist([a,unknown]);queued.advanceDocumentPlaylist(-20);finish({local:{is_downloading_completed:true,path:'/next'}});await Promise.resolve();assert.equal(advanced.length,2);assert.equal(advanced[1][1].path,'/next');
const musicQueue=[a,b];controller.adopt(a,musicQueue);controller.adopt(b,musicQueue);assert.equal(controller.getQueue(),musicQueue);assert.equal(controller.index,1);
console.log('PASS: shared/deduplicated playlist, 1000 cache hits, next/end/account boundaries, stale whole-file completion and music-center queue retention.');

ctx.SliderChangeMode={Begin:0,Moving:1,End:2,Click:3};
card.widget=first;card.visible=true;card.onSourceChanged();card.onClaim=()=>true;
let handler=card.seekCallback();handler(.2,0);handler(.6,1);assert.equal(card.shownSeekProgress,.6);
for(let i=0;i<1000;i++){voiceCallback({playingId:-20,mode:'music',status:'playing',positionMs:i,durationMs:40000});assert.equal(card.shownSeekProgress,.6,'playback clock cannot overwrite active drag');}
handler(.6,2);assert.deepEqual(seeks.pop(),[-20,.6]);assert.equal(card.shownSeekProgress,.6,'committed thumb does not snap back before playback notification');
handler(.7,3);assert.deepEqual(seeks.pop(),[-20,.7],'keyboard/click can seek without Begin');
let claims=0;card.onClaim=()=>{claims++;return false;};handler(.2,0);handler(.8,1);handler(.8,3);handler(.8,2);assert.equal(claims,1);assert.equal(seeks.length,0,'denied gesture cannot dispatch a seek');
card.onClaim=()=>true;handler(.2,0);card.widget=second;card.onSourceChanged();const newHandler=card.seekCallback();newHandler(.4,0);handler(.8,2);assert.equal(card.seekDragging,true,'stale End cannot cancel the new drag');assert.equal(seeks.length,0);
card.widget=first;card.onSourceChanged();handler(.8,2);newHandler(.4,2);assert.equal(seeks.length,0,'A/B/A rejects both old callbacks');
handler=card.seekCallback();handler(Infinity,3);assert.equal(seeks.length,0);handler(2,3);assert.deepEqual(seeks.pop(),[-20,1]);card.aboutToDisappear();handler(.5,3);assert.equal(seeks.length,0,'detached seek ignored');
let scans=0;const many=new Proxy(Array.from({length:5000},(_,i)=>({...first,file:{id:10000+i},title:`track ${i}`})),{get(t,k){if(k===Symbol.iterator)scans++;return Reflect.get(t,k);}});
const fullList=ctx.documentAudioPlaylist(many,3,123);assert.equal(fullList.length,5000);assert.equal(fullList.at(-1).fileId,14999);const scanCount=scans;for(let i=0;i<1000;i++)assert.equal(ctx.documentAudioPlaylist(many,3,123),fullList);assert.equal(scans,scanCount);
console.log('PASS: local seek drag vs playback clock, commit/click/denial, reuse and detach epochs, finite clamp, full 5000-track playlist and 1000 no-rescan cache hits.');

let indexed=0;const mapSet=queued.documentIndices.set.bind(queued.documentIndices);queued.documentIndices.set=(...args)=>{indexed++;return mapSet(...args);};
queued.setDocumentPlaylist(fullList);assert.equal(queued.documentPlaylist,fullList);assert.equal(queued.documentIndices.size,5000);assert.equal(indexed,5000);for(let i=0;i<1000;i++)queued.setDocumentPlaylist(fullList);assert.equal(indexed,5000,'same playlist cannot rebuild the entire index');
queued.advanceDocumentPlaylist(fullList.at(-2).messageId);assert.equal(advanced.at(-1)[0].fileId,14999,'player advances beyond the old cutoff');
load(compiled+'pages/chat/DrawnDocumentVoice.ts',['DrawnDocumentVoice']);
const voice=Object.assign(Object.create(ctx.DrawnDocumentVoice.prototype),{widget:first,visible:true,generation:0,pending:false,loading:false,off:null,onClaim:()=>true});voice.bind();
const request=voice.requestCallback(),oldRequests=requests;request();request();assert.equal(requests,oldRequests+1,'pending voice click cannot enqueue the same transfer twice');
voice.widget=second;voice.onSourceChanged();request();assert.equal(requests,oldRequests+1,'old source click cannot request the replacement file');const currentRequest=voice.requestCallback();currentRequest();assert.equal(requests,oldRequests+2);fileCallback({path:'',failed:true});currentRequest();assert.equal(requests,oldRequests+3,'failed transfer can be retried');voice.aboutToDisappear();currentRequest();assert.equal(requests,oldRequests+3);
console.log('PASS: full player playlist and one-time index, next beyond 2048, pending voice dedup and reused/detached button callbacks.');
