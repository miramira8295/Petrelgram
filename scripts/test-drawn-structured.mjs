import assert from 'node:assert/strict';
import vm from 'node:vm';
import { ctx, ui, data, style, group, layoutCounters } from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.DrawnStructuredSource=DrawnStructuredSource;globalThis.richSpansOf=richSpansOf;globalThis.DrawnRichTextLayouts=DrawnRichTextLayouts',ctx);
const plain=text=>({'@type':'richTextPlain',text});
const link=(text,url)=>({'@type':'richTextUrl',text:plain(text),url});
const p=text=>({'@type':'pageBlockParagraph',text:typeof text==='string'?plain(text):text});
const nodes=[{'@type':'pageBlockTitle',title:plain('Native title alias')},
 p({'@type':'richTexts',texts:[link('first','https://a.test'),plain(' / '),link('second','https://b.test')]}),
 {'@type':'pageBlockList',items:[{label:'1.',blocks:[p('ordered')]},{has_checkbox:true,is_checked:true,page_blocks:[p('done')]}]},
 {'@type':'pageBlockBlockQuote',blocks:[{'@type':'pageBlockDetails',header:plain('Details'),page_blocks:[p(link('secret link','https://hidden.test'))],is_open:false}]},
 {'@type':'pageBlockPreformatted',text:plain('const x=1;'),language:'js'}, {'@type':'pageBlockDivider'}];
const sources=new ctx.DrawnStructuredSource();const source=sources.prepare(nodes);assert.ok(source);
assert.equal(source.blocks[0].source.content,'Native title alias');assert.equal(source.blocks[0].source.runs[0].bold,true);
const details=source.blocks.find(b=>b.kind==='quote').source.blocks[0];
const engine=new ctx.DrawnRichTextLayouts();
const spec={source,maxWidthVp:280,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'structured'};
const closed=engine.prepare(ui,spec);
assert.ok(closed.hits.some(h=>h.link.url==='https://a.test'));assert.ok(closed.hits.some(h=>h.link.url==='https://b.test'));
assert.ok(!closed.hits.some(h=>h.link.url==='https://hidden.test'));
assert.ok(!closed.accessibilityText.includes('secret link'));
const opened=engine.prepare(ui,{...spec,expandedBlocks:[details.offset]});
assert.ok(opened.hits.some(h=>h.link.url==='https://hidden.test'),'nested details expansion must propagate through quote');
assert.ok(opened.heightVp>closed.heightVp);
const copy=opened.hits.find(h=>h.link.action==='copy');assert.equal(copy.link.label,'const x=1;');
const before=layoutCounters();for(let i=0;i<1000;i++){assert.equal(sources.prepare(nodes),source);assert.equal(engine.prepare(ui,spec),closed);}
assert.deepEqual(layoutCounters(),before);
const g=group('preview only');g.head.contentType='richMessage';g.head.richBlocks=nodes;
assert.equal(ctx.drawnTextRowEligible(g,data,false,false),true);
const rowPlan=new ctx.DrawnTextLayouts().prepare(ui,g,data,style);assert.ok(rowPlan);
assert.ok(rowPlan.caption.accessibilityText.includes('Native title alias'));assert.ok(!rowPlan.caption.accessibilityText.includes('preview only'));
// Unsupported blocks must reject atomically, never publish only the surviving text.
assert.equal(sources.prepare([p('before'),{'@type':'pageBlockPhoto',photo:{}},p('after')]),null);
assert.equal(sources.reason,'structured-media-missing-file');
const row=Object.create(ctx.DrawnMessageRow.prototype);row.group=g;row.data=data;row.kind='text';row.toggleDrawnQuote(details.offset);
assert.deepEqual(Array.from(row.rowExpandedBlocks()),[details.offset]);
row.group={...g,head:{...g.head,richBlocks:[...nodes]}};
assert.equal(row.rowExpandedBlocks(),undefined,'edited structure with identical preview resets expansion ownership');
// Deep inline styles are iterative, and inner links override inherited links.
let deep=plain('leaf');for(let i=0;i<20000;i++)deep={'@type':i%2?'richTextBold':'richTextItalic',text:deep};
const spans=ctx.richSpansOf(deep);assert.equal(spans.length,1);assert.equal(spans[0].text,'leaf');assert.ok(spans[0].bold&&spans[0].italic);
const mail=ctx.richSpansOf({'@type':'richTextEmailAddress',email_address:'a@b.test',text:plain('mail')});assert.equal(mail[0].url,'mailto:a@b.test');
console.log('PASS: structured title/list/task/code/nested details, distinct links, hidden actions, cache identity, edits, atomic admission and linear deep richText traversal.');
vm.runInContext('globalThis.drawnTableGrid=drawnTableGrid',ctx);
const cell=(text,extra={})=>({'@type':'pageBlockTableCell',text:typeof text==='string'?plain(text):text,...extra});
const tableNodes=[{'@type':'pageBlockTable',is_bordered:true,is_striped:true,caption:plain('caption'),cells:[
 [cell('merged header',{colspan:2,is_header:true}),cell('third')],
 [cell('tall merged',{rowspan:2}),cell(link('tap second','https://cell.test')),cell('right',{align:{'@type':'pageBlockHorizontalAlignmentRight'}})],
 [cell('lower two columns',{colspan:2})]]}];
const tableSource=sources.prepare(tableNodes);assert.ok(tableSource);
const grid=ctx.drawnTableGrid(tableSource.blocks[0].source.table.rows);assert.equal(grid.columns,3);assert.equal(grid.rows,3);
assert.deepEqual(Array.from(grid.cells,p=>[p.row,p.column,p.rows,p.columns]),[[0,0,1,2],[0,2,1,1],[1,0,2,1],[1,1,1,1],[1,2,1,1],[2,1,1,2]]);
const tablePlan=engine.prepare(ui,{...spec,source:tableSource,maxWidthVp:110});
assert.equal(tablePlan.tables.length,1);const table=tablePlan.tables[0];assert.ok(table.layout.widthVp>table.width);
assert.equal(table.width,110);assert.equal(table.layout.paragraph.borders.length,6);
assert.ok(table.layout.hits.length>0);assert.ok(table.layout.hits.every(h=>h.link.url==='https://cell.test'));
assert.ok(tablePlan.accessibilityText.includes('caption'));
assert.equal(tablePlan.paragraph.parts.length,1,'cell paragraphs are drawn only by the independent table island');
let cellPaint=0;for(const part of table.layout.paragraph.parts)part.paragraph.paint=()=>cellPaint++;
table.layout.paragraph.paint({save(){},translate(){},restore(){},attachPen(){},detachPen(){},drawRect(){},attachBrush(){},detachBrush(){},drawRoundRect(){}},0,0);
assert.equal(cellPaint,6);
const stable=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...spec,source:tableSource,maxWidthVp:110}),tablePlan);
assert.deepEqual(layoutCounters(),stable);
const invalidCell={source:tableSource,header:false,align:'left',rowspan:1,colspan:Infinity};assert.equal(ctx.drawnTableGrid([[invalidCell]]),null);
console.log('PASS: merged table occupancy/rowspan/colspan, independent horizontal viewport, link geometry, retained draw commands and bounded invalid spans.');
// Inline scripts/marking/formulas retain their semantic spans; button layout
// and media keep independent slots rather than disappearing into plain text.
vm.runInContext('globalThis.drawnPageButtonBoxes=drawnPageButtonBoxes;globalThis.drawnPageButtonAction=drawnPageButtonAction',ctx);
const styled=sources.prepare([p({'@type':'richTexts',texts:[
 {'@type':'richTextSuperscript',text:plain('2')},{'@type':'richTextSubscript',text:plain('n')},
 {'@type':'richTextMarked',text:plain('marked')},{'@type':'richTextMathematicalExpression',expression:'x^2'}]})]);
assert.ok(styled);assert.equal(styled.hasMath,true);
const runs=styled.blocks[0].source.runs;
assert.equal(runs[0].script,1);assert.equal(runs[1].script,-1);assert.equal(runs[2].marked,true);assert.equal(runs[3].math,'x^2');
const formulaLayout=engine.prepare(ui,{...spec,source:styled,mathRevision:0});assert.equal(formulaLayout.maths.length,1);
for(const width of [20,48,100,280,600])for(const align of ['fill','left','right','center']) {
 const boxes=ctx.drawnPageButtonBoxes([60,200,80,48,180,75],width,align);
 assert.equal(boxes.length,6);
 boxes.forEach((b,i)=>{assert.ok(b.x>=-1e-8&&b.x+b.width<=width+1e-8);if(i&&b.y===boxes[i-1].y)assert.ok(b.x>=boxes[i-1].x+boxes[i-1].width);});
}
const buttons=sources.prepare([{'@type':'pageBlockButtonRow',buttons:[
 {text:'Open',type:{'@type':'inlineKeyboardButtonTypeUrl',url:'https://example.org'}},
 {text:'Copy',type:{'@type':'inlineKeyboardButtonTypeCopyText',text:'copied'}},
 {text:'Disabled',type:{'@type':'inlineKeyboardButtonTypeDisabled'}}]}]);
const buttonPlan=engine.prepare(ui,{...spec,source:buttons});
assert.equal(buttonPlan.hits.length,2);assert.equal(buttonPlan.hits[0].link.button.value,'https://example.org');
assert.equal(buttonPlan.hits[1].link.button.kind,'copy');
const file=id=>({id,size:100,local:{is_downloading_completed:false,path:''}});
const photo={'@type':'pageBlockPhoto',photo:{sizes:[{width:100,height:100,photo:file(1)},{width:480,height:320,photo:file(2)},{width:1600,height:1200,photo:file(3)}]}};
const video={'@type':'pageBlockVideo',video:{video:file(4),thumbnail:{file:file(5)},width:640,height:360}};
const mediaSource=sources.prepare([photo,p('caption'),{'@type':'pageBlockDetails',header:plain('media'),is_open:true,page_blocks:[video]}]);
assert.ok(mediaSource);assert.equal(mediaSource.mediaItems.length,2);
assert.equal(mediaSource.mediaItems[0].file.id,3);assert.equal(mediaSource.mediaItems[0].thumbnail.id,2);
const mediaPlan=engine.prepare(ui,{...spec,source:mediaSource});assert.equal(mediaPlan.media.length,2);
assert.equal(mediaPlan.media[1].media.index,1);assert.ok(mediaPlan.media[1].y>mediaPlan.media[0].y);
const mediaStable=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...spec,source:mediaSource}),mediaPlan);
assert.deepEqual(layoutCounters(),mediaStable);
console.log('PASS: scripts/marked/formula placeholders, bounded button wrapping/actions, photo size selection, ordered nested media and hot layout reuse.');
// Gallery layout preserves source order and nested slideshow identity.
const gallerySource=sources.prepare([{'@type':'pageBlockCollage',page_blocks:[photo,video,photo],caption:{text:plain('gallery caption')}},
 {'@type':'pageBlockBlockQuote',page_blocks:[{'@type':'pageBlockSlideshow',page_blocks:[video,photo]}]}]);
assert.ok(gallerySource);assert.equal(gallerySource.mediaItems.length,5);
const galleryPlan=engine.prepare(ui,{...spec,source:gallerySource});assert.equal(galleryPlan.media.length,4);
assert.ok(galleryPlan.accessibilityText.includes('gallery caption'));
assert.deepEqual(Array.from(galleryPlan.media.slice(0,3),p=>p.media.index),[0,1,2]);
assert.deepEqual(Array.from(galleryPlan.media[3].slides,p=>p.index),[3,4]);
assert.ok(galleryPlan.media.every(p=>p.x>=0&&p.x+p.width<=galleryPlan.widthVp));
const galleryWarm=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...spec,source:gallerySource}),galleryPlan);
assert.deepEqual(layoutCounters(),galleryWarm);
assert.equal(sources.prepare([{'@type':'pageBlockCollage',page_blocks:[photo,p('cannot drop me')]}]),null);
console.log('PASS: linear collage packing, nested slideshow members, captions, malformed-member atomic rejection and 1000 hot gallery reuses.');
const icon={'@type':'richTextIcon',document:{document:file(90)},width:24,height:18};
const inlineSource=sources.prepare([p({'@type':'richTexts',texts:[plain('a'),{'@type':'richTextUrl',url:'https://icon.test',text:icon},plain('😀end'),icon]}),
 {'@type':'pageBlockTable',cells:[[cell(icon)]]},
 {'@type':'pageBlockDetails',header:icon,page_blocks:[p('expanded')],is_open:false}]);
assert.ok(inlineSource);
const inlinePlan=engine.prepare(ui,{...spec,source:inlineSource});
assert.equal(inlinePlan.icons.length,3);assert.equal(inlinePlan.tables[0].layout.icons.length,1);
assert.equal(inlinePlan.icons[2].x,24,'details header icon aligns with its paragraph after the disclosure arrow');
assert.equal(inlinePlan.hits.filter(h=>h.link.url==='https://icon.test').length,1);
assert.ok(inlinePlan.icons.every(i=>i.width>0&&i.width<=24&&i.height>0));
assert.equal(sources.prepare([p({'@type':'richTextIcon',document:{},width:20,height:20})]),null);
console.log('PASS: inline document placeholders, mixed UTF-16 link mapping, table/details offsets and malformed icon rejection.');
const widgetSource=sources.prepare([{'@type':'pageBlockMap',location:{latitude:0,longitude:0},width:400,height:200,zoom:15,
 caption:{text:plain('map caption')}},{'@type':'pageBlockBlockQuote',page_blocks:[
 {'@type':'pageBlockDocument',document:{document:file(71),file_name:'file.pdf',mime_type:'application/pdf'}},
 {'@type':'pageBlockVoiceNote',voice_note:{voice:file(72),duration:12,waveform:'AAAA'}}]}]);
assert.ok(widgetSource);const widgetPlan=engine.prepare(ui,{...spec,source:widgetSource});
assert.equal(widgetPlan.widgets.length,3);assert.deepEqual(Array.from(widgetPlan.widgets,p=>p.widget.kind),['map','file','voice']);
assert.ok(widgetPlan.widgets[1].x>0);assert.equal(widgetPlan.widgets[2].widget.duration,12);
assert.ok(widgetPlan.widgetOwners.has(widgetPlan.widgets[1].widget));
assert.ok(widgetPlan.accessibilityText.includes('map caption'));
assert.equal(widgetPlan.widgets[0].height,140);
assert.equal(sources.prepare([{'@type':'pageBlockMap',location:{latitude:91,longitude:0}}]),null);
assert.equal(sources.prepare([{'@type':'pageBlockDocument',document:{document:file(0)}}]),null);
const widgetsWarm=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...spec,source:widgetSource}),widgetPlan);
assert.deepEqual(layoutCounters(),widgetsWarm);
console.log('PASS: nested map/file/voice widgets, caption preservation, constant-time owner membership, invalid source rejection and 1000 retained geometries.');
const musicSource=sources.prepare([{'@type':'pageBlockAudio',audio:{audio:file(73),title:'Track',performer:'Artist',duration:42},caption:{text:plain('audio caption')}}]);
assert.ok(musicSource);const musicPlan=engine.prepare(ui,{...spec,source:musicSource});
assert.equal(musicPlan.widgets.length,1);assert.equal(musicPlan.widgets[0].widget.kind,'audio');
assert.equal(musicPlan.widgets[0].height,52,'music height includes measured labels and seek track');assert.ok(musicPlan.accessibilityText.includes('audio caption'));
const musicWarm=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...spec,source:musicSource}),musicPlan);
assert.deepEqual(layoutCounters(),musicWarm);
console.log('PASS: audio block admission, caption and 1000 geometry cache hits.');
const audioList=sources.prepare([{'@type':'pageBlockAudio',audio:{audio:file(80),title:'first'}},{'@type':'pageBlockDetails',title:plain('more'),page_blocks:[{'@type':'pageBlockAudio',audio:{audio:file(81),title:'second'}}]}]);
assert.deepEqual(Array.from(audioList.audioItems,item=>item.file.id),[80,81]);
console.log('PASS: document audio playlist preserves nested source order.');
const embeddedNodes=[{'@type':'pageBlockEmbeddedPost',url:'https://example.test/post',author:'Author',date:1700000000,
 author_photo:{sizes:[{width:800,height:800,photo:file(91)},{width:80,height:80,photo:file(92)}]},
 page_blocks:[p(link('body link','https://body.test')),{'@type':'pageBlockAudio',audio:{audio:file(93),title:'nested audio'}},
 {'@type':'pageBlockAnchor',name:'inside'},p('target')],caption:{text:plain('caption'),credit:plain('credit')}}];
const embedded=sources.prepare(embeddedNodes);assert.ok(embedded);
const header=embedded.blocks[0].source.blocks[0].widget;
assert.equal(header.kind,'post-author');assert.equal(header.avatar.id,92);assert.equal(header.url,'https://example.test/post');
assert.deepEqual(Array.from(embedded.audioItems,w=>w.file.id),[93]);assert.ok(embedded.anchorPaths.has('inside'));
const embedPlan=engine.prepare(ui,{...spec,source:embedded});assert.equal(embedPlan.widgets[0].height,56);
assert.ok(embedPlan.widgets[0].x>0);assert.ok(embedPlan.widgets[0].width<280);
assert.ok(embedPlan.hits.some(h=>h.link.url==='https://body.test'));assert.ok(embedPlan.accessibilityText.includes('caption'));assert.ok(embedPlan.accessibilityText.includes('credit'));
assert.ok(embedPlan.anchors.get('inside')>0);
const embedWarm=layoutCounters();for(let i=0;i<1000;i++){assert.equal(sources.prepare(embeddedNodes),embedded);assert.equal(engine.prepare(ui,{...spec,source:embedded}),embedPlan);}assert.deepEqual(layoutCounters(),embedWarm);
assert.ok(sources.prepare([{'@type':'pageBlockEmbeddedPost',author:'No photo',page_blocks:[],caption:{text:plain('caption only')}}]));
assert.equal(sources.prepare([{'@type':'pageBlockEmbeddedPost',page_blocks:[{'@type':'not-supported'}]}]),null,'must not silently omit post members');
console.log('PASS: embedded-post author/avatar selection, nested audio/links/anchors/caption/credit, geometry and 1000 cached preparations; unsupported children reject atomically.');
// Author/date preserves rich links and parses only when source/environment changes.
ctx.Date = Date; ctx.fullDate = date => 'date-' + date.getUTCFullYear();
const metaEngine=new ctx.DrawnStructuredSource();
const metaNodes=[{'@type':'pageBlockAuthorDate',author:link('Writer','https://writer.test'),publish_date:1700000000},
 {'@type':'pageBlockChatLink',title:'Channel',username:'example_channel',photo:{small:{id:88},minithumbnail:{data:'abc'}}},p('after')];
const meta=metaEngine.prepare(metaNodes,'en');assert.ok(meta);
assert.equal(meta.blocks[0].source.content,'date-2023 · Writer');
assert.equal(meta.blocks[0].source.links.length,1);assert.equal(meta.links.length,1);
assert.equal(meta.blocks[0].source.content.slice(meta.links[0].start,meta.links[0].end),'Writer');
assert.equal(meta.blocks[1].widget.kind,'chat-link');assert.equal(meta.blocks[1].widget.url,'https://t.me/example_channel');
assert.equal(meta.blocks[1].widget.avatar.id,88);
for(let i=0;i<1000;i++)assert.equal(metaEngine.prepare(metaNodes,'en'),meta);
ctx.fullDate=()=> '新日期';const localized=metaEngine.prepare(metaNodes,'zh');assert.notEqual(localized,meta);assert.equal(localized.blocks[0].source.content,'新日期 · Writer');
const noDate=metaEngine.prepare([{'@type':'pageBlockAuthorDate',author:plain('Author'),publish_date:0}]);assert.equal(noDate.blocks[0].source.content,'Author');
const noAuthor=metaEngine.prepare([{'@type':'pageBlockAuthorDate',publish_date:1700000000}]);assert.equal(noAuthor.blocks[0].source.content,'新日期');
const badDate=metaEngine.prepare([{'@type':'pageBlockAuthorDate',author:plain('A'),publish_date:Infinity}]);assert.equal(badDate.blocks[0].source.content,'A');
assert.equal(metaEngine.prepare([{'@type':'pageBlockChatLink',username:'evil.test/x'}]),null);
const metaLayout=engine.prepare(ui,{...spec,source:localized});assert.ok(metaLayout.widgets.some(w=>w.widget.kind==='chat-link'&&w.height===56));
console.log('PASS: author/date rich spans and offset, locale/source caching, channel link/avatar/geometry, invalid fields rejected.');
const metaGroup=group('flattened preview');metaGroup.head.contentType='richMessage';metaGroup.head.richBlocks=metaNodes;
const metaRow=new ctx.DrawnTextLayouts().prepare(ui,metaGroup,data,style);
assert.ok(metaRow,'author/date plus chat entry must retain the unified row');
assert.ok(metaRow.caption.widgets.some(w=>w.widget.kind==='chat-link'));
const articleNodes=[{'@type':'pageBlockRelatedArticles',header:plain('More'),articles:[
 {url:'https://article.test/one',title:'A long title '.repeat(25),author:'Writer',publish_date:1700000000,description:'ignored',photo:{sizes:[{width:80,height:80,photo:{id:333}}]}},
 {url:'https://article.test/two',title:'Second',description:'Description'},
 {url:'https://article.test/three',title:''}
]}];
const articleSource=new ctx.DrawnStructuredSource(),articles=articleSource.prepare(articleNodes,'en');assert.ok(articles);
assert.equal(articles.blocks.length,4);assert.equal(articles.blocks[1].source.content,'新日期 · Writer');
assert.equal(articles.blocks[2].source.content,'Description');assert.equal(articles.blocks[3].source.content,'https://article.test/three');
assert.equal(articles.blocks[1].article.avatar.id,333);
const articlesEngine=new ctx.DrawnRichTextLayouts();const articleSpec={...spec,source:articles};
const articlesLayout=articlesEngine.prepare(ui,articleSpec);
const articleHits=articlesLayout.hits.filter(h=>h.key.includes(':article:'));
assert.equal(articleHits.length,3);assert.equal(articlesLayout.widgets.length,1);assert.equal(articlesLayout.widgets[0].width,44);
assert.equal(articleHits[0].link.url,'https://article.test/one');assert.ok(articleHits[1].y>=articleHits[0].y+articleHits[0].heightVp);
const counters=layoutCounters();for(let i=0;i<1000;i++){assert.equal(articleSource.prepare(articleNodes,'en'),articles);assert.equal(articlesEngine.prepare(ui,articleSpec),articlesLayout);}assert.deepEqual(layoutCounters(),counters);
const narrow=articlesEngine.prepare(ui,{...articleSpec,maxWidthVp:100});assert.ok(Number.isFinite(narrow.heightVp));assert.ok(narrow.hits.every(h=>h.x+h.widthVp<=100));
const manyArticles=articleSource.prepare([{'@type':'pageBlockRelatedArticles',articles:Array.from({length:2049},(_,i)=>({url:`https://a/${i}`,title:'a'}))}]);
assert.ok(manyArticles);assert.equal(manyArticles.blocks.length,2050);assert.equal(manyArticles.blocks.at(-1).article.url,'https://a/2048');
console.log('PASS: related article metadata priority, thumbnail, whole-card links, narrow layout, 1000 cached prepares and full 2049-article document.');
const embeds=new ctx.DrawnStructuredSource();
const embedNodes=[{'@type':'pageBlockEmbedded',html:'<p>Embedded</p>',url:'https://example.test',width:320,height:180,allow_scrolling:true,
 caption:{text:plain('Caption'),credit:link('Credit','https://credit.test')}}];
const embed=embeds.prepare(embedNodes);assert.ok(embed);assert.equal(embed.blocks[0].widget.kind,'html-embed');
assert.equal(embed.blocks[0].widget.allowScrolling,true);assert.equal(embed.blocks[1].source.content,'Caption');assert.equal(embed.blocks[2].source.content,'Credit');
const embedLayout=engine.prepare(ui,{...spec,source:embed});assert.equal(embedLayout.widgets[0].height,280*180/320);
for(let i=0;i<1000;i++)assert.equal(embeds.prepare(embedNodes),embed);
for(const override of [{url:'tg-widget:42'},{width:-1},{height:Infinity},{html:'',url:'file:///private'},{html:'x'.repeat(131073)}]){
 assert.equal(embeds.prepare([{...embedNodes[0],...override}]),null);
}
console.log('PASS: fixed HTML source/geometry, caption/credit, cache and explicit unsupported/oversized embed boundaries.');
const urlEmbedNodes=[{'@type':'pageBlockEmbedded',html:'',url:'https://example.test/player',width:640,height:360,
 poster_photo:{sizes:[{width:80,height:80,photo:{id:456}}]},caption:{text:plain('Remote video')}}];
const urlEmbed=embeds.prepare(urlEmbedNodes);assert.ok(urlEmbed);assert.equal(urlEmbed.blocks[0].widget.avatar.id,456);
assert.equal(urlEmbed.blocks[0].widget.url,'https://example.test/player');assert.equal(urlEmbed.blocks[1].source.content,'Remote video');
assert.ok(engine.prepare(ui,{...spec,source:urlEmbed}).widgets.length===1);
console.log('PASS: URL embeds retain poster/caption and unified geometry without empty-HTML substitution.');
vm.runInContext('globalThis.setDocumentEmbedHeight=setDocumentEmbedHeight',ctx);
const resizingSource=new ctx.DrawnStructuredSource().prepare([p('cached before'),{'@type':'pageBlockDetails',is_open:true,header:plain('Details'),page_blocks:[
 {'@type':'pageBlockEmbedded',html:'<p>dynamic</p>',url:'https://example.test',width:0,height:0},p('cached after')]}]);
assert.ok(resizingSource.hasEmbed);const resizingEngine=new ctx.DrawnRichTextLayouts();
const initialSize=resizingEngine.prepare(ui,{...spec,source:resizingSource,mathRevision:0});const placement=initialSize.widgets[0];assert.equal(placement.height,10);
const beforeResize=layoutCounters();ctx.setDocumentEmbedHeight(placement.widget,placement.width,180);
const changedSize=resizingEngine.prepare(ui,{...spec,source:resizingSource,mathRevision:1});assert.equal(changedSize.widgets[0].height,180);assert.equal(changedSize.heightVp-initialSize.heightVp,170);
const afterResize=layoutCounters();
assert.equal(afterResize.parseCalls,beforeResize.parseCalls);assert.equal(afterResize.bodyLayouts,beforeResize.bodyLayouts);assert.equal(afterResize.totalLayouts,beforeResize.totalLayouts,'height-only update repositions existing paragraphs, never reshapes them');
console.log('PASS: nested dynamic embed admission and geometry invalidation reuse all unchanged text paragraphs.');
const videoEmbed=new ctx.DrawnStructuredSource().prepare([{'@type':'pageBlockEmbedded',html:'',url:'https://cdn.test/movie.mp4?signature=abc',width:0,height:0,
 caption:{text:plain('Video caption')},poster_photo:{sizes:[{width:80,height:80,photo:{id:900}}]}}]);
assert.ok(videoEmbed);assert.equal(videoEmbed.blocks[0].widget.kind,'video-embed');assert.equal(videoEmbed.blocks[0].widget.avatar.id,900);
assert.equal(videoEmbed.blocks[0].widget.url,'https://cdn.test/movie.mp4?signature=abc');assert.equal(videoEmbed.blocks[1].source.content,'Video caption');
const videoGeometry=engine.prepare(ui,{...spec,source:videoEmbed});assert.equal(videoGeometry.widgets[0].height,280*9/16);
console.log('PASS: direct video uses the unified media island, preserves signed URL/poster/caption and defaults missing size to 16:9.');
const mathDoc=new ctx.DrawnStructuredSource().prepare([
  p('单缝缝宽暂算：'.repeat(5)),
  {'@type':'pageBlockMathematicalExpression',expression:'d = 0.1226'},
  {'@type':'pageBlockMathematicalExpression',expression:'d = (0.12260 \\pm 0.00023)\\,\\text{mm}'},
  {'@type':'pageBlockThinking',text:plain('Thinking...')},
  p({'@type':'richTexts',texts:[
    {'@type':'richTextMention',username:'hermes',text:plain('@hermes')},
    plain(' '),
    {'@type':'richTextHashtag',hashtag:'physics',text:plain('#physics')},
    plain(' '),
    {'@type':'richTextCashtag',cashtag:'TON',text:plain('$TON')},
    plain(' '),
    {'@type':'richTextBotCommand',bot_command:'calc',text:plain('/calc')},
    plain(' '),
    {'@type':'richTextMentionName',user_id:42,text:plain('Alice')},
    plain(' '),
    {'@type':'richTextBankCardNumber',bank_card_number:'4111222233334444',text:plain('card')},
    plain(' '),
    {'@type':'richTextReferenceLink',reference_name:'fn1',url:'https://fallback',text:plain('[1]')}
  ]}),
  p({'@type':'richTextReference',name:'FN1',text:plain('Footnote body')})
]);
assert.ok(mathDoc,'pageBlockMathematicalExpression and pageBlockThinking are accepted');
assert.equal(mathDoc.hasMath,true);
assert.equal(mathDoc.footnotes.get('fn1').content,'Footnote body');
assert.deepEqual(Array.from(mathDoc.blocks[4].source.links,l=>l.url),[
  'https://t.me/hermes','tg-hashtag:#physics','tg-hashtag:$TON','tg-command:/calc','tg://user?id=42','tg-copy:4111222233334444','#fn1'
]);
const mathPlan=engine.prepare(ui,{...spec,source:mathDoc,mathRevision:0});
assert.equal(mathPlan.tables.length,2);
assert.ok(mathPlan.tables[0].x>0,'short display formula block is horizontally centered inside wider bubble');
assert.equal(mathPlan.tables[1].x,0,'wide display formula block fills width and scrolls horizontally');
assert.equal(mathPlan.tables[1].layout.maths[0].expression,'d = (0.12260 \\pm 0.00023)\\,\\text{mm}');
assert.equal(Object.hasOwn(mathPlan.tables[0].layout.paragraph.native.parts[0].style,'backgroundRect'),false,'rendered math placeholder must not paint inline code background');
const prevMathMetrics=ctx.mathMetricsFor;
ctx.mathMetricsFor=()=>({width:160,height:160});
const tallMathPlan=engine.prepare(ui,{...spec,source:mathDoc,mathRevision:1});
ctx.mathMetricsFor=prevMathMetrics;
assert.equal(tallMathPlan.tables[0].layout.maths.length,1,'tall formula bitmap must expand row height instead of clipping out');
assert.ok(tallMathPlan.tables[0].layout.maths[0].rect.top>=0);
assert.ok(tallMathPlan.tables[0].height>=40);
console.log('PASS: pageBlockMathematicalExpression centered layout, tall formula expansion, pageBlockThinking, richTextReference/ReferenceLink and richText interactive entities.');
