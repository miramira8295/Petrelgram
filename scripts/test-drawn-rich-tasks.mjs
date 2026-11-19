import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,load,root,ui,layoutCounters} from './test-drawn-text-row.mjs';
if(typeof ctx.richMessageTaskIndex!=='function')load(root+'util/richMessageTaskEdit.ets');
vm.runInContext('globalThis.TaskSource=DrawnStructuredSource;globalThis.TaskLayouts=DrawnRichTextLayouts;',ctx);
const plain=text=>({'@type':'richTextPlain',text}),p=text=>({'@type':'pageBlockParagraph',text:typeof text==='string'?plain(text):text});
const task=(text,checked=false)=>({'@type':'pageBlockListItem',has_checkbox:true,is_checked:checked,blocks:[p(text)]});
const link={'@type':'richTextUrl',text:plain('inner link'),url:'https://example.test/task'},first=task(link),second=task('done',true);
const nodes=[{'@type':'pageBlockList',items:[first,second]}],compiler=new ctx.TaskSource(),layouts=new ctx.TaskLayouts();
const spec={maxWidthVp:280,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'rich-tasks'};
const writable=compiler.prepare(nodes,'',true),plan=layouts.prepare(ui,{...spec,source:writable});
const toggles=plan.hits.filter(h=>h.link.action==='rich-task-toggle');assert.equal(toggles.length,2);assert.deepEqual(Array.from(toggles,h=>h.link.taskId),[0,1]);assert.deepEqual(Array.from(toggles,h=>h.link.taskChecked),[false,true]);
for(const hit of toggles){assert.equal(hit.x,0);assert.ok(hit.widthVp<=24);assert.equal(hit.accessible,true);assert.equal(plan.hitIndex.find(hit.x+1,hit.y+1).link.action,'rich-task-toggle');}
const bodyLink=plan.hits.find(h=>h.link.url==='https://example.test/task');assert.ok(bodyLink.x>=24);assert.equal(plan.hitIndex.find(bodyLink.x+1,bodyLink.y+1).link.url,'https://example.test/task');
const before=layoutCounters();for(let i=0;i<1000;i++){assert.equal(compiler.prepare(nodes,'',true),writable);assert.equal(layouts.prepare(ui,{...spec,source:writable}),plan);}assert.deepEqual(layoutCounters(),before);
const readonly=compiler.prepare(nodes,'',false),readonlyPlan=layouts.prepare(ui,{...spec,source:readonly});assert.equal(readonlyPlan.hits.filter(h=>h.link.action==='rich-task-toggle').length,0);assert.ok(readonlyPlan.hits.some(h=>h.link.url==='https://example.test/task'));
// Native update JSON replaces objects. Equal task text must still retain the
// same leaf source/paragraph instead of reshaping all body text on every check.
const initial=compiler.prepare(nodes,'',true),text0=initial.blocks[0].source.blocks[0].source;
const edited=JSON.parse(JSON.stringify(nodes));edited[0].items[0].is_checked=true;
const changed=compiler.prepare(edited,'',true);assert.equal(changed.blocks[0].source.blocks[0].source,text0);const updated=layouts.prepare(ui,{...spec,source:changed});
function nativeLeaves(paragraph){const result=new Map(),pending=[paragraph];while(pending.length){const p=pending.pop();if(p.native)result.set(p.native.content,p.native);for(const part of p.parts??[])pending.push(part.paragraph);}return result;}
const oldNative=nativeLeaves(plan.paragraph),newNative=nativeLeaves(updated.paragraph);assert.equal(oldNative.get('inner link'),newNative.get('inner link'),'checkbox edit preserves body paragraph');assert.equal(oldNative.get('done'),newNative.get('done'),'unchanged task paragraph remains retained');
assert.equal(updated.hits.find(h=>h.link.taskId===0).link.taskChecked,true);
let nested=p('nested body');for(let i=0;i<40;i++)nested={'@type':'pageBlockDetails',header:plain('details'),is_open:true,blocks:[nested]};
const deepNodes=[{'@type':'pageBlockList',items:[{...task(link),blocks:[p(link),nested]}]}];
const deepSource=compiler.prepare(deepNodes,'',true),deepPlan=new ctx.TaskLayouts().prepare(ui,{...spec,source:deepSource});const deepHit=deepPlan.hits.find(h=>h.link.action==='rich-task-toggle');assert.ok(deepHit);assert.equal(deepHit.link.taskId,0);assert.equal(deepPlan.hitIndex.find(deepHit.x+1,deepHit.y+1).link.action,'rich-task-toggle');
const unsupported=compiler.prepare([...nodes,{'@type':'pageBlockEmbedded',html:'<p>unsupported input</p>',width:200,height:50}],'',true);assert.ok(unsupported);const disabled=new ctx.TaskLayouts().prepare(ui,{...spec,source:unsupported});assert.equal(disabled.hits.filter(h=>h.link.action==='rich-task-toggle').length,0,'readable but uneditable content must not expose fake persistence');
console.log('PASS: structured task marker-only hit areas, link isolation, readonly input gating, 1000 source/layout hits, equivalent edit leaf reuse and normal/deep action/accessibility geometry.');
