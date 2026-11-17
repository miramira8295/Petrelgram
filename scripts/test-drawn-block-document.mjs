// Exercise production parsing/layout and compiled row actions. Mock shaping
// verifies cache/geometry contracts, not font pixels or device performance.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { ctx, ui, data, style, group, layoutCounters } from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.DrawnRichTextLayouts=DrawnRichTextLayouts',ctx);
const entity=(kind,offset,length,extra={})=>({offset,length,type:{'@type':'textEntityType'+kind,...extra}});
const code='const x = "😀";\nreturn x;';
const quote='first https://a.test\nsecond\nthird\nfourth\nfifth https://b.test\nsixth 😀';
const content='intro\n'+code+'\n'+quote+'\nend';
const quoteStart=7+code.length;
const entities=[entity('PreCode',6,code.length,{language:'javascript'}),entity('ExpandableBlockQuote',quoteStart,quote.length),
 entity('Url',content.indexOf('https://a.test'),14),entity('Url',content.indexOf('https://b.test'),14),
 entity('CustomEmoji',quoteStart+quote.length-2,2,{custom_emoji_id:'emoji'})];
const source=new ctx.DrawnRichSourceCache().prepare(content,entities);
assert.ok(source.blocks);assert.equal(source.blocks.filter(b=>b.kind==='pre').length,1);
const engine=new ctx.DrawnRichTextLayouts();
const spec={source,maxWidthVp:300,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'blocks'};
const collapsed=engine.prepare(ui,spec);
assert.equal(collapsed.hits.filter(h=>h.link.action==='copy').length,1);
assert.equal(collapsed.hits.find(h=>h.link.action==='copy').link.label,code);
assert.equal(collapsed.emojis.length,0,'hidden quote emoji must not escape clipping');
assert.ok(!collapsed.hits.some(h=>h.link.url==='https://b.test'),'hidden quote link cannot be tapped');
const expand=collapsed.hits.find(h=>h.link.action==='quote');assert.equal(expand.link.blockOffset,quoteStart);
assert.equal(collapsed.hitIndex.find(expand.x+1,expand.y+1),expand);
const expanded=engine.prepare(ui,{...spec,expandedBlocks:[quoteStart]});
assert.ok(expanded.heightVp>collapsed.heightVp);assert.equal(expanded.emojis.length,1);
assert.ok(expanded.hits.some(h=>h.link.url==='https://b.test'));
assert.equal(expanded.hitsByUrl.has(''),false,'controls are not links/busy URL groups');
const before=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,spec),collapsed);
assert.deepEqual(layoutCounters(),before,'warm document lookup does not reparse or reshape');
const parts=collapsed.paragraph.parts;let painted=0,backgrounds=0;
for(const p of parts)p.paragraph.paint=()=>painted++;
collapsed.paragraph.paint({save(){},translate(){},restore(){},attachBrush(){},detachBrush(){},drawRoundRect(){backgrounds++;},drawRect(){}},0,0);
assert.equal(painted,parts.length);assert.equal(backgrounds,2);assert.deepEqual(layoutCounters(),before);
// Block state belongs to message + content, never to a physical recycled slot.
const row=Object.create(ctx.DrawnMessageRow.prototype);row.group=group(content,entities);row.data={...data};row.kind='text';
row.toggleDrawnQuote(quoteStart);assert.deepEqual(Array.from(row.rowExpandedBlocks()),[quoteStart]);
row.group={...row.group,head:{...row.group.head,rowId:987654}};assert.equal(row.rowExpandedBlocks(),undefined);
row.toggleDrawnQuote(4);assert.deepEqual(Array.from(row.rowExpandedBlocks()),[4]);
row.group={...row.group,head:{...row.group.head,text:'edited'}};assert.equal(row.rowExpandedBlocks(),undefined);
const documentPlan=new ctx.DrawnTextLayouts().prepare(ui,group(content,entities),data,style);
assert.ok(documentPlan);assert.ok(documentPlan.footerY>=documentPlan.captionY);
console.log('PASS: mixed code/expandable quote document, copy payload, hidden links/emoji, control hit index, immutable cache and message ownership.');

// Spoiler precedence: styled URL and custom emoji remain concealed; revealing
// restores exact source offsets without parsing again, and never launches URL.
const secret='visible hidden 😀';
const secretSource=new ctx.DrawnRichSourceCache().prepare(secret,[entity('Spoiler',8,9),entity('TextUrl',8,6,{url:'https://secret.test'}),entity('CustomEmoji',15,2,{custom_emoji_id:'secret'})]);
const hidden=engine.prepare(ui,{...spec,source:secretSource});
assert.equal(hidden.emojis.length,0);assert.ok(!hidden.hits.some(h=>h.link.url==='https://secret.test'));
assert.ok(!hidden.accessibilityText.includes('hidden'));assert.ok(!hidden.accessibilityText.includes('😀'));
assert.ok(hidden.hits.some(h=>h.link.action==='spoiler'));
const parses=layoutCounters().parseCalls;
const visible=engine.prepare(ui,{...spec,source:secretSource,spoilersRevealed:true});
assert.equal(visible.emojis.length,1);assert.ok(visible.hits.some(h=>h.link.url==='https://secret.test'));
assert.equal(visible.accessibilityText,secret);assert.equal(layoutCounters().parseCalls,parses);
console.log('PASS: concealed text/link/custom emoji/accessibility and reveal without reparsing.');
