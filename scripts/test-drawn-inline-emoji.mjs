// Actual parser/layout/painter code; deterministic shaping and cache session
// doubles test offsets/lifecycle/operation counts, not real device timings.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.DrawnRichTextLayouts = DrawnRichTextLayouts',ctx);
const entity=(kind,offset,length,more={})=>({offset,length,type:{'@type':'textEntityType'+kind,...more}});
const content='😀 one 👩‍💻 two 🎬';
const entities=[entity('CustomEmoji',0,2,{custom_emoji_id:'a'}),entity('TextUrl',3,3,{url:'https://one.test'}),
  entity('CustomEmoji',7,5,{custom_emoji_id:'b'}),entity('TextUrl',13,3,{url:'https://two.test'}),
  entity('CustomEmoji',17,2,{custom_emoji_id:'a'}),entity('TextUrl',17,2,{url:'https://icon.test'})];
const sources=new ctx.DrawnRichSourceCache(),source=sources.prepare(content,entities);
assert.ok(source);assert.equal(source.content,content);assert.equal(source.links[1].start,13);
const layouts=new ctx.DrawnRichTextLayouts();
const spec={source,maxWidthVp:320,minWidthVp:0,fontSize:16,reserve:' 12:00 ',foreground:'black',accent:'blue',environment:'1'};
const plan=layouts.prepare(ui,spec);
assert.equal(plan.emojis.length,3);assert.deepEqual(Array.from(plan.emojis,e=>e.id),['a','b','a']);
assert.equal(plan.paragraph.getRectsForPlaceholders().length,3);
// Original lengths 2/5/2 become 1/1/1. Every link uses its projected offset,
// while its payload remains original UTF-16 for copy/accessibility/confirmation.
const boxes=plan.paragraph.getRectsForRange({start:8,end:11});
assert.equal(plan.hits.find(h=>h.link.url==='https://two.test').x,boxes[0].rect.left/2);
assert.equal(plan.hits.find(h=>h.link.url==='https://icon.test').x,plan.emojis[2].rect.left/2);
const end=plan.paragraph.boxes.at(-1).rect.right/2;
assert.ok(plan.widthVp>=end,'time reserve uses projected text length');
assert.equal(plan.source.links[2].label,'🎬');
const before=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(layouts.prepare(ui,spec),plan);
assert.deepEqual(layoutCounters(),before);
// The whole text row stays drawn; custom emoji no longer makes its plan null.
const row=new ctx.DrawnTextLayouts().prepare(ui,group(content,entities),data,style);
assert.ok(row);assert.equal(row.caption.emojis.length,3);
// Use the real media layout path too, not only the shared rich paragraph.
for(const file of ['packAlbumRows','albumCellRenderData'])load(root+'util/'+file+'.ets');
for(const file of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout'])
  load(root+'pages/chat/'+file+'.ets',file==='DrawnMediaLayout'?['DrawnMediaLayouts']:[]);
const album={...group(),caption:content,captionEntities:entities,memberIds:[10,11,12],
  photoRatios:[1,.6,1.5],photoPaths:[],photoFileIds:[1,2,3],photoMinis:[],photoProgress:[],photoFailed:[],
  photoIsVideo:[],photoIsLive:[],videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[]};
const albumCache=new ctx.DrawnMediaLayouts(false),albumPlan=albumCache.prepare(ui,album,data,style);
assert.equal(albumPlan.caption.emojis.length,3);
const single=group(content,entities);Object.assign(single.head,{contentType:'photo',photoFileId:5,
  photoWidth:400,photoHeight:300,photoPath:'',photoMini:'',photoProgress:0,photoFailed:false});
assert.equal(new ctx.DrawnMediaLayouts(true).prepare(ui,single,data,style).caption.emojis.length,3);
const mediaBefore=layoutCounters();
const loadedAlbum={...album,captionMessage:{inlineCustomEmojiIds:['a','b'],inlineCustomEmojiPaths:['/a.png','/b.png']}};
assert.equal(albumCache.prepare(ui,loadedAlbum,data,style).caption,albumPlan.caption);
assert.equal(layoutCounters().bodyLayouts,mediaBefore.bodyLayouts,'asset hydration retains caption paragraph');
// Repeated glyph fallback paragraphs are prepared once per glyph/color style.
const repeatedSource=sources.prepare('😀😀😀',[0,2,4].map(i=>entity('CustomEmoji',i,2,{custom_emoji_id:'a'})));
const repeated=layouts.prepare(ui,{...spec,source:repeatedSource,reserve:''});
assert.equal(repeated.emojis[0].fallback,repeated.emojis[2].fallback);
const narrow=layouts.prepare(ui,{...spec,maxWidthVp:60,reserve:''});
assert.ok(narrow.emojis[2].rect.top>narrow.emojis[0].rect.top);
let invalidations=0,updates=0,brushes=0,draws=0,fallbacks=0;
const sessions=[];
ctx.DrawModifier=class{invalidate(){invalidations++;}};
ctx.ImageFit={Contain:1,Cover:2};
ctx.drawing.Brush=class{constructor(){brushes++;}setColorFilter(f){this.filter=f;}};
ctx.drawing.ColorFilter={createBlendModeColorFilter:(c,m)=>({c,m})};ctx.drawing.BlendMode={SRC_IN:1};
ctx.drawing.SamplingOptions=class{};ctx.drawing.FilterMode={FILTER_MODE_LINEAR:1};
ctx.CachedImageSession=class{
  constructor(publish){this.publish=publish;this.disposed=false;sessions.push(this);}
  activate(spec){this.spec=spec;updates++;}
  update(spec){this.spec=spec;updates++;if(!spec.path)this.publish(undefined,false);}
  dispose(){this.disposed=true;}
};
load(root+'util/inlineCustomEmojiPaint.ets');
load(compiled+'pages/common/DrawnImageReceiver.ts');
load(compiled+'pages/chat/DrawnInlineEmojiPainter.ts',['DrawnInlineEmojiPainter']);
const painter=new ctx.DrawnInlineEmojiPainter(),ids=['a','b'],paths=['/a.png','/b.png'],tints=[false,true];
painter.bind(ui,plan,ids,paths,tints);
assert.equal(sessions.length,2,'repeat ID shares one cache session');assert.equal(updates,2);
assert.equal(sessions[0].spec.path,'/a.png');assert.equal(sessions[1].spec.opaque,false);
const counts={updates,brushes,invalidations};
for(let i=0;i<1000;i++)painter.bind(ui,plan,ids,paths,tints);
assert.deepEqual({updates,brushes,invalidations},counts,'warm binding is O(1), no native allocations');
const savedLayouts=layoutCounters();
for(const e of plan.emojis)e.fallback.paint=()=>{fallbacks++;};
let attached=0;const canvas={save(){},restore(){},translate(){},attachBrush(){attached++;},detachBrush(){},drawImageRectWithSrc(){draws++;}};
painter.drawFront({canvas});assert.equal(fallbacks,3,'undownloaded custom glyph retains Unicode fallback');
const pixel={getImageInfoSync(){throw Error('provided metadata should be reused');}};
sessions[0].publish(pixel,true,30,30);sessions[1].publish({},true,40,20);
assert.deepEqual(layoutCounters(),savedLayouts,'bitmap completion must not shape/parse anything');
painter.drawFront({canvas});assert.equal(draws,3);assert.equal(attached,1,'only repaintable emoji gets tint');
const changedPaths=['/a-new.png','/b.png'];painter.bind(ui,plan,ids,changedPaths,[true,true]);
assert.equal(sessions.length,2);assert.equal(brushes,counts.brushes,'asset-only update keeps paint geometry and brushes');
painter.drawFront({canvas});assert.equal(attached,4,'same ID used at multiple colors receives each placement tint');
painter.bind(ui,repeated,ids,paths,tints);assert.equal(sessions[1].disposed,true,'removed unique ID releases its session');
// Theme changes replace tint/paragraph geometry but preserve shared image owners.
const theme=layouts.prepare(ui,{...spec,environment:'theme-2'});
const sessionCount=sessions.length;painter.bind(ui,theme,ids,paths,tints);
assert.equal(sessions.length,sessionCount+1,'only previously removed b is reacquired');
painter.dispose();assert.ok(sessions.every(s=>s.disposed));
const oldInvalidations=invalidations;for(const session of sessions)session.publish(pixel,true,30,30);
assert.equal(invalidations,oldInvalidations,'disposed owner ignores stale callback');
const oldDraws=draws;painter.drawFront({canvas});assert.equal(draws,oldDraws,'no released handle remains drawable');
painter.bind(ui,plan,ids,paths,tints);assert.equal(sessions.length,5,'A/B/A mount owns fresh sessions');
painter.dispose();
// Both full-row and native-shell rich blocks use exactly one shared layer.
for(const file of ['DrawnMessageRow','DrawnRichTextView']){
 const source=fs.readFileSync(root+'pages/chat/'+file+'.ets','utf8');assert.ok(source.includes('DrawnInlineEmojiLayer({'));
}
const layer=fs.readFileSync(root+'pages/chat/DrawnInlineEmojiLayer.ets','utf8');
assert.ok(!/^\s*@Local/m.test(layer));assert.ok(layer.includes("@Monitor('plan', 'msg')"));
console.log('PASS: inline custom emoji UTF-16/ZWJ and multi-link offsets, wrapping/footer, deduplication, O(1) warm binding, tint, late resources, disposal and stale callbacks.');
