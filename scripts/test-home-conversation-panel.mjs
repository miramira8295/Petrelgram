// Execute the compiled shell/list builders: geometry, clipping and cache mode
// must agree. This replaces the obsolete collapsing-folder-bar lifecycle test.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const trees=new Map();
function source(name){
 if(!trees.has(name))trees.set(name,ts.createSourceFile(name,fs.readFileSync(root+'pages/'+(name==='GlobalSearchPage'?'search/':name==='ContactsPage'?'main/':'chatlist/')+name+'.ts','utf8'),ts.ScriptTarget.Latest,true));
 return trees.get(name);
}
function methods(name,names){
 const ast=source(name),cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===name);
 return names.map(key=>{const method=cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)===key);assert.ok(method,name+'.'+key);return method.getText(ast);}).join('\n');
}
let nodes=[],stack=[],lazyCalls=0;
const ctx=vm.createContext({
 CHAT_ROW_VERTICAL_GUTTER:4,ListItemAlign:{Center:0},CONTACT_LIST_CACHED_COUNT:4,
 Visibility:{Visible:0,Hidden:1},Alignment:{TopStart:0},Color:{Transparent:'transparent'},EdgeEffect:{Spring:0},BarState:{Off:0},
 GradientDirection:{Bottom:0},SafeAreaType:{SYSTEM:0},SafeAreaEdge:{BOTTOM:0},
 GLASS_OUTLINE_COLOR:'#4DFFFFFF',EDGE_OVERLAY_VP:95,
 surfaceGlassFill:()=> '#CCFFFFFF',homeCardMarginVp:bp=>bp===0?6:bp===1?10:14,
 edgeBlurRadiusOf:enabled=>enabled?30:0,
 edgeBlurStopsEx:()=>[],recallListPosition:()=>3,ViewStackProcessor:{AllocateNewElmetIdForNextComponent:()=>1,StartGetAccessRecordingFor(){},StopGetAccessRecording(){}},
 LazyForEach:{create(){lazyCalls++;},pop(){}},
});
const blurAst=ts.createSourceFile('scrollEdgeBlurModifier.ets',fs.readFileSync('entry/src/main/ets/util/scrollEdgeBlurModifier.ets','utf8'),ts.ScriptTarget.Latest,true);
vm.runInContext(ts.transpileModule(
 blurAst.statements.filter(n=>!ts.isImportDeclaration(n)).map(n=>n.getText(blurAst).replace(/^export /,'')).join('\n')
 +'\nglobalThis.ScrollEdgeBlurBinder=ScrollEdgeBlurBinder;globalThis.ScrollEdgeBlurModifier=ScrollEdgeBlurModifier;',
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
for(const name of ['Column','Stack','List','ListItem','If','Text'])ctx[name]=new Proxy({}, {get:(_target,key)=>(...args)=>{
 if(key==='create'){const node={name,parent:stack.at(-1),props:{},options:args[0],deep:name==='ListItem'?args[0]:undefined};nodes.push(node);stack.push(node);return;}
 if(key==='pop'){assert.equal(stack.pop().name,name);return;}
 const node=stack.at(-1);assert.equal(node?.name,name,key+' belongs to the current node');node.props[key]=args;
}});
function run(code){vm.runInContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
// Use the production setting resolution rather than a permanently enabled mock.
const edgeAst=ts.createSourceFile('edgeBlurSetting.ets',fs.readFileSync('entry/src/main/ets/util/edgeBlurSetting.ets','utf8'),ts.ScriptTarget.Latest,true);
run("const EDGE_BLUR_FORCE_ON='on', EDGE_BLUR_FORCE_OFF='off', EDGE_BLUR_FOLLOW='follow';\n"+
 ['normalizeEdgeBlurOverride','edgeBlurStateOn','edgeBlurPageTopOn','edgeBlurPageBottomOn','edgeBlurOtherBottomOn'].map(name=>
 edgeAst.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name.text===name).getText(edgeAst).replace(/^export /,'')).join('\n'));
function make(name,names){run(`class ${name}Probe {${methods(name,names)}} globalThis.${name}Probe=${name}Probe;`);const p=new ctx[name+'Probe']();p.observeComponentCreation2=fn=>fn(1,true);p.ifElseBranchUpdateFunction=(_n,fn)=>fn();p.observeComponentCreation=fn=>fn(1,true);return p;}
function reset(){nodes=[];stack=[];lazyCalls=0;}
const panel=make('HomeConversationPanel',['initialRender','panelFill']);
// Exercise the actual parent's compiled BuilderParam bindings with the child
// receiver. A direct page.panelHeader() call misses the search-entry crash.
const search=make('GlobalSearchPage',['panelHeader','panelContent']);
const searchAst=source('GlobalSearchPage');let searchParams;
function findSearchPanel(n){
 if(ts.isNewExpression(n)&&n.expression.getText(searchAst)==='HomeConversationPanel')searchParams=n.arguments[1];
 ts.forEachChild(n,findSearchPanel);
}
findSearchPanel(searchAst);assert.ok(searchParams);
run(`globalThis.searchPanelParams=function(){return ${searchParams.getText(searchAst)};};`);
ctx.SEARCH_PAGE_INSET=10;
const visits=[];
Object.assign(search,{query:'',searchBar(){assert.equal(this,search);visits.push('search');},
 searchCategoryTabs(recent){assert.equal(this,search);visits.push(recent?'recent':'results');},
 scopeControls(){assert.equal(this,search);visits.push('scope');},tabBody(){assert.equal(this,search);visits.push('body');}});
Object.assign(panel,ctx.searchPanelParams.call(search));
for(const query of ['', 'video']){
 reset();visits.length=0;search.query=query;
 panel.header();panel.content();
 assert.deepEqual(visits,query?['search','results','scope','body']:['search','recent','body']);
 assert.equal(stack.length,0);
}
panel.header=()=>{ctx.Text.create('folders');ctx.Text.pop();};
panel.content=()=>{ctx.List.create();ctx.List.pop();};
for(const glassOn of [false,true]){
 reset();Object.assign(panel,{glassOn,glassEpoch:4,dark:false});panel.initialRender();
 const shell=nodes.find(n=>n.props.id?.[0]==='homeConversationPanel');
 const viewport=nodes.find(n=>n.props.id?.[0]==='homeConversationViewport');
 assert.equal(nodes.find(n=>n.name==='Text').parent,shell,'folders share the surface but remain fixed');
 assert.equal(nodes.find(n=>n.name==='List').parent,viewport);
 assert.equal(viewport.props.layoutWeight[0],1);
 assert.equal(viewport.props.clip[0],true);
 assert.equal(shell.props.clip[0],true);
 assert.equal(nodes.filter(n=>n.props.backgroundColor).length,1,'one shared surface, including an empty list');
 assert.equal(shell.props.border[0].width,glassOn?.5:0);
 if(glassOn)assert.equal(shell.props.backgroundColor[0],'#CCFFFFFF');else assert.equal(shell.props.backgroundColor[0].type,10001);
 assert.equal(stack.length,0);
}
const main=make('MainTabBody',['chatList','initialRender','edgeBlurTopEnabled','edgeBlurBottomEnabled','edgeBlurRadius','cardGutter','archiveFill','archiveGlassOn','archiveExtent','listStartInset','listEndInset','archiveOffset','updateArchiveGesture','clearArchiveHint','finishArchivePull','refreshArchiveTop','onArchiveAvailabilityChanged','jumpToRow','scheduleArchiveInitialPosition']);
Object.assign(main,{edgeBlur:new ctx.ScrollEdgeBlurBinder(),archivePositionInitialized:true,archiveInitialChatIndex:3,archivePositionEpoch:0,archiveRowHeight:()=>62,chatCount:20,menuOpen:false,bottomSafe:20,contentTopInset:0,chatsData:{},archiveRowShown:()=>false,listViewH:500,edgeBlurOn:true,edgeBlurTopOn:true,edgeBlurBottomOn:true,edgeBlurListTop:'follow',edgeBlurListBottom:'follow'});
for(const continuousPanel of [true,false]){
 reset();main.continuousPanel=continuousPanel;main.initialRender();
 const list=nodes.find(n=>n.name==='List'),host=list.parent;
 assert.equal(lazyCalls,1,'exactly one lazy data source; no eager list rendering');
 assert.equal(list.props.cachedCount[0],2);assert.equal(list.props.cachedCount[1],!continuousPanel);
 assert.equal(list.props.clip[0],continuousPanel);assert.equal(list.props.contentStartOffset[0],continuousPanel?0:95);
 assert.equal(list.props.contentEndOffset[0],108,'dock remains reachable');
 assert.equal(host.props.offset[0].y,continuousPanel?0:-95);
 assert.equal(host.props.layoutWeight[0],continuousPanel?1:0);
 assert.equal(host.props.linearGradientBlur,undefined,'never attaches direct linearGradientBlur');
 assert.equal(host.props.attributeModifier[0].radius,30,'panel honors enabled edge blur');
 assert.equal(host.props.attributeModifier[0].active,true);
 host.props.onAreaChange[0]({}, {height:600});assert.equal(main.listViewH,600,'gradient uses actual viewport height');
 if(continuousPanel)assert.equal(main.archiveFill(false),'transparent');
 assert.equal(stack.length,0);
}
// Execute production callbacks, not a mirror of the gesture implementation.
const archiveSource=fs.readFileSync('entry/src/main/ets/util/archiveReveal.ets','utf8').replace(/export /g,'');
run(archiveSource+'\nglobalThis.ArchiveRevealGesture=ArchiveRevealGesture;');
let archiveNow=1000, archiveY=62, snap=null, remembered=-1, summaryReads=0, duration=250, timerId=0;
const timers=new Map(), jumps=[];
Object.assign(ctx,{
 Date:{now:()=>archiveNow},setTimeout:fn=>{timers.set(++timerId,fn);return timerId;},clearTimeout:id=>timers.delete(id),
 TouchType:{Down:0,Up:1,Cancel:2},ScrollState:{Idle:0,Scroll:1,Fling:2},
 ScrollSource:{DRAG:0,FLING:1,SCROLLER:6,SCROLLER_ANIMATION:7},ScrollAlign:{START:0},
 updateTouchHold(){},rememberListPosition:(_key,index)=>remembered=index,
 powerAnimationDuration:()=>duration,KEY_POWER_SMOOTH_TRANSITIONS:'smooth',
 curves:{cubicBezierCurve:()=> 'ease-out'},
 getChatStore:()=>({firstChat:()=>{summaryReads++;return {id:42};}}),
 smoothJumpStage:(_from,to)=>to>10?to-5:-1,RETAP_SMOOTH_SPAN:10
});
Object.assign(main,{continuousPanel:true,chatCount:20,archiveGesture:new ctx.ArchiveRevealGesture(),
 archiveHintTimer:-1,archiveSnapTarget:null,archiveRevealed:false,archivePulling:false,archiveReady:false,
 archiveRowShown:()=>true,updateScrollActivity(){},updateImmersiveBars(){},
 listScroller:{currentOffset:()=>({yOffset:archiveY}),scrollTo:opts=>snap=opts,scrollToIndex:(...args)=>jumps.push(args)}});
reset();main.chatList();
const archiveList=nodes.find(n=>n.name==='List');
const events=archiveList.props;
assert.equal(archiveList.options.initialIndex,4,'restore logical chat 3 after the resident archive');
assert.equal(nodes.filter(n=>n.name==='ListItem'&&n.parent===archiveList).length,1,'one resident header before lazy chat rows');
const touch=type=>events.onTouch[0]({type});
const scroll=y=>{archiveY=y;events.onDidScroll[0](0,ctx.ScrollState.Scroll);};
const will=(delta,source)=>events.onWillScroll[0](delta,ctx.ScrollState.Scroll,source).offsetRemain;
assert.equal(will(-20,ctx.ScrollSource.FLING),0,'fling cannot expose archive');
touch(ctx.TouchType.Down);
assert.equal(will(-20,ctx.ScrollSource.DRAG),-9,'finger pull uses Android friction');
scroll(40);assert.equal(timers.size,1);assert.equal(summaryReads,0,'no archive array/materialization on drag');
archiveNow=1250;scroll(5);assert.equal(main.archiveReady,true);
touch(ctx.TouchType.Up);assert.equal(snap.yOffset,0);assert.equal(snap.animation.duration,250);
assert.equal(main.archiveRevealed,true);assert.equal(summaryReads,1);assert.equal(timers.size,0);
assert.equal(will(-30,ctx.ScrollSource.FLING),0,'release fling cannot fight snap animation');
assert.equal(will(-5,ctx.ScrollSource.SCROLLER_ANIMATION),-5);
scroll(0);events.onScrollStop[0]();assert.equal(main.archiveGesture.settling,false);
scroll(10);assert.equal(main.archiveRevealed,true,'no old 8vp auto-collapse');
scroll(62);assert.equal(main.archiveRevealed,false);
assert.equal(will(-30,ctx.ScrollSource.FLING),0);
touch(ctx.TouchType.Down);archiveNow=1500;scroll(40);archiveNow=1800;scroll(5);
touch(ctx.TouchType.Cancel);assert.equal(snap.yOffset,62,'cancel hides even after threshold');
scroll(62);events.onScrollStop[0]();
// A shallow pull without smooth transitions snaps instantly and leaves no lock.
duration=0;touch(ctx.TouchType.Down);archiveNow=2000;scroll(40);touch(ctx.TouchType.Up);
assert.equal(snap.yOffset,62);assert.equal(snap.animation,false);assert.equal(main.archiveGesture.settling,false);
events.onScrollIndex[0](8);assert.equal(remembered,7);assert.equal(main.firstVisibleIndex,7);
main.jumpToRow(20);assert.deepEqual(jumps.map(x=>x[0]),[16,21],'all jumps use logical chat index + 1');
main.chatCount=1;main.listViewH=500;assert.equal(main.listEndInset(),438,'one chat can hide archive');
main.chatCount=0;assert.equal(main.listEndInset(),500);
main.continuousPanel=false;assert.equal(main.listEndInset(),405,'insets cannot exceed viewport');
// Archive removed while shown closes the same resident row; no data source reset.
main.continuousPanel=true;main.archiveRowShown=()=>false;main.archiveRevealed=true;
main.archiveGesture.revealed=true;archiveY=0;main.onArchiveAvailabilityChanged();
assert.equal(main.archiveRevealed,false);assert.equal(snap.yOffset,62);
main.chatCount=20;main.archiveRowShown=()=>false;
// First entry must hide archive without relying on a scroll event, for both
// synchronous data and the initial empty LazyForEach that clamped index to 0.
const frames=[];
ctx.OneShotFrameCallback=class {constructor(task){this.task=task;}onFrame(){this.task();}};
main.getUIContext=()=>({postDelayedFrameCallback:cb=>frames.push(cb)});
for(const count of [0,1,20]){
 Object.assign(main,{archivePositionInitialized:false,archivePositionScheduled:false,
  archiveInitialChatIndex:0,chatCount:count,listViewH:0,archivePositionEpoch:0});
 snap=null;main.scheduleArchiveInitialPosition();assert.equal(frames.length,0,'wait for real viewport');
 main.listViewH=500;main.scheduleArchiveInitialPosition();main.scheduleArchiveInitialPosition();
 assert.equal(frames.length,1,'coalesce data + size notifications');
 assert.equal(main.archivePositionInitialized,false);
 frames.shift().onFrame();
 if(count===0){
  assert.equal(snap.yOffset,62);assert.equal(snap.animation,false);
 }else{
  assert.deepEqual(jumps.at(-1),[1,false,ctx.ScrollAlign.START]);
 }
 assert.equal(main.archivePositionInitialized,true);
 main.scheduleArchiveInitialPosition();assert.equal(frames.length,0,'never repositions normal scrolling');
}
Object.assign(main,{archivePositionInitialized:false,archiveInitialChatIndex:7,chatCount:20});
main.scheduleArchiveInitialPosition();events.onScrollIndex[0](0);
assert.equal(main.archiveInitialChatIndex,7,'first native index callback cannot erase remembered target');
frames.shift().onFrame();assert.equal(jumps.at(-1)[0],8);
// Empty-first mount hides archive immediately, then restores saved position
// once data arrives. The empty viewport must not overwrite that position.
Object.assign(main,{archivePositionInitialized:false,archiveInitialChatIndex:7,chatCount:0});
main.scheduleArchiveInitialPosition();frames.shift().onFrame();assert.equal(snap.yOffset,62);
assert.equal(main.archiveInitialRestorePending,true);
main.scheduleArchiveInitialPosition();assert.equal(frames.length,0,'no empty-page polling');
main.chatCount=20;main.scheduleArchiveInitialPosition();frames.shift().onFrame();
assert.equal(jumps.at(-1)[0],8);assert.equal(main.archiveInitialRestorePending,false);
// A user gesture wins over a queued startup correction; no delayed snap-back.
main.archivePositionInitialized=false;main.scheduleArchiveInitialPosition();snap=null;
touch(ctx.TouchType.Down);frames.shift().onFrame();assert.equal(snap,null);
Object.assign(main,{archivePositionInitialized:true,chatCount:20});
// The production store lookup must access one ordered ID/Map entry, not build a snapshot.
const storeAst=ts.createSourceFile('ChatStore.ts',fs.readFileSync(root+'store/ChatStore.ts','utf8'),ts.ScriptTarget.Latest,true);
const storeClass=storeAst.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatStore');
const firstChatMethod=storeClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(storeAst)==='firstChat');
run(`class ArchiveStoreProbe {${firstChatMethod.getText(storeAst)}} globalThis.ArchiveStoreProbe=ArchiveStoreProbe;`);
const store=new ctx.ArchiveStoreProbe();
store.listIds=()=>[42,43];store.mirror=new Map([[42,{title:'first'}],[43,{title:'second'}]]);
assert.equal(store.firstChat('archive').title,'first');
store.listIds=()=>[];assert.equal(store.firstChat('archive'),null);
const row=make('ChatRow',['cardGutter','rowFill','rowGlassEnabled']);
for(const widthBp of [0,1,2]){
 Object.assign(row,{widthBp,continuousPanel:true});assert.equal(row.cardGutter(),0);assert.equal(row.rowFill(false),'transparent');assert.notEqual(row.rowFill(true),'transparent');
 row.continuousPanel=false;assert.equal(row.cardGutter(),[6,10,14][widthBp]);
}
// Folder/standalone-archive builder must use the same policy as the main list.
const folder=make('ChatListView',['initialRender','listBody','edgeBlurTopEnabled','edgeBlurBottomEnabled','edgeBlurRadius']);
Object.assign(folder,{edgeBlur:new ctx.ScrollEdgeBlurBinder(),chatsEmpty:false,listKey:'archive',loadFailed:false,chatsData:{},paging:false,pagingFailed:false,menuOpen:false,contentTopInset:0,listViewH:500,edgeBlurOn:true,edgeBlurTopOn:true,edgeBlurBottomOn:true,edgeBlurListTop:'follow',edgeBlurListBottom:'follow',endInset:()=>100});
for(const continuousPanel of [true,false]){
 reset();folder.continuousPanel=continuousPanel;folder.initialRender();const list=nodes.find(n=>n.name==='List');
 assert.equal(lazyCalls,1);assert.equal(list.props.cachedCount[1],!continuousPanel);
 assert.equal(list.props.clip[0],continuousPanel);assert.equal(list.props.contentStartOffset[0],continuousPanel?0:95);
 assert.equal(list.parent.props.margin[0].top,continuousPanel?0:-95);
 assert.equal(list.parent.props.linearGradientBlur,undefined);
 assert.equal(list.parent.props.attributeModifier[0].radius,30);
}
// Both home list implementations must honor toggles without swapping their list trees.
for(const probe of [main,folder])for(const continuousPanel of [true,false]){
 for(const master of [false,true])for(const globalTop of [false,true])for(const globalBottom of [false,true]){
  for(const top of ['on','off','follow'])for(const bottom of ['on','off','follow']){
   Object.assign(probe,{edgeBlur:new ctx.ScrollEdgeBlurBinder(),continuousPanel,edgeBlurOn:master,edgeBlurTopOn:globalTop,edgeBlurBottomOn:globalBottom,edgeBlurListTop:top,edgeBlurListBottom:bottom});
   const topEnabled=!continuousPanel&&master&&(top==='on'||top==='follow'&&globalTop);
   const bottomEnabled=master&&(bottom==='on'||bottom==='follow'&&globalBottom);
   reset();probe.initialRender();const list=nodes.find(n=>n.name==='List');
   const mod=list.parent.props.attributeModifier[0];
   assert.equal(mod.active,topEnabled||bottomEnabled);
   assert.equal(mod.radius,topEnabled||bottomEnabled?30:0);
   const calls=[];mod.applyNormalAttribute({linearGradientBlur:(...a)=>calls.push(a)});
   if(topEnabled||bottomEnabled){assert.equal(calls.length,1);assert.equal(calls[0][0],30);}
   else{assert.equal(calls.length,0,'disabled edge blur must never attach linearGradientBlur');}
   assert.equal(probe.edgeBlurTopEnabled(),topEnabled);assert.equal(probe.edgeBlurBottomEnabled(),bottomEnabled);
   assert.equal(lazyCalls,1);assert.equal(list.props.clip[0],continuousPanel);
  }
 }
}
// Switching tabs must no longer query possibly unbound controllers to collapse
// the folder bar. Width publication uses the outer pane, not the inset viewport.
const page=source('ChatListPage').text;
run(fs.readFileSync('entry/src/main/ets/util/splitMetrics.ets','utf8').replace(/\bexport /g,''));
const listPage=make('ChatListPage',['conversationPanelHeader','folderRailShown','navBarMinWidth','openArchive','onSplitModeChanged']);
ctx.HorizontalAlign={Start:0};
for(const split of [false,true])for(const width of [1119,1120,1297])for(const count of [0,2]){
 const headerParts=[];
 Object.assign(listPage,{isSplitLayout:()=>split,screenW:width,newSessionCount:0,folders:Array(count),
  titleBarActions:()=>headerParts.push('actions'),tabBar:()=>headerParts.push('folders')});
 reset();listPage.conversationPanelHeader();
 const rail=split&&width>=1120&&count>0;
 assert.equal(listPage.folderRailShown(),rail);
 if(rail)assert.ok(listPage.navBarMinWidth()>=400);
 assert.deepEqual(headerParts,['actions',...(count&&!rail?['folders']:[])]);
}
let archiveDestinations=0;
ctx.closeForumDrawer=()=>{};
ctx.navigateToArchive=()=>{archiveDestinations++;};
Object.assign(listPage,{isSplitLayout:()=>true,archivePaneOpen:false});
listPage.openArchive();
assert.equal(listPage.archivePaneOpen,true);
assert.equal(archiveDestinations,0,'opening the list must preserve the right-hand destination');
let archiveHeaders=0;
listPage.archivePaneHeader=()=>{archiveHeaders++;};
reset();listPage.conversationPanelHeader();
assert.equal(archiveHeaders,1);
listPage.isSplitLayout=()=>false;
listPage.onSplitModeChanged();
assert.equal(listPage.archivePaneOpen,false);
listPage.openArchive();
assert.equal(archiveDestinations,1,'single-column archive keeps its navigation destination');
assert.doesNotMatch(page,/noteFolderBarScroll|syncFolderBarWithActiveList|FolderChipAnchor/);
assert.doesNotMatch(page,/linearGradientBlur|homeTopBlurRadius|homeViewH/);
assert.match(page,/HomeConversationPanel/);assert.match(page,/hideTitleBar\(true, false\)/);
assert.match(page,/setOrCreate<number>\(NAV_BAR_WIDTH_KEY, paneWidth\)/);
assert.doesNotMatch(page,/setOrCreate<number>\(NAV_BAR_WIDTH_KEY, this.tabsWidth\)/);
assert.doesNotMatch(page,/NativeGlassHost|SystemGlassSurface|backgroundBlurStyle|backdropBlur/);
for(const name of ['MainTabBody','ChatListView'])assert.match(source(name).text,/continuousPanel: this.continuousPanel/,'row reuse receives the panel policy');
// Contacts uses the same fixed-header panel; search is never a scrolling row.
const contacts=make('ContactsPage',['contactsList']);
let contactBranch='';
for(const name of ['loadingCard','errorContactsCard','emptyContactsCard','listCard'])contacts[name]=()=>{contactBranch=name;};
Object.assign(contacts,{edgeBlur:new ctx.ScrollEdgeBlurBinder(),query:'',contacts:[],bottomSafe:20,contactsViewH:500,edgeBlurOn:true,edgeBlurBottomOn:true,edgeBlurOtherBottom:'follow'});
for(const [query,loading,loadError,expected] of [['',true,'','loadingCard'],['',false,'network','errorContactsCard'],['',false,'','emptyContactsCard'],['alice',false,'','listCard']]){
 reset();Object.assign(contacts,{query,loading,loadError,contextMenuShown:false});contacts.contactsList();
 for(const node of [...nodes])if(typeof node.deep==='function')node.deep(1,true);
 assert.equal(contactBranch,expected);const list=nodes.find(n=>n.name==='List');
 assert.equal(list.props.clip[0],true);assert.equal(list.props.cachedCount[0],4);assert.equal(list.props.cachedCount[1],false);
 assert.equal(list.props.contentStartOffset,undefined);assert.equal(list.props.contentEndOffset[0],108);
 assert.equal(list.props.enableScrollInteraction[0],true);
 assert.equal(list.props.attributeModifier[0].radius,30);assert.equal(stack.length,0);
}
reset();contacts.contextMenuShown=true;contacts.edgeBlurOn=false;contacts.contactsList();
assert.equal(nodes.find(n=>n.name==='List').props.enableScrollInteraction[0],false);
assert.equal(nodes.find(n=>n.name==='List').props.attributeModifier[0].active,false);
assert.equal(nodes.find(n=>n.name==='List').props.attributeModifier[0].reset,true,'turning off after enabled resets blur');
const contactsCode=source('ContactsPage').text;
assert.match(contactsCode,/HomeConversationPanel/);assert.match(contactsCode,/hideTitleBar\(true, false\)/);
assert.doesNotMatch(methods('ContactsPage',['contactsList']),/searchBox|setOrCreate/,'search is fixed; dock width is measured outside panel');
assert.doesNotMatch(methods('ContactsPage',['listCard']),/this.cardFill\(|Column.borderRadius|Column.border\(/,'contacts share the panel surface');
console.log('PASS: archive pull/release/cancel/fling/snap/logical-index callbacks and O(1) summary; compiled shared panel/fixed header/clipped viewport, lazy cache, no overlay in panel mode, live global/page edge-blur toggles, transparent contiguous rows, standalone archive preserved and no unbound folder-collapse reads.');
