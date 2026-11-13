// Real layout engines with deterministic native doubles. Count avoided work,
// compare warm inputs against cold results, and retain old plans across reuse.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
for(const f of ['packAlbumRows','albumGeometryCache','albumCellRenderData'])load(root+'util/'+f+'.ets');
for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout'])
  load(root+'pages/chat/'+f+'.ets',f==='DrawnMediaLayout'?['DrawnMediaLayouts']:[]);
vm.runInContext('globalThis.AlbumGeometryCache=AlbumGeometryCache; globalThis.DrawnBubbleOutlineCache=DrawnBubbleOutlineCache; globalThis.DrawnSourcePool=DrawnSourcePool;',ctx);
// Cross-owner normalization shares immutable runs/links, never Paragraphs.
const entities=[{offset:0,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://first.test'}}];
const sourceA=new ctx.DrawnRichSourceCache().prepare('link',entities),parsed=layoutCounters().parseCalls;
Object.freeze(sourceA);for(const run of sourceA.runs)Object.freeze(run);for(const link of sourceA.links)Object.freeze(link);
Object.freeze(sourceA.runs);Object.freeze(sourceA.links);
for(let i=0;i<1000;i++)assert.equal(new ctx.DrawnRichSourceCache().prepare('link',entities),sourceA);
assert.equal(layoutCounters().parseCalls,parsed);
const second=new ctx.DrawnRichSourceCache().prepare('link',[{offset:0,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://second.test'}}]);
assert.notEqual(second,sourceA);assert.equal(second.links[0].url,'https://second.test');
assert.notEqual(new ctx.DrawnRichSourceCache().prepare('link edited',entities),sourceA);
let injected=0;const custom=()=>{injected++;return [];};
new ctx.DrawnRichSourceCache(custom).prepare('link',entities);new ctx.DrawnRichSourceCache(custom).prepare('link',entities);
assert.equal(injected,2,'custom parsers must not share production decisions');
const sourcePool=new ctx.DrawnSourcePool(),key=[];sourcePool.put('one',key,sourceA,1000);
assert.equal(sourcePool.get('one',key),sourceA);assert.equal(sourcePool.get('two',key),undefined);
const entry=sourcePool.inputs.get(key);
for(let i=0;i<1000;i++){sourcePool.put(String(i),[],{source:null,reason:'unsupported'},10000);assert.ok(sourcePool.recent.size<=64);assert.ok(sourcePool.cost<=262144);}
assert.equal(entry.result,null);assert.equal(entry.content,'');assert.equal(sourcePool.get('one',key),undefined);
sourcePool.put('huge',key,sourceA,262145);assert.equal(sourcePool.get('huge',key),undefined);
assert.equal(sourceA.links[0].url,'https://first.test','eviction cannot mutate a source borrowed by another row');
function album(){return {...group(),caption:'caption https://one.test',captionEntities:[],
  memberIds:[10,11,12,13,14,15],photoRatios:[1,.6,1.5,1,1,1],photoPaths:[],photoFileIds:[1,2,3,4,5,6],
  photoMinis:[],photoProgress:[],photoFailed:[],photoIsVideo:[],photoIsLive:[],videoFileIds:[],videoFileSizes:[],
  videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[]};}
const decorated=album();Object.assign(decorated.head,{senderName:'Sender',replyToMessageId:5,replySenderName:'Reply',replyText:'Quoted'});
const grouped={...data,isGroup:true},cache=new ctx.DrawnMediaLayouts(false);
let p=cache.prepare(ui,decorated,grouped,style);
const warm=layoutCounters(),initial=p;
for(let i=0;i<1000;i++){
  const next={...decorated,head:{...decorated.head,videoProgress:i,videoPath:`/video/${i}`}};
  assert.equal(cache.prepare(ui,next,{...grouped},style),initial,'irrelevant snapshots must retain plan identity');
}
assert.deepEqual(layoutCounters(),warm,'no extra paragraph, last-line query or SVG parsing on new irrelevant snapshots');
for(let i=0;i<1000;i++){
  const next={...decorated,photoRatios:[...decorated.photoRatios],photoFileIds:[...decorated.photoFileIds],memberIds:[...decorated.memberIds]};
  assert.equal(cache.prepare(ui,next,grouped,style),initial,'equal arrays must retain the prepared grid');
}
assert.deepEqual(layoutCounters(),warm);

// Poster replacement changes binding but not shape; old plans are immutable.
const beforeShape=initial.outline.svg;
const poster={...decorated,photoPaths:['/new']};p=cache.prepare(ui,poster,grouped,style);
assert.notEqual(p,initial);assert.equal(p.outline,initial.outline);assert.equal(p.caption,initial.caption);
assert.equal(p.tiles[0].cell.thumbPath,'/new');assert.equal(initial.tiles[0].cell.thumbPath,'');
assert.equal(initial.outline.svg,beforeShape);assert.equal(layoutCounters().pathBuilds,warm.pathBuilds);

// Same-width footer text changes reuse paths, but an actually wider footer
// must still be allowed to change layout and the shell.
const textCache=new ctx.DrawnTextLayouts(),message=group('short');
const first=textCache.prepare(ui,message,data,{...style,views:'11'}),count=layoutCounters().pathBuilds;
for(let i=0;i<100;i++){
  const next=textCache.prepare(ui,message,data,{...style,views:i%2?'22':'33'});
  assert.equal(next.outline,first.outline);assert.equal(next.caption,first.caption);
}
assert.equal(layoutCounters().pathBuilds,count);
const wide=textCache.prepare(ui,message,data,{...style,views:'12345678901234567890'});
assert.ok(wide.width!==first.width||wide.height!==first.height);assert.notEqual(wide.outline,first.outline);

// Every input to SVG geometry participates in the cache key. Compare exact
// commands with the original pure generator; a miss cannot mutate an old path.
const outline=new ctx.DrawnBubbleOutlineCache(),base=[220,160,false,true,10,12,14,16,2,7];
let old=outline.prepare(...base);const saved=old.svg;
for(let k=0;k<base.length;k++){
  const args=[...base];args[k]=typeof args[k]==='boolean'?!args[k]:args[k]+1;
  const next=outline.prepare(...args);assert.notEqual(next,old);
  const [w,h,out,tail,tl,tr,br,bl,d,gutter]=args;
  assert.equal(next.svg,ctx.glassBubbleCommands(w,h,out,tail,tl,tr,br,bl,8,12,d,0,gutter));
  assert.equal(outline.prepare(...args),next);
  assert.equal(old.svg,saved);outline.prepare(...base);
}

// Pool shares only geometry, has a hard entry/cell budget and tolerates eviction
// while an old owner still holds its rows. No entity/body hashing on warm bind.
const pool=new ctx.AlbumGeometryCache(),ratios=[.5,1,1.5,2,1,1];
const rows=pool.prepare(ratios,280),snapshot=JSON.stringify(rows);
assert.equal(pool.prepare([...ratios],280),rows);
for(const row of rows){for(const cell of row)Object.freeze(cell);Object.freeze(row);}Object.freeze(rows);
for(let i=0;i<1000;i++){
  const input=Array.from({length:32},(_,j)=>.4+(i+j)%17/10),width=200+i/10;
  const result=pool.prepare(input,width);
  assert.equal(JSON.stringify(result),JSON.stringify(ctx.packAlbumRows(input,width)));
  assert.ok(pool.entries.size<=64);assert.ok(pool.cells<=512);
}
assert.equal(JSON.stringify(rows),snapshot);
assert.notEqual(pool.prepare(ratios,280),rows,'eviction releases pool ownership');
const size=pool.entries.size,cells=pool.cells;
for(const input of [[],[NaN],[Infinity],Array(33).fill(1)])pool.prepare(input,280);
pool.prepare([1],Infinity);assert.equal(pool.entries.size,size);assert.equal(pool.cells,cells);

// Differential cache invalidation: a reused owner must agree with a cold owner
// for geometry, text, selection, playback, colors, clipping and image binding.
const plain=p=>JSON.parse(JSON.stringify({...p,outline:p.outline.svg,outlinePath:undefined}));
let seed=20261113;const rand=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
const reused=new ctx.DrawnMediaLayouts(false);
for(let i=0;i<300;i++){
  const g=album(),d={...grouped,contentWidth:[180,260,400,800][rand(4)],isGroup:!!rand(2),isChannel:!!rand(2),
    selectionActive:!!rand(2),selectedMemberIds:rand(2)?[11,14]:[],playSlotKey:rand(2)?'11:1':'',autoplayMuted:!!rand(2),playSlotStartMs:rand(100)};
  g.caption=['','short','long '.repeat(50)][rand(3)];g.showAvatar=!!rand(2);g.showSenderName=!!rand(2);
  Object.assign(g.head,{isOutgoing:!!rand(2),senderId:rand(50),senderInitials:`A${rand(10)}`,senderName:rand(2)?'Name':'',
    date:rand(60),editDate:rand(2),replyToMessageId:rand(2),replyText:'quote',replySenderName:'reply',forwardFrom:rand(2)?'Forward':'',
    commentCount:rand(3),commentReplierIds:[1,2],sendState:rand(2)?'sent':'sending'});
  g.photoPaths=rand(2)?['/a']:[];g.photoFailed=rand(2)?[false,true]:[];g.photoIsVideo=[false,true];
  g.videoFileIds=[0,88];g.videoDurations=[0,12];
  const s={...style,radius:[4,16,24][rand(3)],fontSize:[12,16,24][rand(3)],views:['','1','123456789'][rand(3)],role:rand(2)?'admin':''};
  const actual=reused.prepare(ui,g,d,s),fresh=new ctx.DrawnMediaLayouts(false).prepare(ui,g,d,s);
  assert.deepEqual(plain(actual),plain(fresh),`cache invalidation case ${i}`);
}
// Optional before/after parity uses a saved baseline only during development;
// the standard suite above has no dependency on local build artifacts.
if(process.env.BEFORE_DRAWN_MEDIA){
  const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
  const source=fs.readFileSync(process.env.BEFORE_DRAWN_MEDIA,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
    .replace(/\bexport /g,'').replace(/\bDrawnMediaLayouts\b/g,'BeforeDrawnMediaLayouts');
  vm.runInContext(ts.transpileModule(source+'\nglobalThis.BeforeDrawnMediaLayouts=BeforeDrawnMediaLayouts;',
    {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
  for(let i=0;i<100;i++){
    const g=album();g.caption=i%2?'caption '.repeat(i+1):'';g.showAvatar=!!(i%2);g.head.isOutgoing=!!(i%3);
    const d={...data,isGroup:!!(i%2),contentWidth:180+i*3},s={...style,views:String(i)};
    assert.deepEqual(plain(new ctx.DrawnMediaLayouts(false).prepare(ui,g,d,s)),plain(new ctx.BeforeDrawnMediaLayouts(false).prepare(ui,g,d,s)));
  }
}
console.log('PASS: 1000 cross-owner source hits; 2000 equivalent snapshots retain plan; poster/footer changes reuse shape; all shape keys; bounded immutable source/geometry pools; 300 warm/cold differential cases.');

// Exercise the palette through real media layout preparation, not only its
// helper. Equivalent snapshots must avoid native color resolution; environment
// changes and custom outgoing colors must still reach the published plan.
const originalResolve=ctx.ColorMetrics.resourceColor;
let colorReads=0,colorEpoch=1;
ctx.ColorMetrics.resourceColor=(color)=>{colorReads++;return{...originalResolve(color),red:colorEpoch};};
try {
  const paletteOwner=new ctx.DrawnMediaLayouts(false),media=album();
  media.caption='';media.head.text='';
  const first=paletteOwner.prepare(ui,media,data,style),coldReads=colorReads;
  for(let i=0;i<1000;i++)assert.equal(paletteOwner.prepare(ui,{...media,head:{...media.head}},data,style),first);
  assert.equal(colorReads,coldReads,'1000 equivalent snapshots perform no more color resolution');
  colorEpoch=2;
  const themed=paletteOwner.prepare(ui,media,data,{...style,environment:'palette-2'});
  assert.equal(themed.fill.red,2);assert.equal(first.fill.red,1);assert.ok(colorReads>coldReads);
  const outgoing={...media,head:{...media.head,isOutgoing:true}};
  for(let i=0;i<100;i++){
    const custom={...data,themeBubbleOut:'#'+i.toString(16).padStart(6,'0')};
    const actual=paletteOwner.prepare(ui,outgoing,custom,{...style,environment:'palette-2'});
    const expected=new ctx.DrawnMediaLayouts(false).prepare(ui,outgoing,custom,{...style,environment:'palette-2'});
    assert.deepEqual(plain(actual),plain(expected));assert.ok(paletteOwner.colors.colors.size<=16);
  }
} finally { ctx.ColorMetrics.resourceColor=originalResolve; }
console.log('PASS: real media layout avoids 1000 repeated color resolutions; theme changes preserve old plans; 100 custom outgoing colors match cold layouts with bounded palette storage.');
