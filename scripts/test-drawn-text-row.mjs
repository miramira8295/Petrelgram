// Production parser, caches, geometry and compiled host handlers; native font
// shaping is deterministic here, so these checks do not claim device timings.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'), ts=imported.default||imported;
const root='entry/src/main/ets/', compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
let parseCalls=0, bodyLayouts=0, lastReads=0, pathBuilds=0, totalLayouts=0, unitConversions=0;
class Paragraph {
  constructor(style,parts){this.style=style;this.parts=parts;this.content=parts.map(p=>p.text||'').join('');}
  layoutSync(max){
    totalLayouts++;if(this.style.wordBreak!==undefined)bodyLayouts++;
    this.max=max;this.boxes=[];this.lines=[];let x=0,y=0,start=0;
    const base=this.style.textStyle, h=base.fontSize*(base.heightScale||1.2);this.h=h;
    for(const p of this.parts) {
      if(p.width!==undefined){
        if(x+p.width>max){this.lines.push({left:0,width:x,baseline:y+h*.8,ascent:h*.8});x=0;y+=h;}
        this.boxes.push({placeholder:true,start,end:start+1,rect:{left:x,right:x+p.width,top:y+(h-p.height)/2,bottom:y+(h+p.height)/2}});
        start++;x+=p.width;continue;
      }
      for(const ch of p.text) {
        const w=p.style.fontSize*.5;
        if(ch==='\n'||x+w>max){this.lines.push({left:0,width:x,baseline:y+h*.8,ascent:h*.8});x=0;y+=h;if(ch==='\n'){start++;continue;}}
        this.boxes.push({start,end:start+ch.length,rect:{left:x,right:x+w,top:y,bottom:y+h}});start+=ch.length;x+=w;
      }
    }
    this.lines.push({left:0,width:x,baseline:y+h*.8,ascent:h*.8});this.height=y+h;
    if(this.style.maxLines===1){this.lines=this.lines.slice(0,1);this.height=h;}
  }
  getHeight(){return this.height;}getLongestLine(){return Math.max(...this.lines.map(l=>l.width));}
  getMaxIntrinsicWidth(){return this.parts.reduce((a,p)=>a+(p.width??p.text.length*p.style.fontSize*.5),0);}
  getLineCount(){return this.lines.length;}getLineMetrics(i){lastReads++;return this.lines[i];}
  getRectsForRange({start,end}){return this.boxes.filter(b=>b.start>=start&&b.end<=end).map(b=>({rect:b.rect}));}
  getRectsForPlaceholders(){return this.boxes.filter(b=>b.placeholder).map(b=>({rect:b.rect}));}
  updateColor(){} paint(){}
}
class ParagraphBuilder {
  constructor(style){this.style=style;this.stack=[style.textStyle];this.parts=[];}
  pushStyle(s){this.stack.push(s);}popStyle(){this.stack.pop();}
  addText(text){this.parts.push({text,style:this.stack.at(-1)});}addPlaceholder(p){this.parts.push(p);}
  build(){return new Paragraph(this.style,this.parts);}
}
const enumMock=new Proxy({},{get:(_t,k)=>k});
const ctx=vm.createContext({ViewV2:class{},ViewPU:class{},Color:{White:'white'},$r:x=>({resource:x}),
  ColorMetrics:{resourceColor:()=>({alpha:255,red:10,green:20,blue:30})},
  text:{ParagraphBuilder,FontCollection:{getGlobalInstance:()=>({})},FontWeight:enumMock,FontStyle:enumMock,
    TextDecorationType:enumMock,TextDirection:enumMock,TextAlign:enumMock,WordBreak:enumMock,
    PlaceholderAlignment:enumMock,TextBaseline:enumMock,RectWidthStyle:enumMock,RectHeightStyle:enumMock},
  drawing:{Path:class{buildFromSvgString(s){this.svg=s;pathBuilds++;return true;}},RoundRect:class{constructor(rect){this.rect=rect;}}},
  deviceInfo:{deviceType:'phone'},getUserStore:()=>({accentColorId:()=>-1}),getAccentColorStore:()=>({}),
  AVATAR_PALETTE:['red','blue'],COLOR_PRIMARY:'blue',COLOR_TEXT_SECONDARY:'gray',COLOR_BUBBLE_IN:'white',COLOR_BUBBLE_OUT:'green',
  accentSoft:()=> ({resource:'soft'}),bubbleTextFor:()=> 'black',formatClockTime:d=>`12:${String(d%60).padStart(2,'0')}`,str:x=>x,plural:(k,n)=>`${n} comments`,reactionKeyFrom:(e,id)=>id||e,slotKey:(id,i)=>`${id}:${i}`,
  SourceType:{TouchScreen:1,Mouse:2},TouchType:{Down:0,Up:1,Move:2,Cancel:3},
  firstFinger:list=>list[0],messageGesturePolicy:()=>({tapOpensMenu:true,longPressSelects:false,longPressOpensMenu:true}),
  tableScrollTouched:()=>false,isEdgeSwipeStart:x=>x<36,SWIPE_REPLY_MAX:-70,SWIPE_REPLY_TRIGGER:-40,SWIPE_SELECT_MAX:70,SWIPE_SELECT_TRIGGER:40,
  Curve:{EaseOut:1},Date:{now:()=>1000},messageDragType:()=> 'general.plain-text'});
function load(path,names=[]){const s=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:path});}
load(root+'util/drawnTextUnits.ets');
load(root+'pages/chat/DrawnMediaColors.ets');
for(const file of ['mediaBox','messageBubblePresentation','bubbleCornerInset','bubbleGlassPath','drawnPlainTextPolicy','drawnFooterPlacement','richText','messageLinkAction'])load(root+'util/'+file+'.ets');
vm.runInContext('globalThis.actualParser=parseFormattedText',ctx);ctx.countParse=(...a)=>{parseCalls++;return ctx.actualParser(...a);};
vm.runInContext('parseFormattedText=countParse',ctx);
for(const file of ['drawnSourcePool','drawnRichHitIndex','drawnRichTextPolicy','drawnAlbumPolicy','drawnTextRowPolicy','drawnContentPolicy','messageDragGesture'])load(root+'util/'+file+'.ets',[file==='messageDragGesture'?'MessageDragGesture':file==='drawnTextRowPolicy'?'drawnTextRowEligible':file==='drawnRichTextPolicy'?'DrawnRichSourceCache':'drawnTailGutter']);
for(const file of ['DrawnTextLine','DrawnRichTextLayout','DrawnSenderHeader','DrawnReplyQuote','DrawnReactionLayout','DrawnBubbleChrome','DrawnBubbleGeometry','DrawnBubblePlan','DrawnTextFooter','DrawnTextLayout'])load(root+'pages/chat/'+file+'.ets',file==='DrawnTextLayout'?['DrawnTextLayouts']:[]);
load(root+'util/drawnMediaSlot.ets',['DrawnMediaSlots']);
load(root+'util/drawnRouteMetrics.ets',['DrawnRouteReason','DrawnRouteTracker','drawnRouteMetrics']);
load(root+'util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load(root+'pages/chat/DrawnMediaFrames.ets',['DrawnMediaFrames']);
load(root+'pages/chat/DrawnNativeAttributes.ets',['DrawnMediaAnchorPool','DrawnCanvasAttributes']);
load(root+'pages/chat/DrawnLayoutWarmCache.ets',['takeDrawnWarmLayout']);
ctx.getTdClient ??= () => ctx; ctx.setTimeout ??= () => 0; ctx.clearTimeout ??= () => {};
load(root+'pages/chat/DrawnRecycledLayouts.ets',['DrawnLayoutRetention','takeDrawnRecycledLayout','drawnRecycledLayouts']);
load(compiled+'pages/chat/DrawnMessageRow.ts',['DrawnMessageRow']);
const ui={vp2px:n=>{unitConversions++;return n*2;},fp2px:n=>{unitConversions++;return n*2;}};
const data={playSlotKey:'',chatId:9,isGroup:false,isChannel:false,contentWidth:400,themeBubbleOut:'',selectionActive:false,selectedMemberIds:[],canReply:true,lightweightPlainText:true};
const style={radius:20,fontSize:16,environment:'1',textEnvironment:'1',role:'',views:''};
function group(content='hello',entities=[]){return{head:{id:10,rowId:10,contentType:'text',text:content,textEntities:entities,date:1,editDate:0,isOutgoing:false,senderId:5,senderName:'',senderInitials:'AB',senderIsUser:true,senderAvatarPath:'',senderTag:'',sendState:'sent',translatedText:'',reactions:[],inlineButtons:[],forwardFrom:'',commentCount:0,replyToMessageId:0,replySenderName:'',replyText:'',replyThumbPath:'',replyDiceLayers:[],linkUrl:'',linkTitle:'',linkSiteName:'',linkDescription:'',linkPhotoFileId:0},memberIds:[10],showAvatar:true,showSenderName:true,dateLabel:''};}
const layouts=new ctx.DrawnTextLayouts();let g=group(),p=layouts.prepare(ui,g,data,style);
assert.ok(ctx.drawnTextRowEligible(g,data,false,false));assert.equal(p.tiles.length,0);assert.equal(p.caption.source.content,'hello');
assert.ok(p.footerY<p.captionY+p.caption.heightVp,'short last line shares footer');
const initial={parseCalls,bodyLayouts,lastReads,pathBuilds,totalLayouts,unitConversions};
for(let i=0;i<1000;i++){g.head.sendState=i%2?'sent':'read';assert.equal(layouts.prepare(ui,g,data,style),p);}
assert.deepEqual({parseCalls,bodyLayouts,lastReads,pathBuilds,totalLayouts,unitConversions},initial,'1000 status changes must do no parsing, shaping, last-line query or outline allocation');
for(let i=0;i<100;i++){g.head.date=i;layouts.prepare(ui,g,data,{...style,views:String(i)});}
assert.equal(bodyLayouts,initial.bodyLayouts);assert.equal(parseCalls,initial.parseCalls);assert.equal(lastReads,initial.lastReads);
assert.equal(unitConversions,initial.unitConversions,'footer-only changes reuse native units as well as body paragraphs');
// Header/reply/footer changes reuse the body and its link rectangles.
g.head.senderName='Sender';g.head.replyToMessageId=33;g.head.replySenderName='Quoted';g.head.replyText='quote';
p=layouts.prepare(ui,g,{...data,isGroup:true},{...style,role:'admin'});const body=p.caption;
const warm={bodyLayouts,lastReads,totalLayouts,pathBuilds};
assert.equal(layouts.prepare(ui,g,{...data,isGroup:true},{...style,role:'admin'}),p);
assert.deepEqual({bodyLayouts,lastReads,totalLayouts,pathBuilds},warm,'resource objects must not defeat chrome/plan caches');
const q=layouts.prepare(ui,g,{...data,isGroup:true},{...style,role:'owner',views:'20'});assert.equal(q.caption,body);assert.equal(bodyLayouts,warm.bodyLayouts);
assert.equal(q.avatar.width,38);assert.ok(q.quoteRect.y+q.quoteRect.height<q.captionY);
let cases=0;
for(const width of [180,260,400,800])for(const font of [12,16,24])for(const count of [1,20,50,100,1000])for(const outgoing of [false,true]){
 const one=group('x'.repeat(count));one.head.isOutgoing=outgoing;
 const plan=new ctx.DrawnTextLayouts().prepare(ui,one,{...data,contentWidth:width},{...style,fontSize:font});
 const right=plan.captionX+(width-48), footerRight=plan.footerX+plan.footerWidth;
 assert.ok(plan.width>0&&plan.height>0);assert.ok(footerRight<=plan.width+0.01);
 assert.ok(plan.footerY+plan.footer.heightPx/plan.density<=plan.height);
 const last=plan.caption.paragraph.lines.at(-1),lastRight=plan.captionX+last.width/2;
 if(plan.footerY<plan.captionY+plan.caption.heightVp){assert.ok(plan.footerX>=lastRight+4-.01,'inline footer never overlaps body');}
 else assert.ok(plan.footerY>=plan.captionY+plan.caption.heightVp,'overflow footer gets own line');cases++;
}
// Actual parser support and multiple links survive the new route.
const links=group('https://one.test https://two.test');p=layouts.prepare(ui,links,data,style);assert.equal(p.caption.source.links.length,2);
const styled=group('bold link',[{offset:0,length:4,type:{'@type':'textEntityTypeBold'}},{offset:5,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://target.test'}}]);
p=layouts.prepare(ui,styled,{...data,lightweightPlainText:false},style);assert.ok(p.caption.source.runs[0].bold);assert.equal(p.caption.source.links[0].url,'https://target.test');
for(const kind of ['textEntityTypeSpoiler','textEntityTypeCode','textEntityTypePre','textEntityTypeBlockQuote']){
 const x=group('abc',[{offset:0,length:3,type:{'@type':kind,custom_emoji_id:'9'}}]);assert.equal(layouts.prepare(ui,x,data,style),null,kind);
}
for(const field of ['translatedText','linkUrl','linkTitle','linkSiteName','linkDescription']){const x=group();x.head[field]='x';assert.equal(ctx.drawnTextRowEligible(x,data,false,false),false,field);}
for(const field of ['inlineButtons','replyDiceLayers']){const x=group();x.head[field]=[{}];assert.equal(ctx.drawnTextRowEligible(x,data,false,false),true,field);}
const structured=group();structured.head.contentType='richMessage';assert.equal(ctx.drawnTextRowEligible(structured,data,false,false),false);
assert.equal(ctx.drawnTextRowEligible(group(),data,true,false),false);assert.equal(ctx.drawnTextRowEligible(group(),data,false,true),false);
// Replay real compiled link/reply/avatar/drag handlers, including reuse.
const events=[],row=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames(),nativeAnchors:new ctx.DrawnMediaAnchorPool(),canvasAttributes:new ctx.DrawnCanvasAttributes()});
row.kind='text';row.group=links;row.data=data;row.env={gestureScheme:0,screenWidthVp:400};row.dragGesture=new ctx.MessageDragGesture();
row.actions=new Proxy({},{get:(_t,k)=>(...args)=>events.push([k,...args])});row.foreground={press(){},pressReaction(){},setPress(){}};
row.getUIContext=()=>({animateTo:(_o,fn)=>fn()});p=layouts.prepare(ui,links,data,style);Object.defineProperty(row,'plan',{configurable:true,value:p});
const hit=p.caption.hits.find(h=>h.link.url==='https://two.test');const x=p.captionX+hit.x+.1,y=p.captionY+hit.y+.1;
const touch=(type,x,y)=>({type,touches:[{x,y,windowX:100,windowY:200}],changedTouches:[{x,y,windowX:100,windowY:200}]});
row.touch(touch(0,x,y));row.rowTouch(touch(0,x,y));row.click({x,y,source:1});assert.equal(events.at(-1)[1],'https://two.test');
row.group={...links,head:{...links.head,rowId:11}};const before=events.length;row.click({x,y,source:1});assert.equal(events.length,before);
row.group=links;row.touch(touch(0,x,y));row.rowTouch(touch(0,x,y));ctx.Date.now=()=>1600;row.swipe(-60);assert.equal(row.swipeX,undefined,'held text favors system drag');
row.touch(touch(1,x,y));assert.equal(row.menuShown,true,'held unmoved text opens menu on release');
row.claimed=false;row.menuShown=false;ctx.Date.now=()=>2000;row.touch(touch(0,x,y));row.rowTouch(touch(0,x,y));row.dragGesture.claim();row.draggingMessage=true;ctx.Date.now=()=>2600;row.touch(touch(1,x,y));assert.equal(row.menuShown,false,'claimed system drag never opens menu');

// Tiny-font avatar rows retain the native bottom-aligned layout.
const tiny=layouts.prepare(ui,group('x'),{...data,isGroup:true},{...style,fontSize:10});
assert.equal(tiny.height,38);assert.ok(tiny.bubbleY>0);assert.equal(tiny.avatar.y,0);
// Live sending and busy links retain the exact plan and cached paragraph.
const gate=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames(),nativeAnchors:new ctx.DrawnMediaAnchorPool(),canvasAttributes:new ctx.DrawnCanvasAttributes()});gate.kind='text';gate.group=links;gate.data=data;
gate.env={appearanceEpoch:1,langEpoch:1,bubbleMaterialOn:false,bubbleRadius:20,msgTextSize:16,linkNavBusy:''};
gate.a11y={active:false};gate.translation=null;gate.sendState='sent';gate.avatarAnimated=false;gate.role='';gate.views='';
gate.textLayouts=null;gate.albumLayouts=null;gate.getUIContext=()=>ui;
ctx.textMeasureEnvironment={epoch:0};ctx.drawnTextUsesRtlLayout=()=>false;ctx.logW=x=>{throw Error(x);};
const beforeSend=gate.plan;const beforeWork=layoutCounters();
for(let i=0;i<1000;i++){gate.sendState=i%2?'sending':'sent';assert.equal(gate.plan,beforeSend);}
assert.deepEqual(layoutCounters(),beforeWork);gate.sendState='sent';
const staticAvatarPlan=gate.plan;gate.avatarAnimated=true;assert.equal(gate.plan,staticAvatarPlan);gate.avatarAnimated=false;
gate.translation='pending';assert.equal(gate.plan,null);gate.translation=null;
gate.env.linkNavBusy='https://two.test';assert.equal(gate.plan,beforeSend);
assert.equal(gate.plan.caption.hitsByUrl.get('https://two.test').length,gate.plan.caption.hits.filter(h=>h.link.url==='https://two.test').length);gate.env.linkNavBusy='';assert.ok(gate.plan);
// Reply and avatar hit paths stay distinct from links and menu gestures.
row.group=g;row.data={...data,isGroup:true};p=layouts.prepare(ui,g,row.data,style);
Object.defineProperty(row,'plan',{configurable:true,value:p});row.claimed=false;row.draggingMessage=false;
row.click({x:p.quoteRect.x+1,y:p.quoteRect.y+1,source:2});assert.equal(events.at(-1)[0],'onReplyTap');
row.click({x:1,y:p.avatar.y+1,source:2});assert.equal(events.at(-1)[0],'onAvatarTap');
row.longPress({fingerList:[{localX:5,localY:p.avatar.y+4}],target:{area:{width:400}}});
assert.equal(events.at(-1)[0],'onAvatarLongPress');assert.equal(events.at(-1)[1],g.head.senderId);
row.claimed=false;row.data.selectionActive=true;const beforeSelect=events.length;
row.click({x:p.quoteRect.x+1,y:p.quoteRect.y+1,source:2});assert.equal(events.length,beforeSelect);
row.invokeLongPress(20);assert.equal(events.at(-1)[0],'onSelectMessages');row.data.selectionActive=false;
row.planCheck=true;

// Published native bindings remain safe when the plan disappears on reuse.
const callbacks=[],created=[];
for(const n of ['Stack','Row','Image','If','ForEach','Column','Text','SymbolGlyph'])ctx[n]=new Proxy({},{get:(_t,k)=>(...a)=>{if(k==='create')created.push(n);}});
for(const n of ['Alignment','HitTestMode','MenuPreviewMode','BlurStyle','ModalMode','HapticFeedbackMode'])ctx[n]=enumMock;
ctx.JUMP_FOCUS_SCALE=.01;ctx.JUMP_FOCUS_BRIGHTNESS=.01;ctx.menuPreviewCompact=()=>false;ctx.containerBlur=()=>0;ctx.overlayMaterial=()=>0;
row.observeComponentCreation2=fn=>{callbacks.push(fn);fn(1,true);};row.ifElseBranchUpdateFunction=(_id,fn)=>fn();row.forEachUpdateFunction=(_id,items,fn)=>items.forEach(fn);
row.painter={bind:()=>({})};row.foreground.bind=()=>({});row.menuFx={preview:()=>({}),menu:()=>({})};row.canvasContent();
assert.equal(created.filter(n=>n==='Stack').length,1);assert.equal(created.filter(n=>n==='Row').length,1);assert.equal(created.filter(n=>n==='Image'||n==='Text').length,0);
Object.defineProperty(row,'plan',{configurable:true,value:null});for(const fn of callbacks)fn(1,false);
const host=fs.readFileSync(compiled+'pages/chat/DrawnMessageRow.ts','utf8');assert.doesNotMatch(host,/new (MessageBubbleShell|LightweightPlainTextBubble)\(/);
const route=fs.readFileSync(compiled+'pages/chat/ReusableMessageBubble.ts','utf8');assert.doesNotMatch(route,/new LightweightPlainTextBubble\(/);assert.match(route,/new DrawnMessageRow\(/);assert.doesNotMatch(route,/new (TextMessageBubble|SingleMediaBubble|AlbumMessageBubble)\(/);
console.log(`PASS: ${cases} text geometries, 1000 status/100 footer updates reuse body, chrome cache, real rich parser/multiple links/fallback, compiled gestures/reuse and two-node text paint surface.`);

// Shared deterministic harness for the chrome integration regressions.
export { ctx, load, root, compiled, ui, data, style, group };
export function layoutCounters(){return {parseCalls,bodyLayouts,lastReads,pathBuilds,totalLayouts};}

const stablePlan=gate.plan;
for(const flag of ['drawnEnabled','drawnText','drawnPlain']){
 gate.env[flag]=false;assert.equal(gate.plan,null,flag);gate.env[flag]=true;assert.equal(gate.plan,stablePlan,flag);
}
console.log('PASS: runtime master/text/rich switches fall back and restore the cached row plan.');

gate.data={...gate.data,lightweightPlainText:false};const richPlan=gate.plan;
gate.env.drawnRich=false;assert.equal(gate.plan,null);gate.env.drawnRich=true;assert.equal(gate.plan,richPlan);

// Runtime body switches must reject cold rows before creating any layout owner,
// not merely return null after discarding a freshly built paragraph.
load(root+'util/drawnSingleMediaPolicy.ets',['drawnSingleMediaEligible']);
for(const kind of ['text','single','album'])for(const plain of [true,false]){
 const cold=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames(),nativeAnchors:new ctx.DrawnMediaAnchorPool(),canvasAttributes:new ctx.DrawnCanvasAttributes()}),message=group('body');
 if(kind!=='text')message.head.contentType='photo';
 if(kind==='album'){message.memberIds=[10,11];message.photoRatios=[1,1];message.caption='caption';}
 const flag=plain?'drawnPlain':'drawnRich',owner=kind==='text'?'textLayouts':kind==='single'?'singleLayouts':'albumLayouts';
 Object.assign(cold,{kind,group:message,data:{...data,lightweightPlainText:plain},env:{...gate.env,drawnPlain:true,drawnRich:true,[flag]:false},
  a11y:{active:false},translation:null,role:'',views:'',textLayouts:null,singleLayouts:null,albumLayouts:null,
  getUIContext:()=>{throw Error('disabled body must not request UIContext');}});
 assert.equal(cold.plan,null);assert.equal(cold[owner],null,`${kind}/${plain} disabled cold owner remains unallocated`);
 let preparations=0;const prepared={caption:{}};cold[owner]={prepare(){preparations++;return prepared;}};cold.getUIContext=()=>ui;
 cold.env[flag]=true;assert.equal(cold.plan,prepared);assert.equal(preparations,1);
 cold.env[flag]=false;for(let i=0;i<1000;i++)assert.equal(cold.plan,null);assert.equal(preparations,1);
 if(kind!=='text'){
  if(kind==='album')message.caption='';else message.head.text='';
  assert.equal(cold.plan,prepared,'empty media stays drawn when body rendering is disabled');assert.equal(preparations,2);
 }
}
console.log('PASS: plain/rich switches skip cold allocation and 1000 warm prepares for text/single/album; empty media stays eligible.');

// Home -> actual compiled row: transfer the production layout engine, then
// prepare current inputs. Matching body survives a new UIContext wrapper and
// message snapshot; edited text/width/font/config must invalidate it.
{
 const owner={};ctx.getTdClient=()=>owner;ctx.setTimeout=()=>1;ctx.clearTimeout=()=>{};
 const reserve=vm.runInContext('drawnLayoutWarmCache',ctx);
 const homeGroup=group('visit https://warm.test',[]),engine=new ctx.DrawnTextLayouts();
 const environment={...gate.env,drawnEnabled:true,drawnText:true,drawnPlain:true,drawnRich:true};
 const homeStyle={radius:environment.bubbleRadius,fontSize:environment.msgTextSize,
   environment:`${environment.appearanceEpoch}:${environment.langEpoch}:0`,textEnvironment:`${environment.langEpoch}:0`,role:'',views:''};
 const home=engine.prepare(ui,homeGroup,data,homeStyle),before=bodyLayouts;
 reserve.put(owner,data.chatId,homeGroup.head.id,'text',engine);
 const incoming={...homeGroup,head:{...homeGroup.head}};
 const recipient=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),
  kind:'text',group:incoming,data:{...data},env:environment,a11y:{active:false},translation:null,
  role:'',views:'',textLayouts:null,singleLayouts:null,albumLayouts:null,
  getUIContext:()=>({vp2px:n=>n*2,fp2px:n=>n*2})});
 const adopted=recipient.plan;
 assert.equal(recipient.textLayouts,engine);
 assert.equal(adopted.caption,home.caption);assert.equal(bodyLayouts,before,'matching warm body must not shape again');
 assert.equal(reserve.hasEntries(),false,'no second live row can claim the same engine');
 recipient.group={...incoming,head:{...incoming.head,text:'edited body'}};
 assert.notEqual(recipient.plan.caption,home.caption);assert.equal(bodyLayouts,before+1);
 recipient.data={...data,contentWidth:350};void recipient.plan;assert.equal(bodyLayouts,before+2);
 recipient.env={...environment,msgTextSize:18};void recipient.plan;assert.equal(bodyLayouts,before+3);
 recipient.env={...recipient.env,appearanceEpoch:2};void recipient.plan;assert.equal(bodyLayouts,before+4);
 console.log('PASS: home-prepared real rich paragraph transfers into compiled row without re-layout; message edits, width, font and theme invalidate correctly.');
}
