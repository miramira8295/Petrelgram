import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.deepAPI={DrawnStructuredSource,DrawnRichTextLayouts,DrawnRichHitIndex,drawnExpandedBlockSet,expandDocumentAnchor};',ctx);
const {DrawnStructuredSource,DrawnRichTextLayouts,DrawnRichHitIndex,drawnExpandedBlockSet,expandDocumentAnchor}=ctx.deepAPI;
const plain=text=>({'@type':'richTextPlain',text}),para=text=>({'@type':'pageBlockParagraph',text:typeof text==='string'?plain(text):text});
const link=(label,url)=>({'@type':'richTextUrl',text:plain(label),url});
const specOf=source=>({source,maxWidthVp:300,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'deep'});
function visitSources(source,fn){const pending=[source];while(pending.length){const s=pending.pop();fn(s);for(const b of s.blocks??[])pending.push(b.source);}}
// Flattened vs nested additions can differ at floating-point roundoff only.
const canonical=object=>JSON.parse(JSON.stringify(object,(_key,v)=>typeof v==='number'?Number(v.toFixed(7)):v));
function snapshot(plan){
 const text=[],backgrounds=[];const pending=[{p:plan.paragraph,x:0,y:0}];
 while(pending.length){const {p,x,y}=pending.pop();if(p.native){text.push({text:p.native.content,x:x+(p.shiftX??0),y});continue;}for(const b of p.backgrounds??[])backgrounds.push({left:b.shape.rect.left+x,right:b.shape.rect.right+x,top:b.shape.rect.top+y,bottom:b.shape.rect.bottom+y});for(let i=(p.parts?.length??0)-1;i>=0;i--){const part=p.parts[i];pending.push({p:part.paragraph,x:x+part.x,y:y+part.y});}}
 backgrounds.sort((a,b)=>a.top-b.top||a.left-b.left||a.bottom-b.bottom||a.right-b.right);
 return {width:plan.widthVp,height:plan.heightVp,spoken:plan.accessibilityText,text,backgrounds,
  hits:plan.hits.map(h=>({x:h.x,y:h.y,w:h.widthVp,h:h.heightVp,url:h.link.url,action:h.link.action,label:h.link.label,offset:h.link.blockOffset,accessible:h.accessible})),
  icons:plan.icons.map(i=>({x:i.x,y:i.y,w:i.width,h:i.height})),
  maths:plan.maths.map(m=>({key:m.key,rect:m.rect,fallbackY:m.fallbackY})),
  widgets:plan.widgets.map(w=>({kind:w.widget.kind,x:w.x,y:w.y,width:w.width,height:w.height})),
  media:plan.media.map(m=>({index:m.media.index,x:m.x,y:m.y,width:m.width,height:m.height})),
  tables:plan.tables.map(t=>({x:t.x,y:t.y,width:t.width,height:t.height,content:t.layout.accessibilityText})),
  anchors:Array.from(plan.anchors)};
}
const icon={'@type':'richTextIcon',document:{document:{id:501,size:100}},width:24,height:18};
const formula={'@type':'richTextMathematicalExpression',expression:'x^2'};
const leafNodes=[para({'@type':'richTexts',texts:[plain('icons '),icon,formula]}),para(link('linked body','https://deep.test/body')),{'@type':'pageBlockPreformatted',text:plain('const answer = 42;'),language:'ts'},
 {'@type':'pageBlockPhoto',photo:{sizes:[{width:400,height:300,photo:{id:111,size:1}}]}},
 {'@type':'pageBlockTable',cells:[[{text:link('cell','https://deep.test/cell')}]]},
 {'@type':'pageBlockAnchor',name:'end'},para('end')];
const mixed=[para('intro'),{'@type':'pageBlockDocument',document:{document:{id:502,size:100},file_name:'file.pdf'}},{'@type':'pageBlockDetails',header:{'@type':'richTexts',texts:[plain('details '),icon,formula]},is_open:true,blocks:[
 {'@type':'pageBlockList',items:[{label:'1.',blocks:[{'@type':'pageBlockBlockQuote',blocks:leafNodes,credit:plain('credit')}]},{has_checkbox:true,is_checked:true,blocks:[para('checked')]}]}]},para('after')];
const source=new DrawnStructuredSource().prepare(mixed);assert.ok(source);
// Force the iterative renderer on a small, inspectable tree. Reference keeps
// the existing recursive geometry engine; only test dispatch is overridden.
visitSources(source,s=>{if(s.blocks)s.nestingDepth=100;});
const actualDeep=DrawnRichTextLayouts.prototype.buildDeepBlocks;
for(const width of [300,90,30])for(const expandedBlocks of [undefined,[1]]){
 const spec={...specOf(source),maxWidthVp:width,expandedBlocks};
 DrawnRichTextLayouts.prototype.buildDeepBlocks=function(ui,s,d){return this.buildBlocks(ui,s,d);};
 const reference=new DrawnRichTextLayouts().prepare(ui,spec);
 DrawnRichTextLayouts.prototype.buildDeepBlocks=actualDeep;
 const actual=new DrawnRichTextLayouts().prepare(ui,spec);
 assert.deepEqual(canonical(snapshot(actual)),canonical(snapshot(reference)),`geometry/disclosure/metadata at width ${width}`);
}
console.log('PASS: iterative/recursive differential text/frame/link/order/anchor/media/table geometry, code copy and details open/closed at wide and narrow widths.');
let node={'@type':'pageBlockDetails',header:plain('inner anchor'),is_open:false,blocks:[{'@type':'pageBlockAnchor',name:'deep-end'},para(link('deepest','https://deep.test/end'))]};
for(let i=0;i<10000;i++)node={'@type':'pageBlockDetails',header:plain(`section ${i}`),is_open:false,blocks:[node]};
const sourceEngine=new DrawnStructuredSource(),deepSource=sourceEngine.prepare([node]);assert.ok(deepSource);assert.equal(deepSource.nestingDepth,10002);
const engine=new DrawnRichTextLayouts(),closed=engine.prepare(ui,specOf(deepSource));assert.equal(closed.hits.length,1);assert.ok(!closed.accessibilityText.includes('deepest'));assert.equal(closed.widgets.length,0);
const allOpen=[];visitSources(deepSource,s=>{for(const b of s.blocks??[])if(b.kind==='details')allOpen.push(b.offset);});
const expandedSet=drawnExpandedBlockSet(allOpen);for(let i=0;i<1000;i++)assert.equal(drawnExpandedBlockSet(allOpen),expandedSet);
const opened=engine.prepare(ui,{...specOf(deepSource),expandedBlocks:allOpen});assert.ok(opened.accessibilityText.includes('deepest'));assert.equal(opened.hits.filter(h=>h.link.url==='https://deep.test/end').length,7,'mock glyph rectangles for deepest link');assert.equal(opened.hits.filter(h=>h.link.action==='quote').length,10001);
const expandedAnchor=expandDocumentAnchor(deepSource.anchorPaths.get('deep-end'),[]);assert.equal(expandedAnchor.length,10001);assert.ok(engine.prepare(ui,{...specOf(deepSource),expandedBlocks:expandedAnchor}).anchors.has('deep-end'));
// Recheck using the exact immutable owner list.
const owner=[node],owned=sourceEngine.prepare(owner),ownedSpec={...specOf(owned),expandedBlocks:allOpen},ownedPlan=engine.prepare(ui,ownedSpec),stable=layoutCounters();
for(let i=0;i<1000;i++){assert.equal(sourceEngine.prepare(owner),owned);assert.equal(engine.prepare(ui,ownedSpec),ownedPlan);}assert.deepEqual(layoutCounters(),stable);
console.log('PASS: 10000-deep source compilation and disclosure traversal without JS recursion; hidden content stays hidden, all open controls/links retained and expansion/source/layout caches stable.');
// Count index input volume, not milliseconds: ancestor copying would multiply
// 1000 link rectangles by 3000 covers before the final hit index was built.
let indexed=0;class CountedIndex extends DrawnRichHitIndex{constructor(hits){indexed+=hits.length;super(hits);}}
ctx.CountedIndex=CountedIndex;vm.runInContext('DrawnRichHitIndex=CountedIndex;',ctx);
let covered=para({'@type':'richTexts',texts:Array.from({length:600},(_,i)=>link(`x${i} `,`https://many.test/${i}`))});
for(let i=0;i<3000;i++)covered={'@type':'pageBlockCover',cover:covered};
const coverSource=new DrawnStructuredSource().prepare([covered]);assert.ok(coverSource);const coverEngine=new DrawnRichTextLayouts(),coverPlan=coverEngine.prepare(ui,specOf(coverSource));assert.ok(coverPlan.hits.length>=600);assert.ok(indexed<coverPlan.hits.length*20,`indices must not repeat per ancestor: ${indexed}`);
let saves=0,maxSaves=0;const canvas=new Proxy({}, {get:(_t,k)=>(..._args)=>{if(k==='save')maxSaves=Math.max(maxSaves,++saves);if(k==='restore')saves--;}});coverPlan.paragraph.paint(canvas,0,0);assert.equal(saves,0);assert.ok(maxSaves<20,`paint recursion must stay bounded: ${maxSaves}`);
let list=para('list bottom');for(let i=0;i<200;i++)list={'@type':'pageBlockList',items:[{label:'•',blocks:[list]}]};
const listSource=new DrawnStructuredSource().prepare([list]),listPlan=new DrawnRichTextLayouts().prepare(ui,specOf(listSource));assert.ok(listPlan.widthVp<=300);assert.ok(listPlan.accessibilityText.includes('list bottom'));
const g=group('');g.head.contentType='richMessage';g.head.richBlocks=[list];assert.ok(new ctx.DrawnTextLayouts().prepare(ui,g,data,style),'deep lists retain the complete drawn row');
const cyclic={'@type':'pageBlockCover'};cyclic.cover=cyclic;const rejected=new DrawnStructuredSource();assert.equal(rejected.prepare([cyclic]),null);assert.equal(rejected.reason,'structured-cycle');
console.log('PASS: 3000 covers do not multiply descendant hit indices; paint depth bounded, 200-level lists stay inside width budget/full row, cyclic source rejected atomically.');

const invalidCredit=new DrawnStructuredSource();assert.equal(invalidCredit.prepare([{'@type':'pageBlockBlockQuote',text:plain('quote'),credit:{'@type':'richTextIcon',document:{},width:20,height:20}}]),null,'an unsupported quote credit cannot silently disappear');
