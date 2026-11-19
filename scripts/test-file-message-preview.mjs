import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,group,ui,data,style,layoutCounters} from './test-drawn-text-row.mjs';
load(root+'util/formatMsgContent.ets',['formatMsgContent']);
const file=(id,path='')=>({id,size:900,local:{path,is_downloading_completed:path!=='',downloaded_size:path?900:0}});
const document=(name,mime,thumb,mini)=>({content:{'@type':'messageDocument',document:{document:file(31,'/local'),file_name:name,mime_type:mime,thumbnail:thumb,minithumbnail:mini},caption:{text:'',entities:[]}}});
for(const [name,mime,kind] of [['one.mp4','video/mp4','video'],['two.HEIC','application/octet-stream','image'],['three.heif','','image'],['archive.zip','application/zip','']]){
 assert.equal(ctx.filePreviewKind(name,mime),kind);
 const parsed=ctx.formatMsgContent(document(name,mime,{file:file(5,'/thumb'),width:120,height:90},{data:'abc'}));
 assert.equal(parsed.contentType,'file');assert.equal(parsed.photoFileId,5);assert.equal(parsed.photoLocalPath,'/thumb');assert.equal(parsed.photoWidth,120);assert.equal(parsed.photoHeight,90);assert.equal(parsed.photoMini,'data:image/jpeg;base64,abc');assert.equal(parsed.videoFileId,31);assert.equal(parsed.videoLocalPath,'/local');assert.equal(parsed.photoFullFileId,0,'never register original file as automatic photo download');
}
const noThumb=ctx.formatMsgContent(document('local.mp4','video/mp4'));assert.equal(noThumb.photoFileId,0);assert.equal(noThumb.photoLocalPath,'');
const g=group('');Object.assign(g.head,{contentType:'file',videoFileName:'clip.mp4',videoMimeType:'video/mp4',videoFileId:31,videoFileSize:900});
const layouts=new ctx.DrawnTextLayouts(),plan=layouts.prepare(ui,g,data,style),slot=plan.caption.widgets[0];assert.equal(slot.height,91,'86vp preview + actual padding');assert.equal(plan.caption.source.blocks.length,1);
const counts=layoutCounters();for(let i=0;i<1000;i++)assert.equal(layouts.prepare(ui,{...g,head:{...g.head,videoPath:'/ready',photoPath:'/cover'+i,videoProgress:i%100}},data,style),plan);assert.deepEqual(layoutCounters(),counts);
// Execute the compiled component's lifecycle and actual computed source selection.
const subscriptions=[],requests=[];let released=0;
ctx.posterFor=()=>'';ctx.subscribePoster=(path,fn)=>{subscriptions.push({path,fn});return()=>released++;};ctx.requestPoster=(...args)=>requests.push(args);ctx.ImageFit={Cover:1};
load(compiled+'pages/chat/FileMessagePreview.ts',['FileMessagePreview']);
const source=(id,path,kind='video',thumbnailId=0,thumbnailPath='',mini='')=>({fileId:id,filePath:path,fileSize:900,kind,thumbnailId,thumbnailPath,mini});
const s=source(1,'/a'),c=Object.assign(Object.create(ctx.FileMessagePreview.prototype),{source:s,boxSize:86,poster:'',active:false,visible:false,generation:0,bound:null,off:null,requested:false,specs:{prepare:s=>s}});
c.aboutToAppear();assert.equal(requests.length,0,'no decoding in offscreen creation');c.visible=true;c.attach();assert.equal(requests.length,1);for(let i=0;i<1000;i++)c.attach();assert.equal(requests.length,1,'same visible source requests once');const first=subscriptions[0];first.fn('/poster-a');assert.equal(c.imageSpec.initialPath,'/poster-a');
c.source=source(2,'/b');c.changed();assert.equal(c.poster,'');first.fn('/stale-a');assert.equal(c.poster,'');const second=subscriptions.at(-1);second.fn('/poster-b');assert.equal(c.imageSpec.initialPath,'/poster-b');
c.source=s;c.changed();second.fn('/late-b');assert.equal(c.poster,'');assert.equal(c.imageSpec.initialPath,'');c.aboutToRecycle();subscriptions.at(-1).fn('/late-detached');assert.equal(c.poster,'');
c.source=source(3,'/image','image');c.aboutToReuse();assert.equal(c.imageSpec.initialPath,'/image');assert.equal(c.imageSpec.fileId,0,'local originals use path identity, not a thumbnail channel');
c.source=source(4,'/video','video',9,'/thumb','mini');c.changed();assert.equal(c.imageSpec.fileId,9);assert.equal(c.imageSpec.initialPath,'/thumb');const requestCount=requests.length;c.visible=true;c.attach();assert.equal(requests.length,requestCount,'server thumbnail avoids local frame extraction');c.aboutToDisappear();assert.ok(released>=3);
console.log('PASS: document thumbnail/minithumbnail/local-state parsing, original file download isolation, Android-size cover geometry, 1000 stable updates, compiled visible-only poster/decode ownership and A-B-A/recycle guards.');
// Replay the actual compiled parent parameter and child's initialRender. A bare
// @Builder method is rebound to the child by ArkUI; it then has no controlPainter.
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const parentPath=process.env.FILE_PREVIEW_PARENT_COMPILED||compiled+'pages/chat/FileBubble.ts';
load(parentPath,['FileBubble']);
const parentText=fs.readFileSync(parentPath,'utf8');
const ast=ts.createSourceFile('FileBubble.ts',parentText,ts.ScriptTarget.Latest,true);
let previewParams;
function findParams(node){
 if(ts.isNewExpression(node)&&node.expression.getText(ast)==='FileMessagePreview')previewParams=node.arguments[1].getText(ast);
 ts.forEachChild(node,findParams);
}
findParams(ast);assert.ok(previewParams,'compiled parent must construct file preview');
vm.runInContext(ts.transpileModule(`globalThis.makePreviewParams=function(){return ${previewParams};};`,
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const paintCalls=[],nodeCalls=[];
ctx.Stack=new Proxy({},{get:(_o,key)=>(...args)=>nodeCalls.push({key,args})});
ctx.If={create(){},pop(){}};ctx.Image=new Proxy({},{get:()=>()=>{}});
ctx.LiveThumbImage=class{};ctx.ViewV2.create=()=>{};
const parent=Object.assign(Object.create(ctx.FileBubble.prototype),{
 fileId:7,filePath:'',fileName:'first',uploading:false,downloadActive:false,downloadProgress:0,
 downloadFailed:false,controlPainter:{bind(...args){paintCalls.push(args);return this;}},
 getUIContext:()=>ui,visual:()=>({color:'#123456'}),tileLabel(){return this.fileName;},
 observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_i,fn)=>fn()
});
Object.defineProperties(parent,{tileSize:{value:86},paintEnvironment:{value:'env'},previewSource:{get(){return source(7,'','image');}}});
const params=ctx.makePreviewParams.call(parent);
c.placeholder=params.placeholder;c.observeComponentCreation2=fn=>fn(1,true);c.ifElseBranchUpdateFunction=(_i,fn)=>fn();
for(const kind of ['image','video']){
 for(const phase of ['initial','reuse']){
  parent.fileName=kind+'-'+phase;
  c.source=source(kind==='image'?7:8,'',kind);c.poster='';
  const before=paintCalls.length;c.initialRender();
  assert.equal(paintCalls.length,before+1,'missing mini must draw exactly one parent placeholder');
  assert.equal(paintCalls.at(-1)[8],parent.fileName,'callback must read current parent state after reuse');
 }
}
const beforeMini=paintCalls.length;c.source=source(9,'','image',1,'','mini');c.initialRender();
assert.equal(paintCalls.length,beforeMini,'embedded mini bypasses the placeholder');
for(let i=0;i<1000;i++){parent.fileName='reused-'+i;c.placeholder.call(c);}
assert.equal(paintCalls.length,beforeMini+1000,'one paint per invocation, no retained content snapshot');
assert.equal(paintCalls.at(-1)[8],'reused-999');
console.log('PASS: compiled FileBubble → FileMessagePreview no-mini image/video creation, current-state reuse, mini bypass, and 1000 constant-work callbacks.');
