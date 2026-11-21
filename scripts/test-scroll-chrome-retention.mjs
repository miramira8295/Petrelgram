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
 assert.equal(glassHosts[0].effectsEnabled ?? true,true,'return control uses the shared material policy');
 assert.ok(!calls.some(c=>['backdropBlur','backgroundEffect','shadow'].includes(c[1])));
 assert.ok(calls.some(c=>c[1]==='visibility'&&c[2]===(active?'Visible':'Hidden')));
 assert.ok(calls.some(c=>c[1]==='accessibilityLevel'&&c[2]===(active?'auto':'no-hide-descendants')));
 const before=tapped;for(const c of calls.filter(c=>c[1]==='onClick'))c[2]();
 assert.equal(tapped-before,active&&!busy?2:0,'hidden/busy button AND badge cannot dispatch');
}
const date=method('FloatingDateOverlay','initialRender');
assert.doesNotMatch(date,/ifElseBranchUpdateFunction/,'date subtree is resident even before first label');
assert.match(date,/no-hide-descendants/);assert.match(date,/state\.shown/);
console.log('PASS: retained return control, mention-only/both positions, drawer/search/emoji gates; material host and accessibility/click guards including badge; resident date subtree.');

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

run(`class SharedGlass {${['initialRender','w','h','glassOn'].map(n=>method('SystemGlassSurface',n)).join('\n')}} globalThis.SharedGlass=SharedGlass;`);
const plain=init(new ctx.SharedGlass());
Object.assign(plain,{effectsEnabled:false,plainOutline:true,radius:18,fixedWidth:0,fixedHeight:0,mw:0,mh:0,fill:false,content:()=>{}});
calls.length=0;glassHosts.length=0;plain.initialRender();
assert.equal(glassHosts.length,0,'plain surface must not create a second material/measurement subtree');
assert.ok(calls.some(c=>c[1]==='border'&&c[2].width===0.5));
const area=calls.find(c=>c[1]==='onAreaChange')[2];
for(let i=0;i<1000;i++)area({}, {width:300+i,height:48});
assert.equal(plain.mw,0);assert.equal(plain.mh,0,'disabled material geometry never publishes local size');
assert.ok(calls.some(c=>c[1]==='backgroundColor'&&c[2]?.type===10001));
console.log('PASS: plain shared surface paints in its existing container with outline, no material child and no size-state writes.');

// Hidden pinned banner used to produce height -2 and leave a full-parent
// translucent surface alive. Replay real bindings, not just the height helper.
run(fs.readFileSync('entry/src/main/ets/util/chatChromeGeometry.ets','utf8').replace(/\bexport /g,''));
run(`class Banners {${['initialRender','hasContent','liveShowing','containerHeight'].map(n=>method('TopBanners',n)).join('\n')}} globalThis.Banners=Banners;`);
const surfaces=[];
ctx.SystemGlassSurface=class{constructor(_owner,params){surfaces.push(params);}};
const effect={combine(){return this;},animation(){return this;}};
ctx.TransitionEffect={OPACITY:effect,translate:()=>effect};
const banners=init(new ctx.Banners());
let pinned=false,music=false;
Object.assign(banners,{appDark:false,actionBarKind:'',grabSlot:-1,grabDX:0,grabDY:0,
 topCard:{pinnedVisible:()=>pinned,musicVisible:()=>music,liveGroupCallId:0,liveCallIsActive:false}});
for(let cycle=0;cycle<3;cycle++)for(let mask=0;mask<=15;mask++){
 pinned=!!(mask&1);music=!!(mask&2);const live=!!(mask&4),action=!!(mask&8);
 banners.topCard.liveGroupCallId=live?1:0;banners.topCard.liveCallIsActive=live;banners.actionBarKind=action?'join':'';
 surfaces.length=0;calls.length=0;banners.initialRender();
 const rows=Number(pinned||music)+Number(live)+Number(action);
 const height=rows?rows*54+(rows-1)*.5:0;
 assert.equal(banners.containerHeight(),height,'hidden banner height must be zero, never negative');
 assert.equal(surfaces.length,rows?1:0,'no material/background subtree when all rows collapse');
 assert.equal(calls.find(c=>c[0]==='Stack'&&c[1]==='height')[2],height);
 assert.equal(calls.find(c=>c[0]==='Stack'&&c[1]==='margin')[2].bottom,rows?2:0);
 assert.equal(calls.find(c=>c[0]==='Stack'&&c[1]==='clip')?.[2],true,'collapse cannot paint beyond wrapper');
}
console.log('PASS: pinned/music/live/action combinations and repeated collapse remove background, clamp empty height/gap to zero and preserve active rows.');
