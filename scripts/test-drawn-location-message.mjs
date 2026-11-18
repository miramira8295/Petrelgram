import assert from 'node:assert/strict';
import {ctx,load,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const g=group('');
Object.assign(g.head,{contentType:'location',locationLatitude:0,locationLongitude:0,locationValid:true,
 locationLivePeriod:3600,locationExpiresIn:100,venueTitle:'',venueAddress:'',date:100});
const engine=new ctx.DrawnTextLayouts(),d={...data,liveSharingId:0},p=engine.prepare(ui,g,d,style);
assert.ok(p);assert.equal(p.caption.widgets[0].widget.kind,'message-location');
const counts=layoutCounters();
for(let i=0;i<1000;i++) {
 const next={...g,head:{...g.head,locationLatitude:i/100,locationLongitude:-i/100,locationExpiresIn:i%100,locationAccuracy:i,sendState:i%2?'sent':'sending'}};
 assert.equal(engine.prepare(ui,next,d,style),p,'coordinates/countdown do not invalidate document layout');
}
assert.deepEqual(layoutCounters(),counts);
const shared=engine.prepare(ui,g,{...d,liveSharingId:g.head.id},style);
assert.equal(shared.caption.widgets[0].height,245);assert.ok(shared.height>p.height);
assert.equal(p.caption.widgets[0].height,180,'published geometry must not be mutated');
assert.equal(engine.prepare(ui,g,d,style).caption.widgets[0].height,180);
for(const width of [160,240,400]) {
 const plan=engine.prepare(ui,{...g,head:{...g.head,contentType:'venue',venueTitle:'Cafe',venueAddress:'Road'}},{...d,contentWidth:width},style);
 assert.ok(plan.caption.widgets[0].width<=plan.caption.widthVp+.01);
}
load(compiled+'pages/chat/DrawnLocationMessage.ts',['DrawnLocationMessage']);
const calls=[];let stops=0;
const local=Object.assign(Object.create(ctx.DrawnLocationMessage.prototype),{msg:g.head,sharing:true,onClaim:()=>false,
 actions:{onLocationOpen:(...args)=>calls.push(args),onStopLiveLocation:()=>stops++}});
local.openLocation();local.stopSharing();assert.equal(calls.length,0);assert.equal(stops,0);
local.onClaim=()=>true;local.openLocation();assert.deepEqual(calls.pop(),[0,0,'',true]);
local.msg={...g.head,locationLatitude:22,locationLongitude:33,venueTitle:' Cafe ',venueAddress:' Road '};
local.openLocation();assert.deepEqual(calls.pop(),[22,33,'Cafe，Road',true]);
local.stopSharing();assert.equal(stops,1);local.sharing=false;local.stopSharing();assert.equal(stops,1);
load(compiled+'pages/chat/LocationBubble.ts',['LocationBubble']);
const bubble=Object.assign(Object.create(ctx.LocationBubble.prototype),{livePeriod:3600,expiresIn:100,messageDate:100,nowSec:200,latitude:22,longitude:33});
assert.equal(bubble.liveActive(),true);bubble.expiresIn=0;assert.equal(bubble.liveActive(),false,'early stop wins over original duration');
bubble.expiresIn=100;bubble.nowSec=3700;assert.equal(bubble.liveActive(),false,'expiry boundary');
console.log('PASS: location/venue row, 1000 coordinate/expiry updates without paragraph layout, sharing height immutable, narrow widths, current action targets, selection and early stop/expiry.');
// Exercise the actual shared map receiver: an old coordinate request must not
// publish after the same physical location card has been rebound.
const jobs=[],listeners=new Map();let downloads=0,offs=0;
ctx.documentMapFile=(widget)=>new Promise(resolve=>jobs.push({widget,resolve}));
ctx.documentFileState=file=>({path:file.path});
ctx.watchDocumentFile=(file,fn)=>{listeners.set(file.id,fn);return()=>offs++;};
ctx.requestDocumentFile=()=>downloads++;
ctx.THUMBNAIL_PRIORITY=24;
load(compiled+'pages/chat/DrawnDocumentMap.ts',['DrawnDocumentMap']);
const map=Object.assign(Object.create(ctx.DrawnDocumentMap.prototype),{widget:{latitude:1},chatId:1,boxWidth:200,boxHeight:104,visible:true,generation:0,off:null,path:''});
map.bind();map.widget={latitude:2};map.bind();
jobs[1].resolve({id:2,path:'/current'});await Promise.resolve();
jobs[0].resolve({id:1,path:'/stale'});await Promise.resolve();
assert.equal(map.path,'/current');assert.equal(downloads,1);
listeners.get(2)({path:'/downloaded'});assert.equal(map.path,'/downloaded');
map.aboutToDisappear();listeners.get(2)({path:'/late'});
assert.equal(map.path,'/downloaded');assert.equal(offs,1);
console.log('PASS: actual map receiver rejects stale coordinates and detached file callbacks.');
