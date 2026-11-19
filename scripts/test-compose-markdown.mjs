import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const source=fs.readFileSync('entry/src/main/ets/util/composeMarkdown.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const ctx=vm.createContext({});vm.runInContext(ts.transpileModule(source+'\nglobalThis.api={composeFormattedText,hasComposeMarkdown,checkedComposeFormattedText,parseComposeMarkdown,markdownForEditing,remapComposeEntities};',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);const api=ctx.api;
const ft=(text,entities=[])=>({'@type':'formattedText',text,entities}),entity=(offset,length,type='textEntityTypeBold')=>({offset,length,type:{'@type':type}});
const calls=[];let response;
const client={send:async request=>{calls.push(request);return response??request.text;}};
for(const text of ['hello 😀','/help','2 * 3','a_b','https://example.test','single ~ literal']){const result=await api.parseComposeMarkdown(client,text);assert.equal(result.text,text);assert.equal(result.entities.length,0);}assert.equal(calls.length,0,'ordinary text requires no parse request');
const input='**bold** 🙂 @User',mentions=[{offset:12,length:5,type:{'@type':'textEntityTypeMentionName',user_id:42}}];response=ft('bold 🙂 @User',[entity(0,4),{offset:8,length:5,type:mentions[0].type}]);
assert.equal(await api.parseComposeMarkdown(client,input,mentions),response);assert.equal(calls.at(-1)['@type'],'parseMarkdown');assert.equal(calls.at(-1).text.entities,mentions,'native parser owns mention UTF-16 remapping');
for(const text of ['**unmatched','[broken]( link','`unclosed','\\**literal\\**','```ts\n**literal code**\n```','[link](https://a.test/a_(b))','~~s~~ ||spoiler||']){response=ft(text);const result=await api.parseComposeMarkdown(client,text);assert.equal(result.text,text,'helper never drops malformed/code/link raw characters or rewrites matching itself');}
const nativeEdit=ft('**bold** @User',[{offset:9,length:5,type:mentions[0].type}]);response=nativeEdit;assert.equal(await api.markdownForEditing(client,'bold @User',[entity(0,4),{offset:5,length:5,type:mentions[0].type}]),nativeEdit);assert.equal(calls.at(-1)['@type'],'getMarkdownText');assert.equal(nativeEdit.entities.length,1,'non-Markdown entity remains available to editor');
const count=calls.length;await api.markdownForEditing(client,'**literal**');assert.equal(calls.length,count);
for(const bad of [{'@type':'text',text:'x',entities:[]},ft('x',[entity(0,2)]),ft('😀',[entity(1,1)]),ft('x',[entity(0,0)]),ft('x',[entity(-1,1)]),{'@type':'formattedText',text:'x',entities:{}}]){response=bad;await assert.rejects(api.parseComposeMarkdown(client,'**x**'));}
response=undefined;await assert.rejects(api.parseComposeMarkdown({send:async()=>{throw new Error('native failure');}},'**raw draft**'),/native failure/);
const name=entity(2,2,'textEntityTypeMentionName');assert.deepEqual(JSON.parse(JSON.stringify(api.remapComposeEntities('x @A','++x @A',[name]))),[entity(4,2,'textEntityTypeMentionName')]);
assert.equal(api.remapComposeEntities('@Name','@Nxxame',[entity(0,5,'textEntityTypeMentionName')]).length,0);
assert.deepEqual(JSON.parse(JSON.stringify(api.remapComposeEntities('bold','boXXld',[entity(0,4)]))),[entity(0,6)]);
assert.equal(api.remapComposeEntities('bold','',[entity(0,4)]).length,0);
assert.equal(api.remapComposeEntities('A😀B','A😃B',[entity(1,2,'textEntityTypeCustomEmoji')]).length,0);
const stable=[entity(0,1)];assert.equal(api.remapComposeEntities('x','x',stable),stable);
let reads=0;const fake={length:20000,charAt(i){reads++;return i<this.length?'a':'';}};assert.equal(api.hasComposeMarkdown(fake),false);assert.ok(reads<=20000,'one character scan, no substring/indexOf-per-position');
assert.ok(calls.every(r=>r['@type']==='parseMarkdown'||r['@type']==='getMarkdownText'),'helper never sends or edits a real message');
console.log('PASS: native composer Markdown boundary, protected entities and UTF-16 validation, literal/malformed/code/link passthrough, edit entity retention, failure propagation, O(T+E) entity remapping and one-scan admission.');
