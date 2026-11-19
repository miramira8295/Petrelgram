import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,ui,data,style,group,layoutCounters,load,root} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.chromeAPI={drawnChromeTextSupported,drawnRowChromeReason,DrawnSenderHeaderCache,DrawnReplyQuoteCache};',ctx);
const {drawnChromeTextSupported,drawnRowChromeReason}=ctx.chromeAPI;
for(const value of ['', 'x'.repeat(20000), 'مرحبا\t👩‍👩‍👧‍👦\n'.repeat(1000)])assert.equal(drawnChromeTextSupported(value),true);
for(const value of [null,undefined,0,{},[]])assert.equal(drawnChromeTextSupported(value),false,'untrusted non-string metadata is rejected before native shaping');
const text='long chrome 👩‍👩‍👧‍👦\t'.repeat(1000),g=group('body');
Object.assign(g.head,{senderName:text,senderTag:text,replyToMessageId:9,replySenderName:text,replyText:text,forwardFrom:text});
const renderData={...data,isGroup:true};assert.equal(drawnRowChromeReason(g,renderData,text),ctx.DrawnRouteReason.Drawn);
const engine=new ctx.DrawnTextLayouts(),plan=engine.prepare(ui,g,renderData,{...style,role:text});assert.ok(plan);assert.ok(plan.header);assert.ok(plan.quote);assert.ok(plan.chrome);
assert.equal(plan.header.name.paragraph.content,text);assert.equal(plan.header.role.paragraph.content,text);assert.equal(plan.quote.sender.paragraph.content,text);assert.equal(plan.quote.excerpt.paragraph.content,text);
for(const line of [plan.header.name,plan.header.role,plan.quote.sender,plan.quote.excerpt]){assert.equal(line.paragraph.style.maxLines,1);assert.equal(line.paragraph.style.textStyle.ellipsis,'…');}
assert.ok(plan.header.widthPx<=plan.width*2);assert.ok(plan.quote.widthPx<=plan.width*2);
const before=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,g,renderData,{...style,role:text}),plan);assert.deepEqual(layoutCounters(),before,'stable status inputs do not reshape long chrome');
for(const f of ['albumGeometryCache','albumCellRenderData'])load(root+'util/'+f+'.ets');
for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout'])load(root+'pages/chat/'+f+'.ets',f==='DrawnMediaLayout'?['DrawnMediaLayouts']:[]);
for(const single of [true,false]){
 const media=group('caption');Object.assign(media.head,g.head,{contentType:'photo',photoWidth:160,photoHeight:120,photoFileId:1,photoPath:''});
 Object.assign(media,{caption:'caption',captionEntities:[],memberIds:single?[10]:[10,11],photoRatios:single?[1]:[1,1],photoPaths:[],photoFileIds:single?[1]:[1,2],photoMinis:[],photoProgress:[],photoFailed:[],photoIsVideo:[],photoIsLive:[],videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[]});
 assert.equal(drawnRowChromeReason(media,renderData,text),ctx.DrawnRouteReason.Drawn);
 const mediaEngine=new ctx.DrawnMediaLayouts(single),p=mediaEngine.prepare(ui,media,renderData,{...style,role:text});assert.ok(p);assert.ok(p.header);assert.ok(p.quote);const stable=layoutCounters();
 for(let i=0;i<1000;i++)assert.equal(mediaEngine.prepare(ui,media,renderData,{...style,role:text}),p);assert.deepEqual(layoutCounters(),stable);
}
const changed={...g,head:{...g.head,replyText:'edited reply'}};const edited=engine.prepare(ui,changed,renderData,{...style,role:text});assert.notEqual(edited.quote,plan.quote);assert.equal(edited.header,plan.header);assert.equal(edited.caption,plan.caption);
console.log('PASS: complete >4096-character sender/role/forward/reply text stays drawn for text/photo/album, single-line ellipsis and width budgets retained, 3000 cache hits without shaping, independent edits and invalid runtime type guards.');
