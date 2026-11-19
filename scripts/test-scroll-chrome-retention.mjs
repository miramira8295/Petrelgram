import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/';
function method(file,name){const s=fs.readFileSync(root+file+'.ts','utf8'),a=ts.createSourceFile(file,s,ts.ScriptTarget.Latest,true),c=a.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===file);return c.members.find(n=>n.name?.getText(a)===name).getText(a);}
const calls=[],children=[],glassHosts=[];let tapped=0;
const ui=name=>new Proxy({}, {get:(_,key)=>(...args)=>calls.push([name,key,...args])});
const enums=new Proxy({}, {get:(_,k)=>k});
const ctx=vm.createContext({Context:{animation(){}},__Common__:ui('__Common__'),Stack:ui('Stack'),Row:ui('Row'),Column:ui('Column'),Text:ui('Text'),If:ui('If'),
 Button:ui('Button'),SymbolGlyph:ui('SymbolGlyph'),LoadingProgress:ui('LoadingProgress'),
 Visibility:enums,HitTestMode:enums,Alignment:enums,FlexAlign:enums,FontWeight:enums,TextAlign:enums,VerticalAlign:enums,
 Color:enums,ButtonType:enums,Curve:enums,EffectScope:enums,EffectDirection:enums,
 BounceSymbolEffect:class{},ViewStackProcessor:{visualState(){}},$r:x=>x,
 COLOR_PRIMARY:'primary',COLOR_TEXT_PRIMARY:'text',COLOR_ON_PRIMARY:'white',KEY_POWER_SMOOTH_TRANSITIONS:'smooth',
 plainGlassFill:x=>x,plainBackdropBlur:()=>16,hdsVisualEffect:(kind,active)=>({kind,active}),powerAnimationDuration:()=>0,
 unreadBadgeText:n=>String(n),unreadBadgeWidth:()=>20,unreadBadgeOffsetX:()=>30,BADGE_HEIGHT:20,plural:()=>'',
 NativeGlassHost:class{constructor(_owner,params){glassHosts.push(params);}},
 ScrollFab:class{constructor(_owner,params){children.push(params);}},ViewPU:{create(){}},ViewV2:{create(){}}
});
const run=s=>vm.runInContext(ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const init=o=>{o.observeComponentCreation2=cb=>cb(1,true);o.ifElseBranchUpdateFunction=(_,cb)=>cb();return o;};
run(`class Surface {${method('ChatPageSurface','floatingActionsAllowed')} ${method('ChatPageSurface','floatingActions')}} globalThis.Surface=Surface;`);
const surface=init(new ctx.Surface());Object.assign(surface,{search:{mode:false},emojiDrawer:{shellHeight:0},showEmojiPanel:false,
 hasReturnTarget:false,unreadMentions:{count:0,busy:false,next(){}},pendingJumpId:0,unreadBadge:3,scrollToBottomBusy:false,bottomChromeH:76,chromeIconColor:'ink',onReturnTap:()=>tapped++});
for(const [target,mention] of [[false,0],[true,0],[false,2],[true,2]]){
 surface.hasReturnTarget=target;surface.unreadMentions.count=mention;children.length=0;calls.length=0;surface.floatingActions();
 assert.equal(children.length,1+(mention>0?1:0));assert.equal(children[0].active,target);
 const margins=calls.filter(c=>c[1]==='margin').map(c=>c[2]);
 assert.equal(margins[0].bottom,84);if(mention)assert.equal(margins[1].bottom,84+(target?60:0));
}
for(const gate of ['search','emoji','drawer']){
 surface.search.mode=gate==='search';surface.showEmojiPanel=gate==='emoji';surface.emojiDrawer.shellHeight=gate==='drawer'?100:0;
 children.length=0;surface.floatingActions();assert.equal(children.length,1);assert.equal(children[0].active,false);
}
run(`class Fab {${method('ScrollFab','initialRender')}} globalThis.Fab=Fab;`);
const fab=init(new ctx.Fab());Object.assign(fab,{active:false,busy:false,mention:false,unreadCount:3,iconColor:'ink',onTap:()=>tapped++});
for(const active of [false,true])for(const busy of [false,true]){
 fab.active=active;fab.busy=busy;calls.length=0;glassHosts.length=0;fab.initialRender();
 assert.equal(glassHosts.length,1);
 assert.equal(glassHosts[0].effectsEnabled,false,'chat glass host must preserve disabled blur/shadow');
 assert.ok(!calls.some(c=>['backdropBlur','backgroundEffect','shadow'].includes(c[1])));
 assert.ok(calls.some(c=>c[1]==='visibility'&&c[2]===(active?'Visible':'Hidden')));
 assert.ok(calls.some(c=>c[1]==='accessibilityLevel'&&c[2]===(active?'auto':'no-hide-descendants')));
 const before=tapped;for(const c of calls.filter(c=>c[1]==='onClick'))c[2]();
 assert.equal(tapped-before,active&&!busy?2:0,'hidden/busy button AND badge cannot dispatch');
}
const date=method('FloatingDateOverlay','initialRender');
assert.doesNotMatch(date,/ifElseBranchUpdateFunction/,'date subtree is resident even before first label');
assert.match(date,/no-hide-descendants/);assert.match(date,/state\.shown/);
console.log('PASS: retained return control, mention-only/both positions, drawer/search/emoji gates; disabled effects/accessibility/click guards including badge; resident date subtree.');

run(`class Glass {${method('NativeGlassHost','initialRender')}} globalThis.Glass=Glass;`);
for(const tapHost of [false,true]) {
 const glass=init(new ctx.Glass());
 Object.assign(glass,{effectsEnabled:false,tapHost,hostWidth:46,hostHeight:46,hostRadius:23,onHostTap:()=>tapped++});
 calls.length=0;glass.initialRender();
 assert.ok(calls.some(c=>c[1]==='backgroundColor'));
 assert.ok(!calls.some(c=>['backdropBlur','backgroundEffect','shadow','attributeModifier'].includes(c[1])));
 const before=tapped;for(const c of calls.filter(c=>c[1]==='onClick'))c[2]();
 assert.equal(tapped-before,tapHost?1:0,'plain fallback preserves delegated clicks without enabling effects');
}
console.log('PASS: real disabled glass host retains fill and delegated clicks without filters or material allocation.');
