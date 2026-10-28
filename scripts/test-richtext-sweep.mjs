// Differential parser validation and host-only timing against a supplied
// pre-change richText.ets. Timings do not predict device frame latency.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const baselinePath = process.argv[2];
assert.ok(baselinePath, 'Usage: node scripts/test-richtext-sweep.mjs path/to/richText-before.ets');
function load(source) {
  const ctx = vm.createContext({});
  const js = ts.transpileModule(source.replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, ''),
    {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
  vm.runInContext(js + '\nglobalThis.parse = parseFormattedText;', ctx);
  return ctx.parse;
}
const before = load(fs.readFileSync(baselinePath, 'utf8'));
const after = load(fs.readFileSync(new URL('../entry/src/main/ets/util/richText.ets', import.meta.url), 'utf8'));
let seed = 281026;
function random(n) { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; }
const kinds = ['Bold','Italic','Underline','Strikethrough','Code','Spoiler','CustomEmoji','TextUrl','Url','Mention','MentionName','Hashtag','Cashtag','BotCommand','EmailAddress','PhoneNumber','BankCardNumber','FallbackUrl','BlockQuote','ExpandableBlockQuote','Pre','PreCode','Unknown'];
const texts = ['abcdefghijklmnopqrstuvwxyz\n\n0123456789', 'https://example.com/path?q=😀', '😀😀\n caption\n\n', '@alice #话题 $USD /start', ' \n\nhead \n\nquote\n\nend\n ', '', '  ', '+86 (138)-0000 a@example.com'];
const plain = x => JSON.parse(JSON.stringify(x));
for (let i=0;i<10000;i++) {
  const text = texts[random(texts.length)];
  const entities = Array.from({length:random(40)},()=>({ offset:random(text.length+8)-4, length:random(text.length+8)-2,
    type:{'@type':'textEntityType'+kinds[random(kinds.length)], url:random(3)?'https://target.example/'+random(2):'', user_id:random(3)?123:0, custom_emoji_id:random(3)?'12':'', language:'ts'} }));
  assert.deepEqual(plain(after(text, entities)), plain(before(text, entities)), `differential case ${i}`);
  assert.equal(after(text, entities), after(text, entities));
}
const text = 'word '.repeat(400);
function fixture(n, overlap) {
  return Array.from({length:n},(_,i)=>({offset:overlap?i*3:i*14,length:overlap?text.length-i*6:10,
    type:{'@type':'textEntityType'+['Bold','Italic','TextUrl','Spoiler','CustomEmoji','Underline'][i%6], url:`https://example.com/${i}`, custom_emoji_id:String(i)}}));
}
const median = xs => xs.sort((a,b)=>a-b)[Math.floor(xs.length/2)];
const timings=[];
for (const n of [0,1,8,32,128]) for (const overlap of [false,true]) {
  if (n===0 && overlap) continue;
  const entities=fixture(n,overlap), iterations=Math.max(100,Math.floor(6000/(n+1)));
  assert.deepEqual(plain(after(text,entities)),plain(before(text,entities)));
  const old=[],next=[];
  for (let round=0;round<5;round++) for (const [parse,values] of (round%2?[[after,next],[before,old]]:[[before,old],[after,next]])) {
    const inputs=Array.from({length:iterations},()=>entities.slice());
    const start=performance.now();
    for (const input of inputs) parse(text,input);
    values.push((performance.now()-start)/iterations);
  }
  const oldMs=median(old),newMs=median(next);
  timings.push({entities:n,overlap,before_us:+(oldMs*1000).toFixed(2),after_us:+(newMs*1000).toFixed(2),speedup:+(oldMs/newMs).toFixed(2)});
}
console.log(JSON.stringify({differential_cases:10000,timings,scope:'Host uncached parse; not ArkUI/device frame measurements'},null,2));
