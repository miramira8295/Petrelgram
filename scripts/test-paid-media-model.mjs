import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const file=(id,path='',loaded=0)=>({id,size:100,local:{path,is_downloading_completed:!!path,downloaded_size:loaded}});
const photo=(id)=>({'@type':'paidMediaPhoto',photo:{sizes:[{width:320,height:240,photo:file(id,'/thumb'+id)},
 {width:1280,height:960,photo:file(id+1)}],minithumbnail:{data:'mini'+id}}});
const video=(id)=>({'@type':'paidMediaVideo',video:{width:640,height:360,duration:65,mime_type:'video/mp4',
 file_name:'video.mp4',video:file(id),thumbnail:{file:file(id+1,'/poster'+id)}}});
const preview={'@type':'paidMediaPreview',width:800,height:600,duration:12,minithumbnail:{data:'blur'}};
const set=ctx.parsePaidMediaSet([photo(10),video(20),photo(30)]);
assert.equal(set.complete,true);assert.equal(set.locked,false);assert.equal(set.items.length,3);assert.equal(set.media.length,3);
assert.deepEqual(Array.from(set.viewerIndices),[0,1,2]);
assert.equal(set.media[0].file.id,11);assert.equal(set.media[0].thumbnail.id,10);
assert.equal(set.media[1].file.id,20);assert.equal(set.media[1].duration,65);assert.equal(set.items[0].mini,'data:image/jpeg;base64,mini10');
assert.equal(ctx.paidMediaViewerTarget(set,1).media[1],set.items[1].media);
const mixed=ctx.parsePaidMediaSet([photo(10),{'@type':'futurePaidType'},video(20)]);
assert.equal(mixed.complete,false);assert.deepEqual(Array.from(mixed.viewerIndices),[0,-1,1]);
assert.equal(ctx.paidMediaViewerTarget(mixed,1),null);assert.equal(ctx.paidMediaViewerTarget(mixed,2).index,1);
const locked=ctx.parsePaidMediaSet([photo(10),preview]);
assert.equal(locked.locked,true);assert.equal(locked.items[1].mini,'data:image/jpeg;base64,blur');
assert.equal(ctx.paidMediaViewerTarget(locked,0),null,'a mixed locked set cannot expose its decoded members');
assert.equal(ctx.parsePaidMediaSet([]).locked,true);
assert.equal(ctx.parsePaidMediaSet([{'@type':'paidMediaPhoto',photo:{sizes:[]}}]).complete,false);
for(const index of [-1,0.5,NaN,Infinity,999])assert.equal(ctx.paidMediaViewerTarget(set,index),null);
assert.equal(ctx.parsePaidMediaSet([photo(10),video(20),photo(30)]).signature,set.signature);
assert.notEqual(ctx.parsePaidMediaSet([photo(10),video(40),photo(30)]).signature,set.signature,'secondary item edits change the row fingerprint');
const progressing=[photo(10),video(20),photo(30)];progressing[1].video.video.local.downloaded_size=77;
assert.equal(ctx.parsePaidMediaSet(progressing).signature,set.signature,'byte progress never enters the row fingerprint');
// Count actual source-size reads. No cross-product scan over album members.
let sizeReads=0;
const many=Array.from({length:1000},(_,i)=>({'@type':'paidMediaPhoto',photo:{sizes:Array.from({length:4},(_,j)=>({
 get width(){sizeReads++;return 100+j*100;},height:100+j*100,photo:file(10000+i*4+j)}))}}));
const large=ctx.parsePaidMediaSet(many);assert.equal(large.media.length,1000);assert.equal(sizeReads,4000);
let lookups=0;
const watched={...large,items:new Proxy(large.items,{get(t,k){lookups++;return Reflect.get(t,k);}}),
 viewerIndices:new Proxy(large.viewerIndices,{get(t,k){lookups++;return Reflect.get(t,k);}}),
 media:new Proxy(large.media,{get(t,k){lookups++;return Reflect.get(t,k);}})};
for(let i=0;i<10000;i++)assert.equal(ctx.paidMediaViewerTarget(watched,999).index,999);
assert.ok(lookups<=60000,'each selection uses a fixed number of direct index reads');
load(root+'util/formatMsgContent.ets',['formatMsgContent']);
const parsed=ctx.formatMsgContent({content:{'@type':'messagePaidMedia',media:[photo(10),video(20)],star_count:12,
 caption:{text:'caption',entities:[]}}});
assert.equal(parsed.paidMediaCount,2);assert.equal(parsed.paidMediaSet.complete,true);assert.equal(parsed.text,'caption');
assert.equal(parsed.paidMediaSet.media[1].file.id,20);
const g=group('caption');Object.assign(g.head,parsed,{rowId:99});
const engine=new ctx.DrawnTextLayouts(),plan=engine.prepare(ui,g,data,style),slot=plan.caption.widgets[0];
vm.runInContext('globalThis.paidMediaLayoutFor=paidMediaLayoutFor',ctx);
assert.equal(ctx.paidMediaLayoutFor(slot.widget).note,null,'complete multi-media viewer no longer shows the first-only warning');
const counters=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...g,head:{...g.head,photoProgress:i%100}},data,style),plan);
assert.deepEqual(layoutCounters(),counters);
// Extract real production functions/methods instead of mirroring their branches.
function extract(path,name,method=false) {
 const source=fs.readFileSync(path,'utf8'),ast=ts.createSourceFile(path,source,ts.ScriptTarget.Latest,true);let found;
 function visit(node){if((method?ts.isMethodDeclaration(node):ts.isFunctionDeclaration(node))&&node.name?.getText(ast)===name)found=node;ts.forEachChild(node,visit);}
 visit(ast);assert.ok(found,name);return found.getText(ast).replace(/^export\s+/,'');
}
function evaluate(code){vm.runInContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
evaluate(extract(root+'store/MessageEntry.ets','cloneMessage')+'\nglobalThis.clonePaidMessage=cloneMessage;');
evaluate(fs.readFileSync(root+'util/richBlockRevision.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,''));
evaluate(extract(root+'util/collapseAlbums.ets','computeMutableSig')+'\nglobalThis.paidMutableSig=computeMutableSig;');
const entry=new Proxy({...g.head,paidMediaSet:set},{get(t,k){return k in t?t[k]:[];}});
assert.equal(ctx.clonePaidMessage(entry).paidMediaSet,set,'snapshot cloning preserves the immutable normalized set');
const changed=new Proxy({...g.head,paidMediaSet:ctx.parsePaidMediaSet([photo(10),video(40),photo(30)])},{get(t,k){return k in t?t[k]:[];}});
assert.notEqual(ctx.paidMutableSig(entry),ctx.paidMutableSig(changed));
evaluate('class PaidRouteHarness {'+extract(compiled+'pages/chat/ChatPage.ts','onPaidMediaOpen',true)+'}\nglobalThis.PaidRouteHarness=PaidRouteHarness;');
const opened=[],legacy=[];ctx.stackOf=()=>({pushPath:p=>opened.push(p)});
const page=Object.assign(Object.create(ctx.PaidRouteHarness.prototype),{chatId:7,entryById:()=>entry,openViewer:id=>legacy.push(id)});
page.onPaidMediaOpen(10);assert.equal(opened.length,1);assert.equal(opened[0].name,'DownloadPreviewPage');
assert.equal(opened[0].param.documentMedia.media,set.media);assert.equal(opened[0].param.documentMedia.messageId,entry.id);
assert.equal(opened[0].param.startIndex,0);
page.onPaidMediaOpen(10,2);assert.equal(opened[1].param.startIndex,2,'tile index reaches the actual compiled page route');
page.onPaidMediaOpen(10,-1);assert.equal(opened.length,2);
page.entryById=()=>({...entry,paidMediaLocked:true});page.onPaidMediaOpen(10);assert.equal(opened.length,2);
page.entryById=()=>({...entry,paidMediaSet:locked,paidMediaLocked:false});page.onPaidMediaOpen(10);assert.equal(opened.length,2);
page.entryById=()=>({...entry,paidMediaSet:undefined,paidMediaLocked:false});page.onPaidMediaOpen(10);assert.deepEqual(legacy,[10]);
page.onPaidMediaOpen(10,2);assert.deepEqual(legacy,[10],'legacy content cannot silently open a different tile');
console.log('PASS: all paid items survive parsing/cloning/content fingerprints; mixed preview and unsupported indices are safe; 4000 size reads for 1000×4 variants, constant-index selection, complete viewer routing and 1000 progress updates retain geometry.');
