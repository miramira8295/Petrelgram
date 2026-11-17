import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,ui,group,data,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.api={DrawnStructuredSource,DrawnRichTextLayouts,documentAnchorName,expandDocumentAnchor};',ctx);
const {DrawnStructuredSource,DrawnRichTextLayouts,documentAnchorName,expandDocumentAnchor}=ctx.api;
const plain=text=>({'@type':'richTextPlain',text}),p=text=>({'@type':'pageBlockParagraph',text:typeof text==='string'?plain(text):text});
const nodes=[p({'@type':'richTextAnchorLink',anchor_name:'CHAPTER',url:'https://fallback',text:plain('jump')}),
 {'@type':'pageBlockDetails',header:plain('outer'),is_open:false,page_blocks:[
 {'@type':'pageBlockDetails',header:plain('inner'),is_open:true,page_blocks:[
 {'@type':'pageBlockAnchor',name:'Chapter'},p('target text')]}]},
 p({'@type':'richTexts',texts:[{'@type':'richTextAnchor',name:'note'},plain('Footnote '),{'@type':'richTextUrl',url:'https://example.test',text:plain('link')}]}),
 p({'@type':'richTextReference',anchor_name:'note',url:'https://fallback-note',text:plain('1')})];
const source=new DrawnStructuredSource().prepare(nodes);assert.ok(source);
assert.equal(source.blocks[0].source.links[0].url,'#CHAPTER');assert.equal(source.footnotes.get('note').content,'Footnote link');
assert.equal(source.footnotes.get('note').links[0].url,'https://example.test');
assert.equal(documentAnchorName('#CHAP%54ER'),'chapter');assert.equal(documentAnchorName('#%ZZ'),'%zz');assert.equal(documentAnchorName('#'),'');assert.equal(documentAnchorName('https://x/#a'),null);
const outer=source.blocks[1],inner=outer.source.blocks[0];
const expanded=expandDocumentAnchor(source.anchorPaths.get('chapter'),[inner.offset]);
assert.deepEqual(Array.from(expanded),[outer.offset]);
const layouts=new DrawnRichTextLayouts(),spec={source,maxWidthVp:280,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'anchors'};
const closed=layouts.prepare(ui,spec);assert.equal(closed.anchors.has('chapter'),false);
const open=layouts.prepare(ui,{...spec,expandedBlocks:expanded});assert.ok(open.anchors.get('chapter')>0);
const warm=layoutCounters();for(let i=0;i<1000;i++)assert.equal(layouts.prepare(ui,{...spec,expandedBlocks:expanded}),open);assert.deepEqual(layoutCounters(),warm);
// Real compiled row methods: note resolution, delayed layout and stale-owner guard.
const row=Object.create(ctx.DrawnMessageRow.prototype),g=group('text');g.head.richBlocks=nodes;
Object.assign(row,{kind:'text',group:g,data,expandedBlockOffsets:undefined,pendingAnchor:null,documentOwner:'',noteShown:false,noteSource:null,presentationReady:()=>true});
let y=[];row.actions={onDocumentAnchor:value=>y.push(value)};
row.getUIContext=()=>({px2vp:x=>x/2,getComponentUtils:()=>({getRectangleById:()=>({size:{height:100},windowOffset:{y:200}})})});
Object.defineProperty(row,'plan',{get:()=>({caption:layouts.prepare(ui,{...spec,expandedBlocks:row.rowExpandedBlocks()}),captionY:20})});
row.openDocumentLink('#note');assert.equal(row.noteShown,true);assert.equal(row.noteSource,source.footnotes.get('note'));
row.openDocumentLink('#chapter');assert.equal(row.noteShown,false);assert.equal(y.length,0);assert.equal(row.pendingAnchor,'chapter');
row.flushDocumentAnchor();assert.equal(y.length,1);assert.ok(y[0]>120);
row.openDocumentLink('#');assert.equal(y.at(-1),120);
row.pendingAnchor='chapter';row.pendingDocument=nodes;row.documentOwner='old-owner';row.flushDocumentAnchor();assert.equal(y.length,2);
assert.equal(row.openDocumentLink('https://external'),false);
console.log('PASS: internal reference parsing, footnote rich links, folded ancestor expansion, anchor coordinates, 1000 cached layouts, compiled row scroll/top/note and stale-owner guards.');
ctx.anchorSource=source;ctx.anchorMessage={...g.head,translatedText:'translated',translatedEntities:[],translatedLang:'en',translationHidden:false};
const translated=vm.runInContext("new DrawnTranslatedSource().prepare('text',[],anchorMessage,null,false,anchorSource)",ctx);
assert.equal(translated.anchorPaths,source.anchorPaths);assert.equal(translated.footnotes,source.footnotes);
const translatedPlan=layouts.prepare(ui,{...spec,source:translated,expandedBlocks:expanded});assert.equal(translatedPlan.anchors.get('chapter'),open.anchors.get('chapter'));
const duplicate=new DrawnStructuredSource().prepare([{'@type':'pageBlockAnchor',name:'same'},p('one'),{'@type':'pageBlockDetails',header:plain('two'),page_blocks:[{'@type':'pageBlockAnchor',name:'same'},p('two')]}]);
assert.equal(duplicate.anchorPaths.get('same').offset,duplicate.blocks[2].offset);
console.log('PASS: translation retains anchor/note identity and coordinates; duplicate names resolve in document order.');
const base=new DrawnStructuredSource().prepare([p('body')]);
const marked=new DrawnStructuredSource().prepare([p('body'),{'@type':'pageBlockAnchor',name:'end'}]);
const baseLayout=layouts.prepare(ui,{...spec,source:base,reserve:'12:30'}),markedLayout=layouts.prepare(ui,{...spec,source:marked,reserve:'12:30'});
assert.equal(markedLayout.heightVp,baseLayout.heightVp);assert.equal(markedLayout.widthVp,baseLayout.widthVp);
assert.equal(markedLayout.anchors.get('end'),markedLayout.heightVp);
console.log('PASS: trailing invisible anchor preserves body/footer geometry.');
row.noteShown=true;row.noteSource=source.footnotes.get('note');row.documentOwner=row.documentNodeId();row.documentBlocks=nodes;row.active=false;g.head.richBlocks=[];
row.attach();assert.equal(row.noteShown,false);assert.equal(row.noteSource,null);
console.log('PASS: editing the same message closes its stale footnote.');
