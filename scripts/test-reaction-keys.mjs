// Execute the real helpers and the store toggle method, including paid-key boundaries.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';let hasCalls=0,addCalls=0;const sent=[];
class CountingSet extends Set{has(key){hasCalls++;return super.has(key);}add(key){addCalls++;return super.add(key);}}
const ctx=vm.createContext({Set:CountingSet,str:x=>x,logE(){}});
function run(src,names){src=src.replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(src+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
run(fs.readFileSync(root+'util/reactions.ets','utf8'),['reactionKeyFrom','parseReactionKey','reactionTypeOf','parseAvailableReactions']);
assert.equal(ctx.reactionKeyFrom('⭐','',true),'paid:stars');assert.equal(ctx.reactionKeyFrom('⭐',''),'⭐');assert.equal(ctx.reactionTypeOf('paid:stars')['@type'],'reactionTypePaid');assert.equal(ctx.reactionTypeOf('⭐')['@type'],'reactionTypeEmoji');
assert.equal(ctx.reactionTypeOf('ce:9007199254740999').custom_emoji_id,'9007199254740999');assert.equal(ctx.parseReactionKey('paid:stars').paid,true);
const standard=emoji=>({type:{'@type':'reactionTypeEmoji',emoji}}),custom=id=>({type:{'@type':'reactionTypeCustomEmoji',custom_emoji_id:id}});
vm.runInContext("Array.prototype.indexOf=function(){throw new Error('quadratic array membership');};",ctx);
const input={top_reactions:[standard('A'),custom('9007199254740999'),standard('B')],recent_reactions:[standard('B'),standard('C'),custom('4')],popular_reactions:[],allow_custom_emoji:true};
for(let i=0;i<20000;i++)input.popular_reactions.push(i%2?standard('D'):custom('4'));
input.popular_reactions.push({},standard(''),custom('0'),{type:{'@type':'reactionTypePaid'}});
const result=ctx.parseAvailableReactions(input);assert.deepEqual([...result.emojis],['A','B','C','D']);assert.deepEqual([...result.customEmojiIds],['9007199254740999','4']);assert.equal(result.allowCustomEmoji,true);assert.ok(hasCalls<=20010);assert.equal(addCalls,6,'only unique keys are inserted');
const source=ts.createSourceFile('MessageStore.ts',fs.readFileSync(root+'store/MessageStore.ets','utf8'),ts.ScriptTarget.Latest,true);let method;
function visit(node){if(ts.isMethodDeclaration(node)&&node.name.getText(source)==='setReaction')method=node.getText(source);ts.forEachChild(node,visit);}visit(source);assert.ok(method);
run(fs.readFileSync(root+'tdkit/TdTypes.ets','utf8'),['TdError']);
run(`class ToggleStore { ${method} }`,['ToggleStore']);const store=new ctx.ToggleStore();store.chatId=4;store.client={send:req=>{sent.push(req);return Promise.resolve({});}};
for(const selected of [false,true])await assert.rejects(store.setReaction(7,'paid:stars',selected),error=>error.message==='PAID_REACTION_REQUIRES_CONFIRMATION');assert.equal(sent.length,0,'paid key cannot enter ordinary add/remove network flow');
await store.setReaction(7,'⭐',false);await store.setReaction(7,'ce:9007199254740999',true);assert.equal(sent[0]['@type'],'addMessageReaction');assert.equal(sent[0].reaction_type.emoji,'⭐');assert.equal(sent[1]['@type'],'removeMessageReaction');assert.equal(sent[1].reaction_type.custom_emoji_id,'9007199254740999');
console.log('PASS: paid/ordinary-star separation, exact int64, ordered O(N) dedup for 20000 duplicates, real store paid guard with zero network requests.');
