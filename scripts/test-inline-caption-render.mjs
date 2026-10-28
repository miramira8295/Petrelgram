// Compare the real compiled ArkUI builders with a recording UI boundary.
// This checks construction/attributes/click closures, not native layout pixels.
// Run after assembleHap so the compiler output matches the current source.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE || 'typescript');const ts=imported.default||imported;
const read=p=>fs.readFileSync(new URL(p,import.meta.url),'utf8');
function compile(source){return ts.transpileModule(source.replace(/^import[\s\S]*?;\n/gm,'')
 .replace(/@Monitor\([^\n]*\)\s*/g,'').replace(/@(?:Param|Local|Require)\s*/g,'').replace(/\bexport /g,''),
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;}
const compiled=read('../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/MessageBubbleText.ts');
assert.ok(compiled.includes('inlineCaptionContent('),'assembleHap is required before this test');
const helpers=compile(read('../entry/src/main/ets/util/richText.ets')+'\n'+read('../entry/src/main/ets/util/inlineCaptionData.ets')+'\n'+read('../entry/src/main/ets/util/translationMode.ets'));
const enumOf=()=>new Proxy({},{get:(_o,k)=>String(k)});
function setup(compiledSource=compiled){
 const events=[],clicks=[],keys=[],actions=[];let nodeId=0,loops=0;
 function node(name){return new Proxy({},{get:(_o,method)=>(...args)=>{
  if(name==='If'||name==='ForEach') {if(name==='ForEach'&&method==='create')loops++;return;}
  if(method==='onClick'){clicks.push(args[0]);events.push([name,method,'handler']);return;}
  events.push([name,method,...args]);
 }});}
 class ViewV2{
  initParam(k,v){this[k]=v;} updateParam(k,v){this[k]=v;} finalizeConstruction(){}
  observeComponentCreation2(fn){fn(nodeId++,true);}
  ifElseBranchUpdateFunction(_index,fn){fn();}
  forEachUpdateFunction(_id,items,fn,keyFn){items.forEach((item,i)=>{keys.push(keyFn(item,i));fn(item,i);});}
 }
  const globals={ViewV2,ViewPU:ViewV2,Param:()=>{},Local:()=>{},Monitor:()=>{},Context:node('Context'),
  makeBuilderParameterProxy:(_name,fields)=>new Proxy({},{get:(_target,key)=>fields[key]?.()}),
  chatEnv:{msgTextSize:16,appearanceEpoch:1,linkNavBusy:'',translateReplaceOriginal:false,chatEffects:false,messageEffects:false,powerSaving:false},
  formatClockTime:()=> '09:05',viewsReserve:v=>v?`${v} `:'',timeLayerMinWidth:(max,v)=>Math.min(max,Math.max(v.forwardShown?v.forwardW:0,v.senderShown?v.senderW:0,v.commentsShown?v.commentsW:0)),
  bubbleMaxWidth:(w,gutter)=>w-gutter-40,BUBBLE_AVATAR_GUTTER_VP:44,
  bubbleTextFor:out=>out?'out-color':'in-color',COLOR_PRIMARY:'accent',
  COLOR_ICON_SECONDARY:'icon',COLOR_TEXT_SECONDARY:'secondary',
  animationDurationFor:(_on,_scroll,d)=>d,persistentAnimationDurationFor:(_a,_b,_c,d)=>d,scrollActiveNow:()=>false,
  linkTextHidesUrl:(text,url)=>text!==url,ViewStackProcessor:{visualState:s=>events.push(['state',s])},
  $r:(name)=>({resource:name})};
 for(const name of ['Color','FontWeight','FontStyle','TextDecorationType','ImageSpanAlignment','ImageFit','WordBreak','HorizontalAlign','Curve','TextOverflow','VerticalAlign','ItemAlign','PlayMode'])globals[name]=enumOf();
 for(const name of ['If','ForEach','Column','Row','Text','Span','ImageSpan','SymbolGlyph','LoadingProgress'])globals[name]=node(name);
 const ctx=vm.createContext(globals);vm.runInContext(helpers+compile(compiledSource)+'\nglobalThis.Caption=MessageBubbleText;',ctx);
 const c=new ctx.Caption(undefined,{context:{},presentation:{},actions:{}});
 c.actions={onLinkTap:(...args)=>actions.push(args),onCopyCode:()=>{},onToggleTranslation:()=>{},onRetryTranslation:()=>{}};
 function render(input,fast){
  events.length=0;clicks.length=0;keys.length=0;actions.length=0;loops=0;
  c.presentation={msg:input.msg,input:{text:input.text,entities:input.entities,maxWidth:0,mode:'caption'},showSenderName:true,layout:{contentWidth:390,isGroup:true,isChannel:false}};
  c.context={gestureClaimed:input.claimed,liveViews:'123',forwardLabelW:160,senderLabelW:140,commentsRowW:120,translationStatus:input.status??null};
  c.env={...globals.chatEnv,translateReplaceOriginal:input.replace,linkNavBusy:input.busy??''};
  c.revealedSpoilerKeys=[];c.expandedQuoteKeys=[];
  if(fast)c.inlineCaptionContent();else c.richContent({text:c.displayedMessageText(input.text),entities:c.displayedMessageEntities(input.entities),maxWidth:c.inlineMaxW()});
  const output=JSON.stringify(events);for(const click of clicks)click();
  return {output,actions:JSON.stringify(actions),spoilers:JSON.stringify(c.revealedSpoilerKeys),loops,keys:[...keys]};
 }
 return {render,c};
}
const entity=(kind,offset,length,value='')=>({offset,length,type:{'@type':`textEntityType${kind}`,url:value,custom_emoji_id:value}});
const fixtures=[['simple',[]],['bold and italic',[entity('Bold',0,4),entity('Italic',9,6)]],
 ['link rest',[entity('TextUrl',0,4,'https://a.example')]],['visit https://example.com',[]],
 ['hide text',[entity('Spoiler',0,4)]],['code text',[entity('Code',0,4)]],
 ['😀 custom',[entity('CustomEmoji',0,2,'123')]],['styled',[entity('Underline',0,6),entity('Strikethrough',0,6)]],
 ['one\ntwo #tag',[]],['link',[entity('TextUrl',0,4,'https://b.example')]]];
const old=setup(),fast=setup();let count=0;
for(const [text,entities] of fixtures)for(const out of [false,true])for(const reactions of [[],[{}]])for(const claimed of [false,true])for(const replace of [false,true]){
 const msg={id:1,rowId:1,date:1000,editDate:1,isOutgoing:out,contentType:'photo',reactions,forwardFrom:'',senderName:'Name',commentCount:0,
  translatedText:replace?'translated link':'',translatedEntities:replace?[entity('TextUrl',11,4,'https://translated.example')]:[],translationHidden:false,
  inlineCustomEmojiIds:['123'],inlineCustomEmojiPaths:['/emoji']};
 const input={text,entities,msg,claimed,replace};const a=old.render(input,false),b=fast.render(input,true);
 assert.equal(b.output,a.output,`render ${text} ${out} ${replace}`);assert.equal(b.actions,a.actions);assert.equal(b.spoilers,a.spoilers);
 assert.equal(a.loops,2);assert.equal(b.loops,1);count++;
}
// Same text and same position with a changed target must invalidate cached handlers.
const msg={id:2,rowId:2,isOutgoing:false,contentType:'photo',reactions:[],translatedText:'',inlineCustomEmojiIds:[],inlineCustomEmojiPaths:[]};
const a=fast.render({text:'link',entities:[entity('TextUrl',0,4,'https://a.example')],msg},true);
const b=fast.render({text:'link',entities:[entity('TextUrl',0,4,'https://b.example')],msg},true);
assert.notEqual(a.keys[0],b.keys[0]);assert.notEqual(a.actions,b.actions);
console.log(`Inline caption render: ${count} compiled-builder comparisons passed; loop count 2 -> 1; click target reuse passed`);

// Rebinding an unchanged caption must not re-read observed source state for
// every key. Exercise the actual generated builder with different run counts.
const preparationCounts=[];
for (const runCount of [1,8,32]) {
 const host=setup();let prepared=0,translationChecks=0;
 const prepare=host.c.inlineCaptionSegment,translation=host.c.replacementTranslationShown;
 host.c.inlineCaptionSegment=function(...args){prepared++;return prepare.apply(this,args);};
 host.c.replacementTranslationShown=function(...args){translationChecks++;return translation.apply(this,args);};
 const input={text:'x'.repeat(runCount),entities:Array.from({length:Math.ceil(runCount/2)},(_,i)=>entity('Bold',i*2,1)),
  msg:{id:1,rowId:1,date:1000,editDate:0,isOutgoing:false,contentType:'photo',reactions:[],forwardFrom:'',senderName:'',translatedText:'',translatedEntities:[],translationHidden:false,inlineCustomEmojiIds:[],inlineCustomEmojiPaths:[]}};
 host.render(input,true);const items=host.c.inlineCaptionCache.runs();prepared=0;translationChecks=0;
 const rendered=host.render(input,true);
 assert.equal(rendered.keys.length,runCount);assert.strictEqual(host.c.inlineCaptionCache.runs(),items);
 assert.equal(prepared,2);assert.equal(translationChecks,2);
 preparationCounts.push({runs:runCount,prepared,translationChecks});
}
// Translation is mutable on the same observed MessageEntry. Changing mode,
// hidden state, text or its URL must select/prepare the current source each time.
const live=setup(),reference=setup();
const liveInput={text:'original link',entities:[entity('TextUrl',9,4,'https://original.example')],replace:false,
 msg:{id:1,rowId:1,date:1000,editDate:0,isOutgoing:false,contentType:'photo',reactions:[],forwardFrom:'',senderName:'',translatedText:'translated link',translatedEntities:[entity('TextUrl',11,4,'https://translated.example')],translationHidden:false,inlineCustomEmojiIds:[],inlineCustomEmojiPaths:[]}};
let translationCases=0;
for (const change of [()=>{},()=>liveInput.replace=true,()=>liveInput.msg.translationHidden=true,()=>liveInput.msg.translationHidden=false,
 ()=>liveInput.msg.translatedEntities=[entity('TextUrl',11,4,'https://changed.example')],
 ()=>{liveInput.msg.translatedText='new link';liveInput.msg.translatedEntities=[entity('TextUrl',4,4,'https://new.example')];},
 ()=>liveInput.replace=false]) {
 change();const actual=live.render(liveInput,true),expected=reference.render(liveInput,false);
 assert.equal(actual.output,expected.output);assert.equal(actual.actions,expected.actions);translationCases++;
}
console.log(`Prepared caption: ${JSON.stringify(preparationCounts)}; ${translationCases} live translation transitions passed`);

// Text has no decoration and Span defaults to None / transparent background.
// Ordinary, bold and italic content should not pay for redundant setters on
// first construction. Decorated/code/busy-link branches must still set their styles.
const styleHost=setup();
const styleMsg={id:1,rowId:1,date:1000,editDate:0,isOutgoing:false,contentType:'photo',reactions:[{}],forwardFrom:'',senderName:'',translatedText:'',translatedEntities:[],translationHidden:false,inlineCustomEmojiIds:[],inlineCustomEmojiPaths:[]};
let styleCases=0;
for(const kind of ['', 'Bold', 'Italic', 'Underline', 'Strikethrough', 'Code', 'TextUrl', 'Spoiler']) {
 const result=styleHost.render({text:'text',entities:kind?[entity(kind,0,4,'https://target.example')]:[],msg:styleMsg},true);
 const events=JSON.parse(result.output),decorations=events.filter(e=>e[0]==='Span'&&e[1]==='decoration'),backgrounds=events.filter(e=>e[0]==='Span'&&e[1]==='textBackgroundStyle');
 const ordinary=['','Bold','Italic','TextUrl'].includes(kind);
 assert.equal(decorations.length,ordinary?0:1);assert.equal(backgrounds.length,ordinary?0:1);
 assert.equal(events.filter(e=>e[0]==='Text'&&e[1]==='decoration').length,0);
 assert.equal(events.filter(e=>e[0]==='Span'&&['fontWeight','fontStyle','fontFamily','fontColor'].includes(e[1])).length,4);
 styleCases++;
}
console.log(`Cold Span construction: ${styleCases} style cases passed; ordinary/bold/italic and idle-link default style setters 6 -> 4`);

// Optional real pre-change compiler output gives a cross-version differential.
// Only omit no-op native defaults; compare all remaining geometry, styles,
// click handlers, actions, spoiler changes and keys without normalisation.
if(process.env.CAPTION_BASELINE_COMPILED) {
 const before=setup(fs.readFileSync(process.env.CAPTION_BASELINE_COMPILED,'utf8')),after=setup();
 function effectiveOutput(output){return JSON.stringify(JSON.parse(output).filter(e=> !(e[0]==='Span'&&(
  (e[1]==='decoration'&&e[2].type==='None')||
  (e[1]==='textBackgroundStyle'&&e[2].color==='Transparent'&&e[2].radius===0)))));}
 let comparisons=0;
 const flags=['Bold','Italic','Underline','Strikethrough','Code','Spoiler'];
 for(let mask=0;mask<64;mask++)for(const outgoing of [false,true])for(const mode of ['normal','link','busy','emoji','pendingEmoji']) {
  const entities=flags.flatMap((kind,i)=>mask&(1<<i)?[entity(kind,0,4)]:[]);
  if(mode==='link'||mode==='busy')entities.push(entity('TextUrl',0,4,'https://target.example'));
  if(mode==='emoji'||mode==='pendingEmoji')entities.push(entity('CustomEmoji',0,4,'123'));
  const msg={...styleMsg,isOutgoing:outgoing,inlineCustomEmojiIds:['123'],inlineCustomEmojiPaths:mode==='emoji'?['/emoji']:[]};
  const input={text:'text rest',entities,msg,busy:mode==='busy'?'https://target.example':''};
  const a=before.render(input,true),b=after.render(input,true);
  assert.equal(effectiveOutput(b.output),effectiveOutput(a.output),`${mask}/${outgoing}/${mode}`);
  assert.equal(b.actions,a.actions);assert.equal(b.spoilers,a.spoilers);assert.deepEqual(b.keys,a.keys);comparisons++;
 }
 console.log(`Cold Span before/after: ${comparisons} generated-builder differentials passed`);
}
