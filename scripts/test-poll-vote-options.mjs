import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const root='entry/src/main/ets/';
const ctx=vm.createContext({Set,Number,Date,str:k=>k,pollVoteErrorText:x=>x,logE(){}});
const source=fs.readFileSync(root+'util/pollVoteOptions.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'');
vm.runInContext(ts.transpileModule(source.replace(/\bexport /g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const entities=[{offset:0,length:1,type:{'@type':'textEntityTypeBold'}}];
const options=Array.from({length:1000},(_,i)=>Object.freeze({text:`option ${i}`,entities,voterCount:i,votePercentage:20,isChosen:false,isBeingChosen:false}));
Object.freeze(options);
const ids=ctx.pollVoteIds([1,1,2,-1,1.5,NaN,Infinity,1000],1000);assert.deepEqual([...ids],[1,2]);
let checks=0;const selected={has:i=>{checks++;return i%2===0;}};
const pending=ctx.pollVoteOptions(options,selected,true);assert.equal(checks,1000);
assert.equal(pending[1],options[1]);assert.notEqual(pending[0],options[0]);assert.equal(pending[0].entities,entities);
checks=0;assert.equal(ctx.pollVoteOptions(pending,selected,true),pending);assert.equal(checks,1000);
const done=ctx.pollVoteOptions(pending,selected,false);assert.equal(done[0].entities,entities);assert.equal(done[0].isChosen,true);assert.equal(done[0].isBeingChosen,false);assert.equal(options[0].isChosen,false);
// Execute the repository's actual submission method with deterministic TD replies.
const store=fs.readFileSync(root+'store/MessageStore.ets','utf8');
const start=store.indexOf('  votePoll('),end=store.indexOf('\n  // Voice notes',start);
vm.runInContext(ts.transpileModule('class VoteHarness {\n'+store.slice(start,end)+'\n}\nglobalThis.VoteHarness=VoteHarness;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
function harness(){
 const jobs=[],outcomes=[];
 const h=Object.assign(Object.create(ctx.VoteHarness.prototype),{chatId:9,messages:[{id:7,contentType:'poll',pollQuestion:'Q',pollCloseDate:0,pollIsClosed:false,pollIsQuiz:false,pollAllowMultiple:false,pollVotePending:false,pollOptions:options.slice(0,1)}],
 indexOf(id){return this.messages.findIndex(m=>m.id===id);},patch(id,fn){const i=this.indexOf(id);if(i>=0){const m={...this.messages[i]};fn(m);this.messages[i]=m;}},
 client:{send:req=>new Promise((resolve,reject)=>jobs.push({req,resolve,reject}))}});
 return {h,jobs,outcomes,finish:(...args)=>outcomes.push(args)};
}
const success=harness();success.h.votePoll(7,[0],success.finish);assert.equal(success.jobs.length,1,'single-option server polls can vote');
assert.equal(success.h.messages[0].pollOptions[0].entities,entities);
success.h.votePoll(7,[0],success.finish);assert.equal(success.jobs.length,1,'pending double tap is ignored');
success.jobs[0].resolve({});await Promise.resolve();assert.equal(success.h.messages[0].pollOptions[0].entities,entities);assert.equal(success.h.messages[0].pollOptions[0].isChosen,true);
const failure=harness(),original=failure.h.messages[0].pollOptions;failure.h.votePoll(7,[0],failure.finish);
failure.jobs[0].reject({message:'network'});await Promise.resolve();await Promise.resolve();assert.equal(failure.h.messages[0].pollOptions,original);assert.equal(original[0].entities,entities);assert.equal(failure.h.messages[0].pollVotePending,false);
console.log('PASS: vote ID deduplication, exactly N membership checks, immutable sharing/no-op reuse, real single-option submit/double tap/success/failure preserve entities.');
