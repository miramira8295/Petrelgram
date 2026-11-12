// Actual compiled component: shared empty state, per-message interaction and reuse.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/MessageBubbleText.ts';
const source = fs.readFileSync(compiled, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '')
  .replace(/@(?:Param|Event|Local|Computed)\s*/g, '').replace(/@Monitor\([^)]*\)\s*/g, '').replace(/\bexport /g, '');
let computedResets = 0;
const ctx = vm.createContext({ ViewV2: class {
  initParam(k,v) { this[k]=v; } resetParam(k,v) { this[k]=v; }
  finalizeConstruction() {} resetMonitorsOnReuse() {}
  resetComputed(name) { assert.equal(name, 'drawnTextLayout'); computedResets++; }
}, ViewPU: class {}, chatEnv: {}, DrawnRichSourceCache: class {}, InlineCustomEmojiPaint: class {},
InlineEmojiColorFilters: class {}, InlineCaptionCache: class {} });
vm.runInContext(ts.transpileModule(source + '\nglobalThis.Probe = MessageBubbleText;',
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
function params(id, text = 'text') { return { context: {}, actions: {}, presentation: {
  input: { text }, msg: { rowId: id }, layout: {} } }; }
const a = new ctx.Probe(null, params(1)), b = new ctx.Probe(null, params(2));
a.aboutToAppear(); b.aboutToAppear();
const empty = a.revealedSpoilerKeys;
assert.equal(empty, a.expandedQuoteKeys); assert.equal(empty, b.revealedSpoilerKeys);
const spoiler = { offset: 0, text: 'secret' }, quote = { offset: 7, text: 'quote' };
a.revealSpoiler(spoiler); a.toggleQuote(quote);
assert.equal(a.spoilerRevealed(spoiler), true); assert.equal(a.quoteExpanded(quote), true);
assert.equal(b.revealedSpoilerKeys, empty); assert.equal(b.expandedQuoteKeys, empty);
assert.equal(empty.length, 0, 'one message cannot mutate another message/shared empty array');
const revealed = a.revealedSpoilerKeys, expanded = a.expandedQuoteKeys;
a.revealSpoiler(spoiler); assert.equal(a.revealedSpoilerKeys, revealed);
a.presentation = params(1).presentation; a.resetTextState();
assert.equal(a.revealedSpoilerKeys, revealed); assert.equal(a.expandedQuoteKeys, expanded);
a.toggleQuote(quote); assert.equal(a.quoteExpanded(quote), false);
a.toggleQuote(quote); assert.equal(a.quoteExpanded(quote), true);
a.presentation = params(1, 'edited').presentation; a.resetTextState();
assert.equal(a.revealedSpoilerKeys, empty); assert.equal(a.expandedQuoteKeys, empty);
a.revealSpoiler(spoiler); a.toggleQuote(quote);
a.presentation = params(3, 'edited').presentation; a.resetTextState();
assert.equal(a.revealedSpoilerKeys, empty); assert.equal(a.expandedQuoteKeys, empty);
a.revealSpoiler(spoiler); a.toggleQuote(quote);
a.resetStateVarsOnReuse(params(4)); a.aboutToReuse();
assert.equal(a.revealedSpoilerKeys, empty); assert.equal(a.expandedQuoteKeys, empty);
let writes = 0;
for (const key of ['revealedSpoilerKeys', 'expandedQuoteKeys']) {
  let value = a[key];
  Object.defineProperty(a, key, { get() { return value; }, set(next) { writes++; value = next; } });
}
a.presentation = params(5).presentation; a.resetTextState();
assert.equal(writes, 0, 'monitor does not assign already-empty interaction state');
const identities = new Set();
for (let i = 0; i < 1000; i++) {
  a.resetStateVarsOnReuse(params(i + 6)); a.aboutToReuse();
  identities.add(a.revealedSpoilerKeys); identities.add(a.expandedQuoteKeys);
}
assert.equal(identities.size, 1, '1000 reuse resets allocate no empty interaction arrays');
assert.equal(computedResets, 1001, 'paragraph computed reset remains intact');
console.log('PASS: isolated spoiler/quote interaction, unchanged-source preservation, edit/identity/reuse reset, 1000 resets reuse one empty array, paragraph invalidation retained.');
