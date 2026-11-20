import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let currentClient={},nextId=0,offCount=0;const subscriptions=[],children=[],created=[],clicks=[];
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}observeComponentCreation2(fn){fn(++nextId,true);}ifElseBranchUpdateFunction(_i,fn){fn();}forEachUpdateFunction(_id,items,fn){items.forEach(fn);}static create(c){children.push(c);}}
class Child {constructor(_parent,params){this.params=params;}}
class Painter {bind(...args){this.args=args;return this;}}
const idle={pendingTaskIds:new Set(),error:''};let initial=idle;
const layout={width:250,height:128,title:{heightVp:20,widthVp:250},footerHeight:24,subtitleHeight:24,subtitle:{heightPx:12},rows:[{id:9,width:250,height:40,textX:36,textY:8,checkboxSize:20,checkboxY:8,checkboxHitWidth:36,label:{heightVp:20,widthVp:190}},{id:2,width:250,height:40,textX:36,textY:8,checkboxSize:20,checkboxY:8,checkboxHitWidth:36,label:{heightVp:20,widthVp:190}}]};
const ctx=vm.createContext({ViewV2:View,ViewPU:class{},DrawnPollText:Child,DrawnLoadingSpinner:Child,DrawnChecklistDecoration:Painter,DrawnCardBar:Painter,chatEnv:{appearanceEpoch:1,langEpoch:1},textMeasureEnvironment:{epoch:1},str:(k,...args)=>{if(k.startsWith('checklist_progress'))assert.ok(args.every(a=>typeof a==='string'),'%s requires string arguments');return [k,...args].join(':');},COLOR_PRIMARY:'accent',COLOR_TEXT_PRIMARY:'primary',COLOR_TEXT_SECONDARY:'secondary',Alignment:{TopStart:0},HorizontalAlign:{Start:0},AccessibilityRoleType:{BUTTON:1},IDLE_CHECKLIST_ACTION:idle,isReady:()=>currentClient!==undefined,getTdClient:()=>currentClient,checklistActionState:()=>initial,subscribeChecklistAction:(client,chatId,id,fn)=>{subscriptions.push({client,chatId,id,fn});return()=>offCount++;},checklistLayoutFor:()=>layout});
for(const name of ['Stack','Row','Column','If','ForEach','__Common__','Text','SymbolGlyph','Circle'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k.startsWith('create'))created.push(name);if(k==='onClick')clicks.push(args[0]);}});
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const s=fs.readFileSync(root+'pages/chat/DrawnChecklistMessage.ts','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(s+'\nglobalThis.Checklist=DrawnChecklistMessage;globalThis.TaskRow=DrawnChecklistTaskRow;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const task=id=>({id,text:`task ${id}`,entities:[],completed:false,content:{id,label:{text:`task ${id}`,entities:[]}}});
const model={title:{text:'Plan',entities:[]},tasks:[task(9),task(2)],canMarkTasksAsDone:true,completedCount:0};model.taskById=new Map(model.tasks.map(t=>[t.id,t]));
const toggles=[],links=[];let claims=0;
const actions={onChecklistToggle:(...args)=>toggles.push(args),onLinkTap:(...args)=>links.push(args)};
const c=new ctx.Checklist(null,{msg:{id:10,rowId:100,checklist:model},actions,widget:{},chatId:5,boxWidth:250,onClaim:()=>{claims++;return true;}});c.getUIContext=()=>({});
c.aboutToAppear();assert.equal(subscriptions.length,1);const first=subscriptions.at(-1);c.initialRender();let rows=children.filter(x=>x instanceof ctx.TaskRow);assert.equal(rows.length,2);assert.equal(rows[0].allowed,true);assert.equal(rows[0].task.id,9);
const row=rows[0];row.getUIContext=()=>({});created.length=0;children.length=0;clicks.length=0;row.initialRender();for(const n of ['Text','SymbolGlyph','Circle'])assert.equal(created.includes(n),false);assert.equal(clicks.length,1);
const old=clicks[0];old();assert.deepEqual(toggles.pop(),[10,9,true]);assert.equal(claims,1);const text=children.find(x=>x.params?.preparedLayout===layout.rows[0].label);assert.ok(text);assert.equal(text.params.onBeforeLink(),true);text.params.onLink('https://task.test',false);assert.deepEqual(links.pop(),['https://task.test',false]);assert.equal(toggles.length,0,'link does not toggle the task');
row.pending=true;old();assert.equal(toggles.length,0);row.pending=false;row.task={...row.task,completed:true};old();assert.equal(toggles.length,0,'old completion snapshot click ignored');row.toggleCallback()();assert.deepEqual(toggles.pop(),[10,9,false]);row.allowed=false;row.toggleCallback()();assert.equal(toggles.length,0);
first.fn({pendingTaskIds:new Set([9]),error:''});children.length=0;c.initialRender();rows=children.filter(x=>x instanceof ctx.TaskRow);assert.equal(rows[0].pending,true);assert.ok(rows.every(r=>!r.allowed),'single-flight locks other task buttons without changing geometry');assert.equal(c.layout,layout);
first.fn({pendingTaskIds:new Set(),error:'server rejected'});assert.equal(c.footerLabel(),'server rejected');assert.equal(c.layout.height,128);
c.msg={...c.msg,id:11,rowId:101};c.sourceChanged();const second=subscriptions.at(-1);const state=c.actionState;first.fn({pendingTaskIds:new Set([2]),error:'stale'});assert.equal(c.actionState,state);second.fn({pendingTaskIds:new Set(),error:'current'});assert.equal(c.footerLabel(),'current');
currentClient={};second.fn({pendingTaskIds:new Set(),error:'old account'});assert.equal(c.footerLabel(),'current');c.sourceChanged();assert.equal(subscriptions.at(-1).client,currentClient);const latest=subscriptions.at(-1);c.aboutToDisappear();const detached=c.actionState;latest.fn({pendingTaskIds:new Set([9]),error:'detached'});assert.equal(c.actionState,detached);assert.ok(offCount>=3);
console.log('PASS: compiled checklist prelaid Canvas task controls, distinct link/toggle targets, completion/pending guards, single-flight UI, fixed error footer, source/account/recycle callback isolation.');

currentClient=undefined;const beforeLogout=subscriptions.length;c.sourceChanged();assert.equal(c.actionState,idle);assert.equal(subscriptions.length,beforeLogout,'logout cannot register an undefined client');currentClient={};c.aboutToReuse();assert.equal(subscriptions.length,beforeLogout+1);c.aboutToRecycle();
const wrapperSource=fs.readFileSync(root+'pages/chat/ChecklistBubble.ts','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(wrapperSource+'\nglobalThis.Compat=ChecklistBubble;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const widget={width:250,height:128},prepares=[];const wrapper=Object.assign(Object.create(ctx.Compat.prototype),{msg:c.msg,actions,chatId:5,maxWidth:250,env:ctx.chatEnv,source:{prepare:(...args)=>{prepares.push(args);return{blocks:[{widget}]};}},onClaim:()=>true,getUIContext:()=>({})});children.length=0;wrapper.initialRender();const child=children.find(x=>x instanceof ctx.Checklist);assert.ok(child);assert.equal(child.widget,widget);assert.equal(child.chatId,5);assert.equal(child.onClaim(),true);assert.equal(prepares.at(-1)[1],null,'compatibility host never appends duplicated preview/body');
console.log('PASS: compatibility checklist host reuses the same widget/actions without another bubble shell, and logout/reuse subscriptions remain account-safe.');

assert.equal(typeof c.footerLabel(), 'string');

c.actionState=idle;c.error='';c.msg={id:11,rowId:101,isOutgoing:false,senderName:'deleted_account',checklist:{...model,othersCanMarkTasksAsDone:false}};
assert.equal(c.footerLabel(),'checklist_progress_by:0:2:deleted_account');
c.msg={...c.msg,isOutgoing:true};assert.equal(c.footerLabel(),'checklist_progress:0:2');
