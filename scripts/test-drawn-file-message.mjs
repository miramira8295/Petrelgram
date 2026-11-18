import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const g=group('file caption https://example.org');
Object.assign(g.head,{contentType:'file',videoFileId:31,videoFileName:'sample.pdf',videoFileSize:900,videoMimeType:'application/pdf',videoPath:'',videoProgress:0,videoFailed:false,mediaDownloadActive:false});
const engine=new ctx.DrawnTextLayouts(),p=engine.prepare(ui,g,data,style);
assert.ok(p);assert.equal(p.caption.widgets.length,1);assert.equal(p.caption.widgets[0].widget.kind,'message-file');
const counts=layoutCounters();
for(let i=0;i<1000;i++){
 const next={...g,head:{...g.head,videoPath:i%2?'/ready':'',videoProgress:i%101,videoFailed:!!(i%2),mediaDownloadActive:!!(i%3),sendState:i%2?'sent':'sending'}};
 assert.equal(engine.prepare(ui,next,data,style),p,'transfer changes must retain row geometry');
}
assert.deepEqual(layoutCounters(),counts);
const empty={...g,head:{...g.head,text:'',textEntities:[]}};
assert.ok(engine.prepare(ui,empty,data,style),'captionless file still has a body');
const translated={...g,head:{...g.head,translatedText:'translated caption',translatedLang:'en',translatedEntities:[]}};
const translatedPlan=engine.prepare(ui,translated,data,{...style,replaceTranslation:true});
assert.equal(translatedPlan.caption.widgets.length,1,'replace translation cannot remove file controls');
for(const width of [160,240,400]){
 const plan=engine.prepare(ui,g,{...data,contentWidth:width},style);
 const widget=plan.caption.widgets[0];
 assert.ok(widget.width>0);assert.ok(widget.x+widget.width<=plan.caption.widthVp+.01);
}
// Real compiled local component: subscriptions belong to a physical owner and
// late callbacks cannot publish into a newly bound file.
const callbacks=new Map();let off=0;
ctx.progressForOr=(_id,fallback)=>fallback;
ctx.subscribeProgress=(id,fn)=>{callbacks.set(id,fn);return ()=>off++;};
load(compiled+'pages/chat/DrawnFileMessage.ts',['DrawnFileMessage']);
const local=Object.assign(Object.create(ctx.DrawnFileMessage.prototype),{msg:g.head,active:true,generation:0,off:null,progress:0});
local.bind();const old=callbacks.get(31);old(44);assert.equal(local.progress,44);
local.msg={...g.head,id:2,videoFileId:32,videoProgress:7};local.bind();old(99);assert.equal(local.progress,7);
callbacks.get(32)(55);assert.equal(local.progress,55);
local.aboutToRecycle();callbacks.get(32)(88);assert.equal(local.progress,55);assert.equal(off,2);
console.log('PASS: file row caption/translation, 1000 transfer updates without layout, narrow widths, compiled progress subscriptions and stale callback guards.');
// Route is explicit and fallback must remain a FILE row when switches are off.
const rowSource=fs.readFileSync(root+'pages/chat/DrawnMessageRow.ets','utf8');
assert.match(rowSource,/if \(this\.rowGroup\.head\.contentType === 'file' \|\| this\.rowGroup\.head\.contentType === 'audio' \|\| this\.rowGroup\.head\.contentType === 'voice' \|\| this\.rowGroup\.head\.contentType === 'contact' \|\| this\.rowGroup\.head\.contentType === 'location' \|\| this\.rowGroup\.head\.contentType === 'venue' \|\| this\.rowGroup\.head\.contentType === 'poll' \|\| this\.rowGroup\.head\.contentType === 'videoNote' \|\| this\.rowGroup\.head\.contentType === 'dice' \|\| this\.rowGroup\.head\.contentType === 'game' \|\| this\.rowGroup\.head\.contentType === 'paidMedia' \|\| this\.rowGroup\.head\.contentType === 'gift' \|\| this\.rowGroup\.head\.contentType === 'giveaway'\) \{\s*MessageBubble\(/);
const policy=fs.readFileSync(root+'util/drawnTextRowPolicy.ets','utf8');
assert.match(policy,/contentType === 'file'/);
const routing=fs.readFileSync(root+'pages/chat/ReusableMessageBubble.ets','utf8');
assert.match(routing,/contentType === 'richMessage' \|\| this\.shownGroup\.head\.contentType === 'file'/);
console.log('PASS: file route preserves legacy file behavior when drawn plan is unavailable.');
