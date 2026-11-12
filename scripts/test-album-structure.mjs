// Compiled component control-flow regression. No claim about device layout time.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE || 'typescript'); const ts=imported.default||imported;
const base='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
let nodes=[],current,children=[];
class ViewV2 {
  initParam(k,v){this[k]=v} resetParam(k,v){this[k]=v} finalizeConstruction(){} resetMonitorsOnReuse(){}
  observeComponentCreation2(fn,type){const old=current;current={type:type.name};nodes.push(current);fn(nodes.length,true);current=old;}
  ifElseBranchUpdateFunction(_id,fn){fn();}
  static create(child){children.push(child);}
}
function node(name){return new Proxy({name},{get:(target,key)=>key==='name'?name:(...args)=>{if(key!=='pop'&&current)current[key]=args[0];}});}
const ctx=vm.createContext({ViewV2,ViewPU:class{},Color:{White:'white'},FontWeight:{Medium:1},ImageFit:{Cover:0},
  HitTestMode:{None:0},Alignment:{TopEnd:0},TextOverflow:{Ellipsis:0},
  Stack:node('Stack'),Row:node('Row'),If:node('If'),Text:node('Text'),__Common__:node('Common'),
  Circle:node('Circle'),SymbolGlyph:node('SymbolGlyph'),Column:node('Column'),
  LiveThumbImage:class {constructor(_parent,args){this.kind='thumb';this.args=args;}},
  VideoBubbleSurface:class {constructor(_parent,args){this.kind='video';this.args=args;}},
  LiveProgressRing:class {constructor(_parent,args){this.kind='progress';this.args=args;}},
  PLAY_SLOT_ENTER_RATIO:.6,PLAY_SLOT_KEEP_RATIO:.3,chatEnv:{langEpoch:0},
  thumbBackdropColor:video=>video?'video':'photo',miniPlaceholderOf:x=>x,
  formatFileSize:x=>String(x),formatMediaDuration:x=>String(x),str:(key,n)=>`${key}:${n}`,$r:x=>x});
function load(file,name){let s=fs.readFileSync(base+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/@(?:Param|Event|Local|Computed)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s+`\nglobalThis.${name}=${name};`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('pages/chat/AlbumCellView.ts','AlbumCellView');
let claimed=false,tapped=[],ratios=[],centers=[];
const actions={onMediaTap:(id,x,y)=>tapped.push([id,x,y]),onMediaRatio:(...a)=>ratios.push(a),onMediaGone:(...a)=>ratios.push(a),onSpecialPhotoRetry:id=>tapped.push(['retry',id])};
const hooks={isClaimed:()=>claimed,onToggleMember:id=>tapped.push(['select',id]),centerYOf:()=>42,onCenterY:(...a)=>centers.push(a)};
const cell={idx:0,width:100,height:80,chatId:1,messageId:2,thumbFileId:7,thumbPath:'/a',mini:'',isVideo:false,isLive:false,uploading:false,failed:false,isPlaySlot:false,videoFileId:10,inlineFileId:0,videoDuration:0,videoFileSize:0,selectionActive:false};
const v=new ctx.AlbumCellView(null,{cell,actions,hooks});
function render(){nodes=[];children=[];v.initialRender();return {nodes,children};}
const photo=render();assert.equal(photo.nodes.filter(n=>n.type==='Stack').length,1);
assert.equal(photo.nodes.filter(n=>n.onVisibleAreaApproximateChange).length,0);
assert.equal(photo.nodes.find(n=>n.type==='Stack').geometryTransition,'media_1_2');
assert.equal(photo.children.filter(c=>c.kind==='thumb').length,1);
const cached=v.thumbSpec();assert.equal(v.thumbSpec(),cached);
v.cell={...cell,isVideo:true};const video=render();
assert.equal(video.nodes.filter(n=>n.type==='Stack').length,1);
assert.equal(video.nodes.find(n=>n.type==='Stack').geometryTransition,'');
assert.equal(video.nodes.filter(n=>n.onVisibleAreaApproximateChange).length,1);
assert.equal(video.children.filter(c=>c.kind==='thumb').length,1);
assert.equal(video.children.some(c=>c.kind==='gate'),false);
const observed=v.cell, oldRatio=v.videoRatioCallback(observed), oldArea=v.videoAreaCallback(observed);
oldRatio(true,.8);assert.deepEqual(ratios.pop(),[2,0,.8,42]);
oldArea({}, {globalPosition:{y:100},height:80});assert.deepEqual(centers.pop(),[0,140]);
v.cell={...observed,messageId:3};oldRatio(true,.9);oldArea({}, {globalPosition:{y:300},height:80});
assert.equal(ratios.length,0);assert.equal(centers.length,0,'old slot geometry cannot update the new message');
v.cell={...observed,width:50};oldRatio(true,.9);assert.equal(ratios.length,0,'old size observation is ignored');
v.cell={...cell,isVideo:true,thumbFileId:0,thumbPath:''};const missing=render();
assert.equal(missing.children.filter(c=>c.kind==='thumb').length,1,'missing source retains the same thumbnail owner');
assert.equal(missing.children[0].args.spec.readyWithoutPath,true);
v.cell={...cell,isVideo:true,failed:true};assert.equal(v.thumbSpec().readyWithoutPath,true);
v.cell={...cell,isVideo:true,isPlaySlot:true};assert.equal(render().children.filter(c=>c.kind==='video').length,1);
v.cell=cell;v.onCellTap({windowX:3,windowY:4});assert.deepEqual(tapped.pop(),[2,3,4]);
claimed=true;v.onCellTap({windowX:3,windowY:4});assert.equal(tapped.length,0);claimed=false;
v.cell={...cell,selectionActive:true};v.onCellTap({});assert.deepEqual(tapped.pop(),['select',2]);
v.cell={...cell,idx:-1};assert.equal(render().children.length,0);
// The one Stack creation site is shared across photo/video updates. Native
// recycling still needs device verification; the test cannot simulate ArkUI.
const method=ctx.AlbumCellView.prototype.initialRender.toString();
assert.equal((method.match(/Stack\.create\(/g)||[]).length,1);
console.log('PASS: one shared cell host, photo/video/missing/failed/playing/sentinel dispatch, video-only observation, transition reset, click/selection/claim behavior.');
