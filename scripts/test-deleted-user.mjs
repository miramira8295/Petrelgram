import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
function load(ctx,file,names=[]){
 const s=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(ObservedV2|Trace)\s*/g,'');
 vm.runInContext(ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:file});
}
const str=(key,...args)=>args.length?`${key}(${args.join(',')})`:key;
const ctx=vm.createContext({str,logE:()=>{},logW:()=>{},showToast:()=>{},setTimeout,clearTimeout,
 photoHasAnimation:p=>p?.has_animation===true,botTopicFlagsOf:()=>({hasTopics:false,allowsUserTopics:false}),
 senderChannelKey:id=>String(id),invalidateSenderAnimation:()=>{},getTdClient:()=>client,
 TdError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
load(ctx,'util/deletedUser.ets',['isDeletedUser']);
load(ctx,'store/UserStore.ets',['UserStore']);
load(ctx,'store/ChatEntry.ets',['cloneEntry','computeInitials']);
load(ctx,'store/chatEntryFactory.ets',['compareChatEntries']);
load(ctx,'store/chatMirror.ets',['ChatMirror']);
load(ctx,'util/chatPermissions.ets',['allPermissions','permissionValue']);
load(ctx,'util/sendPermissions.ets',['firstDeniedPermission']);
load(ctx,'store/SendPermissionApi.ets',['readSendPermissions','requireSendPermissions']);
load(ctx,'util/membershipState.ets',['membershipLosesComposer']);
load(ctx,'pages/chat/MembershipSession.ets',['MembershipSession']);
load(ctx,'util/chatHeaderPresentation.ets',['chatHeaderPresentation']);
load(ctx,'pages/chat/HeaderIdentitySession.ets',['HeaderIdentitySession']);
const callbacks=new Map(),pending=[];
const client={onUpdate:(k,fn)=>{callbacks.set(k,fn);return()=>{};},send:request=>new Promise((resolve,reject)=>pending.push({request,resolve,reject}))};
const user=(deleted,id=7)=>({'@type':'user',id,first_name:'',last_name:'',type:{'@type':deleted?'userTypeDeleted':'userTypeRegular'},profile_photo:{small:{id:42},has_animation:true}});
assert.equal(ctx.isDeletedUser(undefined),false);assert.equal(ctx.isDeletedUser(user(false)),false,'empty name is not deletion');
const users=new ctx.UserStore(client);callbacks.get('updateUser')({user:user(true)});
assert.equal(users.displayName(7),'deleted_account');assert.equal(users.isDeleted(7),true);assert.equal(users.photoFileId(7),0);assert.equal(users.hasAnimatedPhoto(7),false);
// Exercise the actual ChatStore normalizer, with no constructor services.
const source=fs.readFileSync(root+'store/ChatStore.ets','utf8'),ast=ts.createSourceFile('ChatStore.ts',source,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatStore');
const field=cls.members.find(n=>n.name?.getText(ast)==='normalizePeer').getText(ast);
vm.runInContext(ts.transpileModule(`class Normalizer {${field}} globalThis.Normalizer=Normalizer;`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const normalizer=new ctx.Normalizer();normalizer.users=users;
const mirror=new ctx.ChatMirror();const entry={id:7,kind:'private',title:'',revision:0,photoFileId:42,avatarPath:'old',initials:'?',liveGroupCallId:0};
assert.equal(mirror.apply([entry],normalizer.normalizePeer).length,1);
assert.equal(mirror.get(7).title,'deleted_account');assert.equal(mirror.get(7).isDeletedUser,true);assert.equal(mirror.get(7).avatarPath,'');
const stable=mirror.get(7);for(let i=0;i<1000;i++)assert.equal(mirror.apply([entry],normalizer.normalizePeer).length,0);
assert.equal(mirror.get(7),stable,'delayed worker snapshots preserve identity and revision');
mirror.setAvatarPath(7,'late-old-photo');assert.equal(mirror.get(7).avatarPath,'');
callbacks.get('updateUser')({user:{...user(false),first_name:'Restored'}});mirror.apply([stable],normalizer.normalizePeer);
assert.equal(mirror.get(7).title,'Restored');assert.equal(mirror.get(7).isDeletedUser,false);
const header=new ctx.HeaderIdentitySession();header.host={chatId:()=>7,store:()=>null};header.state='error';header.avatarPath='old';
header.onUserUpdate({user:user(true)});assert.equal(header.titleTextOf(),'deleted_account');assert.equal(header.subtitleTextOf(),'user_status_long_ago');assert.equal(header.state,'ready');
header.applyTitle('late stale title');header.applyAvatar('late stale photo');assert.equal(header.titleTextOf(),'deleted_account');assert.equal(header.avatarPath,'');
header.host.chatId=()=>8;header.onUserUpdate({user:user(false,7)});assert.equal(header.deletedPeer,true,'other peer update ignored');
const port=async req=>req['@type']==='getChat'?{type:{'@type':'chatTypePrivate',user_id:7}}:user(true);
assert.equal((await ctx.readSendPermissions(port,7)).sendMessages,false);
await assert.rejects(()=>ctx.requireSendPermissions(port,7,['sendPhotos']));
assert.equal((await ctx.readSendPermissions(async req=>req['@type']==='getChat'?{type:{'@type':'chatTypePrivate',user_id:7}}:user(false),7)).sendMessages,true);
const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};
let id=7,state='',permissions,closed=0;
const host={chatId:()=>id,client:()=>client,isChannel:()=>false,setMembershipState:s=>state=s,setSendPermissions:p=>permissions=p,
 closeComposerSurfaces:()=>closed++,setIsGroup:()=>{},setIsChannel:()=>{},commitTimelineSnapshot:()=>{},setJoiningChat:()=>{}};
const membership=new ctx.MembershipSession();membership.bind(host);membership.refresh();pending.shift().resolve({type:{'@type':'chatTypePrivate',user_id:7}});await flush();
assert.equal(state,'checking');const old=pending.shift();assert.equal(old.request['@type'],'getUser');
membership.onUserUpdate({user:user(true)});assert.equal(state,'deletedUser');assert.equal(permissions.sendDocuments,false);assert.equal(closed,1);
old.resolve(user(false));await flush();assert.equal(state,'deletedUser','old getUser cannot restore a deleted peer');
membership.refresh();pending.shift().reject(new Error('offline'));await flush();assert.equal(state,'deletedUser','read failure cannot restore input');
id=8;membership.refresh();const late=pending.shift();membership.dispose();late.resolve({type:{'@type':'chatTypePrivate',user_id:8}});await flush();assert.equal(pending.length,0,'disposed request cannot spawn a new user read');
console.log('PASS: explicit deletion only, localized identity, removed avatars, 1000 delayed worker batches without churn, header guards, text/media send rejection, live deletion, stale user response/offline/dispose isolation.');
// The independent membership response can win the race with the header. The
// delete action must still use local chat deletion, never a group leave request.
const page=fs.readFileSync(root+'pages/chat/ChatPage.ets','utf8');
const method=page.slice(page.indexOf('  private confirmLeaveChat(): void {'),page.indexOf('  private openHeaderMenu(): void {'));
let dialog,deletedCalls=0,leaveCalls=0,backs=0;
Object.assign(ctx,{$r:k=>k,leaveOrDeleteChat:async(chat,kind,own,all)=>{assert.deepEqual([chat,kind,own,all],[7,'private',true,false]);deletedCalls++;return true;},leaveChatFully:async()=>{leaveCalls++;}});
vm.runInContext(ts.transpileModule(`class Page {${method}} globalThis.Page=Page;`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const pageController=new ctx.Page();Object.assign(pageController,{chatId:7,membershipState:'deletedUser',header:{deletedPeer:false,titleTextOf:()=>''},getUIContext:()=>({showAlertDialog:d=>dialog=d}),goBack:()=>backs++});
pageController.confirmLeaveChat();assert.equal(deletedCalls,0,'presenting the bar/dialog must not delete history');
dialog.secondaryButton.action();await flush();assert.equal(deletedCalls,1);assert.equal(leaveCalls,0);assert.equal(backs,1);
console.log('PASS: membership-before-header deletion routing, explicit confirmation, local-only delete request.');
