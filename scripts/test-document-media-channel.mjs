import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let update,requests=[],progress=[],subscriptions=0;
function client(){return {onUpdate(_type,fn){update=fn;subscriptions++;return ()=>subscriptions--;},send(request){return new Promise((resolve,reject)=>requests.push({request,resolve,reject}));}};}
let current=client();
const ctx=vm.createContext({ViewV2:class{},ViewPU:class{},getTdClient:()=>current,publishProgress:(id,value)=>progress.push([id,value]),getUserStore:()=>({}),
 buildMessageEntry:()=>({}),cloneMessage:base=>({...base}),THUMBNAIL_PRIORITY:16,MEDIA_VIEWING_PRIORITY:32});
function load(name,exports=[]){let source=fs.readFileSync('entry/src/main/ets/util/'+name+'.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(source+exports.map(n=>`\nglobalThis.${n}=${n}`).join(';'),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('drawnDocumentMedia');load('documentFileChannel',['watchDocumentFile','requestDocumentFile','documentFileState']);
load('downloadCenterModel');load('downloadViewerSet');load('documentMediaViewer',['DocumentMediaViewer']);
const file=(id,path='',loaded=0)=>({id,size:100,local:{path,is_downloading_completed:path!=='',downloaded_size:loaded}});
const tick=()=>new Promise(resolve=>setImmediate(resolve));
let events=[];const off=ctx.watchDocumentFile(file(1),state=>events.push(state));
assert.equal(subscriptions,1);ctx.requestDocumentFile(file(1),16);ctx.requestDocumentFile(file(1),16);assert.equal(requests.length,1);
update({file:file(1,'',20)});assert.equal(events.length,0);assert.equal(progress.at(-1)[1],20);
ctx.requestDocumentFile(file(1),32,true);assert.equal(requests.length,2);
requests[0].reject(new Error('old request'));await tick();assert.equal(events.length,0);
requests[1].resolve(file(1,'/full'));await tick();assert.equal(events.length,1);assert.equal(events[0].path,'/full');
off();assert.equal(subscriptions,0);
// Late callbacks after a receiver is detached cannot repaint another owner.
let stale=0;const off2=ctx.watchDocumentFile(file(2),()=>stale++);ctx.requestDocumentFile(file(2),16);off2();
requests.at(-1).resolve(file(2,'/late'));await tick();assert.equal(stale,0);
// A new account with the same numerical file ID never receives old pixels.
current=client();assert.equal(ctx.documentFileState(file(1)).path,'');
let seen=0;const off3=ctx.watchDocumentFile(file(1),()=>seen++);update({file:file(99,'/unrelated')});assert.equal(seen,0);off3();
const media=(index,kind,full,thumb)=>({key:'m'+index,index,kind,file:full,thumbnail:thumb,width:640,height:360,size:100,mimeType:'image/jpeg',name:'',autoplay:false});
let redraws=0;
const viewer=new ctx.DocumentMediaViewer({media:[media(0,'photo',file(10),file(11,'/thumb-A')),media(1,'photo',file(20),file(21,'/thumb-B'))],chatId:9,messageId:77,date:1,senderName:'sender'},()=>redraws++);
assert.equal(viewer.entries[0].photoPath,'/thumb-A');assert.equal(viewer.entries[1].photoPath,'/thumb-B');
assert.equal(viewer.entries[0].photoFullPath,'');assert.equal(viewer.entries[0].photoFullProgress,0);
const before=requests.length;viewer.activate(0);assert.equal(requests.length,before+1);assert.equal(requests.at(-1).request.file_id,10);
const paints=redraws;update({file:file(10,'',30)});assert.equal(redraws,paints,'byte progress is not a viewer array update');
viewer.activate(1);update({file:file(10,'/old-A')});assert.equal(viewer.entries[1].photoPath,'/thumb-B');
update({file:file(20,'/full-B')});assert.equal(viewer.entries[1].photoFullPath,'/full-B');assert.equal(viewer.items[1].messageId,77);
viewer.dispose();assert.equal(subscriptions,0);
const videoViewer=new ctx.DocumentMediaViewer({media:[{...media(0,'video',file(60),file(61,'/video-thumb')),duration:65}],chatId:9,messageId:78,date:1,senderName:'sender'},()=>{});
assert.equal(videoViewer.entries[0].videoFileId,60);assert.equal(videoViewer.entries[0].videoDuration,65);
videoViewer.dispose();
const posterless=new ctx.DocumentMediaViewer({media:[{...media(0,'video',file(62,'/local.mp4'),undefined),duration:90}],chatId:9,messageId:79,date:1,senderName:'sender'},()=>{});
assert.equal(posterless.entries[0].photoPath,'','a local MP4 is not an image poster');
assert.equal(posterless.entries[0].videoPath,'/local.mp4');assert.equal(posterless.entries[0].videoDuration,90);
posterless.dispose();
console.log('PASS: O(1) file routing, independent progress, request dedup/generation, account ownership, selected-only viewer downloads and distinct temporary media IDs.');

// Exercise the compiled component lifecycle, including late native callbacks.
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/DrawnDocumentMediaIsland.ts';
const islandSource=fs.readFileSync(compiled,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
vm.runInContext(ts.transpileModule(islandSource+'\nglobalThis.MediaIsland=DrawnDocumentMediaIsland;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const island=Object.create(ctx.MediaIsland.prototype);
Object.assign(island,{generation:0,off:null,visible:true,pageActive:true,path:'old',failed:false,media:media(0,'photo',file(30),file(31,'/A'))});
island.bind();assert.equal(island.path,'/A');
island.media=media(1,'photo',file(40),file(41));island.onMediaChanged();assert.equal(island.path,'');
update({file:file(31,'/old-late')});assert.equal(island.path,'');
update({file:file(41,'/B')});assert.equal(island.path,'/B');
island.aboutToRecycle();assert.equal(island.path,'');assert.equal(subscriptions,0);
console.log('PASS: compiled media-island ownership reset, unrelated completion rejection and recycle cleanup.');
const iconCompiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/DrawnInlineIconLayer.ts';
const iconCode=fs.readFileSync(iconCompiled,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'')
 .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
vm.runInContext(ts.transpileModule(iconCode+'\nglobalThis.InlineImage=DrawnInlineIconImage;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const inlineImage=Object.create(ctx.InlineImage.prototype);
Object.assign(inlineImage,{generation:0,off:null,visible:true,path:'old',icon:{file:file(101,'/icon-A'),width:18,height:18}});
inlineImage.bind();assert.equal(inlineImage.path,'/icon-A');
inlineImage.icon={file:file(102),width:18,height:18};inlineImage.onIconChanged();assert.equal(inlineImage.path,'');
update({file:file(101,'/stale-icon')});assert.equal(inlineImage.path,'');
update({file:file(102,'/icon-B')});assert.equal(inlineImage.path,'/icon-B');
inlineImage.aboutToDisappear();assert.equal(subscriptions,0);
console.log('PASS: compiled inline icon source reset, stale completion isolation and detach cleanup.');
