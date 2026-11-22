import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const g=group('file caption https://example.org');
Object.assign(g.head,{contentType:'file',photoFileId:0,photoPath:'',photoMini:'',videoFileId:31,videoFileName:'sample.pdf',videoFileSize:900,videoMimeType:'application/pdf',videoPath:'',videoProgress:0,videoFailed:false,mediaDownloadActive:false});
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
assert.match(rowSource,/if \(this\.rowGroup\.head\.contentType === 'file' \|\| this\.rowGroup\.head\.contentType === 'audio' \|\| this\.rowGroup\.head\.contentType === 'voice' \|\| this\.rowGroup\.head\.contentType === 'contact' \|\| this\.rowGroup\.head\.contentType === 'location' \|\| this\.rowGroup\.head\.contentType === 'venue' \|\| this\.rowGroup\.head\.contentType === 'checklist' \|\| this\.rowGroup\.head\.contentType === 'poll' \|\| this\.rowGroup\.head\.contentType === 'videoNote' \|\| this\.rowGroup\.head\.contentType === 'dice' \|\| this\.rowGroup\.head\.contentType === 'game' \|\| this\.rowGroup\.head\.contentType === 'paidMedia' \|\| this\.rowGroup\.head\.contentType === 'gift' \|\| this\.rowGroup\.head\.contentType === 'giveaway'\) \{\s*MessageBubble\(/);
const policy=fs.readFileSync(root+'util/drawnTextRowPolicy.ets','utf8');
assert.match(policy,/contentType === 'file'/);
const routing=fs.readFileSync(root+'pages/chat/ReusableMessageBubble.ets','utf8');
assert.match(routing,/contentType === 'richMessage' \|\| this\.shownGroup\.head\.contentType === 'file'/);
console.log('PASS: file route preserves legacy file behavior when drawn plan is unavailable.');
// No-caption documents used to reserve 80vp AND shape an empty caption.
const compactEngine=new ctx.DrawnTextLayouts();
const compact=compactEngine.prepare(ui,empty,data,style),card=compact.caption.widgets[0];
assert.equal(compact.caption.source.blocks.length,1,'no phantom empty caption paragraph');
assert.ok(card.height<80,'file slot is measured from actual controls');
assert.equal(compact.caption.heightVp,card.height,'terminal file has no phantom inter-block spacing');
assert.ok(compact.height<100,'ordinary file plus time fits a compact bubble');
const compactCounts=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(compactEngine.prepare(ui,{...empty,head:{...empty.head,photoPath:'/cover'+i,videoProgress:i%100}},data,style),compact);
assert.deepEqual(layoutCounters(),compactCounts,'thumbnail/progress never reshape filename or bubble');
const captionPlan=compactEngine.prepare(ui,g,data,style);assert.ok(captionPlan.height>compact.height,'real caption is retained');
console.log('PASS: captionless files have one measured control block, compact footer and no blank paragraph; 1000 cover updates retain complete geometry.');

vm.runInContext('globalThis.fileCardFor=fileCardFor;',ctx);
let checked=0;
for(const scale of [1,1.5,2]) for(const contentWidth of [240,400,800])
for(const preview of [false,true]) for(const outgoing of [false,true]) for(const longName of [false,true]) {
 const testUi={vp2px:n=>n*2,fp2px:n=>n*2*scale};
 const testGroup={...empty,head:{...empty.head,isOutgoing:outgoing,
  videoFileName:longName?'a long document filename with many words.pdf':'file.pdf',
  photoFileId:preview?71:0,photoMini:''}};
 const plan=new ctx.DrawnTextLayouts().prepare(testUi,testGroup,{...data,contentWidth},style);
 assert.ok(plan);const slot=plan.caption.widgets[0],file=ctx.fileCardFor(slot.widget);
 const timeTop=plan.footerY-plan.captionY-slot.y;
 assert.equal(plan.caption.heightVp,slot.height);
 assert.ok(timeTop>=file.footerTop-1e-6,'time clears both filename/status and download/save button');
 if(timeTop<slot.height)assert.ok(plan.footerX-plan.captionX>=file.footerLeft+4-1e-6,'inline time clears the preview tile');
 assert.ok(plan.footerY+plan.footerSlot.heightPx/plan.density<=plan.height-8+1e-6,'footer stays inside the bubble');
 const oldHeight=plan.captionY+slot.height+6+plan.footerSlot.heightPx/plan.density+2+8;
 assert.ok(plan.height<=oldHeight-6+1e-6,'never restore the trailing block gap');
 if(preview&&scale===1&&contentWidth>=400&&!longName)
  assert.ok(timeTop+plan.footerSlot.heightPx/plan.density<=slot.height,'preview and timestamp share the card height');
 checked++;
}
// A genuine caption still has its 6vp separation and owns the footer layout.
assert.equal(captionPlan.caption.widgets[0].height+6,captionPlan.caption.paragraph.parts[0].y/captionPlan.density);
console.log(`PASS: ${checked} file footer geometries across covers, long names, send direction, width and font scale; no overlap or progress-dependent row layout.`);

// Replay the generated ForEach keys and click handlers. A retained key keeps
// its original closure, exactly the case that lost file taps after relayout.
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
function compiledTree(name) {
  const path = compiled + 'pages/chat/' + name + '.ts';
  return ts.createSourceFile(path, fs.readFileSync(path, 'utf8'), ts.ScriptTarget.Latest, true);
}
function matchingNodes(tree, predicate) {
  const matches = [];
  function visit(node) {
    if (predicate(node)) matches.push(node);
    ts.forEachChild(node, visit);
  }
  visit(tree);
  return matches;
}
function binding(expression, parameter = '') {
  const fn = '(function(' + parameter + '){ return (' + expression.getText() + '); })';
  return vm.runInContext(ts.transpileModule(fn, {compilerOptions: {target: ts.ScriptTarget.ES2020}}).outputText, ctx);
}
const rowTree = compiledTree('DrawnMessageRow');
const rowLists = matchingNodes(rowTree, n => ts.isCallExpression(n) && n.expression.getText() === 'this.forEachUpdateFunction');
const rowHost = Object.create(ctx.DrawnMessageRow.prototype);
let activePlan = p;
const selected = [];
Object.defineProperties(rowHost, {
  rowGroup: {value: g}, rowData: {value: {...data, selectionActive: false}},
  plan: {get: () => activePlan}, presentationReady: {value: () => true},
  actions: {value: {onToggleSelectedMessage: id => selected.push(id)}}
});
function placementKey(list) {
  const call = rowLists.find(n => n.arguments[1].getText().includes('caption?.' + list));
  return binding(call.arguments[3]).call(rowHost);
}
const fileKey = placementKey('widgets');
const fileChild = matchingNodes(rowTree, n => ts.isNewExpression(n) && n.expression.getText() === 'DrawnFileMessage')[0];
const bindFile = binding(fileChild.arguments[1], 'item');
const retained = new Map();
function renderFile(plan) {
  activePlan = plan;
  const placement = plan.caption.widgets[0], key = fileKey(placement);
  if (!retained.has(key)) retained.set(key, bindFile.call(rowHost, placement));
  return retained.get(key);
}
const firstButton = renderFile(p);
const relayout = engine.prepare(ui, g, {...data, contentWidth: 180}, style);
assert.notEqual(p.caption.widgets[0].widget, relayout.caption.widgets[0].widget);
const visibleButton = renderFile(relayout);
rowHost.claimed = false;
assert.ok(visibleButton.onClaim(), 'visible file must accept a tap after reflow');
assert.equal(visibleButton.onClaim(), false, 'already consumed gesture');
rowHost.claimed = false;
rowHost.rowData.selectionActive = true;
assert.equal(firstButton.onClaim(), false, 'late event from old layout');
assert.equal(rowHost.claimed, false);
assert.equal(visibleButton.onClaim(), false);
assert.deepEqual(selected, [g.head.id], 'only current card can select the message');
const progressOnly = engine.prepare(ui, {...g, head: {...g.head, videoProgress: 42}},
  {...data, contentWidth: 180}, style);
assert.equal(renderFile(progressOnly), visibleButton, 'progress keeps the existing controls');
for (const list of ['media', 'tables']) {
  const key = placementKey(list), asset = {key: 'same logical item'};
  assert.equal(key(asset), key(asset));
  assert.notEqual(key(asset), key({...asset}), list + ' must replace stale geometry and events');
}
for (const component of ['DrawnChecklistMessage', 'DrawnRowAccessibility']) {
  const lists = matchingNodes(compiledTree(component),
    n => ts.isCallExpression(n) && n.expression.getText() === 'this.forEachUpdateFunction');
  assert.equal(lists.length, 1);
  const key = binding(lists[0].arguments[3]).call({msg: g.head});
  const target = {key: 'body', id: 7};
  assert.equal(key(target), key(target));
  assert.notEqual(key(target), key({...target}), component + ' must bind the current hit target');
}

const clicks = matchingNodes(compiledTree('FileBubble'), n => ts.isCallExpression(n) && n.expression.getText() === 'Row.onClick');
assert.equal(clicks.length, 2);
load(root + 'pages/chat/MediaSaveState.ets', ['MediaSaveState']);
const transfer = Object.create(ctx.MediaSaveState.prototype);
const operations = [];
const current = {...g.head};
ctx.showToast = () => {};
transfer.host = {findMsg: id => id === current.id ? current : undefined, store: () => ({
  pauseFileDownload: id => operations.push(['pause', id]),
  requestVideoDownload: id => operations.push(['download', id])
})};
transfer.openDownloadedFile = msg => operations.push(['open', msg.id]);
const displayedCard = {downloadActive: true, uploading: false, filePath: '', sourceUnavailable: () => false,
  onOpen: () => transfer.onFileTap(current.id), onSave: () => operations.push(['save', current.id])};
const body = binding(clicks[0].arguments[0]).call(displayedCard);
const arrow = binding(clicks[1].arguments[0]).call(displayedCard);
body(); // The UI still shows an active transfer, but the store has paused it.
current.mediaDownloadActive = true; displayedCard.downloadActive = false; body();
current.videoPath = '/ready'; body();
displayedCard.filePath = '/ready'; arrow();
displayedCard.uploading = true; body();
assert.deepEqual(operations, ['download', 'pause', 'open', 'save'].map(action => [action, current.id]));
console.log('PASS: retained file taps after reflow, stale-owner rejection, selection, stable progress and live download/pause/open decisions.');
