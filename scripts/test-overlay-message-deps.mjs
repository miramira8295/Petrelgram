// Replay compiled UI branches. Native dependency scheduling still needs device
// validation; tests check where reactive reads occur, not a predicted frame gain.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/';
const read=name=>fs.readFileSync(root+name+'.ts','utf8');
function methods(name,names){const s=read(name),a=ts.createSourceFile(name,s,ts.ScriptTarget.Latest,true),c=a.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===name);return names.map(k=>c.members.find(n=>n.name?.getText(a)===k).getText(a).replace(/@Computed\s*/g,'' )).join('\n');}
const ui=new Proxy({}, {get:()=>()=>{}}),enumStub=new Proxy({}, {get:(_,k)=>k});
const created=[];const component=name=>class {constructor(_p,params){created.push({name,params});}};
const ctx=vm.createContext({Stack:ui,Column:ui,Alignment:enumStub,FlexAlign:enumStub,HitTestMode:enumStub,
  ViewPU:{create(){}},ViewV2:{create(){}},musicTrackKey:(a,b)=>`${a}:${b}`,
  MusicAddToSheet:component('music'),MusicCreateDialog:component('create'),ReactionSheet:component('reaction'),ForwardSheet:component('forward'),
  selectionHasRemovableForwardCaption:(messages,ids)=>messages.some(m=>ids.includes(m.id)&&m.caption),
});
const evalCode=s=>vm.runInContext(ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
evalCode(`class Audio {${methods('AudioFavoriteFlow',['track','initialRender','trackKey'])}} globalThis.Audio=Audio;`);
evalCode(`class Overlay {${methods('ChatOverlayHost',['initialRender','anyOpen','forwardHasRemovableCaption'])}} globalThis.Overlay=Overlay;`);
const init=o=>{o.observeComponentCreation2=cb=>cb(1,true);o.ifElseBranchUpdateFunction=(_,cb)=>cb();return o;};
ctx.If=ui;
let reads=0,visits=0;
let messages=Array.from({length:500},(_,i)=>({id:i+1,audioTitle:`t${i}`,audioPerformer:`a${i}`,caption:false}));
const timeline={get messages(){reads++;return new Proxy(messages,{get(t,k){if(/^\d+$/.test(String(k)))visits++;return t[k];}});}};
const audio=init(new ctx.Audio());Object.assign(audio,{targetMessageId:0,chatId:7,timeline,creating:false,collections:[],bottomSafe:0});
for(let i=0;i<1000;i++){audio.initialRender();assert.equal(audio.track,null);}
assert.equal(reads,0);assert.equal(visits,0);
audio.targetMessageId=500;const track=audio.track;
assert.equal(track.audioTitle,'t499');assert.equal(track.audioPerformer,'a499');assert.equal(reads,1);assert.equal(visits,500,'one lookup produces both labels');
messages=messages.map(m=>m.id===500?{...m,audioTitle:'edited',audioPerformer:'new artist'}:m);
assert.equal(audio.track.audioTitle,'edited');assert.equal(audio.track.audioPerformer,'new artist');
audio.targetMessageId=1;assert.equal(audio.track.id,1);
messages=messages.filter(m=>m.id!==1);assert.equal(audio.track,null);
audio.targetMessageId=0;reads=0;visits=0;assert.equal(audio.track,null);assert.equal(reads,0);
const overlay=init(new ctx.Overlay());
const state={showReactionSheet:false,showForwardSheet:false,showScheduledSheet:false,showPollSheet:false,showContactSheet:false,showVideoNoteRecorder:false,showPinnedListSheet:false,forwardMessageIds:[500]};
Object.assign(overlay,{timeline,overlayState:state,selection:{entries:()=>[]}});
for(let i=0;i<1000;i++)overlay.initialRender();assert.equal(reads,0);assert.equal(visits,0);
state.showReactionSheet=true;overlay.initialRender();assert.ok(reads>0);assert.equal(created.at(-1).name,'reaction');assert.equal(created.at(-1).params.messages[0],messages[0]);
messages=messages.slice(1);overlay.initialRender();assert.equal(created.at(-1).params.messages[0],messages[0]);
state.showReactionSheet=false;state.showForwardSheet=true;messages=[{id:500,caption:true}];overlay.initialRender();assert.equal(created.at(-1).params.canRemoveCaption,true);
messages=[{id:500,caption:false}];overlay.initialRender();assert.equal(created.at(-1).params.canRemoveCaption,false);
state.showForwardSheet=false;reads=0;overlay.initialRender();assert.equal(reads,0);
assert.match(read('AudioFavoriteFlow'),/@Computed\s+private get track/);
const page=read('ChatPage');
assert.ok(!page.includes('audioTitleOf(')&&!page.includes('audioPerformerOf('));
for(const name of ['AudioFavoriteFlow','ChatOverlayHost']){
 const at=page.indexOf(name+'(this,');assert.ok(at>=0);
 const params=page.slice(at,page.indexOf('}, undefined',at));
 assert.match(params,/timeline: this.timeline/);assert.ok(!params.includes('this.timeline.messages'));
}
console.log('PASS: 1000 closed audio/overlay renders read zero messages; one audio lookup returns both labels; target/edit/delete and open reaction/forward snapshots stay live; compiled parent passes stable timeline only.');
