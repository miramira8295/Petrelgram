// Width policy and real layout engines; single/split at identical content width must invalidate caches.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {ctx,load,root,ui,data,style,group} from './test-drawn-text-row.mjs';
const width=vm.runInContext('messageBubbleMaxWidth',ctx);
const legacy=vm.runInContext('bubbleMaxWidth',ctx);
const plain=group('long ordinary message '.repeat(30));
for(const w of [0,40,180,390,960])for(const gutter of [0,41]){
 assert.equal(width(w,gutter,plain.head,false),legacy(w,gutter));
 assert.equal(width(w,gutter,plain.head,true),Math.max(0,Math.min(600,w-80-gutter)));
}
assert.equal(width(390,0,plain.head,true),310);assert.equal(width(390,41,plain.head,true),269);
let cases=0;
for(const kind of ['bold','italic','code','pre','preCode','blockquote','expandableBlockQuote','textUrl','customEmoji']){
 const g=group(plain.head.text,[{offset:0,length:12,type:{'@type':'textEntityType'+kind[0].toUpperCase()+kind.slice(1)}}]);
 assert.equal(width(390,0,g.head,true),358);cases++;
}
for(const patch of [{replyToMessageId:20},{replyText:'selected quote'},{replySenderName:'sender'},
 {contentType:'richMessage',richBlocks:[]},{richBlocks:[]},{linkUrl:'https://example.com'},
 {translatedText:'translation'},{contentType:'checklist'},{contentType:'photo'}]){
 assert.equal(width(390,0,{...plain.head,...patch},true),358);cases++;
}
// O(1): checking entity length must never iterate or parse a large body.
const entities=new Proxy(Array(100000),{get(t,k){assert.notEqual(k,Symbol.iterator);assert.ok(k==='length');return t[k];}});
assert.equal(width(390,0,{...plain.head,textEntities:entities},true),358);
const engine=new ctx.DrawnTextLayouts();
const single=engine.prepare(ui,plain,{...data,contentWidth:390,splitLayout:false},style);
const split=engine.prepare(ui,plain,{...data,contentWidth:390,splitLayout:true},style);
assert.ok(split.width<single.width);assert.ok(split.height>=single.height);
const restored=engine.prepare(ui,plain,{...data,contentWidth:390,splitLayout:false},style);
assert.equal(restored.width,single.width);assert.equal(restored.height,single.height);
for(const g of [group(plain.head.text,[{offset:0,length:12,type:{'@type':'textEntityTypeBold'}}]),
 group('const hello = "world";\n'.repeat(12),[{offset:0,length:120,type:{'@type':'textEntityTypePreCode',language:'js'}}]),
 {...plain,head:{...plain.head,replyToMessageId:2,replyText:'quoted message',replySenderName:'name'}}]){
 const e=new ctx.DrawnTextLayouts();
 const a=e.prepare(ui,g,{...data,contentWidth:390,splitLayout:false},style);
 const b=e.prepare(ui,g,{...data,contentWidth:390,splitLayout:true},style);
 assert.ok(a&&b);assert.equal(b.width,a.width);assert.equal(b.height,a.height);
 assert.equal(b.caption.widthVp,a.caption.widthVp);
}
load(root+'util/rowPageInputs.ets',['rowPageKeyPart','buildRowPageInputs']);
const page={isGroup:false,isChannel:false,translationActive:false,editingActive:false,liveCallActive:false,liveGroupCallId:0,
 liveLocationMessageId:0,autoplayMuted:true,appearanceEpoch:0,materialEpoch:0,appDark:false,selectionActive:false,
 chatContentWidth:390,canReply:true,playSlotKey:'',freshSinceId:0,pausedAnimationIds:[],forcedAnimationIds:[],failedAnimationIds:[],paidMediaPendingIds:[]};
assert.notEqual(ctx.rowPageKeyPart(page),ctx.rowPageKeyPart({...page,splitLayout:true}));
assert.equal(ctx.buildRowPageInputs({...page,splitLayout:true}).splitLayout,true);
load(root+'util/messageTextInput.ets',['MessageTextPresentationCache']);
const inputs=new ctx.MessageTextPresentationCache();
const a=inputs.prepare(plain.head,true,{contentWidth:390,isGroup:false,isChannel:false,splitLayout:false},'abc',[],200,'body');
const b=inputs.prepare(plain.head,true,{contentWidth:390,isGroup:false,isChannel:false,splitLayout:true},'abc',[],200,'body');
assert.equal(a.layout.splitLayout,false);assert.equal(b.layout.splitLayout,true);
// Use the app's actual split policy; a wide portrait window / forced single is still single.
load(root+'util/layoutBreakpoint.ets',['isSplitByBreakpoint']);
const policy=fs.readFileSync(root+'pages/chat/ChatPage.ets','utf8');
assert.match(policy,/splitLayout: isSplitByBreakpoint\(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait\)/);
assert.equal(ctx.isSplitByBreakpoint(2,0,true,false),false);
assert.equal(ctx.isSplitByBreakpoint(2,0,false,true),false);
console.log(`PASS: ${cases} rich/Markdown/quote exclusions, O(1) eligibility, real plain and protected layouts, same-width split/restore caches and presentation propagation.`);
for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout','DrawnSingleMediaLayout'])load(root+'pages/chat/'+f+'.ets',f==='DrawnSingleMediaLayout'?['DrawnSingleMediaLayouts']:[]);
const originalMediaWidth=vm.runInContext('mediaThumbWidth',ctx);
ctx.mediaThumbWidth=(w,g)=>originalMediaWidth(w,g,'tablet');
for(const protectedBody of [false,true]){
 const g=group('caption with code '.repeat(40),protectedBody?[{offset:0,length:7,type:{'@type':'textEntityTypeCode'}}]:[]);
 Object.assign(g.head,{contentType:'photo',photoWidth:1000,photoHeight:1000,photoPath:'',photoMini:'',photoFileId:4});
 const e=new ctx.DrawnSingleMediaLayouts();
 const a=e.prepare(ui,g,{...data,contentWidth:800,splitLayout:false},style);
 const b=e.prepare(ui,g,{...data,contentWidth:800,splitLayout:true},style);
 assert.ok(a&&b);assert.equal(a.grid.width,280);
 if(protectedBody){assert.equal(a.grid.width,b.grid.width);assert.equal(a.width,b.width);assert.equal(a.height,b.height);}
 else{assert.ok(b.width<a.width);assert.ok(b.height>a.height);}
 const back=e.prepare(ui,g,{...data,contentWidth:800,splitLayout:false},style);assert.equal(back.width,a.width);
}
console.log('PASS: single-media tablet cap is split-only; formatted captions preserve full geometry; split/restore invalidates media cache.');

// The compatibility renderers must obey the same policy, including keyboard width.
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
for(const name of ['MessageBubbleShell','MessageBubble','BubbleContentLayout','BubbleInlineKeyboard','MessageBubbleText','LegacyTextMessageBubble','LightweightPlainTextBubble']){
 const source=fs.readFileSync(root+'pages/chat/'+name+'.ets','utf8');
 const start=source.indexOf('  private bubbleMaxW(): number {');assert.ok(start>=0);
 const ast=ts.createSourceFile('width.ts','class Probe {\n'+source.slice(start),ts.ScriptTarget.Latest,true);
 const m=ast.statements[0].members[0].getText(ast);
 vm.runInContext(ts.transpileModule(`globalThis.WidthProbe=class {${m}};`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const p=new ctx.WidthProbe();Object.assign(p,{msg:plain.head,data:{contentWidth:390,splitLayout:true},contentWidth:390,splitLayout:true,isGroup:false,avatarReserve:()=>0});
 assert.equal(p.bubbleMaxW(),310,name);p.msg={...plain.head,replyToMessageId:3};assert.equal(p.bubbleMaxW(),358,name);
 p.msg=plain.head;p.data.splitLayout=false;p.splitLayout=false;assert.equal(p.bubbleMaxW(),358,name);
}
console.log('PASS: all seven compatibility renderer/keyboard width consumers share split-only/plain-only policy.');
