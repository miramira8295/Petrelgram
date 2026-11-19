import assert from 'node:assert/strict';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const g=group('audio caption');Object.assign(g.head,{contentType:'audio',audioTitle:'Song',audioPerformer:'Artist',videoFileId:18,videoPath:'',videoProgress:0});
const engine=new ctx.DrawnTextLayouts(),p=engine.prepare(ui,g,data,style),count=layoutCounters();
assert.equal(p.caption.widgets[0].widget.kind,'message-audio');
for(let i=0;i<1000;i++){
 const next={...g,head:{...g.head,videoProgress:i%100,videoPath:i%2?'/music':'',mediaDownloadActive:!!(i%2),photoPath:`/cover${i}`}};
 assert.equal(engine.prepare(ui,next,{...data,audioQueuePosition:i},style),p);
}
assert.deepEqual(layoutCounters(),count);
assert.equal(engine.prepare(ui,{...g,head:{...g.head,text:''}},data,style).caption.widgets.length,1);
const callbacks=new Map();let unsubs=0;
ctx.progressForOr=(_id,n)=>n;ctx.subscribeProgress=(id,fn)=>{callbacks.set(id,fn);return()=>unsubs++;};
load(compiled+'pages/chat/DrawnAudioMessage.ts',['DrawnAudioMessage']);
const local=Object.assign(Object.create(ctx.DrawnAudioMessage.prototype),{msg:g.head,active:true,generation:0,off:null,progress:0});
local.bind();const stale=callbacks.get(18);stale(20);assert.equal(local.progress,20);
local.msg={...g.head,id:2,videoFileId:19,videoProgress:3};local.bind();stale(90);assert.equal(local.progress,3);
local.aboutToRecycle();callbacks.get(19)(77);assert.equal(local.progress,3);assert.equal(unsubs,2);
// Exercise compiled seek handling with empty UP touches and cancelled gestures.
load(compiled+'pages/chat/MusicBubble.ts',['MusicBubble']);
ctx.TouchType={Down:0,Move:1,Up:2,Cancel:3};
const seeks=[];const music=Object.assign(Object.create(ctx.MusicBubble.prototype),{currentTrack:()=>true,resolvedDuration:()=>100,dragging:false,onBeforeSeek:()=>true,setClock(){},onSeek:n=>seeks.push(n)});
Object.defineProperty(music,'waveWidth',{value:100});
music.onWaveTouch({type:0,touches:[{x:10}],changedTouches:[]});
music.onWaveTouch({type:2,touches:[],changedTouches:[{x:70}]});assert.deepEqual(seeks,[.7]);
music.onWaveTouch({type:0,touches:[{x:10}],changedTouches:[]});music.onWaveTouch({type:3,touches:[],changedTouches:[]});assert.deepEqual(seeks,[.7]);
music.onBeforeSeek=()=>false;music.onWaveTouch({type:0,touches:[{x:10}],changedTouches:[]});music.onWaveTouch({type:2,touches:[],changedTouches:[{x:90}]});assert.deepEqual(seeks,[.7]);
console.log('PASS: audio controls/caption source, 1000 transfer/cover/queue updates retain layout, compiled lifecycle and seek cancel/selection/empty-UP handling.');
