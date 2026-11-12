// Host checks for cache behavior and the native filter contract. Actual device
// decoding/theme rendering is deliberately not simulated as pixel validation.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
let resolutions = 0, filters = 0, numericReads = 0;
let color = { alpha: 255, red: 20, green: 30, blue: 40 };
const ctx = vm.createContext({ ColorMetrics: { resourceColor() { resolutions++; return color; } },
  ColorFilter: class { constructor(matrix) { this.matrix = matrix; } },
  drawing: { BlendMode: { SRC_IN: 5 }, ColorFilter: {
    createBlendModeColorFilter(value, mode) { filters++; return { value, mode }; }
  } } });
for (const file of ['util/inlineCustomEmojiPaint', 'pages/chat/InlineEmojiColorFilter']) {
  const source = fs.readFileSync(`entry/src/main/ets/${file}.ets`, 'utf8')
    .replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
const assets = vm.runInContext('new InlineCustomEmojiPaint()', ctx);
const colors = vm.runInContext('new InlineEmojiColorFilters()', ctx);
const watched = items => new Proxy(items, { get(target, key) {
  if (/^\d+$/.test(String(key))) numericReads++;
  return Reflect.get(target, key);
} });
const ids = watched(['video', 'photo', 'colored']), paths = watched(['/v', '/p', '/c']);
const flags = watched([true, true, false]);
assets.prepare(ids, paths, flags); const reads = numericReads;
const body = colors.get(true, 'body', 1), link = colors.get(true, 'link', 1);
const identity = colors.get(false, 'body', 1);
for (let i = 0; i < 1000; i++) {
  assets.prepare(ids, paths, flags);
  assert.equal(assets.source('photo'), 'file:///p');
  assert.equal(assets.needsRepainting('photo'), true);
  assert.equal(colors.get(true, 'body', 1), body);
  assert.equal(colors.get(true, 'link', 1), link);
  assert.equal(colors.get(false, 'body', 1), identity);
}
assert.equal(numericReads, reads, 'cache hits must not traverse source arrays');
assert.equal(filters, 2); assert.equal(resolutions, 2);
assert.equal(body.mode, 5, 'SRC_IN preserves template alpha rather than filling a solid rectangle');
assert.deepEqual(JSON.parse(JSON.stringify(body.value)), color);
assert.equal(identity.matrix[0], 1); assert.equal(identity.matrix[18], 1);
color = { alpha: 255, red: 240, green: 240, blue: 240 };
const dark = colors.get(true, 'body', 2);
assert.notEqual(dark, body); assert.equal(dark.value.red, 240);
assets.prepare(['other'], ['/new'], [false]);
assert.equal(assets.source('photo'), ''); assert.equal(assets.needsRepainting('other'), false);
// Read actual compiler output and require both text owners to pass the filter
// to ImageSpan; callback/binding behavior remains a device verification item.
for (const name of ['MessageBubbleText', 'SelectTextOverlay']) {
  const output = fs.readFileSync(`entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/${name}.ts`, 'utf8');
  assert.match(output, /ImageSpan\.colorFilter\(this\.inlineCustomEmojiFilter\(run\)\)/);
}
console.log('PASS: emoji lookup cache, bounded color cache, theme invalidation, alpha-preserving tint and both ImageSpan bindings.');
