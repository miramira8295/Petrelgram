import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/';
function ast(file){return ts.createSourceFile(file,fs.readFileSync(compiled+file,'utf8'),ts.ScriptTarget.Latest,true);}
function methods(file,name,names){const a=ast(file),c=a.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===name);
 return names.map(k=>c.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(a)===k).getText(a)).join('\n');}
const paint=[],glass=[],clicks=[];
const transition={combine(){return this;},animation(){return this;}};
const ctx=vm.createContext({systemMaterialState:{chatEnabled:false},immersiveMaterialAvailable:()=>true,
 Color:{Transparent:'transparent'},Alignment:{TopStart:0},HitTestMode:{Default:0,Block:1},Curve:{EaseOut:0},
 TransitionEffect:{OPACITY:transition,translate:()=>transition},KEY_POWER_SMOOTH_TRANSITIONS:'smooth',
 powerAnimationDuration:(_k,n)=>n,hdsVisualEffect:()=>undefined,chromeOutline:()=>({width:1}),
 NativeGlassHost:class{constructor(_parent,p){glass.push(p);}},ViewV2:{create(){}},
 dismissTopSheet:()=>false,slotIsDrawer:()=>false});
for(const name of ['Stack','Column','If','__Common__','Row'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{
 if(k==='backgroundColor'||k==='hitTestBehavior')paint.push([name,k,args[0]]);
 if(k==='onClick')clicks.push(args[0]);
}});
const run=code=>vm.runInContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
run(`class Panel {${methods('SuggestionPanel.ts','SuggestionPanel',['glassHostOn','initialRender'])}} globalThis.Panel=Panel;`);
const ui={observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_id,fn)=>fn(),
 commandHeader(){},commandList(){},mentionList(){}};
for(const enabled of [false,true])for(const supported of [false,true])for(const dark of [false,true]){
 ctx.systemMaterialState.chatEnabled=enabled;ctx.immersiveMaterialAvailable=()=>supported;
 const p=new ctx.Panel();Object.assign(p,ui,{surfaceWidth:300,surfaceHeight:180,appDark:dark,commandMode:true});
 paint.length=glass.length=clicks.length=0;p.initialRender();
 assert.equal(glass.length,enabled&&supported?1:0);
 if(glass.length){assert.equal(glass[0].surface,'control');assert.equal(glass[0].dark,dark);}
 assert.equal(paint.find(x=>x[1]==='hitTestBehavior')[2],0,'panel must not block command children');
 if(!glass.length)assert.notEqual(paint.find(x=>x[1]==='backgroundColor')[2],'transparent');
}
const p=new ctx.Panel();Object.assign(p,ui,{surfaceWidth:0,surfaceHeight:0});assert.equal(p.glassHostOn(),false);
run(`class Surface {${methods('ChatPageSurface.ts','ChatPageSurface',['commandSuggestionsVisible','composerPopupVisible','dismissComposerPopup','floatingActionsAllowed'])}} globalThis.Surface=Surface;`);
const surfaceAst=ast('ChatPageSurface.ts'),candidates=[];
function find(n){if(ts.isCallExpression(n)&&n.expression.getText(surfaceAst)==='this.observeComponentCreation2'){
 const text=n.getText(surfaceAst);if(text.includes('if (this.composerPopupVisible())')&&text.includes('Row.onClick'))candidates.push(text);
 }ts.forEachChild(n,find);}
find(surfaceAst);assert.ok(candidates.length);
run(`globalThis.renderDismiss=function(){${candidates.sort((a,b)=>a.length-b.length)[0]};};`);
let dismissed=0,active=true;
const surface=new ctx.Surface();Object.assign(surface,ui,{timeline:{initialMessageTransitionSettled:true},membershipState:'writable',
 showEmojiPanel:false,replyKeyboardVisible:false,command:{commandPanelActive:()=>active,dismissPanel:()=>{dismissed++;active=false;}},
 search:{mode:false},emojiDrawer:{shellHeight:0}});
clicks.length=paint.length=0;ctx.renderDismiss.call(surface);
assert.equal(clicks.length,1);assert.equal(paint.find(x=>x[1]==='hitTestBehavior')[2],1);
assert.equal(surface.floatingActionsAllowed(),false);clicks[0]();assert.equal(dismissed,1);
clicks.length=0;ctx.renderDismiss.call(surface);assert.equal(clicks.length,0);assert.equal(surface.floatingActionsAllowed(),true);
// The separate four-square reply keyboard uses the same outside interception.
let replyDismissed=0;
surface.replyKeyboardVisible=true;
surface.onDismissReplyKeyboard=()=>{replyDismissed++;surface.replyKeyboardVisible=false;};
clicks.length=0;ctx.renderDismiss.call(surface);assert.equal(clicks.length,1);
assert.equal(surface.floatingActionsAllowed(),false);clicks[0]();
assert.equal(replyDismissed,1);assert.equal(dismissed,1,'reply close must not dispatch a command action');
// Real system-back dispatcher closes commands before navigation/search/selection.
run(`class Page {${methods('ChatPage.ts','ChatPage',['handleBackPressed'])}} globalThis.Page=Page;`);
const page=new ctx.Page();Object.assign(page,{overlayState:{},viewer:{},viewerOpen:()=>false,
 command:surface.command,membershipState:'writable',showEmojiPanel:false,replyKbVisible:()=>false,
 selection:{active:false},search:{mode:false}});
active=true;assert.equal(page.handleBackPressed(),true);assert.equal(dismissed,2);
assert.equal(page.handleBackPressed(),false);
// A higher sheet must retain priority over the command popup.
active=true;ctx.dismissTopSheet=()=>true;assert.equal(page.handleBackPressed(),true);assert.equal(active,true);
console.log('command panel: PASS (compiled material/capability/theme matrix, outside tap interception, child hit testing, return-button visibility and real back priority)');

ctx.dismissTopSheet=()=>false;
page.replyKbVisible=()=>true;page.dismissReplyKeyboard=()=>{replyDismissed++;};
assert.equal(page.handleBackPressed(),true);assert.equal(replyDismissed,2);
run(`class ReplyClose {${methods('ChatPage.ts','ChatPage',['dismissReplyKeyboard'])}} globalThis.ReplyClose=ReplyClose;`);
ctx.closeSlot=(current,target)=>current===target?'none':current;ctx.SLOT_REPLY_KB='replyKeyboard';
let stops=0,focusClears=0,commandCloses=0;
const close=new ctx.ReplyClose();Object.assign(close,{bottomSlot:'replyKeyboard',composerFocused:true,
 replyKeyboardSendingKey:'pending',replyKbVisible:()=>close.bottomSlot==='replyKeyboard',
 command:{dismissPanel:()=>commandCloses++},applyBottomSlot:next=>{close.bottomSlot=next;},
 composerController:{stopEditing:()=>stops++},getUIContext:()=>({getFocusController:()=>({clearFocus:()=>focusClears++})})});
close.dismissReplyKeyboard();close.dismissReplyKeyboard();
assert.equal(close.bottomSlot,'none');assert.equal(close.composerFocused,false);
assert.equal(close.replyKeyboardSendingKey,'pending','dismiss must preserve in-flight sending state');
assert.equal(stops,1);assert.equal(focusClears,1);assert.equal(commandCloses,1);
// Actual compiled reply-panel material props and child hit testing.
const replyProps=[];ctx.SystemGlassSurface=class{constructor(_parent,p){replyProps.push(p);}};
ctx.PUV2ViewBase={contextStack:[]};ctx.Scroll=ctx.Column;ctx.BarState={Auto:0};
run(`class ReplyPanel {${methods('ReplyKeyboardPanel.ts','ReplyKeyboardPanel',['initialRender'])}} globalThis.ReplyPanel=ReplyPanel;`);
for(const enabled of [false,true])for(const supported of [false,true])for(const dark of [false,true]){
 ctx.systemMaterialState.chatEnabled=enabled;ctx.immersiveMaterialAvailable=()=>supported;
 const r=new ctx.ReplyPanel();Object.assign(r,ui,{rows:[],appDark:dark});paint.length=replyProps.length=0;
 r.initialRender();assert.equal(replyProps.length,1);assert.equal(replyProps[0].surface,'control');
 assert.equal(replyProps[0].dark,dark);assert.equal(replyProps[0].effectsEnabled,enabled&&supported);
 assert.equal(paint.find(x=>x[1]==='hitTestBehavior')[2],0);
}
console.log('reply panel: PASS (compiled material matrix, outside/back dismissal, idempotence, no cancellation of pending action or command reopening)');
