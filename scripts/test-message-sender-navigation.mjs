import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const calls=[],errors=[];
const ctx=vm.createContext({Number,
 navigateToProfile:p=>calls.push(['user',p.userId]),
 navigateToChatProfile:p=>calls.push(['group',p.chatId]),
 navigateToChat:(p,o)=>{calls.push(['chat',p.chatId,o]);return Promise.resolve();},
 logChatNavFailure:e=>errors.push(e.message)});
const source=fs.readFileSync('entry/src/main/ets/util/messageSenderNavigation.ets','utf8')
 .replace(/^import .*;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.open=openMessageSender;',
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
ctx.open(123,true,-100);assert.deepEqual(calls.pop(),['user',123]);
ctx.open(-100,false,-100);assert.deepEqual(calls.pop(),['group',-100]);
ctx.open(-200,false,-100);assert.deepEqual(calls.pop(),['chat',-200,'content']);
for(const id of [0,NaN,Infinity,1.5,Number.MAX_SAFE_INTEGER+1]){
 ctx.open(id,false,-100);ctx.open(id,true,-100);
}
ctx.open(-100,true,-100);ctx.open(123,false,-100);
assert.equal(calls.length,0,'invalid/hidden identities never become user profiles');
ctx.navigateToChat=()=>Promise.reject(new Error('navigation unavailable'));
ctx.open(-200,false,-100);await Promise.resolve();await Promise.resolve();
assert.deepEqual(errors,['navigation unavailable']);
// All four avatar surfaces preserve sender kind; long-press remains user-only.
for(const file of ['DrawnMessageRow','DrawnContentRow','LightweightPlainTextBubble','MessageBubbleShell']){
 const code=fs.readFileSync(`entry/src/main/ets/pages/chat/${file}.ets`,'utf8');
 assert.match(code,/onAvatarTap\((?:m|this\.msg)\.senderId, (?:m|this\.msg)\.senderIsUser\)/,file);
}
console.log('message sender navigation: PASS (anonymous group, channel, user, hidden identity, navigation rejection)');
