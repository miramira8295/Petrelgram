import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/src/main/ets/';
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
const file=(id,path='')=>({id,size:100,local:{path,is_downloading_completed:path!==''}});
const requests=[];let update;
let client={onUpdate(_type,callback){update=callback;return ()=>{};},send(request){return new Promise((resolve,reject)=>requests.push({request,resolve,reject}));}};
const ctx=vm.createContext({getTdClient:()=>client,publishProgress(){},ViewV2:class{},ViewPU:class{},MEDIA_USER_PRIORITY:24,THUMBNAIL_PRIORITY:16});
function load(path,names=[]){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'')
 .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load(root+'util/documentEmbedNavigation.ets');load(root+'util/drawnDocumentMedia.ets');load(root+'util/drawnDocumentWidget.ets',['drawnDocumentWidget']);
load(root+'util/documentFileChannel.ets',['watchDocumentFile','documentFileState','requestDocumentFile','cancelDocumentFile']);
load(root+'util/documentMapCache.ets',['documentMapFile']);
const widget=ctx.drawnDocumentWidget({'@type':'pageBlockMap',location:{latitude:0,longitude:0},zoom:99,width:320,height:180},'map');
assert.ok(widget);assert.equal(widget.zoom,20);assert.equal(ctx.drawnDocumentWidget({'@type':'pageBlockMap',location:{latitude:91,longitude:0}},'bad'),null);
const one=ctx.documentMapFile(widget,9,300,180),two=ctx.documentMapFile(widget,9,300,180);
assert.equal(one,two);assert.equal(requests.length,1);requests[0].resolve(file(7));await one;
assert.equal((await ctx.documentMapFile(widget,9,300,180)).id,7);assert.equal(requests.length,1);
// Never let the previous account's metadata populate the new account's cache.
const old=ctx.documentMapFile(widget,9,400,180);
client={...client};const fresh=ctx.documentMapFile(widget,9,400,180);
requests[1].resolve(file(8));requests[2].resolve(file(9));await Promise.all([old,fresh]);
assert.equal((await ctx.documentMapFile(widget,9,400,180)).id,9);
// A -> B -> A may reuse the same client object; an epoch, not identity alone,
// must guard old pending map results and receiver unsubscriptions.
const accountA=client;
const lateA=ctx.documentMapFile(widget,9,500,180),lateJob=requests.at(-1);
client={...client};const middle=ctx.documentMapFile(widget,9,500,180),middleJob=requests.at(-1);
client=accountA;const newA=ctx.documentMapFile(widget,9,500,180),newJob=requests.at(-1);
newJob.resolve(file(12));await newA;lateJob.resolve(file(11));middleJob.resolve(file(13));await Promise.all([lateA,middle]);
assert.equal((await ctx.documentMapFile(widget,9,500,180)).id,12);
let currentEvents=0;const oldOff=ctx.watchDocumentFile(file(99),()=>{});
client={...client};ctx.documentFileState(file(99));client=accountA;
const currentOff=ctx.watchDocumentFile(file(99),()=>currentEvents++);oldOff();
update({file:file(99,'/current-account')});assert.equal(currentEvents,1);currentOff();
let activity=0,pixels=0;
const off=ctx.watchDocumentFile(file(10),()=>activity++,true),offPixels=ctx.watchDocumentFile(file(10),()=>pixels++);
ctx.requestDocumentFile(file(10),24,true);const oldRequest=requests.at(-1);
assert.equal(activity,1);assert.equal(pixels,0);
ctx.cancelDocumentFile(file(10));const cancel=requests.at(-1);cancel.resolve({});await Promise.resolve();
assert.equal(activity,2);assert.equal(pixels,0);oldRequest.resolve(file(10,'/too-late'));await Promise.resolve();assert.equal(ctx.documentFileState(file(10)).path,'');
off();offPixels();
let opened=[],saved=[];
ctx.progressForOr=(_id,value)=>value;ctx.subscribeProgress=()=>()=>{};
Object.assign(ctx,{fileOpenMimeType:(_name,mime)=>mime,openLocalFile:async(_context,path)=>{opened.push(path);return true;},
 downloadSaveService:{saveDownloadedFile:(_context,path)=>saved.push(path),saveRemoteFile:(_context,id,chat,message)=>saved.push([id,chat,message])},showToast(){},$r:x=>x});
load(compiled+'pages/chat/DrawnDocumentFile.ts',['DrawnDocumentFile']);
const card=Object.create(ctx.DrawnDocumentFile.prototype),attachment=id=>({key:'f',kind:'file',file:file(id),name:'a.pdf',mimeType:'application/pdf',size:100});
Object.assign(card,{widget:attachment(20),chatId:3,messageId:45,visible:true,generation:0,off:null,path:'',failed:false,downloading:false,pending:'',opening:false,
 onClaim:()=>true,getUIContext:()=>({getHostContext:()=>({})})});
card.bind();card.tap(false);assert.equal(card.pending,'open');
card.widget=attachment(21);card.onSourceChanged();update({file:file(20,'/wrong')});assert.equal(opened.length,0);
card.tap(false);update({file:file(21,'/right')});await Promise.resolve();assert.deepEqual(opened,['/right']);
card.widget=attachment(22);card.onSourceChanged();card.tap(true);assert.deepEqual(saved,[[22,3,45]]);
card.aboutToDisappear();assert.equal(card.pending,'');
console.log('PASS: map single-flight/cache/account boundaries, zero-coordinate validation, file activity-only notifications, cancel generation, reuse-safe open intent and background-save delegation.');
// Embedded voice uses a disjoint playback namespace without relaxing the
// ordinary message API's invalid-ID check or retaining UI owners in playback.
load(root+'services/VoicePlayback.ets',['VoicePlayback']);
const playback=Object.create(ctx.VoicePlayback.prototype);const started=[];
playback.toggleCurrent=()=>false;playback.play=(...args)=>started.push(args);
playback.toggleDocumentVoice(31,'/voice',12);assert.equal(started.length,1);assert.equal(started[0][0],-31);assert.equal(started[0][3],'voice');
playback.toggle(-31,'/ordinary-invalid',12);assert.equal(started.length,1);
playback.toggleDocumentVoice(0,'/invalid',12);assert.equal(started.length,1);
const voices=[];ctx.getVoicePlayback=()=>({toggleDocumentVoice:(...args)=>voices.push(args)});
load(compiled+'pages/chat/DrawnDocumentVoice.ts',['DrawnDocumentVoice']);
const voice=Object.create(ctx.DrawnDocumentVoice.prototype);
Object.assign(voice,{widget:{...attachment(50),kind:'voice',duration:12},visible:true,generation:0,off:null,path:'',failed:false,loading:false,pending:false,onClaim:()=>true});
voice.bind();voice.request();voice.widget={...attachment(51),kind:'voice',duration:20};voice.onSourceChanged();
update({file:file(50,'/stale-voice')});assert.equal(voices.length,0);
voice.request();update({file:file(51,'/voice-51')});assert.deepEqual(voices,[[51,'/voice-51',20]]);
voice.aboutToDisappear();assert.equal(voice.pending,false);
console.log('PASS: embedded voice ID isolation, ordinary invalid-ID rejection, source ownership and deferred-play cancellation.');
load(compiled+'pages/chat/DrawnDocumentPostAuthor.ts',['DrawnDocumentPostAuthor']);
const post=Object.create(ctx.DrawnDocumentPostAuthor.prototype);
const author=id=>({kind:'post-author',key:'post',name:'Author',avatar:file(id)});
Object.assign(post,{widget:author(100),visible:true,generation:0,off:null,path:''});
post.bind();post.widget=author(101);post.onSourceChanged();update({file:file(100,'/old-author')});assert.equal(post.path,'');
update({file:file(101,'/new-author')});assert.equal(post.path,'/new-author');
post.aboutToDisappear();update({file:file(101,'/late-author')});assert.equal(post.path,'/new-author');
post.widget={kind:'post-author',name:'No photo'};post.onSourceChanged();assert.equal(post.path,'');
const badDate=ctx.drawnDocumentWidget({'@type':'pageBlockEmbeddedPost',date:Infinity},'post');assert.equal(badDate.date,0);
console.log('PASS: compiled embedded-post author clears reused image, ignores stale/detached file delivery and accepts missing avatar/date.');
load(compiled+'pages/chat/DrawnDocumentArticleImage.ts',['DrawnDocumentArticleImage']);
const articleImage=Object.create(ctx.DrawnDocumentArticleImage.prototype);
Object.assign(articleImage,{widget:author(200),visible:false,generation:0,off:null,path:''});
const beforeImageRequests=requests.length;articleImage.bind();assert.equal(requests.length,beforeImageRequests,'offscreen thumbnail must not start IO');
articleImage.visible=true;articleImage.bind();articleImage.widget=author(201);articleImage.onSourceChanged();
update({file:file(200,'/stale-article')});assert.equal(articleImage.path,'');
update({file:file(201,'/right-article')});assert.equal(articleImage.path,'/right-article');
articleImage.aboutToDisappear();update({file:file(201,'/late-article')});assert.equal(articleImage.path,'/right-article');
console.log('PASS: related thumbnail does no offscreen IO, clears old pixels and ignores stale/recycled/detached delivery.');

// The long-post document now shares the ordinary file preview. Only its
// thumbnail may be auto-requested, and reused owners reject stale thumb paths.
const thumbCard=Object.create(ctx.DrawnDocumentFile.prototype);
const thumbAttachment=(id,thumb)=>({...attachment(id),name:'clip.mp4',mimeType:'video/mp4',thumbnailFile:file(thumb),thumbnailMini:'mini'});
Object.assign(thumbCard,{widget:thumbAttachment(300,301),chatId:3,messageId:45,visible:false,generation:0,off:null,offThumb:null,offProgress:null,path:'',thumbnailPath:'',failed:false,downloading:false,pending:'',opening:false,onClaim:()=>true,getUIContext:()=>({getHostContext:()=>({})})});
const beforeThumb=requests.length;thumbCard.bind();assert.equal(requests.length,beforeThumb,'offscreen file cover performs no IO');
thumbCard.visible=true;thumbCard.bind();assert.equal(requests.at(-1).request.file_id,301,'request thumbnail, never full video');
update({file:file(301,'/thumb-a')});assert.equal(thumbCard.thumbnailPath,'/thumb-a');assert.equal(thumbCard.path,'');
thumbCard.widget=thumbAttachment(302,303);thumbCard.onSourceChanged();assert.equal(thumbCard.thumbnailPath,'');
update({file:file(301,'/stale-a')});assert.equal(thumbCard.thumbnailPath,'');
update({file:file(303,'/thumb-b')});assert.equal(thumbCard.thumbnailPath,'/thumb-b');
thumbCard.aboutToDisappear();update({file:file(303,'/late-b')});assert.equal(thumbCard.thumbnailPath,'/thumb-b');
console.log('PASS: actual compiled long-post cover subscription, thumbnail-only visible IO, reused and detached thumbnail callback rejection.');
