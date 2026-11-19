import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const ctx=vm.createContext({hasPendingMedia:items=>items.length>0,showToast(){},$r:k=>k,str:k=>k,closeContextMenu(){},replySnippetOf:()=>'',replyThumbOf:()=>'',replyThumbIsSticker:()=>false,setTimeout:()=>1,clearTimeout(){}});
function load(file,append=''){const s=fs.readFileSync(file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:ObservedV2|Trace)\s*/g,'');vm.runInContext(ts.transpileModule(s+append,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('entry/src/main/ets/util/composerMode.ets');ctx.clearReplyMode=ctx.clearReply;ctx.cancelEditMode=ctx.cancelEdit;
load('entry/src/main/ets/util/composeMarkdown.ets');load('entry/src/main/ets/pages/chat/ComposerSession.ets','\nglobalThis.Session=ComposerSession;');
const bold={offset:0,length:4,type:{'@type':'textEntityTypeBold'}},mention={offset:5,length:5,type:{'@type':'textEntityTypeMentionName',user_id:1}};
const jobs=[];let current={id:1,isOutgoing:true,contentType:'text',text:'bold @Name',textEntities:[bold,mention],editDate:1};let draft='previous draft';
const store={getMessages:()=>[current],prepareMarkdownEdit:()=>new Promise((resolve,reject)=>jobs.push({resolve,reject}))};let activeStore=store;
const host={headerTitle:()=>'',store:()=>activeStore,findMsg:id=>current?.id===id?current:null,pendingMedia:()=>[],draft:()=>draft,setDraft:value=>{draft=value;},closeReactionSheet(){},setEmojiPanel(){},closeReplyKeyboardSlot(){}};
const session=new ctx.Session();session.bind(host);session.startEdit(1);assert.equal(draft,'bold @Name');assert.equal(jobs.length,1);
jobs.shift().resolve({'@type':'formattedText',text:'**bold** @Name',entities:[{...mention,offset:9}]});await Promise.resolve();assert.equal(draft,'**bold** @Name');
let payload=session.editPayload(draft);assert.equal(payload.text,'bold @Name');assert.equal(payload.entities,current.textEntities);assert.equal(payload.parseMarkdown,false,'unchanged formatted edit retains exact original payload');
session.draftChanged('prefix **bold** @Name');draft='prefix **bold** @Name';payload=session.editPayload(draft);assert.equal(payload.parseMarkdown,true);assert.equal(payload.entities[0].offset,16);
session.cancelEdit();assert.equal(draft,'previous draft');assert.equal(session.editingId,0);
// Native result cannot overwrite a user edit, another message, a new store,
// remote edit, a cancellation, disposal, or another request for the same id.
for(const action of ['typed','switched','store','remote','cancel','dispose','same-id']){
 current={id:1,isOutgoing:true,contentType:'text',text:'bold @Name',textEntities:[bold,mention],editDate:1};activeStore=store;draft='base';session.reset();session.startEdit(1);const pending=jobs.shift();
 if(action==='typed'){draft='typed now';session.draftChanged(draft);}
 if(action==='switched'){current={...current,id:2};session.startEdit(2);}
 if(action==='store'){activeStore={...store};}
 if(action==='remote'){current={...current,editDate:2,text:'remote edit'};}
 if(action==='cancel')session.cancelEdit();if(action==='dispose')session.dispose();if(action==='same-id')session.startEdit(1);
 const before=draft;pending.resolve({'@type':'formattedText',text:'STALE',entities:[]});await Promise.resolve();assert.equal(draft,before,action);
 while(jobs.length){jobs.shift().reject(new Error('ignored'));}await Promise.resolve();
}
current={id:3,isOutgoing:true,contentType:'text',text:'**literal raw**',textEntities:[],editDate:0};draft='';session.reset();activeStore=store;session.startEdit(3);assert.equal(jobs.length,0);payload=session.editPayload(draft);assert.equal(payload.text,'**literal raw**');assert.equal(payload.parseMarkdown,false,'literal Markdown-looking no-op must not gain formatting');
current={id:4,isOutgoing:true,contentType:'photo',text:'bold',textEntities:[bold],editDate:0};session.startEdit(4);jobs.shift().resolve({'@type':'formattedText',text:'**bold**',entities:[]});await Promise.resolve();assert.equal(session.editingKind,'caption');assert.equal(session.editPayload(draft).parseMarkdown,false);
console.log('PASS: composer getMarkdownText roundtrip and remaining entity shifts, exact no-op/literal/caption edits, prior draft restore and async typed/switch/store/remote/cancel/dispose/same-id ownership guards.');
