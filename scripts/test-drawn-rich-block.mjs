// Run after HAP build. Test compiled per-block dispatch and cached-plan inputs.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript');const ts=imported.default||imported;
const base='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
let rtl=false,warnings=0,clicks=0,reset=[];
class ViewV2 {resetParam(k,v){this[k]=v;}resetComputed(k){reset.push(k);}}
const ctx=vm.createContext({ViewV2,ViewPU:class{},DRAWN_RICH_TEXT_ENABLED:true,
 textMeasureEnvironment:{epoch:0},drawnTextUsesRtlLayout:()=>rtl,
 drawnRichSegmentSource:s=>s.source,bubbleTextFor:o=>o?'out':'in',COLOR_PRIMARY:'accent',logW:()=>warnings++});
const source=fs.readFileSync(base+'pages/chat/DrawnRichTextBlock.ts','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/@(?:Param|Event|Local|Computed)\s*/g,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Block=DrawnRichTextBlock;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const v=Object.create(ctx.Block.prototype),paragraphSource={content:'a link',links:[{}],targets:new Set(['https://example.org'])};
v.segment={source:paragraphSource};v.env={bubbleMaterialOn:false,langEpoch:0,msgTextSize:16,appearanceEpoch:0,linkNavBusy:''};
v.maxWidthVp=210;v.reserve=' 12:34';v.outgoing=false;v.getUIContext=()=>({});v.layouts={prepare:(_ui,s)=>s};
assert.equal(v.plan.maxWidthVp,210);assert.equal(v.plan.reserve,' 12:34');assert.equal(v.plan.minWidthVp,0);
v.maxWidthVp=150;assert.equal(v.plan.maxWidthVp,150);v.outgoing=true;assert.equal(v.plan.foreground,'out');
v.reserve='';assert.equal(v.plan.reserve,'','non-last block must not reserve footer twice');
v.env.linkNavBusy='https://unrelated.org';assert.notEqual(v.plan,null);
v.env.linkNavBusy='https://example.org';assert.notEqual(v.plan,null);v.env.linkNavBusy='';
v.env.bubbleMaterialOn=true;assert.equal(v.plan,null);v.env.bubbleMaterialOn=false;
rtl=true;assert.equal(v.plan,null);rtl=false;
v.env.langEpoch++;assert.ok(v.plan.environment.includes(':1:'));
v.segment={source:null};assert.equal(v.plan,null);
v.segment={source:paragraphSource};v.layouts={prepare(){throw Error('native unavailable');}};
assert.equal(v.plan,null);assert.equal(v.plan,null);assert.equal(warnings,1,'native failure logs once and preserves fallback');
const replacement={source:{...paragraphSource,content:'edited'}};
v.resetStateVarsOnReuse({segment:replacement,maxWidthVp:90,outgoing:false,reserve:'x',fallback(){},onLinkTap(){clicks++;}});
assert.equal(v.segment,replacement);assert.equal(v.maxWidthVp,90);assert.deepEqual(reset,['plan']);v.onLinkTap({});assert.equal(clicks,1);
console.log('PASS: compiled block width/footer/theme/language/busy/RTL/material/failure/reuse inputs; unsupported blocks preserve native fallback.');
