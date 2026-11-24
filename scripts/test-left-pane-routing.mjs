// Execute production routing/controllers; no device or network navigation.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const read=p=>fs.readFileSync(root+p+'.ets','utf8');
const compile=s=>ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
const clean=s=>s.replace(/^import[\s\S]*?;\n/gm,'').replace(/^export /gm,'');
const storage=new Map(),queued=[],retaps=[],haptics=[];
const ctx=vm.createContext({AppStorage:{get:k=>storage.get(k),setOrCreate:(k,v)=>storage.set(k,v)},
 KEY_FORCE_SINGLE_COLUMN:'forceSingle',KEY_MAIN_TAB:'mainTabIndex',logW(){},logE(){},
 queuePendingNav:n=>queued.push(n),publishTabReTap:n=>retaps.push(n),
 physicalTabIndex:(i,contacts)=>contacts?i:(i===0?0:i-1),
 navigationHaptics:{play:k=>haptics.push(k)},KEY_ACTIVE_FORUM_OPEN:'forum',closeForumDrawer:()=>{},
 powerAnimationDuration:(_k,v)=>v,KEY_POWER_SMOOTH_TRANSITIONS:'animations',DOCK_SWITCH_DURATION:200,Curve:{EaseOut:0}});
for(const p of ['util/layoutBreakpoint','util/leftPaneState','util/splitRouting','util/navStacks','util/settingsNav']){
 vm.runInContext(compile(clean(read(p))),ctx);
}
vm.runInContext('Object.assign(globalThis,{navigateToSetting,navigateToSettingInChat,registerStack,showLeftPane,closeLeftPane,resetStacksForTest,splitLeftPaneEnabled});',ctx);
function extract(file,names){
 const ast=ts.createSourceFile('probe.ts',read(file).replace(/\bstruct /g,'class '),ts.ScriptTarget.Latest,true);
 const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===file.split('/').at(-1));
 return names.map(key=>{const m=cls.members.find(n=>n.name?.getText(ast)===key);assert.ok(m,key);return m.getText(ast);}).join('\n');
}
vm.runInContext(compile('class MainProbe {'+extract('pages/main/MainScreen',
 ['select','openDockPane','paneViewFor','dockSelected','railIndex','dockWidth','onShowContactsTabChanged'])+'}\nglobalThis.MainProbe=MainProbe;'),ctx);
vm.runInContext(compile('class ChatProbe {'+extract('pages/chatlist/ChatListPage',
 ['leftPaneActive','onSplitModeChanged','onLeftPaneChanged','selectFolder','openSettingsFromProfilePane'])+'}\nglobalThis.ChatProbe=ChatProbe;'),ctx);
function reset(split=true){storage.clear();storage.set('currentWidthBreakpoint',split?3:1);storage.set('currentHeightBreakpoint',split?0:2);
 storage.set('windowPortrait',!split);storage.set('mainTabIndex',0);queued.length=0;retaps.length=0;ctx.resetStacksForTest();}
function stack(names=[]){return {paths:names.map(name=>({name})),clears:0,replaces:0,
 clear(){this.clears++;this.paths=[];},pushPath(p){this.paths.push(p);},replacePath(p){this.replaces++;this.paths[this.paths.length-1]=p;},
 pop(){this.paths.pop();},size(){return this.paths.length;},getAllPathName(){return this.paths.map(p=>p.name);},getParamByIndex(i){return this.paths[i]?.param;}};}
function main(){const p=new ctx.MainProbe();Object.assign(p,{tab:0,showContactsTab:true,navBarWidth:450,folderRailInset:80,
 wallpaperSplit:()=>ctx.splitLeftPaneEnabled(),getUIContext:()=>({animateTo:(_o,fn)=>fn()})});
 Object.defineProperty(p,'leftPaneView',{get:()=>storage.get('leftPaneView')??'chats'});return p;}
reset();const right=stack(['ChatPage']);ctx.registerStack('chat',right);const p=main();
for(const [i,view] of [[1,'contacts'],[2,'settings'],[3,'profile'],[0,'chats']]){
 p.select(i);assert.equal(p.tab,0);assert.equal(p.leftPaneView,view);assert.equal(p.dockSelected(i),true);
 assert.deepEqual(right.getAllPathName(),['ChatPage']);assert.equal(p.dockWidth(),370);
}
p.tab=2;p.select(0);assert.equal(p.tab,0,'chat button restores a stranded main tab');
p.select(2);for(let i=0;i<1000;i++)p.select(2);assert.equal(right.paths.length,1);
ctx.navigateToSetting('PrivacySecurityPage');assert.deepEqual(right.getAllPathName(),['PrivacySecurityPage']);assert.equal(right.replaces,1);assert.equal(right.clears,0);
ctx.navigateToSetting('ActiveSessionsPage',undefined,'content');assert.deepEqual(right.getAllPathName(),['PrivacySecurityPage','ActiveSessionsPage']);
right.pop();assert.equal(right.paths[0].name,'PrivacySecurityPage');
ctx.navigateToSetting('AppearancePage');assert.deepEqual(right.getAllPathName(),['AppearancePage']);
const proxy={proxyServer:'a',proxyPort:443};ctx.navigateToSetting('ProxyPage',proxy);const replaces=right.replaces;
ctx.navigateToSetting('ProxyPage',proxy);assert.equal(right.replaces,replaces);
ctx.navigateToSetting('ProxyPage',{proxyServer:'b',proxyPort:443});assert.equal(right.replaces,replaces+1);
// Shrinking the window must not send nested right-page navigation to a hidden settings tab.
storage.set('forceSingle',true);ctx.navigateToSetting('ActiveSessionsPage',undefined,'content');assert.equal(storage.get('mainTabIndex'),0);assert.equal(right.paths.at(-1).name,'ActiveSessionsPage');
const chat=new ctx.ChatProbe();Object.assign(chat,{leftPaneView:'settings',archivePaneOpen:true,isSplitLayout:()=>false});chat.onSplitModeChanged();assert.equal(chat.leftPaneView,'chats');assert.equal(chat.archivePaneOpen,false);
reset(false);const standalone=stack();ctx.registerStack('settings',standalone);ctx.navigateToSetting('PrivacySecurityPage');assert.equal(storage.get('mainTabIndex'),2);assert.equal(standalone.paths[0].name,'PrivacySecurityPage');
const phone=main();phone.tab=0;phone.select(2);assert.equal(phone.tab,2);assert.equal(phone.leftPaneView,'chats');
assert.equal(ctx.showLeftPane('contacts'),false);
reset();ctx.navigateToSetting('ProxyPage',proxy);assert.equal(queued[0].tab,'chat');assert.deepEqual(queued[0].params.param,proxy);
// Replay owns the queued stack even if the layout changed before registration.
ctx.takePendingNavs=()=>queued.splice(0);ctx.navigateToChat=()=>Promise.resolve();ctx.navigateToSearch=()=>{};ctx.replayProfileNav=()=>{};ctx.SEARCH_DEST_NAME='Search';
vm.runInContext(compile(clean(read('util/pendingNavFlush'))+'\nglobalThis.flushPendingNavs=flushPendingNavs;'),ctx);
const cold=stack();ctx.registerStack('chat',cold);storage.set('forceSingle',true);ctx.flushPendingNavs('chat');assert.equal(cold.paths[0].name,'ProxyPage');assert.equal(queued.length,0);
reset();ctx.showLeftPane('contacts');const noContacts=main();noContacts.showContactsTab=false;noContacts.onShowContactsTabChanged();assert.equal(noContacts.leftPaneView,'chats');
ctx.showLeftPane('settings');Object.assign(chat,{controller:{changeIndex:i=>storage.set('folder',i)},selectedIndex:0,isSplitLayout:()=>true});chat.selectFolder(1);
assert.equal(storage.get('leftPaneView'),'chats');assert.equal(storage.get('folder'),1);
ctx.showLeftPane('profile');chat.openSettingsFromProfilePane();assert.equal(storage.get('leftPaneView'),'settings');assert.equal(storage.get('mainTabIndex'),0);
console.log('PASS: split/phone navigation, dock return/reselection/rail inset, right-content preservation, nested settings, proxy parameters, deferred replay, folder return and hidden contacts.');
// Replay the emitted left-column tree, including the Common visibility wrapper.
const compiled=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root+'pages/chatlist/ChatListPage.ts','utf8');
const ast=ts.createSourceFile('compiled.ts',compiled,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatListPage');
const body=cls.members.find(n=>n.name?.getText(ast)==='initialRender').body.statements;
const first=body.findIndex(n=>n.getText(ast).includes('Column.create('));
const last=body.findIndex(n=>n.getText(ast)==='HdsNavigation.pop();');assert.ok(first>=0&&last>first);
const uiNodes=[],uiStack=[];let railNode,paneNode,panelNode;
Object.assign(ctx,{Alignment:{TopStart:0},Visibility:{Visible:0,Hidden:1},FOLDER_RAIL_GAP:8,
 homeCardMarginVp:()=>14,homeCardBottomMarginVp:()=>14,ViewPU:{create(){}},
 HomeConversationPanel:class {constructor(){panelNode=uiStack.at(-1);}}});
for(const name of ['Column','Row','Stack','If','__Common__'])ctx[name]=new Proxy({}, {get:(_t,key)=>(...args)=>{
 if(key==='create'){const node={name,parent:uiStack.at(-1),props:{}};uiNodes.push(node);uiStack.push(node);return;}
 if(key==='pop'){assert.equal(uiStack.pop().name,name);return;}
 uiStack.at(-1).props[key]=args;
}});
vm.runInContext(compile('class PaneTree {render(){'+body.slice(first,last).map(n=>n.getText(ast)).join('\n')+'}} globalThis.PaneTree=PaneTree;'),ctx);
for(const shown of [false,true]){
 const tree=new ctx.PaneTree();Object.assign(tree,{topSafe:24,bottomSafe:20,widthBp:3,
 observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_i,fn)=>fn(),
 folderRailShown:()=>true,leftPaneActive:()=>shown,
 verticalFolderRail(){railNode={parent:uiStack.at(-1)};},leftPaneContent(){paneNode={parent:uiStack.at(-1)};}});
 uiNodes.length=0;uiStack.length=0;paneNode=null;tree.render();assert.equal(uiStack.length,0);
 for(let parent=railNode.parent;parent;parent=parent.parent){assert.notEqual(parent.props.visibility?.[0],1);assert.notEqual(parent.props.enabled?.[0],false);}
 assert.equal(panelNode.props.visibility[0],shown?1:0);
 if(shown){assert.equal(paneNode.parent.name,'If');assert.equal(paneNode.parent.parent.name,'Stack');assert.equal(paneNode.parent.parent.props.clip[0],true);assert.equal(paneNode.parent.parent.parent,railNode.parent.parent);}
}
console.log('PASS: compiled pane replacement hides only the conversation panel; folder rail stays visible/enabled outside the clipped content region.');
const settingsCompiled=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root+'pages/main/SettingsPage.ts','utf8');
const settingsAst=ts.createSourceFile('settings.ts',settingsCompiled,ts.ScriptTarget.Latest,true);
const settingsClass=settingsAst.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='SettingsPage');
const render=settingsClass.members.find(n=>n.name?.getText(settingsAst)==='initialRender');let paneBranch;
function findPaneBranch(n){if(ts.isIfStatement(n)&&n.expression.getText(settingsAst)==='this.paneMode')paneBranch=n.thenStatement;ts.forEachChild(n,findPaneBranch);}
findPaneBranch(render);assert.ok(paneBranch);
ctx.Scroll=new Proxy({}, {get:(_t,key)=>(...args)=>{
 if(key==='create'){uiStack.push({name:'Scroll',props:{}});return;}if(key==='pop'){assert.equal(uiStack.pop().name,'Scroll');return;}uiStack.at(-1).props[key]=args;
}});
Object.assign(ctx,{EdgeEffect:{Spring:0},BarState:{Off:0}});let titles=0,settingsBodies=0;
vm.runInContext(compile('class SettingsTree {render()'+paneBranch.getText(settingsAst)+'} globalThis.SettingsTree=SettingsTree;'),ctx);
const settingsTree=new ctx.SettingsTree();Object.assign(settingsTree,{observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_i,fn)=>fn(),topBar(){titles++;},settingsBody(){settingsBodies++;}});
uiStack.length=0;settingsTree.render();assert.equal(titles,1);assert.equal(settingsBodies,1);assert.equal(uiStack.length,0);
console.log('PASS: compiled settings pane retains its title/search builder and content within the existing outer safe-area bounds.');
